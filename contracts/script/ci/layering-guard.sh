#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

check_no_imports() {
  local domain_dir="$1"
  local forbidden_re="$2"
  local label="$3"

  local files
  files="$(find "$domain_dir" -type f -name '*.sol' | sort)"
  if [[ -z "$files" ]]; then
    return 0
  fi

  local hits
  hits="$(rg -n --no-heading "$forbidden_re" $files || true)"
  if [[ -n "$hits" ]]; then
    echo "[layering-guard] Forbidden imports found for rule: $label" >&2
    echo "$hits" >&2
    exit 1
  fi
}

# Unit tests must stay domain-local at the test-helper layer.
check_no_imports \
  "test/unit/bridge" \
  '^import\s+.*"(?:\.\./settlement/|\.\./\.\./unit/settlement/|\.\./\.\./integration/settlement/|\.\./\.\./invariant/settlement/|\.\./\.\./e2e/settlement/|test/unit/settlement/|test/integration/settlement/|test/invariant/settlement/|test/e2e/settlement/)' \
  "unit/bridge -> settlement test trees"

check_no_imports \
  "test/unit/settlement" \
  '^import\s+.*"(?:\.\./bridge/|\.\./\.\./unit/bridge/|test/unit/bridge/)' \
  "unit/settlement -> bridge test trees"

# Deploy scripts should remain domain-local.
check_no_imports \
  "script/deploy/bridge" \
  '^import\s+.*"(?:\.\./settlement/|\.\./\.\./deploy/settlement/|script/deploy/settlement/)' \
  "deploy/bridge -> deploy/settlement"

check_no_imports \
  "script/deploy/settlement" \
  '^import\s+.*"(?:\.\./bridge/|\.\./\.\./deploy/bridge/|script/deploy/bridge/)' \
  "deploy/settlement -> deploy/bridge"

echo "[layering-guard] OK"
