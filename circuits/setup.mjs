// Trusted setup for MARKPool circuit.
// Generates build/MARKPoolVerifier.sol for use in contracts/src/pool/verifier/.
// Run: node setup.mjs
//
// Powers of tau: pot15 (2^15 = 32768 >= 26387*2 wires required by MARKPool(20,2,2))

import { zKey, powersOfTau } from 'snarkjs';
import { readFileSync, writeFileSync } from 'fs';

console.log('Step 1: Powers of Tau (pot15)...');
await powersOfTau.newAccumulator('bn128', 15, 'build/pot15_0000.ptau');

console.log('Step 2: Contribute to Powers of Tau...');
await powersOfTau.contribute('build/pot15_0000.ptau', 'build/pot15_final.ptau',
  'MARK Protocol', 'markpool-entropy-' + Date.now());

console.log('Step 3: Prepare phase 2...');
await powersOfTau.preparePhase2('build/pot15_final.ptau', 'build/pot15_phase2.ptau');

console.log('Step 4: Phase 2 setup...');
await zKey.newZKey('build/MARKPool.r1cs', 'build/pot15_phase2.ptau', 'build/markpool_0000.zkey');

console.log('Step 5: Contribute to zkey...');
await zKey.contribute('build/markpool_0000.zkey', 'build/markpool_final.zkey',
  'MARK Protocol MARKPool', 'markpool-zkey-entropy-' + Date.now());

console.log('Step 6: Export verification key...');
const vKey = await zKey.exportVerificationKey('build/markpool_final.zkey');
writeFileSync('build/markpool_verification_key.json', JSON.stringify(vKey, null, 2));

console.log('Step 7: Export Solidity verifier...');
const { default: solidityTemplate } = await import('snarkjs/templates/verifier_groth16.sol.ejs', { assert: { type: 'text' } });
const verifier = await zKey.exportSolidityVerifier('build/markpool_final.zkey', { groth16: solidityTemplate });
writeFileSync('build/MARKPoolVerifier.sol', verifier);

console.log('Done. Copy build/MARKPoolVerifier.sol to contracts/src/pool/verifier/MARKPoolVerifier.sol');
