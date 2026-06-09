# Contributing to MARK Protocol

Thank you for your interest in contributing to MARK Protocol! This guide will walk you through the development workflow, code standards, and release procedures.

## Table of Contents

- [Security Policy](#security-policy)
- [Getting Started](#getting-started)
- [Development Workflow](#development-workflow)
- [Code Standards](#code-standards)
- [Testing](#testing)
- [Submitting a PR](#submitting-a-pr)
- [Release Process](#release-process)
- [Troubleshooting](#troubleshooting)

---

## Security Policy

### For New Contributors

**We do not accept unsolicited PRs with executable code from new contributors.**

This policy protects the project and community from potential security risks.

### Contribution Process

1. **Open an issue first**
   - Describe the feature or bug fix
   - Wait for maintainer feedback
   - Get approval before writing code

2. **Start with documentation**
   - First-time contributors: documentation PRs only
   - Build trust before submitting code

3. **Run CI locally before submitting**
   - All contributors must verify their changes pass CI
   - Run full CI fast pipeline: `mise run ci-fast` (typecheck, lint, semgrep, contracts core, circuits core — ~10 min)
   - Provide CI verification in PR description

4. **Verify your identity (for code contributions)**
   - Sign commits with GPG key
   - Add public key to GitHub profile
   - Link to verified email and social profiles
   - Maintainers may request additional verification

5. **Follow the review process**
   - Fill out PR template completely
   - Address all CI checks
   - Respond to review feedback

### What We Don't Accept

- ❌ Unsolicited code PRs from new contributors
- ❌ PRs with incomplete templates
- ❌ Code handling private keys without prior approval
- ❌ Large PRs (>500 lines) without discussion
- ❌ PRs without linked issues

### Security-Sensitive Changes

These require extra scrutiny:
- Smart contract changes
- Deployment scripts
- CI/CD workflows
- Dependency updates
- Code handling secrets/keys

**Report security issues**: See [SECURITY.md](./SECURITY.md)

---

## Getting Started

### Option A: Automated Setup (Recommended)

Install all prerequisites via mise (tool versions pinned in `.mise.toml`):

```bash
# Clone the repository
git clone https://github.com/trade/mark.git
cd mark

# Install and activate all tools via mise (Node, pnpm, Foundry)
mise trust
mise install

# Install project dependencies
pnpm i
```

All tool versions are pinned in `.mise.toml`. Run `mise install` after every `git pull` to stay in sync.

Tools managed by mise:
- **Node.js 24** + **pnpm 9.0.2** — toolchain
- **Foundry** (forge, cast, anvil) — Solidity development

The bootstrap script (`./scripts/bootstrap.sh`) remains available as a
convenience wrapper that also installs mise itself if missing.

The script also installs (not managed by mise):
- **uv** — Python package manager (for slither, semgrep, and other Python tooling)
- **super-cli** — OP Superchain deployment CLI

Python tools (slither, semgrep) are installed via `uv pip install` for fast, isolated, reproducible installs.

Re-run `./scripts/bootstrap.sh` at any time to verify/update tools. Use `./scripts/bootstrap.sh --check` for a read-only status report.

Run `./scripts/bootstrap.sh --check` to see what's installed without making changes.

### Option B: Manual Setup

If you prefer to install tools manually, the prerequisites are:

- **mise**: `curl https://mise.run | sh` — manages tool versions via `.mise.toml`
- **Node.js 24**: `mise use -g node@24`
- **pnpm 9.x**: `mise use -g pnpm@9.0.2`
- **Foundry**: `mise use -g foundry@latest`
- **uv**: `curl -LsSf https://astral.sh/uv/install.sh | sh` — Python package manager
- **slither**: `uv pip install slither-analyzer==0.11.5`
- **semgrep**: `uv pip install semgrep`
- **super-cli**: `npm install -g @ethereum-optimism/super-cli`
- **lefthook**: installed automatically via `pnpm install` (`prepare` script)

### Verify Setup

```bash
# Type checking
pnpm typecheck

# Linting
pnpm lint

# Circuit witness tests
pnpm -s circuits:test

# Contract tests (includes architecture/layering/size guards)
cd contracts && make ci-fast
```

All checks should pass before you proceed.

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

Once the devnet is running, follow the [end-to-end tutorial](docs/TUTORIAL.md) to execute your first complete transaction flow (deposit, settlement, verification).

---

## Development Workflow

### Branching Strategy

MARK uses a **two-track branch model**:

- **`dev`** — Active integration and testnet (OP Sepolia auto-deploys on push)
- **`main`** — Mainnet-ready only (manual promotion)

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

   # Circuit witness tests
   pnpm -s circuits:test

   # Contract compilation and tests
   cd contracts && make ci-fast
   ```

   `make ci-fast` includes:
   - `make architecture-guard`
   - `make layering-guard`
   - `make size-guard` (fails if `MARKPool` bytecode margin is below threshold)
   - core contract tests

   Override bytecode margin threshold locally if needed:
   ```bash
   cd contracts
   MARK_POOL_MIN_SIZE_MARGIN_BYTES=120 make size-guard
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
- [ ] All local tests pass: `pnpm typecheck && pnpm lint && pnpm -s circuits:test && cd contracts && make ci-fast`
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
1. Staging rehearsal auto-triggers on push to dev
   
2. After staging passes, create PR: dev → main
   ↓ (All production gates triggered)
   
3. After maintainer approval, manual dispatch:
   - Run mainnet readiness workflow from main
   
4. Tag release: v0.x.0
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

- [BRANCHING.md](./docs/BRANCHING.md) — Release strategy & branch protection
- [DEPLOYMENT.md](./docs/DEPLOYMENT.md) — Step-by-step release runbook
- [TROUBLESHOOTING.md](./docs/TROUBLESHOOTING.md) — Common issues & solutions
- [contracts/ARCHITECTURE.md](./contracts/ARCHITECTURE.md) — Module architecture
- [README.md](./README.md) — Project overview

---

## Questions?

Feel free to open an issue or ask in a PR. We're here to help!
