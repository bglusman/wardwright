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
  "/admin",
  "/admin?model=browser-smoke-model",
  "/admin?view=model_access",
  "/admin?view=model_access&model=browser-smoke-tools",
  "/admin?view=control_debugger"
];

if (!chromePath) {
  const message =
    "Chrome or Chromium was not found. Set CHROME_PATH to run browser smoke tests.";

  if (process.env.WARDWRIGHT_BROWSER_REQUIRED === "1") {
    throw new Error(message);
  }

  console.log(`skip browser smoke tests: ${message}`);
  process.exit(0);
}

const serverCommand = mixCommand();
const server = spawn(serverCommand.command, [...serverCommand.args, "phx.server"], {
  cwd: "app",
  detached: true,
  env: {
    ...process.env,
    MIX_ENV: process.env.MIX_ENV || "dev",
    WARDWRIGHT_BROWSER_ADAPTER_STATUS_FIXTURE: "1",
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
  await waitForHttp(`${appUrl}/admin`, "Wardwright", serverStartTimeoutMs);
  await waitForHttp(`http://127.0.0.1:${chromePort}/json/version`, "webSocketDebuggerUrl");
  await seedRegisteredModelWorkbench();
  await seedServerToolModelAccess();

  for (const viewport of viewports) {
    await runViewportSmoke(viewport);
  }

  await assertSelectedModelWorkbench();
  await assertServerToolModelAccess();
  await assertControlDebuggerSaveScenario();
  await assertAdapterStatusPanel();

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
          regex: "\\bmoo\\b",
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

async function seedServerToolModelAccess() {
  const response = await fetch(`${appUrl}/v1/policy-authoring/wardwright-models`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      artifact: {
        model_id: "browser-smoke-tools",
        version: "browser-smoke",
        description: "Browser smoke model with Wardwright-hosted server tools.",
        targets: [
          {
            model: "openai/browser-smoke-tools",
            context_window: 8192,
            provider_kind: "openai-compatible",
            provider_base_url: "https://example.com/v1"
          },
          { model: "local/browser-smoke-toolless", context_window: 4096 }
        ],
        dispatchers: [
          {
            id: "dispatcher.browser-smoke-tools",
            models: ["openai/browser-smoke-tools", "local/browser-smoke-toolless"]
          }
        ],
        route_root: "dispatcher.browser-smoke-tools",
        server_tools: [
          { name: "wardwright_policy_cache_status" },
          {
            name: "browser_smoke_dune_tool",
            source: `%{"visible" => input["value"]}`,
            input: { tenant: "browser-smoke" },
            limits: { timeout_ms: 500, max_reductions: 10000, max_heap_size: 1000000 },
            parameters: {
              type: "object",
              additionalProperties: false,
              properties: {
                value: { type: "string" }
              }
            }
          },
          {
            enabled: false,
            name: "browser_smoke_disabled_tool",
            source: `%{"disabled" => true}`
          }
        ],
        tool_mediation: {
          mode: "patch",
          rules: [
            { id: "browser-smoke-search", action: "augment", match: { name: "search" } }
          ]
        },
        auth: { unkeyed_model_access: "public" }
      }
    })
  });

  if (!response.ok) {
    throw new Error(
      `Could not seed server-tool model access fixture: ${response.status} ${await response.text()}`
    );
  }
}

async function assertAdapterStatusPanel() {
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

    await cdp.send("Page.navigate", { url: `${appUrl}/admin?view=control_debugger` });
    await cdp.waitFor("Page.loadEventFired");
    await waitForEval(cdp, `pageText(document.body).includes("Adapter install status")`);
    await waitForEval(cdp, `pageText(document.body).includes("verified_with_probe")`);

    const result = await evaluate(
      cdp,
      `(() => {
        const states = [
          "installable",
          "verified",
          "verified_with_probe",
          "drifted"
        ];
        const rows = states.map((state) => {
          const className = "adapter-state-" + state.replaceAll("_", "-");
          const row = allElements("*").find((element) =>
            String(element.className || "").split(/\\s+/).includes(className)
          );
          return {
            state,
            present: Boolean(row),
            borderLeftColor: row ? getComputedStyle(row).borderLeftColor : ""
          };
        });
        const text = pageText(document.body);
        return {
          rows,
          distinctColors: new Set(rows.map((row) => row.borderLeftColor).filter(Boolean)).size,
          hasOpenCodeRuntimeCoverage: text.includes("OpenCode through OMP") &&
            text.includes("covered by the OMP runtime adapter"),
          hasOpenCodeNativeLimit: text.includes("OpenCode native") &&
            text.includes("session_import_best_effort") &&
            text.includes("lower-fidelity plugin/import scaffold"),
          hasRecordingPolicy: text.includes("Auto-recording applies only to verified adapters") &&
            text.includes("Generic OpenAI-compatible clients stay manual") &&
            text.includes("recording.adapted_agents")
        };
      })()`
    );

    const missing = result.rows.filter((row) => !row.present);
    if (
      missing.length > 0 ||
      result.distinctColors < 4 ||
      !result.hasOpenCodeRuntimeCoverage ||
      !result.hasOpenCodeNativeLimit ||
      !result.hasRecordingPolicy
    ) {
      throw new Error(`adapter status panel smoke failed: ${JSON.stringify(result)}`);
    }

    console.log("ok adapter status panel renders state, fidelity, and recording policy");
  } finally {
    cdp.close();
  }
}

async function assertSelectedModelWorkbench() {
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
      url: `${appUrl}/admin?model=browser-smoke-model`
    });
    await cdp.waitFor("Page.loadEventFired");
    await waitForEval(cdp, `pageText(document.body).includes("browser-smoke-model")`);
    await waitForEval(cdp, `pageText(document.body).includes("Simulate a turn")`);
    await waitForEval(cdp, `pageText(document.body).includes("browser-smoke-redact")`);

    const result = await evaluate(
      cdp,
      `(() => {
        const text = pageText(document.body);
        const forbidden = [
          "Selected Node",
          "Review Findings",
          "Legacy workbench"
        ].filter((label) => text.includes(label));
        return {
          hasExamples: text.includes("Example models"),
          hasTrace: text.includes("Step playback"),
          forbidden
        };
      })()`
    );

    if (!result.hasExamples || !result.hasTrace || result.forbidden.length > 0) {
      throw new Error(
        `selected model workbench rendered stale or missing panels: ${JSON.stringify(result)}`
      );
    }

    console.log("ok selected model workbench renders Lustre model surface");
  } finally {
    cdp.close();
  }
}

async function assertServerToolModelAccess() {
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
      url: `${appUrl}/admin?view=model_access&model=browser-smoke-tools`
    });
    await cdp.waitFor("Page.loadEventFired");
    await waitForEval(cdp, `pageText(document.body).includes("Server Tools")`);
    await waitForEval(cdp, `pageText(document.body).includes("browser_smoke_dune_tool")`);

    const result = await evaluate(
      cdp,
      `(() => {
        const text = pageText(document.body);
        return {
          hasEnabledTool: text.includes("wardwright_policy_cache_status"),
          hasDuneLimits: text.includes("timeout 500ms") &&
            text.includes("reductions 10000") &&
            text.includes("heap 1000000"),
          hasDisabledTool: text.includes("browser_smoke_disabled_tool") &&
            text.includes("disabled"),
          hasProviderSupport: text.includes("Server tools sent to provider") &&
            text.includes("Server tools not sent"),
          hasToggleControls: text.includes("Disable") && text.includes("Enable"),
          hasAdvertisementSummary: text.includes("Advertise") &&
            text.includes("Guaranteed tools") &&
            text.includes("Conditional tools"),
          hasRoutingScope: text.includes("Tool availability differs by raw target") &&
            text.includes("selected tool-capable provider target")
        };
      })()`
    );

    if (
      !result.hasEnabledTool ||
      !result.hasDuneLimits ||
      !result.hasDisabledTool ||
      !result.hasProviderSupport ||
      !result.hasToggleControls ||
      !result.hasAdvertisementSummary ||
      !result.hasRoutingScope
    ) {
      throw new Error(`server-tool model access smoke failed: ${JSON.stringify(result)}`);
    }

    await cdp.send("Emulation.setDeviceMetricsOverride", {
      width: 390,
      height: 844,
      deviceScaleFactor: 3,
      mobile: true
    });
    await cdp.send("Page.navigate", {
      url: `${appUrl}/admin?view=model_access&model=browser-smoke-tools`
    });
    await cdp.waitFor("Page.loadEventFired");
    await waitForEval(cdp, `pageText(document.body).includes("browser_smoke_dune_tool")`);

    const mobileLayout = await evaluate(
      cdp,
      `(() => {
        const thead = allElements(".server-tool-table thead")[0];
        const row = allElements(".server-tool-table tbody tr")[0];
        const cell = allElements(".server-tool-table tbody td")[0];
        return {
          hidesHeader: thead ? getComputedStyle(thead).display === "none" : false,
          stacksRows: row ? getComputedStyle(row).display === "block" : false,
          labelsCells: cell ? getComputedStyle(cell, "::before").content.includes("Tool") : false
        };
      })()`
    );

    if (!mobileLayout.hidesHeader || !mobileLayout.stacksRows || !mobileLayout.labelsCells) {
      throw new Error(`server-tool mobile table layout smoke failed: ${JSON.stringify(mobileLayout)}`);
    }

    console.log("ok model access renders server-tool config and target support");
  } finally {
    cdp.close();
  }
}

async function assertControlDebuggerSaveScenario() {
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

    await cdp.send("Page.navigate", { url: `${appUrl}/admin?view=control_debugger` });
    await cdp.waitFor("Page.loadEventFired");
    await waitForEval(cdp, `pageText(document.body).includes("Session replay")`);
    await waitForEval(cdp, `!document.documentElement.classList.contains("phx-loading")`);

    await clickButtonByText(cdp, "Record example session");
    await waitForEval(
      cdp,
      `pageText(document.body).includes("Violation: edit_file ran before read_file for app.txt.")`
    );

    await clickButtonByText(cdp, "Save scenario");
    await waitForEval(
      cdp,
      `pageText(document.body).includes("Open Workbench, choose tool-governance")`
    );

    console.log("ok control debugger saves read-before-edit scenario to tool-governance");
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
          const elements = [document.documentElement, document.body].filter(Boolean);
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
          .filter((entry) =>
            entry.right > document.documentElement.clientWidth + 1 ||
            entry.width > document.documentElement.clientWidth + 1 ||
            entry.scrollWidth > document.documentElement.clientWidth + 1
          )
          .sort((a, b) => b.scrollWidth - a.scrollWidth || b.right - a.right || b.width - a.width)
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

    await cdp.send("Page.navigate", { url: `${appUrl}/admin?model=demo-retry-guard` });
    await cdp.waitFor("Page.loadEventFired");
    await waitForEval(cdp, `pageText(document.body).includes("Step playback")`);
    await waitForEval(cdp, `pageText(document.body).includes("Example models")`);

    await assertClickableControl(cdp, viewport.name, "Next step");
    await clickControlAndWait(
      cdp,
      "Next step",
      `pageText(document.body).includes("Step 2 of")`
    );

    await assertClickableControl(cdp, viewport.name, "Back");
    await clickControlAndWait(
      cdp,
      "Back",
      `pageText(document.body).includes("Step 1 of")`
    );

    await assertClickableControl(cdp, viewport.name, "Next step");
    await clickControlAndWait(
      cdp,
      "Next step",
      `pageText(document.body).includes("Step 2 of")`
    );

    await assertClickableControl(cdp, viewport.name, "Reset");
    await clickControlAndWait(
      cdp,
      "Reset",
      `pageText(document.body).includes("Step 1 of")`
    );

    console.log(`ok ${viewport.name} Lustre playback controls`);
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
    }
  }

  throw lastError;
}

async function clickControl(cdp, label) {
  const result = await evaluate(
    cdp,
    `(() => {
      const candidates = allElements("button")
        .filter((candidate) => candidate.textContent.trim() === ${JSON.stringify(label)});
      if (candidates.length === 0) return { error: "missing ${label} control" };

      for (const button of candidates) {
        button.scrollIntoView({ block: "center", inline: "center" });
        const rect = button.getBoundingClientRect();
        const x = rect.left + rect.width / 2;
        const y = rect.top + rect.height / 2;
        const root = button.getRootNode();
        const covering = root.elementFromPoint ? root.elementFromPoint(x, y) : document.elementFromPoint(x, y);
        if (covering === button || button.contains(covering)) {
          button.click();
          return { clicked: true };
        }
      }

      return { error: "no clickable ${label} control" };
    })()`
  );

  if (!result || result.error) {
    throw new Error(result?.error || `Could not click ${label} control`);
  }
}

async function clickButtonByText(cdp, label) {
  const result = await evaluate(
    cdp,
    `(() => {
      const button = allElements("button")
        .find((candidate) => candidate.textContent.trim() === ${JSON.stringify(label)});
      if (!button) return { error: "missing ${label} button" };
      button.scrollIntoView({ block: "center", inline: "center" });
      button.click();
      return { clicked: true };
    })()`
  );

  if (!result || result.error) {
    throw new Error(result?.error || `Could not click ${label} button`);
  }
}

async function assertClickableControl(cdp, viewportName, label) {
  const result = await evaluate(cdp, controlPointExpression(label));

  if (!result || result.error) {
    throw new Error(`${viewportName}: ${result?.error || `missing ${label} control`}`);
  }

  if (!result.clickable) {
    throw new Error(
      `${viewportName}: ${label} control is covered by ${result.coveringTag}.${result.coveringClass} ` +
        `at ${JSON.stringify(result.rect)} text=${JSON.stringify(result.coveringText || "")}`
    );
  }
}

function controlPointExpression(label) {
  return `(() => {
    const candidates = allElements("button")
      .filter((candidate) => candidate.textContent.trim() === ${JSON.stringify(label)});
    if (candidates.length === 0) return { error: "missing ${label} control" };

    let blocked = null;

    for (const button of candidates) {
      button.scrollIntoView({ block: "center", inline: "center" });
      const rect = button.getBoundingClientRect();
      const x = rect.left + rect.width / 2;
      const y = rect.top + rect.height / 2;
      const root = button.getRootNode();
      const covering = root.elementFromPoint ? root.elementFromPoint(x, y) : document.elementFromPoint(x, y);
      const clickable = covering === button || button.contains(covering);

      const result = {
        x,
        y,
        clickable,
        coveringTag: covering?.tagName || "none",
        coveringClass: covering?.className || "",
        coveringText: covering?.textContent?.trim()?.slice(0, 80) || "",
        rect: {
          left: Math.round(rect.left),
          top: Math.round(rect.top),
          width: Math.round(rect.width),
          height: Math.round(rect.height)
        }
      };

      if (clickable) {
        return result;
      }

      blocked = result;
    }

    return blocked || { error: "missing ${label} control" };
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

      const allElements = (selector) => {
        const elements = [...document.querySelectorAll(selector)];
        const collect = (root) => {
          if (!root?.querySelectorAll) return;
          for (const element of root.querySelectorAll("*")) {
            if (element.shadowRoot) {
              elements.push(...element.shadowRoot.querySelectorAll(selector));
              collect(element.shadowRoot);
            }
          }
        };
        collect(document);
        return elements;
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
