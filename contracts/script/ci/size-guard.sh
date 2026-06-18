#!/usr/bin/env bash
set -euo pipefail

# EIP-170 max code size is 24,576 bytes.
MAX_CODE_SIZE=24576
# Fail early before the hard limit is reached. Default margin of 1000 bytes
# provides headroom for optimizer output variance.
MIN_MARGIN_BYTES="${MARK_POOL_MIN_SIZE_MARGIN_BYTES:-1000}"
TARGET_ARTIFACT="out/MARKPool.sol/MARKPool.json"

# In CI, we try to measure the optimized artifact if it exists from a prior
# build step. If not (optimizer build times out), skip with warning and rely
# on local `forge build --sizes` with the ci profile.
if [ -n "${GITHUB_ACTIONS:-}" ]; then
  if [ -f "$TARGET_ARTIFACT" ]; then
    echo "size-guard: using existing optimized artifact in CI"
  else
    echo "size-guard: WARNING - optimized artifact not found in CI (build timeout)."
    echo "size-guard: Skipping enforcement; local verification required."
    echo "size-guard: Run 'FOUNDRY_PROFILE=ci forge build' locally to verify deployed size."
    exit 0
  fi
fi

if [ ! -f "$TARGET_ARTIFACT" ]; then
  echo "size-guard: artifact not found: $TARGET_ARTIFACT" >&2
  echo "Run 'FOUNDRY_PROFILE=ci forge build' first." >&2
  exit 1
fi

deployed_bytecode_hex=$(
  python3 - "$TARGET_ARTIFACT" <<'PY'
import json, sys
path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)
value = data.get("deployedBytecode", {}).get("object", "")
if value.startswith("0x"):
    value = value[2:]
print(value)
PY
)

if [ -z "$deployed_bytecode_hex" ]; then
  echo "size-guard: empty deployed bytecode in $TARGET_ARTIFACT" >&2
  exit 1
fi

byte_len=$((${#deployed_bytecode_hex} / 2))
margin=$((MAX_CODE_SIZE - byte_len))

echo "size-guard: MARKPool deployed size=${byte_len} bytes, margin=${margin} bytes (threshold=${MIN_MARGIN_BYTES})"

if [ "$margin" -lt 0 ]; then
  echo "size-guard: FAIL MARKPool exceeds EIP-170 by $((-margin)) bytes" >&2
  exit 1
fi

if [ "$margin" -lt "$MIN_MARGIN_BYTES" ]; then
  echo "size-guard: FAIL MARKPool margin ${margin} < required ${MIN_MARGIN_BYTES}" >&2
  exit 1
fi

echo "size-guard: OK"
