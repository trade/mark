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

require_cmd openssl
require_cmd jq

MANIFEST_PATH="${MANIFEST_PATH:-broadcast/mark-evidence-manifest.json}"
SIGNATURE_PATH="${SIGNATURE_PATH:-broadcast/mark-evidence-manifest.sig}"
SIGNATURE_META_PATH="${SIGNATURE_META_PATH:-broadcast/mark-evidence-signature.json}"
VERIFY_PUBLIC_KEY_FILE="${VERIFY_PUBLIC_KEY_FILE:-}"
VERIFY_PUBLIC_KEY_PEM="${VERIFY_PUBLIC_KEY_PEM:-}"

if [[ ! -f "$MANIFEST_PATH" ]]; then
  echo "Missing manifest file: $MANIFEST_PATH" >&2
  exit 1
fi
if [[ ! -f "$SIGNATURE_PATH" ]]; then
  echo "Missing signature file: $SIGNATURE_PATH" >&2
  exit 1
fi
if [[ ! -f "$SIGNATURE_META_PATH" ]]; then
  echo "Missing signature metadata file: $SIGNATURE_META_PATH" >&2
  exit 1
fi

if [[ -z "$VERIFY_PUBLIC_KEY_FILE" && -z "$VERIFY_PUBLIC_KEY_PEM" ]]; then
  echo "Provide VERIFY_PUBLIC_KEY_FILE or VERIFY_PUBLIC_KEY_PEM" >&2
  exit 1
fi

KEY_FILE_TO_USE="$VERIFY_PUBLIC_KEY_FILE"
TMP_KEY_FILE=""
if [[ -z "$KEY_FILE_TO_USE" ]]; then
  TMP_KEY_FILE="$(mktemp)"
  printf '%s\n' "$VERIFY_PUBLIC_KEY_PEM" >"$TMP_KEY_FILE"
  KEY_FILE_TO_USE="$TMP_KEY_FILE"
fi

cleanup() {
  if [[ -n "$TMP_KEY_FILE" ]]; then
    rm -f "$TMP_KEY_FILE"
  fi
}
trap cleanup EXIT

meta_manifest_path="$(jq -r '.manifestPath // empty' "$SIGNATURE_META_PATH")"
meta_signature_path="$(jq -r '.signaturePath // empty' "$SIGNATURE_META_PATH")"
meta_schema="$(jq -r '.schemaVersion // empty' "$SIGNATURE_META_PATH")"

if [[ "$meta_schema" != "1" ]]; then
  echo "Unsupported or missing schemaVersion in signature metadata: $meta_schema" >&2
  exit 1
fi

if [[ "$meta_manifest_path" != "$MANIFEST_PATH" ]]; then
  echo "Signature metadata manifestPath mismatch: $meta_manifest_path != $MANIFEST_PATH" >&2
  exit 1
fi
if [[ "$meta_signature_path" != "$SIGNATURE_PATH" ]]; then
  echo "Signature metadata signaturePath mismatch: $meta_signature_path != $SIGNATURE_PATH" >&2
  exit 1
fi

openssl dgst -sha256 -verify "$KEY_FILE_TO_USE" -signature "$SIGNATURE_PATH" "$MANIFEST_PATH" >/dev/null

if command -v shasum >/dev/null 2>&1; then
  manifest_sha="$(shasum -a 256 "$MANIFEST_PATH" | awk '{print $1}')"
  signature_sha="$(shasum -a 256 "$SIGNATURE_PATH" | awk '{print $1}')"
elif command -v sha256sum >/dev/null 2>&1; then
  manifest_sha="$(sha256sum "$MANIFEST_PATH" | awk '{print $1}')"
  signature_sha="$(sha256sum "$SIGNATURE_PATH" | awk '{print $1}')"
else
  echo "No SHA-256 tool found (need shasum or sha256sum)" >&2
  exit 1
fi

meta_manifest_sha="$(jq -r '.manifestSha256 // empty' "$SIGNATURE_META_PATH")"
meta_signature_sha="$(jq -r '.signatureSha256 // empty' "$SIGNATURE_META_PATH")"

if [[ "$manifest_sha" != "$meta_manifest_sha" ]]; then
  echo "Manifest SHA mismatch in signature metadata" >&2
  exit 1
fi
if [[ "$signature_sha" != "$meta_signature_sha" ]]; then
  echo "Signature SHA mismatch in signature metadata" >&2
  exit 1
fi

echo "Evidence signature verification PASSED"
echo "Manifest:  $MANIFEST_PATH"
echo "Signature: $SIGNATURE_PATH"
echo "Metadata:  $SIGNATURE_META_PATH"
