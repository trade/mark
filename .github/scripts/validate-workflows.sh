#!/bin/bash
# Validate workflows match project configuration

set -euo pipefail

ERRORS=0

# Check circuits package manager
if [ -f "circuits/pnpm-lock.yaml" ]; then
  if grep -E "^[[:space:]]+(run:).*\bnpm (ci|install)\b" .github/workflows/circuits-ci.yml >/dev/null; then
    echo "❌ circuits-ci.yml uses npm but circuits/ uses pnpm"
    ERRORS=$((ERRORS + 1))
  fi
elif [ -f "circuits/package-lock.json" ]; then
  if grep -E "^[[:space:]]+(run:).*\bpnpm install\b" .github/workflows/circuits-ci.yml >/dev/null; then
    echo "❌ circuits-ci.yml uses pnpm but circuits/ uses npm"
    ERRORS=$((ERRORS + 1))
  fi
fi

# Check Node version consistency
MISE_NODE=$(grep "^node = " .mise.toml | cut -d'"' -f2)
WORKFLOWS=$(find .github/workflows -name "*.yml" -exec grep -l "node-version:" {} \;)

for workflow in $WORKFLOWS; do
  WORKFLOW_NODE=$(grep "node-version:" "$workflow" | head -1 | grep -oP "'\\K[0-9]+" || true)
  if [ -n "$WORKFLOW_NODE" ] && [ "$WORKFLOW_NODE" != "$MISE_NODE" ]; then
    echo "⚠️  $(basename "$workflow"): Node $WORKFLOW_NODE (expected $MISE_NODE)"
  fi
done

if [ $ERRORS -gt 0 ]; then
  echo ""
  echo "❌ Found $ERRORS workflow validation error(s)"
  exit 1
fi

echo "✅ All workflows validated"
