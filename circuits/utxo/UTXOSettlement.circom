pragma circom 2.0.0;

include "circomlib/circuits/poseidon.circom";
include "circomlib/circuits/comparators.circom";
include "circomlib/circuits/switcher.circom";
include "circomlib/circuits/bitify.circom";

template UTXO(depth, nIn, nOut) {
    // Domain separation constants.
    // Keep stable once deployed to avoid cross-version commitment/nullifier reuse.
    var DOMAIN_VERSION = 1;
    var DOMAIN_NOTE_COMMITMENT = 11;
    var DOMAIN_NULLIFIER = 12;
    // Withdrawal fee policy: 0.5% (50 bps), rounded up to avoid under-collection.
    var WITHDRAW_FEE_BPS = 50;
    var BPS_DENOMINATOR = 10000;

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
    // Keep this block in canonical verifier order:
    // [merkleRoot, chainId, dstChainId, protocolEpoch, fee, relayer, nullifier0, nullifier1, outCommitment0, outCommitment1, withdrawOwner, withdrawRecipient, withdrawAmount]
    signal input merkleRoot;
    signal input chainId;
    signal input dstChainId;
    signal input protocolEpoch;
    signal input fee;
    signal input relayer;

    // Public signals (provided as inputs and constrained)
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
    // FIX: Prevent zero nullifiers (double-spend protection)
    component nullifierNonZero[nIn];
    for (i = 0; i < nIn; i++) {
        nullifierNonZero[i] = IsZero();
        nullifierNonZero[i].in <== nullifier[i];
        nullifierNonZero[i].out === 0;
    }

    // FIX: Prevent duplicate nullifiers (all pairs)
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

    // FIX: Ensure merkle root is non-zero
    component merkleRootNonZero = IsZero();
    merkleRootNonZero.in <== merkleRoot;
    merkleRootNonZero.out === 0;

    // 3) Output commitments
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
    // FIX: Prevent duplicate output commitments (all pairs)
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
        inAmountBits[i] = Num2Bits(64); // FIX: Reduced to 64-bit for realistic token amounts
        inAmountBits[i].in <== inAmount[i];

        // FIX: Require strictly positive amounts (> 0)
        inAmountPositive[i] = GreaterThan(64);
        inAmountPositive[i].in[0] <== inAmount[i];
        inAmountPositive[i].in[1] <== 0;
        inAmountPositive[i].out === 1;
    }

    component outAmountBits[nOut];
    for (i = 0; i < nOut; i++) {
        outAmountBits[i] = Num2Bits(64); // FIX: Reduced to 64-bit
        outAmountBits[i].in <== outAmount[i];
        // Note: Output amounts can be zero (change outputs)
    }

    component feeBits = Num2Bits(64); // FIX: Reduced to 64-bit
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

    // If no withdrawal amount is consumed from the witness, owner/recipient must be zero.
    // If withdrawal amount is non-zero, owner/recipient must both be non-zero.
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

    // 6) Enforce fixed withdrawal fee policy.
    // fee = ceil(sumIn * WITHDRAW_FEE_BPS / BPS_DENOMINATOR)
    signal feeScaled;
    signal feeTarget;
    signal feeDelta;
    feeScaled <== fee * BPS_DENOMINATOR;
    feeTarget <== sumIn[nIn] * WITHDRAW_FEE_BPS;

    component feeCoversTarget = GreaterEqThan(80);
    feeCoversTarget.in[0] <== feeScaled;
    feeCoversTarget.in[1] <== feeTarget;
    feeCoversTarget.out === 1;

    feeDelta <== feeScaled - feeTarget;
    component feeDeltaBound = LessThan(14);
    feeDeltaBound.in[0] <== feeDelta;
    feeDeltaBound.in[1] <== BPS_DENOMINATOR;
    feeDeltaBound.out === 1;
}

// Public signal order:
// 1) merkleRoot
// 2) chainId
// 3) dstChainId
// 4) protocolEpoch
// 5) fee
// 6) relayer
// 7) nullifier[0]
// 8) nullifier[1]
// 9) outCommitment[0]
// 10) outCommitment[1]
// 11) withdrawOwner
// 12) withdrawRecipient
// 13) withdrawAmount
component main {public [merkleRoot, chainId, dstChainId, protocolEpoch, fee, relayer, nullifier, outCommitment, withdrawOwner, withdrawRecipient, withdrawAmount]} = UTXO(20, 2, 2);
