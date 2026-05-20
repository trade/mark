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
  echo "📊 CodeRabbit analysis..."
  coderabbit review --plain || echo "⚠️  CodeRabbit found issues (see above)"
  echo ""
fi

# Linting
echo "📝 Linting..."
pnpm -s lint
echo ""

# Type checking
echo "🔍 Type checking..."
pnpm -s typecheck
echo ""

# Contract checks (if changed)
if git diff --name-only HEAD | grep -q "contracts/"; then
  echo "⚙️  Contract checks..."
  cd contracts && make ci-fast
  cd ..
  echo ""
fi

echo "✅ Local review complete!"
