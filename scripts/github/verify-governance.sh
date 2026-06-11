#!/usr/bin/env bash
set -euo pipefail

# Verify governance baseline is active on GitHub repository.
# Required env:
#   GH_PAT=<token with repo read/admin scope>
# Optional:
#   GH_REPO=owner/repo (inferred from origin if omitted)

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "$1 is required" >&2
    exit 1
  }
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
    echo "${BASH_REMATCH[1]%.git}"
    return
  fi
  if [[ "$remote" =~ ^https://github.com/([^/]+/[^/]+)(\.git)?$ ]]; then
    echo "${BASH_REMATCH[1]%.git}"
    return
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

# Required status check contexts. These must mirror apply-governance.sh exactly and
# match the check names GitHub reports. Jobs in ci-fast.yml that call a reusable
# workflow are reported under the compound name "<caller job name> / <callee job name>".
require_checks_dev=(
  "Typecheck + Lint"
  "Secret Scan (trufflehog)"
  "Dependency Review"
  "Detect Secrets Drift"
  "Release Gate Container"
  "Contracts Core (Unit + Invariant) / Contracts Core"
  "Contracts Security (Semgrep) / Semgrep Scan"
  "Contracts Security (Semgrep) / Slither Core Contracts"
  "Contracts Fuzz / Contracts Fuzz"
  "Circuits Core (Build + Tests + Circomspect) / Circuits Core"
  "Frontend Checks (Node 24) / Frontend Checks (Node 24.3.0)"
)

require_checks_main=(
  "Typecheck + Lint"
  "Secret Scan (trufflehog)"
  "Dependency Review"
  "Detect Secrets Drift"
  "Release Gate Container"
  "Contracts Core (Unit + Invariant) / Contracts Core"
  "Contracts Security (Semgrep) / Semgrep Scan"
  "Contracts Security (Semgrep) / Slither Core Contracts"
  "Contracts Fuzz / Contracts Fuzz"
  "Circuits Core (Build + Tests + Circomspect) / Circuits Core"
  "Frontend Checks (Node 24) / Frontend Checks (Node 24.3.0)"
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
  local expected_approvals="$3"
  shift 3
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

  if [[ "$require_stale" == "true" && "$expected_approvals" != "0" ]]; then
    local stale
    stale="$(jq -r '.required_pull_request_reviews.dismiss_stale_reviews // false' <<<"$json")"
    if [[ "$stale" != "true" ]]; then
      echo "  FAIL: dismiss_stale_reviews is not enabled for ${branch}" >&2
      return 1
    fi
  fi

  local actual_approvals
  actual_approvals="$(jq -r '.required_pull_request_reviews.required_approving_review_count // 0' <<<"$json")"
  if [[ "$actual_approvals" != "$expected_approvals" ]]; then
    echo "  FAIL: required_approving_review_count is ${actual_approvals}, expected ${expected_approvals} for ${branch}" >&2
    return 1
  fi

  # apply-governance.sh's build_restrictions() supports either a team-based restriction
  # (default: maintainers) or a user-based one (MAIN_PUSH_ALLOW_USERS/DEV_PUSH_ALLOW_USERS).
  # Accept either, but require that some push restriction is configured.
  local push_restricted
  push_restricted="$(jq -r '
    (((.restrictions.teams // []) | map(.slug) | index("maintainers")) != null)
    or (((.restrictions.users // []) | length) > 0)
  ' <<<"$json")"
  if [[ "$push_restricted" != "true" ]]; then
    echo "  FAIL: push restrictions must include the maintainers team or explicit users for ${branch}" >&2
    return 1
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

# All branches use 0 required approvals — sole maintainer cannot approve own PRs.
check_branch dev false 0 "${require_checks_dev[@]}"
check_branch main true 0 "${require_checks_main[@]}"

echo "[verify] governance baseline active for ${GH_REPO}"
