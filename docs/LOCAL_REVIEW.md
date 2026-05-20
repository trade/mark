# Local Code Review Guide

## Quick Start

```bash
# Full review (includes CodeRabbit)
pnpm review

# Quick review (skip CodeRabbit)
pnpm review:quick
```

## Review Workflow

### Before Opening PR (Recommended)

```bash
# Run full local review
pnpm review

# Fix any issues found
# Then commit and push
```

### During Development (Optional)

```bash
# Quick checks (no CodeRabbit)
pnpm review:quick

# Or individual checks
pnpm typecheck
pnpm lint
cd contracts && make ci-fast
```

## Git Hooks

### Pre-Push Hook (Automatic)

CodeRabbit runs automatically before push:

```bash
git push  # CodeRabbit review runs
```

**Skip if needed**:
```bash
SKIP_CODERABBIT=1 git push
# or
git push --no-verify
```

### Pre-Commit Hook (Runs by Default)

- TypeScript type checking
- ESLint linting

**Can be skipped** with `git commit --no-verify`

## CodeRabbit Usage

### Local CLI

```bash
# Interactive review
coderabbit review

# Plain text output
coderabbit review --plain

# Agent-structured output
coderabbit review --agent

# Check stats
coderabbit stats
```

### GitHub App

- Runs automatically on every PR
- Required check (must pass to merge)
- Team visibility

## When to Use What

| Scenario | Tool | Command |
|----------|------|---------|
| Before opening PR | Full review | `pnpm review` |
| Quick iteration | Quick review | `pnpm review:quick` |
| Fix specific issue | Individual check | `pnpm lint` / `pnpm typecheck` |
| Contract changes | Contract CI | `cd contracts && make ci-fast` |
| Pre-push (auto) | Git hook | Runs on `git push` |

## Tips

### Speed Up Reviews

```bash
# Skip CodeRabbit for WIP pushes
SKIP_CODERABBIT=1 git push

# Run only what changed
pnpm typecheck  # Fast
pnpm lint       # Fast
```

### Review Specific Files

```bash
# CodeRabbit doesn't support file filtering yet
# Use eslint for specific files
pnpm eslint src/components/MyComponent.tsx
```

### Disable Pre-Push Hook Temporarily

```bash
# Option 1: Environment variable
SKIP_CODERABBIT=1 git push

# Option 2: Skip all hooks
git push --no-verify
```

## Configuration

### CodeRabbit Config

`.coderabbit.yaml` - Controls GitHub App behavior

### Lefthook Config

`lefthook.yml` - Controls git hooks

### Review Script

`scripts/review.sh` - Customizable review workflow
