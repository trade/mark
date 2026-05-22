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

## KI-6: Transitive dependency alerts from @eth-optimism/super-cli and wagmi

**Scope:** Development tooling and frontend dev dashboard only

**Description:** Several transitive dependency vulnerabilities exist with no upstream fix available:

- `drizzle-orm@0.38.4` (high — GHSA-gpj5-g38j-94v9): transitive dep of `@eth-optimism/super-cli@0.0.13`. Patched in `>=0.45.2` but super-cli still pins `^0.38.1`. No upstream fix available.
- `uuid@9.0.1` (moderate — GHSA-w5hq-g745-h8pq): transitive dep of `wagmi` → `@wagmi/connectors` → `@metamask/utils@9.3.0`. Missing buffer bounds check in v3/v5/v6. Patched in `>=11.1.1`. `@metamask/utils` pins `uuid@^9.0.0` and has not released a version using `>=11.1.1`. No upstream fix available.
- `ws@8.18.x` (moderate — GHSA-58qx-3vcg-4xpx): reported by audit but `ws@8.20.1` (patched) is already installed in the lockfile — this is a **false positive** in the audit output.
- `@hono/node-server@1.19.14`: transitive dep of `@eth-optimism/super-cli`. The installed version `1.19.14` is not flagged by `pnpm audit` — earlier GHSAs (GHSA-wc8c-qw6v-h7f6, patched in `>=1.19.10`) are already resolved by the installed version.

**Impact:** None — `@eth-optimism/super-cli` is a dev/deploy tool that never runs in production. The frontend (`src/`) is a read-only dev dashboard with no wallet interaction or user funds per `SECURITY.md`. The `uuid` buffer bounds check issue is not exploitable in a read-only context.

**Accepted because:** No upstream fix is available without breaking changes. All affected packages are scoped to development tooling or the non-production frontend dashboard.

**Resolution path:** Blocked on upstream — `@eth-optimism/super-cli` updating `drizzle-orm`, and `wagmi`/`@metamask/sdk` updating `uuid`. Monitor Dependabot alerts for when fixes become available.

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

## KI-9: Vulnerable transitive dependencies in circuits/ dev tooling

**Scope:** `circuits/` — local trusted-setup and witness-test tooling only

**Description:** `circomlibjs >= 0.1.0` depends on `ethers@5`, which pulls in `elliptic <= 6.6.1` (faulty ECDSA signatures, potential key exposure — GHSA-848j-6mx2-7j84) and `ws 8.0.0–8.20.0` (uninitialized memory disclosure — GHSA-58qx-3vcg-4xpx). No non-breaking fix is available: the only upstream resolution (`npm audit fix --force`) downgrades `circomlibjs` to `0.0.8`, which is incompatible with Node 22/24 and breaks `buildPoseidon`.

**Impact:** None — `circuits/` is local developer tooling. It is never deployed, never handles user input, and never runs in CI with untrusted data. The `elliptic` key-exposure vector requires an attacker to obtain both a faulty and a correct signature for the same inputs, which is not possible in this context.

**Accepted because:** No upstream fix is available without a breaking change. The packages are scoped to local trusted-setup (`setup.mjs`) and witness tests (`npm test`). Resolution is blocked on `circomlibjs` releasing a version that drops the `ethers@5` dependency.

**Resolution path:** Replace `circomlibjs` with a lightweight Poseidon library that has no `ethers` dependency, such as `poseidon-lite` or `@zk-kit/poseidon-cipher`. Both provide `buildPoseidon`-equivalent functionality without pulling in `ethers@5`. Before switching, verify the Poseidon implementation produces identical field outputs to what `MARKPool.circom` expects — run the full witness test suite (`npm test` in `circuits/`) to confirm. Target this before mainnet promotion.
