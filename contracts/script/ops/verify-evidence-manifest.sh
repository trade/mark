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

require_cmd jq

MANIFEST_PATH="${MANIFEST_PATH:-broadcast/mark-evidence-manifest.json}"

if [[ ! -f "$MANIFEST_PATH" ]]; then
  echo "Missing manifest file: $MANIFEST_PATH" >&2
  exit 1
fi

SCHEMA_VERSION="$(jq -r '.schemaVersion // empty' "$MANIFEST_PATH")"
if [[ "$SCHEMA_VERSION" != "1" ]]; then
  echo "Unsupported or missing schemaVersion in manifest: $SCHEMA_VERSION" >&2
  exit 1
fi

ARTIFACT_COUNT="$(jq '.artifacts | length' "$MANIFEST_PATH")"
if [[ "$ARTIFACT_COUNT" -lt 1 ]]; then
  echo "Manifest has no artifacts entries" >&2
  exit 1
fi

mapfile -t ENTRIES < <(jq -r '.artifacts[] | [.id, .path, .sha256] | @tsv' "$MANIFEST_PATH")

for entry in "${ENTRIES[@]}"; do
  IFS=$'\t' read -r id path expected_sha <<<"$entry"
  if [[ -z "$id" || -z "$path" || -z "$expected_sha" ]]; then
    echo "Malformed manifest entry: $entry" >&2
    exit 1
  fi
  if [[ ! -f "$path" ]]; then
    echo "Missing artifact file for $id: $path" >&2
    exit 1
  fi
  actual_sha="$(sha256_file "$path")"
  if [[ "$actual_sha" != "$expected_sha" ]]; then
    echo "SHA mismatch for $id ($path)" >&2
    echo "  expected: $expected_sha" >&2
    echo "  actual:   $actual_sha" >&2
    exit 1
  fi
done

echo "Evidence manifest verification PASSED"
echo "Manifest: $MANIFEST_PATH"
