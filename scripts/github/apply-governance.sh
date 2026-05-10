#!/usr/bin/env bash
set -euo pipefail

# Applies repository governance defaults:
# - branch protection for main and dev
# - creates/updates production environment
#
# Required env:
#   GH_PAT=<github token with repo admin permissions>
# Optional env:
#   GH_REPO=owner/repo (default: inferred from git remote origin)
#   MAIN_REVIEW_COUNT=2
#   DEV_REVIEW_COUNT=1
#   PRODUCTION_REVIEWER_IDS=12345,67890   # GitHub user IDs
#   MAIN_PUSH_ALLOW_USERS=user1,user2     # optional login allowlist for direct push
#   MAIN_PUSH_ALLOW_TEAMS=team-slug       # optional team slug allowlist
#   MAIN_PUSH_ALLOW_APPS=app-slug         # optional GitHub App allowlist
#   DEV_PUSH_ALLOW_USERS=user1,user2      # optional login allowlist for direct push
#   DEV_PUSH_ALLOW_TEAMS=team-slug        # optional team slug allowlist
#   DEV_PUSH_ALLOW_APPS=app-slug          # optional GitHub App allowlist

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 1
fi

if [[ -z "${GH_PAT:-}" ]]; then
  echo "GH_PAT is required" >&2
  exit 1
fi

infer_repo_from_remote() {
  local remote
  remote="$(git remote get-url origin)"
  # Supports:
  #   git@github.com:owner/repo.git
  #   https://github.com/owner/repo.git
  if [[ "$remote" =~ ^git@github.com:([^/]+/[^/]+)(\.git)?$ ]]; then
    echo "${BASH_REMATCH[1]}"
    return
  fi
  if [[ "$remote" =~ ^https://github.com/([^/]+/[^/]+)(\.git)?$ ]]; then
    echo "${BASH_REMATCH[1]}"
    return
  fi
  echo "Could not infer GH_REPO from origin: $remote" >&2
  exit 1
}

GH_REPO="${GH_REPO:-$(infer_repo_from_remote)}"
MAIN_REVIEW_COUNT="${MAIN_REVIEW_COUNT:-2}"
DEV_REVIEW_COUNT="${DEV_REVIEW_COUNT:-1}"

owner="${GH_REPO%%/*}"
repo="${GH_REPO##*/}"
api="https://api.github.com/repos/${owner}/${repo}"

auth_headers=(
  -H "Authorization: Bearer ${GH_PAT}"
  -H "Accept: application/vnd.github+json"
  -H "X-GitHub-Api-Version: 2022-11-28"
)

echo "Applying governance to ${GH_REPO}..."

csv_to_json_array() {
  local csv="${1:-}"
  if [[ -z "$csv" ]]; then
    echo "[]"
    return
  fi

  awk -v csv="$csv" 'BEGIN {
    n=split(csv, a, ",");
    printf("[");
    first=1;
    for (i=1; i<=n; i++) {
      gsub(/^[ \t]+|[ \t]+$/, "", a[i]);
      if (a[i] == "") continue;
      gsub(/\\/,"\\\\",a[i]);
      gsub(/"/,"\\\"",a[i]);
      if (!first) printf(",");
      printf("\"%s\"", a[i]);
      first=0;
    }
    printf("]");
  }'
}

build_restrictions_json() {
  local users_csv="${1:-}"
  local teams_csv="${2:-}"
  local apps_csv="${3:-}"
  local users_json teams_json apps_json
  users_json="$(csv_to_json_array "$users_csv")"
  teams_json="$(csv_to_json_array "$teams_csv")"
  apps_json="$(csv_to_json_array "$apps_csv")"

  if [[ "$users_json" == "[]" && "$teams_json" == "[]" && "$apps_json" == "[]" ]]; then
    echo "null"
    return
  fi

  jq -n \
    --argjson users "$users_json" \
    --argjson teams "$teams_json" \
    --argjson apps "$apps_json" \
    '{users: $users, teams: $teams, apps: $apps}'
}

apply_branch_protection() {
  local branch="$1"
  local review_count="$2"
  local checks_json="$3"
  local restrictions_json="$4"

  local payload
  payload="$(
    jq -n \
      --argjson review_count "$review_count" \
      --argjson checks "$checks_json" \
      --argjson restrictions "${restrictions_json}" \
      '{
        required_status_checks: {
          strict: true,
          checks: ($checks | map({ context: . }))
        },
        enforce_admins: true,
        required_pull_request_reviews: {
          dismissal_restrictions: {},
          dismiss_stale_reviews: true,
          require_code_owner_reviews: false,
          required_approving_review_count: $review_count,
          require_last_push_approval: false
        },
        restrictions: $restrictions,
        required_linear_history: false,
        allow_force_pushes: false,
        allow_deletions: false,
        block_creations: false,
        required_conversation_resolution: true,
        lock_branch: false,
        allow_fork_syncing: false
      }'
  )"

  echo "  - protecting branch: ${branch}"
  local tmp_body
  tmp_body="$(mktemp)"
  local http_code
  http_code="$(
    curl -sS -o "${tmp_body}" -w "%{http_code}" -X PUT \
      "${auth_headers[@]}" \
      "${api}/branches/${branch}/protection" \
      -d "${payload}"
  )"

  if [[ "${http_code}" == "200" ]]; then
    rm -f "${tmp_body}"
    return
  fi

  if [[ "${http_code}" == "403" ]] && grep -q "Upgrade to GitHub Pro" "${tmp_body}"; then
    echo "    ! skipped: branch protection requires GitHub Pro/Team on private repos"
    rm -f "${tmp_body}"
    return
  fi

  echo "    ! failed (${http_code}) while protecting ${branch}:"
  cat "${tmp_body}"
  rm -f "${tmp_body}"
  return 1
}

ensure_environment() {
  local env_name="$1"
  local payload="$2"
  local tmp_body
  tmp_body="$(mktemp)"
  local http_code
  http_code="$(
    curl -sS -o "${tmp_body}" -w "%{http_code}" -X PUT \
      "${auth_headers[@]}" \
      "${api}/environments/${env_name}" \
      -d "${payload}"
  )"

  if [[ "${http_code}" == "200" ]]; then
    rm -f "${tmp_body}"
    return
  fi

  if [[ "${http_code}" == "422" ]] && grep -q "billing plan supports the required reviewers protection rule" "${tmp_body}"; then
    echo "    ! skipped: required reviewers rule not available on current billing plan"
    rm -f "${tmp_body}"
    return
  fi

  echo "    ! failed (${http_code}) while configuring environment ${env_name}:"
  cat "${tmp_body}"
  rm -f "${tmp_body}"
  return 1
}

# Baseline checks for dev, canary, and main.
DEV_CHECKS_JSON='[
  "Analyze (javascript-typescript)",
  "Dependency Review",
  "Contracts Unit + Invariant",
  "Contracts Release Check (Dry-Run + Execute Smoke)",
  "Contracts Production Mode Smoke",
  "gitleaks / Gitleaks Scan",
  "slither-core / Slither Core Contracts",
  "frontend-checks / Frontend Checks (Node 20)",
  "frontend-checks / Frontend Checks (Node 22)",
  "Detect Secrets Drift",
  "Release Gate Container"
]'
CANARY_CHECKS_JSON='[
  "Analyze (javascript-typescript)",
  "Dependency Review",
  "Contracts Unit + Invariant",
  "Contracts Release Check (Dry-Run + Execute Smoke)",
  "Contracts Production Mode Smoke",
  "gitleaks / Gitleaks Scan",
  "slither-core / Slither Core Contracts",
  "frontend-checks / Frontend Checks (Node 20)",
  "frontend-checks / Frontend Checks (Node 22)",
  "Detect Secrets Drift",
  "Release Gate Container"
]'
MAIN_CHECKS_JSON='[
  "Analyze (javascript-typescript)",
  "Dependency Review",
  "Contracts Unit + Invariant",
  "Contracts Release Check (Dry-Run + Execute Smoke)",
  "Contracts Production Mode Smoke",
  "gitleaks / Gitleaks Scan",
  "slither-core / Slither Core Contracts",
  "frontend-checks / Frontend Checks (Node 20)",
  "frontend-checks / Frontend Checks (Node 22)",
  "Detect Secrets Drift",
  "Release Gate Container",
  "Validate Release PR Checklist",
  "Validate Release Evidence"
]'

MAIN_RESTRICTIONS_JSON="$(build_restrictions_json "${MAIN_PUSH_ALLOW_USERS:-}" "${MAIN_PUSH_ALLOW_TEAMS:-}" "${MAIN_PUSH_ALLOW_APPS:-}")"
CANARY_RESTRICTIONS_JSON="$(build_restrictions_json "${CANARY_PUSH_ALLOW_USERS:-}" "${CANARY_PUSH_ALLOW_TEAMS:-}" "${CANARY_PUSH_ALLOW_APPS:-}")"
DEV_RESTRICTIONS_JSON="$(build_restrictions_json "${DEV_PUSH_ALLOW_USERS:-}" "${DEV_PUSH_ALLOW_TEAMS:-}" "${DEV_PUSH_ALLOW_APPS:-}")"

if [[ "$MAIN_RESTRICTIONS_JSON" == "null" ]]; then
  echo "  - note: MAIN push restrictions not set (provide MAIN_PUSH_ALLOW_* to restrict direct push safely)"
fi

# main: strict, no direct pushes
apply_branch_protection "main" "${MAIN_REVIEW_COUNT}" "$MAIN_CHECKS_JSON" "$MAIN_RESTRICTIONS_JSON"

# canary: PR + checks; stabilisation track
apply_branch_protection "canary" "1" "$CANARY_CHECKS_JSON" "$CANARY_RESTRICTIONS_JSON"

# dev: PR + checks; direct pushes configurable by changing restrict_pushes here
apply_branch_protection "dev" "${DEV_REVIEW_COUNT}" "$DEV_CHECKS_JSON" "$DEV_RESTRICTIONS_JSON"

# Ensure production environment exists
echo "  - ensuring environment: production"
ensure_environment "production" '{}'

# Optional: set required reviewers for production environment
if [[ -n "${PRODUCTION_REVIEWER_IDS:-}" ]]; then
  reviewers_json="$(
    awk -v ids="${PRODUCTION_REVIEWER_IDS}" 'BEGIN{
      n=split(ids,a,",");
      printf("[");
      for(i=1;i<=n;i++){
        gsub(/^[ \t]+|[ \t]+$/, "", a[i]);
        if (a[i] ~ /^[0-9]+$/) {
          if (i>1) printf(",");
          printf("{\"type\":\"User\",\"id\":%s}", a[i]);
        }
      }
      printf("]");
    }'
  )"

  env_payload="$(jq -n --argjson reviewers "${reviewers_json}" '{reviewers: $reviewers, wait_timer: 0}')"
  echo "  - applying production reviewers"
  ensure_environment "production" "${env_payload}"
fi

echo "Done."
echo "Next: manually verify branch protection toggles in GitHub UI."
