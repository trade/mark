// Witness test for UTXOSettlement circuit.
// Verifies that valid inputs produce a correct witness and invalid inputs fail constraint checks.
// Run: node test/UTXOSettlement.test.js

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

// Load the compiled wasm witness calculator (CJS module — use createRequire)
const wasmPath = path.join(__dirname, "../build/UTXOSettlement_js/UTXOSettlement.wasm");
const wcPath = path.join(__dirname, "../build/UTXOSettlement_js/witness_calculator.js");
const WitnessCalculator = require(wcPath);
const wasm = readFileSync(wasmPath);
const wc = await WitnessCalculator(wasm);

async function calcWitness(input) {
  return wc.calculateWitness(input, false);
}

async function expectPass(label, input) {
  try {
    await calcWitness(input);
    console.log(`  PASS: ${label}`);
  } catch (e) {
    console.error(`  FAIL: ${label} — expected pass but got: ${e.message}`);
    process.exit(1);
  }
}

async function expectFail(label, input) {
  try {
    await calcWitness(input);
    console.error(`  FAIL: ${label} — expected constraint failure but witness succeeded`);
    process.exit(1);
  } catch {
    console.log(`  PASS: ${label}`);
  }
}

// Test values
const secret = 12345678901234567890n;
const nonce = 98765432109876543210n;
const recipient = BigInt("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266");
const chainId = 11155420n;
const settlementModule = BigInt("0x8e2540963de8517564FACb02f2e8DDDA7C48fBF8");
const amount = 1000000000000000000n;
const isMint = 1n;

const nullifierHash = poseidonHash(secret, nonce);
const commitmentHash = poseidonHash(secret, amount, isMint, recipient, chainId, settlementModule);

const validInput = { secret, nonce, recipient, chainId, settlementModule, nullifierHash, commitmentHash, amount, isMint };

console.log("UTXOSettlement circuit tests");

await expectPass("valid inputs", validInput);
await expectFail("wrong nullifierHash", { ...validInput, nullifierHash: nullifierHash + 1n });
await expectFail("wrong commitmentHash", { ...validInput, commitmentHash: commitmentHash + 1n });
await expectFail("non-binary isMint (2)", { ...validInput, isMint: 2n });
await expectFail("zero amount", {
  ...validInput,
  amount: 0n,
  commitmentHash: poseidonHash(secret, 0n, isMint, recipient, chainId, settlementModule),
});
await expectPass("isMint=0 (burn)", {
  ...validInput,
  isMint: 0n,
  commitmentHash: poseidonHash(secret, amount, 0n, recipient, chainId, settlementModule),
});

console.log("\nAll tests passed.");
