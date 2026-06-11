// Trusted setup for MARKPool circuit.
// Generates build/MARKPoolVerifier.sol for use in contracts/src/pool/verifier/.
// Run: node setup.mjs
//
// Powers of tau: pot15 (2^15 = 32768 >= 26387*2 wires required by MARKPool(20,2,2))
// Using pre-computed ptau from circomlib perpetual ceremony.

import { randomBytes } from "crypto";
import { mkdirSync, writeFileSync, readFileSync, existsSync } from "fs";
import { fileURLToPath } from "url";
import { zKey, powersOfTau } from "snarkjs";

mkdirSync("build", { recursive: true });

const entropy1 = randomBytes(32).toString("hex");
const entropy2 = randomBytes(32).toString("hex");

// Skip steps 1-3: Use pre-computed pot15_final.ptau from circomlib ceremony
// Downloaded from: https://github.com/iden3/circomlib/blob/master/circuits/pot15_final.ptau
console.log("Using pre-computed pot15_final.ptau...");
if (!existsSync("build/pot15_final.ptau")) {
  console.error("Error: build/pot15_final.ptau not found. Download from circomlib repo.");
  process.exit(1);
}

console.log("Step 1-3: Skipped (using pre-computed powers of tau)");
console.log("Step 3: Prepare phase 2...");
await powersOfTau.preparePhase2("build/pot15_final.ptau", "build/pot15_phase2.ptau");

// Verify compiled circuit exists before attempting trusted setup
if (!existsSync("build/MARKPool.r1cs")) {
  console.error("Error: build/MARKPool.r1cs not found. Run: pnpm run build");
  process.exit(1);
}

console.log("Step 4: Phase 2 setup...");
await zKey.newZKey("build/MARKPool.r1cs", "build/pot15_phase2.ptau", "build/markpool_0000.zkey");

console.log("Step 5: Contribute to zkey...");
await zKey.contribute(
  "build/markpool_0000.zkey",
  "build/markpool_final.zkey",
  "MARK Protocol MARKPool",
  entropy2
);

console.log("Step 6: Export verification key...");
const vKey = await zKey.exportVerificationKey("build/markpool_final.zkey");
writeFileSync("build/markpool_verification_key.json", JSON.stringify(vKey, null, 2));

console.log("Step 7: Export Solidity verifier...");
const templatePath = fileURLToPath(
  new URL("node_modules/snarkjs/templates/verifier_groth16.sol.ejs", import.meta.url)
);
const solidityTemplate = readFileSync(templatePath, "utf8");
const verifier = await zKey.exportSolidityVerifier("build/markpool_final.zkey", {
  groth16: solidityTemplate,
});
writeFileSync("build/MARKPoolVerifier.sol", verifier);

console.log(
  "Done. Copy build/MARKPoolVerifier.sol to contracts/src/pool/verifier/MARKPoolVerifier.sol"
);
