# MARK Mainnet Runbook

This runbook is the operational source of truth for MARK (`RYLA`) deployments.

For operator sign-off before production promotion, use:

- [`STAGING_GO_NO_GO_CHECKLIST.md`](./STAGING_GO_NO_GO_CHECKLIST.md)

## 0) Branch Policy

- Production deployment and mainnet readiness checks are executed from `main` branch only.
- Development and config iteration happen on `dev` branch and feature branches.
- Merge flow is documented in `/BRANCHING.md`.

## 1) Pre-Deployment Checklist

Run the gate script from `contracts/`:

```bash
RPC_URL=<target_rpc> \
PRIVATE_KEY=<deployer_pk> \
./script/ops/mainnet-readiness.sh
```

Gate mode:

- `MARK_MAINNET_GATE_MODE=predeploy` (default)
- `MARK_MAINNET_GATE_MODE=postdeploy`
- `MARK_MAINNET_GATE_MODE=full`

The gate enforces:

- `forge test` passes
- Slither core scan passes (`--fail-medium`)
- Preflight checks pass (modes 1, 2, 3)
- Deployment verify script passes
- Release artifact is generated and schema-validated
- Env schema guard passes (`contracts-env-guard.yml`)

Do not broadcast to production if this gate fails.

### Run Readiness Gate via GitHub Actions (UI)

Workflow:

- `.github/workflows/contracts-mainnet-readiness.yml`

Steps:

1. Open Actions -> `Contracts Mainnet Readiness`.
2. Click `Run workflow`.
3. Set inputs:
   - `mode`: `predeploy` (default), `postdeploy`, or `full`
   - `rpc_url`: target network RPC endpoint
   - `artifact_path` (optional): default `broadcast/mark-mainnet-gate-ci.json`
4. Run and wait for completion.

Required repository secret:

- `MARK_DEPLOYER_PRIVATE_KEY`

Expected outputs:

- Job status is green.
- Readiness artifact is uploaded (`mark-mainnet-readiness-artifact`).

Do not run production broadcasts from CI unless your organization explicitly approves that process.

### Run Post-Deploy Production Lock Verify via GitHub Actions (UI)

Workflow:

- `.github/workflows/contracts-production-lock-verify.yml`

Inputs:

- `rpc_url`
- `token_address`
- `module_address`
- `verifier_address`
- `owner_address`
- `settlement_operator`
- `attester_address` (optional, default zero address)

Output artifact:

- `mark-production-lock-verify` (contains `mark-production-lock-verify.json`)

Optional CLI dispatch helper (from `contracts/`):

```bash
set -a && source .env && set +a
make dispatch-production-lock-verify
```

To execute dispatch (not dry-run):

```bash
set -a && source .env && set +a
DISPATCH_EXECUTE=true make dispatch-production-lock-verify
```

### Run Staging Rehearsal via GitHub Actions (UI)

Workflow:

- `.github/workflows/contracts-staging-rehearsal.yml`

Required repository secret:

- `MARK_STAGING_DEPLOYER_PRIVATE_KEY`

Result artifacts:

- `mark-staging-release`
- `mark-staging-rehearsal`

### Generate Promotion Checklist (Go/No-Go Evidence)

Workflow:

- `.github/workflows/contracts-promotion-checklist.yml`

This generates:

- `mark-promotion-checklist.json`
- `mark-promotion-checklist.md`

The checklist links latest successful:

- staging rehearsal run evidence
- mainnet readiness run evidence

Promotion policy (enforced):

- freshness: both evidence runs must be within `freshness_hours` (default `72`)
- lineage: mainnet run commit must be `identical` or `ahead` of staging run commit
- strict checks: workflow exits non-zero when any policy check fails

### Dispatch Full Evidence Sequence (CLI)

From `contracts/`:

```bash
STAGING_RPC_URL=<staging_rpc> \
STAGING_SETTLEMENT_OPERATOR=<0x_operator> \
MAINNET_RPC_URL=<mainnet_rpc> \
DISPATCH_EXECUTE=true \
WAIT_FOR_COMPLETION=true \
make dispatch-release-evidence-sequence
```

This will:

1. Dispatch `contracts-staging-rehearsal.yml`.
2. Dispatch `contracts-mainnet-readiness.yml`.
3. Wait for both to succeed.
4. Dispatch `contracts-promotion-checklist.yml` with explicit run IDs.

Safety behavior:

- run correlation uses dispatch timestamp + actor + branch filtering (reduces cross-run mismatch risk under concurrent operators)
- production dispatch/verify env validation rejects known placeholder addresses

Required repository secrets:

- `MARK_STAGING_DEPLOYER_PRIVATE_KEY`
- `MARK_DEPLOYER_PRIVATE_KEY`

Optional bootstrap helper (from `contracts/`):

```bash
MARK_STAGING_DEPLOYER_PRIVATE_KEY=<0x_staging_pk> \
MARK_DEPLOYER_PRIVATE_KEY=<0x_mainnet_pk> \
DISPATCH_EXECUTE=true \
make bootstrap-release-secrets
```

### Evidence Manifest (Hash Integrity Baseline)

Workflow:

- `.github/workflows/contracts-evidence-manifest.yml`

Local commands:

```bash
make generate-evidence-manifest
make verify-evidence-manifest
make sign-evidence-manifest
make verify-evidence-signature
```

No-Go triggers for this baseline:

- any required artifact missing
- manifest hash mismatch
- signature missing/invalid

### Operator Sign-Off Checklist

Before approving production deployment, capture:

1. Commit/tag being deployed (`MARK_GIT_COMMIT`).
2. Successful readiness gate run link (CLI logs or GitHub Actions run URL).
3. Release artifact file and hash.
4. Verify script output proving expected role/config wiring.
5. Security scan result (Slither pass).

Required approvals (minimum):

- Protocol owner/admin signer.
- Security reviewer.
- Deployment operator.

Go/No-Go decision rule:

- Go only if all checklist items are present and all approvals are recorded.
- No-Go if any verify/preflight/security check is missing or failed.
- For production settlement deployments, require `VERIFY_MARK_SETTLEMENT_PRODUCTION_MODE=true` in verify inputs and confirm verify passes.

## 2) Standard Deployment Sequence

1. Run preflight gate:

```bash
RPC_URL=<target_rpc> PRIVATE_KEY=<deployer_pk> ./script/ops/mainnet-readiness.sh
```

2. Run release orchestrator:

```bash
set -a && source .env && set +a
MARK_RELEASE_EXECUTE=true MARK_RELEASE_WRITE_ARTIFACT=true \
forge script script/ops/settlement/ReleaseMARK.s.sol --rpc-url $RPC_URL --broadcast
```

3. Run post-deploy verify:

```bash
set -a && source .env && set +a
forge script script/ops/settlement/VerifyMARKDeployment.s.sol --rpc-url $RPC_URL
```

4. Run production lock assurance:

```bash
set -a && source .env && set +a
make verify-production-lock
```

## 3) Verify Failure Playbook

Condition: `VerifyMARKDeployment` fails after broadcast.

Actions:

1. Stop all further broadcasts.
2. Record failing assertion and tx hashes.
3. If issue is role/config only:
   - fix deterministically with `PostDeployMARKSetup.s.sol`
   - re-run verify
4. If issue is ownership/admin mismatch:
   - do not continue
   - execute admin correction via delayed transfer flow
5. If issue cannot be safely corrected:
   - treat deployment as failed
   - redeploy clean stack

## 4) Wrong Config / Wrong Address Playbook

Condition: wrong env values, wrong target address, wrong chain, or wrong operator.

Actions:

1. Stop deployment immediately.
2. Revoke accidental operational roles from incorrect addresses.
3. Re-run preflight with corrected env.
4. Re-run release only after preflight + verify are green.

## 5) Operator Key Compromise Playbook

Condition: suspected compromise of bridge/settlement operator key.

Actions:

1. Revoke compromised operator role(s) immediately:
   - `MARKBridgeAdapter.setOperator(compromised, false)`
   - `MARKSettlementModule.setOperator(compromised, false)`
2. Rotate to new operator key(s).
3. Re-run verify to confirm clean role state.
4. If admin key may also be compromised:
   - start delayed default admin transfer to secure key
   - accept after delay
   - re-verify all contracts

## 6) Default Admin Rotation (Delayed)

1. Current admin schedules transfer:

```bash
cast send <CONTRACT> "beginDefaultAdminTransfer(address)" <newAdmin> --private-key $OLD_ADMIN_PK
```

2. Wait at least `defaultAdminDelay()` (expected: 1 day).
3. New admin accepts:

```bash
cast send <CONTRACT> "acceptDefaultAdminTransfer()" --private-key $NEW_ADMIN_PK
```

4. Re-run verify script.

Optional cancel before acceptance:

```bash
cast send <CONTRACT> "cancelDefaultAdminTransfer()" --private-key $OLD_ADMIN_PK
```

## 7) Rollback Decision Rule

Rollback is mandatory if either is true:

- Verify cannot be made green with deterministic post-deploy setup.
- Privileged roles/admin are not provably under expected control.

When rollback is triggered:

1. Freeze further changes.
2. Revoke unsafe operators/attesters.
3. Redeploy from clean, verified env snapshot.
4. Re-run full readiness gate.

## 8) Trust Model

This section documents the trust assumptions, key custody model, and break-glass procedures for the MARK protocol. Auditors and operators should read this before reviewing or operating the contracts.

### Key Roles and Trust Assumptions

**Default Admin** (`DEFAULT_ADMIN_ROLE`)

- Held by the protocol deployer address on all three contracts: `RYLA`, `MARKBridgeAdapter`, `MARKSettlementModule`.
- Controls role grants/revokes, verifier configuration, bridge limits, and production mode activation.
- Protected by a 1-day delay (`AccessControlDefaultAdminRules`): admin transfers cannot take effect for at least 24 hours after initiation.
- Trust assumption: the admin key is held by the protocol owner in a hardware wallet or equivalent secure storage. Compromise of this key is the highest-severity incident.

**Operator** (`OPERATOR_ROLE` on bridge and settlement)

- Submits bridge transactions and settlement intents.
- Can move tokens cross-chain (bridge) and trigger mint/burn (settlement).
- Trust assumption: operator keys are hot keys used by the protocol's backend. They are scoped to operational actions only — they cannot change configuration, rotate roles, or disable proof validation.
- Rotation: use section 5 (Operator Key Compromise Playbook) if compromised.

**Attester** (`ATTESTER_ROLE` on `AttestedSettlementVerifier`)

- Signs settlement attestations that authorize mint/burn operations when proof validation is enabled.
- Trust assumption: the attester key is a hot signing key. Its compromise allows fraudulent settlement attestations until revoked.
- Rotation policy: see Attester Key Rotation below.

**Minter / Burner** (`MINTER_ROLE`, `BURNER_ROLE` on `RYLA`)

- Held exclusively by `MARKSettlementModule`. Not held by any EOA in production.
- Trust assumption: the settlement module is the only authorized issuer. Direct mint/burn by any EOA is not permitted.

### Attester Key Rotation

Rotate the attester key if:

- Key material may have been exposed.
- Signing infrastructure is being migrated.
- Scheduled rotation policy requires it.

Steps:

1. Generate new attester key in secure environment.
2. Grant new attester role before revoking old:

```bash
cast send <VERIFIER> "setAttester(address,bool)" <newAttester> true --private-key $ADMIN_PK
```

3. Verify new attester is active.
4. Revoke old attester:

```bash
cast send <VERIFIER> "setAttester(address,bool)" <oldAttester> false --private-key $ADMIN_PK
```

5. Re-run verify script to confirm clean attester state.

Note: there is a 1-day admin delay on the admin key itself, but `setAttester` is callable immediately by the current admin. Rotation is instant once the admin key is available.

### Break-Glass Procedure

Use this procedure when normal operational controls are insufficient — for example, if a critical vulnerability is discovered post-deployment.

**Step 1: Contain**

- Revoke all operator roles on bridge and settlement immediately (section 5).
- Revoke all attester roles on the verifier.
- This stops new settlements and bridge operations without requiring admin key rotation.

**Step 2: Assess**

- Determine whether the vulnerability is in contract logic or in key material.
- If key material: proceed to admin rotation (section 6).
- If contract logic: assess whether existing deployed state is safe to leave in place while a fix is prepared.

**Step 3: Communicate**

- Use GitHub private vulnerability reporting (see `SECURITY.md`) to coordinate disclosure.
- Do not deploy fixes to production without re-running the full mainnet readiness gate.

**Step 4: Recover**

- If redeployment is required: follow section 7 (Rollback Decision Rule).
- If configuration fix is sufficient: use `PostDeployMARKSetup.s.sol` and re-run verify.

### Production Mode Implications

Once `activateProductionMode()` is called on `MARKSettlementModule`:

- Proof validation cannot be disabled.
- The verifier address cannot be set to zero.
- This is irreversible.

Before activating production mode, confirm:

- The attester key is in secure, long-term storage.
- The verifier contract has been audited.
- The admin key is in a hardware wallet or equivalent.
- If using `Groth16SettlementVerifier`:
  - `settlementModule` is bound to the deployed module.
  - `MARK_SETTLEMENT_GROTH16_DIRECTION_ENFORCEMENT` matches your proof format.
  - Direction rollout has been completed (below) before enabling production mode.

### Groth16 Direction Rollout (Required If Using Groth16SettlementVerifier)

Goal: enforce `isMint` at proof-signal level without breaking legacy proofs during migration.

1. Deploy or reconfigure verifier/module binding:
   - Use `DeployMARKSettlementModule.s.sol` or `PostDeployMARKSetup.s.sol`.
   - Ensure `MARK_SETTLEMENT_VERIFIER=<groth16_verifier_address>`.
2. Start in compatibility mode:
   - `MARK_SETTLEMENT_GROTH16_DIRECTION_ENFORCEMENT=false`
   - Expected proof mapping: `signals[7] == 0`.
3. Upgrade prover/circuit output:
   - mint proofs use `signals[7] = 1`
   - burn proofs use `signals[7] = 0`
4. Validate in staging:
   - run settlement tests and `VerifyMARKDeployment.s.sol`.
5. Enable strict mode:
   - `MARK_SETTLEMENT_GROTH16_DIRECTION_ENFORCEMENT=true`
6. Re-run verify and only then lock production mode:
   - `MARK_SETTLEMENT_PRODUCTION_MODE=true`

No-Go rule:

- Do not enable production mode with Groth16 if strict direction expectations are ambiguous or untested in staging.

### Key Storage Recommendations

| Key                 | Recommended storage             | Rotation frequency                  |
| ------------------- | ------------------------------- | ----------------------------------- |
| Default admin       | Hardware wallet (Ledger/Trezor) | On compromise or scheduled annually |
| Operator            | HSM or secure server key        | On compromise or quarterly          |
| Attester            | HSM or secure server key        | On compromise or quarterly          |
| Deployer (one-time) | Hardware wallet                 | N/A after deployment                |
