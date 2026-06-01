.PHONY: ci-local ci-fast ci-full test-core test-invariants release-gate release-gate-container architecture-guard layering-guard size-guard semgrep smoke-production-mode test-production-lock verify-production-lock dispatch-production-lock-verify dispatch-release-evidence-sequence bootstrap-release-secrets rehearse-production-lock generate-promotion-checklist validate-prod-env validate-prod-env-all generate-evidence-manifest verify-evidence-manifest sign-evidence-manifest verify-evidence-signature slither-install slither-core gas-snapshot gas-check

# Fast local loop: guards + bytecode budget + unit/e2e tests (excludes invariants and integration profile tests).
ci-fast: architecture-guard layering-guard size-guard test-core

test-core:
	@FOUNDRY_OFFLINE=true forge test --no-match-path 'test/{invariant,integration}/**' -q

test-invariants:
	@FOUNDRY_OFFLINE=true FOUNDRY_INVARIANT_RUNS=64 forge test --match-path 'test/invariant/**/*.t.sol' -q

# Full local gate: fast checks + invariants + explicit production lock regression checks.
ci-full: ci-fast test-invariants
	@$(MAKE) test-production-lock

# Backward-compatible alias for local usage.
ci-local: ci-fast

release-gate:
	@./script/ci/release-gate.sh

release-gate-container:
	@./script/ci/run-release-gate-container.sh

architecture-guard:
	@./script/ci/architecture-guard.sh

layering-guard:
	@./script/ci/layering-guard.sh

size-guard:
	@./script/ci/size-guard.sh

semgrep:
	@command -v semgrep >/dev/null 2>&1 || { \
	  echo "semgrep not found. Install: pip install semgrep"; \
	  exit 1; \
	}
	@semgrep --config .semgrep.yml --quiet

smoke-production-mode:
	@./script/ops/smoke-production-mode.sh

test-production-lock:
	@forge test --match-contract MARKSettlementModuleTest --match-test ProductionMode -vv
	@forge test --match-contract PreflightMARKDeploymentTest --match-test ProductionMode -vv
	@forge test --match-contract PostDeployMARKSetupTest --match-test ProductionMode -vv

verify-production-lock:
	@./script/ops/verify-production-lock.sh

dispatch-production-lock-verify:
	@./script/ops/dispatch-production-lock-verify.sh

dispatch-release-evidence-sequence:
	@./script/ops/dispatch-release-evidence-sequence.sh

bootstrap-release-secrets:
	@./script/ops/bootstrap-release-secrets.sh

rehearse-production-lock:
	@./script/ops/rehearse-production-lock.sh

generate-promotion-checklist:
	@./script/ops/generate-promotion-checklist.sh

validate-prod-env:
	@./script/ops/validate-prod-env.sh

validate-prod-env-all:
	@set -a; source config/profiles/staging.env; set +a; \
	  MARK_RELEASE_EXECUTE=true MARK_SETTLEMENT_PROOF_ENABLED=true MARK_SETTLEMENT_PRODUCTION_MODE=true MARK_DEPLOY_ATTESTED_VERIFIER=true VALIDATE_MODE=rehearsal ./script/ops/validate-prod-env.sh
	@set -a; source config/profiles/mainnet.env; set +a; \
	  VALIDATE_MODE=dispatch ./script/ops/validate-prod-env.sh
	@set -a; source config/profiles/mainnet.env; set +a; \
	  VALIDATE_MODE=verify-lock ./script/ops/validate-prod-env.sh

generate-evidence-manifest:
	@./script/ops/generate-evidence-manifest.sh

verify-evidence-manifest:
	@./script/ops/verify-evidence-manifest.sh

sign-evidence-manifest:
	@./script/ops/sign-evidence-manifest.sh

verify-evidence-signature:
	@./script/ops/verify-evidence-signature.sh

slither-install:
	@python3 -m venv .venv
	@.venv/bin/python3 -m pip install --upgrade pip
	@.venv/bin/python3 -m pip install slither-analyzer==0.11.5

slither-core:
	@.venv/bin/python3 -m slither --version >/dev/null 2>&1 || { \
	  echo "slither not found in .venv. Run: make slither-install"; \
	  exit 1; \
	}
	# Per-contract exclusion rationale:
	# naming-convention  — SCREAMING_SNAKE_CASE immutables are intentional (all contracts)
	# timestamp          — block.timestamp used only for root expiry windows, not randomness (all)
	# arbitrary-send-erc20 — transferFrom requires prior approval from the token holder (bridge, settlement, ledger)
	# reentrancy-balance — false positive on settlement module balance checks
	# reentrancy-benign  — benign reentrancy paths with no exploitable state (settlement + pool)
	# incorrect-return   — false positive on PoseidonT3 assembly return (correct EVM usage)
	# assembly           — PoseidonT3 uses inline assembly by design (ZK hash function)
	# arbitrary-send-eth — MARKWithdrawAdapter sends ETH to recipient by design (withdrawal adapter)
	# missing-zero-check — false positive: recipient checked in _validateWithdrawRequest before ETH send
	# low-level-calls    — .call{value} is intentional (supports contract recipients)
SLITHER_CMD := python3 -m slither
SLITHER_REMAPS := @interop-lib/=lib/interop-lib/src/ @openzeppelin/=lib/createx/lib/openzeppelin-contracts/
SLITHER_FLAGS := --exclude-dependencies --filter-paths lib|test|script|out|cache --fail-medium
SLITHER_BASE_EXCLUDES := naming-convention,timestamp
	@$(SLITHER_CMD) src/token/RYLA.sol --solc-remaps "$(SLITHER_REMAPS)" $(SLITHER_FLAGS) --exclude "$(SLITHER_BASE_EXCLUDES)"
	@$(SLITHER_CMD) src/bridge/MARKBridgeAdapter.sol --solc-remaps "$(SLITHER_REMAPS)" $(SLITHER_FLAGS) --exclude "$(SLITHER_BASE_EXCLUDES),arbitrary-send-erc20"
	@$(SLITHER_CMD) src/settlement/MARKSettlementModule.sol --solc-remaps "$(SLITHER_REMAPS)" $(SLITHER_FLAGS) --exclude "$(SLITHER_BASE_EXCLUDES),arbitrary-send-erc20,reentrancy-balance,reentrancy-benign"
	@$(SLITHER_CMD) src/settlement/verifier/AttestedSettlementVerifier.sol --solc-remaps "$(SLITHER_REMAPS)" $(SLITHER_FLAGS) --exclude "$(SLITHER_BASE_EXCLUDES)"
	@$(SLITHER_CMD) src/settlement/verifier/Groth16SettlementVerifier.sol --solc-remaps "$(SLITHER_REMAPS)" $(SLITHER_FLAGS) --exclude "$(SLITHER_BASE_EXCLUDES)"
	@$(SLITHER_CMD) src/pool/MARKPool.sol --solc-remaps "$(SLITHER_REMAPS)" $(SLITHER_FLAGS) --exclude "$(SLITHER_BASE_EXCLUDES),reentrancy-benign,incorrect-return,assembly"
	@$(SLITHER_CMD) src/pool/RYLACreditLedger.sol --solc-remaps "$(SLITHER_REMAPS)" $(SLITHER_FLAGS) --exclude "$(SLITHER_BASE_EXCLUDES),arbitrary-send-erc20"
	@$(SLITHER_CMD) src/withdraw/MARKWithdrawAdapter.sol --solc-remaps "$(SLITHER_REMAPS)" $(SLITHER_FLAGS) --exclude "$(SLITHER_BASE_EXCLUDES),arbitrary-send-eth,missing-zero-check,low-level-calls"

gas-snapshot:
	@echo "Generating gas snapshot (excluding invariants)..."
	@forge snapshot --snap .gas-snapshot --nmp "test/{invariant,integration}/**"
	@echo "Gas snapshot saved to .gas-snapshot"

gas-check:
	@echo "Checking gas snapshot (tolerance: 2%, excluding invariants)..."
	@forge snapshot --check --snap .gas-snapshot --tolerance 2 --nmp "test/{invariant,integration}/**"
