# Org Transfer Security Checklist (Execution Guide)

Date baseline: May 5, 2026.

## Goal

Enable a safe organization transfer while immediately enforcing a security baseline for a solo-maintained protocol repository.

## Phase 0 — Before transfer (same day)

- [ ] Confirm current default branch and protected branches.
- [ ] Export current repository secrets/variables inventory (names only, no values).
- [ ] Snapshot existing Actions workflows and required checks.
- [ ] Freeze risky merges during transfer window.

Success criteria:
- You can compare pre/post transfer settings without guessing.

## Phase 1 — Transfer + governance baseline (Day 1)

- [ ] Transfer repository into the target GitHub organization.
- [ ] Re-enable CodeQL workflow and confirm scan jobs trigger on PRs.
- [ ] Set branch protection rules:
  - `main`: no direct push, require PR, require passing checks.
  - `canary`: no direct push, require PR, require passing checks.
  - `dev`: require PR + passing checks (can be less strict than main).
- [ ] Enable dismiss stale approvals when new commits are pushed.

Required checks (minimum):
- [ ] `pnpm -s lint`
- [ ] `pnpm -s typecheck`
- [ ] contracts CI fast gate
- [ ] CodeQL

Success criteria:
- No PR can merge unless all baseline checks pass.

## Phase 2 — CI runtime determinism (Day 2-4)

- [ ] Add pinned runtime path for release verification (container preferred).
- [ ] Add single wrapper command for repeatability (example: `make release-gate-container`).
- [ ] Ensure `forge`, `jq`, `slither`, `node`, and `pnpm` versions are explicit.
- [ ] Persist release artifacts/evidence manifest as build artifacts.

Success criteria:
- Release gate gives same result locally and in CI for same commit + env.

## Phase 3 — Secrets and key hygiene (Day 5-7)

- [ ] Split credentials by environment (`staging`, `mainnet`).
- [ ] Split credentials by duty (`deploy`, `verify`, `sign`).
- [ ] Rotate old/shared credentials.
- [ ] Store emergency recovery instructions in runbook.

Success criteria:
- Compromise in one environment or role does not expose all release paths.

## Phase 4 — Privacy and incident readiness (Day 8-14)

- [ ] Add release privacy-impact checklist (on-chain + off-chain metadata review).
- [ ] Add playbooks for:
  - verifier key compromise
  - operator key compromise
  - bad release artifact anchoring
- [ ] Run one tabletop drill and capture deltas.

Success criteria:
- You can execute incident response steps without ad-hoc decisions.

## Immediate next action (single highest ROI)

If you only do one thing first, do this:

**Enable CodeQL + required status checks + branch protection immediately after transfer.**

This creates an enforceable baseline for every future change and is the most effective solo-founder risk reduction step.


## Phase 0.5 — Pre-transfer readiness script

Run:

```bash
export GH_PAT=<repo_admin_token>
# optional: export GH_REPO=<owner>/<repo>
./scripts/github/pretransfer-readiness.sh
```

This verifies API access, expected workflow files, and checks whether `GOVERNANCE_VERIFY_PAT` is already present.


## Phase 1.5 — Post-transfer bootstrap (recommended)

Run:

```bash
export GH_PAT=<repo_admin_token>
# optional: export GH_REPO=<org>/<repo>
./scripts/github/posttransfer-bootstrap.sh
```

This executes governance apply + verification in one command and should be run immediately after repo transfer.
