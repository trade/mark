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

require_cmd cast
require_cmd jq

require_env() {
  local key="$1"
  if [[ -z "${!key:-}" ]]; then
    echo "Missing required env var: $key" >&2
    exit 1
  fi
}

norm_addr() {
  echo "$1" | tr '[:upper:]' '[:lower:]'
}

assert_eq() {
  local got="$1"
  local expected="$2"
  local msg="$3"
  if [[ "$got" != "$expected" ]]; then
    echo "ASSERT FAILED: $msg (got=$got expected=$expected)" >&2
    exit 1
  fi
}

assert_true() {
  local got="$1"
  local msg="$2"
  if [[ "$got" != "true" ]]; then
    echo "ASSERT FAILED: $msg (got=$got expected=true)" >&2
    exit 1
  fi
}

assert_contract() {
  local addr="$1"
  local label="$2"
  local code
  code="$(cast code "$addr" --rpc-url "$RPC_URL")"
  if [[ "$code" == "0x" ]]; then
    echo "ASSERT FAILED: $label has no code at $addr" >&2
    exit 1
  fi
}

has_role() {
  local contract_addr="$1"
  local role="$2"
  local account="$3"
  cast call "$contract_addr" "hasRole(bytes32,address)(bool)" "$role" "$account" --rpc-url "$RPC_URL"
}

RPC_URL="${RPC_URL:-}"
ARTIFACT_PATH="${MARK_RELEASE_ARTIFACT_PATH:-}"

require_env RPC_URL

TOKEN_ADDRESS="${MARK_RYLA_TOKEN:-${VERIFY_MARK_RYLA_TOKEN:-}}"
MODULE_ADDRESS="${MARK_SETTLEMENT_MODULE:-${VERIFY_MARK_SETTLEMENT_MODULE:-}}"
VERIFIER_ADDRESS="${MARK_SETTLEMENT_VERIFIER:-${VERIFY_MARK_SETTLEMENT_VERIFIER:-}}"

if [[ -n "$ARTIFACT_PATH" && -f "$ARTIFACT_PATH" ]]; then
  if [[ -z "$TOKEN_ADDRESS" ]]; then
    TOKEN_ADDRESS="$(jq -r '.token' "$ARTIFACT_PATH")"
  fi
  if [[ -z "$MODULE_ADDRESS" ]]; then
    MODULE_ADDRESS="$(jq -r '.module' "$ARTIFACT_PATH")"
  fi
  if [[ -z "$VERIFIER_ADDRESS" ]]; then
    VERIFIER_ADDRESS="$(jq -r '.verifier' "$ARTIFACT_PATH")"
  fi
fi

EXPECTED_OWNER="${VERIFY_MARK_RYLA_OWNER:-${MARK_RYLA_OWNER:-}}"
EXPECTED_SETTLEMENT_OPERATOR="${VERIFY_MARK_SETTLEMENT_OPERATOR:-${MARK_SETTLEMENT_OPERATOR:-}}"
EXPECTED_VERIFIER="${VERIFY_MARK_SETTLEMENT_VERIFIER:-${MARK_SETTLEMENT_VERIFIER:-$VERIFIER_ADDRESS}}"
EXPECTED_ATTESTER="${VERIFY_MARK_SETTLEMENT_ATTESTER:-${MARK_SETTLEMENT_ATTESTER:-}}"

require_env TOKEN_ADDRESS
require_env MODULE_ADDRESS
require_env VERIFIER_ADDRESS
require_env EXPECTED_OWNER
require_env EXPECTED_SETTLEMENT_OPERATOR
require_env EXPECTED_VERIFIER

export MARK_RYLA_TOKEN="$TOKEN_ADDRESS"
export MARK_SETTLEMENT_MODULE="$MODULE_ADDRESS"
export MARK_SETTLEMENT_VERIFIER="$VERIFIER_ADDRESS"
export MARK_RYLA_OWNER="$EXPECTED_OWNER"
export MARK_SETTLEMENT_OPERATOR="$EXPECTED_SETTLEMENT_OPERATOR"
export MARK_SETTLEMENT_ATTESTER="${EXPECTED_ATTESTER:-0x0000000000000000000000000000000000000000}"
export MARK_ENV_STRICT_PLACEHOLDERS=true
VALIDATE_MODE=verify-lock ./script/ops/validate-prod-env.sh

DEFAULT_ADMIN_ROLE="0x0000000000000000000000000000000000000000000000000000000000000000"

assert_contract "$TOKEN_ADDRESS" "RYLA token"
assert_contract "$MODULE_ADDRESS" "Settlement module"
assert_contract "$VERIFIER_ADDRESS" "Settlement verifier"

PROOF_ENABLED="$(cast call "$MODULE_ADDRESS" "proofValidationEnabled()(bool)" --rpc-url "$RPC_URL")"
PRODUCTION_MODE="$(cast call "$MODULE_ADDRESS" "productionMode()(bool)" --rpc-url "$RPC_URL")"
MODULE_VERIFIER="$(cast call "$MODULE_ADDRESS" "verifier()(address)" --rpc-url "$RPC_URL")"
MODULE_OPERATOR_ROLE="$(cast call "$MODULE_ADDRESS" "OPERATOR_ROLE()(bytes32)" --rpc-url "$RPC_URL")"
TOKEN_MINTER_ROLE="$(cast call "$TOKEN_ADDRESS" "MINTER_ROLE()(bytes32)" --rpc-url "$RPC_URL")"
TOKEN_BURNER_ROLE="$(cast call "$TOKEN_ADDRESS" "BURNER_ROLE()(bytes32)" --rpc-url "$RPC_URL")"

assert_true "$PROOF_ENABLED" "module proofValidationEnabled must be true"
assert_true "$PRODUCTION_MODE" "module productionMode must be true"
assert_eq "$(norm_addr "$MODULE_VERIFIER")" "$(norm_addr "$EXPECTED_VERIFIER")" "module verifier mismatch"
assert_eq "$(norm_addr "$VERIFIER_ADDRESS")" "$(norm_addr "$EXPECTED_VERIFIER")" "configured verifier mismatch"

TOKEN_OWNER_ADMIN="$(has_role "$TOKEN_ADDRESS" "$DEFAULT_ADMIN_ROLE" "$EXPECTED_OWNER")"
MODULE_OWNER_ADMIN="$(has_role "$MODULE_ADDRESS" "$DEFAULT_ADMIN_ROLE" "$EXPECTED_OWNER")"
MODULE_OPERATOR_SET="$(has_role "$MODULE_ADDRESS" "$MODULE_OPERATOR_ROLE" "$EXPECTED_SETTLEMENT_OPERATOR")"
TOKEN_MINTER_SET="$(has_role "$TOKEN_ADDRESS" "$TOKEN_MINTER_ROLE" "$MODULE_ADDRESS")"
TOKEN_BURNER_SET="$(has_role "$TOKEN_ADDRESS" "$TOKEN_BURNER_ROLE" "$MODULE_ADDRESS")"
VERIFIER_OWNER_ADMIN="$(has_role "$VERIFIER_ADDRESS" "$DEFAULT_ADMIN_ROLE" "$EXPECTED_OWNER")"

assert_true "$TOKEN_OWNER_ADMIN" "owner must be token default admin"
assert_true "$MODULE_OWNER_ADMIN" "owner must be module default admin"
assert_true "$MODULE_OPERATOR_SET" "expected settlement operator role missing on module"
assert_true "$TOKEN_MINTER_SET" "module must have token minter role"
assert_true "$TOKEN_BURNER_SET" "module must have token burner role"
assert_true "$VERIFIER_OWNER_ADMIN" "owner must be verifier default admin"

if [[ -n "$EXPECTED_ATTESTER" && "$EXPECTED_ATTESTER" != "0x0000000000000000000000000000000000000000" ]]; then
  ATTESTER_ROLE="$(cast call "$VERIFIER_ADDRESS" "ATTESTER_ROLE()(bytes32)" --rpc-url "$RPC_URL")"
  VERIFIER_ATTESTER_SET="$(has_role "$VERIFIER_ADDRESS" "$ATTESTER_ROLE" "$EXPECTED_ATTESTER")"
  assert_true "$VERIFIER_ATTESTER_SET" "expected attester role missing on verifier"
fi

echo "Production lock verification PASSED"
echo "Token: $TOKEN_ADDRESS"
echo "Module: $MODULE_ADDRESS"
echo "Verifier: $VERIFIER_ADDRESS"
echo "Owner(admin): $EXPECTED_OWNER"
echo "Settlement operator: $EXPECTED_SETTLEMENT_OPERATOR"
