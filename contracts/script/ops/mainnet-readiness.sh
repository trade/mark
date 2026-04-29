#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

if ! command -v forge >/dev/null 2>&1; then
  echo "forge is required but not found in PATH" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required but not found in PATH" >&2
  exit 1
fi

if ! command -v slither >/dev/null 2>&1; then
  echo "slither is required but not found in PATH" >&2
  exit 1
fi

if [[ -z "${RPC_URL:-}" ]]; then
  echo "RPC_URL is required" >&2
  exit 1
fi

if [[ -z "${PRIVATE_KEY:-}" ]]; then
  echo "PRIVATE_KEY is required" >&2
  exit 1
fi

ARTIFACT_PATH="${MARK_MAINNET_GATE_ARTIFACT_PATH:-broadcast/mark-mainnet-gate.json}"
MODE="${MARK_MAINNET_GATE_MODE:-predeploy}"

case "$MODE" in
  predeploy|postdeploy|full) ;;
  *)
    echo "MARK_MAINNET_GATE_MODE must be one of: predeploy, postdeploy, full" >&2
    exit 1
    ;;
esac

run_predeploy_checks() {
  echo "[1/6] Running contract tests..."
  forge test -vv

  echo "[2/6] Running Slither core scan..."
  slither \
    src/token/RYLA.sol \
    src/bridge/MARKBridgeAdapter.sol \
    src/settlement/MARKSettlementModule.sol \
    src/settlement/verifier/AttestedSettlementVerifier.sol \
    --solc-remaps "@interop-lib/=lib/interop-lib/src/ @openzeppelin/=lib/createx/lib/openzeppelin-contracts/" \
    --exclude-dependencies \
    --filter-paths "lib|test|script|out|cache" \
    --fail-medium

  echo "[3/6] Running preflight checks for all modes..."
  for mode in 1 2 3; do
    MARK_PREFLIGHT_MODE="$mode" forge script script/ops/settlement/PreflightMARKDeployment.s.sol --rpc-url "$RPC_URL" -q
  done
}

run_postdeploy_checks() {
  echo "[4/6] Running deployment verify checks..."
  forge script script/ops/settlement/VerifyMARKDeployment.s.sol --rpc-url "$RPC_URL" -q
}

generate_and_validate_artifact() {
  echo "[5/6] Generating release artifact via dry-run orchestration..."
  MARK_RELEASE_EXECUTE=false \
  MARK_RELEASE_WRITE_ARTIFACT=true \
  MARK_RELEASE_ARTIFACT_PATH="$ARTIFACT_PATH" \
  MARK_RELEASE_STRICT_VERIFY=false \
  forge script script/ops/settlement/ReleaseMARK.s.sol --rpc-url "$RPC_URL" -q

  echo "[6/6] Validating release artifact schema..."
  jq -e '
    .protocol == "MARK" and
    .tokenSymbol == "RYLA" and
    .execute == false and
    .deployer != null and
    .chainId != null and
    .timestamp != null and
    .gitCommit != null
  ' "$ARTIFACT_PATH" >/dev/null
}

if [[ "$MODE" == "predeploy" ]]; then
  run_predeploy_checks
  generate_and_validate_artifact
elif [[ "$MODE" == "postdeploy" ]]; then
  run_postdeploy_checks
else
  run_predeploy_checks
  run_postdeploy_checks
  generate_and_validate_artifact
fi

echo "Mainnet readiness gate PASSED."
echo "Artifact: $ARTIFACT_PATH"
