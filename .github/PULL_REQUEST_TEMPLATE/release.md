## Release PR (`dev` -> `main`)

Use this template only for production candidate merges.

## Release Scope

- Release tag/version candidate:
- Commit range / PR range:
- Contracts affected:

## Required Evidence

- [ ] `Contracts Unit + Invariant` CI passed
- [ ] `Contracts Release Check (Dry-Run + Execute Smoke)` CI passed
- [ ] `Contracts Production Mode Smoke` CI passed
- [ ] `Slither Core Contracts` CI passed
- [ ] `Analyze (javascript-typescript)` CI passed
- [ ] `Gitleaks Scan` CI passed
- [ ] `Dependency Review` CI passed
- [ ] `Frontend Checks (Node 20)` CI passed
- [ ] `Frontend Checks (Node 22)` CI passed
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

## Staging Go/No-Go (Pre-Mainnet)

Reference: `contracts/STAGING_GO_NO_GO_CHECKLIST.md`

- [ ] Staging rehearsal workflow succeeded (`contracts-staging-rehearsal.yml`)
- [ ] Production-lock verify succeeded (`contracts-production-lock-verify.yml`)
- [ ] Staging evidence artifacts reviewed (`mark-staging-release`, `mark-staging-rehearsal`, `mark-production-lock-verify`)
- [ ] Freshness and lineage policy passed (`contracts-promotion-checklist.yml`)
- [ ] Final Go/No-Go decision documented with links

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
