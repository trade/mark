#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

fail() {
  echo "[architecture-guard] $1" >&2
  exit 1
}

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
    echo "[architecture-guard] Forbidden imports found for rule: $label" >&2
    echo "$hits" >&2
    exit 1
  fi
}

# Bridge contracts must not depend on settlement concrete contracts.
check_no_imports \
  "src/bridge" \
  '^\s*import\s+.*"(\.\.\/)+(?:src\/)?settlement\/' \
  "bridge -> settlement"

# Settlement contracts must not depend on bridge concrete contracts.
check_no_imports \
  "src/settlement" \
  '^\s*import\s+.*"(\.\.\/)+(?:src\/)?bridge\/' \
  "settlement -> bridge"

# Pool contracts must not depend on settlement or bridge concrete contracts.
check_no_imports \
  "src/pool" \
  '^\s*import\s+.*"(\.\.\/)+(?:src\/)?(?:settlement|bridge)\/' \
  "pool -> settlement/bridge"

# Withdraw contracts must not depend on settlement or bridge concrete contracts.
check_no_imports \
  "src/withdraw" \
  '^\s*import\s+.*"(\.\.\/)+(?:src\/)?(?:settlement|bridge)\/' \
  "withdraw -> settlement/bridge"

echo "[architecture-guard] OK"
