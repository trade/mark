# Production Governance Checklist (GitHub)

Use this checklist to apply repository settings that enforce the `dev` -> `main` release process.

## 1) Protect `main` branch

GitHub path: `Settings -> Branches -> Add branch protection rule`

- Branch name pattern: `main`
- Enable `Require a pull request before merging`
- Enable `Require approvals` and set minimum to `2` (or `1` if your team is small)
- Enable `Dismiss stale pull request approvals when new commits are pushed`
- Enable `Require status checks to pass before merging`
- Add required checks:
  - `Analyze (javascript-typescript)`
  - `gitleaks / Gitleaks Scan`
  - `Detect Secrets Drift`
  - `Release Gate Container`
  - `Dependency Review`
  - `Contracts Unit + Invariant`
  - `Contracts Release Check (Dry-Run + Execute Smoke)`
  - `Contracts Production Mode Smoke`
  - `slither-core / Slither Core Contracts`
  - `frontend-checks / Frontend Checks (Node 20)`
  - `frontend-checks / Frontend Checks (Node 22)`
  - `Validate Release PR Checklist`
  - `Validate Release Evidence`
- Optional additional checks (recommended but not globally required):
  - `Contracts Unit + Invariant`
  - `Contracts Env Guard`
  - `Contracts Evidence Manifest`
  - `Governance Policy Guard`
- Governance policy PR rule:
  - If PR changes `scripts/github/apply-governance.sh`, `BRANCHING.md`, or this checklist, ensure `Validate Governance Policy Consistency` passes before merge.
- Enable `Require branches to be up to date before merging`
- Enable `Restrict who can push to matching branches` (maintainers only)
- Enable `Do not allow bypassing the above settings`

## 2) Protect `dev` branch

GitHub path: `Settings -> Branches -> Add branch protection rule`

- Branch name pattern: `dev`
- Enable `Require a pull request before merging`
- Enable `Require status checks to pass before merging`
- Add required checks:
  - `Analyze (javascript-typescript)`
  - `gitleaks / Gitleaks Scan`
  - `Detect Secrets Drift`
  - `Release Gate Container`
  - `Dependency Review`
  - `Contracts Unit + Invariant`
  - `Contracts Release Check (Dry-Run + Execute Smoke)`
  - `Contracts Production Mode Smoke`
  - `slither-core / Slither Core Contracts`
  - `frontend-checks / Frontend Checks (Node 20)`
  - `frontend-checks / Frontend Checks (Node 22)`
- Optional additional checks (recommended but not globally required):
  - `Contracts Unit + Invariant`
  - `Contracts Env Guard`
  - `Governance Policy Guard`
- Governance policy PR rule:
  - If PR changes `scripts/github/apply-governance.sh`, `BRANCHING.md`, or this checklist, ensure `Validate Governance Policy Consistency` passes before merge.
- Choose one model:
  - Strict model: also restrict direct push to maintainers only
  - Fast model: allow maintainer direct push for emergency dev iteration

## 4) Configure `production` environment

GitHub path: `Settings -> Environments -> New environment`

- Environment name: `production`
- Enable required reviewers (at least `1`, recommended `2`)
- Add secret:
  - `MARK_DEPLOYER_PRIVATE_KEY`
- Optional environment variables:
  - `MARK_MAINNET_GATE_MODE=predeploy` (default input still controls mode)

Notes:

- `contracts-mainnet-readiness.yml` already binds to `environment: production`.
- The workflow already enforces `main` branch execution.

## 5) Restrict release tagging

GitHub path: `Settings -> Rules -> Rulesets` (or tag protection in legacy settings)

- Protect tag pattern: `v*`
- Restrict create/update/delete tag permissions to maintainers/release managers.

## 6) Validation run (one-time)

1. Open a small PR to `dev` changing docs only.
2. Confirm required checks run and pass.
3. Merge PR to `dev`.
4. Open PR `dev -> main`; confirm staging rehearsal passed on dev.
5. Confirm required checks are enforced on `main`.
6. Merge into `main`.
7. Run workflow `Contracts Mainnet Readiness` from `main`.
8. Confirm:
   - workflow requests/uses `production` environment approvals
   - run succeeds
   - readiness artifact uploads

## 7) Ongoing operational rule

- No production deployment from `dev`.
- Production readiness + deployment sign-off only from `main`.
- Any emergency `main` hotfix must be back-merged into `dev` immediately after release.

## 8) Optional automation (API)

You can apply most settings via script:

```bash
cd /path/to/mark
export GH_PAT=<github_token_with_repo_admin_scope>
# optional:
# export GH_REPO=trade/mark
# export MAIN_REVIEW_COUNT=2
# export DEV_REVIEW_COUNT=1
# export MAIN_PUSH_ALLOW_USERS=iap
# export MAIN_PUSH_ALLOW_TEAMS=release-managers
# export CANARY_PUSH_ALLOW_USERS=iap
# export DEV_PUSH_ALLOW_USERS=iap
# export PRODUCTION_REVIEWER_IDS=12345,67890
./scripts/github/apply-governance.sh
```

What this script applies:

- `main` branch protection (PR + checks + stale review dismissal)
- `dev` branch protection (PR + checks)
- `production` environment creation
- optional production required reviewers by user ID
- optional direct-push restrictions via `*_PUSH_ALLOW_*` allowlists

## 9) Verify active protections after transfer

Run the verification script with a repo-admin token:

```bash
cd /path/to/mark
export GH_PAT=<github_token_with_repo_admin_scope>
# optional: export GH_REPO=your-org/mark
./scripts/github/verify-governance.sh
```

Expected output: both branches (`dev`, `main`) report `PASS` and required checks include CodeQL (`Analyze (javascript-typescript)`), `gitleaks / Gitleaks Scan`, and `Dependency Review`.
