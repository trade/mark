// Witness tests for MARKPool circuit.
// Run: node test/MARKPool.test.mjs

import { buildPoseidon } from "circomlibjs";
import { readFileSync } from "fs";
import { createRequire } from "module";
import { fileURLToPath } from "url";
import path from "path";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const require = createRequire(import.meta.url);

const poseidon = await buildPoseidon();
const F = poseidon.F;

function poseidonHash(...inputs) {
  return F.toObject(poseidon(inputs.map(BigInt)));
}

// Replicate MerkleTree.sol zero-value tree (depth=20, zero leaf = 0)
function buildZeroTree(depth) {
  const zeros = [0n];
  for (let i = 1; i <= depth; i++) {
    zeros.push(poseidonHash(zeros[i - 1], zeros[i - 1]));
  }
  return zeros;
}

const wasmPath = path.join(__dirname, "../build/MARKPool_js/MARKPool.wasm");
const WitnessCalculator = require(
  path.join(__dirname, "../build/MARKPool_js/witness_calculator.js")
);
const wasm = readFileSync(wasmPath);
const wc = await WitnessCalculator(wasm);

async function expectPass(label, input) {
  try {
    await wc.calculateWitness(input, false);
    console.log(`  PASS: ${label}`);
  } catch (e) {
    console.error(`  FAIL: ${label} — ${e.message}`);
    process.exit(1);
  }
}

async function expectFail(label, input) {
  try {
    await wc.calculateWitness(input, false);
    console.error(`  FAIL: ${label} — expected constraint failure`);
    process.exit(1);
  } catch (e) {
    // Only treat constraint/assertion failures as expected. Rethrow anything else
    // (malformed input, missing signal, internal error) so regressions surface.
    const msg = (e?.message ?? "").toLowerCase();
    if (
      msg.includes("assert failed") ||
      msg.includes("constraint") ||
      msg.includes("error in template")
    ) {
      console.log(`  PASS: ${label}`);
    } else {
      throw e;
    }
  }
}

// Domain constants (must match MARKPool.circom)
const DOMAIN_VERSION = 1n;
const DOMAIN_NOTE_COMMITMENT = 11n;
const DOMAIN_NULLIFIER = 12n;
const DOMAIN_DST_CHAIN = 13n;
const DOMAIN_COMMITMENT = DOMAIN_VERSION * 100n + DOMAIN_NOTE_COMMITMENT;
const DOMAIN_NULLIFIER_TAG = DOMAIN_VERSION * 100n + DOMAIN_NULLIFIER;

const DEPTH = 20;
const CHAIN_ID = 11155420n; // OP Sepolia

// Build a valid note
function makeNote(amount, secret, blinding) {
    const commitment = poseidonHash(DOMAIN_COMMITMENT, amount, secret, blinding);
    return { amount, secret, blinding, commitment };
}

function makeNullifier(note, chainId) {
    return poseidonHash(DOMAIN_NULLIFIER_TAG, note.secret, note.commitment, chainId);
}

function makeInSecret0Upper(secret) {
    // Upper bits of secret when split at 160 bits
    // secret = withdrawOwner + inSecret0Upper * 2^160
    // withdrawOwner is the lower 160 bits, so inSecret0Upper = (secret - withdrawOwner) / 2^160
    const RELAYER_MAX = 2n ** 160n;
    return (secret / RELAYER_MAX);
}

// Helper to create a secret with specific lower 160 bits (the owner)
function makeSecretWithOwner(owner, upperBits) {
    const RELAYER_MAX = 2n ** 160n;
    return owner + upperBits * RELAYER_MAX;
}

// NEW: Output commitment uses 5-input Poseidon with domain-separated dstChainId
function makeOutCommitment(amount, secret, blinding, dstChainId) {
  return poseidonHash(
    DOMAIN_COMMITMENT,
    amount,
    secret,
    blinding,
    dstChainId + DOMAIN_DST_CHAIN * 100n
  );
}

// Base valid inputs: 2-in 2-out transact, no withdrawal
const in0 = makeNote(500n, 111n, 222n);
const in1 = makeNote(500n, 333n, 444n);
const out0Secret = 555n;
const out0Blinding = 666n;
const out0Amount = 400n;
const out1Secret = 777n;
const out1Blinding = 888n;
const out1Amount = 100n;
const fee = 500n; // 500 = 500 (in0+in1=1000, out0+out1=500, fee=500, withdraw=0)

// After inserting in1 at index 1, the root changes — for simplicity use a single-leaf tree
// where in1 is also at index 0 in its own path (both share the same root for test purposes).
// Use a shared root: insert both into the same tree.
function buildTwoLeafRoot(leaf0, leaf1, depth) {
  const zeros = buildZeroTree(depth);
  // Level 0: leaf0 at 0, leaf1 at 1
  let cur0 = poseidonHash(leaf0, leaf1); // parent of both
  let root = cur0;
  for (let i = 1; i < depth; i++) {
    root = poseidonHash(root, zeros[i]);
  }
  return {
    root,
    path0: { elements: [leaf1, ...zeros.slice(1, depth)], indices: Array(depth).fill(0n) },
    path1: {
      elements: [leaf0, ...zeros.slice(1, depth)],
      indices: [1n, ...Array(depth - 1).fill(0n)],
    },
  };
}

const tree = buildTwoLeafRoot(in0.commitment, in1.commitment, DEPTH);
const merkleRoot = tree.root;

const nullifier0 = makeNullifier(in0, CHAIN_ID);
const nullifier1 = makeNullifier(in1, CHAIN_ID);
const outC0 = makeOutCommitment(out0Amount, out0Secret, out0Blinding, CHAIN_ID);
const outC1 = makeOutCommitment(out1Amount, out1Secret, out1Blinding, CHAIN_ID);

const validBase = {
  inAmount: [in0.amount, in1.amount],
  inSecret: [in0.secret, in1.secret],
  inBlinding: [in0.blinding, in1.blinding],
  inPathElements: [tree.path0.elements, tree.path1.elements],
  inPathIndices: [tree.path0.indices, tree.path1.indices],
  outAmount: [out0Amount, out1Amount],
  outSecret: [out0Secret, out1Secret],
  outBlinding: [out0Blinding, out1Blinding],
  merkleRoot,
  chainId: CHAIN_ID,
  dstChainId: CHAIN_ID,
  protocolEpoch: 0n,
  fee,
  relayer: 0n,
  nullifier: [nullifier0, nullifier1],
  outCommitment: [outC0, outC1],
  withdrawOwner: 0n,
  withdrawRecipient: 0n,
  withdrawAmount: 0n,
  inSecret0Upper: makeInSecret0Upper(in0.secret),
};

console.log("MARKPool circuit tests");

// Happy path
await expectPass("valid 2-in 2-out transact", validBase);

// Balance equation
await expectFail("fee too low (balance broken)", { ...validBase, fee: fee - 1n });
await expectFail("fee too high (balance broken)", { ...validBase, fee: fee + 1n });

// Withdrawal binding
const withdrawOwner = BigInt("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266");
const withdrawRecipient = BigInt("0x70997970C51812dc3A010C7d01b50e0d17dc79C8");
const withdrawAmount = 200n;
const feeWithWithdraw = 300n; // in0+in1=1000, out0+out1=500, fee=300, withdraw=200

// Create a new input note with secret bound to withdrawOwner
const in0Withdraw = makeNote(500n, makeSecretWithOwner(withdrawOwner, 0n), 222n);
const in1Withdraw = makeNote(500n, 333n, 444n);
const nullifier0Withdraw = makeNullifier(in0Withdraw, CHAIN_ID);
const nullifier1Withdraw = makeNullifier(in1Withdraw, CHAIN_ID);
const treeWithdraw = buildTwoLeafRoot(in0Withdraw.commitment, in1Withdraw.commitment, DEPTH);

const validWithWithdraw = {
  inAmount: [in0Withdraw.amount, in1Withdraw.amount],
  inSecret: [in0Withdraw.secret, in1Withdraw.secret],
  inBlinding: [in0Withdraw.blinding, in1Withdraw.blinding],
  inPathElements: [treeWithdraw.path0.elements, treeWithdraw.path1.elements],
  inPathIndices: [treeWithdraw.path0.indices, treeWithdraw.path1.indices],
  outAmount: [out0Amount, out1Amount],
  outSecret: [out0Secret, out1Secret],
  outBlinding: [out0Blinding, out1Blinding],
  merkleRoot: treeWithdraw.root,
  chainId: CHAIN_ID,
  dstChainId: CHAIN_ID,
  protocolEpoch: 0n,
  fee: feeWithWithdraw,
  relayer: 0n,
  nullifier: [nullifier0Withdraw, nullifier1Withdraw],
  outCommitment: [outC0, outC1],
  withdrawOwner,
  withdrawRecipient,
  withdrawAmount,
  inSecret0Upper: makeInSecret0Upper(in0Withdraw.secret),
};
await expectPass("valid transact with withdraw binding", validWithWithdraw);
await expectFail("withdraw amount non-zero but owner zero", {
    ...validWithWithdraw,
    withdrawOwner: 0n,
});
await expectFail("withdraw amount non-zero but recipient zero", {
    ...validWithWithdraw,
    withdrawRecipient: 0n,
});
await expectFail("withdraw amount zero but owner non-zero", {
    ...validBase,
    withdrawOwner,
    withdrawRecipient: 0n,
    withdrawAmount: 0n,
});

// Nullifier constraints
await expectFail("wrong nullifier (tampered)", {
  ...validBase,
  nullifier: [nullifier0 + 1n, nullifier1],
});
await expectFail("duplicate nullifiers", {
  ...validBase,
  nullifier: [nullifier0, nullifier0],
});

// Merkle root
await expectFail("wrong merkle root", { ...validBase, merkleRoot: merkleRoot + 1n });
await expectFail("zero merkle root", { ...validBase, merkleRoot: 0n });

// Input amount constraints
await expectFail("zero input amount", {
  ...validBase,
  inAmount: [0n, in1.amount],
  fee: in1.amount,
});

// Output commitment
await expectFail("wrong output commitment", {
  ...validBase,
  outCommitment: [outC0 + 1n, outC1],
});

// NEW: Test relayer upper bound constraint (relayer must be < 2^160)
await expectFail("relayer exceeds 160 bits", {
  ...validBase,
  relayer: 2n ** 160n, // exactly 2^160 should fail
});
await expectFail("relayer exceeds 160 bits (larger)", {
  ...validBase,
  relayer: 2n ** 161n,
});
await expectPass("relayer at max valid value (2^160 - 1)", {
  ...validBase,
  relayer: 2n ** 160n - 1n,
});

// NEW: Test cross-chain commitment reuse fails (domain-separated dstChainId)
const otherChainId = 11155111n; // Different chain (e.g., OP Mainnet)
const outC0_otherChain = makeOutCommitment(out0Amount, out0Secret, out0Blinding, otherChainId);
await expectFail("cross-chain commitment replay (dstChainId mismatch)", {
  ...validBase,
  outCommitment: [outC0_otherChain, outC1], // commitment computed for otherChainId
  dstChainId: CHAIN_ID, // but proof uses CHAIN_ID
});

console.log("\nAll tests passed.");
