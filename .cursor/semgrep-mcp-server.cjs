#!/usr/bin/env node
/**
 * MARK project Semgrep MCP (stdio).
 * Wraps pinned `uvx semgrep` with repo-root cwd and CI-aligned defaults.
 */

const { spawn } = require("child_process");
const path = require("path");
const readline = require("readline");

const REPO_ROOT = path.resolve(__dirname, "..");
const CONFIG = path.join(REPO_ROOT, ".semgrep.yml");
const SEMGREP_BIN = process.env.SEMGREP_BIN || "uvx";
const SEMGREP_VERSION = process.env.SEMGREP_VERSION || "1.163.0";

const DEFAULT_SCAN_PATHS = "contracts/,circuits/,src/,scripts/,.github/workflows";

const TOOLS = [
  {
    name: "semgrep_scan",
    description:
      "Run Semgrep with MARK .semgrep.yml. Paths are comma-separated; default matches CI scope.",
    inputSchema: {
      type: "object",
      properties: {
        paths: {
          type: "string",
          description: `Comma-separated paths (default: ${DEFAULT_SCAN_PATHS})`,
        },
        severity: {
          type: "string",
          enum: ["ERROR", "WARNING", "INFO"],
          description: "Minimum severity (default: ERROR)",
        },
        output_format: {
          type: "string",
          enum: ["text", "json"],
          description: "Output format (default: text)",
        },
        include_registry: {
          type: "boolean",
          description:
            "If true, also load --config=auto and p/security-audit (local dev parity with mise run semgrep)",
        },
      },
    },
  },
  {
    name: "semgrep_rules",
    description: "Validate .semgrep.yml loads (semgrep scan --dryrun).",
    inputSchema: { type: "object", properties: {} },
  },
  {
    name: "semgrep_ci_scope",
    description: "Return CI-aligned scan command and default paths.",
    inputSchema: { type: "object", properties: {} },
  },
];

function semgrepCommand(extraArgs) {
  if (SEMGREP_BIN === "mise") {
    return {
      cmd: "mise",
      args: ["exec", "--", "uvx", `semgrep@${SEMGREP_VERSION}`, ...extraArgs],
    };
  }
  if (SEMGREP_BIN === "uvx") {
    return {
      cmd: "uvx",
      args: [`semgrep@${SEMGREP_VERSION}`, ...extraArgs],
    };
  }
  return { cmd: SEMGREP_BIN, args: extraArgs };
}

function runSemgrep(extraArgs) {
  return new Promise((resolve, reject) => {
    const { cmd, args } = semgrepCommand(extraArgs);
    const proc = spawn(cmd, args, {
      cwd: REPO_ROOT,
      env: { ...process.env, SEMGREP_SEND_METRICS: "off" },
    });

    let stdout = "";
    let stderr = "";

    proc.stdout.on("data", d => {
      stdout += d.toString();
    });
    proc.stderr.on("data", d => {
      stderr += d.toString();
    });

    proc.on("error", reject);
    proc.on("close", code => resolve({ code, stdout, stderr }));
  });
}

function respond(id, payload) {
  const out = { jsonrpc: "2.0", ...payload };
  if (id !== undefined && id !== null) out.id = id;
  process.stdout.write(`${JSON.stringify(out)}\n`);
}

async function handleScan(params = {}) {
  const paths = (params.paths || DEFAULT_SCAN_PATHS)
    .split(",")
    .map(s => s.trim())
    .filter(Boolean);
  const severity = params.severity || "ERROR";
  const outputFormat = params.output_format || "text";
  const includeRegistry = Boolean(params.include_registry);

  const args = ["scan", `--config=${CONFIG}`, `--severity=${severity}`];
  if (includeRegistry) {
    args.push("--config=auto", "--config=p/security-audit");
  }
  args.push("--error");
  if (outputFormat === "json") args.push("--json");
  args.push(...paths);

  const result = await runSemgrep(args);
  const text =
    result.stdout ||
    result.stderr ||
    (result.code === 0 ? "No findings." : "Scan finished with no output.");

  // exit 0 = no findings, exit 1 = findings present, exit >1 = tool error
  // MCP surfaces findings as a normal tool result (isError: false) so caller
  // can decide; only tool/internal failures are marked isError: true.
  return {
    content: [{ type: "text", text: text.trim() }],
    isError: result.code > 1,
  };
}

async function handleRules() {
  const result = await runSemgrep(["scan", `--config=${CONFIG}`, "--dryrun", "--error", REPO_ROOT]);

  const text =
    result.code === 0
      ? `Rules loaded from ${CONFIG}\n${result.stderr || result.stdout}`
      : `Rule validation failed (exit ${result.code}):\n${result.stderr || result.stdout}`;

  return {
    content: [{ type: "text", text: text.trim() }],
    isError: result.code !== 0,
  };
}

function handleCiScope() {
  return {
    content: [
      {
        type: "text",
        text: [
          "CI-aligned (ERROR, MARK rules only):",
          `uvx semgrep@${SEMGREP_VERSION} scan --config .semgrep.yml --severity ERROR --error ${DEFAULT_SCAN_PATHS.replace(/,/g, " ")}`,
          "",
          "Local dev (registry + MARK rules):",
          "mise run semgrep",
        ].join("\n"),
      },
    ],
  };
}

async function handleToolCall(name, args) {
  switch (name) {
    case "semgrep_scan":
      return handleScan(args);
    case "semgrep_rules":
      return handleRules();
    case "semgrep_ci_scope":
      return handleCiScope();
    default:
      throw new Error(`Unknown tool: ${name}`);
  }
}

async function handleMessage(msg) {
  const { id, method, params } = msg;

  if (method === "initialize") {
    respond(id, {
      result: {
        protocolVersion: "2024-11-05",
        capabilities: { tools: {} },
        serverInfo: { name: "mark-semgrep-mcp", version: "1.1.0" },
      },
    });
    return;
  }

  if (method === "notifications/initialized") {
    return;
  }

  if (method === "tools/list") {
    respond(id, { result: { tools: TOOLS } });
    return;
  }

  if (method === "tools/call") {
    try {
      const result = await handleToolCall(params.name, params.arguments || {});
      respond(id, { result });
    } catch (err) {
      respond(id, {
        result: {
          content: [{ type: "text", text: `Error: ${err.message}` }],
          isError: true,
        },
      });
    }
    return;
  }

  if (method === "ping") {
    respond(id, { result: {} });
    return;
  }

  if (id !== undefined && id !== null) {
    respond(id, { error: { code: -32601, message: `Method not found: ${method}` } });
  }
}

const rl = readline.createInterface({
  input: process.stdin,
  terminal: false,
});

rl.on("line", line => {
  const trimmed = line.trim();
  if (!trimmed) return;
  let msg;
  try {
    msg = JSON.parse(trimmed);
  } catch {
    return;
  }
  handleMessage(msg).catch(err => {
    process.stderr.write(`mark-semgrep-mcp: ${err.stack}\n`);
  });
});
