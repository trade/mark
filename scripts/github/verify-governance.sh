#!/usr/bin/env bash
set -euo pipefail

# Verify governance baseline is active on GitHub repository.
# Required env:
#   GH_PAT=<token with repo read/admin scope>
# Optional:
#   GH_REPO=owner/repo (inferred from origin if omitted)

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "$1 is required" >&2; exit 1; }
}

require_cmd curl
require_cmd jq
require_cmd git

if [[ -z "${GH_PAT:-}" ]]; then
  echo "GH_PAT is required" >&2
  exit 1
fi

infer_repo_from_remote() {
  local remote
  remote="$(git remote get-url origin)"
  if [[ "$remote" =~ ^git@github.com:([^/]+/[^/]+)(\.git)?$ ]]; then
    echo "${BASH_REMATCH[1]}"; return
  fi
  if [[ "$remote" =~ ^https://github.com/([^/]+/[^/]+)(\.git)?$ ]]; then
    echo "${BASH_REMATCH[1]}"; return
  fi
  echo "Could not infer GH_REPO from origin: $remote" >&2
  exit 1
}

GH_REPO="${GH_REPO:-$(infer_repo_from_remote)}"
owner="${GH_REPO%%/*}"
repo="${GH_REPO##*/}"
api="https://api.github.com/repos/${owner}/${repo}"

auth_headers=(
  -H "Authorization: Bearer ${GH_PAT}"
  -H "Accept: application/vnd.github+json"
  -H "X-GitHub-Api-Version: 2022-11-28"
)

require_checks_dev=(
  "Contracts Unit + Invariant"
  "Contracts Release Check (Dry-Run + Execute Smoke)"
  "slither-core / Slither Core Contracts"
  "Detect Secrets Drift"
  "Analyze (javascript-typescript)"
)

require_checks_main=(
  "Contracts Unit + Invariant"
  "Contracts Release Check (Dry-Run + Execute Smoke)"
  "slither-core / Slither Core Contracts"
  "Detect Secrets Drift"
  "Analyze (javascript-typescript)"
  "Validate Release PR Checklist"
  "Validate Release Evidence"
)

get_protection() {
  local branch="$1"
  curl -sS "${auth_headers[@]}" "${api}/branches/${branch}/protection"
}

check_branch() {
  local branch="$1"
  local require_stale="$2"
  shift 2
  local -a expected=("$@")

  echo "[verify] branch=${branch}"
  local json
  json="$(get_protection "$branch")"

  local enabled
  enabled="$(jq -r '.required_status_checks != null' <<<"$json")"
  if [[ "$enabled" != "true" ]]; then
    echo "  FAIL: required_status_checks not enabled for ${branch}" >&2
    return 1
  fi

  if [[ "$require_stale" == "true" ]]; then
    local stale
    stale="$(jq -r '.required_pull_request_reviews.dismiss_stale_reviews // false' <<<"$json")"
    if [[ "$stale" != "true" ]]; then
      echo "  FAIL: dismiss_stale_reviews is not enabled for ${branch}" >&2
      return 1
    fi
  fi

  local missing=0
  for check in "${expected[@]}"; do
    if ! jq -e --arg c "$check" '.required_status_checks.checks[]?.context | select(. == $c)' <<<"$json" >/dev/null; then
      echo "  FAIL: missing required check on ${branch}: ${check}" >&2
      missing=1
    fi
  done

  if [[ $missing -ne 0 ]]; then
    return 1
  fi

  echo "  PASS"
}

# dev has 0 required approvals so dismiss_stale_reviews is not applicable.
check_branch dev    false "${require_checks_dev[@]}"
check_branch canary true  "${require_checks_dev[@]}"
check_branch main   true  "${require_checks_main[@]}"

echo "[verify] governance baseline active for ${GH_REPO}"
