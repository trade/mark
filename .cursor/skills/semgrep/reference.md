# Semgrep configuration strategy (MARK)

Living plan for evolving `.semgrep.yml`, ignores, CI, and MCP. Update when restructuring rules.

## Current state (summary)

| Layer            | Location                                              | Role                                                    |
| ---------------- | ----------------------------------------------------- | ------------------------------------------------------- |
| Rules            | `.semgrep.yml`                                        | Single file, 7 sections (invariants → secrets)          |
| Global ignore    | `.semgrepignore`                                      | Build artifacts, deps, tests; **not** scripts/workflows |
| Contracts ignore | `contracts/.semgrepignore`                            | `out/`, verifier generated, test/script                 |
| MCP              | `.cursor/mcp.json` + `.cursor/semgrep-mcp-server.cjs` | Agent-driven scans with CI defaults                     |
| CI SARIF         | `.github/workflows/semgrep.yml`                       | `.semgrep.yml` only, baseline tag, `@1.163.0`           |
| CI fast gate     | `_reusable-contracts-security.yml`                    | `contracts/` + `circuits/` only                         |
| Local dev        | `mise run semgrep`                                    | `auto` + `p/security-audit` + `.semgrep.yml`            |

## Gaps and noise sources

1. **CI scope mismatch** — Reusable job scans `contracts/` + `circuits/`; rules also cover `src/`, `scripts/`, `.github/workflows/`. Frontend/script/workflow findings may not block CI until SARIF workflow or scope is aligned.
2. **Version drift** — GitHub uses `semgrep@1.163.0`; `pyproject.toml` still pins `1.90.0`. Align pins to avoid rule-behavior differences.
3. **`mark-timestamp-in-withdraw`** — `MARKWithdrawAdapter` legitimately uses `block.timestamp` for intent expiry (off-chain EIP-712, not ZK witness). Rule should target **pool ZK paths only**, not the withdraw adapter.
4. **`ts-prototype-pollution`** — `Object.assign` is broad; expect frontend noise if registry configs are added to CI-fast paths.
5. **Circom** — `mark-circom-*` supplements `circomspect`; keep Circom rules minimal to avoid duplicating circomspect.
6. **Removed anti-patterns** — Dropped broken `mark-lockfile-integrity` (matched lockfile names as code). Lock integrity belongs to dependency review / `pnpm audit`, not Semgrep string rules.
7. **Duplicate excludes** — Many rules repeat `test/**`, `lib/**`; centralize via `.semgrepignore` and trim per-rule `paths.exclude` when splitting files.

## Target architecture (scalable)

```
.semgrep/
  README.md                 # This plan + ownership
  mark-invariants.yml       # Section 1 — CI ERROR, never loosen without review
  mark-solidity.yml         # Section 2
  mark-typescript.yml       # Section 3
  mark-circom.yml           # Section 4
  mark-scripts.yml          # Section 5
  mark-github.yml           # Section 6 — WARNING default
  mark-secrets.yml          # Section 7
  profiles/
    ci.yml                  # include: invariants + solidity + circom + secrets (ERROR)
    dev.yml                 # ci.yml + typescript + scripts + github (WARNING ok)
```

Root `.semgrep.yml` becomes a thin aggregator:

```yaml
rules:
  - rules: .semgrep/mark-invariants.yml
  - rules: .semgrep/mark-solidity.yml
  # ...
```

(Syntax per Semgrep docs for `rules:` imports — validate with `semgrep scan --dryrun` after each split.)

### Ignore policy

| Path                                | Ignore in `.semgrepignore`?                                                          | Rationale                   |
| ----------------------------------- | ------------------------------------------------------------------------------------ | --------------------------- |
| `contracts/out`, `lib`, `cache`     | Yes                                                                                  | Not source                  |
| `**/test/**`, `contracts/script/**` | Yes                                                                                  | Intentional bad patterns    |
| `scripts/**`                        | **No**                                                                               | Trust boundary (governance) |
| `.github/workflows/**`              | **No**                                                                               | CI trust boundary           |
| `docs/**`, `*.md`                   | Optional — secrets rules include markdown; exclude docs if doc examples trigger keys |
| `circuits/build`, `utxo`            | Yes                                                                                  | Artifacts                   |
| `contracts/src/pool/verifier/**`    | Yes (contracts ignore)                                                               | Generated verifier          |

Add `circuits/.semgrepignore` mirroring `build/`, `node_modules/`, `test/` when scanning from `circuits/` root often.

## Phased rollout

### Phase 1 (done / in progress)

- [x] Restructure monolith header + sections in single `.semgrep.yml`
- [x] Refocus `.semgrepignore` on artifacts (stop ignoring all `*.yaml`)
- [x] Project MCP server with pinned version + repo-root cwd
- [ ] Align `pyproject.toml` + `mise` tasks on `1.163.0`
- [ ] Narrow `mark-timestamp-in-withdraw` to `contracts/src/pool/**` only
- [ ] Expand `_reusable-contracts-security.yml` paths OR document intentional narrow gate

### Phase 2

- Split `.semgrep.yml` into `.semgrep/*.yml` with `profiles/ci.yml` and `profiles/dev.yml`
- Point `mise run semgrep` at `profiles/dev.yml`; point reusable CI at `profiles/ci.yml`
- Add `semgrep scan --dryrun` to `contracts` Makefile or architecture guard optional step

### Phase 3

- Tighten `ts-prototype-pollution` (drop `Object.assign` or scope to `src/` user-input paths)
- Add rule IDs to `KNOWN_ISSUES.md` for accepted WARNINGs with expiry
- Refresh `semgrep-baseline-v1` after Phase 2 split (one-time baseline bump PR)

## MCP vs CLI

| Use                     | Tool                                                  |
| ----------------------- | ----------------------------------------------------- |
| Agent in Cursor         | MCP `semgrep_scan`                                    |
| Merge gate              | `mise run ci-fast` / GitHub Actions                   |
| Official Semgrep plugin | Optional `semgrep mcp` + hooks; not required for MARK |

MCP must not replace CLI: MCP uses `.semgrep.yml` only unless `include_registry: true`.
