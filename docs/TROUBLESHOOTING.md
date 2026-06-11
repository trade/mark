# MARK Protocol Troubleshooting Guide

A comprehensive guide to diagnosing and resolving common issues in MARK Protocol development, testing, and deployment.

---

## Table of Contents

- [Development Setup Issues](#development-setup-issues)
- [Smart Contract Issues](#smart-contract-issues)
- [Frontend Development Issues](#frontend-development-issues)
- [Testing Issues](#testing-issues)
- [Deployment Issues](#deployment-issues)
- [CI/CD Workflow Issues](#cicd-workflow-issues)
- [Network & RPC Issues](#network--rpc-issues)

---

## Development Setup Issues

### "pnpm: command not found"

**Symptoms**:

```
bash: pnpm: command not found
```

**Causes**:

- pnpm not installed
- corepack not enabled
- PATH not updated

**Solutions**:

1. **Enable corepack** (recommended):

   ```bash
   # Enable corepack globally
   corepack enable

   # Prepare pnpm version from package.json
   corepack prepare

   # Verify
   pnpm --version  # Should show 9.0.2+
   ```

2. **Install pnpm via mise** (project standard):

   ```bash
   # mise manages pnpm version per .mise.toml
   mise install pnpm

   # Verify
   which pnpm
   pnpm --version  # Should show 9.0.2
   ```

3. **Update PATH**:

   ```bash
   # Add to ~/.bashrc, ~/.zshrc, or ~/.profile
   export PATH="$HOME/.npm/_npx:$PATH"

   # Reload shell
   source ~/.bashrc  # or source ~/.zshrc
   ```

---

### "Node.js version mismatch"

**Symptoms**:

```
⚠️ This project requires Node.js v24
You are using v18.x.x
```

**Causes**:

- Node.js version doesn't match `.mise.toml`
- mise or another Node version manager is not installed

**Solutions**:

1. **Use mise** (recommended):

   ```bash
   # Install mise if not present
   brew install mise

   # Trust and install tools from .mise.toml
   mise trust
   mise install

   # Verify
   node --version  # Should show v24.x.x
   ```

2. **Use another version manager**:

   ```bash
   # Example with fnm
   brew install fnm
   fnm install 24
   fnm use 24
   ```

3. **Manual installation**:
   - Download from https://nodejs.org
   - Install Node.js v24

---

### "Foundry not installed"

**Symptoms**:

```
forge: command not found
```

**Solutions**:

```bash
# Install Foundry (macOS/Linux/WSL)
curl -L https://foundry.paradigm.xyz | bash

# Update PATH
source $HOME/.bashrc  # or ~/.zshrc

# Install Foundry components
foundryup

# Verify
forge --version
cast --version
```

**Windows users**:

```powershell
# Use WSL2 or install from https://github.com/foundry-rs/foundry/releases
```

---

### "circom fails with Bad CPU type or Not Found"

**Symptoms**:

```
sh: /usr/local/bin/circom: Bad CPU type in executable
/usr/local/bin/circom: line 1: Not: command not found
```

**Causes**:

- A stale or wrong-architecture `circom` binary is earlier in PATH
- A failed download wrote an error page to `/usr/local/bin/circom`
- The local shell and downloaded binary architectures do not match

**Solutions**:

1. **Inspect active candidates**:

   ```bash
   type -a circom
   file "$(command -v circom)"
   circom --version
   ```

2. **Install a known-good local binary with Cargo**:

   ```bash
   cargo install --git https://github.com/iden3/circom.git --tag v2.2.3 --locked
   ```

3. **Remove or replace the broken system binary**:

   ```bash
   mv /usr/local/bin/circom /usr/local/bin/circom.bak.$(date +%Y%m%d%H%M%S)
   ln -s "$HOME/.cargo/bin/circom" /usr/local/bin/circom
   ```

4. **Verify circuit tests**:
   ```bash
   command -v circom
   circom --version
   pnpm -s circuits:test
   ```

---

### "super-cli not installed"

**Symptoms**:

```
sup: command not found
```

**Solutions**:

```bash
# Install super-cli via pnpm (dev tooling)
pnpm add -g @eth-optimism/super-cli

# Or use the bootstrap script which installs all tools:
./scripts/bootstrap.sh

# Verify
sup --version
```

---

### "Git hooks not running"

**Symptoms**:

- Linting not running before commit
- Tests not running before push

**Causes**:

- Git hooks not installed
- `.git/hooks` directory corrupted

**Solutions**:

```bash
# Reinstall dependencies (usually sets up hooks)
pnpm i

# If still not working, manually set up hooks
# (Hook setup depends on your husky/lint-staged config)

# Force rebuild
rm -rf node_modules pnpm-lock.yaml
pnpm i
```

---

## Smart Contract Issues

### "architecture-guard failed: forbidden import"

**Symptoms**:

```
CI Error: architecture-guard
ERROR: Forbidden import found in src/bridge/MARKBridgeAdapter.sol
  Importing from: src/settlement/ISettlement.sol
  Settlement should not be imported by bridge domain
```

**Causes**:

- Bridge contract imported settlement module
- Settlement contract imported bridge module
- Violates strict domain boundaries

**Solutions**:

1. **Check the forbidden import**:

   ```bash
   grep -n "import.*settlement\|import.*bridge" src/bridge/MARKBridgeAdapter.sol
   grep -n "import.*settlement\|import.*bridge" src/settlement/MARKSettlementModule.sol
   ```

2. **Remove the forbidden import**:

   ```solidity
   // ❌ DON'T DO THIS (bridge importing settlement)
   import { ISettlement } from "../settlement/ISettlement.sol";

   // ✅ DO THIS INSTEAD (use shared interface)
   import { ISharedSettlement } from "../interfaces/ISharedSettlement.sol";
   ```

3. **Create shared interface if needed**:

   ```solidity
   // src/interfaces/ISharedSettlement.sol
   pragma solidity ^0.8.0;

   interface ISharedSettlement {
     function execute(bytes32 id, bytes calldata proof) external;
   }
   ```

4. **Run guard to verify**:
   ```bash
   cd contracts && make architecture-guard
   # Should pass: ✅ Architecture guard passed
   ```

---

### "layering-guard failed: test imports src/script"

**Symptoms**:

```
CI Error: layering-guard
ERROR: Test file importing script in src/script/Deploy.sol
  Tests should mock or import only from src/
```

**Causes**:

- Test file imports from deployment scripts
- Script file imports from tests
- Violates layering boundaries

**Solutions**:

1. **Identify the problematic import**:

   ```bash
   grep -n "import.*script" contracts/test/**/*.sol
   grep -n "import.*test" contracts/script/**/*.sol
   ```

2. **Refactor to remove cross-layer dependency**:

   ```solidity
   // ❌ DON'T DO THIS (test importing script)
   import { Deploy } from "../../script/Deploy.s.sol";

   // ✅ DO THIS (test imports contract directly)
   import { RYLA } from "../../src/token/RYLA.sol";
   ```

3. **Extract shared code to `src/` if needed**:

   ```bash
   # Move common utilities to src/
   mv contracts/script/Helpers.sol contracts/src/lib/Helpers.sol

   # Update imports in both test and script files
   ```

4. **Run guard to verify**:
   ```bash
   cd contracts && make layering-guard
   # Should pass: ✅ Layering guard passed
   ```

---

### "slither finds high-severity issue"

**Symptoms**:

```
Slither output:
HIGH: Arbitrary Send ERC20 in MARKBridgeAdapter.transfer()
  Risk: Caller can transfer arbitrary tokens
```

**Causes**:

- Actual security issue (fix it!)
- False positive (document exclusion)

**Solutions**:

1. **If legitimate issue** (do this first):

   ```solidity
   // ❌ Before: Vulnerable
   function bridgeTransfer(address token, uint amount) external {
     IERC20(token).transfer(recipient, amount);  // Arbitrary token!
   }

   // ✅ After: Safe
   function bridgeTransfer(uint amount) external {
     require(msg.sender == owner);  // Only owner can bridge
     RYLA.transfer(recipient, amount);  // Only RYLA token
   }
   ```

2. **If false positive**, document exclusion:

   ```makefile
   # contracts/Makefile
   slither-core:
     slither "$$target" \
       --exclude-dependencies \
       --exclude "naming-convention,arbitrary-send-erc20" \  # ← Add here
   ```

   **Document why** in your code:

   ```solidity
   /// @notice Transfer is safe because:
   /// - Only whitelisted tokens allowed (see tokenWhitelist)
   /// - Transfer is guarded by onlyOwner modifier
   /// - Slither exclusion: arbitrary-send-erc20 (documented safe)
   function transfer(address token, uint amount) external onlyOwner {
     IERC20(token).transfer(recipient, amount);
   }
   ```

3. **Update Slither exclusions in Makefile**:
   ```bash
   cd contracts && make slither-core
   # Review findings
   # Update Makefile if excluding
   make slither-core  # Re-verify
   ```

---

### "forge test: compilation failed"

**Symptoms**:

```
Compiler error: contracts/src/token/RYLA.sol:5:1: DeclarationError
  Import "openzeppelin-contracts/token/ERC20/ERC20.sol" not found
```

**Causes**:

- Missing dependencies
- Remapping misconfigured
- Submodule not initialized

**Solutions**:

1. **Initialize submodules**:

   ```bash
   git submodule init
   git submodule update --recursive
   ```

2. **Check remappings**:

   ```bash
   cat contracts/foundry.toml | grep -A5 "remappings"
   # Should show:
   # @openzeppelin/ => lib/createx/lib/openzeppelin-contracts/
   # @interop-lib/ => lib/interop-lib/src/
   ```

3. **Verify dependencies exist**:

   ```bash
   ls -la contracts/lib/
   # Should show: forge-std, interop-lib, createx
   ```

4. **Reinstall dependencies**:

   ```bash
   cd contracts
   rm -rf lib cache
   forge install
   ```

5. **Try building again**:
   ```bash
   cd contracts && forge build
   ```

---

### "test execution out of gas"

**Symptoms**:

```
forge test execution reverted: OutOfGas
  Function: testSettlementWithLargeProof
```

**Causes**:

- Test uses too much gas
- Fuzzing with many iterations
- Complex contract interaction

**Solutions**:

1. **Reduce fuzzing runs** (in test file):

   ```solidity
   // Add at top of test file:
   /// forge-config: default.fuzz.runs = 10  (instead of default 256)

   function testFuzzSettlement(bytes32 id) public {
     // Test logic
   }
   ```

2. **Optimize test setup**:

   ```solidity
   // ❌ Before: Redundant setup
   function testManySettlements() public {
     for (uint i = 0; i < 1000; i++) {
       settlement.execute(id, proof);  // 1000 executions = high gas
     }
   }

   // ✅ After: Test key scenario
   function testSettlement() public {
     settlement.execute(id, proof);
   }

   function testMultipleSettlements() public {
     settlement.execute(id1, proof1);
     settlement.execute(id2, proof2);
     // Test only 2-3 scenarios, not 1000
   }
   ```

3. **Check gas limits in Makefile**:

   ```bash
   grep -n "gas\|FOUNDRY" contracts/Makefile
   ```

4. **Run with gas reporting**:
   ```bash
   cd contracts && forge test --gas-report
   # See which functions consume most gas
   ```

---

## Frontend Development Issues

### "pnpm dev fails: port already in use"

**Symptoms**:

```
Error: listen EADDRINUSE: address already in use :::5173
```

**Causes**:

- Another process using port 5173
- Previous dev server still running
- Port configured differently

**Solutions**:

1. **Kill process on port 5173**:

   ```bash
   # macOS/Linux
   lsof -i :5173  # Find process
   kill -9 <PID>  # Kill it

   # Or use direct command
   pkill -f "vite\|dev:frontend"
   ```

2. **Use different port**:

   ```bash
   pnpm dev:frontend -- --port 5174
   ```

3. **Restart dev server**:

   ```bash
   # Stop all processes
   pkill -f "vite\|anvil\|supersim"

   # Start fresh
   pnpm dev
   ```

---

### "TypeScript errors in IDE but tests pass"

**Symptoms**:

- VS Code shows red squiggles
- `pnpm typecheck` passes locally
- CI passes but IDE unhappy

**Causes**:

- IDE cache stale
- TypeScript version mismatch
- tsconfig.json not reloaded

**Solutions**:

1. **Reload TypeScript server in VS Code**:
   - Press: `Cmd/Ctrl + Shift + P`
   - Type: "TypeScript: Restart TS Server"
   - Press Enter

2. **Clear IDE cache**:

   ```bash
   # Close VS Code
   rm -rf .vscode/
   rm -rf node_modules/.vite
   pnpm i
   # Reopen VS Code
   ```

3. **Verify TypeScript version**:

   ```bash
   pnpm ls typescript
   # Should show 5.7.2+
   ```

4. **Force typecheck**:
   ```bash
   pnpm typecheck --strict
   ```

---

### "Module not found error in browser"

**Symptoms**:

```
Browser console: Uncaught ReferenceError: MARK is not defined
or
Failed to resolve module: @eth-optimism/viem
```

**Causes**:

- Dependency not installed
- Import path wrong
- Build cache stale

**Solutions**:

1. **Reinstall dependencies**:

   ```bash
   rm -rf node_modules pnpm-lock.yaml
   pnpm i
   ```

2. **Check import path**:

   ```typescript
   // ❌ Wrong
   import { useAccount } from "wagmi"; // Missing path

   // ✅ Correct
   import { useAccount } from "wagmi";
   import { supersimL2A } from "@eth-optimism/viem/chains";
   ```

3. **Clear browser cache**:

   ```bash
   # Hard refresh in browser
   Cmd/Ctrl + Shift + R (or Cmd/Ctrl + Shift + Delete, then clear cache)
   ```

4. **Restart dev server**:
   ```bash
   pkill -f "vite"
   pnpm dev:frontend
   ```

---

## Testing Issues

### "forge test hangs or times out"

**Symptoms**:

```
forge test
# ... waiting forever ...
Test suite hangs without completing
```

**Causes**:

- Infinite loop in test
- Test stuck waiting for transaction
- Network call timeout
- Foundry offline mode issue

**Solutions**:

1. **Kill hanging process**:

   ```bash
   # In another terminal
   pkill -f forge
   ```

2. **Run single test to isolate**:

   ```bash
   cd contracts
   forge test --match-test "testSpecificFunction" -vv
   ```

3. **Check for infinite loops** in problematic test:

   ```solidity
   // ❌ Bad: Infinite loop
   function testLoop() public {
     while(true) {  // INFINITE!
       settlement.execute(...);
     }
   }

   // ✅ Good: Bounded loop
   function testLoop() public {
     for (uint i = 0; i < 10; i++) {  // 10 iterations max
       settlement.execute(...);
     }
   }
   ```

4. **Try offline mode**:

   ```bash
   cd contracts
   FOUNDRY_OFFLINE=true forge test
   ```

5. **Increase timeout**:
   ```bash
   timeout 300 forge test  # 5 minute timeout
   ```

---

### "test fails with 'insufficient balance'"

**Symptoms**:

```
forge test error: Assertion failed
  Message: Insufficient balance
```

**Causes**:

- Test didn't fund account properly
- Token transfer didn't work
- Balance calculation wrong

**Solutions**:

1. **Add explicit balance setup**:

   ```solidity
   function setUp() public {
     // Mint tokens to test accounts
     vm.prank(owner);
     token.mint(user, 1000e18);  // 1000 tokens

     // Verify balance
     assertEq(token.balanceOf(user), 1000e18);
   }
   ```

2. **Use deal()** (simpler):

   ```solidity
   // Set ETH balance
   vm.deal(user, 10 ether);
   assertEq(user.balance, 10 ether);

   // Set ERC20 balance (requires contract)
   deal(address(token), user, 1000e18);
   assertEq(token.balanceOf(user), 1000e18);
   ```

3. **Debug balance in test**:

   ```solidity
   function testDebugBalance() public {
     emit log_uint(token.balanceOf(user));  // Print to console
     assertEq(token.balanceOf(user), expectedAmount);
   }

   // Run with: forge test -vv
   ```

---

## Deployment Issues

### "Insufficient balance for gas fees"

**Symptoms**:

```
Error: Insufficient balance. Required: 0.5 ETH, Have: 0.01 ETH
```

**Solutions**:

```bash
# Check balance
cast balance $DEPLOYER_ADDRESS --rpc-url $RPC

# Fund account (from another address)
cast send $DEPLOYER_ADDRESS --value 1ether \
  --rpc-url $RPC \
  --private-key $FUNDING_KEY

# Verify funded
cast balance $DEPLOYER_ADDRESS --rpc-url $RPC
```

---

### "Deployment timeout: transaction not mined"

**Symptoms**:

```
Error: Transaction not mined after 300 seconds
TX Hash: 0x1234...
```

**Causes**:

- Network congestion
- Gas price too low
- RPC node issues

**Solutions**:

1. **Check transaction status**:

   ```bash
   cast receipt 0x1234... --rpc-url $RPC
   # If output is empty, transaction dropped
   ```

2. **Increase gas price**:

   ```bash
   # Check current gas
   cast gas-price --rpc-url $RPC

   # Redeploy with higher gas
   GASPRICE=50gwei pnpm sup deploy create2 ...
   ```

3. **Verify RPC is healthy**:

   ```bash
   # Test RPC
   curl -X POST $RPC \
     -H "Content-Type: application/json" \
     -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
   ```

4. **Wait longer**:
   ```bash
   # Testnet congestion? Wait 5-10 minutes and retry
   sleep 300
   pnpm sup deploy ...
   ```

---

## CI/CD Workflow Issues

### "GitHub Actions workflow stuck"

**Symptoms**:

- Workflow shows "In progress" for >1 hour
- No error message

**Solutions**:

1. **Cancel workflow**:
   - Go to: https://github.com/trade/mark/actions
   - Find workflow
   - Click: "Cancel workflow"

2. **Check logs**:
   - Click workflow name
   - View "Logs" section
   - Look for last message before hang

3. **Restart workflow**:
   - Go to workflow run
   - Click: "Re-run failed jobs"

4. **Check GitHub status**:
   - https://www.githubstatus.com/
   - If GitHub is down, wait for recovery

---

### "Secrets not available in workflow"

**Symptoms**:

```
Error: Environment variable DEPLOYER_KEY not set
```

**Causes**:

- Secret not added to repository
- Secret name misspelled
- Secret scoped to wrong environment

**Solutions**:

1. **Add secret to repository**:
   - Go to: Settings → Secrets and variables → Actions
   - Click: "New repository secret"
   - Name: `DEPLOYER_KEY`
   - Value: (paste actual private key)
   - Click: "Add secret"

2. **Verify secret name in workflow**:

   ```yaml
   # In .github/workflows/deploy.yml
   - name: Deploy
     env:
       DEPLOYER_KEY: ${{ secrets.DEPLOYER_KEY }} # Must match exact name
     run: pnpm sup deploy create2
   ```

3. **For environment-specific secrets**:

   ```yaml
   environment: production # Or staging
   # Secrets from production environment used
   ```

4. **Re-run workflow** after adding secret:
   - Go to workflow run
   - Click: "Re-run failed jobs"

---

### "Slither workflow fails but locally passes"

**Symptoms**:

```
GitHub Actions: Slither Core Contracts → FAILED
Local: cd contracts && make slither-core → PASSED
```

**Causes**:

- Slither version different
- Environment differences
- Cache issues

**Solutions**:

1. **Update Slither locally**:

   ```bash
   pip install --upgrade slither-analyzer
   slither --version
   ```

2. **Run Slither like CI does**:

   ```bash
   cd contracts && make slither-core
   # Should match GitHub output
   ```

3. **Check Slither remappings**:
   ```bash
   # Verify remappings in workflow
   slither src/token/RYLA.sol \
     --solc-remaps "@interop-lib/=lib/interop-lib/src/ @openzeppelin/=lib/createx/lib/openzeppelin-contracts/"
   ```

---

## Network & RPC Issues

### "RPC endpoint timeout or unreachable"

**Symptoms**:

```
Error: connect ECONNREFUSED 127.0.0.1:9545
or
Error: Gateway timeout
```

**Causes**:

- Local network (anvil/supersim) not running
- RPC URL wrong
- Network congestion

**Solutions**:

1. **For local network**:

   ```bash
   # Check if supersim is running
   lsof -i :9545  # Should show anvil process

   # If not, start it
   pnpm dev:supersim
   ```

2. **For public RPC**:

   ```bash
   # Verify RPC URL
   echo $MAINNET_RPC
   # Example: https://mainnet.infura.io/v3/YOUR_API_KEY

   # Test RPC
   curl -X POST $MAINNET_RPC \
     -H "Content-Type: application/json" \
     -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
   ```

3. **Retry with timeout**:
   ```bash
   # Use cast with timeout
   cast call 0x123... "balanceOf(address)" $ACCOUNT \
     --rpc-url $RPC \
     --timeout 30s  # 30 second timeout
   ```

---

### "Contract address not found / zero address"

**Symptoms**:

```
Error: Contract address is 0x0000000000000000000000000000000000000000
or
Error: Contract not found at 0x1234...
```

**Causes**:

- Deployment failed silently
- Contract address misconfigured
- Wrong network selected

**Solutions**:

1. **Check deployment status**:

   ```bash
   # Look at broadcast files
   ls -la contracts/broadcast/
   cat contracts/broadcast/Deploy.s.sol/*/run-latest.json | jq '.transactions'
   ```

2. **Verify contract deployed**:

   ```bash
   # Check if code exists at address
   cast code 0x1234... --rpc-url $RPC
   # Should show bytecode (not 0x)
   ```

3. **Check network**:

   ```bash
   # Verify you're on correct network
   cast chain-id --rpc-url $RPC
   # Mainnet: 1
   # OP Sepolia: 11155420
   # Sepolia: 11155111
   ```

4. **Redeploy if needed**:
   ```bash
   # Get fresh deployment
   cd contracts && make ci-full  # Verify locally first
   pnpm sup deploy create2 ...   # Deploy
   ```

---

## Getting More Help

- **Check existing issues**: https://github.com/trade/mark/issues
- **Review pull requests**: https://github.com/trade/mark/pulls
- **Read documentation**: `CONTRIBUTING.md`, `DEPLOYMENT.md`, `BRANCHING.md`
- **Ask in GitHub Discussions** (if enabled)

---

**Version**: 1.0  
**Last Updated**: 2026-06-02
