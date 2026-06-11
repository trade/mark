# MARK Protocol — Threat Model

This document is intended for security auditors. It describes the trust assumptions, threat boundaries, and worst-case impact of each privileged role being compromised.

## System Overview

MARK is a settlement, bridging, and ZK UTXO privacy protocol on the Optimism Superchain. It consists of two independent stacks:

**Settlement stack** (production-bound):

- **RYLA** — ERC-20 credit token with role-gated mint/burn
- **MARKSettlementModule** — operator-gated settlement boundary; holds MINTER_ROLE and BURNER_ROLE on RYLA
- **MARKBridgeAdapter** — operator-gated bridge adapter; routes RYLA cross-chain via SuperchainTokenBridge
- **AttestedSettlementVerifier** — EIP-712 signature verifier; validates settlement attestations before mint/burn
- **Groth16SettlementVerifier** — Groth16 proof verifier adapter; validates 13-signal ZK proofs for settlement

**Pool stack** (pre-production):

- **MARKPool** — ZK UTXO pool; nullifier registry with Merkle commitment tree; does not hold tokens
- **RYLACreditLedger** — ICreditLedger adapter; mints RYLA for relayer fees (via pool) and burns RYLA on withdrawal (via adapter)
- **MARKWithdrawAdapter** — EIP-191 signature-based withdrawal adapter; verifies withdraw bindings and sends ETH to recipients

## Trust Boundaries

```
External actors
  └── Operator (hot key)
        ├── calls settleMint / settleBurn on MARKSettlementModule
        └── calls bridgeTo on MARKBridgeAdapter

  └── Attester (hot key)
        └── signs EIP-712 attestations consumed by AttestedSettlementVerifier

  └── Default Admin (hardware wallet)
        ├── grants/revokes OPERATOR_ROLE on bridge and settlement
        ├── grants/revokes ATTESTER_ROLE on verifier
        ├── grants/revokes MINTER_ROLE and BURNER_ROLE on RYLA
        ├── configures verifier, bridge limits, destination allowlist
        └── activates production mode (irreversible)

External contracts
  └── SuperchainTokenBridge (predeploy 0x4200...0028)
        └── called by MARKBridgeAdapter.bridgeTo; trusted as a system predeploy

Pool stack trust boundaries:

```

External actors
└── Pool Authority (AccessManager admin)
├── grants/revokes restricted selectors on MARKPool and MARKWithdrawAdapter
├── sets verifier on MARKPool (one-time per proof type)
└── sets asset ledger on MARKPool (one-time)

└── Note owner (end user)
├── submits ZK proofs to MARKPool.transact / transactWithWithdrawBinding
└── calls MARKWithdrawAdapter.withdrawWithSig with EIP-191 signatures

└── Relayer (permissionless)
└── calls MARKPool.transact on behalf of note owners; receives fee credit via RYLACreditLedger

└── Intent signer (hot key, configured on MARKWithdrawAdapter)
└── co-signs withdraw intents; prevents unauthorized withdrawals without owner signature

External contracts
└── RYLACreditLedger
└── called by MARKPool.credit (relayer fees) and MARKWithdrawAdapter.debit (withdrawals)
└── holds MINTER_ROLE and BURNER_ROLE on RYLA

```

## Role Compromise Impact

### Default Admin key compromised

Worst case: complete protocol takeover.

- Attacker can grant OPERATOR_ROLE to any address and submit arbitrary settlements
- Attacker can grant MINTER_ROLE directly to any address and mint unbounded RYLA
- Attacker can disable proof validation (if not in production mode)
- Attacker can change the verifier to a malicious contract

Mitigations:
- 1-day delay on admin transfers (`AccessControlDefaultAdminRules`) — admin key rotation takes at least 24 hours
- Production mode lock prevents disabling proof validation once activated
- Operator role revocation is immediate — existing operators can be revoked before attacker acts

### Operator key compromised

Worst case: unauthorized settlements and bridge transactions within configured limits.

- Attacker can call `settleMint` to mint RYLA to arbitrary addresses (if proof validation is disabled)
- Attacker can call `settleBurn` to burn RYLA from accounts that have approved the module
- Attacker can call `bridgeTo` to bridge RYLA cross-chain within daily cap and per-tx limits
- Attacker cannot change configuration, rotate roles, or disable proof validation

Mitigations:
- Proof validation (when enabled) requires a valid attester signature — operator alone cannot mint without attester cooperation
- Bridge rate limits (maxPerTx, dailyCap) bound the damage window
- Operator role can be revoked immediately by admin

### Attester key compromised

Worst case: fraudulent settlement attestations.

- Attacker can sign attestations authorizing arbitrary mint/burn operations
- Attacker cannot submit settlements directly (requires OPERATOR_ROLE)
- Attacker cannot change configuration

Mitigations:
- Requires operator cooperation to execute — attester alone cannot settle
- Attester role can be revoked immediately by admin
- Attestations are bound to a specific verifier address, settlement module, and deadline — cannot be replayed across contracts or after expiry

### SuperchainTokenBridge compromised

Worst case: cross-chain token accounting failure.

- A compromised bridge predeploy could fail to burn tokens on the source chain or fail to mint on the destination
- `MARKBridgeAdapter` handles bridge failure via try/catch — clears approval and reverts `BridgeFailed()` if `sendERC20` fails
- The bridge is a system predeploy — its security is outside the scope of this protocol

### Pool Authority (AccessManager admin) compromised

Worst case: pool configuration takeover.

- Attacker can replace the verifier with a malicious contract that accepts any proof
- Attacker can set the asset ledger to a malicious contract that mints unbounded RYLA
- Attacker can pause/unpause the pool and withdrawal adapter
- Attacker cannot replay already-consumed nullifiers (stored on-chain, immutable)
- Attacker cannot forge withdraw bindings for past transactions (bound to nullifier hashes)

Mitigations:
- `setVerifier` and `setAssetLedger` are restricted to AccessManager — requires the authority contract to be compromised
- Nullifier registry is append-only — consumed nullifiers cannot be un-consumed
- Withdraw bindings are cryptographically bound to owner/recipient/amount at proof time

### Intent signer key compromised

Worst case: unauthorized withdrawals for notes whose nullifiers are already consumed.

- Attacker can co-sign withdraw intents for any pending withdraw binding
- Attacker cannot create new withdraw bindings (requires a valid ZK proof submitted to MARKPool)
- Attacker cannot withdraw without the note owner's EIP-191 signature (dual-signature requirement)

Mitigations:
- Dual-signature requirement: both owner signature and intent signer signature required
- Intent signer can be rotated via AccessManager
- Withdraw bindings are one-time use (nullifiers marked claimed after withdrawal)

## External Dependencies

| Dependency | Version | Trust level | Notes |
|---|---|---|---|
| OpenZeppelin Contracts | via createx lib | High | AccessControl, SafeERC20, EIP712, ECDSA, ReentrancyGuard |
| interop-lib | submodule | High | SuperchainERC20, ISuperchainTokenBridge, PredeployAddresses |
| SuperchainTokenBridge | predeploy 0x4200...0028 | System | Trusted as OP Stack system contract |

## What Is Explicitly Out of Scope

- **AttestedSettlementVerifier is a production-safe baseline** — it is an ECDSA-based verifier intended as a bridge step before full ZK verifier integration. Auditors should evaluate it as a standalone ECDSA verifier.
- **MARKPool ZK circuit** — the Groth16 circuit (`circuits/mark/MARKPool.circom`) has not undergone a formal trusted setup ceremony. The current setup used a single contributor. A multi-party ceremony is required before mainnet.
- **Off-chain operator infrastructure** — the protocol does not specify how operators construct or submit settlement intents. That is provider-layer responsibility.
- **Frontend** — the frontend is a read-only info page with no wallet interaction or user funds.
- **Deployment scripts** — `contracts/script/` contains operational tooling, not protocol logic.

## Invariants the Protocol Relies On

1. Only `MARKSettlementModule` holds `MINTER_ROLE` and `BURNER_ROLE` on RYLA in production.
2. `consumedIntents[intentId]` is set to `true` before the external call to `verifier_.verifySettlement()`, following the CEI pattern. This prevents replay even if a future non-view verifier makes a reentrant call.
3. `bridgedInDailyCapEpoch` never exceeds `dailyCap` within a single epoch.
4. `productionMode` is irreversible once set — proof validation cannot be disabled.
5. The module's RYLA balance returns to its pre-settlement value after each `settleBurn` operation. The module does not accumulate tokens across settlements. Note: tokens sent directly to the module address outside of settlement flows are not covered by this invariant.
6. `nullifierUsed[nullifier]` is set to `true` before any state changes in `MARKPool.transact*` — nullifiers cannot be replayed even under reentrancy.
7. `nullifierWithdrawBinding` is written only after nullifiers are consumed — a withdraw binding cannot be created without a valid ZK proof.
8. `RYLACreditLedger.debit` requires `from` to have approved the ledger for at least `amount` RYLA — the burn cannot proceed without explicit token approval from the note owner.

## MARKPool Privacy Model

### Privacy Guarantees

**What is private:**
- **Sender anonymity**: The ZK proof proves note ownership without revealing which address owns the note. Observers cannot determine who spent a note by examining the proof or on-chain data.
- **Transaction graph privacy**: The Merkle tree hides which specific notes were spent. Observers see nullifiers but cannot link them to specific commitments without the secret.
- **Note ownership**: The secret key never appears on-chain. Only the note owner can generate a valid proof.

**What is NOT private:**
- **Withdrawal amounts**: Public in `WithdrawBindingRecorded` events and `withdrawAmount` public signal.
- **Withdrawal recipients**: Public in `WithdrawBindingRecorded` events and `withdrawRecipient` public signal.
- **Withdrawal timing**: Two-transaction flow (transactWithWithdrawBinding → withdrawWithSig) creates timing correlation. Observers can link nullifiers to owners if transactions occur within a short time window (< 10 blocks).
- **Cross-chain destinations**: `dstChainId` is a public signal. Output commitments are bound to destination chain, revealing where notes will be spent.
- **Bridge transaction graph**: `BridgeOut` and `BridgeIn` events expose raw commitments, allowing observers to link transactions across chains (see KI-10).

### Privacy Scope

**MARKPool provides sender anonymity only.** It does not provide:
- Recipient anonymity (by design — withdraw recipients are public)
- Amount privacy (by design — withdraw amounts are public)
- Timing privacy (limitation — two-transaction withdrawal flow)
- Cross-chain privacy (limitation — bridge integration breaks privacy)

**Comparison to other privacy protocols:**
- **Tornado Cash**: Sender + recipient anonymity, fixed denominations (amount privacy)
- **Zcash**: Full privacy (sender + recipient + amount via shielded addresses)
- **MARK**: Sender anonymity only

### Privacy Limitations

1. **Withdrawal timing attack** (KI-11): Observers can correlate `NoteSpent` and `WithdrawExecuted` events by timing to link nullifiers to owners.
2. **No recipient shielding** (KI-12): Withdrawal recipients are public. Observers know who receives withdrawn funds.
3. **Bridge privacy leak** (KI-10): Cross-chain transfers expose commitments in public events, breaking transaction graph privacy.

### Recommended Use Cases

MARKPool is suitable for:
- **Private transfers within a single chain** where sender anonymity is sufficient
- **Non-withdrawal transactions** where timing correlation is not a concern
- **Use cases where recipient and amount privacy are not required**

MARKPool is NOT suitable for:
- **Cross-chain private transfers** (bridge integration breaks privacy)
- **Withdrawals requiring full anonymity** (timing attack reveals ownership)
- **Use cases requiring recipient privacy** (recipients are public)

### Mitigation Strategies

For users requiring stronger privacy:
1. **Avoid withdrawals** — keep funds in the pool and transact within the pool
2. **Use relayers** — submit withdrawal intents through a relayer to batch transactions
3. **Add delays** — wait 10+ minutes between transactWithWithdrawBinding and withdrawWithSig
4. **Avoid cross-chain** — do not use bridgeOut/bridgeIn (will be removed before mainnet)

For protocol improvements (future):
1. **Combine withdrawal transactions** — merge transactWithWithdrawBinding + withdrawWithSig into single atomic transaction
2. **Add recipient shielding** — implement stealth addresses or encrypted recipient field
3. **Remove bridge integration** — keep pool single-chain only (planned before mainnet)
4. **Migrate to Halo 2** — eliminate trusted setup requirement
```
