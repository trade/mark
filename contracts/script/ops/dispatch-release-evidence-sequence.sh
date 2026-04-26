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

require_secret() {
  local repo="$1"
  local secret_name="$2"
  if ! gh api "/repos/$repo/actions/secrets/$secret_name" >/dev/null 2>&1; then
    echo "Required GitHub Actions secret missing in $repo: $secret_name" >&2
    exit 1
  fi
}

fetch_latest_run_id_for_ref() {
  local repo="$1"
  local workflow="$2"
  local ref="$3"
  gh run list \
    --repo "$repo" \
    --workflow "$workflow" \
    --branch "$ref" \
    --limit 1 \
    --json databaseId \
    --jq '.[0].databaseId // empty'
}

fetch_run_conclusion() {
  local repo="$1"
  local run_id="$2"
  gh run view "$run_id" --repo "$repo" --json conclusion --jq '.conclusion // empty'
}

wait_for_success() {
  local repo="$1"
  local run_id="$2"
  gh run watch "$run_id" --repo "$repo"
  local conclusion
  conclusion="$(fetch_run_conclusion "$repo" "$run_id")"
  if [[ "$conclusion" != "success" ]]; then
    echo "Run did not succeed: run_id=$run_id conclusion=$conclusion" >&2
    exit 1
  fi
}

GH_REPO="${GH_REPO:-$(infer_repo_from_remote)}"
GH_REF="${GH_REF:-main}"
DISPATCH_EXECUTE="${DISPATCH_EXECUTE:-false}"
WAIT_FOR_COMPLETION="${WAIT_FOR_COMPLETION:-false}"

STAGING_WORKFLOW="${STAGING_WORKFLOW:-contracts-staging-rehearsal.yml}"
MAINNET_WORKFLOW="${MAINNET_WORKFLOW:-contracts-mainnet-readiness.yml}"
PROMOTION_WORKFLOW="${PROMOTION_WORKFLOW:-contracts-promotion-checklist.yml}"

STAGING_RPC_URL="${STAGING_RPC_URL:-}"
STAGING_SETTLEMENT_OPERATOR="${STAGING_SETTLEMENT_OPERATOR:-}"
STAGING_OWNER_ADDRESS="${STAGING_OWNER_ADDRESS:-}"
STAGING_BRIDGE_OPERATOR="${STAGING_BRIDGE_OPERATOR:-}"
STAGING_DESTINATION_CHAIN_ID="${STAGING_DESTINATION_CHAIN_ID:-10}"
STAGING_ATTESTER_ADDRESS="${STAGING_ATTESTER_ADDRESS:-0x0000000000000000000000000000000000000000}"
STAGING_RELEASE_ARTIFACT_PATH="${STAGING_RELEASE_ARTIFACT_PATH:-broadcast/mark-staging-release.json}"
STAGING_REHEARSAL_ARTIFACT_PATH="${STAGING_REHEARSAL_ARTIFACT_PATH:-broadcast/mark-staging-rehearsal.json}"

MAINNET_RPC_URL="${MAINNET_RPC_URL:-}"
MAINNET_MODE="${MAINNET_MODE:-predeploy}"
MAINNET_ARTIFACT_PATH="${MAINNET_ARTIFACT_PATH:-broadcast/mark-mainnet-gate-ci.json}"

PROMOTION_FRESHNESS_HOURS="${PROMOTION_FRESHNESS_HOURS:-72}"
PROMOTION_CHECKLIST_PATH="${PROMOTION_CHECKLIST_PATH:-broadcast/mark-promotion-checklist.json}"
PROMOTION_CHECKLIST_MARKDOWN_PATH="${PROMOTION_CHECKLIST_MARKDOWN_PATH:-broadcast/mark-promotion-checklist.md}"

require_nonempty "STAGING_RPC_URL" "$STAGING_RPC_URL"
require_nonempty "STAGING_SETTLEMENT_OPERATOR" "$STAGING_SETTLEMENT_OPERATOR"
require_nonempty "MAINNET_RPC_URL" "$MAINNET_RPC_URL"

STAGING_CMD=(
  gh workflow run "$STAGING_WORKFLOW"
  --repo "$GH_REPO"
  --ref "$GH_REF"
  -f "rpc_url=$STAGING_RPC_URL"
  -f "owner_address=$STAGING_OWNER_ADDRESS"
  -f "settlement_operator=$STAGING_SETTLEMENT_OPERATOR"
  -f "bridge_operator=$STAGING_BRIDGE_OPERATOR"
  -f "destination_chain_id=$STAGING_DESTINATION_CHAIN_ID"
  -f "attester_address=$STAGING_ATTESTER_ADDRESS"
  -f "release_artifact_path=$STAGING_RELEASE_ARTIFACT_PATH"
  -f "rehearsal_artifact_path=$STAGING_REHEARSAL_ARTIFACT_PATH"
)

MAINNET_CMD=(
  gh workflow run "$MAINNET_WORKFLOW"
  --repo "$GH_REPO"
  --ref "$GH_REF"
  -f "mode=$MAINNET_MODE"
  -f "rpc_url=$MAINNET_RPC_URL"
  -f "artifact_path=$MAINNET_ARTIFACT_PATH"
)

echo "Dispatch target repo: $GH_REPO"
echo "Dispatch ref: $GH_REF"
echo "Staging workflow: $STAGING_WORKFLOW"
echo "Mainnet workflow: $MAINNET_WORKFLOW"
echo "Promotion workflow: $PROMOTION_WORKFLOW"
echo "wait_for_completion=$WAIT_FOR_COMPLETION"
echo "promotion_freshness_hours=$PROMOTION_FRESHNESS_HOURS"

if [[ "$DISPATCH_EXECUTE" != "true" ]]; then
  echo "Dry run only. Set DISPATCH_EXECUTE=true to run:"
  printf '  %q' "${STAGING_CMD[@]}"
  printf '\n'
  printf '  %q' "${MAINNET_CMD[@]}"
  printf '\n'
  if [[ "$WAIT_FOR_COMPLETION" == "true" ]]; then
    echo "  # promotion checklist auto-dispatches after both runs succeed"
  else
    echo "  # then dispatch promotion checklist manually with run IDs"
  fi
  exit 0
fi

require_secret "$GH_REPO" "MARK_STAGING_DEPLOYER_PRIVATE_KEY"
require_secret "$GH_REPO" "MARK_DEPLOYER_PRIVATE_KEY"

"${STAGING_CMD[@]}"
"${MAINNET_CMD[@]}"

echo "Staging + mainnet workflows dispatched."

if [[ "$WAIT_FOR_COMPLETION" != "true" ]]; then
  echo "Wait disabled. After both runs succeed, dispatch promotion checklist with:"
  echo "  gh workflow run $PROMOTION_WORKFLOW --repo $GH_REPO --ref $GH_REF -f staging_run_id=<id> -f mainnet_run_id=<id> -f freshness_hours=$PROMOTION_FRESHNESS_HOURS"
  exit 0
fi

# Allow GH API indexing time so latest run lookup is stable.
sleep 5

staging_run_id="$(fetch_latest_run_id_for_ref "$GH_REPO" "$STAGING_WORKFLOW" "$GH_REF")"
mainnet_run_id="$(fetch_latest_run_id_for_ref "$GH_REPO" "$MAINNET_WORKFLOW" "$GH_REF")"

require_nonempty "staging_run_id" "$staging_run_id"
require_nonempty "mainnet_run_id" "$mainnet_run_id"

echo "Watching staging run: $staging_run_id"
wait_for_success "$GH_REPO" "$staging_run_id"

echo "Watching mainnet run: $mainnet_run_id"
wait_for_success "$GH_REPO" "$mainnet_run_id"

gh workflow run "$PROMOTION_WORKFLOW" \
  --repo "$GH_REPO" \
  --ref "$GH_REF" \
  -f "staging_run_id=$staging_run_id" \
  -f "mainnet_run_id=$mainnet_run_id" \
  -f "checklist_path=$PROMOTION_CHECKLIST_PATH" \
  -f "checklist_markdown_path=$PROMOTION_CHECKLIST_MARKDOWN_PATH" \
  -f "freshness_hours=$PROMOTION_FRESHNESS_HOURS"

echo "Promotion checklist workflow dispatched."
echo "Inspect runs with:"
echo "  gh run list --repo $GH_REPO --workflow \"$PROMOTION_WORKFLOW\" --limit 5"
