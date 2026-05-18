#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPO_DIR="$(cd "${ROOT_DIR}/.." && pwd)"
IMAGE_TAG="${MARK_RELEASE_GATE_IMAGE_TAG:-mark-release-gate:local}"
DOCKERFILE_PATH="${ROOT_DIR}/docker/release-gate.Dockerfile"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required for release-gate-container" >&2
  exit 1
fi

echo "[release-gate-container] building image: ${IMAGE_TAG}"
docker build \
  --cache-from "type=gha" \
  --cache-to "type=gha,mode=max" \
  -t "${IMAGE_TAG}" \
  -f "${DOCKERFILE_PATH}" \
  "${REPO_DIR}"

echo "[release-gate-container] running release gate inside container"
# Pass through environment variables commonly used by release-gate and remote mode.
docker run --rm \
  -v "${REPO_DIR}:/repo" \
  -w /repo/contracts \
  -e MARK_RELEASE_GATE_MODE \
  -e MARK_RELEASE_VERIFY_REQUIRE_SIGNED_MANIFEST \
  -e MARK_RELEASE_VERIFY_ARTIFACT_PATH \
  -e MARK_RELEASE_ARTIFACT_PATH \
  -e MARK_RELEASE_VERIFY_MANIFEST_PATH \
  -e MARK_RELEASE_VERIFY_SIGNATURE_PATH \
  -e MARK_RELEASE_VERIFY_SIGNATURE_META_PATH \
  -e VERIFY_PUBLIC_KEY_FILE \
  -e VERIFY_PUBLIC_KEY_PEM \
  -e MARK_MAINNET_GATE_MODE \
  -e MARK_MAINNET_GATE_ARTIFACT_PATH \
  -e RPC_URL \
  -e PRIVATE_KEY \
  "${IMAGE_TAG}" \
  bash -lc 'corepack enable >/dev/null 2>&1 || true; pnpm --version >/dev/null 2>&1 || true; make release-gate'
