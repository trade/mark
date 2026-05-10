# MARK Protocol — Threat Model

This document is intended for security auditors. It describes the trust assumptions, threat boundaries, and worst-case impact of each privileged role being compromised.

## System Overview

MARK is a settlement and bridging protocol on the Optimism Superchain. It consists of four contracts:

- **RYLA** — ERC-20 credit token with role-gated mint/burn
- **MARKSettlementModule** — operator-gated settlement boundary; holds MINTER_ROLE and BURNER_ROLE on RYLA
- **MARKBridgeAdapter** — operator-gated bridge adapter; routes RYLA cross-chain via SuperchainTokenBridge
- **AttestedSettlementVerifier** — EIP-712 signature verifier; validates settlement attestations before mint/burn

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

## External Dependencies

| Dependency | Version | Trust level | Notes |
|---|---|---|---|
| OpenZeppelin Contracts | via createx lib | High | AccessControl, SafeERC20, EIP712, ECDSA, ReentrancyGuard |
| interop-lib | submodule | High | SuperchainERC20, ISuperchainTokenBridge, PredeployAddresses |
| SuperchainTokenBridge | predeploy 0x4200...0028 | System | Trusted as OP Stack system contract |

## What Is Explicitly Out of Scope

- **AttestedSettlementVerifier is a placeholder** — it is a production-safe bridge step before ZK verifier integration. The ZK proof system has not been designed yet. Auditors should evaluate the attested verifier as a standalone ECDSA-based verifier, not as a ZK system.
- **Off-chain operator infrastructure** — the protocol does not specify how operators construct or submit settlement intents. That is provider-layer responsibility.
- **Frontend** — the frontend is a read-only info page with no wallet interaction or user funds.
- **Deployment scripts** — `contracts/script/` contains operational tooling, not protocol logic.

## Invariants the Protocol Relies On

1. Only `MARKSettlementModule` holds `MINTER_ROLE` and `BURNER_ROLE` on RYLA in production.
2. `consumedIntents[intentId]` is set to `true` before any external call in `_consumeAndValidate`.
3. `bridgedInDailyCapEpoch` never exceeds `dailyCap` within a single epoch.
4. `productionMode` is irreversible once set — proof validation cannot be disabled.
5. The module's RYLA balance is always zero after any settlement operation.
