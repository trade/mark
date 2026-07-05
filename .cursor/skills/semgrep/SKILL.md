---
name: semgrep
description: Runs MARK Protocol Semgrep security scans (Solidity, Circom, TS, Bash, YAML) using repo .semgrep.yml and mise/uvx. Use when scanning changes, fixing Semgrep CI failures, or reviewing pool/bridge/settlement/circuits/scripts/workflows security.
---

# MARK Semgrep

Static analysis for this repo. **Prefer the CLI path below** so any agent (Cursor, CI, local shell) gets the same results.

## Prerequisites

From repo root (`/Users/iap/mark` or clone path):

```bash
mise trust
mise install   # if needed
```

Semgrep runs via **`uvx semgrep`** (see `.mise.toml`, `pyproject.toml`). Do not rely on a global `semgrep` on PATH unless you mirror CI flags.

## MCP Server

If the Cursor MCP plugin is installed, a local Semgrep MCP server is configured in `.cursor/mcp.json`:

- **Server:** `semgrep`
- **Command:** `node .cursor/semgrep-mcp-server.cjs`
- **Tools:** `semgrep_scan`, `semgrep_rules`, `semgrep_ci_scope`

Use the MCP for in-editor feedback. Still run **`mise run semgrep` or the CI-scoped command** before claiming merge-ready.

## When to scan

| Change                                                            | Minimum scan                                                     |
| ----------------------------------------------------------------- | ---------------------------------------------------------------- |
| `contracts/src/**` (especially `pool/`, `bridge/`, `settlement/`) | Scoped Semgrep on touched paths + `make ci-fast` in `contracts/` |
| `circuits/**`                                                     | Scoped Semgrep on touched paths (Circom rules active)            |
| `scripts/**`                                                      | Scoped Semgrep on touched paths (script injection rules active)  |
| `.github/workflows/**`                                            | Scoped Semgrep on touched workflows (WARNING rules active)       |
| Pre-PR to `dev`                                                   | `mise run ci-fast` (includes Semgrep ERROR rules)                |
| Pre-PR to `main`                                                  | `mise run ci-full`                                               |

## Configuration

| File                                                            | Role                                                                                               |
| --------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| [`.semgrep.yml`](../../../.semgrep.yml)                         | MARK-specific rules organized by domain: invariants, Solidity, TS, Circom, scripts, YAML, markdown |
| [`.semgrepignore`](../../../.semgrepignore)                     | Repo-wide excludes (build artifacts, tests, dependencies)                                          |
| [`contracts/.semgrepignore`](../../../contracts/.semgrepignore) | Contracts-specific excludes (out, cache, broadcast, generated verifier code, tests)                |

## Trust boundaries (per AGENTS.md)

Semgrep rules intentionally cover trust-boundary paths:

- **`scripts/**`** — "Scripts handle governance and release orchestration." Covered by `mark-script-injection`and`mark-script-hardcoded-secret`.
- **`.github/workflows/**`** — Workflows are part of CI security. Covered by `mark-github-actions-injection` at WARNING severity.

Semgrep does NOT replace TruffleHog, Slither, or CodeQL. It complements them.

## Standard commands

**Full project scan (local dev, matches `mise run semgrep`):**

```bash
cd /path/to/mark
mise run semgrep
```

Equivalent:

```bash
uvx semgrep scan \
  --config=auto \
  --config=p/security-audit \
  --config=./.semgrep.yml \
  --error
```

**CI-aligned scope (ERROR severity only):**

```bash
uvx semgrep scan \
  --config .semgrep.yml \
  --severity ERROR \
  --error \
  contracts/ circuits/ src/ scripts/ .github/workflows/
```

**Diff-scoped (after edits):**

```bash
uvx semgrep scan \
  --config=auto \
  --config=./.semgrep.yml \
  --severity ERROR \
  --error \
  -- path/to/changed/file.sol
```

**PR workflow baseline (matches `.github/workflows/semgrep.yml`):**

```bash
git fetch origin tag semgrep-baseline-v1 || true
BASELINE_SHA=$(git rev-parse semgrep-baseline-v1^{commit} 2>/dev/null || echo "")
if [ -n "$BASELINE_SHA" ]; then
  uvx semgrep@1.163.0 scan \
    --config=.semgrep.yml \
    --severity ERROR \
    --sarif \
    --output=semgrep.sarif \
    --baseline-commit="$BASELINE_SHA" .
else
  uvx semgrep@1.163.0 scan \
    --config=.semgrep.yml \
    --severity ERROR \
    --sarif \
    --output=semgrep.sarif .
fi
```

Pin `@1.163.0` for SARIF/baseline parity with GitHub Actions; day-to-day scans may use unpinned `uvx semgrep` unless debugging version drift.

## Interpreting findings

1. **Rule id** — `mark-*` rules encode protocol invariants, domain boundaries, or trust-boundary checks.
2. **Severity** — `ERROR` is CI-blocking (reject PR if unfixed); `WARNING` requires manual review.
3. **Path** — Focus on production code under `contracts/src/{pool,bridge,settlement}/`, `circuits/`, `scripts/`, `.github/workflows/`.
4. **Fix order** — For reentrancy/nullifier issues: state updates before external calls (SWC-107). Do not weaken checks to green the scan.

Report format for agents:

```markdown
## Semgrep summary

- Command: ...
- Result: pass | N findings

### Findings

1. **[ERROR] `rule-id`** — `path:line` — one-line fix intent
```

## Rule conventions

| Prefix         | Domain                   | Example                                |
| -------------- | ------------------------ | -------------------------------------- |
| `mark-`        | MARK protocol invariant  | `mark-nullifier-before-external-call`  |
| `ts-`          | TypeScript / frontend    | `ts-unsafe-innerhtml`                  |
| `mark-circom-` | Circom circuit           | `mark-circom-unconstrained-assignment` |
| `mark-github-` | GitHub Actions           | `mark-github-actions-injection`        |
| `mark-script-` | Scripts / trust boundary | `mark-script-injection`                |

New rules: add to `.semgrep.yml` with `severity: ERROR` for CI-blocking findings or `severity: WARNING` for review-only findings. Align messages with forbidden patterns in root `AGENTS.md` and `contracts/AGENTS.md`.

## Agent checklist

- [ ] Cwd is repo root
- [ ] Scan scope matches changed paths (or full CI scope)
- [ ] ERROR findings addressed or documented as accepted risk
- [ ] WARNING findings reviewed and acknowledged
- [ ] Related: architecture-guard / layering-guard if contracts imports changed
- [ ] No `.semgrep.yml` or `.semgrepignore` changes without strategic review

## Additional resources

- Threat context: [`docs/THREAT_MODEL.md`](../../../docs/THREAT_MODEL.md)
- Contract agent loop: [`contracts/AGENTS.md`](../../../contracts/AGENTS.md)
- Semgrep MCP tool: `semgrep_scan`, `semgrep_rules`, `semgrep_ci_scope` via `.cursor/mcp.json`
