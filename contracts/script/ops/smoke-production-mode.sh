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

require_cmd anvil
require_cmd forge
require_cmd cast
require_cmd jq

ANVIL_HOST="${ANVIL_HOST:-127.0.0.1}"
ANVIL_PORT="${ANVIL_PORT:-8545}"
HTTP_RPC_URL="${HTTP_RPC_URL:-http://${ANVIL_HOST}:${ANVIL_PORT}}"
RPC_URL="${RPC_URL:-ws://${ANVIL_HOST}:${ANVIL_PORT}}"
START_LOCAL_ANVIL="${START_LOCAL_ANVIL:-true}"

PRIVATE_KEY="${PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"
OWNER="${MARK_RYLA_OWNER:-0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266}"
BRIDGE_OPERATOR="${MARK_BRIDGE_OPERATOR:-0x70997970C51812dc3A010C7d01b50e0d17dc79C8}"
SETTLEMENT_OPERATOR="${MARK_SETTLEMENT_OPERATOR:-0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC}"
BRIDGE_DEST_CHAIN="${MARK_BRIDGE_DESTINATION_CHAIN_ID:-10}"
ARTIFACT_PATH="${MARK_RELEASE_ARTIFACT_PATH:-broadcast/mark-release-prodmode-ci.json}"

ANVIL_PID=""
cleanup() {
  if [[ -n "$ANVIL_PID" ]]; then
    kill "$ANVIL_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

if [[ "$START_LOCAL_ANVIL" == "true" ]]; then
  anvil --host "$ANVIL_HOST" --port "$ANVIL_PORT" >/tmp/mark-anvil.log 2>&1 &
  ANVIL_PID=$!
fi

for _ in $(seq 1 30); do
  if /usr/bin/curl -sS -H 'content-type: application/json' \
    --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
    "$HTTP_RPC_URL" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

/usr/bin/curl -sS -H 'content-type: application/json' \
  --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
  "$HTTP_RPC_URL" >/dev/null

# Deploy an attested verifier with cast to avoid local forge create broadcast quirks.
BYTECODE="$(forge inspect src/settlement/verifier/AttestedSettlementVerifier.sol:AttestedSettlementVerifier bytecode)"
ARGS="$(cast abi-encode "constructor(address)" "$OWNER")"
DATA="${BYTECODE}${ARGS#0x}"
SEND_JSON="$(cast send --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" --create "$DATA" --json 2>/dev/null || true)"
VERIFIER_TX="$(echo "$SEND_JSON" | jq -r '.transactionHash' 2>/dev/null || true)"
if [[ -z "$VERIFIER_TX" || "$VERIFIER_TX" == "null" ]]; then
  SEND_OUT="$(cast send --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" --create "$DATA")"
  VERIFIER_TX="$(echo "$SEND_OUT" | grep -Eo '0x[0-9a-fA-F]{64}' | head -n1 || true)"
fi
VERIFIER_ADDRESS="$(cast receipt "$VERIFIER_TX" --rpc-url "$RPC_URL" --json | jq -r '.contractAddress')"

if [[ "$VERIFIER_ADDRESS" == "0x0000000000000000000000000000000000000000" ]]; then
  echo "Verifier deployment failed: zero address" >&2
  exit 1
fi

export PRIVATE_KEY RPC_URL
export MARK_RELEASE_EXECUTE=true
export MARK_RELEASE_RUN_POSTDEPLOY=true
export MARK_RELEASE_WRITE_ARTIFACT=true
export MARK_RELEASE_ARTIFACT_PATH="$ARTIFACT_PATH"
export MARK_RELEASE_STRICT_VERIFY=true
export MARK_GIT_COMMIT="${MARK_GIT_COMMIT:-local-prodmode-smoke}"

export MARK_RYLA_OWNER="$OWNER"
export MARK_MODULE_OWNER="$OWNER"
export MARK_BRIDGE_OPERATOR="$BRIDGE_OPERATOR"
export MARK_BRIDGE_DESTINATION_CHAIN_ID="$BRIDGE_DEST_CHAIN"
export MARK_SETTLEMENT_OPERATOR="$SETTLEMENT_OPERATOR"
export MARK_SETTLEMENT_VERIFIER="$VERIFIER_ADDRESS"
export MARK_SETTLEMENT_PROOF_ENABLED=true
export MARK_SETTLEMENT_PRODUCTION_MODE=true
export MARK_SETTLEMENT_ATTESTER="${MARK_SETTLEMENT_ATTESTER:-0x0000000000000000000000000000000000000000}"

export VERIFY_MARK_RYLA_OWNER="$OWNER"
export VERIFY_MARK_BRIDGE_OPERATOR="$BRIDGE_OPERATOR"
export VERIFY_MARK_BRIDGE_DEST_CHAIN="$BRIDGE_DEST_CHAIN"
export VERIFY_MARK_SETTLEMENT_OPERATOR="$SETTLEMENT_OPERATOR"
export VERIFY_MARK_SETTLEMENT_PROOF_ENABLED=true
export VERIFY_MARK_SETTLEMENT_PRODUCTION_MODE=true
export VERIFY_MARK_SETTLEMENT_VERIFIER="$VERIFIER_ADDRESS"

forge script script/ops/settlement/ReleaseMARK.s.sol --rpc-url "$RPC_URL" --broadcast -q

if [[ ! -f "$ARTIFACT_PATH" ]]; then
  echo "Missing artifact: $ARTIFACT_PATH" >&2
  exit 1
fi

TOKEN="$(jq -r '.token' "$ARTIFACT_PATH")"
ADAPTER="$(jq -r '.adapter' "$ARTIFACT_PATH")"
MODULE="$(jq -r '.module' "$ARTIFACT_PATH")"
VERIFIER_ARTIFACT="$(jq -r '.verifier' "$ARTIFACT_PATH")"
PROOF="$(cast call "$MODULE" "proofValidationEnabled()(bool)" --rpc-url "$RPC_URL")"
PRODUCTION_MODE="$(cast call "$MODULE" "productionMode()(bool)" --rpc-url "$RPC_URL")"
ONCHAIN_VERIFIER="$(cast call "$MODULE" "verifier()(address)" --rpc-url "$RPC_URL")"

echo "Production mode smoke PASSED"
echo "Artifact: $ARTIFACT_PATH"
echo "Verifier predeploy: $VERIFIER_ADDRESS"
echo "Token: $TOKEN"
echo "Adapter: $ADAPTER"
echo "Module: $MODULE"
echo "Verifier (artifact): $VERIFIER_ARTIFACT"
echo "Proof enabled: $PROOF"
echo "Production mode: $PRODUCTION_MODE"
echo "Verifier (onchain): $ONCHAIN_VERIFIER"
