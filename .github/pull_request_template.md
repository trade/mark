# Summary

Describe the change and why it is needed.

## Scope

- [ ] Contracts
- [ ] Scripts/ops
- [ ] Workflows/CI
- [ ] Docs/runbook

## Verification

- [ ] `pnpm review` passes locally (or `pnpm review:quick` for quick checks)
- [ ] `forge build` passes locally
- [ ] `forge test` passes locally
- [ ] If contracts changed: slither scan reviewed
- [ ] No secrets/private keys added
- [ ] Commits signed with GPG key (for code contributions)

**CI Output** (paste relevant output):

```
# Example:
# ✅ typecheck (2.01 seconds)
# ✅ lint (4.12 seconds)
# ✅ forge test: 159 tests passed
```

## Risk Review

- [ ] Access control changes reviewed
- [ ] Upgrade/deployment behavior reviewed
- [ ] Backward compatibility impact reviewed
- [ ] No unintended changes to production deployment flow

## Governance

- [ ] Target branch is correct (`dev` for normal work, `main` for production release PR)
- [ ] CODEOWNER review requested
- [ ] Relevant runbook/docs updated

## Linked Context

- Issue / task:
- Related PRs:
