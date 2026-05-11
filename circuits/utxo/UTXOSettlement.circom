pragma circom 2.2.3;

include "circomlib/circuits/poseidon.circom";
include "circomlib/circuits/comparators.circom";

// UTXOSettlement proves ownership of a UTXO note for a settlement intent.
//
// Private inputs (not revealed on-chain):
//   secret          - random 32-byte blinding factor known only to the note owner
//   nonce           - random value used to derive the nullifier (prevents double-spend)
//   recipient       - address receiving tokens (mint) or spending (burn)
//   chainId         - chain the note is bound to (prevents cross-chain replay)
//   settlementModule - contract the note is bound to (prevents cross-contract replay)
//
// Public inputs (verified on-chain by Groth16SettlementVerifier):
//   nullifierHash   - Poseidon(secret, nonce): revealed to prevent double-spend
//   commitmentHash  - Poseidon(secret, amount, isMint, recipient, chainId, settlementModule)
//   amount          - token amount in base units
//   isMint          - 1 for mint, 0 for burn
//
// The circuit proves:
//   1. nullifierHash == Poseidon(secret, nonce)
//   2. commitmentHash == Poseidon(secret, amount, isMint, recipient, chainId, settlementModule)
//   3. amount > 0
//   4. isMint is binary (0 or 1)
template UTXOSettlement() {
    // Private inputs
    signal input secret;
    signal input nonce;
    signal input recipient;
    signal input chainId;
    signal input settlementModule;

    // Public inputs
    signal input nullifierHash;
    signal input commitmentHash;
    signal input amount;
    signal input isMint;

    // Constraint 1: isMint must be binary
    isMint * (isMint - 1) === 0;

    // Constraint 2: amount must be non-zero
    // IsZero returns 1 if input is 0, so we assert IsZero(amount) == 0
    component amountIsZero = IsZero();
    amountIsZero.in <== amount;
    amountIsZero.out === 0;

    // Constraint 3: nullifierHash == Poseidon(secret, nonce)
    component nullifierHasher = Poseidon(2);
    nullifierHasher.inputs[0] <== secret;
    nullifierHasher.inputs[1] <== nonce;
    nullifierHash === nullifierHasher.out;

    // Constraint 4: commitmentHash == Poseidon(secret, amount, isMint, recipient, chainId, settlementModule)
    component commitmentHasher = Poseidon(6);
    commitmentHasher.inputs[0] <== secret;
    commitmentHasher.inputs[1] <== amount;
    commitmentHasher.inputs[2] <== isMint;
    commitmentHasher.inputs[3] <== recipient;
    commitmentHasher.inputs[4] <== chainId;
    commitmentHasher.inputs[5] <== settlementModule;
    commitmentHash === commitmentHasher.out;
}

component main {public [nullifierHash, commitmentHash, amount, isMint]} = UTXOSettlement();
