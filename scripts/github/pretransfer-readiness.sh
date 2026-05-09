#!/usr/bin/env bash
set -euo pipefail

# Pre-transfer readiness checks for org migration.
# Required env:
#   GH_PAT=<token with repo admin read scope>
# Optional:
#   GH_REPO=owner/repo (inferred from origin)

require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "$1 is required" >&2; exit 1; }; }
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
auth_headers=(-H "Authorization: Bearer ${GH_PAT}" -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28")

echo "[pretransfer] repo=${GH_REPO}"

# Basic repo access check
curl -sS "${auth_headers[@]}" "${api}" | jq -e '.full_name != null' >/dev/null

echo "[pretransfer] checking required workflow files"
required_workflows=(
  ".github/workflows/codeql.yml"
  ".github/workflows/secrets-scan.yml"
  ".github/workflows/governance-verify.yml"
  ".github/workflows/contracts-release-gate-container.yml"
)
for wf in "${required_workflows[@]}"; do
  if [[ ! -f "$wf" ]]; then
    echo "  FAIL: missing workflow file: $wf" >&2
    exit 1
  fi
  echo "  PASS: $wf"
done

echo "[pretransfer] checking required repo secret names for post-transfer workflows"
secrets_json="$(curl -sS "${auth_headers[@]}" "${api}/actions/secrets")"
for s in GOVERNANCE_VERIFY_PAT; do
  if jq -e --arg n "$s" '.secrets[]?.name | select(. == $n)' <<<"$secrets_json" >/dev/null; then
    echo "  PASS: secret exists: $s"
  else
    echo "  WARN: secret missing (add after transfer if needed): $s"
  fi
done

echo "[pretransfer] done"
