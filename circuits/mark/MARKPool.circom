pragma circom 2.0.0;

include "circomlib/circuits/poseidon.circom";
include "circomlib/circuits/comparators.circom";
include "circomlib/circuits/switcher.circom";
include "circomlib/circuits/bitify.circom";

template MARKPool(depth, nIn, nOut) {
    // Domain separation constants — PERMANENT. Never change after first deployment.
    // These values are protocol-specific to MARK and must remain stable across upgrades
    // to prevent cross-version commitment and nullifier reuse.
    //   DOMAIN_VERSION:         1  — protocol version tag
    //   DOMAIN_NOTE_COMMITMENT: 11 — note commitment hash domain
    //   DOMAIN_NULLIFIER:       12 — nullifier hash domain
    var DOMAIN_VERSION = 1;
    var DOMAIN_NOTE_COMMITMENT = 11;
    var DOMAIN_NULLIFIER = 12;

    // Private inputs (notes to spend)
    signal input inAmount[nIn];
    signal input inSecret[nIn];
    signal input inBlinding[nIn];
    signal input inPathElements[nIn][depth];
    signal input inPathIndices[nIn][depth];

    // Private outputs (new notes)
    signal input outAmount[nOut];
    signal input outSecret[nOut];
    signal input outBlinding[nOut];

    // Public inputs.
    // IMPORTANT: snarkjs publicSignals ordering follows signal declaration order.
    // Canonical verifier order (13 signals):
    // [merkleRoot, chainId, dstChainId, protocolEpoch, fee, relayer,
    //  nullifier[0], nullifier[1], outCommitment[0], outCommitment[1],
    //  withdrawOwner, withdrawRecipient, withdrawAmount]
    signal input merkleRoot;
    signal input chainId;
    signal input dstChainId;
    signal input protocolEpoch;
    signal input fee;
    signal input relayer;
    signal input nullifier[nIn];
    signal input outCommitment[nOut];
    signal input withdrawOwner;
    signal input withdrawRecipient;
    signal input withdrawAmount;

    signal computedNullifier[nIn];
    signal computedOutCommitment[nOut];

    // 1) Input commitments + nullifiers
    component inCommitment[nIn];
    component inNullifier[nIn];
    var i;
    for (i = 0; i < nIn; i++) {
        inCommitment[i] = Poseidon(4);
        inCommitment[i].inputs[0] <== DOMAIN_VERSION * 100 + DOMAIN_NOTE_COMMITMENT;
        inCommitment[i].inputs[1] <== inAmount[i];
        inCommitment[i].inputs[2] <== inSecret[i];
        inCommitment[i].inputs[3] <== inBlinding[i];

        inNullifier[i] = Poseidon(4);
        inNullifier[i].inputs[0] <== DOMAIN_VERSION * 100 + DOMAIN_NULLIFIER;
        inNullifier[i].inputs[1] <== inSecret[i];
        inNullifier[i].inputs[2] <== inCommitment[i].out;
        inNullifier[i].inputs[3] <== chainId;
        computedNullifier[i] <== inNullifier[i].out;
        computedNullifier[i] === nullifier[i];
    }

    // Prevent zero nullifiers (double-spend protection)
    component nullifierNonZero[nIn];
    for (i = 0; i < nIn; i++) {
        nullifierNonZero[i] = IsZero();
        nullifierNonZero[i].in <== nullifier[i];
        nullifierNonZero[i].out === 0;
    }

    // Prevent duplicate nullifiers within the same proof
    component sameNullifier[nIn * (nIn - 1) / 2];
    var pairIndex = 0;
    for (i = 0; i < nIn; i++) {
        for (var j = i + 1; j < nIn; j++) {
            sameNullifier[pairIndex] = IsEqual();
            sameNullifier[pairIndex].in[0] <== nullifier[i];
            sameNullifier[pairIndex].in[1] <== nullifier[j];
            sameNullifier[pairIndex].out === 0;
            pairIndex++;
        }
    }

    // 2) Merkle inclusion for each input
    signal cur[nIn][depth + 1];
    component sw[nIn][depth];
    component h[nIn][depth];
    var j;
    for (i = 0; i < nIn; i++) {
        cur[i][0] <== inCommitment[i].out;
        for (j = 0; j < depth; j++) {
            inPathIndices[i][j] * (inPathIndices[i][j] - 1) === 0;
            sw[i][j] = Switcher();
            sw[i][j].sel <== inPathIndices[i][j];
            sw[i][j].L <== cur[i][j];
            sw[i][j].R <== inPathElements[i][j];
            h[i][j] = Poseidon(2);
            h[i][j].inputs[0] <== sw[i][j].outL;
            h[i][j].inputs[1] <== sw[i][j].outR;
            cur[i][j + 1] <== h[i][j].out;
        }
        cur[i][depth] === merkleRoot;
    }

    // Ensure merkle root is non-zero
    component merkleRootNonZero = IsZero();
    merkleRootNonZero.in <== merkleRoot;
    merkleRootNonZero.out === 0;

    // 3) Output commitments — bound to dstChainId to prevent cross-chain replay
    component outCommit[nOut];
    for (i = 0; i < nOut; i++) {
        outCommit[i] = Poseidon(4);
        outCommit[i].inputs[0] <== DOMAIN_VERSION * 100 + DOMAIN_NOTE_COMMITMENT;
        outCommit[i].inputs[1] <== outAmount[i];
        outCommit[i].inputs[2] <== outSecret[i];
        outCommit[i].inputs[3] <== outBlinding[i] + dstChainId;
        computedOutCommitment[i] <== outCommit[i].out;
        computedOutCommitment[i] === outCommitment[i];
    }

    // Prevent duplicate output commitments within the same proof
    component sameOutCommitment[nOut * (nOut - 1) / 2];
    pairIndex = 0;
    for (i = 0; i < nOut; i++) {
        for (j = i + 1; j < nOut; j++) {
            sameOutCommitment[pairIndex] = IsEqual();
            sameOutCommitment[pairIndex].in[0] <== outCommitment[i];
            sameOutCommitment[pairIndex].in[1] <== outCommitment[j];
            sameOutCommitment[pairIndex].out === 0;
            pairIndex++;
        }
    }

    // 4) Range constraints
    component inAmountBits[nIn];
    component inAmountPositive[nIn];
    for (i = 0; i < nIn; i++) {
        inAmountBits[i] = Num2Bits(64);
        inAmountBits[i].in <== inAmount[i];

        inAmountPositive[i] = GreaterThan(64);
        inAmountPositive[i].in[0] <== inAmount[i];
        inAmountPositive[i].in[1] <== 0;
        inAmountPositive[i].out === 1;
    }

    component outAmountBits[nOut];
    for (i = 0; i < nOut; i++) {
        outAmountBits[i] = Num2Bits(64);
        outAmountBits[i].in <== outAmount[i];
        // Output amounts may be zero (change outputs)
    }

    component feeBits = Num2Bits(64);
    feeBits.in <== fee;

    component relayerBits = Num2Bits(160);
    relayerBits.in <== relayer;

    component withdrawRecipientBits = Num2Bits(160);
    withdrawRecipientBits.in <== withdrawRecipient;

    component withdrawOwnerBits = Num2Bits(160);
    withdrawOwnerBits.in <== withdrawOwner;

    component withdrawAmountBits = Num2Bits(64);
    withdrawAmountBits.in <== withdrawAmount;

    component dstChainBits = Num2Bits(64);
    dstChainBits.in <== dstChainId;

    component protocolEpochBits = Num2Bits(32);
    protocolEpochBits.in <== protocolEpoch;

    // 5) Balance equation: sum(inputs) = sum(outputs) + fee + withdrawAmount
    // Fee rate policy is enforced at the contract level (Pool.feeBurnBps), not here.
    signal sumIn[nIn + 1];
    signal sumOut[nOut + 1];
    sumIn[0] <== 0;
    sumOut[0] <== 0;
    for (i = 0; i < nIn; i++) {
        sumIn[i + 1] <== sumIn[i] + inAmount[i];
    }
    for (i = 0; i < nOut; i++) {
        sumOut[i + 1] <== sumOut[i] + outAmount[i];
    }
    sumIn[nIn] === sumOut[nOut] + fee + withdrawAmount;

    // Withdraw binding: if withdrawAmount is zero, owner and recipient must be zero.
    // If withdrawAmount is non-zero, owner and recipient must both be non-zero.
    component withdrawAmountIsZero = IsZero();
    withdrawAmountIsZero.in <== withdrawAmount;
    withdrawOwner * withdrawAmountIsZero.out === 0;
    withdrawRecipient * withdrawAmountIsZero.out === 0;

    component withdrawOwnerIsZero = IsZero();
    withdrawOwnerIsZero.in <== withdrawOwner;
    withdrawOwnerIsZero.out * (1 - withdrawAmountIsZero.out) === 0;

    component withdrawRecipientIsZero = IsZero();
    withdrawRecipientIsZero.in <== withdrawRecipient;
    withdrawRecipientIsZero.out * (1 - withdrawAmountIsZero.out) === 0;
}

// Public signal order (13 signals):
// [0]  merkleRoot
// [1]  chainId
// [2]  dstChainId
// [3]  protocolEpoch
// [4]  fee
// [5]  relayer
// [6]  nullifier[0]
// [7]  nullifier[1]
// [8]  outCommitment[0]
// [9]  outCommitment[1]
// [10] withdrawOwner
// [11] withdrawRecipient
// [12] withdrawAmount
component main {public [merkleRoot, chainId, dstChainId, protocolEpoch, fee, relayer, nullifier, outCommitment, withdrawOwner, withdrawRecipient, withdrawAmount]} = MARKPool(20, 2, 2);
