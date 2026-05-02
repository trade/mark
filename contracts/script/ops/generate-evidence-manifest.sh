#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

sha256_file() {
  local path="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" | awk '{print $1}'
    return
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{print $1}'
    return
  fi
  echo "No SHA-256 tool found (need shasum or sha256sum)" >&2
  exit 1
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "$1 is required but not found in PATH" >&2
    exit 1
  fi
}

require_file() {
  local label="$1"
  local path="$2"
  if [[ ! -f "$path" ]]; then
    echo "Missing required $label file: $path" >&2
    exit 1
  fi
}

require_cmd jq
require_cmd git

RELEASE_ARTIFACT_PATH="${RELEASE_ARTIFACT_PATH:-broadcast/mark-release-prodmode-ci.json}"
PRODUCTION_LOCK_ARTIFACT_PATH="${PRODUCTION_LOCK_ARTIFACT_PATH:-broadcast/mark-production-lock-verify.json}"
STAGING_REHEARSAL_ARTIFACT_PATH="${STAGING_REHEARSAL_ARTIFACT_PATH:-broadcast/mark-staging-rehearsal.json}"
PROMOTION_CHECKLIST_PATH="${PROMOTION_CHECKLIST_PATH:-broadcast/mark-promotion-checklist.json}"
MANIFEST_PATH="${MANIFEST_PATH:-broadcast/mark-evidence-manifest.json}"
MANIFEST_GENERATED_BY="${MANIFEST_GENERATED_BY:-manual}"
MANIFEST_NOTE="${MANIFEST_NOTE:-}"

require_file "release artifact" "$RELEASE_ARTIFACT_PATH"
require_file "production-lock artifact" "$PRODUCTION_LOCK_ARTIFACT_PATH"
require_file "staging-rehearsal artifact" "$STAGING_REHEARSAL_ARTIFACT_PATH"
require_file "promotion-checklist artifact" "$PROMOTION_CHECKLIST_PATH"

mkdir -p "$(dirname "$MANIFEST_PATH")"

RELEASE_SHA="$(sha256_file "$RELEASE_ARTIFACT_PATH")"
LOCK_SHA="$(sha256_file "$PRODUCTION_LOCK_ARTIFACT_PATH")"
STAGING_SHA="$(sha256_file "$STAGING_REHEARSAL_ARTIFACT_PATH")"
CHECKLIST_SHA="$(sha256_file "$PROMOTION_CHECKLIST_PATH")"

GIT_COMMIT="${MARK_GIT_COMMIT:-$(git rev-parse --short=12 HEAD 2>/dev/null || echo unknown)}"

jq -n \
  --arg generatedAt "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  --arg generatedBy "$MANIFEST_GENERATED_BY" \
  --arg note "$MANIFEST_NOTE" \
  --arg gitCommit "$GIT_COMMIT" \
  --arg releasePath "$RELEASE_ARTIFACT_PATH" \
  --arg releaseSha "$RELEASE_SHA" \
  --arg lockPath "$PRODUCTION_LOCK_ARTIFACT_PATH" \
  --arg lockSha "$LOCK_SHA" \
  --arg stagingPath "$STAGING_REHEARSAL_ARTIFACT_PATH" \
  --arg stagingSha "$STAGING_SHA" \
  --arg checklistPath "$PROMOTION_CHECKLIST_PATH" \
  --arg checklistSha "$CHECKLIST_SHA" \
  '{
    schemaVersion: 1,
    generatedAt: $generatedAt,
    generatedBy: $generatedBy,
    note: $note,
    gitCommit: $gitCommit,
    artifacts: [
      {id: "release", path: $releasePath, sha256: $releaseSha},
      {id: "production-lock-verify", path: $lockPath, sha256: $lockSha},
      {id: "staging-rehearsal", path: $stagingPath, sha256: $stagingSha},
      {id: "promotion-checklist", path: $checklistPath, sha256: $checklistSha}
    ]
  }' >"$MANIFEST_PATH"

echo "Evidence manifest generated:"
echo "  $MANIFEST_PATH"
