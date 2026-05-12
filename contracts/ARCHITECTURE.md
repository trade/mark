# Contracts Architecture

## Domains

- `src/token`: token primitives (`RYLA`).
- `src/bridge`: bridge adapter domain.
- `src/settlement`: settlement module + verifier domain.
- `src/pool`: ZK UTXO pool domain (`MARKPool`, `RYLACreditLedger`, support libraries).
- `src/withdraw`: withdrawal adapter domain (`MARKWithdrawAdapter`).
- `src/crypto`: shared cryptographic primitives (Merkle tree, Poseidon).
- `src/interfaces`: shared interfaces used across domains.
- `src/errors`: shared error types.

## Dependency Rules

- `src/bridge/**` must not import from `src/settlement/**`.
- `src/settlement/**` must not import from `src/bridge/**`.
- `src/pool/**` must not import from `src/settlement/**` or `src/bridge/**`.
- `src/withdraw/**` must not import from `src/settlement/**` or `src/bridge/**`.
- Cross-domain sharing should be done through narrow interfaces and shared types only.
- `src/token/**` is an allowed dependency for all domains.
- `src/crypto/**` and `src/interfaces/**` are allowed dependencies for all domains.

## Pool Withdrawal Flow (burn-to-claim model)

Notes enter the pool via `transact()` (ZK proof) or `bridgeIn()` (restricted). The pool
is a nullifier registry — it does not hold tokens.

To withdraw RYLA, a note owner:

1. Calls `MARKPool.transactWithWithdrawBinding()` — verifies ZK proof, marks nullifiers
   spent, records a withdraw binding (hash of owner/recipient/amount). No token transfer.
2. Calls `MARKWithdrawAdapter.withdrawWithSig()` — verifies the binding matches, verifies
   EIP-712 signatures, calls `RYLACreditLedger.debit(owner, amount)` which burns RYLA.

The owner must hold RYLA equal to the withdrawal amount and approve `RYLACreditLedger`
before step 2. The ZK proof proves note ownership; the RYLA burn redeems it.

## Enforcement

- CI runs `make architecture-guard`.
- Guard implementation: `script/ci/architecture-guard.sh`.
- CI runs `make layering-guard`.
- Guard implementation: `script/ci/layering-guard.sh`.
- Any forbidden cross-domain import causes CI failure.
