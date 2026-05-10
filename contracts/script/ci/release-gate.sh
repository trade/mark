#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "release-gate: required command not found: $1" >&2
    exit 1
  fi
}

require_cmd forge
require_cmd jq
require_cmd git

MODE="${MARK_RELEASE_GATE_MODE:-local}" # local | remote
OUT_DIR="${MARK_RELEASE_GATE_OUT_DIR:-broadcast/release-gate}"
VERIFY_REQUIRE_SIGNED_MANIFEST="${MARK_RELEASE_VERIFY_REQUIRE_SIGNED_MANIFEST:-true}"
TIMESTAMP_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
STAMP="$(date -u +"%Y%m%dT%H%M%SZ")"
GIT_COMMIT="$(git rev-parse --short HEAD)"
ARTIFACT_PATH="$OUT_DIR/release-gate-$STAMP.json"

mkdir -p "$OUT_DIR"

echo "[release-gate] mode=$MODE"
echo "[release-gate] step 1/3: make ci-full"
make ci-full

READINESS_STATUS="skipped"
VERIFY_STATUS="skipped"
MANIFEST_VERIFY_STATUS="skipped"

if [[ "$MODE" == "remote" ]]; then
  if [[ -z "${RPC_URL:-}" ]]; then
    echo "release-gate: RPC_URL is required for remote mode" >&2
    exit 1
  fi
  if [[ -z "${PRIVATE_KEY:-}" ]]; then
    echo "release-gate: PRIVATE_KEY is required for remote mode" >&2
    exit 1
  fi

  echo "[release-gate] step 2/3: mainnet-readiness (dry checks)"
  MARK_MAINNET_GATE_MODE="${MARK_MAINNET_GATE_MODE:-predeploy}" \
  MARK_MAINNET_GATE_ARTIFACT_PATH="${MARK_MAINNET_GATE_ARTIFACT_PATH:-$OUT_DIR/mainnet-gate-$STAMP.json}" \
  ./script/ops/mainnet-readiness.sh
  READINESS_STATUS="passed"

  RELEASE_VERIFY_ARTIFACT_PATH="${MARK_RELEASE_VERIFY_ARTIFACT_PATH:-${MARK_RELEASE_ARTIFACT_PATH:-}}"
  if [[ -z "$RELEASE_VERIFY_ARTIFACT_PATH" ]]; then
    echo "release-gate: MARK_RELEASE_VERIFY_ARTIFACT_PATH or MARK_RELEASE_ARTIFACT_PATH is required in remote mode" >&2
    exit 1
  fi

  if [[ "$VERIFY_REQUIRE_SIGNED_MANIFEST" == "true" ]]; then
    echo "[release-gate] step 3/4: verify signed evidence manifest"
    VERIFY_MANIFEST_PATH="${MARK_RELEASE_VERIFY_MANIFEST_PATH:-broadcast/mark-evidence-manifest.json}"
    VERIFY_SIGNATURE_PATH="${MARK_RELEASE_VERIFY_SIGNATURE_PATH:-broadcast/mark-evidence-manifest.sig}"
    VERIFY_SIGNATURE_META_PATH="${MARK_RELEASE_VERIFY_SIGNATURE_META_PATH:-broadcast/mark-evidence-signature.json}"

    if [[ -z "${VERIFY_PUBLIC_KEY_FILE:-}" && -z "${VERIFY_PUBLIC_KEY_PEM:-}" ]]; then
      echo "release-gate: VERIFY_PUBLIC_KEY_FILE or VERIFY_PUBLIC_KEY_PEM is required when MARK_RELEASE_VERIFY_REQUIRE_SIGNED_MANIFEST=true" >&2
      exit 1
    fi

    MANIFEST_PATH="$VERIFY_MANIFEST_PATH" ./script/ops/verify-evidence-manifest.sh
    MANIFEST_PATH="$VERIFY_MANIFEST_PATH" \
    SIGNATURE_PATH="$VERIFY_SIGNATURE_PATH" \
    SIGNATURE_META_PATH="$VERIFY_SIGNATURE_META_PATH" \
    VERIFY_PUBLIC_KEY_FILE="${VERIFY_PUBLIC_KEY_FILE:-}" \
    VERIFY_PUBLIC_KEY_PEM="${VERIFY_PUBLIC_KEY_PEM:-}" \
    ./script/ops/verify-evidence-signature.sh

    if ! jq -e --arg path "$RELEASE_VERIFY_ARTIFACT_PATH" '.artifacts[] | select(.id == "release" and .path == $path)' "$VERIFY_MANIFEST_PATH" >/dev/null; then
      echo "release-gate: release artifact path is not anchored in manifest (id=release, path=$RELEASE_VERIFY_ARTIFACT_PATH)" >&2
      exit 1
    fi
    MANIFEST_VERIFY_STATUS="passed"
  else
    echo "[release-gate] step 3/4: signed evidence manifest verification skipped (MARK_RELEASE_VERIFY_REQUIRE_SIGNED_MANIFEST=false)"
  fi

  echo "[release-gate] step 4/4: strict deployment verification"
  MARK_RELEASE_VERIFY_ARTIFACT_PATH="$RELEASE_VERIFY_ARTIFACT_PATH" \
  ./script/ci/verify-from-artifact.sh
  VERIFY_STATUS="passed"
fi

jq -n \
  --arg gate "release-gate" \
  --arg mode "$MODE" \
  --arg timestamp "$TIMESTAMP_UTC" \
  --arg commit "$GIT_COMMIT" \
  --arg ciFull "passed" \
  --arg readiness "$READINESS_STATUS" \
  --arg manifestVerify "$MANIFEST_VERIFY_STATUS" \
  --arg verify "$VERIFY_STATUS" \
  '{
    gate: $gate,
    mode: $mode,
    timestamp: $timestamp,
    gitCommit: $commit,
    checks: {
      ciFull: $ciFull,
      mainnetReadiness: $readiness,
      signedManifestVerify: $manifestVerify,
      strictDeploymentVerify: $verify
    }
  }' > "$ARTIFACT_PATH"

echo "[release-gate] PASSED"
echo "[release-gate] artifact: $ARTIFACT_PATH"
