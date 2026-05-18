#!/usr/bin/env node

import { spawn, spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

const appPort = Number(process.env.WARDWRIGHT_BROWSER_TEST_PORT || 8797);
const chromePort = Number(process.env.WARDWRIGHT_CHROME_DEBUG_PORT || 9237);
const appUrl = `http://127.0.0.1:${appPort}`;
const chromePath = process.env.CHROME_PATH || findChromePath();

const viewports = [
  { name: "mobile", width: 390, height: 844, mobile: true, scale: 3 },
  { name: "desktop", width: 1280, height: 900, mobile: false, scale: 1 }
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
  { stdio: ["ignore", "ignore", "pipe"] }
);

try {
  await waitForHttp(`${appUrl}/policies/tts-retry/diagram`, "Wardwright");
  await waitForHttp(`http://127.0.0.1:${chromePort}/json/version`, "webSocketDebuggerUrl");

  for (const viewport of viewports) {
    await runViewportSmoke(viewport);
  }
} finally {
  chrome.kill("SIGTERM");
  server.kill("SIGTERM");
  await rm(userDataDir, { recursive: true, force: true, maxRetries: 3, retryDelay: 100 }).catch(
    () => {}
  );
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

    await assertClickableControl(cdp, viewport.name, "Step");
    await clickControl(cdp, "Step", viewport);
    await waitForEval(
      cdp,
      `document.querySelector(".player_status span")?.textContent.includes("Step 1 of 5")`
    );

    await assertClickableControl(cdp, viewport.name, "Back");
    await clickControl(cdp, "Back", viewport);
    await waitForEval(
      cdp,
      `document.querySelector(".player_status span")?.textContent.includes("Ready: 5")`
    );

    await assertClickableControl(cdp, viewport.name, "Step");
    await clickControl(cdp, "Step", viewport);
    await waitForEval(
      cdp,
      `document.querySelector(".player_status span")?.textContent.includes("Step 1 of 5")`
    );

    await assertClickableControl(cdp, viewport.name, "Reset");
    await clickControl(cdp, "Reset", viewport);
    await waitForEval(
      cdp,
      `document.querySelector(".player_status span")?.textContent.includes("Ready: 5")`
    );

    await assertClickableControl(cdp, viewport.name, "Play");
    await clickControl(cdp, "Play", viewport);
    await waitForEval(
      cdp,
      `[...document.querySelectorAll(".simulation_player button")].some((button) => button.textContent.trim() === "Pause")`
    );

    console.log(`ok ${viewport.name} LiveView playback controls`);
  } finally {
    cdp.close();
  }
}

async function clickControl(cdp, label, viewport) {
  const point = await evaluate(cdp, controlPointExpression(label));
  if (!point || point.error) {
    throw new Error(point?.error || `Could not find ${label} control`);
  }

  if (viewport.mobile) {
    await cdp.send("Input.dispatchTouchEvent", {
      type: "touchStart",
      touchPoints: [{ x: point.x, y: point.y }]
    });
    await cdp.send("Input.dispatchTouchEvent", {
      type: "touchEnd",
      touchPoints: []
    });
  } else {
    await cdp.send("Input.dispatchMouseEvent", {
      type: "mouseMoved",
      x: point.x,
      y: point.y,
      button: "left"
    });
    await cdp.send("Input.dispatchMouseEvent", {
      type: "mousePressed",
      x: point.x,
      y: point.y,
      button: "left",
      clickCount: 1
    });
    await cdp.send("Input.dispatchMouseEvent", {
      type: "mouseReleased",
      x: point.x,
      y: point.y,
      button: "left",
      clickCount: 1
    });
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
    `document.querySelector(".player_status span")?.textContent || document.body?.innerText.slice(0, 200) || ""`
  );
  throw new Error(`Timed out waiting for browser condition: ${expression}\nLast status: ${status}`);
}

async function evaluate(cdp, expression) {
  const response = await cdp.send("Runtime.evaluate", {
    expression,
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
