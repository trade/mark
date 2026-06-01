#!/usr/bin/env bash
# Local code review script
# Usage: ./scripts/review.sh [--quick]

set -uo pipefail

QUICK_MODE=false
if [[ "${1:-}" == "--quick" ]]; then
  QUICK_MODE=true
fi

echo "🤖 Running local code review..."
echo ""

FAILED=()
WARNINGS=()

# Detect base ref for diff checks
BASE_REF=""
for ref in origin/dev origin/main origin/master; do
  if git rev-parse --verify --quiet "$ref" >/dev/null 2>&1; then
    BASE_REF="$ref"
    break
  fi
done

if [[ -z "$BASE_REF" ]]; then
  WARNINGS+=("No base branch found (tried: origin/dev, origin/main, origin/master) — circuits and contract checks skipped")
fi

# CodeRabbit review (optional, non-blocking)
if ! $QUICK_MODE; then
  if command -v coderabbit &>/dev/null; then
    echo "📊 CodeRabbit analysis..."
    if ! coderabbit review --plain 2>&1; then
      WARNINGS+=("CodeRabbit found issues")
    fi
    echo ""
  else
    echo "⚠️  CodeRabbit CLI not found. Skipping."
    echo ""
  fi
fi

# Linting
echo "📝 Linting..."
if ! pnpm -s lint 2>&1; then
  FAILED+=("lint")
fi
echo ""

# Type checking
echo "🔍 Type checking..."
if ! pnpm typecheck 2>&1; then
  FAILED+=("typecheck")
fi
echo ""

# Circuits tests (if circuits files changed)
if [[ -n "$BASE_REF" ]] && git diff --name-only "$BASE_REF"...HEAD circuits/ 2>/dev/null | grep -q .; then
  echo "⚡ Circuits tests..."
  if ! pnpm -s circuits:test 2>&1; then
    FAILED+=("circuits")
  fi
  echo ""
fi

# Contract checks (if contract files changed and forge available)
if command -v forge &>/dev/null; then
  if [[ -n "$BASE_REF" ]] && git diff --name-only "$BASE_REF"...HEAD contracts/ 2>/dev/null | grep -q .; then
    echo "⚙️  Contract checks..."
    if ! (cd contracts && make ci-fast 2>&1); then
      FAILED+=("contracts")
    fi
    echo ""
  fi
else
  echo "⚠️  Foundry not installed. Skipping contract checks."
  echo "   Run 'mise install' to enable."
  echo ""
fi

# Summary
if [[ ${#WARNINGS[@]} -gt 0 ]]; then
  echo "⚠️  Warnings: ${WARNINGS[*]}"
fi

if [[ ${#FAILED[@]} -gt 0 ]]; then
  echo "❌ Local review FAILED: ${FAILED[*]}"
  echo "   Fix issues before pushing."
  exit 1
else
  echo "✅ Local review complete!"
fi