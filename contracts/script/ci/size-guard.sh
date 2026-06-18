#!/usr/bin/env bash
set -euo pipefail

# EIP-170 max code size is 24,576 bytes.
MAX_CODE_SIZE=24576
# Fail early before the hard limit is reached. Default margin of 1000 bytes
# provides headroom for optimizer output variance.
MIN_MARGIN_BYTES="${MARK_POOL_MIN_SIZE_MARGIN_BYTES:-1000}"
# All Foundry profiles share the default `out` directory, so a prior default or
# integration build can leave an unoptimized MARKPool artifact there. Build into
# an isolated directory with the ci profile so the budget is always measured
# against freshly optimized deployment bytecode, never a stale or wrong-profile
# artifact. Overridable for local experimentation.
SIZE_GUARD_OUT="${MARK_POOL_SIZE_OUT_DIR:-out-size-guard}"
TARGET_ARTIFACT="$SIZE_GUARD_OUT/MARKPool.sol/MARKPool.json"

if ! command -v forge >/dev/null 2>&1; then
  echo "size-guard: forge not found on PATH; cannot build optimized artifact" >&2
  echo "Install Foundry (https://book.getfoundry.sh) and retry." >&2
  exit 1
fi

# Clean and rebuild so the measurement can never come from a stale artifact.
# A failed build (or a build that does not emit the artifact) is a hard failure
# here rather than a silent skip, so the gate cannot be bypassed in CI.
rm -rf "$SIZE_GUARD_OUT"
echo "size-guard: building optimized MARKPool (FOUNDRY_PROFILE=ci, out=$SIZE_GUARD_OUT)"
FOUNDRY_PROFILE=ci FOUNDRY_OUT="$SIZE_GUARD_OUT" forge build src/pool/MARKPool.sol

if [ ! -f "$TARGET_ARTIFACT" ]; then
  echo "size-guard: artifact not found after build: $TARGET_ARTIFACT" >&2
  echo "size-guard: 'FOUNDRY_PROFILE=ci forge build src/pool/MARKPool.sol' did not produce the expected artifact." >&2
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
