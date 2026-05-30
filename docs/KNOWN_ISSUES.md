# MARK Protocol — Known Issues and Design Decisions

This document lists known limitations and intentional design decisions that auditors should be aware of before reviewing the contracts. These are not bugs — they are accepted tradeoffs with documented rationale.

## KI-1: AttestedSettlementVerifier is a placeholder for ZK

**Contract:** `AttestedSettlementVerifier`

**Description:** The verifier uses ECDSA signatures (EIP-712) rather than zero-knowledge proofs. It is explicitly designed as a production-safe bridge step before ZK verifier integration. The ZK proof system has not been designed yet.

**Impact:** Settlement validity depends on attester key security rather than cryptographic proof. A compromised attester key allows fraudulent attestations (though still requires operator cooperation to execute).

**Accepted because:** The attested verifier provides meaningful security (role-gated, replay-protected, deadline-bound, module-bound) while the ZK system is being designed. Production mode lock ensures the verifier cannot be removed once activated.

---

## KI-2: No pause mechanism on MARKBridgeAdapter

**Contract:** `MARKBridgeAdapter`

**Description:** There is no `pause()` function. Emergency containment is achieved by revoking all `OPERATOR_ROLE` holders, which stops all bridge operations.

**Impact:** Emergency response requires an admin transaction to revoke operators. There is no single-transaction pause.

**Accepted because:** A pause function introduces pause-admin key risk. Operator revocation achieves the same containment without adding a new privileged role. The 1-day admin delay does not apply to role revocation — it is immediate.

---

## KI-3: setVerifier does not verify IUTXOSettlementVerifier compliance

**Contract:** `MARKSettlementModule.setVerifier`

**Description:** The `code.length > 0` check rejects EOAs and undeployed addresses, but does not verify that the contract at `verifierAddress` implements `IUTXOSettlementVerifier`. A non-conforming contract would revert at settlement call time rather than at configuration time.

**Impact:** A misconfigured verifier address would cause all settlements to revert until corrected by admin.

**Accepted because:** Adding an ERC-165 check would require the verifier to implement `supportsInterface`, which is not part of the `IUTXOSettlementVerifier` interface. The admin controls the verifier address and is expected to verify correctness before setting it.

---

## KI-4: totalSettledMint and totalSettledBurn are informational only

**Contract:** `MARKSettlementModule`

**Description:** `totalSettledMint` and `totalSettledBurn` are cumulative counters with no overflow protection beyond Solidity 0.8's default checked arithmetic (which reverts on overflow).

**Impact:** If either counter overflows `type(uint256).max`, all future settlements would revert. This requires minting or burning more than 2^256 - 1 tokens, which is practically impossible given token supply constraints.

**Accepted because:** The overflow condition is unreachable in practice. The counters are informational — they do not affect settlement logic.

---

## KI-5: Bridge daily cap uses block.timestamp epoch

**Contract:** `MARKBridgeAdapter._consumeLimits`

**Description:** The daily cap epoch is computed as `block.timestamp / 1 days`. Miners/validators can manipulate `block.timestamp` by a small amount (~15 seconds on OP Stack). This could allow a small amount of cap boundary manipulation.

**Impact:** An operator with validator cooperation could bridge slightly more than the daily cap at epoch boundaries. The manipulation window is bounded by the timestamp tolerance (~15 seconds).

**Accepted because:** The daily cap is a soft risk control, not a hard security boundary. The manipulation window is negligible relative to the cap amounts expected in production.

---

## KI-6: Transitive dependency alerts from @eth-optimism/super-cli

**Scope:** Development tooling only

**Description:** `@hono/node-server` (high), `drizzle-orm` (high), and `@stablelib/ed25519` (medium) have open Dependabot alerts. All are transitive dependencies of `@eth-optimism/super-cli`, a dev/deploy tool that never runs in production.

**Impact:** None — these packages are not part of the deployed protocol.

**Accepted because:** No upstream fix is available. The packages are scoped to development tooling only.

---

## KI-7: Two separate ZK systems sharing the MARKPool 13-signal circuit

**Scope:** `circuits/`, `src/pool/`, `src/settlement/verifier/Groth16SettlementVerifier.sol`

**Description:** The project contains two contract domains that both use the same ZK circuit (`circuits/mark/MARKPool.circom`, 13 public signals):

- **Pool system** (`MARKPool` + `MARKPoolVerifier`): uses the circuit directly for UTXO transfers. The circuit is compiled, the verifier is generated at `src/pool/verifier/MARKPoolVerifier.sol`, and witness tests pass.
- **Settlement system** (`MARKSettlementModule` + `Groth16SettlementVerifier`): the design supports the same 13-signal layout via `IGroth16Verifier` and is compatible with `MARKPoolVerifier`. However, `MARKPoolVerifier` has not yet been wired into `Groth16SettlementVerifier.setVerifierContract()` — this configuration step is required before ZK-based settlement is active. `AttestedSettlementVerifier` remains the production-safe fallback until that wiring is completed.

**Impact:** Auditors should verify that `Groth16SettlementVerifier.verifierContract` is set to a deployed `MARKPoolVerifier` instance before evaluating ZK settlement security. Until then, settlement security depends on `AttestedSettlementVerifier` (EIP-712 signatures).

**Accepted because:** `AttestedSettlementVerifier` provides meaningful security (role-gated, replay-protected, deadline-bound, module-bound). The pool circuit and verifier are consistent with each other. Settlement ZK integration is in progress.

---

## KI-8: MARKPool and PoseidonT3 contract size

**Contracts:** `src/pool/MARKPool.sol`, `src/crypto/generated/PoseidonT3.sol`

**Description:** `MARKPool` is currently 24,231 bytes — 345 bytes under the EIP-170 24,576-byte limit. `PoseidonT3` is 55,856 bytes and cannot be deployed directly. `MerkleTree` calls Poseidon via `IPoseidonT3` interface at a configurable address; `MARKPool` has no link references and is fully self-contained. The default deployment address is `0xB43122Ecb241DD50062641f089876679fd06599a` (Semaphore's PoseidonT3, same address on all EVM networks via CREATE2).

**Impact:** `MARKPool` is deployable. The 345-byte margin is tight — any significant feature addition risks exceeding the limit. CI runs pool release dry-run only (no execute smoke): Foundry's contract size check rejects the `PoseidonT3` library artifact (55,856 bytes) during broadcast. The dry-run validates the release script logic without triggering this check.

**Required before mainnet:** Monitor `MARKPool` size on every change. If the margin drops below ~100 bytes, extract logic (e.g. bridge-out, fee policy, or root management) into a separate contract.

**Accepted for now because:** The pool domain is pre-production. The settlement layer (which does not use `MARKPool`) is unaffected and can proceed to testnet independently.

---

## KI-9: Vulnerable transitive dependencies in dev tooling

**Scope:** Development tooling only — `circuits/` and `@eth-optimism/super-cli`

**Description:** 

1. **circuits/ dependencies**: `circomlibjs >= 0.1.0` depends on `ethers@5`, which pulls in `elliptic@6.6.1` (risky cryptographic primitive implementation — CVE-2025-14505, GHSA-848j-6mx2-7j84, low severity, Dependabot alert #69) and `ws@8.18.0` (uninitialized memory disclosure — CVE-2026-45736, GHSA-58qx-3vcg-4xpx, medium severity). The root pnpm workspace override can force patched transitive versions where compatible, but no non-breaking upstream fix removes the risky dependency chain entirely: the only upstream resolution (`npm audit fix --force`) downgrades `circomlibjs` to `0.0.8`, which is incompatible with Node 24 and breaks `buildPoseidon`.

2. **@eth-optimism/super-cli dependencies**: `uuid < 11.1.1` (missing buffer bounds check in v3/v5/v6 — CVE-2026-41907, GHSA-w5hq-g745-h8pq, medium severity, Dependabot alert #68) is pulled in via `@metamask/utils` packages. The vulnerable versions are `uuid@8.3.2` and `uuid@9.0.1`. No upstream fix is available from @metamask packages.

**Impact:** None — these packages are scoped to local development tooling only. They are never deployed, never handle user input, and never run in CI with untrusted data. The `elliptic` key-exposure vector requires an attacker to obtain both a faulty and a correct signature for the same inputs, which is not possible in this context. The `uuid` buffer bounds issue requires providing a malicious `buf` parameter to v3/v5/v6 functions, which does not occur in the dependency usage.

**Accepted because:** No upstream fix is available without breaking changes. The packages are scoped to:
- `circuits/`: local trusted-setup (`setup.mjs`) and witness tests (`pnpm --filter @mark/circuits test`)
- `@eth-optimism/super-cli`: local deployment tool (devDependencies)

Resolution is blocked on:
- `circomlibjs` releasing a version that drops the `ethers@5` dependency
- `@metamask/*` packages updating to `uuid@11.1.1+`

**Resolution path:** 
1. For circuits: Replace `circomlibjs` with a lightweight Poseidon library that has no `ethers` dependency, such as `poseidon-lite` or `@zk-kit/poseidon-cipher`. Both provide `buildPoseidon`-equivalent functionality without pulling in `ethers@5`. Before switching, verify the Poseidon implementation produces identical field outputs to what `MARKPool.circom` expects — run the full witness test suite (`pnpm --filter @mark/circuits test`) to confirm.
2. For uuid: Monitor @metamask package updates or add pnpm override if needed before mainnet.

Target this before mainnet promotion.

---

## KI-10: MARKPool bridge integration breaks privacy model

**Contracts:** `src/pool/MARKPool.sol` (`bridgeOut`, `bridgeIn`)

**Description:** The pool's cross-chain bridge functions emit public events containing raw output commitments, allowing observers to link transactions across chains. When a user calls `bridgeOut()` on Chain A, the `BridgeOut` event exposes `outCommitments[0]` and `outCommitments[1]`. When the bridge relay calls `bridgeIn()` on Chain B, the `BridgeIn` event exposes the same commitments. An observer monitoring both chains can match these commitments to reconstruct the cross-chain transaction graph, completely breaking the privacy model.

**Attack vector:**
```
Chain A: Alice calls bridgeOut() → BridgeOut(dstChainId, commitmentX, commitmentY)
Chain B: Relay calls bridgeIn() → BridgeIn(srcChainId, commitmentX, commitmentY)
Result: Observer links Alice's transaction on Chain A to Chain B output
```

**Impact:** Cross-chain privacy is broken. The pool provides sender anonymity only within a single chain. Cross-chain transfers leak the transaction graph.

**Accepted because:** The pool is pre-production and not yet deployed to mainnet. The bridge integration was designed for convenience but was not evaluated for privacy implications. Removing bridge integration from the pool preserves single-chain privacy while allowing RYLA cross-chain transfers via the separate `MARKBridgeAdapter` (which does not claim privacy).

**Resolution:** Remove `bridgeOut()` and `bridgeIn()` functions from `MARKPool` before mainnet. Use `MARKBridgeAdapter` for cross-chain RYLA transfers (non-private). Keep pool single-chain only.

---

## KI-11: Withdrawal timing correlation attack

**Contracts:** `src/pool/MARKPool.sol` (`transactWithWithdrawBinding`), `src/withdraw/MARKWithdrawAdapter.sol` (`withdrawWithSig`)

**Description:** The two-transaction withdrawal flow creates a timing correlation that can link nullifiers to owners. When a user calls `transactWithWithdrawBinding()`, the pool emits `NoteSpent` events revealing the nullifiers. Shortly after (typically within 1-2 blocks), the same user calls `withdrawWithSig()`, which emits `WithdrawExecuted` revealing the owner address. An observer monitoring both events can correlate them by timing to determine which nullifiers belong to which owner.

**Attack vector:**
```
Block N:   MARKPool.NoteSpent(nullifier1, nullifier2)
Block N+1: MARKWithdrawAdapter.WithdrawExecuted(owner=Alice, amount=100)
Result: Observer infers Alice owns nullifier1 and nullifier2
```

**Impact:** Withdrawal privacy is limited. An observer can link nullifiers to owners if the time gap between transactions is small (< 10 blocks). This does not break sender anonymity for non-withdrawal transactions, but it does reveal note ownership for users who withdraw.

**Accepted because:** The pool is pre-production. The two-transaction design was chosen to separate ZK proof verification (pool) from token burning (adapter), but the privacy implications were not fully evaluated. Mitigations include: (1) combining into a single atomic transaction, (2) adding a mandatory delay (10+ minutes) between transactions, or (3) using a relayer to batch withdrawals.

**Resolution:** Before mainnet, either: (A) combine `transactWithWithdrawBinding` and `withdrawWithSig` into a single atomic transaction, or (B) add a mandatory 10-minute delay in `withdrawWithSig` to decorrelate timing, or (C) document the limitation in `THREAT_MODEL.md` and accept reduced withdrawal privacy.

---

## KI-12: No recipient anonymity in withdrawals

**Contracts:** `src/pool/MARKPool.sol` (`transactWithWithdrawBinding`)

**Description:** Withdrawal recipients are public. When a user calls `transactWithWithdrawBinding()`, the pool emits `WithdrawBindingRecorded` events containing the recipient address in plaintext. This is by design — the circuit includes `withdrawRecipient` as a public input, and the withdraw binding commits to it. However, this means observers can see who is receiving withdrawn funds, reducing privacy to sender anonymity only.

**Impact:** Recipient privacy is not provided. The pool offers sender anonymity (who spent the note) but not recipient anonymity (who received the withdrawal). This is acceptable for many use cases but should be documented.

**Accepted because:** Recipient shielding would require significant circuit redesign (encrypted recipient field or stealth addresses) and is not a priority for the current use case. The pool is designed for sender anonymity, not full transaction privacy. Tornado Cash also has public recipients by design.

**Resolution:** Document in `THREAT_MODEL.md` that recipient addresses are public. If recipient privacy is needed in the future, consider: (A) stealth addresses (simpler), or (B) encrypted recipient field in circuit (complex).

---

## KI-13: Root pruning can invalidate active proofs

**Contracts:** `src/pool/MARKPool.sol` (`_pruneRoots`, `isRootUsable`)

**Description:** The pool prunes old Merkle roots after `maxRootAge` (default 30 days, max 30 days). If a user generates a proof using root R at time T, but submits it at time T + 31 days, the proof will be rejected because root R has been pruned. This could lock user funds if they are unable to generate a new proof (e.g., lost witness data, offline for extended period).

**Attack vector:**
```
Time T:     User generates proof with root R
Time T+31d: User submits proof
Result:     Root R pruned → proof rejected → funds locked
```

**Impact:** Users must submit proofs within `maxRootAge` or regenerate them with a newer root. This is a liveness risk, not a security risk. Tornado Cash and Zcash never prune roots (infinite history).

**Accepted because:** Root pruning reduces storage costs and is configurable (can be disabled by setting `maxRootAge = 0`). The 30-day window is generous for most use cases. Users who need longer validity can regenerate proofs with newer roots.

**Resolution:** Before mainnet, consider: (A) increasing `MAX_ALLOWED_ROOT_AGE` to 90 days, (B) adding a 7-day grace period in `isRootUsable()`, or (C) disabling pruning entirely (`maxRootAge = 0`) and accepting the storage cost (~32 bytes per root, ~64 MB for 1M transactions).
