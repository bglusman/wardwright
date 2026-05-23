#!/usr/bin/env node

import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";

const OMP_BIN = process.env.OMP_BIN || "omp";
const TIMEOUT_MS = Number(process.env.OMP_TTSR_TIMEOUT_MS || 10_000);
const KEEP_TEMP = process.argv.includes("--keep-temp");
const REPO_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const ruleContent = await loadExportedOmpRule();

const extensionContent = `
let calls = 0;

function emptyUsage() {
  return {
    input: 0,
    output: 0,
    cacheRead: 0,
    cacheWrite: 0,
    totalTokens: 0,
    cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
  };
}

class ProbeStream {
  events;
  final;

  constructor(model) {
    calls += 1;

    const startedAt = Date.now();
    const blocks = [];
    const partial = {
      role: "assistant",
      content: blocks,
      api: model.api,
      provider: model.provider,
      model: model.id,
      usage: emptyUsage(),
      stopReason: calls === 1 ? "toolUse" : "stop",
      timestamp: startedAt,
    };

    if (calls === 1) {
      const toolName = process.env.WARDWRIGHT_PROBE_TOOL || "edit";
      const toolCall = {
        type: "toolCall",
        id: "ww-probe-tool-1",
        name: toolName,
        arguments: {
          path: "target.txt",
          oldString: "before",
          newString: "after",
          content: "after",
        },
      };
      blocks.push(toolCall);
      this.final = partial;
      this.events = [
        { type: "start", partial },
        { type: "toolcall_start", contentIndex: 0, partial },
        { type: "toolcall_delta", contentIndex: 0, delta: JSON.stringify(toolCall.arguments), partial },
        { type: "toolcall_end", contentIndex: 0, toolCall, partial },
        { type: "done", reason: "toolUse", message: partial },
      ];
    } else {
      const text = "Wardwright probe retry completed.";
      blocks.push({ type: "text", text });
      this.final = partial;
      this.events = [
        { type: "start", partial },
        { type: "text_start", contentIndex: 0, partial },
        { type: "text_delta", contentIndex: 0, delta: text, partial },
        { type: "text_end", contentIndex: 0, content: text, partial },
        { type: "done", reason: "stop", message: partial },
      ];
    }
  }

  async *[Symbol.asyncIterator]() {
    for (const event of this.events) yield event;
  }

  async result() {
    return this.final;
  }
}

export default function wardwrightRuntimeEquivalenceProbe(pi) {
  pi.registerProvider("wardwright-runtime", {
    baseUrl: "http://127.0.0.1/unused",
    apiKey: "WARDWRIGHT_RUNTIME_API_KEY",
    api: "wardwright-runtime-api",
    models: [
      {
        id: "tool-probe",
        name: "Wardwright runtime tool probe",
        api: "wardwright-runtime-api",
        input: ["text"],
        contextWindow: 8192,
        maxTokens: 1024,
        cost: { input: 0, output: 0 },
      },
    ],
    streamSimple: (model) => new ProbeStream(model),
  });

  pi.on("ttsr_triggered", async (event) => {
    const markerPath = process.env.WARDWRIGHT_TTSR_MARKER;
    if (!markerPath) return;

    await Bun.write(
      markerPath,
      JSON.stringify({
        tool: process.env.WARDWRIGHT_PROBE_TOOL || "edit",
        rules: event.rules.map((rule) => rule.name),
      }),
    );
  });
}
`;

const cases = [
  { tool: "edit", shouldTrigger: true },
  { tool: "edit_file", shouldTrigger: true },
  { tool: "write", shouldTrigger: true },
  { tool: "read", shouldTrigger: false },
];

async function loadExportedOmpRule() {
  const sourcePath = path.join(REPO_ROOT, "app", "lib", "wardwright_web", "agent_harness_adapters.ex");
  const source = await readFile(sourcePath, "utf8");
  const match = /defp oh_my_pi_ttsr_rule do\s+"""\n([\s\S]*?)\n\s+"""\n\s+end/.exec(source);

  if (!match) {
    throw new Error(`Could not find oh_my_pi_ttsr_rule heredoc in ${sourcePath}`);
  }

  return `${match[1]
    .split("\n")
    .map((line) => line.replace(/^    /, ""))
    .join("\n")}\n`;
}

async function main() {
  const results = [];

  for (const testCase of cases) {
    results.push(await runCase(testCase));
  }

  for (const result of results) {
    const status = result.passed ? "PASS" : "FAIL";
    const expected = result.shouldTrigger ? "trigger" : "not trigger";
    console.log(`${status} ${result.tool}: expected ${expected}`);
    if (!result.passed) {
      console.log(indent(result.reason));
      if (result.stderr) console.log(indent(`stderr:\n${result.stderr}`));
      if (result.stdout) console.log(indent(`stdout:\n${result.stdout}`));
      if (result.tempDir) console.log(indent(`temp: ${result.tempDir}`));
    }
  }

  const failed = results.filter((result) => !result.passed);
  if (failed.length > 0) {
    process.exitCode = 1;
    return;
  }

  console.log("OMP TTSR runtime equivalence probe matched Wardwright read-before-edit expectations.");
}

async function runCase({ tool, shouldTrigger }) {
  const tempDir = await mkdtemp(path.join(tmpdir(), `wardwright-omp-ttsr-${tool}-`));
  const projectDir = path.join(tempDir, "project");
  const ruleDir = path.join(projectDir, ".omp", "rules");
  const markerPath = path.join(tempDir, "ttsr-marker.json");
  const extensionPath = path.join(tempDir, "wardwright-runtime-equivalence.ts");

  await writeFile(extensionPath, extensionContent);
  await mkdirp(ruleDir);
  await writeFile(path.join(ruleDir, "wardwright-read-before-edit.md"), ruleContent);
  await writeFile(path.join(projectDir, "target.txt"), "before\n");

  const child = spawn(
    OMP_BIN,
    [
      "--extension",
      extensionPath,
      "--model",
      "wardwright-runtime/tool-probe",
      "--no-session",
      "-p",
      `Run Wardwright ${tool} probe.`,
    ],
    {
      cwd: projectDir,
      env: {
        ...process.env,
        HOME: path.join(tempDir, "home"),
        PI_CONFIG_DIR: path.join(tempDir, "config"),
        PI_CODING_AGENT_DIR: path.join(tempDir, "agent"),
        WARDWRIGHT_RUNTIME_API_KEY: "wardwright-runtime-probe",
        WARDWRIGHT_PROBE_TOOL: tool,
        WARDWRIGHT_TTSR_MARKER: markerPath,
      },
      stdio: ["ignore", "pipe", "pipe"],
    },
  );

  let stdout = "";
  let stderr = "";
  let spawnError = null;
  child.stdout.on("data", (chunk) => {
    stdout += chunk.toString();
  });
  child.stderr.on("data", (chunk) => {
    stderr += chunk.toString();
  });
  child.on("error", (error) => {
    spawnError = error;
  });

  const startedAt = Date.now();
  let timedOut = false;
  let marker = null;

  while (Date.now() - startedAt < TIMEOUT_MS) {
    if (!marker && existsSync(markerPath)) {
      marker = JSON.parse(await readFile(markerPath, "utf8"));
      if (!shouldTrigger) break;
    }

    if (child.exitCode !== null || spawnError) break;
    await sleep(100);
  }

  if (child.exitCode === null && !spawnError) {
    timedOut = true;
    child.kill("SIGTERM");
  }

  const exit = spawnError
    ? { code: null, signal: null, error: spawnError.message }
    : await waitForExit(child);
  const triggered = Boolean(marker?.rules?.includes("wardwright-read-before-edit"));
  const passed = shouldTrigger
    ? triggered && !timedOut && exit.code === 0
    : !triggered && !timedOut && exit.code === 0;

  const result = {
    tool,
    shouldTrigger,
    passed,
    stdout: stdout.trim(),
    stderr: stderr.trim(),
    tempDir: KEEP_TEMP ? tempDir : null,
    reason: spawnError ? `Failed to start OMP binary "${OMP_BIN}": ${spawnError.message}` : "",
  };

  if (!passed && !result.reason) {
    result.reason = shouldTrigger
      ? `TTSR marker did not include wardwright-read-before-edit. marker=${JSON.stringify(marker)} exit=${JSON.stringify(exit)}`
      : `TTSR marker should not have been written. marker=${JSON.stringify(marker)} timedOut=${timedOut} exit=${JSON.stringify(exit)}`;
  }

  if (!KEEP_TEMP) {
    await rm(tempDir, { force: true, recursive: true });
  }

  return result;
}

async function mkdirp(dir) {
  await mkdir(dir, { recursive: true });
}

function waitForExit(child) {
  if (child.exitCode !== null) {
    return Promise.resolve({ code: child.exitCode, signal: child.signalCode });
  }

  return new Promise((resolve) => {
    child.once("error", (error) => resolve({ code: null, signal: null, error: error.message }));
    child.once("exit", (code, signal) => resolve({ code, signal }));
  });
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function indent(text) {
  return text
    .split("\n")
    .map((line) => `  ${line}`)
    .join("\n");
}

main().catch((error) => {
  console.error(error instanceof Error ? error.stack : String(error));
  process.exitCode = 1;
});
