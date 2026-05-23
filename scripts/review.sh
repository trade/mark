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

# Contract checks (if changed since base branch)
BASE_REF=""
for ref in origin/dev origin/main origin/master; do
  if git rev-parse --verify --quiet "$ref" >/dev/null; then
    BASE_REF="$ref"
    break
  fi
done

if [[ -z "$BASE_REF" ]]; then
  echo "⚠️  No base branch found (tried: origin/dev, origin/main, origin/master)."
  echo "    Skipping contract checks..."
  echo ""
elif git diff --name-only "$BASE_REF"...HEAD contracts/ | grep -q .; then
  echo "⚙️  Contract checks..."
  (cd contracts && make ci-fast)
  echo ""
fi

echo "✅ Local review complete!"
