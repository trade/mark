# Transfer Now Checklist (Do This Now)

Date: May 5, 2026.

## Short answer

Yes — based on current status, you should transfer the repo to your organization now.

## Execute in order

1. Pre-check before transfer:

```bash
export GH_PAT=<repo_admin_token>
# optional: export GH_REPO=<owner>/<repo>
./scripts/github/pretransfer-readiness.sh
```

2. Transfer the repository to your organization in GitHub settings.

3. Immediately run post-transfer bootstrap:

```bash
export GH_PAT=<repo_admin_token>
# optional: export GH_REPO=<org>/<repo>
./scripts/github/posttransfer-bootstrap.sh
```

4. Add/confirm required secret in new org repo:
- `GOVERNANCE_VERIFY_PAT`

5. Trigger and confirm these workflows on a small PR:
- `CodeQL` (`Analyze (JavaScript/TypeScript)`)
- `Secrets Scan` (`Gitleaks Scan`)
- `Contracts Release Gate (Containerized)` (`Release Gate Container`)
- `Scripts CI` (`Shellcheck Scripts`)

6. Confirm branch protection required checks in GitHub UI match policy docs.

## If something fails

- Run `./scripts/github/verify-governance.sh` and fix missing checks/protections.
- Re-run `./scripts/github/posttransfer-bootstrap.sh` after corrections.

## Done criteria

- Transfer completed.
- Governance apply+verify passes.
- Required checks are merge-blocking on `dev`, `canary`, and `main`.
