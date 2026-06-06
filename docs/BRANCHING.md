# Branch Strategy

This repository uses a two-track branch model:

- `dev`: active integration and testnet — default target for all feature work; maps to OP Sepolia staging deployment
- `main`: mainnet-ready only — source of truth for mainnet releases

## Branch Roles

### `dev`

- Default target for feature branches and iterative changes.
- Automatically triggers staging rehearsal deployment (OP Sepolia) on push.
- Must stay buildable and testable at all times.
- Code merged here is considered testnet-ready.

### `main`

- Contains only reviewed, mainnet-ready code.
- Used for mainnet deployment preparation and release tags.
- Must pass full contract checks and staging rehearsal before merge.

## Working Branches

- `feature/<name>`: regular feature or refactor work, branch from `dev`, merge into `dev`.
- `hotfix/<name>`: urgent production fix, branch from `main`, merge to `main`, then back-merge to `dev`.
- `release/<name>` (optional): additional stabilisation before merging `dev` into `main`.

## CI and Deployment Policy

- `ci-fast` runs on pushes to `dev` and `main`, and on all PRs into protected branches.
- `ci-full` runs on pushes to `dev` and `main`, on PRs, on schedule, and manual dispatch — includes invariants + release gate.
- `governance` validates required-check consistency across:
  - `scripts/github/apply-governance.sh`
  - `BRANCHING.md`
  - `.github/PRODUCTION_GOVERNANCE_CHECKLIST.md`
- `contracts-staging-rehearsal` is automatically triggered on push to `dev`.
- `contracts-release-gate` runs release gate in a pinned container on pushes to `dev`/`main` and manual dispatch.
- `contracts-mainnet-readiness` is production-gated:
  - manual only (`workflow_dispatch`)
  - enforced to run from `main` branch
  - tied to `production` environment
- GitHub settings implementation checklist:
  - `.github/PRODUCTION_GOVERNANCE_CHECKLIST.md`
- Review/PR governance files:
  - `.github/CODEOWNERS`
  - `.github/pull_request_template.md`
  - `.github/PULL_REQUEST_TEMPLATE/release.md`

## Required Checks Matrix

Use this matrix as the merge baseline.

### PRs into `dev`

- `Typecheck + Lint`
- `Gitleaks Scan`
- `Detect Secrets Drift`
- `Dependency Review`
- `Release Gate Container`
- `Contracts Core (Unit + Invariant) / Contracts Core`
- `Contracts Security (Semgrep + Slither) / Semgrep Scan`
- `Contracts Security (Semgrep + Slither) / Slither Core Contracts`
- `Circuits Core (Build + Tests + Circomspect) / Circuits Core`
- `Frontend Checks (Node 24) / Frontend Checks (Node 24.3.0)`
- If PR touches governance policy files (`apply-governance.sh`, `BRANCHING.md`, governance checklist): `Validate Governance Policy Consistency`

### PRs into `main` (release candidate)

- `Typecheck + Lint`
- `Gitleaks Scan`
- `Detect Secrets Drift`
- `Dependency Review`
- `Release Gate Container`
- `Contracts Core (Unit + Invariant) / Contracts Core`
- `Contracts Security (Semgrep + Slither) / Semgrep Scan`
- `Contracts Security (Semgrep + Slither) / Slither Core Contracts`
- `Circuits Core (Build + Tests + Circomspect) / Circuits Core`
- `Frontend Checks (Node 24) / Frontend Checks (Node 24.3.0)`
- `Validate Release PR Checklist`
- `Validate Release Evidence`
- If PR touches governance policy files (`apply-governance.sh`, `BRANCHING.md`, governance checklist): `Validate Governance Policy Consistency`

### After merge to `main` (pre-deploy gate)

- Manually run `Contracts Mainnet Readiness` from `main`
- Capture readiness artifact and run URL in release records

## Required GitHub Branch Protection (Recommended)

Apply these repository settings:

1. Protect `main`

- Require pull request before merge.
- Require status checks:
  - `Typecheck + Lint`
  - `Gitleaks Scan`
  - `Dependency Review`
  - `Contracts Core (Unit + Invariant) / Contracts Core`
  - `Contracts Security (Semgrep + Slither) / Semgrep Scan`
  - `Contracts Security (Semgrep + Slither) / Slither Core Contracts`
  - `Circuits Core (Build + Tests + Circomspect) / Circuits Core`
  - `Frontend Checks (Node 24) / Frontend Checks (Node 24.3.0)`
  - `Detect Secrets Drift`
  - `Release Gate Container`
  - `Validate Release PR Checklist`
  - `Validate Release Evidence`
- Require at least 1-2 approvals.
- Dismiss stale approvals on new commits.
- Restrict direct push.

2. Protect `dev`

- Require pull request before merge (or allow maintainers direct push if desired).
- Require status checks:
  - `Typecheck + Lint`
  - `Gitleaks Scan`
  - `Dependency Review`
  - `Contracts Core (Unit + Invariant) / Contracts Core`
  - `Contracts Security (Semgrep + Slither) / Semgrep Scan`
  - `Contracts Security (Semgrep + Slither) / Slither Core Contracts`
  - `Circuits Core (Build + Tests + Circomspect) / Circuits Core`
  - `Frontend Checks (Node 24) / Frontend Checks (Node 24.3.0)`
  - `Detect Secrets Drift`
  - `Release Gate Container`
- Require at least 1-2 approvals.
- Dismiss stale approvals on new commits.
- Restrict direct push.

Notes:

- Do not add `Validate Governance Policy Consistency` as a global required branch-protection check because it is intentionally path-filtered; require it only on governance-touching PRs.
- `Contracts Core (With Invariants)` runs in `ci-full` after `ci-fast` passes — not a required branch protection check to avoid timeout on PRs.

3. Protect tags

- Release tags (`v*`) are protected by the `tag-protection` ruleset: creation is restricted to maintainers, deletion and force-update are blocked for all actors.

## Merge Flow

1. Create `feature/*` from `dev`.
2. Open PR into `dev`; resolve feedback and green checks.
3. Staging rehearsal runs automatically on push to `dev`.
4. Open PR `dev -> main` once staging rehearsal passes.
5. Run production readiness workflow from `main`.
6. Tag release on `main` after approval.