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
