## Release PR (`canary` -> `main`)

Use this template only for production candidate merges.

## Release Scope

- Release tag/version candidate:
- Commit range / PR range:
- Contracts affected:

## Required Evidence

- [ ] `Contracts Unit + Invariant` CI passed
- [ ] `Contracts Release Check (Dry-Run + Execute Smoke)` CI passed
- [ ] `Slither Core Contracts` CI passed
- [ ] `Contracts Mainnet Readiness` run from `main` branch
- [ ] Readiness artifact uploaded and reviewed
- [ ] Verify output reviewed (role/config expectations)

Evidence links/values:
- Mainnet readiness run URL:
- Readiness artifact SHA256:

## Security + Ops Sign-off

- [ ] Protocol owner/admin signer approval
- [ ] Security reviewer approval
- [ ] Deployment operator approval

## Deployment Inputs

- RPC target:
- Artifact path:
- `MARK_GIT_COMMIT` value:
- Environment used: `production`

## Go / No-Go

- [ ] Go
- [ ] No-Go (reason)

## Post-Merge Plan

- [ ] Run/confirm deployment sequence in `contracts/RUNBOOK.md`
- [ ] Tag release on `main`
- [ ] Back-merge any hotfixes into `dev` (if applicable)
