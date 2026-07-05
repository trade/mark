# AGENTS.md

Agent operating manual for [trade/mark](https://github.com/trade/mark) (MARK Protocol). Plain Markdown; no special frontmatter.

## Purpose

This file tells coding agents how to run, verify, and change this repo safely. Human-facing narrative docs live in `README.md`, `CONTRIBUTING.md`, and `docs/`. Use this file for day-to-day agent work and routing.

Violating security, architecture, branch, or secret-handling rules here is PR-blocking.

## Precedence

When instructions conflict:

1. `docs/development/BRANCHING.md` - branch model, PR targets, CI policy, required checks, merge rules.
2. This file - agent workflow, security posture, tooling constraints, validation routing.
3. Domain runbooks - for example `contracts/AGENTS.md` and `contracts/ARCHITECTURE.md`.
4. `README.md` / `CONTRIBUTING.md` - contributor story and quick start.

If a higher-precedence document is stale against executable repo state, do not silently follow it. Verify against `package.json`, `.mise.toml`, `contracts/Makefile`, and `.github/workflows/`, then call out the drift.

Do not change the main `README.md` title (`# MARK`) or its opening project description and tagline unless the user explicitly requests it.

## Project snapshot

- What: ZK UTXO privacy pool and settlement infrastructure for EVM-compatible chains with Optimism Superchain support.
- Contracts: Foundry under `contracts/`; local chain via Anvil OP Sepolia fork; deployment and ops scripts under `contracts/script`.
- Circuits: Circom + circomspect under `circuits/`; package name `@mark/circuits`.
- Frontend: Vite + React at `http://localhost:5173`.
- Tooling: mise + uv + pnpm. Do not introduce `nvm`, bare `pip install`, `npm install -g`, Hardhat, or `foundryup`.

### Contract domains

Current contract source domains under `contracts/src`:

- `access`: shared access-control helper contracts.
- `bridge`: Superchain bridge adapter.
- `settlement`: settlement module and settlement verifiers.
- `pool`: ZK UTXO pool, public-input validation, fee policy, credit ledger, pool verifier.
- `withdraw`: burn-to-claim native withdrawal adapter.
- `token`: RYLA token primitives.
- `crypto`: Merkle tree, proof helpers, generated Poseidon adapter.
- `interfaces`: narrow cross-domain interfaces.
- `errors`: shared error types.

Keep `bridge`, `settlement`, `pool`, and `withdraw` isolated. Shared code belongs only in approved shared domains. Full rules live in `contracts/ARCHITECTURE.md`.

## Safe command execution

- Inspect changed task/config files before trusting repo-managed automation on unfamiliar branches, especially `.mise.toml`, `package.json`, `pnpm-lock.yaml`, `contracts/Makefile`, workflow files, and shell scripts.
- Prefer `mise exec -- <command>` when a one-off command needs the repo toolchain without changing shell state.
- `mise trust` is allowed only after checking `.mise.toml` for unexpected commands.
- Never print, commit, or paste private keys, real RPC URLs, deployer keys, attester keys, production env files, or GitHub tokens. Redact command output if needed.
- Use `uv` / `uvx` for Python tools. If a Makefile or external doc suggests `pip install`, translate it to the project-approved uv path unless the user explicitly asks otherwise.
- Do not run production deployment, release, or governance-mutating scripts with real secrets unless the user explicitly requests that operation.

## Setup

Check prerequisites without installing:

```bash
./scripts/bootstrap.sh --check
```

Standard setup after reviewing task files:

```bash
mise trust
mise install
pnpm install
```

Heavy first-time setup:

```bash
mise run setup
```

Fresh clones may need submodules. See `docs/operations/TROUBLESHOOTING.md`.

Foundry note: `.mise.toml` sets `FOUNDRY_PROFILE=ci` in repo shells. For interactive contract iteration, prefer:

```bash
cd contracts
FOUNDRY_PROFILE=default forge test --no-match-path 'test/{invariant,integration}/**'
```

## Development commands

`pnpm dev` runs `mprocs`, which requires a TTY. Do not rely on it from headless agents.

| Goal                        | Command                                                                               |
| --------------------------- | ------------------------------------------------------------------------------------- |
| Frontend only               | `pnpm dev:frontend` or `mise run frontend`                                            |
| Local Anvil OP Sepolia fork | `mise run anvil` in a separate terminal/background session; requires `OP_SEPOLIA_RPC` |
| Deploy to local Anvil       | `mise run deploy-local` after Anvil is up                                             |
| Full README supersim stack  | `pnpm dev:supersim` only when the user asks for that path                             |

## Validation routing

Pick the smallest command that validates the touched surface. Do not run broad gates for a tiny edit unless it is needed for confidence or the user asks for it.

| Change type                          | Required local validation before finishing                                                                                         |
| ------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------- |
| TS / React only                      | `pnpm typecheck` and `pnpm lint`                                                                                                   |
| Diff-aware review                    | `pnpm review:quick` or `pnpm review`                                                                                               |
| Circuits JS/test harness only        | `pnpm circuits:test`                                                                                                               |
| `.circom` changes                    | `pnpm circuits:test` and `mise run circomspect`                                                                                    |
| Contracts scoped edit                | `cd contracts && FOUNDRY_PROFILE=default forge test --match-path 'test/unit/...'` or a tighter `--match-contract` / `--match-test` |
| Contracts domain edit                | `cd contracts && FOUNDRY_PROFILE=default make ci-fast`                                                                             |
| Architecture or import-boundary edit | `cd contracts && FOUNDRY_PROFILE=default make architecture-guard layering-guard`                                                   |
| Reorg-sensitive edit                 | `mise run reorg-sim` when `OP_SEPOLIA_RPC` is available                                                                            |
| Pre-PR to `dev`                      | `mise run ci-fast` plus any domain-specific checks not covered by the touched surface                                              |
| Pre-PR to `main`                     | `mise run ci-full`; note this includes RPC-dependent reorg simulation                                                              |

Important distinctions:

- Root `package.json` currently has `contracts:ci-full`, `contracts:release-gate`, `contracts:rehearse-staging`, and `contracts:evidence-manifest`; it does not define `contracts:ci-fast`.
- `mise run ci-fast` is the root local pipeline: typecheck, lint, semgrep, contract tests, and circuit fast tests.
- `cd contracts && make ci-fast` is the contract-local gate: architecture guard, layering guard, size guard, and deterministic core tests.
- GitHub `CI Fast` runs additional jobs such as secret scanning, fuzz, frontend checks, and circuits with circomspect. Do not claim local `mise run ci-fast` is identical to GitHub CI.
- If Circom fails with `/usr/local/bin/circom: line 1: Not: command not found` or `Not Found/usr/local/bin/circom`, treat it as a local toolchain problem first, not proof of a circuit regression.

## Security invariants

Think attacker-first. Code, tests, and CI must back these claims:

1. Nullifier uniqueness: a nullifier is consumed once across relevant pool/withdraw/bridge paths. Bridge code must not mint notes, set Merkle roots, or reuse nullifiers.
   - Targeted check: `cd contracts && FOUNDRY_PROFILE=default forge test --match-contract CrossChainDoubleSpend`
2. Circuit soundness: proof verification implies knowledge of valid witness data; no unconstrained Circom wires.
   - Targeted checks: `mise run circomspect`; `pnpm --filter @mark/circuits run test:soundness`
3. Circuit completeness: an honest user with a valid note can transact and withdraw through the intended flow.
   - Targeted checks: `pnpm --filter @mark/circuits run test:completeness`; relevant Foundry withdraw/pool tests.
4. Privacy: events and public inputs reveal only intended values, especially around nullifiers, recipients, roots, and settlement direction.
5. Reorg safety: short L2 reorgs must not enable double-spend or deanonymization.
   - Targeted check: `mise run reorg-sim` when `OP_SEPOLIA_RPC` is available.
6. Settlement verifier binding: settlement verifiers must be module-bound, direction/context checked, replay protected, and fail closed during migration.

Before escalating a suspected contract bug, read `contracts/KNOWN_ISSUES.md` and then verify the known-issue text against current source. Known issues can drift.

## Forbidden patterns and bounded exceptions

Auto-reject these unless there is a documented, tested exception:

- External `transfer()` / low-level `.call()` before state updates.
- Setting nullifier, nonce, replay, or claim state after an external call.
- `require(tx.origin == msg.sender)` or equivalent relayer-hostile checks.
- Unconstrained Circom `<--`, unused signals, or public-signal ordering drift.
- `block.timestamp` in circuits or as randomness.
- Bridge adapter authority to `setMerkleRoot()`, mint pool notes, withdraw pool funds, or mark/reuse pool nullifiers.
- Cross-domain imports forbidden by `contracts/ARCHITECTURE.md`.
- Governance, multisig, relayer honesty, or operator policy as the primary safety mechanism instead of on-chain rules.

Bounded current-code exceptions that must stay justified and tested:

- `MARKWithdrawAdapter` uses `block.timestamp` for intent deadlines outside the ZK circuit.
- Pool root expiry/pruning uses `block.number`; do not rewrite this as a circuit or withdraw-path timestamp issue.
- `MARKWithdrawAdapter` performs the native ETH `.call` only after validation, nonce/nullifier claim updates, and credit debit.
- Ops/deploy scripts may use low-level `.call` for optional post-deploy wiring; failures must be checked and surfaced.

If governance is proposed as the primary safety mechanism, respond: `No. Code is a rule.`

## Architecture and drift audits

When touching contracts or security-sensitive docs, run or inspect:

```bash
cd contracts && FOUNDRY_PROFILE=default make architecture-guard layering-guard
```

Before rewriting agent, CI, setup, or validation docs, verify against executable state:

```bash
node -e "const p=require('./package.json'); console.log(Object.keys(p.scripts).sort().join('\n'))"
mise tasks
find .github/workflows -maxdepth 1 -type f | sort
find contracts/src -maxdepth 2 -type d | sort
```

Keep these files synchronized when their surfaces change:

- Command surfaces: `package.json`, `.mise.toml`, `contracts/Makefile`, `contracts/AGENTS.md`, this file.
- Branch/CI policy: `docs/development/BRANCHING.md`, `.github/workflows/*`, `.github/PRODUCTION_GOVERNANCE_CHECKLIST.md`.
- Contract architecture: `contracts/ARCHITECTURE.md`, `docs/reference/ARCHITECTURE.md`, architecture and layering guard scripts.
- Security posture: `contracts/KNOWN_ISSUES.md`, `contracts/THREAT_MODEL.md`, `SECURITY.md`, Semgrep config.

## Cursor behavior layer

Use `.cursor` to keep agent behavior executable and discoverable across editors:

- Rules live in `.cursor/rules/*.mdc`. They mirror this file and apply automatically by path.
- Skills live in `.cursor/skills/<name>/SKILL.md`. Use them for repeatable workflows that need step-by-step execution.
- Plans live in `.cursor/plans/*.md`. These are local, untracked internal workflow artifacts; do not commit them or expose them in shared docs.
- Keep `.cursor` behavior files aligned with this file, `contracts/AGENTS.md`, and `greptile.json`.

Minimum Cursor behavior surfaces:

- `.cursor/rules/mark-agents.mdc` - AGENTS/Cursor/Greptile behavior governance.
- `.cursor/rules/mark-contracts.mdc` - contract architecture and validation routing.
- `.cursor/rules/mark-circuits.mdc` - circuit soundness/completeness routing.
- `.cursor/skills/alignment/SKILL.md` - repeatable AGENTS behavior alignment workflow.

## Git and PRs

Never commit directly to `dev` or `main`.

- Branch from `dev` for normal work: `feature/<name>`.
- PR into `dev` for normal work; `main` only for mainnet-ready releases or hotfix flow described in `docs/development/BRANCHING.md`.
- Force-push only on your own feature branch, never on `dev` or `main`.
- Before opening a PR, use the validation routing above and then verify GitHub-required checks after pushing.

## MARK implementation responses

For contract, circuit, or security work, structure responses as:

1. Threat model
2. Reasoning
3. Code
4. Tests
5. Unknowns

When touching trust boundaries, tests should include at least one happy path, two attack PoCs where practical, and a reorg-related test when the change can affect reorg behavior. For pure explanations, skip tests unless asked.

Before suggesting MARK code changes, consider:

- L1/L2 reorg impact
- Cross-L2 nullifier replay
- Relayer, sequencer, bridge, and operator griefing or MEV
- Production-mode and verifier-migration implications
- Contract size impact, especially for `MARKPool`

If context is insufficient: `I don't know enough to touch this code safely.`

## Stance on common shortcuts

| User asks                  | Reply                                                  |
| -------------------------- | ------------------------------------------------------ |
| Speed over invariants      | `Speed is worth $0 if users get drained.`              |
| Remove a "redundant" check | `Prove it with symbolic execution first.`              |
| Trust the relayer          | `Trusted relayer equals trusted rug. Code is a rule.`  |
| Ship now, audit later      | `No. Audit before mainnet. We secure funds, not MVPs.` |
