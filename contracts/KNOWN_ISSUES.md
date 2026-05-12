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

## KI-7: Production UTXO pool with 13-signal circuit integrated

**Contracts:** `Pool`, `MARKSettlementModule`, `Groth16SettlementVerifier`, `utxo.circom`

**Description:** The pool (`Pool.sol`) now uses a production-ready 13-signal UTXO circuit (`utxo.circom`) with Merkle tree privacy, in-circuit fee enforcement (0.5%), and cross-chain support. The circuit includes: merkleRoot, chainId, dstChainId, protocolEpoch, fee, relayer, nullifier[2], outCommitment[2], withdrawOwner, withdrawRecipient, withdrawAmount. The settlement module (`MARKSettlementModule`) uses `Groth16SettlementVerifier` which expects the same 13-signal layout. `AttestedSettlementVerifier` remains available as a signature-based fallback.

**Impact:** The pool is now production-ready with full ZK privacy via Merkle tree membership proofs. The circuit enforces balance conservation, prevents double-spends, and validates withdrawal fees in-circuit. The settlement module can use either the Groth16 verifier (with ZK proofs) or the attested verifier (with signatures).

**Status:** Circuit artifacts exist in `/Users/iap/contracts/circuits/artifacts/prod/` and can be regenerated from `utxo.circom`. The verifier contract needs to be generated from the circuit and integrated with `Groth16SettlementVerifier`.

---

## KI-7: Two separate ZK systems with different circuit designs

**Scope:** `circuits/`, `src/pool/`, `src/settlement/verifier/Groth16SettlementVerifier.sol`

**Description:** The project contains two distinct ZK systems that use different circuit designs and signal layouts:

- **Pool system** (`Pool.sol` + `UTXOVerifier.sol`): uses a 13-signal circuit with Merkle root membership, epochs, relayers, and cross-chain support. The circuit is compiled and the verifier is deployed.
- **Settlement system** (`MARKSettlementModule` + `Groth16SettlementVerifier`): expects the same 13-signal circuit via `IGroth16Verifier`. `AttestedSettlementVerifier` bridges the gap until the settlement-specific ZK integration is wired up.

The `circuits/utxo/UTXOSettlement.circom` file is an earlier 4-signal circuit (nullifierHash, commitmentHash, amount, isMint) that predates the current pool design. It is not used by `Pool.sol` or `Groth16SettlementVerifier`. It is retained for reference and its witness tests remain valid.

**Impact:** Auditors should not assume the circom circuit and the deployed verifier are aligned — they use different signal layouts by design.

**Accepted because:** The pool circuit and verifier are consistent with each other. The settlement ZK integration is in progress. `AttestedSettlementVerifier` provides production-safe coverage in the interim.
