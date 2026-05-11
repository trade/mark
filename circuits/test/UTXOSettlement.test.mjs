// Witness test for UTXOSettlement circuit.
// Run: node test/UTXOSettlement.test.mjs

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

const wasmPath = path.join(__dirname, "../build/UTXOSettlement_js/UTXOSettlement.wasm");
const WitnessCalculator = require(path.join(__dirname, "../build/UTXOSettlement_js/witness_calculator.js"));
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
  } catch {
    console.log(`  PASS: ${label}`);
  }
}

const secret = 12345678901234567890n;
const nonce = 98765432109876543210n;
const recipient = BigInt("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266");
const chainId = 11155420n;
const settlementModule = BigInt("0x8e2540963de8517564FACb02f2e8DDDA7C48fBF8");
const amount = 1000000000000000000n;
const isMint = 1n;

const nullifierHash = poseidonHash(secret, nonce);
const commitmentHash = poseidonHash(secret, amount, isMint, recipient, chainId, settlementModule);

const valid = { secret, nonce, recipient, chainId, settlementModule, nullifierHash, commitmentHash, amount, isMint };

console.log("UTXOSettlement circuit tests");

await expectPass("valid mint", valid);
await expectPass("valid burn (isMint=0)", {
  ...valid,
  isMint: 0n,
  commitmentHash: poseidonHash(secret, amount, 0n, recipient, chainId, settlementModule),
});
await expectFail("wrong nullifierHash", { ...valid, nullifierHash: nullifierHash + 1n });
await expectFail("wrong commitmentHash", { ...valid, commitmentHash: commitmentHash + 1n });
await expectFail("non-binary isMint (2)", { ...valid, isMint: 2n });
await expectFail("zero amount", {
  ...valid,
  amount: 0n,
  commitmentHash: poseidonHash(secret, 0n, isMint, recipient, chainId, settlementModule),
});
await expectFail("amount exceeds 64 bits", {
  ...valid,
  amount: 2n ** 64n,
  commitmentHash: poseidonHash(secret, 2n ** 64n, isMint, recipient, chainId, settlementModule),
});
await expectFail("recipient exceeds 160 bits", {
  ...valid,
  recipient: 2n ** 160n,
  commitmentHash: poseidonHash(secret, amount, isMint, 2n ** 160n, chainId, settlementModule),
});
await expectFail("chainId exceeds 64 bits", {
  ...valid,
  chainId: 2n ** 64n,
  commitmentHash: poseidonHash(secret, amount, isMint, recipient, 2n ** 64n, settlementModule),
});

console.log("\nAll tests passed.");
