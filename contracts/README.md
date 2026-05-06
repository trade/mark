# Contracts

Smart contracts for Superchain interoperability and `RYLA` standard credit primitives.

Operational procedures (deployment, incident, rollback) are documented in [RUNBOOK.md](./RUNBOOK.md).

## Contracts

### [RYLA.sol](./src/token/RYLA.sol)

- Superchain-compatible ERC-7802 token (mint/burn on bridge is enforced by `SuperchainTokenBridge`)
- Market symbol: `RYLA`
- `MINTER_ROLE` / `BURNER_ROLE` for protocol issuance modules
- Uses `AccessControlDefaultAdminRules` for delayed default-admin transfer hardening

### [MARKBridgeAdapter.sol](./src/bridge/MARKBridgeAdapter.sol)

- Operator-gated bridge-out adapter that routes through `SuperchainTokenBridge`
- Destination allowlist and optional `maxPerTx` / `dailyCap` risk limits
- Keeps token core bridge authority on the canonical predeploy
- Uses `AccessControlDefaultAdminRules` (`OPERATOR_ROLE`)

### [MARKSettlementModule.sol](./src/settlement/MARKSettlementModule.sol)

- Phase-2 integration boundary for UTXO / zk accounting
- Operator-gated settlement with replay protection (`intentId`)
- Optional external proof verifier hook (`IUTXOSettlementVerifier`)
- Holds token minter/burner roles for controlled mint and burn settlement
- Uses `AccessControlDefaultAdminRules` (`OPERATOR_ROLE`)

### [AttestedSettlementVerifier.sol](./src/settlement/verifier/AttestedSettlementVerifier.sol)

- Signature-based settlement verifier (`ATTESTER_ROLE` allowlist)
- Intended as a concrete verifier baseline before integrating zk circuits
- Uses OZ `ECDSA` + `MessageHashUtils`
- Binds signed proofs to settlement module address (prevents cross-module replay)
- Proof format:
  - `abi.encode(uint256 deadline, bytes32 contextHash, uint8 v, bytes32 r, bytes32 s)`

## Development

Note: legacy CrossChainCounter example contracts and tests were retired in favor of MARK protocol deployment/ops flows. Current CI and release gates focus on MARK stack contracts and governance evidence artifacts.

### Dependencies

```bash
forge install
```

### Build

```bash
forge build
```

### Test

```bash
forge test
```

Run the fast local CI checks (recommended during iteration):

```bash
make ci-fast
```

Run the full local CI checks (includes explicit production-lock checks):

```bash
make ci-full
```

Run canonical release gate checks and emit a timestamped evidence artifact:

```bash
make release-gate
```

For remote/mainnet-style verification, run with:
- `RPC_URL` and `PRIVATE_KEY`
- anchored release artifact via `MARK_RELEASE_VERIFY_ARTIFACT_PATH` or `MARK_RELEASE_ARTIFACT_PATH`
- signed evidence verification inputs (default-on):
  - `VERIFY_PUBLIC_KEY_FILE` or `VERIFY_PUBLIC_KEY_PEM`
  - optional manifest path overrides:
    - `MARK_RELEASE_VERIFY_MANIFEST_PATH`
    - `MARK_RELEASE_VERIFY_SIGNATURE_PATH`
    - `MARK_RELEASE_VERIFY_SIGNATURE_META_PATH`

Set `MARK_RELEASE_VERIFY_REQUIRE_SIGNED_MANIFEST=false` only for controlled break-glass scenarios.

```bash
MARK_RELEASE_GATE_MODE=remote make release-gate
```

Run integration (fork/RPC-dependent) tests only:

```bash
CHAIN_A_RPC_URL=http://127.0.0.1:9545 \
CHAIN_B_RPC_URL=http://127.0.0.1:9546 \
FOUNDRY_PROFILE=integration forge test --match-path 'test/integration/**/*.t.sol'
```

### Deploy

Deploy to multiple chains using either:

1. Super CLI (recommended):

```bash
cd ../ && pnpm sup
```

2. Direct Forge script (MARK stack):

```bash
set -a && source .env && set +a
forge script script/deploy/bridge/DeployMARKStack.s.sol --rpc-url $RPC_URL --broadcast
```

Deploy `RYLA` stack:

```bash
set -a && source .env && set +a
forge script script/deploy/bridge/DeployMARKStack.s.sol --rpc-url $RPC_URL --broadcast
```

Deploy settlement module:

```bash
set -a && source .env && set +a
forge script script/deploy/settlement/DeployMARKSettlementModule.s.sol --rpc-url $RPC_URL --broadcast
```

Deploy settlement module with in-script attested verifier:

```bash
set -a && source .env && set +a
forge script script/deploy/settlement/DeployMARKSettlementModule.s.sol --rpc-url $RPC_URL --broadcast
```

### Post-Deploy Setup

Apply deterministic role/config setup on already deployed contracts:

```bash
set -a && source .env && set +a
forge script script/ops/settlement/PostDeployMARKSetup.s.sol --rpc-url $RPC_URL --broadcast
```

### Preflight (Recommended Before Broadcast)

Run read-only checks to validate env wiring and admin permissions before deployment/setup:

```bash
set -a && source .env && set +a
forge script script/ops/settlement/PreflightMARKDeployment.s.sol --rpc-url $RPC_URL
```

`MARK_PREFLIGHT_MODE` values:
- `1` => checks for `DeployMARKStack.s.sol`
- `2` => checks for `DeployMARKSettlementModule.s.sol`
- `3` => checks for `PostDeployMARKSetup.s.sol`

### Release Orchestrator

Run full release pipeline (preflight -> deploy -> optional setup -> verify -> artifact):

```bash
set -a && source .env && set +a
forge script script/ops/settlement/ReleaseMARK.s.sol --rpc-url $RPC_URL
```

Local production-mode smoke (starts Anvil, deploys verifier, runs strict release verify):

```bash
make smoke-production-mode
```

Control behavior with:
- `MARK_RELEASE_EXECUTE=false` for dry-run (no broadcast)
- `MARK_RELEASE_EXECUTE=true` for execution
- `MARK_RELEASE_RUN_POSTDEPLOY=true` to run `PostDeployMARKSetup` after deployment
- `MARK_RELEASE_WRITE_ARTIFACT=true` to write JSON artifact (requires Foundry FS write permission)
- `MARK_RELEASE_ARTIFACT_PATH` for JSON output path
- `MARK_GIT_COMMIT` to tag artifact with commit id
- `MARK_RELEASE_STRICT_VERIFY=true` to require explicit `VERIFY_MARK_SETTLEMENT_*` expectations during execute-mode verify
- `MARK_SETTLEMENT_PRODUCTION_MODE=true` to lock settlement verifier/proof validation configuration in production

### Mainnet Readiness Gate

Run the full pre-mainnet gate in one command:

```bash
RPC_URL=<target_rpc> \
PRIVATE_KEY=<deployer_pk> \
./script/ops/mainnet-readiness.sh
```

Gate mode is controlled by `MARK_MAINNET_GATE_MODE`:
- `predeploy` (default): tests + slither + preflight + dry-run artifact
- `postdeploy`: verify-only checks against deployed contracts
- `full`: predeploy checks + postdeploy verify + dry-run artifact

This gate enforces (by mode):
- contract tests pass
- slither scan pass
- preflight pass (all modes)
- deployment verify pass
- release artifact generation + schema validation

Manual CI entrypoint:
- `.github/workflows/contracts-mainnet-readiness.yml` (`workflow_dispatch`)

### Post-Deploy Verify

Run read-only checks against deployed contracts and role wiring:

```bash
set -a && source .env && set +a
forge script script/ops/settlement/VerifyMARKDeployment.s.sol --rpc-url $RPC_URL
```

Optional strict checks supported by verify script:
- `VERIFY_MARK_BRIDGE_MAX_PER_TX` / `VERIFY_MARK_BRIDGE_DAILY_CAP`
- Verifier admin check via `VERIFY_MARK_RYLA_OWNER` when `VERIFY_MARK_SETTLEMENT_VERIFIER` is set
- Verifier attester check via `VERIFY_MARK_SETTLEMENT_ATTESTER`
- Settlement production lock expectation via `VERIFY_MARK_SETTLEMENT_PRODUCTION_MODE`

Run production lock post-deploy assurance (read-only checks):

```bash
set -a && source .env && set +a
make verify-production-lock
```

Manual CI entrypoint for post-deploy production checks:
- `.github/workflows/contracts-production-lock-verify.yml` (`workflow_dispatch`)

Dispatch helper (auto-fills workflow inputs from env/artifact):

```bash
set -a && source .env && set +a
make dispatch-production-lock-verify
```

By default this is dry-run only. To actually dispatch:

```bash
set -a && source .env && set +a
DISPATCH_EXECUTE=true make dispatch-production-lock-verify
```

Dispatch full evidence sequence (staging rehearsal -> mainnet readiness -> promotion checklist):

```bash
STAGING_RPC_URL=<staging_rpc> \
STAGING_SETTLEMENT_OPERATOR=<0x_operator> \
MAINNET_RPC_URL=<mainnet_rpc> \
DISPATCH_EXECUTE=true \
WAIT_FOR_COMPLETION=true \
make dispatch-release-evidence-sequence
```

Notes:
- dispatcher resolves run IDs using `workflow_dispatch` + actor + branch + dispatch timestamp filters (safer under concurrent runs)
- production dispatch/verify paths enforce `MARK_ENV_STRICT_PLACEHOLDERS=true` to block known placeholder addresses

Required GitHub secrets for this sequence:
- `MARK_STAGING_DEPLOYER_PRIVATE_KEY`
- `MARK_DEPLOYER_PRIVATE_KEY`

Bootstrap those secrets from local env values (dry-run by default):

```bash
MARK_STAGING_DEPLOYER_PRIVATE_KEY=<0x_staging_pk> \
MARK_DEPLOYER_PRIVATE_KEY=<0x_mainnet_pk> \
DISPATCH_EXECUTE=true \
make bootstrap-release-secrets
```

Staging rehearsal (release + production-lock verify):

```bash
set -a && source .env && set +a
make rehearse-production-lock
```

Manual CI entrypoint for staging rehearsal:
- `.github/workflows/contracts-staging-rehearsal.yml` (`workflow_dispatch`)

Promotion checklist generator (links latest successful staging rehearsal + mainnet readiness):

```bash
make generate-promotion-checklist
```

Policy defaults:
- freshness window: `72` hours (`FRESHNESS_HOURS`)
- lineage: mainnet commit must be `identical` or `ahead` vs staging commit
- strict mode: fails command/workflow when any check fails (`STRICT_PROMOTION_CHECKS=true`)

Manual CI entrypoint:
- `.github/workflows/contracts-promotion-checklist.yml` (`workflow_dispatch`)

Environment safety precheck utility:

```bash
VALIDATE_MODE=rehearsal make validate-prod-env
```

Supported modes:
- `rehearsal`
- `dispatch`
- `verify-lock`

Canonical env profiles:
- `config/profiles/staging.env`
- `config/profiles/mainnet.env`

CI env schema guard entrypoint:
- `.github/workflows/contracts-env-guard.yml`

Evidence manifest tooling:

```bash
make generate-evidence-manifest
make verify-evidence-manifest
make sign-evidence-manifest
make verify-evidence-signature
```

CI/manual entrypoint:
- `.github/workflows/contracts-evidence-manifest.yml`

### Deployment Config

- Copy `.env.example` to `.env` and fill all required deploy/verify values.
- Use MARK-prefixed keys (`MARK_*`, `VERIFY_MARK_*`) for all deploy and verify scripts.
- Network-specific templates are in:
  - `config/networks/optimism-mainnet.env.example`
  - `config/networks/optimism-sepolia.env.example`

## Admin Runbook

All RYLA contracts use `AccessControlDefaultAdminRules` with a 1-day admin delay.

### Grant operational roles

```bash
# Examples via cast:
# cast send <RYLA> "setMinter(address,bool)" <module> true --private-key $PK
# cast send <RYLA> "setBurner(address,bool)" <module> true --private-key $PK
# cast send <BRIDGE_ADAPTER> "setOperator(address,bool)" <operator> true --private-key $PK
# cast send <SETTLEMENT_MODULE> "setOperator(address,bool)" <operator> true --private-key $PK
# cast send <ATTESTED_VERIFIER> "setAttester(address,bool)" <attester> true --private-key $PK
```

### Rotate default admin (delayed)

Step 1: current admin starts transfer

```bash
# cast send <CONTRACT> "beginDefaultAdminTransfer(address)" <newAdmin> --private-key $OLD_ADMIN_PK
```

Step 2: wait at least `defaultAdminDelay()` (1 day)

Step 3: new admin accepts transfer

```bash
# cast send <CONTRACT> "acceptDefaultAdminTransfer()" --private-key $NEW_ADMIN_PK
```

Optional: cancel pending transfer before acceptance

```bash
# cast send <CONTRACT> "cancelDefaultAdminTransfer()" --private-key $OLD_ADMIN_PK
```

## Architecture

### MARK Settlement Flow

1. Operators submit settlement intents through `MARKSettlementModule`.
2. Optional verifier (`AttestedSettlementVerifier` or custom `IUTXOSettlementVerifier`) validates intent proof material.
3. Settlement module mints/burns `RYLA` under role-constrained rules.
4. Bridge adapter enforces destination/risk controls for cross-chain transfers.

## Testing

Tests are in `test/` directory:

- Unit tests for token/protocol/verifier and deploy scripts
- Invariant tests for settlement supply and authorization safety
- Integration tests (in `test/integration/`) are isolated from default runs

```bash
forge test
```

## Security Analysis

Run Slither locally on MARK core contracts:

```bash
cd contracts
make slither-install
export PATH="$HOME/Library/Python/3.9/bin:$PATH"
make slither-core
```

CI workflow:
- `.github/workflows/contracts-slither.yml`

## License

MIT
