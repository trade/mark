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

require_cmd gh
require_cmd jq
require_cmd git

infer_repo_from_remote() {
  local remote
  remote="$(git remote get-url origin)"
  if [[ "$remote" =~ ^git@github.com:([^/]+/[^.]+)(\.git)?$ ]]; then
    echo "${BASH_REMATCH[1]}"
    return
  fi
  if [[ "$remote" =~ ^https://github.com/([^/]+/[^.]+)(\.git)?$ ]]; then
    echo "${BASH_REMATCH[1]}"
    return
  fi
  echo "Could not infer GH_REPO from origin: $remote" >&2
  exit 1
}

require_nonempty() {
  local label="$1"
  local value="$2"
  if [[ -z "$value" ]]; then
    echo "Missing required value: $label" >&2
    exit 1
  fi
}

ARTIFACT_PATH="${MARK_RELEASE_ARTIFACT_PATH:-broadcast/mark-release-latest.json}"
WORKFLOW_FILE="${WORKFLOW_FILE:-contracts-production-lock-verify.yml}"
GH_REF="${GH_REF:-main}"
GH_REPO="${GH_REPO:-$(infer_repo_from_remote)}"
DISPATCH_EXECUTE="${DISPATCH_EXECUTE:-false}"

RPC_URL="${RPC_URL:-}"
TOKEN_ADDRESS="${MARK_RYLA_TOKEN:-${VERIFY_MARK_RYLA_TOKEN:-}}"
MODULE_ADDRESS="${MARK_SETTLEMENT_MODULE:-${VERIFY_MARK_SETTLEMENT_MODULE:-}}"
VERIFIER_ADDRESS="${MARK_SETTLEMENT_VERIFIER:-${VERIFY_MARK_SETTLEMENT_VERIFIER:-}}"
OWNER_ADDRESS="${MARK_RYLA_OWNER:-${VERIFY_MARK_RYLA_OWNER:-}}"
SETTLEMENT_OPERATOR="${MARK_SETTLEMENT_OPERATOR:-${VERIFY_MARK_SETTLEMENT_OPERATOR:-}}"
ATTESTER_ADDRESS="${MARK_SETTLEMENT_ATTESTER:-${VERIFY_MARK_SETTLEMENT_ATTESTER:-0x0000000000000000000000000000000000000000}}"

if [[ -f "$ARTIFACT_PATH" ]]; then
  if [[ -z "$TOKEN_ADDRESS" ]]; then TOKEN_ADDRESS="$(jq -r '.token // empty' "$ARTIFACT_PATH")"; fi
  if [[ -z "$MODULE_ADDRESS" ]]; then MODULE_ADDRESS="$(jq -r '.module // empty' "$ARTIFACT_PATH")"; fi
  if [[ -z "$VERIFIER_ADDRESS" ]]; then VERIFIER_ADDRESS="$(jq -r '.verifier // empty' "$ARTIFACT_PATH")"; fi
fi

require_nonempty "RPC_URL" "$RPC_URL"
require_nonempty "token_address" "$TOKEN_ADDRESS"
require_nonempty "module_address" "$MODULE_ADDRESS"
require_nonempty "verifier_address" "$VERIFIER_ADDRESS"
require_nonempty "owner_address" "$OWNER_ADDRESS"
require_nonempty "settlement_operator" "$SETTLEMENT_OPERATOR"

export MARK_RYLA_TOKEN="$TOKEN_ADDRESS"
export MARK_SETTLEMENT_MODULE="$MODULE_ADDRESS"
export MARK_SETTLEMENT_VERIFIER="$VERIFIER_ADDRESS"
export MARK_RYLA_OWNER="$OWNER_ADDRESS"
export MARK_SETTLEMENT_OPERATOR
export MARK_SETTLEMENT_ATTESTER="$ATTESTER_ADDRESS"
export MARK_ENV_STRICT_PLACEHOLDERS=true
VALIDATE_MODE=dispatch ./script/ops/validate-prod-env.sh

CMD=(
  gh workflow run "$WORKFLOW_FILE"
  --repo "$GH_REPO"
  --ref "$GH_REF"
  -f "rpc_url=$RPC_URL"
  -f "token_address=$TOKEN_ADDRESS"
  -f "module_address=$MODULE_ADDRESS"
  -f "verifier_address=$VERIFIER_ADDRESS"
  -f "owner_address=$OWNER_ADDRESS"
  -f "settlement_operator=$SETTLEMENT_OPERATOR"
  -f "attester_address=$ATTESTER_ADDRESS"
)

echo "Dispatch target repo: $GH_REPO"
echo "Workflow: $WORKFLOW_FILE"
echo "Ref: $GH_REF"
echo "rpc_url=$RPC_URL"
echo "token_address=$TOKEN_ADDRESS"
echo "module_address=$MODULE_ADDRESS"
echo "verifier_address=$VERIFIER_ADDRESS"
echo "owner_address=$OWNER_ADDRESS"
echo "settlement_operator=$SETTLEMENT_OPERATOR"
echo "attester_address=$ATTESTER_ADDRESS"

if [[ "$DISPATCH_EXECUTE" != "true" ]]; then
  echo "Dry run only. Set DISPATCH_EXECUTE=true to run:"
  printf '  %q' "${CMD[@]}"
  printf '\n'
  exit 0
fi

"${CMD[@]}"

echo "Workflow dispatched."
echo "Inspect runs with:"
echo "  gh run list --repo $GH_REPO --workflow \"$WORKFLOW_FILE\" --limit 5"
