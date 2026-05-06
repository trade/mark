# Project Review (May 5, 2026)

## Scope

This review covers:
- Repository structure and build/test tooling.
- Frontend app purpose and implementation level.
- Smart-contract architecture and key security controls.
- CI/release guardrails and operations readiness.

## What was validated directly

- Root metadata and scripts in `package.json`.
- High-level docs in `README.md`, `contracts/README.md`, and `contracts/ARCHITECTURE.md`.
- Core contracts:
  - `contracts/src/token/RYLA.sol`
  - `contracts/src/bridge/MARKBridgeAdapter.sol`
  - `contracts/src/settlement/MARKSettlementModule.sol`
- Frontend entry screen in `src/App.tsx`.
- TypeScript and lint health (`pnpm -s typecheck`, `pnpm -s lint`).

## High-level assessment

The project is organized with unusually strong operational discipline for an early-stage protocol stack:
- Clear branch/release policy and staged promotion model.
- Security-oriented contract controls (`AccessControlDefaultAdminRules`, operator gating, replay protection, production-mode lock).
- Dedicated release-gate and evidence-manifest workflows aimed at auditable deployments.

Current risk profile appears moderate and mostly operational, not architectural:
- The core solidity modules are intentionally narrow and separated by domain.
- The largest residual risks are around environment-driven correctness (deployment configuration, RPC assumptions, secrets handling) and proof/verifier governance rather than obvious on-chain logic flaws.

## Detailed findings

### 1) Architecture and layering: strong

- Domain boundaries are explicitly declared and enforced by architecture/layering guard scripts (documented in `contracts/ARCHITECTURE.md`).
- Bridge and settlement modules are cleanly decoupled and both depend on token primitives rather than each other.

Why this matters:
- Reduces accidental coupling and blast radius from future changes.
- Improves auditability and ownership by domain.

### 2) Token design (`RYLA`): conservative and controllable

Observed controls:
- Delayed admin handoff via `AccessControlDefaultAdminRules` with `DEFAULT_ADMIN_DELAY = 1 days`.
- Separate `MINTER_ROLE` and `BURNER_ROLE` with explicit grant/revoke APIs.
- Input hardening for zero address and zero amount.

Potential improvement (non-critical):
- Consider adding an explicit cap/issuance policy module if supply governance is expected to be publicly constrained by policy, not only by role management.

### 3) Bridge adapter: practical risk controls in place

Observed controls:
- `OPERATOR_ROLE` gating.
- Destination-chain allowlist.
- Optional transaction/daily limits (`maxPerTx`, `dailyCap`) with epoch reset.
- Uses `SafeERC20`, `forceApprove`, and `nonReentrant`.

Potential improvement (medium):
- Add optional per-destination caps (not just global daily cap) to isolate lane-specific risk.
- Add explicit pause/emergency brake if not already handled by off-chain release controls.

### 4) Settlement module: good baseline for production hardening

Observed controls:
- Replay protection through `consumedIntents[intentId]`.
- Optional verifier hook with explicit `proofValidationEnabled` state.
- Irreversible `productionMode` that requires proof validation to stay active.
- Burn flow uses escrow invariants before/after burn to catch token accounting drift.

Potential improvement (medium):
- Add structured reason codes/events for verifier failures to simplify operations and triage (currently returns a boolean).
- Consider explicit bounded-size checks on `proof` payload length to reduce griefing surface on calldata-heavy failures.

### 5) Frontend: currently operational dashboard, not transaction UX

- `src/App.tsx` is intentionally informational (topology, release flow, runbook commands).
- No wallet interaction, chain writes, or end-user flows yet.

Implication:
- Security criticality is currently centered on contracts and operational scripts, not frontend execution paths.

### 6) Tooling and CI health: partially validated

Validated now:
- TypeScript typecheck passes.
- ESLint passes.

Not validated in this environment:
- Foundry tests (`forge test`) could not run due to missing Foundry binary.

Impact:
- No claim is made here about current pass/fail status of solidity unit/invariant/e2e suites in this container.

## Recommendations (prioritized)

1. **P0 – Enforce executable preflight in CI image**
   - Ensure `forge`, `slither`, and all release-gate dependencies are available in every CI execution context to prevent false confidence from partial checks.

2. **P1 – Strengthen bridge risk segmentation**
   - Introduce optional per-destination rate limits and/or per-operator quotas for incident containment.

3. **P1 – Expand settlement observability**
   - Emit richer verification telemetry and failure reason mapping for on-call diagnostics.

4. **P2 – Document explicit trust model**
   - Add a compact “trust assumptions” section (operator keys, verifier key custody, break-glass policy, evidence signature authority rotation) in `contracts/RUNBOOK.md` or `README.md`.

5. **P2 – Scenario-driven negative tests**
   - Add/confirm tests for edge cases: verifier flip attempts in production mode, proof replay across modules/chains, cap rollover boundaries, and deflationary/non-standard ERC20 behavior assumptions in bridge/settlement wrappers.

## Final verdict

- **Design quality:** Good
- **Security posture (observed):** Good baseline with thoughtful controls
- **Operational readiness:** Good process direction, but environment consistency for solidity toolchain must be enforced to avoid blind spots
- **Main gap to close next:** deterministic, fully reproducible release-gate execution across all CI/runtime environments

## Next best recommendation (based on current status)

If only one thing is done next, the highest-leverage move is:

**Create a reproducible, toolchain-pinned execution path for `make release-gate` and `./script/ops/mainnet-readiness.sh` (containerized or Nix/asdf pinned), then run it in CI on every protected branch.**

Why this is first:
- Current gates are already strong and comprehensive, but they hard-fail when core binaries (`forge`, `jq`, `slither`) are absent.
- This means process quality is high, but reliability of execution across environments is still the bottleneck.
- Once runtime parity is guaranteed, all other recommendations (caps, telemetry, trust-model docs) become safer and easier to validate.

### Practical implementation option

1. Add a dedicated dev/CI container image containing exact versions of:
   - Foundry (`forge`), Slither, `jq`, Node/pnpm.
2. Add a single command wrapper (example: `make release-gate-container`) to execute gates inside that image.
3. Wire branch protection checks to this wrapper for `dev`, `canary`, and `main` with policy-appropriate strictness.
4. Persist generated artifacts (`release-gate-*.json`, mainnet gate artifacts) as CI build outputs for audit trail continuity.

### Better-solution alternative (if minimizing ops overhead)

If maintaining a custom image is heavy, use a lightweight version manager baseline:
- `asdf` + `.tool-versions` for `nodejs`, `jq`, and Foundry toolchain pinning.
- CI bootstrap script that validates tool versions before any gate starts.

This is less hermetic than containers, but still significantly reduces drift and false negatives.

## Opinion on transferring to organization before next improvements

Yes — transferring to your organization first is a sensible move.

Given your note that CodeQL is only available at organization level, transfer-first gives you two immediate benefits:
1. Security scanning baseline (CodeQL + org-level policy controls) becomes enforceable before feature hardening.
2. Follow-up recommendations can be validated under the same governance context that production will use.

### Recommended transfer-first sequence

1. Transfer repository to organization and re-enable CodeQL workflow triggers.
2. Turn on required status checks for at least:
   - lint + typecheck
   - contract CI fast/full
   - CodeQL scan
3. Add branch protections for `dev`, `canary`, and `main` aligned to your promotion path.
4. Only then execute the next hardening item (reproducible release-gate runtime pinning), so it lands under org-enforced controls from day one.

### Practical caution list after transfer

- Verify all GitHub Actions secrets/variables were migrated or recreated at org/repo scope.
- Re-check workflow permissions (especially `security-events: write` for CodeQL uploads).
- Confirm artifact retention policy for release evidence outputs.
- Validate that branch protection rules are actually active on transferred default/protected branches.

This order minimizes rework and prevents a situation where hardening work is merged before your final governance/security baseline is active.

## Solo-founder execution plan (security/privacy first)

Given you are operating solo and security/privacy are top priority, the best practical approach is:

**Do fewer things, but make each control enforceable by automation before scaling scope.**

### Recommended 14-day plan

#### Day 1-3: Governance baseline after org transfer

1. Re-enable CodeQL and make it a required check.
2. Enforce protected branches with no direct push to `main` and `canary`.
3. Require passing checks before merge:
   - frontend lint/typecheck
   - contracts `ci-fast`
   - CodeQL

Outcome: every future change must pass a minimum security gate automatically.

#### Day 4-7: Deterministic release runtime

1. Create pinned execution environment (container preferred).
2. Add one canonical command for release verification (example: `make release-gate-container`).
3. Store release artifacts and evidence manifests as CI artifacts.

Outcome: reproducible release evidence; lower chance of hidden local-environment drift.

#### Day 8-10: Secrets and key-material hardening

1. Split keys by environment (staging/mainnet) and role (deploy/verify/sign).
2. Rotate any legacy/shared keys.
3. Add an emergency key revocation + recovery runbook section.

Outcome: reduced blast radius from key compromise.

#### Day 11-14: Privacy and incident readiness

1. Add privacy-impact checklist for each release (what data is emitted on-chain/off-chain, metadata leakage review).
2. Add incident playbook for verifier compromise, operator compromise, and bad release artifact.
3. Run one tabletop drill (self-run) and capture improvements.

Outcome: preparedness for the exact failures that matter most to institutional users.

### Best recommendation for your context

If you can only choose one immediate task: **make CodeQL + branch protection + required checks fully active right after transfer**.
That single step gives you the highest security ROI as a solo builder by forcing discipline on every change.
