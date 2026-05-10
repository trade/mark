#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "verify-from-artifact: required command not found: $1" >&2
    exit 1
  fi
}

require_cmd jq
require_cmd forge

require_env() {
  local key="$1"
  if [[ -z "${!key:-}" ]]; then
    echo "verify-from-artifact: missing required env var: $key" >&2
    exit 1
  fi
}

norm_addr() {
  echo "$1" | tr '[:upper:]' '[:lower:]'
}

assert_addr_eq() {
  local label="$1"
  local left="$2"
  local right="$3"
  if [[ "$(norm_addr "$left")" != "$(norm_addr "$right")" ]]; then
    echo "verify-from-artifact: $label mismatch (env=$left artifact=$right)" >&2
    exit 1
  fi
}

assert_scalar_eq() {
  local label="$1"
  local left="$2"
  local right="$3"
  if [[ "$left" != "$right" ]]; then
    echo "verify-from-artifact: $label mismatch (env=$left artifact=$right)" >&2
    exit 1
  fi
}

ARTIFACT_PATH="${MARK_RELEASE_VERIFY_ARTIFACT_PATH:-${MARK_RELEASE_ARTIFACT_PATH:-}}"
require_env ARTIFACT_PATH
if [[ ! -f "$ARTIFACT_PATH" ]]; then
  echo "verify-from-artifact: artifact not found: $ARTIFACT_PATH" >&2
  exit 1
fi

token="$(jq -r '.token // empty' "$ARTIFACT_PATH")"
adapter="$(jq -r '.adapter // empty' "$ARTIFACT_PATH")"
module="$(jq -r '.module // empty' "$ARTIFACT_PATH")"
protocol="$(jq -r '.protocol // empty' "$ARTIFACT_PATH")"
tokenSymbol="$(jq -r '.tokenSymbol // empty' "$ARTIFACT_PATH")"
chainId="$(jq -r '.chainId // 0' "$ARTIFACT_PATH")"
expectedOwner="$(jq -r '.expectedOwner // empty' "$ARTIFACT_PATH")"
expectedBridgeOperator="$(jq -r '.expectedBridgeOperator // "0x0000000000000000000000000000000000000000"' "$ARTIFACT_PATH")"
expectedBridgeDestinationChain="$(jq -r '.expectedBridgeDestinationChain // 0' "$ARTIFACT_PATH")"
expectedBridgeMaxPerTx="$(jq -r '.expectedBridgeMaxPerTx // 0' "$ARTIFACT_PATH")"
expectedBridgeDailyCap="$(jq -r '.expectedBridgeDailyCap // 0' "$ARTIFACT_PATH")"
expectedSettlementOperator="$(jq -r '.expectedSettlementOperator // empty' "$ARTIFACT_PATH")"
expectedProofEnabled="$(jq -r '.expectedProofEnabled // empty' "$ARTIFACT_PATH")"
expectedProductionMode="$(jq -r '.expectedProductionMode // empty' "$ARTIFACT_PATH")"
expectedVerifier="$(jq -r '.expectedVerifier // empty' "$ARTIFACT_PATH")"
expectedAttester="$(jq -r '.expectedAttester // "0x0000000000000000000000000000000000000000"' "$ARTIFACT_PATH")"

if [[ -z "$token" || -z "$module" ]]; then
  echo "verify-from-artifact: artifact missing token/module fields" >&2
  exit 1
fi
if [[ "$protocol" != "MARK" ]]; then
  echo "verify-from-artifact: artifact protocol must be MARK (got: $protocol)" >&2
  exit 1
fi
if [[ "$tokenSymbol" != "RYLA" ]]; then
  echo "verify-from-artifact: artifact tokenSymbol must be RYLA (got: $tokenSymbol)" >&2
  exit 1
fi
if [[ "$chainId" == "0" ]]; then
  echo "verify-from-artifact: artifact chainId must be non-zero" >&2
  exit 1
fi

# If env is preset, enforce equality with artifact. Otherwise set from artifact.
if [[ -n "${VERIFY_MARK_RYLA_TOKEN:-}" ]]; then
  assert_addr_eq "VERIFY_MARK_RYLA_TOKEN" "${VERIFY_MARK_RYLA_TOKEN}" "$token"
else
  export VERIFY_MARK_RYLA_TOKEN="$token"
fi

if [[ -n "${VERIFY_MARK_BRIDGE_ADAPTER:-}" && -n "$adapter" ]]; then
  assert_addr_eq "VERIFY_MARK_BRIDGE_ADAPTER" "${VERIFY_MARK_BRIDGE_ADAPTER}" "$adapter"
else
  export VERIFY_MARK_BRIDGE_ADAPTER="${VERIFY_MARK_BRIDGE_ADAPTER:-$adapter}"
fi

if [[ -n "${VERIFY_MARK_SETTLEMENT_MODULE:-}" ]]; then
  assert_addr_eq "VERIFY_MARK_SETTLEMENT_MODULE" "${VERIFY_MARK_SETTLEMENT_MODULE}" "$module"
else
  export VERIFY_MARK_SETTLEMENT_MODULE="$module"
fi

if [[ -n "${VERIFY_MARK_RYLA_OWNER:-}" && -n "$expectedOwner" ]]; then
  assert_addr_eq "VERIFY_MARK_RYLA_OWNER" "${VERIFY_MARK_RYLA_OWNER}" "$expectedOwner"
else
  export VERIFY_MARK_RYLA_OWNER="${VERIFY_MARK_RYLA_OWNER:-$expectedOwner}"
fi

if [[ -n "${VERIFY_MARK_BRIDGE_OPERATOR:-}" ]]; then
  assert_addr_eq "VERIFY_MARK_BRIDGE_OPERATOR" "${VERIFY_MARK_BRIDGE_OPERATOR}" "$expectedBridgeOperator"
else
  export VERIFY_MARK_BRIDGE_OPERATOR="$expectedBridgeOperator"
fi

if [[ -n "${VERIFY_MARK_BRIDGE_DEST_CHAIN:-}" ]]; then
  assert_scalar_eq "VERIFY_MARK_BRIDGE_DEST_CHAIN" "${VERIFY_MARK_BRIDGE_DEST_CHAIN}" "$expectedBridgeDestinationChain"
else
  export VERIFY_MARK_BRIDGE_DEST_CHAIN="$expectedBridgeDestinationChain"
fi

if [[ -n "${VERIFY_MARK_BRIDGE_MAX_PER_TX:-}" ]]; then
  assert_scalar_eq "VERIFY_MARK_BRIDGE_MAX_PER_TX" "${VERIFY_MARK_BRIDGE_MAX_PER_TX}" "$expectedBridgeMaxPerTx"
else
  export VERIFY_MARK_BRIDGE_MAX_PER_TX="$expectedBridgeMaxPerTx"
fi

if [[ -n "${VERIFY_MARK_BRIDGE_DAILY_CAP:-}" ]]; then
  assert_scalar_eq "VERIFY_MARK_BRIDGE_DAILY_CAP" "${VERIFY_MARK_BRIDGE_DAILY_CAP}" "$expectedBridgeDailyCap"
else
  export VERIFY_MARK_BRIDGE_DAILY_CAP="$expectedBridgeDailyCap"
fi

if [[ -n "${VERIFY_MARK_SETTLEMENT_OPERATOR:-}" && -n "$expectedSettlementOperator" ]]; then
  assert_addr_eq "VERIFY_MARK_SETTLEMENT_OPERATOR" "${VERIFY_MARK_SETTLEMENT_OPERATOR}" "$expectedSettlementOperator"
else
  export VERIFY_MARK_SETTLEMENT_OPERATOR="${VERIFY_MARK_SETTLEMENT_OPERATOR:-$expectedSettlementOperator}"
fi

if [[ -n "${VERIFY_MARK_SETTLEMENT_PROOF_ENABLED:-}" && -n "$expectedProofEnabled" ]]; then
  assert_scalar_eq "VERIFY_MARK_SETTLEMENT_PROOF_ENABLED" "${VERIFY_MARK_SETTLEMENT_PROOF_ENABLED}" "$expectedProofEnabled"
else
  export VERIFY_MARK_SETTLEMENT_PROOF_ENABLED="${VERIFY_MARK_SETTLEMENT_PROOF_ENABLED:-$expectedProofEnabled}"
fi

if [[ -n "${VERIFY_MARK_SETTLEMENT_PRODUCTION_MODE:-}" && -n "$expectedProductionMode" ]]; then
  assert_scalar_eq "VERIFY_MARK_SETTLEMENT_PRODUCTION_MODE" "${VERIFY_MARK_SETTLEMENT_PRODUCTION_MODE}" "$expectedProductionMode"
else
  export VERIFY_MARK_SETTLEMENT_PRODUCTION_MODE="${VERIFY_MARK_SETTLEMENT_PRODUCTION_MODE:-$expectedProductionMode}"
fi

if [[ -n "${VERIFY_MARK_SETTLEMENT_VERIFIER:-}" && -n "$expectedVerifier" ]]; then
  assert_addr_eq "VERIFY_MARK_SETTLEMENT_VERIFIER" "${VERIFY_MARK_SETTLEMENT_VERIFIER}" "$expectedVerifier"
else
  export VERIFY_MARK_SETTLEMENT_VERIFIER="${VERIFY_MARK_SETTLEMENT_VERIFIER:-$expectedVerifier}"
fi

if [[ -n "${VERIFY_MARK_SETTLEMENT_ATTESTER:-}" ]]; then
  assert_addr_eq "VERIFY_MARK_SETTLEMENT_ATTESTER" "${VERIFY_MARK_SETTLEMENT_ATTESTER}" "$expectedAttester"
else
  export VERIFY_MARK_SETTLEMENT_ATTESTER="$expectedAttester"
fi

require_env RPC_URL
require_env VERIFY_MARK_RYLA_TOKEN
require_env VERIFY_MARK_SETTLEMENT_MODULE
require_env VERIFY_MARK_RYLA_OWNER
require_env VERIFY_MARK_SETTLEMENT_OPERATOR
require_env VERIFY_MARK_SETTLEMENT_PROOF_ENABLED
require_env VERIFY_MARK_SETTLEMENT_PRODUCTION_MODE
require_env VERIFY_MARK_SETTLEMENT_VERIFIER

echo "[verify-from-artifact] running onchain verify against anchored artifact values"
forge script script/ops/settlement/VerifyMARKDeployment.s.sol --rpc-url "$RPC_URL" -q
echo "[verify-from-artifact] PASSED"
