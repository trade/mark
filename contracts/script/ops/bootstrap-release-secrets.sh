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

GH_REPO="${GH_REPO:-$(infer_repo_from_remote)}"
DISPATCH_EXECUTE="${DISPATCH_EXECUTE:-false}"

STAGING_PK="${MARK_STAGING_DEPLOYER_PRIVATE_KEY:-${STAGING_DEPLOYER_PRIVATE_KEY:-}}"
MAINNET_PK="${MARK_DEPLOYER_PRIVATE_KEY:-${MAINNET_DEPLOYER_PRIVATE_KEY:-}}"

echo "Target repo: $GH_REPO"
echo "Will set secrets:"
echo "  - MARK_STAGING_DEPLOYER_PRIVATE_KEY"
echo "  - MARK_DEPLOYER_PRIVATE_KEY"

if [[ "$DISPATCH_EXECUTE" != "true" ]]; then
  echo "Dry run only."
  echo "Set env vars then run with DISPATCH_EXECUTE=true:"
  echo "  MARK_STAGING_DEPLOYER_PRIVATE_KEY=<0x...> MARK_DEPLOYER_PRIVATE_KEY=<0x...> DISPATCH_EXECUTE=true make bootstrap-release-secrets"
  exit 0
fi

require_nonempty "MARK_STAGING_DEPLOYER_PRIVATE_KEY (or STAGING_DEPLOYER_PRIVATE_KEY)" "$STAGING_PK"
require_nonempty "MARK_DEPLOYER_PRIVATE_KEY (or MAINNET_DEPLOYER_PRIVATE_KEY)" "$MAINNET_PK"

printf "%s" "$STAGING_PK" | gh secret set MARK_STAGING_DEPLOYER_PRIVATE_KEY --repo "$GH_REPO" --body -
printf "%s" "$MAINNET_PK" | gh secret set MARK_DEPLOYER_PRIVATE_KEY --repo "$GH_REPO" --body -

echo "Secrets updated successfully for $GH_REPO."
