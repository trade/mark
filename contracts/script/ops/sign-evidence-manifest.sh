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
SIGNING_KEY_FILE="${SIGNING_KEY_FILE:-}"
SIGNING_KEY_PEM="${SIGNING_KEY_PEM:-}"
SIGNING_KEY_ID="${SIGNING_KEY_ID:-manual-openssl-key}"
SIGNATURE_ALGORITHM="${SIGNATURE_ALGORITHM:-sha256-rsa-pkcs1v15}"

if [[ ! -f "$MANIFEST_PATH" ]]; then
  echo "Missing manifest file: $MANIFEST_PATH" >&2
  exit 1
fi

if [[ -z "$SIGNING_KEY_FILE" && -z "$SIGNING_KEY_PEM" ]]; then
  echo "Provide SIGNING_KEY_FILE or SIGNING_KEY_PEM" >&2
  exit 1
fi

KEY_FILE_TO_USE="$SIGNING_KEY_FILE"
TMP_KEY_FILE=""
if [[ -z "$KEY_FILE_TO_USE" ]]; then
  TMP_KEY_FILE="$(mktemp)"
  printf '%s\n' "$SIGNING_KEY_PEM" >"$TMP_KEY_FILE"
  KEY_FILE_TO_USE="$TMP_KEY_FILE"
fi

cleanup() {
  if [[ -n "$TMP_KEY_FILE" ]]; then
    rm -f "$TMP_KEY_FILE"
  fi
}
trap cleanup EXIT

mkdir -p "$(dirname "$SIGNATURE_PATH")" "$(dirname "$SIGNATURE_META_PATH")"

openssl dgst -sha256 -sign "$KEY_FILE_TO_USE" -out "$SIGNATURE_PATH" "$MANIFEST_PATH"

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

jq -n \
  --arg generatedAt "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  --arg manifestPath "$MANIFEST_PATH" \
  --arg signaturePath "$SIGNATURE_PATH" \
  --arg manifestSha "$manifest_sha" \
  --arg signatureSha "$signature_sha" \
  --arg algorithm "$SIGNATURE_ALGORITHM" \
  --arg keyId "$SIGNING_KEY_ID" \
  '{
    schemaVersion: 1,
    generatedAt: $generatedAt,
    manifestPath: $manifestPath,
    signaturePath: $signaturePath,
    algorithm: $algorithm,
    keyId: $keyId,
    manifestSha256: $manifestSha,
    signatureSha256: $signatureSha
  }' >"$SIGNATURE_META_PATH"

echo "Manifest signature generated:"
echo "  Signature: $SIGNATURE_PATH"
echo "  Metadata:  $SIGNATURE_META_PATH"
