// CI-fast witness tests: reuse existing circom build when present; otherwise build once.
import { existsSync } from "fs";
import { spawnSync } from "child_process";
import path from "path";
import { fileURLToPath } from "url";

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
const wasm = path.join(root, "build/MARKPool_js/MARKPool.wasm");

function run(cmd, args) {
  // nosemgrep:security.detect-child-process.detect-child-process
  // Safe: only called with hardcoded 'pnpm'/'node' and controlled args
  const r = spawnSync(cmd, args, { cwd: root, stdio: "inherit", shell: false });
  if (r.status !== 0) process.exit(r.status ?? 1);
}

if (!existsSync(wasm)) {
  console.log("circuits test:fast — no wasm artifact; running build once");
  run("pnpm", ["run", "build"]);
}

run("node", ["test/MARKPool.test.mjs"]);
