#!/usr/bin/env bash
set -euo pipefail

MODE="${VALIDATE_MODE:-}"
STRICT_PLACEHOLDERS="${MARK_ENV_STRICT_PLACEHOLDERS:-false}"

if [[ -z "$MODE" ]]; then
  echo "VALIDATE_MODE is required (rehearsal | dispatch | verify-lock)" >&2
  exit 1
fi

require_env() {
  local key="$1"
  if [[ -z "${!key:-}" ]]; then
    echo "Missing required env var: $key" >&2
    exit 1
  fi
}

is_address() {
  local value="$1"
  [[ "$value" =~ ^0x[0-9a-fA-F]{40}$ ]]
}

is_zero_address() {
  local value="$1"
  [[ "${value,,}" == "0x0000000000000000000000000000000000000000" ]]
}

require_address() {
  local key="$1"
  local value="${!key:-}"
  require_env "$key"
  if ! is_address "$value"; then
    echo "Invalid address format for $key: $value" >&2
    exit 1
  fi
}

is_strict_mode() {
  [[ "$STRICT_PLACEHOLDERS" == "true" || "$STRICT_PLACEHOLDERS" == "1" ]]
}

is_known_placeholder_address() {
  local value="${1,,}"
  case "$value" in
    0x1111111111111111111111111111111111111111 | \
      0x2222222222222222222222222222222222222222 | \
      0x3333333333333333333333333333333333333333 | \
      0x4444444444444444444444444444444444444444 | \
      0x5555555555555555555555555555555555555555)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

reject_known_placeholder_if_strict() {
  local key="$1"
  local value="$2"
  if is_strict_mode && is_known_placeholder_address "$value"; then
    echo "Placeholder address is not allowed for $key when MARK_ENV_STRICT_PLACEHOLDERS=true: $value" >&2
    exit 1
  fi
}

require_rpc_url() {
  require_env RPC_URL
  if [[ ! "$RPC_URL" =~ ^(https?|wss?):// ]]; then
    echo "RPC_URL must start with http://, https://, ws://, or wss://" >&2
    exit 1
  fi
}

assert_true_like() {
  local key="$1"
  local value="${!key:-}"
  if [[ "$value" != "true" && "$value" != "1" ]]; then
    echo "$key must be true/1 for this mode (got: ${value:-<empty>})" >&2
    exit 1
  fi
}

validate_common_optional_addresses() {
  local key
  for key in "$@"; do
    if [[ -n "${!key:-}" ]] && ! is_address "${!key}"; then
      echo "Invalid address format for $key: ${!key}" >&2
      exit 1
    fi
  done
}

validate_rehearsal() {
  require_rpc_url
  require_env PRIVATE_KEY
  require_address MARK_SETTLEMENT_OPERATOR

  validate_common_optional_addresses \
    MARK_RYLA_OWNER \
    MARK_MODULE_OWNER \
    MARK_BRIDGE_OPERATOR \
    MARK_SETTLEMENT_ATTESTER \
    MARK_SETTLEMENT_VERIFIER

  assert_true_like MARK_SETTLEMENT_PROOF_ENABLED
  assert_true_like MARK_SETTLEMENT_PRODUCTION_MODE
  assert_true_like MARK_RELEASE_EXECUTE

  local verifier="${MARK_SETTLEMENT_VERIFIER:-0x0000000000000000000000000000000000000000}"
  local deploy_attested="${MARK_DEPLOY_ATTESTED_VERIFIER:-false}"
  if is_zero_address "$verifier" && [[ "$deploy_attested" != "true" && "$deploy_attested" != "1" ]]; then
    echo "Production mode requires verifier or MARK_DEPLOY_ATTESTED_VERIFIER=true" >&2
    exit 1
  fi
}

validate_dispatch() {
  require_rpc_url
  require_address MARK_RYLA_TOKEN
  require_address MARK_SETTLEMENT_MODULE
  require_address MARK_SETTLEMENT_VERIFIER
  require_address MARK_RYLA_OWNER
  require_address MARK_SETTLEMENT_OPERATOR
  reject_known_placeholder_if_strict "MARK_RYLA_TOKEN" "$MARK_RYLA_TOKEN"
  reject_known_placeholder_if_strict "MARK_SETTLEMENT_MODULE" "$MARK_SETTLEMENT_MODULE"
  reject_known_placeholder_if_strict "MARK_SETTLEMENT_VERIFIER" "$MARK_SETTLEMENT_VERIFIER"
  reject_known_placeholder_if_strict "MARK_RYLA_OWNER" "$MARK_RYLA_OWNER"
  reject_known_placeholder_if_strict "MARK_SETTLEMENT_OPERATOR" "$MARK_SETTLEMENT_OPERATOR"

  if [[ -n "${MARK_SETTLEMENT_ATTESTER:-}" ]] && ! is_address "${MARK_SETTLEMENT_ATTESTER}"; then
    echo "Invalid address format for MARK_SETTLEMENT_ATTESTER: ${MARK_SETTLEMENT_ATTESTER}" >&2
    exit 1
  fi
  if [[ -n "${MARK_SETTLEMENT_ATTESTER:-}" ]]; then
    reject_known_placeholder_if_strict "MARK_SETTLEMENT_ATTESTER" "$MARK_SETTLEMENT_ATTESTER"
  fi

  if is_zero_address "$MARK_RYLA_TOKEN" || is_zero_address "$MARK_SETTLEMENT_MODULE" || is_zero_address "$MARK_SETTLEMENT_VERIFIER"; then
    echo "Dispatch mode does not allow zero token/module/verifier addresses" >&2
    exit 1
  fi
}

validate_verify_lock() {
  require_rpc_url
  require_address MARK_RYLA_TOKEN
  require_address MARK_SETTLEMENT_MODULE
  require_address MARK_SETTLEMENT_VERIFIER
  require_address MARK_RYLA_OWNER
  require_address MARK_SETTLEMENT_OPERATOR
  reject_known_placeholder_if_strict "MARK_RYLA_TOKEN" "$MARK_RYLA_TOKEN"
  reject_known_placeholder_if_strict "MARK_SETTLEMENT_MODULE" "$MARK_SETTLEMENT_MODULE"
  reject_known_placeholder_if_strict "MARK_SETTLEMENT_VERIFIER" "$MARK_SETTLEMENT_VERIFIER"
  reject_known_placeholder_if_strict "MARK_RYLA_OWNER" "$MARK_RYLA_OWNER"
  reject_known_placeholder_if_strict "MARK_SETTLEMENT_OPERATOR" "$MARK_SETTLEMENT_OPERATOR"

  if [[ -n "${MARK_SETTLEMENT_ATTESTER:-}" ]] && ! is_address "${MARK_SETTLEMENT_ATTESTER}"; then
    echo "Invalid address format for MARK_SETTLEMENT_ATTESTER: ${MARK_SETTLEMENT_ATTESTER}" >&2
    exit 1
  fi
  if [[ -n "${MARK_SETTLEMENT_ATTESTER:-}" ]]; then
    reject_known_placeholder_if_strict "MARK_SETTLEMENT_ATTESTER" "$MARK_SETTLEMENT_ATTESTER"
  fi
}

case "$MODE" in
  rehearsal)
    validate_rehearsal
    ;;
  dispatch)
    validate_dispatch
    ;;
  verify-lock)
    validate_verify_lock
    ;;
  *)
    echo "Unsupported VALIDATE_MODE: $MODE (expected rehearsal | dispatch | verify-lock)" >&2
    exit 1
    ;;
esac

echo "Env validation PASSED ($MODE)"
