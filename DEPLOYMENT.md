# MARK Protocol Deployment Runbook

**Purpose**: Step-by-step procedures for deploying MARK Protocol to staging (OP Sepolia) and mainnet.

**Audience**: Release maintainer, DevOps, protocol stewards.

**Last Updated**: 2026-05-06

---

## Table of Contents

1. [Pre-Deployment Checklist](#pre-deployment-checklist)
2. [Staging Deployment (OP Sepolia)](#staging-deployment-op-sepolia)
3. [Mainnet Deployment](#mainnet-deployment)
4. [Verification & Monitoring](#verification--monitoring)
5. [Rollback Procedures](#rollback-procedures)
6. [Troubleshooting](#troubleshooting)
7. [Post-Deployment](#post-deployment)

---

## Pre-Deployment Checklist

### Environment Setup

- [ ] All environments sourced: `staging.env` and/or `mainnet.env`
- [ ] Private keys loaded (via GitHub Secrets, not committed)
- [ ] RPC endpoints accessible (test: `curl <RPC_URL>`)
- [ ] Sufficient balance in deployer account (≥ 0.5 ETH for gas)

### Code Readiness

- [ ] All tests passing: `cd contracts && make ci-full`
- [ ] Slither scan clean: `cd contracts && make slither-core`
- [ ] No uncommitted changes: `git status` (clean)
- [ ] On correct branch:
  - Staging: `dev` branch
  - Mainnet: `main` branch
- [ ] Latest contracts built: `pnpm build:contracts`

### Governance & Evidence

For **mainnet only**:
- [ ] Release evidence manifest generated
- [ ] Manifest verified & signatures valid
- [ ] Release checklist completed
- [ ] CODEOWNERS review approved

---

## Staging Deployment (OP Sepolia)

### Phase 1: Pre-Release Validation

**Target Branch**: `dev`

**Estimated Time**: 15 minutes

#### Step 1: Trigger Staging Rehearsal (Automated)

When you push to `dev`, the `contracts-staging-rehearsal` workflow auto-triggers.

```bash
# On dev branch
git status  # Should show "On branch dev"
git log --oneline -1  # Verify latest commit

# Wait for GitHub workflow to start
# Monitor: https://github.com/trade/mark/actions
```

**What this does**:
- Deploys contracts to OP Sepolia L2A
- Deploys contracts to OP Sepolia L2B
- Runs post-deployment validation tests
- Generates evidence artifacts

**Expected output**:
```
✅ Deployment successful
✅ All chains have contracts deployed
✅ Evidence manifest generated
✅ Artifacts uploaded
```

#### Step 2: Verify Staging Deployment

Monitor the workflow in GitHub Actions:

```
Contracts Staging Rehearsal Workflow
├─ Deployment (OP Sepolia L2A) ✅
├─ Deployment (OP Sepolia L2B) ✅
├─ Post-deployment validation ✅
└─ Evidence artifact generation ✅
```

**Check deployment on OP Sepolia**:
```bash
# Verify contract on OP Sepolia explorer
# https://sepolia-optimism.etherscan.io

# Expected contracts:
# - RYLA (token)
# - MARKBridgeAdapter
# - MARKSettlementModule
# - AttestedSettlementVerifier
```

#### Step 3: Run Manual Validation (Optional)

```bash
# Source staging config
set -a
source contracts/config/profiles/staging.env
set +a

# Run validation tests
cd contracts
MARK_RELEASE_EXECUTE=true MARK_SETTLEMENT_PROOF_ENABLED=true \
  ./script/ops/validate-prod-env.sh
```

**Expected output**:
```
Staging environment validation
├─ RPC endpoints reachable ✅
├─ Contracts deployed ✅
├─ Settlement module functional ✅
└─ Bridge adapter operational ✅
```

### Phase 2: Evidence Generation & Verification

#### Step 4: Generate Evidence Manifest

```bash
cd contracts

# Generate official release evidence
make generate-evidence-manifest

# Output: contracts/broadcast/evidence-manifest.json
```

**What's in manifest**:
- Deployment timestamps
- Contract addresses (all chains)
- Transaction hashes
- Test results
- Slither findings (if any)

#### Step 5: Verify Evidence

```bash
cd contracts

# Verify manifest integrity
make verify-evidence-manifest

# Expected output:
# ✅ Manifest is valid
# ✅ All contracts verified
# ✅ No tampering detected
```

#### Step 6: Sign Evidence (For Production)

```bash
cd contracts

# If signing releases (recommended for mainnet):
make sign-evidence-manifest

# Prompts for signing key, outputs: evidence-manifest.sig
```

### Phase 3: Promote to Production (Canary → Main)

#### Step 7: Create PR: Canary → Main

```bash
# Create PR via GitHub UI or CLI:
gh pr create \
  --title "Release: MARK Protocol v0.1.0" \
  --base main \
  --head dev \
  --body "See DEPLOYMENT.md for release procedures" \
  --label "release"
```

**PR description should include**:
```markdown
## Release Summary
- Version: v0.1.0
- Settlement module: Production-ready
- Bridge adapter: Tested on OP Sepolia
- Evidence: Available in broadcast/evidence-manifest.json

## Verification
- [x] All tests passing
- [x] Staging rehearsal passed
- [x] Evidence manifest generated
- [x] Slither findings reviewed

## Deployment Impact
- [ ] Breaking API changes: None
- [ ] Database migrations: None
- [ ] Environment variables: None
```

#### Step 8: Wait for CI Checks

GitHub Actions will automatically run:
- ✅ Contracts Unit + Invariant tests
- ✅ Slither core contracts scan
- ✅ Secrets drift guard
- ✅ Release evidence validator
- ✅ Release PR checklist

**Expected time**: 3-5 minutes

#### Step 9: Code Review & Approval

- [ ] CODEOWNERS review requested (auto-required)
- [ ] Wait for review comments (if any)
- [ ] Address feedback
- [ ] Request re-review if changes made

#### Step 10: Merge to Main

```bash
# After approval, merge PR
# Use GitHub UI: Click "Merge pull request"

# Or via CLI:
gh pr merge <PR_NUMBER> --squash --delete-branch
```

---

## Mainnet Deployment

### Pre-Mainnet Gate

**Branch**: `main`

**After successful PR merge to `main`, follow steps below.**

### Phase 1: Production Readiness Gate

#### Step 11: Dispatch Mainnet Readiness Workflow

This is a **manual workflow dispatch** (not automatic).

```bash
# Via GitHub CLI:
gh workflow run contracts-mainnet-readiness.yml \
  --ref main \
  -f environment=production

# Or via GitHub UI:
# 1. Go to Actions tab
# 2. Select "Contracts Mainnet Readiness" workflow
# 3. Click "Run workflow"
# 4. Select branch: main
# 5. Click "Run workflow" button
```

**What this does**:
- Validates production environment variables
- Runs full contract test suite against mainnet RPCs
- Verifies deployment readiness
- Generates mainnet evidence

**Expected time**: 10-15 minutes

#### Step 12: Monitor Mainnet Readiness

```
Contracts Mainnet Readiness Workflow
├─ Environment validation ✅
├─ Mainnet RPC connectivity ✅
├─ Full test suite (mainnet) ✅
├─ Production lock verification ✅
└─ Readiness report generated ✅
```

**Check workflow output**:
```bash
# View workflow details
gh run view <RUN_ID> --repo trade/mark
```

**If successful**:
```
✅ Production is ready for deployment
✅ All safety checks passed
✅ Evidence artifacts prepared
```

**If failed**:
- See [Troubleshooting](#troubleshooting) section
- DO NOT proceed to deployment
- Fix issues, create new PR, restart from Step 7

### Phase 2: Deployment Execution

#### Step 13: Approve Deployment Authorization

Production deployments require manual approval from authorized personnel.

```bash
# Check production environment status
set -a
source contracts/config/profiles/mainnet.env
set +a

# Verify deployment keys are loaded securely
# (Should NOT print private keys)
echo "Deployer ready: $DEPLOYMENT_ADDRESS"
```

#### Step 14: Execute Mainnet Deployment

```bash
# Navigate to contracts directory
cd contracts

# List what will be deployed
make smoke-production-mode  # Dry-run, no actual deployment

# If dry-run looks good, execute actual deployment:
MARK_RELEASE_EXECUTE=true \
  ./script/ops/dispatch-release-evidence-sequence.sh
```

**What happens**:
1. Deploys RYLA token
2. Deploys MARKBridgeAdapter
3. Deploys MARKSettlementModule
4. Deploys AttestedSettlementVerifier
5. Configures cross-chain bridges
6. Locks production state

**Expected output**:
```
Deploying to mainnet...
✅ RYLA deployed: 0x1234...
✅ Bridge deployed: 0x5678...
✅ Settlement deployed: 0x9abc...
✅ Verifier deployed: 0xdef0...
✅ Cross-chain relay configured
✅ Production lock verified
```

**Expected time**: 5-10 minutes (includes block confirmations)

### Phase 3: Post-Deployment Verification

#### Step 15: Verify Production State

```bash
cd contracts

# Verify production lock is in effect
make verify-production-lock

# Expected output:
# ✅ Production mode locked
# ✅ All safety invariants in place
# ✅ Emergency pause enabled (optional)
```

#### Step 16: Create Release Tag

After successful mainnet deployment:

```bash
# Tag release (local)
git tag -a v0.1.0 -m "Release: MARK Protocol v0.1.0

Contracts deployed to mainnet.
Settlement live on OP Mainnet.
Evidence: <commit-sha>"

# Push tag
git push origin v0.1.0
```

**GitHub auto-creates release**: Check https://github.com/trade/mark/releases

#### Step 17: Generate Mainnet Evidence

```bash
cd contracts

# Generate final evidence report
make generate-evidence-manifest

# Verify evidence
make verify-evidence-manifest

# Sign evidence (if keys available)
make sign-evidence-manifest
```

#### Step 18: Wire Groth16SettlementVerifier (if using ZK settlement)

After deploying `Groth16SettlementVerifier`, two post-deploy calls are required
before ZK-based settlement is active. `AttestedSettlementVerifier` remains the
fallback until this is complete.

Required environment variables for this step:
- `MAINNET_RPC`
- `GROTH16_VERIFIER_ADDRESS`
- `SETTLEMENT_MODULE_ADDRESS`
- `MARK_POOL_VERIFIER_ADDRESS` (source this from the deployed `MARKPoolVerifier`
  address in your deployment output/artifacts for the target network)

```bash
# 1. Bind the verifier to the settlement module (prevents cross-module replay)
cast send $GROTH16_VERIFIER_ADDRESS \
  "setSettlementModule(address)" $SETTLEMENT_MODULE_ADDRESS \
  --rpc-url $MAINNET_RPC --interactive

# 2. Set the MARKPoolVerifier contract
cast send $GROTH16_VERIFIER_ADDRESS \
  "setVerifierContract(address)" $MARK_POOL_VERIFIER_ADDRESS \
  --rpc-url $MAINNET_RPC --interactive

# 3. Wire into settlement module
cast send $SETTLEMENT_MODULE_ADDRESS \
  "setVerifier(address,bool)" $GROTH16_VERIFIER_ADDRESS true \
  --rpc-url $MAINNET_RPC --interactive
```

See `contracts/RUNBOOK.md` → "Groth16 Direction Rollout" for the full
migration sequence before enabling production mode.

---

## Verification & Monitoring

### During Deployment

Monitor these metrics in real-time:

```bash
# Check deployment transactions
# https://etherscan.io/tx/<TX_HASH>

# Watch contract state updates
cast call 0x<MARK_ADDRESS> "name()" --rpc-url $MAINNET_RPC

# Monitor gas prices
ethgas-tracker  # or: https://ethgasstation.info
```

### Post-Deployment Health Checks

#### Health Check Script

```bash
#!/bin/bash
# contracts/script/ops/health-check.sh

set -a
source config/profiles/mainnet.env
set +a

# Required environment variables (set in config/profiles/mainnet.env
# or exported from deployment outputs before running this script):
: "${MAINNET_RPC:?Missing MAINNET_RPC}"
: "${RYLA_ADDRESS:?Missing RYLA_ADDRESS}"
: "${SETTLEMENT_ADDRESS:?Missing SETTLEMENT_ADDRESS}"
: "${BRIDGE_ADDRESS:?Missing BRIDGE_ADDRESS}"
: "${VERIFIER_ADDRESS:?Missing VERIFIER_ADDRESS}"

echo "🏥 MARK Protocol Mainnet Health Check"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check RYLA token
cast call $RYLA_ADDRESS "totalSupply()" --rpc-url $MAINNET_RPC
echo "✅ RYLA token operational"

# Check settlement module
cast call $SETTLEMENT_ADDRESS "isProofEnabled()" --rpc-url $MAINNET_RPC
echo "✅ Settlement module functional"

# Check bridge adapter
cast call $BRIDGE_ADDRESS "isBridgeActive()" --rpc-url $MAINNET_RPC
echo "✅ Bridge adapter connected"

# Check verifier
cast call $VERIFIER_ADDRESS "name()" --rpc-url $MAINNET_RPC
echo "✅ Verifier contract live"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✨ All systems operational!"
```

Run health checks:
```bash
cd contracts
./script/ops/health-check.sh
```

---

## Rollback Procedures

### Scenario 1: Deployment Failed Mid-Way

**If deployment halted before completion**:

```bash
# Check what deployed successfully
cd contracts && git log --oneline broadcast/ | head -5

# Redeploy missing contracts
make smoke-production-mode  # Verify first

MARK_RELEASE_EXECUTE=true \
  ./script/ops/dispatch-release-evidence-sequence.sh
```

### Scenario 2: Post-Deployment Issue (Within 24h)

**If issue found shortly after deployment**:

1. **Pause operations** (if applicable):
   ```bash
   cast send $SETTLEMENT_ADDRESS "pause()" \
     --rpc-url $MAINNET_RPC \
     --interactive
   ```

2. **Document issue**: Create GitHub issue with:
   - What went wrong
   - When detected
   - User impact
   - Initial mitigation

3. **Prepare hotfix PR**:
   ```bash
   git checkout dev
   git pull origin dev
   git checkout -b hotfix/critical-issue-name
   # Make fixes
   # Push and create PR into main
   ```

4. **Deploy hotfix**: Follow full deployment procedure again

### Scenario 3: Contract Bug Found (Long-term)

**If critical bug discovered after deployment**:

```bash
# Create hotfix branch from main
git checkout main
git pull origin main
git checkout -b hotfix/contract-bug-fix

# Fix the bug
# Commit and push
git push origin hotfix/contract-bug-fix

# Create PR: hotfix → main
# After approval, deploy as new release
```

---

## Troubleshooting

### "Deployment Failed: Insufficient Balance"

**Cause**: Deployer account has < 0.5 ETH for gas fees

**Fix**:
```bash
# Check balance
cast balance $DEPLOYER_ADDRESS --rpc-url $MAINNET_RPC

# Fund deployer (from treasury or team account)
cast send $DEPLOYER_ADDRESS --value 1ether \
  --rpc-url $MAINNET_RPC \
  --interactive

# Retry deployment
MARK_RELEASE_EXECUTE=true \
  ./script/ops/dispatch-release-evidence-sequence.sh
```

### "Workflow Timeout: Tests Took Too Long"

**Cause**: Tests exceeded 1 hour limit on GitHub Actions

**Fix**:
```bash
# Run tests locally to find slow test
cd contracts && make ci-full

# Profile test execution
forge test --gas-report

# Look for tests marked [SLOW]
# Consider splitting into separate PR or optimizing
```

### "Slither Findings: High Severity Alert"

**Cause**: Security analysis found a medium/high issue

**Fix**:
```bash
cd contracts && make slither-core

# Review findings in Slither output
# If legitimate issue:
#   1. Fix in code
#   2. Create new PR
#   3. Restart deployment process
#
# If false positive:
#   1. Document why it's safe
#   2. Add to slither exclusions in Makefile
#   3. Document reasoning in comments
```

### "Evidence Manifest Verification Failed"

**Cause**: Manifest was modified or corrupted

**Fix**:
```bash
cd contracts

# Regenerate manifest
make generate-evidence-manifest

# Verify new manifest
make verify-evidence-manifest

# If still failing, check git history
git log --oneline broadcast/evidence-manifest.json | head -3
```

### "Staging Rehearsal Passed but Mainnet Failed"

**Cause**: Environment differences (OP Sepolia vs OP Mainnet)

**Fix**:
```bash
# Check environment differences
diff contracts/config/profiles/staging.env \
    contracts/config/profiles/mainnet.env

# Verify mainnet RPC is healthy
curl -X POST $MAINNET_RPC \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'

# Re-run mainnet readiness with verbose logging
VERBOSE=true gh workflow run contracts-mainnet-readiness.yml --ref main
```

### "Production Lock Test Failed"

**Cause**: Deployed state doesn't match expected production configuration

**Fix**:
```bash
cd contracts

# Run production lock test with verbose output
make test-production-lock

# Check what's different
cast call $SETTLEMENT_ADDRESS "productionMode()" --rpc-url $MAINNET_RPC

# If misconfigured, deploy fix
git checkout -b fix/production-lock-config
# Update deployment script or initialization
git push origin fix/production-lock-config
# Create PR into main
```

---

## Post-Deployment

### Monitoring & Observability

1. **Set up alerts** for contract events:
   ```bash
   # Watch for SettlementExecuted events
   cast logs "SettlementExecuted(bytes32)" --rpc-url $MAINNET_RPC
   ```

2. **Weekly health checks**:
   ```bash
   cd contracts && ./script/ops/health-check.sh
   ```

3. **Monitor gas prices** for future deployments:
   - https://ethgasstation.info
   - https://ultrasound.money
   - https://www.blocknative.com/gas-estimator

### Communication

After successful mainnet deployment, communicate:

1. **Announce release**:
   - Twitter/Discord: "MARK Protocol v0.1.0 live on mainnet!"
   - Blog post: Architecture, features, security audit results

2. **Share evidence**: 
   - Link to deployment evidence manifest
   - Contract addresses on Etherscan
   - Verification instructions for community

3. **Create incident response playbook**:
   - Who to contact if issues arise
   - Escalation procedures
   - Monitoring dashboards

### Documentation Updates

- [ ] Update README.md with mainnet addresses
- [ ] Create DEPLOYMENT_EVIDENCE.md with manifest link
- [ ] Update BRANCHING.md with lessons learned
- [ ] Add release notes to GitHub Releases

### Team Debriefing

- [ ] Schedule post-deployment review
- [ ] Document what went well
- [ ] Document what could improve
- [ ] Update this runbook with learnings

---

## Quick Reference

### Command Cheat Sheet

```bash
# Staging deployment (automated on push to dev)
# No manual steps needed during staging rehearsal

# Mainnet readiness check (manual dispatch)
gh workflow run contracts-mainnet-readiness.yml --ref main

# Generate evidence
cd contracts && make generate-evidence-manifest

# Verify evidence
cd contracts && make verify-evidence-manifest

# Sign evidence
cd contracts && make sign-evidence-manifest

# Mainnet deployment (manual)
cd contracts && MARK_RELEASE_EXECUTE=true \
  ./script/ops/dispatch-release-evidence-sequence.sh

# Health check
cd contracts && ./script/ops/health-check.sh

# Rollback (pause operations) - use interactive or hardware-wallet signing
cast send $SETTLEMENT_ADDRESS "pause()" \
  --rpc-url $MAINNET_RPC --interactive

# Optional: hardware wallet signing (recommended for emergency mainnet ops)
cast send $SETTLEMENT_ADDRESS "pause()" \
  --rpc-url $MAINNET_RPC --ledger
```

### Timeline Estimates

- **Staging deployment**: 20 minutes (auto, mostly waiting)
- **Staging validation**: 10 minutes (manual checks)
- **Mainnet readiness**: 15 minutes (automated)
- **Mainnet deployment**: 10 minutes (includes block confirmations)
- **Post-deployment verification**: 5 minutes (health checks)

**Total**: ~60 minutes (mostly waiting for automation)

---

## Support & Escalation

- **Questions**: Open GitHub issue or discussion
- **Urgent issue**: Contact @trade/maintainers
- **Security concern**: See [SECURITY.md](SECURITY.md)

---

**Version**: 1.0  
**Last Updated**: 2026-05-06  
**Maintained By**: @trade/maintainers
