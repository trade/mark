# Security Next Steps

Date: May 5, 2026.

## Immediate next step

Transfer the repo to your organization, then run:

```bash
export GH_PAT=<repo_admin_token>
./scripts/github/pretransfer-readiness.sh
./scripts/github/posttransfer-bootstrap.sh
```

This is the fastest path to enforced controls.

## Lean sequence

1. Enforce required checks and branch protections (`dev`, `canary`, `main`).
2. Confirm CodeQL, Gitleaks, Release Gate Container, and Scripts CI are merge-blocking.
3. Keep release-gate execution containerized.
4. Rotate/split credentials by environment and role.
5. Re-run governance verification on schedule.
