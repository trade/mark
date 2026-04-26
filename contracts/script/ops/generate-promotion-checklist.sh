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
  if [[ -z "$value" || "$value" == "null" ]]; then
    echo "Missing required value: $label" >&2
    exit 1
  fi
}

fetch_latest_success_run_id() {
  local repo="$1"
  local workflow="$2"
  local branch="${3:-}"
  local args=(run list --repo "$repo" --workflow "$workflow" --status success --limit 1 --json databaseId)
  if [[ -n "$branch" ]]; then
    args+=(--branch "$branch")
  fi
  gh "${args[@]}" | jq -r '.[0].databaseId // empty'
}

fetch_run_json() {
  local repo="$1"
  local run_id="$2"
  gh api "/repos/$repo/actions/runs/$run_id"
}

fetch_artifacts_json() {
  local repo="$1"
  local run_id="$2"
  gh api "/repos/$repo/actions/runs/$run_id/artifacts?per_page=100"
}

fetch_compare_json() {
  local repo="$1"
  local base_sha="$2"
  local head_sha="$3"
  gh api "/repos/$repo/compare/$base_sha...$head_sha"
}

GH_REPO="${GH_REPO:-$(infer_repo_from_remote)}"
STAGING_WORKFLOW="${STAGING_WORKFLOW:-contracts-staging-rehearsal.yml}"
MAINNET_WORKFLOW="${MAINNET_WORKFLOW:-contracts-mainnet-readiness.yml}"
STAGING_RUN_ID="${STAGING_RUN_ID:-}"
MAINNET_RUN_ID="${MAINNET_RUN_ID:-}"
MAINNET_BRANCH="${MAINNET_BRANCH:-main}"
CHECKLIST_PATH="${PROMOTION_CHECKLIST_PATH:-broadcast/mark-promotion-checklist.json}"
CHECKLIST_MARKDOWN_PATH="${PROMOTION_CHECKLIST_MARKDOWN_PATH:-broadcast/mark-promotion-checklist.md}"
GENERATED_BY="${GENERATED_BY:-manual}"
FRESHNESS_HOURS="${FRESHNESS_HOURS:-72}"
STRICT_PROMOTION_CHECKS="${STRICT_PROMOTION_CHECKS:-true}"

if [[ -z "$STAGING_RUN_ID" ]]; then
  STAGING_RUN_ID="$(fetch_latest_success_run_id "$GH_REPO" "$STAGING_WORKFLOW" "")"
fi
if [[ -z "$MAINNET_RUN_ID" ]]; then
  MAINNET_RUN_ID="$(fetch_latest_success_run_id "$GH_REPO" "$MAINNET_WORKFLOW" "$MAINNET_BRANCH")"
fi

require_nonempty "STAGING_RUN_ID" "$STAGING_RUN_ID"
require_nonempty "MAINNET_RUN_ID" "$MAINNET_RUN_ID"

STAGING_RUN_JSON="$(fetch_run_json "$GH_REPO" "$STAGING_RUN_ID")"
MAINNET_RUN_JSON="$(fetch_run_json "$GH_REPO" "$MAINNET_RUN_ID")"
STAGING_ARTIFACTS_JSON="$(fetch_artifacts_json "$GH_REPO" "$STAGING_RUN_ID")"
MAINNET_ARTIFACTS_JSON="$(fetch_artifacts_json "$GH_REPO" "$MAINNET_RUN_ID")"

STAGING_SHA="$(jq -r '.head_sha // empty' <<<"$STAGING_RUN_JSON")"
MAINNET_SHA="$(jq -r '.head_sha // empty' <<<"$MAINNET_RUN_JSON")"
require_nonempty "staging head sha" "$STAGING_SHA"
require_nonempty "mainnet head sha" "$MAINNET_SHA"

COMPARE_JSON="$(fetch_compare_json "$GH_REPO" "$STAGING_SHA" "$MAINNET_SHA")"
COMPARE_STATUS="$(jq -r '.status // empty' <<<"$COMPARE_JSON")"

mkdir -p "$(dirname "$CHECKLIST_PATH")"

jq -n \
  --arg generatedAt "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  --arg generatedBy "$GENERATED_BY" \
  --arg repo "$GH_REPO" \
  --arg stagingWorkflow "$STAGING_WORKFLOW" \
  --arg mainnetWorkflow "$MAINNET_WORKFLOW" \
  --arg freshnessHours "$FRESHNESS_HOURS" \
  --arg compareStatus "$COMPARE_STATUS" \
  --argjson stagingRun "$STAGING_RUN_JSON" \
  --argjson mainnetRun "$MAINNET_RUN_JSON" \
  --argjson stagingArtifacts "$STAGING_ARTIFACTS_JSON" \
  --argjson mainnetArtifacts "$MAINNET_ARTIFACTS_JSON" \
  --argjson compare "$COMPARE_JSON" \
  '{
    generatedAt: $generatedAt,
    generatedBy: $generatedBy,
    repository: $repo,
    policy: {
      freshnessHours: ($freshnessHours | tonumber),
      lineageRule: "mainnet-head must be identical-or-ahead of staging-head"
    },
    goNoGo: {
      decision: "pending",
      rationale: "",
      requiredApprovals: [
        "protocol-owner-admin",
        "security-reviewer",
        "deployment-operator"
      ]
    },
    stagingRehearsal: {
      workflow: $stagingWorkflow,
      runId: $stagingRun.id,
      runNumber: $stagingRun.run_number,
      conclusion: $stagingRun.conclusion,
      status: $stagingRun.status,
      branch: $stagingRun.head_branch,
      commit: $stagingRun.head_sha,
      htmlUrl: $stagingRun.html_url,
      createdAt: $stagingRun.created_at,
      updatedAt: $stagingRun.updated_at,
      artifacts: ($stagingArtifacts.artifacts // [] | map({
        id,
        name,
        size_in_bytes,
        expired,
        created_at,
        expires_at
      }))
    },
    mainnetReadiness: {
      workflow: $mainnetWorkflow,
      runId: $mainnetRun.id,
      runNumber: $mainnetRun.run_number,
      conclusion: $mainnetRun.conclusion,
      status: $mainnetRun.status,
      branch: $mainnetRun.head_branch,
      commit: $mainnetRun.head_sha,
      htmlUrl: $mainnetRun.html_url,
      createdAt: $mainnetRun.created_at,
      updatedAt: $mainnetRun.updated_at,
      artifacts: ($mainnetArtifacts.artifacts // [] | map({
        id,
        name,
        size_in_bytes,
        expired,
        created_at,
        expires_at
      }))
    },
    lineage: {
      base: $stagingRun.head_sha,
      head: $mainnetRun.head_sha,
      status: $compareStatus,
      aheadBy: ($compare.ahead_by // 0),
      behindBy: ($compare.behind_by // 0),
      totalCommits: ($compare.total_commits // 0),
      htmlUrl: ($compare.html_url // "")
    },
    checks: [
      {
        id: "staging-rehearsal-success",
        passed: ($stagingRun.conclusion == "success")
      },
      {
        id: "mainnet-readiness-success",
        passed: ($mainnetRun.conclusion == "success")
      },
      {
        id: "staging-artifact-present",
        passed: (($stagingArtifacts.artifacts // [] | map(.name) | index("mark-staging-rehearsal")) != null)
      },
      {
        id: "mainnet-artifact-present",
        passed: (($mainnetArtifacts.artifacts // [] | map(.name) | index("mark-mainnet-readiness-artifact")) != null)
      },
      {
        id: "staging-fresh-enough",
        passed: (
          ((now - ($stagingRun.created_at | fromdateiso8601)) / 3600)
          <= ($freshnessHours | tonumber)
        )
      },
      {
        id: "mainnet-fresh-enough",
        passed: (
          ((now - ($mainnetRun.created_at | fromdateiso8601)) / 3600)
          <= ($freshnessHours | tonumber)
        )
      },
      {
        id: "lineage-identical-or-ahead",
        passed: (($compareStatus == "identical") or ($compareStatus == "ahead"))
      }
    ]
  }' >"$CHECKLIST_PATH"

jq -r '
  "# MARK Promotion Checklist",
  "",
  "- Generated At: \(.generatedAt)",
  "- Repository: \(.repository)",
  "- Freshness Window (hours): \(.policy.freshnessHours)",
  "- Go/No-Go Decision: \(.goNoGo.decision)",
  "",
  "## Staging Rehearsal",
  "- Workflow: \(.stagingRehearsal.workflow)",
  "- Run: \(.stagingRehearsal.runId) (\(.stagingRehearsal.htmlUrl))",
  "- Conclusion: \(.stagingRehearsal.conclusion)",
  "- Commit: \(.stagingRehearsal.commit)",
  "- Artifacts: " + ((.stagingRehearsal.artifacts | map(.name) | join(", ")) // "none"),
  "",
  "## Mainnet Readiness",
  "- Workflow: \(.mainnetReadiness.workflow)",
  "- Run: \(.mainnetReadiness.runId) (\(.mainnetReadiness.htmlUrl))",
  "- Conclusion: \(.mainnetReadiness.conclusion)",
  "- Commit: \(.mainnetReadiness.commit)",
  "- Artifacts: " + ((.mainnetReadiness.artifacts | map(.name) | join(", ")) // "none"),
  "",
  "## Lineage",
  "- Compare: \(.lineage.base)...\(.lineage.head)",
  "- Status: \(.lineage.status)",
  "- Ahead By: \(.lineage.aheadBy)",
  "- Behind By: \(.lineage.behindBy)",
  "- URL: \(.lineage.htmlUrl)",
  "",
  "## Gate Checks",
  (.checks[] | "- \(.id): " + (if .passed then "PASS" else "FAIL" end))
' "$CHECKLIST_PATH" >"$CHECKLIST_MARKDOWN_PATH"

checks_passed="$(jq -r '[.checks[].passed] | all' "$CHECKLIST_PATH")"

echo "Promotion checklist generated:"
echo "  JSON: $CHECKLIST_PATH"
echo "  Markdown: $CHECKLIST_MARKDOWN_PATH"

if [[ "$checks_passed" != "true" ]]; then
  echo "Promotion checklist policy checks FAILED." >&2
  if [[ "$STRICT_PROMOTION_CHECKS" == "true" || "$STRICT_PROMOTION_CHECKS" == "1" ]]; then
    exit 1
  fi
fi
