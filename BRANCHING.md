# Branch Strategy

This repository uses a three-track branch model:

- `dev`: active integration — default target for all feature work
- `canary`: stabilisation and staging — maps to testnet/staging deployment
- `main`: production-ready only — source of truth for mainnet releases

## Branch Roles

### `dev`
- Default target for feature branches and iterative changes.
- May include ongoing refactors and config updates not yet ready for staging.
- Must stay buildable and testable at all times.

### `canary`
- Stabilisation branch between `dev` and `main`.
- Automatically triggers staging rehearsal deployment (OP Sepolia).
- Code here is considered release-candidate quality.
- No direct feature work — only PRs from `dev` or `hotfix/*`.

### `main`
- Contains only reviewed, release-ready code.
- Used for production deployment preparation and release tags.
- Must pass full contract checks before merge.

## Working Branches

- `feature/<name>`: regular feature or refactor work, branch from `dev`, merge into `dev`.
- `hotfix/<name>`: urgent production fix, branch from `main`, merge to `main` and `canary`, then back-merge to `dev`.
- `release/<name>` (optional): additional stabilisation before merging `canary` into `main`.

## CI and Deployment Policy

- `contracts-ci` runs on pushes to `dev`, `canary`, and `main`, and on PRs touching contracts.
- `contracts-slither` runs on pushes to `dev`, `canary`, and `main`, and on PRs touching core contracts.
- `contracts-env-guard` runs on pushes to `dev`, `canary`, and `main`, and on PRs touching contracts.
- `secrets-drift-guard` runs on all PRs into `dev`, `canary`, and `main`.
- `secrets-scan` (gitleaks) runs on PRs/pushes to detect accidental secret commits early.
- `scripts-ci` runs shellcheck on repository automation scripts to reduce operational breakage risk.
- `contracts-staging-rehearsal` is automatically triggered on push to `canary`.
- `contracts-release-gate-container` runs release gate in a pinned container on pushes to `dev`/`canary`/`main` and manual dispatch.
- `contracts-mainnet-readiness` is production-gated:
  - manual only (`workflow_dispatch`)
  - enforced to run from `main` branch
  - tied to `production` environment
- `governance-policy-guard` validates required-check consistency across:
  - `scripts/github/apply-governance.sh`
  - `BRANCHING.md`
  - `.github/PRODUCTION_GOVERNANCE_CHECKLIST.md`
- GitHub settings implementation checklist:
  - `.github/PRODUCTION_GOVERNANCE_CHECKLIST.md`
- Review/PR governance files:
  - `.github/CODEOWNERS`
  - `.github/pull_request_template.md`
  - `.github/PULL_REQUEST_TEMPLATE/release.md`

## Required Checks Matrix

Use this matrix as the merge baseline.

### PRs into `dev`

- `Contracts Unit + Invariant`
- `Contracts Release Check (Dry-Run + Execute Smoke)`
- `Slither Core Contracts`
- `Secrets Drift Guard`
- `Analyze (JavaScript/TypeScript)`
- `Gitleaks Scan`
- `Release Gate Container`
- If PR touches governance policy files (`apply-governance.sh`, `BRANCHING.md`, governance checklist): `Validate Governance Policy Consistency`

### PRs into `canary`

- `Contracts Unit + Invariant`
- `Contracts Release Check (Dry-Run + Execute Smoke)`
- `Slither Core Contracts`
- `Secrets Drift Guard`
- `Analyze (JavaScript/TypeScript)`
- `Gitleaks Scan`
- `Release Gate Container`
- If PR touches governance policy files (`apply-governance.sh`, `BRANCHING.md`, governance checklist): `Validate Governance Policy Consistency`

### PRs into `main` (release candidate)

- `Contracts Unit + Invariant`
- `Contracts Release Check (Dry-Run + Execute Smoke)`
- `Slither Core Contracts`
- `Secrets Drift Guard`
- `Analyze (JavaScript/TypeScript)`
- `Gitleaks Scan`
- `Release Gate Container`
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
  - `Contracts Unit + Invariant`
  - `Contracts Release Check (Dry-Run + Execute Smoke)`
  - `Slither Core Contracts`
  - `Secrets Drift Guard`
  - `Analyze (JavaScript/TypeScript)`
  - `Gitleaks Scan`
  - `Release Gate Container`
  - `Validate Release PR Checklist`
  - `Validate Release Evidence`
- Require at least 1-2 approvals.
- Dismiss stale approvals on new commits.
- Restrict direct push.

2. Protect `canary`
- Require pull request before merge.
- Require status checks:
  - `Contracts Unit + Invariant`
  - `Contracts Release Check (Dry-Run + Execute Smoke)`
  - `Slither Core Contracts`
  - `Secrets Drift Guard`
  - `Analyze (JavaScript/TypeScript)`
  - `Gitleaks Scan`
  - `Release Gate Container`
- `Release Gate Container`
- `Gitleaks Scan`
- `Release Gate Container`
- Require at least 1 approval.
- Dismiss stale approvals on new commits.

3. Protect `dev`
- Require pull request before merge (or allow maintainers direct push if desired).
- Require status checks:
  - `Contracts Unit + Invariant`
  - `Contracts Release Check (Dry-Run + Execute Smoke)`
  - `Slither Core Contracts`
  - `Secrets Drift Guard`
  - `Analyze (JavaScript/TypeScript)`
  - `Gitleaks Scan`
  - `Release Gate Container`
- `Release Gate Container`
- `Gitleaks Scan`
- `Release Gate Container`

Notes:
- Do not add `Validate Governance Policy Consistency` as a global required branch-protection check because it is intentionally path-filtered; require it only on governance-touching PRs.

4. Protect tags
- Reserve release tags (for example `v*`) to maintainers only.

## Merge Flow

1. Create `feature/*` from `dev`.
2. Open PR into `dev`; resolve feedback and green checks.
3. Open PR `dev -> canary` for staging stabilisation.
4. Staging rehearsal runs automatically on push to `canary`.
5. Open PR `canary -> main` once staging rehearsal passes.
6. Run production readiness workflow from `main`.
7. Tag release on `main` after approval.
