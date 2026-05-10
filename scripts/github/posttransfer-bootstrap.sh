#!/usr/bin/env bash
set -euo pipefail

# Post-transfer bootstrap:
# 1) apply governance protections
# 2) verify protections are active
#
# Required env:
#   GH_PAT=<repo admin token>
# Optional:
#   GH_REPO=owner/repo

if [[ -z "${GH_PAT:-}" ]]; then
  echo "GH_PAT is required" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

echo "[posttransfer] applying governance protections"
./scripts/github/apply-governance.sh

echo "[posttransfer] verifying governance protections"
./scripts/github/verify-governance.sh

echo "[posttransfer] SUCCESS: governance baseline applied and verified"
