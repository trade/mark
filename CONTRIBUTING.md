# Contributing to MARK Protocol

Thank you for your interest in contributing to MARK Protocol! This guide will walk you through the development workflow, code standards, and release procedures.

## Table of Contents

- [Getting Started](#getting-started)
- [Development Workflow](#development-workflow)
- [Code Standards](#code-standards)
- [Testing](#testing)
- [Submitting a PR](#submitting-a-pr)
- [Release Process](#release-process)
- [Troubleshooting](#troubleshooting)

---

## Getting Started

### Prerequisites

- **Node.js**: 20 or 22 (check `.nvmrc` for pinned version)
- **pnpm**: 9.0.2+ (managed via corepack)
- **Foundry**: Latest version ([install](https://book.getfoundry.sh/getting-started/installation))
- **super-cli**: Latest version ([install](https://github.com/ethereum-optimism/super-cli))

### Local Setup

```bash
# Clone the repository
git clone https://github.com/trade/mark.git
cd mark

# Install dependencies (pnpm is auto-managed via corepack)
pnpm i

# Verify setup
pnpm typecheck                    # TypeScript check
pnpm lint                         # Linting
cd contracts && make ci-fast      # Contract tests
```

### Start Development

```bash
# Start the full multi-process dev environment
pnpm dev

# This will:
# - Start local Superchain (supersim) with L1 + 2 L2 chains
# - Launch Vite dev server at http://localhost:5173
# - Deploy contracts to local network
# - Watch for file changes

# In separate terminals, you can also run individually:
pnpm dev:frontend                 # Frontend only (port 5173)
pnpm dev:supersim                 # Local Superchain only
pnpm build:contracts              # Compile contracts
```

---

## Development Workflow

### Branching Strategy

MARK uses a **three-track branch model**:

- **`dev`** — Active integration branch (default for features)
- **`canary`** — Staging/stabilization branch
- **`main`** — Production-ready (release branch)

### Feature Development

1. **Create a feature branch from `dev`**:
   ```bash
   git checkout dev
   git pull origin dev
   git checkout -b feature/your-feature-name
   ```

2. **Use conventional commit naming**:
   - `feature/add-settlement-ui` ✅
   - `feature/fix-bridge-relay` ✅
   - `feature/docs-update` ✅
   - `feature/123` ❌ (use descriptive names)

3. **Make changes and commit**:
   ```bash
   git add .
   git commit -m "feat(settlement): add transaction confirmation ui"
   ```

   **Commit format**: `<type>(<scope>): <subject>`

   - **Types**: `feat`, `fix`, `chore`, `ci`, `refactor`, `docs`, `test`
   - **Scope**: Component area (`settlement`, `bridge`, `token`, `frontend`, `workflows`, etc.)
   - **Subject**: Clear, imperative tone

### Before Submitting PR

1. **Run all checks locally**:
   ```bash
   # Type checking
   pnpm typecheck

   # Linting
   pnpm lint

   # Format code
   pnpm format

   # Contract compilation and tests
   cd contracts && make ci-fast
   ```

2. **Verify no secrets in code**:
   ```bash
   # Check for common patterns (key, password, token, secret)
   git diff HEAD^ HEAD | grep -i "password\|api_key\|private_key"
   # Should return nothing
   ```

3. **Update documentation** if your changes affect:
   - Contract APIs
   - Environment setup
   - Release procedures
   - Architecture

---

## Code Standards

### TypeScript/React

- **Use TypeScript** for all `.ts`/`.tsx` files (no `any` types without justification)
- **ESLint** enforces rules automatically
- **Prettier** formats code consistently
- Prefer **functional components** with hooks
- **Component files** should be small and focused

Example component:
```typescript
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';

interface SettlementCardProps {
  id: string;
  status: 'pending' | 'confirmed' | 'failed';
  onExecute: () => void;
}

export function SettlementCard({ id, status, onExecute }: SettlementCardProps) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Settlement {id}</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <div>Status: {status}</div>
        <button onClick={onExecute}>Execute</button>
      </CardContent>
    </Card>
  );
}
```

### Solidity

- **Use PascalCase** for contract names (`MARKSettlementModule`, not `mark_settlement_module`)
- **Keep modules focused**: one contract per file (with related errors/interfaces ok)
- **Document with NatSpec comments** for all public functions
- **Follow existing patterns** in `src/token`, `src/bridge`, `src/settlement`
- **No cross-domain imports** (enforced by `make architecture-guard`)

Example contract:
```solidity
/// @title MARKSettlementModule
/// @notice Handles cross-chain settlement execution
contract MARKSettlementModule is ISettlement {
  /// @notice Execute a settlement transaction
  /// @param id The settlement ID
  /// @param proof The zero-knowledge proof
  function settle(bytes32 id, bytes calldata proof) external {
    // Implementation
  }
}
```

### Testing

- **Test names** should describe behavior: `testSettlementSucceeds()`, not `test1()`
- **Arrange-Act-Assert** pattern for clarity
- **One assertion per test** (or group related assertions with comments)

Example test:
```solidity
function testSettlementExecutesWithValidProof() public {
  // Arrange: Set up settlement state
  bytes32 settlementId = keccak256("test");
  bytes memory proof = _generateValidProof();

  // Act: Execute settlement
  vm.prank(user);
  settlement.execute(settlementId, proof);

  // Assert: Verify result
  assertEq(settlement.status(settlementId), Status.EXECUTED);
}
```

---

## Testing

### Running Tests

```bash
cd contracts

# Fast tests (guards + unit/e2e, ~30 seconds)
make ci-fast

# Full test suite (includes invariants, ~2 minutes)
make ci-full

# Specific test file
forge test --match-path "test/unit/RYLA.t.sol" -v

# Specific test function
forge test --match-test "testMintSucceeds" -v

# With gas reporting
forge test --gas-report
```

### Test Structure

```
contracts/test/
├── unit/              # Unit tests (isolated contract behavior)
│   ├── settlement/
│   ├── bridge/
│   ├── token/
│   └── ...
├── e2e/               # End-to-end tests (integration scenarios)
│   └── settlement/
└── invariant/         # Invariant-based fuzzing tests
    └── settlement/
```

### Writing Tests

1. **Unit tests** should test single functions in isolation
2. **E2E tests** should test complete flows (e.g., bridge → settlement)
3. **Invariants** should test protocol properties that always hold

See `contracts/test/unit/RYLA.t.sol` for examples.

---

## Submitting a PR

### PR Checklist

Before opening a PR, verify:

- [ ] Feature branch created from `dev` (or `main` for hotfixes)
- [ ] All local tests pass: `pnpm typecheck && pnpm lint && cd contracts && make ci-fast`
- [ ] No secrets/private keys added
- [ ] Commits follow conventional format
- [ ] Documentation updated (if applicable)
- [ ] Branch name is descriptive (e.g., `feature/add-settlement-ui`)

### Creating the PR

1. **Push your branch**:
   ```bash
   git push origin feature/your-feature-name
   ```

2. **Open PR on GitHub**:
   - Target: `dev` (unless hotfix → `main`)
   - Title: Use conventional format (e.g., "feat(settlement): add confirmation ui")
   - Description: Use the PR template (auto-populated)

3. **Fill in the PR template**:
   - **Summary**: What does this change do?
   - **Scope**: Which areas are affected?
   - **Verification**: Show commands you ran locally
   - **Risk**: Any potential issues?
   - **Linked Context**: Related issues/PRs?

### PR Review Process

1. **Automated checks run**:
   - TypeScript compilation
   - ESLint linting
   - Contracts CI (unit + invariant tests)
   - Slither security scan (if contracts touched)
   - CodeQL security scanning
   - Secrets drift detection

2. **Manual code review**:
   - CODEOWNERS (see `.github/CODEOWNERS`) required
   - May request changes or ask questions
   - Approval required before merge

3. **Merge**:
   - Squash commits into single commit (auto on GitHub)
   - Branch auto-deleted after merge
   - PR closed

---

## Release Process

**For full details**, see `DEPLOYMENT.md` (detailed runbook) or `BRANCHING.md` (policy).

### Quick Summary

```
1. Create PR: dev → canary
   ↓ (Staging rehearsal auto-triggers)
   
2. After staging passes, create PR: canary → main
   ↓ (All production gates triggered)
   
3. After approval, manual dispatch:
   - Run mainnet readiness workflow
   
4. Tag release: v0.1.0
```

### For Solo Maintainers

```bash
cd contracts

# Validate everything works
make ci-full

# Generate release evidence
make generate-evidence-manifest

# Sign evidence
make sign-evidence-manifest

# Verify before deployment
make verify-evidence-manifest
```

See `DEPLOYMENT.md` for step-by-step walkthrough.

---

## Troubleshooting

### Common Issues

#### "pnpm command not found"

```bash
# pnpm is managed by corepack. Enable it:
corepack enable
corepack prepare

# Then verify:
pnpm --version
```

#### "Foundry not installed"

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
source $HOME/.bashrc  # or .zshrc
foundryup
```

#### Tests fail with "address already in use"

```bash
# Kill leftover anvil processes
pkill -f anvil
# Or restart dev server
pnpm dev
```

#### "architecture-guard failed: forbidden import"

This means a contract imported from wrong domain. Check:
- bridge contracts shouldn't import from `src/settlement/`
- settlement contracts shouldn't import from `src/bridge/`
- token/errors/interfaces are allowed everywhere

Fix: Remove the forbidden import, use interfaces instead.

#### "Slither findings not in report"

Some findings are intentionally excluded. See `contracts/Makefile`:
```makefile
--exclude "naming-convention,timestamp,arbitrary-send-erc20,reentrancy-balance,reentrancy-benign"
```

Each exclusion is documented in the codebase. If you disagree with an exclusion, discuss in PR.

### Getting Help

1. **Check existing issues**: GitHub Issues tab
2. **Read existing PRs**: Similar changes may have docs/discussions
3. **Review TROUBLESHOOTING.md**: Common solutions
4. **Ask in PR/issue**: Context helps maintainers help you

---

## Best Practices

### Commits
- ✅ Atomic commits (one logical change per commit)
- ✅ Descriptive messages (what + why, not just what)
- ✅ Conventional format (feat/fix/chore/etc.)
- ❌ "wip", "asdf", "fix stuff" commits

### Code Review
- ✅ Ask questions if unclear
- ✅ Suggest improvements, don't demand
- ✅ Acknowledge good solutions
- ❌ Personal criticism

### Testing
- ✅ Test new code before submitting
- ✅ Add tests for bug fixes
- ✅ Update tests when changing behavior
- ❌ "I'll add tests later" (won't happen)

### Documentation
- ✅ Update docs for API changes
- ✅ Add comments for complex logic
- ✅ Include examples
- ❌ "Code is self-documenting" (it's not always)

---

## Additional Resources

- [BRANCHING.md](./BRANCHING.md) — Release strategy & branch protection
- [DEPLOYMENT.md](./DEPLOYMENT.md) — Step-by-step release runbook
- [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) — Common issues & solutions
- [contracts/ARCHITECTURE.md](./contracts/ARCHITECTURE.md) — Module architecture
- [README.md](./README.md) — Project overview

---

## Questions?

Feel free to open an issue or ask in a PR. We're here to help!

---

**Happy contributing!** 🚀

*Last updated: 2026-05-06*
