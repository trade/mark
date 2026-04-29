#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "release-gate: required command not found: $1" >&2
    exit 1
  fi
}

require_cmd forge
require_cmd jq
require_cmd git

MODE="${MARK_RELEASE_GATE_MODE:-local}" # local | remote
OUT_DIR="${MARK_RELEASE_GATE_OUT_DIR:-broadcast/release-gate}"
TIMESTAMP_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
STAMP="$(date -u +"%Y%m%dT%H%M%SZ")"
GIT_COMMIT="$(git rev-parse --short HEAD)"
ARTIFACT_PATH="$OUT_DIR/release-gate-$STAMP.json"

mkdir -p "$OUT_DIR"

echo "[release-gate] mode=$MODE"
echo "[release-gate] step 1/3: make ci-full"
make ci-full

READINESS_STATUS="skipped"
VERIFY_STATUS="skipped"

if [[ "$MODE" == "remote" ]]; then
  if [[ -z "${RPC_URL:-}" ]]; then
    echo "release-gate: RPC_URL is required for remote mode" >&2
    exit 1
  fi
  if [[ -z "${PRIVATE_KEY:-}" ]]; then
    echo "release-gate: PRIVATE_KEY is required for remote mode" >&2
    exit 1
  fi

  echo "[release-gate] step 2/3: mainnet-readiness (dry checks)"
  MARK_MAINNET_GATE_MODE="${MARK_MAINNET_GATE_MODE:-predeploy}" \
  MARK_MAINNET_GATE_ARTIFACT_PATH="${MARK_MAINNET_GATE_ARTIFACT_PATH:-$OUT_DIR/mainnet-gate-$STAMP.json}" \
  ./script/ops/mainnet-readiness.sh
  READINESS_STATUS="passed"

  echo "[release-gate] step 3/3: strict deployment verification"
  # Strict mode: require explicit VERIFY_* env instead of implicit defaults.
  : "${VERIFY_MARK_RYLA_TOKEN:?VERIFY_MARK_RYLA_TOKEN is required in remote mode}"
  : "${VERIFY_MARK_RYLA_OWNER:?VERIFY_MARK_RYLA_OWNER is required in remote mode}"
  : "${VERIFY_MARK_SETTLEMENT_MODULE:?VERIFY_MARK_SETTLEMENT_MODULE is required in remote mode}"
  : "${VERIFY_MARK_SETTLEMENT_OPERATOR:?VERIFY_MARK_SETTLEMENT_OPERATOR is required in remote mode}"
  : "${VERIFY_MARK_SETTLEMENT_PROOF_ENABLED:?VERIFY_MARK_SETTLEMENT_PROOF_ENABLED is required in remote mode}"
  : "${VERIFY_MARK_SETTLEMENT_PRODUCTION_MODE:?VERIFY_MARK_SETTLEMENT_PRODUCTION_MODE is required in remote mode}"
  : "${VERIFY_MARK_SETTLEMENT_VERIFIER:?VERIFY_MARK_SETTLEMENT_VERIFIER is required in remote mode}"
  forge script script/ops/settlement/VerifyMARKDeployment.s.sol --rpc-url "$RPC_URL" -q
  VERIFY_STATUS="passed"
fi

jq -n \
  --arg gate "release-gate" \
  --arg mode "$MODE" \
  --arg timestamp "$TIMESTAMP_UTC" \
  --arg commit "$GIT_COMMIT" \
  --arg ciFull "passed" \
  --arg readiness "$READINESS_STATUS" \
  --arg verify "$VERIFY_STATUS" \
  '{
    gate: $gate,
    mode: $mode,
    timestamp: $timestamp,
    gitCommit: $commit,
    checks: {
      ciFull: $ciFull,
      mainnetReadiness: $readiness,
      strictDeploymentVerify: $verify
    }
  }' > "$ARTIFACT_PATH"

echo "[release-gate] PASSED"
echo "[release-gate] artifact: $ARTIFACT_PATH"
