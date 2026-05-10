.PHONY: ci-local ci-fast ci-full test-core test-invariants release-gate release-gate-container architecture-guard layering-guard smoke-production-mode test-production-lock verify-production-lock dispatch-production-lock-verify dispatch-release-evidence-sequence bootstrap-release-secrets rehearse-production-lock generate-promotion-checklist validate-prod-env validate-prod-env-all generate-evidence-manifest verify-evidence-manifest sign-evidence-manifest verify-evidence-signature slither-install slither-core

# Fast local loop: guards + unit/e2e tests (excludes invariants and integration profile tests).
ci-fast: architecture-guard layering-guard test-core

test-core:
	@FOUNDRY_OFFLINE=true forge test --no-match-path 'test/invariant/**' -q

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
	@python3 -m pip install --user slither-analyzer==0.11.5

slither-core:
	@command -v slither >/dev/null 2>&1 || { \
	  echo "slither not found in PATH. Try: export PATH=\"$$HOME/Library/Python/3.9/bin:$$PATH\""; \
	  echo "or run: make slither-install"; \
	  exit 1; \
	}
	@for target in \
	  src/token/RYLA.sol \
	  src/bridge/MARKBridgeAdapter.sol \
	  src/settlement/MARKSettlementModule.sol \
	  src/settlement/verifier/AttestedSettlementVerifier.sol; \
	do \
	  slither "$$target" \
	    --solc-remaps "@interop-lib/=lib/interop-lib/src/ @openzeppelin/=lib/createx/lib/openzeppelin-contracts/" \
	    --exclude-dependencies \
	    --exclude "naming-convention,timestamp,arbitrary-send-erc20,reentrancy-balance,reentrancy-benign" \
	    --filter-paths "lib|test|script|out|cache" \
	    --fail-medium; \
	done
