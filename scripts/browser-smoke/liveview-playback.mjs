#!/usr/bin/env node

import { spawn, spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

const appPort = Number(process.env.WARDWRIGHT_BROWSER_TEST_PORT || randomPort(18_000, 27_999));
const chromePort = Number(process.env.WARDWRIGHT_CHROME_DEBUG_PORT || randomPort(28_000, 37_999));
const appUrl = `http://127.0.0.1:${appPort}`;
const chromePath = process.env.CHROME_PATH || findChromePath();
const serverStartTimeoutMs = Number(process.env.WARDWRIGHT_BROWSER_SERVER_TIMEOUT_MS || 120_000);

const viewports = [
  { name: "mobile", width: 390, height: 844, mobile: true, scale: 3 },
  { name: "desktop", width: 1280, height: 900, mobile: false, scale: 1 }
];

const overflowViewports = [
  { name: "narrow", width: 360, height: 780, mobile: true, scale: 3 },
  { name: "mobile", width: 390, height: 844, mobile: true, scale: 3 },
  { name: "tablet", width: 768, height: 900, mobile: false, scale: 1 },
  { name: "desktop", width: 1280, height: 900, mobile: false, scale: 1 }
];

const overflowPaths = [
  "/policies",
  "/admin",
  "/policies/tts-retry/diagram",
  "/policies/tts-retry/diagram?model=browser-smoke-model",
  "/policies/route-privacy/diagram",
  "/policies/tool-governance/diagram"
];

if (!chromePath) {
  const message =
    "Chrome or Chromium was not found. Set CHROME_PATH to run LiveView browser smoke tests.";

  if (process.env.WARDWRIGHT_BROWSER_REQUIRED === "1") {
    throw new Error(message);
  }

  console.log(`skip LiveView browser smoke tests: ${message}`);
  process.exit(0);
}

const serverCommand = mixCommand();
const server = spawn(serverCommand.command, [...serverCommand.args, "phx.server"], {
  cwd: "app",
  detached: true,
  env: {
    ...process.env,
    MIX_ENV: process.env.MIX_ENV || "dev",
    WARDWRIGHT_BIND: `0.0.0.0:${appPort}`
  },
  stdio: ["ignore", "pipe", "pipe"]
});

const serverLogs = [];
server.stdout.on("data", (chunk) => serverLogs.push(chunk.toString()));
server.stderr.on("data", (chunk) => serverLogs.push(chunk.toString()));

const userDataDir = await mkdtemp(join(tmpdir(), "wardwright-chrome-"));
const chrome = spawn(
  chromePath,
  [
    "--headless=new",
    "--disable-gpu",
    "--disable-dev-shm-usage",
    "--no-first-run",
    "--no-default-browser-check",
    "--no-sandbox",
    `--remote-debugging-port=${chromePort}`,
    `--user-data-dir=${userDataDir}`,
    "about:blank"
  ],
  { detached: true, stdio: ["ignore", "ignore", "pipe"] }
);

try {
  await waitForHttp(`${appUrl}/policies/tts-retry/diagram`, "Wardwright", serverStartTimeoutMs);
  await waitForHttp(`http://127.0.0.1:${chromePort}/json/version`, "webSocketDebuggerUrl");
  await seedRegisteredModelWorkbench();

  for (const viewport of viewports) {
    await runViewportSmoke(viewport);
  }

  await assertRegisteredModelWorkbench();

  for (const viewport of overflowViewports) {
    for (const path of overflowPaths) {
      await assertNoPageOverflow(viewport, path);
    }
  }
} finally {
  await stopProcessGroup(chrome);
  await stopProcessGroup(server);
  await rm(userDataDir, { recursive: true, force: true, maxRetries: 3, retryDelay: 100 }).catch(
    () => {}
  );
}

async function seedRegisteredModelWorkbench() {
  const response = await fetch(`${appUrl}/v1/policy-authoring/wardwright-models`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      model_id: "browser-smoke-model",
      version: "browser-smoke",
      description: "Browser smoke model for registered-model workbench coverage.",
      targets: [{ model: "local/browser-smoke", context_window: 8192 }],
      stream_rules: [
        {
          id: "browser-smoke-redact",
          pattern: "\\bmoo\\b",
          action: "rewrite_chunk",
          replacement: "[cow]"
        }
      ],
      auth: { unkeyed_model_access: "public" }
    })
  });

  if (!response.ok) {
    throw new Error(
      `Could not seed registered model workbench fixture: ${response.status} ${await response.text()}`
    );
  }
}

async function assertRegisteredModelWorkbench() {
  const target = await createChromeTarget();
  const cdp = await connectCdp(target.webSocketDebuggerUrl);

  try {
    await cdp.send("Page.enable");
    await cdp.send("Runtime.enable");
    await cdp.send("Emulation.setDeviceMetricsOverride", {
      width: 1280,
      height: 900,
      deviceScaleFactor: 1,
      mobile: false
    });

    await cdp.send("Page.navigate", {
      url: `${appUrl}/policies/tts-retry/diagram?model=browser-smoke-model`
    });
    await cdp.waitFor("Page.loadEventFired");
    await waitForEval(
      cdp,
      `document.body && document.body.innerText.includes("Registered model selected")`
    );
    await waitForEval(cdp, `!document.documentElement.classList.contains("phx-loading")`);
    await waitForEval(cdp, `document.body.textContent.includes("browser-smoke-redact")`);

    const result = await evaluate(
      cdp,
      `(() => {
        const text = document.body.innerText;
        const forbidden = [
          "Policy run map",
          "State and turn model",
          "Receipt Preview",
          "Selected Node",
          "Review Findings",
          "retry arbiter"
        ].filter((label) => text.includes(label));
        return {
          hasRuntime: text.includes("Runtime Visibility"),
          hasCache: text.includes("History Cache"),
          forbidden
        };
      })()`
    );

    if (!result.hasRuntime || !result.hasCache || result.forbidden.length > 0) {
      throw new Error(
        `registered model workbench rendered stale or missing panels: ${JSON.stringify(result)}`
      );
    }

    console.log("ok registered model workbench hides example simulation panels");
  } finally {
    cdp.close();
  }
}

async function assertNoPageOverflow(viewport, path) {
  const target = await createChromeTarget();
  const cdp = await connectCdp(target.webSocketDebuggerUrl);

  try {
    await cdp.send("Page.enable");
    await cdp.send("Runtime.enable");
    await cdp.send("Emulation.setDeviceMetricsOverride", {
      width: viewport.width,
      height: viewport.height,
      deviceScaleFactor: viewport.scale,
      mobile: viewport.mobile
    });

    await cdp.send("Page.navigate", { url: `${appUrl}${path}` });
    await cdp.waitFor("Page.loadEventFired");
    await waitForEval(cdp, `pageText(document.body).length > 20`);
    await waitForEval(cdp, `!document.documentElement.classList.contains("phx-loading")`);

    const result = await evaluate(
      cdp,
      `(() => {
        const clientWidth = document.documentElement.clientWidth;
        const scrollWidth = document.documentElement.scrollWidth;
        return { clientWidth, scrollWidth, overflow: scrollWidth - clientWidth };
      })()`
    );

    if (result.overflow > 1) {
      const widest = await evaluate(
        cdp,
        `(() => {
          const elements = [];
          const collect = (root) => {
            if (!root?.querySelectorAll) return;
            for (const element of root.querySelectorAll("*")) {
              elements.push(element);
              if (element.shadowRoot) collect(element.shadowRoot);
            }
          };
          collect(document);
          return elements.map((element) => {
            const rect = element.getBoundingClientRect();
            return {
              tag: element.tagName,
              className: String(element.className || ""),
              width: Math.round(rect.width),
              left: Math.round(rect.left),
              right: Math.round(rect.right),
              scrollWidth: element.scrollWidth
            };
          })
          .filter((entry) => entry.right > document.documentElement.clientWidth + 1 || entry.width > document.documentElement.clientWidth + 1)
          .sort((a, b) => b.right - a.right || b.width - a.width)
          .slice(0, 5);
        })()`
      );
      throw new Error(
        `${viewport.name} ${path}: page overflow ${result.overflow}px (` +
          `scrollWidth ${result.scrollWidth}, clientWidth ${result.clientWidth}); widest=${JSON.stringify(widest)}`
      );
    }

    console.log(`ok ${viewport.name} ${path} has no page overflow`);
  } finally {
    cdp.close();
  }
}

async function runViewportSmoke(viewport) {
  const target = await createChromeTarget();
  const cdp = await connectCdp(target.webSocketDebuggerUrl);

  try {
    await cdp.send("Page.enable");
    await cdp.send("Runtime.enable");
    await cdp.send("Emulation.setDeviceMetricsOverride", {
      width: viewport.width,
      height: viewport.height,
      deviceScaleFactor: viewport.scale,
      mobile: viewport.mobile
    });

    await cdp.send("Page.navigate", { url: `${appUrl}/policies/tts-retry/diagram` });
    await cdp.waitFor("Page.loadEventFired");
    await waitForEval(cdp, `document.body && document.body.innerText.includes("Playback")`);
    await waitForEval(cdp, `!document.documentElement.classList.contains("phx-loading")`);
    await waitForEval(cdp, `document.querySelector(".simulation_player button") !== null`);
    await waitForLiveView(cdp);

    await assertClickableControl(cdp, viewport.name, "Step");
    await clickControlAndWait(
      cdp,
      "Step",
      `document.querySelector(".player_status span")?.textContent.includes("Step 1 of 5")`
    );

    await assertClickableControl(cdp, viewport.name, "Back");
    await clickControlAndWait(
      cdp,
      "Back",
      `document.querySelector(".player_status span")?.textContent.includes("Ready: 5")`
    );

    await assertClickableControl(cdp, viewport.name, "Step");
    await clickControlAndWait(
      cdp,
      "Step",
      `document.querySelector(".player_status span")?.textContent.includes("Step 1 of 5")`
    );

    await assertClickableControl(cdp, viewport.name, "Reset");
    await clickControlAndWait(
      cdp,
      "Reset",
      `document.querySelector(".player_status span")?.textContent.includes("Ready: 5")`
    );

    await assertClickableControl(cdp, viewport.name, "Play");
    await clickControlAndWait(
      cdp,
      "Play",
      `[...document.querySelectorAll(".simulation_player button")].some((button) => button.textContent.trim() === "Pause")`
    );

    console.log(`ok ${viewport.name} LiveView playback controls`);
  } finally {
    cdp.close();
  }
}

async function clickControlAndWait(cdp, label, condition) {
  let lastError = null;

  for (let attempt = 0; attempt < 3; attempt += 1) {
    await clickControl(cdp, label);

    try {
      await waitForEval(cdp, condition, 2_000);
      return;
    } catch (error) {
      lastError = error;
      await waitForLiveView(cdp);
    }
  }

  throw lastError;
}

async function clickControl(cdp, label) {
  const result = await evaluate(
    cdp,
    `(() => {
      const button = [...document.querySelectorAll(".simulation_player button")]
        .find((candidate) => candidate.textContent.trim() === ${JSON.stringify(label)});
      if (!button) return { error: "missing ${label} control" };
      button.click();
      return { clicked: true };
    })()`
  );

  if (!result || result.error) {
    throw new Error(result?.error || `Could not click ${label} control`);
  }
}

async function assertClickableControl(cdp, viewportName, label) {
  const result = await evaluate(cdp, controlPointExpression(label));

  if (!result || result.error) {
    throw new Error(`${viewportName}: ${result?.error || `missing ${label} control`}`);
  }

  if (!result.clickable) {
    throw new Error(
      `${viewportName}: ${label} control is covered by ${result.coveringTag}.${result.coveringClass}`
    );
  }
}

async function waitForLiveView(cdp) {
  await waitForEval(
    cdp,
    `window.liveSocket && typeof window.liveSocket.isConnected === "function" && window.liveSocket.isConnected()`
  );
  await waitForEval(cdp, `document.querySelector("[data-phx-main]") !== null`);
}

function controlPointExpression(label) {
  return `(() => {
    const button = [...document.querySelectorAll(".simulation_player button")]
      .find((candidate) => candidate.textContent.trim() === ${JSON.stringify(label)});
    if (!button) return { error: "missing ${label} control" };
    button.scrollIntoView({ block: "center", inline: "center" });
    const rect = button.getBoundingClientRect();
    const x = rect.left + rect.width / 2;
    const y = rect.top + rect.height / 2;
    const covering = document.elementFromPoint(x, y);
    const clickable = covering === button || button.contains(covering);
    return {
      x,
      y,
      clickable,
      coveringTag: covering?.tagName || "none",
      coveringClass: covering?.className || ""
    };
  })()`;
}

async function waitForEval(cdp, expression, timeoutMs = 8_000) {
  const deadline = Date.now() + timeoutMs;

  while (Date.now() < deadline) {
    if (await evaluate(cdp, expression)) {
      return;
    }
    await delay(100);
  }

  const status = await evaluate(
    cdp,
    `document.querySelector(".player_status span")?.textContent || pageText(document.body).slice(0, 200) || ""`
  );
  throw new Error(`Timed out waiting for browser condition: ${expression}\nLast status: ${status}`);
}

async function evaluate(cdp, expression) {
  const response = await cdp.send("Runtime.evaluate", {
    expression: `(() => {
      const pageText = (node) => {
        if (!node) return "";
        let text = node.innerText || node.textContent || "";

        if (node.querySelectorAll) {
          for (const element of node.querySelectorAll("*")) {
            if (element.shadowRoot) {
              text += "\\n" + pageText(element.shadowRoot);
            }
          }
        }

        return text.trim();
      };

      return (${expression});
    })()`,
    returnByValue: true,
    awaitPromise: true
  });

  if (response.exceptionDetails) {
    throw new Error(response.exceptionDetails.text || "Runtime.evaluate failed");
  }

  return response.result?.value;
}

async function createChromeTarget() {
  const response = await fetch(`http://127.0.0.1:${chromePort}/json/new?about:blank`, {
    method: "PUT"
  });

  if (!response.ok) {
    throw new Error(`Could not create Chrome target: ${response.status}`);
  }

  return response.json();
}

async function connectCdp(url) {
  const socket = new WebSocket(url);
  const callbacks = new Map();
  let nextId = 1;

  await new Promise((resolve, reject) => {
    socket.addEventListener("open", resolve, { once: true });
    socket.addEventListener("error", reject, { once: true });
  });

  socket.addEventListener("message", (event) => {
    const message = JSON.parse(event.data);
    if (message.id && callbacks.has(message.id)) {
      const { resolve, reject } = callbacks.get(message.id);
      callbacks.delete(message.id);
      if (message.error) reject(new Error(message.error.message));
      else resolve(message.result || {});
    }
  });

  return {
    send(method, params = {}) {
      const id = nextId++;
      socket.send(JSON.stringify({ id, method, params }));
      return new Promise((resolve, reject) => callbacks.set(id, { resolve, reject }));
    },
    waitFor(method, timeoutMs = 8_000) {
      return new Promise((resolve, reject) => {
        const timeout = setTimeout(
          () => reject(new Error(`Timed out waiting for ${method}`)),
          timeoutMs
        );
        const listener = (event) => {
          const message = JSON.parse(event.data);
          if (message.method === method) {
            clearTimeout(timeout);
            socket.removeEventListener("message", listener);
            resolve(message.params || {});
          }
        };
        socket.addEventListener("message", listener);
      });
    },
    close() {
      socket.close();
    }
  };
}

async function waitForHttp(url, expectedText, timeoutMs = 20_000) {
  const deadline = Date.now() + timeoutMs;

  while (Date.now() < deadline) {
    try {
      const response = await fetch(url);
      const text = await response.text();
      if (response.ok && text.includes(expectedText)) return;
    } catch {
      // Keep waiting until the server or browser is ready.
    }
    await delay(250);
  }

  throw new Error(`Timed out waiting for ${url}\n${serverLogs.slice(-20).join("")}`);
}

function findChromePath() {
  const candidates = [
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
    "/usr/bin/google-chrome",
    "/usr/bin/google-chrome-stable",
    "/usr/bin/chromium",
    "/usr/bin/chromium-browser"
  ];

  return candidates.find((path) => existsSync(path));
}

function mixCommand() {
  if (process.env.WARDWRIGHT_MIX_COMMAND) {
    const [command, ...args] = process.env.WARDWRIGHT_MIX_COMMAND.split(/\s+/);
    return { command, args };
  }

  if (spawnSync("mix", ["--version"], { stdio: "ignore" }).status === 0) {
    return { command: "mix", args: [] };
  }

  if (spawnSync("mise", ["--version"], { stdio: "ignore" }).status === 0) {
    return { command: "mise", args: ["exec", "--", "mix"] };
  }

  throw new Error("Could not find mix. Install Elixir or run through mise.");
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function randomPort(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

async function stopProcessGroup(child) {
  if (!child.pid || child.exitCode !== null || child.signalCode !== null) {
    return;
  }

  try {
    process.kill(-child.pid, "SIGTERM");
  } catch {
    try {
      child.kill("SIGTERM");
    } catch {
      return;
    }
  }

  if (await waitForExit(child, 2_000)) {
    return;
  }

  try {
    process.kill(-child.pid, "SIGKILL");
  } catch {
    try {
      child.kill("SIGKILL");
    } catch {
      // Process already exited.
    }
  }

  await waitForExit(child, 1_000);
}

function waitForExit(child, timeoutMs) {
  return new Promise((resolve) => {
    if (child.exitCode !== null || child.signalCode !== null) {
      resolve(true);
      return;
    }

    const timeout = setTimeout(() => {
      child.off("exit", onExit);
      resolve(false);
    }, timeoutMs);

    function onExit() {
      clearTimeout(timeout);
      resolve(true);
    }

    child.once("exit", onExit);
  });
}
