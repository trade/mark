pragma circom 2.2.3;

include "circomlib/circuits/poseidon.circom";
include "circomlib/circuits/comparators.circom";
include "circomlib/circuits/bitify.circom";

// UTXOSettlement proves ownership of a UTXO note.
//
// Private inputs:
//   secret           - random blinding factor known only to the note owner
//   nonce            - entropy for nullifier derivation
//   recipient        - address receiving tokens (160-bit Ethereum address)
//   chainId          - chain the note is bound to (64-bit)
//   settlementModule - contract the note is bound to (160-bit Ethereum address)
//
// Public inputs:
//   nullifierHash    - Poseidon(secret, nonce): revealed to prevent double-spend
//   commitmentHash   - Poseidon(secret, amount, isMint, recipient, chainId, settlementModule)
//   amount           - token amount in base units (64-bit)
//   isMint           - 1 for mint/withdraw, 0 for burn
//
// Constraints:
//   1. isMint is binary (0 or 1)
//   2. amount > 0 and fits in 64 bits
//   3. recipient fits in 160 bits
//   4. chainId fits in 64 bits
//   5. settlementModule fits in 160 bits
//   6. nullifierHash == Poseidon(secret, nonce)
//   7. commitmentHash == Poseidon(secret, amount, isMint, recipient, chainId, settlementModule)
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

    // Constraint 2: amount must be non-zero and fit in 64 bits
    component amountBits = Num2Bits(64);
    amountBits.in <== amount;
    component amountIsZero = IsZero();
    amountIsZero.in <== amount;
    amountIsZero.out === 0;

    // Constraint 3: recipient must fit in 160 bits (Ethereum address)
    component recipientBits = Num2Bits(160);
    recipientBits.in <== recipient;

    // Constraint 4: chainId must fit in 64 bits
    component chainIdBits = Num2Bits(64);
    chainIdBits.in <== chainId;

    // Constraint 5: settlementModule must fit in 160 bits (Ethereum address)
    component moduleBits = Num2Bits(160);
    moduleBits.in <== settlementModule;

    // Constraint 6: nullifierHash == Poseidon(secret, nonce)
    component nullifierHasher = Poseidon(2);
    nullifierHasher.inputs[0] <== secret;
    nullifierHasher.inputs[1] <== nonce;
    nullifierHash === nullifierHasher.out;

    // Constraint 7: commitmentHash == Poseidon(secret, amount, isMint, recipient, chainId, settlementModule)
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
