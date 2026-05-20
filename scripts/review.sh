#!/bin/bash
# Local code review script
# Usage: ./scripts/review.sh [--quick]

set -e

QUICK_MODE=false
if [[ "$1" == "--quick" ]]; then
  QUICK_MODE=true
fi

echo "🤖 Running local code review..."
echo ""

# CodeRabbit review
if ! $QUICK_MODE; then
  if ! command -v coderabbit &>/dev/null; then
    echo "⚠️  CodeRabbit CLI not found. Install: https://docs.coderabbit.ai/cli"
    echo "    Skipping CodeRabbit review..."
    echo ""
  else
    echo "📊 CodeRabbit analysis..."
    coderabbit review --plain || echo "⚠️  CodeRabbit found issues (see above)"
    echo ""
  fi
fi

# Linting
echo "📝 Linting..."
pnpm -s lint
echo ""

# Type checking
echo "🔍 Type checking..."
pnpm -s typecheck
echo ""

# Contract checks (if changed since origin/dev)
if git diff --name-only origin/dev...HEAD contracts/ 2>/dev/null | grep -q .; then
  echo "⚙️  Contract checks..."
  (cd contracts && make ci-fast)
  echo ""
fi

echo "✅ Local review complete!"
