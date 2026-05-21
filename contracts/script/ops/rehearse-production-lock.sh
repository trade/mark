#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "$1 is required but not found in PATH" >&2
    exit 1
  fi
}

require_env() {
  local key="$1"
  if [[ -z "${!key:-}" ]]; then
    echo "Missing required env var: $key" >&2
    exit 1
  fi
}

require_cmd forge
require_cmd cast
require_cmd jq

require_env RPC_URL
require_env PRIVATE_KEY
require_env MARK_SETTLEMENT_OPERATOR

DEPLOYER_ADDRESS="$(cast wallet address --private-key "$PRIVATE_KEY")"

MARK_RYLA_OWNER="${MARK_RYLA_OWNER:-$DEPLOYER_ADDRESS}"
MARK_MODULE_OWNER="${MARK_MODULE_OWNER:-$MARK_RYLA_OWNER}"
MARK_BRIDGE_OPERATOR="${MARK_BRIDGE_OPERATOR:-$MARK_SETTLEMENT_OPERATOR}"
MARK_BRIDGE_DESTINATION_CHAIN_ID="${MARK_BRIDGE_DESTINATION_CHAIN_ID:-10}"
MARK_SETTLEMENT_ATTESTER="${MARK_SETTLEMENT_ATTESTER:-0x0000000000000000000000000000000000000000}"

RELEASE_ARTIFACT_PATH="${MARK_RELEASE_ARTIFACT_PATH:-broadcast/mark-staging-release.json}"
REHEARSAL_ARTIFACT_PATH="${MARK_REHEARSAL_ARTIFACT_PATH:-broadcast/mark-staging-rehearsal.json}"
MARK_GIT_COMMIT="${MARK_GIT_COMMIT:-unknown}"

export MARK_RYLA_OWNER
export MARK_MODULE_OWNER
export MARK_BRIDGE_OPERATOR
export MARK_BRIDGE_DESTINATION_CHAIN_ID
export MARK_SETTLEMENT_OPERATOR
export MARK_SETTLEMENT_ATTESTER

export MARK_RELEASE_EXECUTE=true
export MARK_RELEASE_RUN_POSTDEPLOY=true
export MARK_RELEASE_WRITE_ARTIFACT=true
export MARK_RELEASE_ARTIFACT_PATH="$RELEASE_ARTIFACT_PATH"
export MARK_RELEASE_STRICT_VERIFY=false
export MARK_GIT_COMMIT

export MARK_SETTLEMENT_PROOF_ENABLED=true
export MARK_SETTLEMENT_PRODUCTION_MODE=true
export MARK_DEPLOY_ATTESTED_VERIFIER=true
export MARK_SETTLEMENT_VERIFIER="${MARK_SETTLEMENT_VERIFIER:-0x0000000000000000000000000000000000000000}"

VALIDATE_MODE=rehearsal ./script/ops/validate-prod-env.sh

echo "Running staging rehearsal release..."
forge script script/ops/settlement/ReleaseMARK.s.sol --rpc-url "$RPC_URL" --broadcast --slow --non-interactive -q

if [[ ! -f "$RELEASE_ARTIFACT_PATH" ]]; then
  echo "Missing release artifact: $RELEASE_ARTIFACT_PATH" >&2
  exit 1
fi

TOKEN_ADDRESS="$(jq -r '.token' "$RELEASE_ARTIFACT_PATH")"
MODULE_ADDRESS="$(jq -r '.module' "$RELEASE_ARTIFACT_PATH")"
VERIFIER_ADDRESS="$(jq -r '.verifier' "$RELEASE_ARTIFACT_PATH")"
CHAIN_ID="$(cast chain-id --rpc-url "$RPC_URL")"

export MARK_RYLA_TOKEN="$TOKEN_ADDRESS"
export MARK_SETTLEMENT_MODULE="$MODULE_ADDRESS"
export MARK_SETTLEMENT_VERIFIER="$VERIFIER_ADDRESS"

echo "Running production lock verification..."
./script/ops/verify-production-lock.sh

mkdir -p "$(dirname "$REHEARSAL_ARTIFACT_PATH")"
jq -n \
  --arg rpcUrl "$RPC_URL" \
  --arg chainId "$CHAIN_ID" \
  --arg deployer "$DEPLOYER_ADDRESS" \
  --arg owner "$MARK_RYLA_OWNER" \
  --arg settlementOperator "$MARK_SETTLEMENT_OPERATOR" \
  --arg token "$TOKEN_ADDRESS" \
  --arg module "$MODULE_ADDRESS" \
  --arg verifier "$VERIFIER_ADDRESS" \
  --arg releaseArtifact "$RELEASE_ARTIFACT_PATH" \
  --arg verifyMode "production-lock" \
  --arg commit "$MARK_GIT_COMMIT" \
  '{
    status: "passed",
    verifyMode: $verifyMode,
    rpcUrl: $rpcUrl,
    chainId: $chainId,
    deployer: $deployer,
    owner: $owner,
    settlementOperator: $settlementOperator,
    token: $token,
    module: $module,
    verifier: $verifier,
    releaseArtifact: $releaseArtifact,
    gitCommit: $commit
  }' >"$REHEARSAL_ARTIFACT_PATH"

echo "Staging rehearsal PASSED"
echo "Release artifact: $RELEASE_ARTIFACT_PATH"
echo "Rehearsal artifact: $REHEARSAL_ARTIFACT_PATH"
