# Staging Go/No-Go Checklist

Use this checklist before any `canary -> main` promotion. Local Anvil checks are required, but final confidence must come from a real staging network rehearsal.

## Scope

- Target: Optimism staging/testnet (for example OP Sepolia).
- Branch source: `canary` commit intended for promotion.
- Governance model: use the same Safe / role model planned for mainnet.

## Required Inputs

- `STAGING_RPC_URL`
- `MARK_STAGING_DEPLOYER_PRIVATE_KEY` (GitHub secret)
- staging operator address (`STAGING_SETTLEMENT_OPERATOR`)
- expected admin/owner/verifier/attester addresses

## Execution Steps

1. Validate environment and config schema:
```bash
cd contracts
VALIDATE_MODE=rehearsal make validate-prod-env
```

2. Run local baseline gates (must be green):
```bash
make ci-full
make slither-core
```

3. Run staging rehearsal workflow:
- GitHub Actions: `.github/workflows/contracts-staging-rehearsal.yml`
- Confirm artifacts:
  - `mark-staging-release`
  - `mark-staging-rehearsal`

4. Run post-deploy production-lock verify:
- GitHub Actions: `.github/workflows/contracts-production-lock-verify.yml`
- Confirm artifact: `mark-production-lock-verify`

5. Run functional rehearsal on staging:
- settlement mint (valid proof path)
- settlement burn (escrow + burn invariants)
- bridge flow with destination allowlist and limit checks
- operator/attester rotation and re-verify

6. Generate promotion checklist evidence:
- GitHub Actions: `.github/workflows/contracts-promotion-checklist.yml`
- Confirm freshness + lineage policy passes.

## Go Criteria

- All required CI checks pass on promotion commit.
- Staging rehearsal + production-lock verify pass.
- Evidence artifacts are present, reviewed, and hashed.
- Role/config verify outputs match expected addresses.
- Security reviewer + operator + admin signer approvals recorded.

## No-Go Triggers

- Any failed verify/preflight/security gate.
- Evidence missing or stale.
- Address/role mismatch vs planned production config.
- Unresolved incident drill or key-rotation concern.
