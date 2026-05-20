import { existsSync, readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { markAddresses, markPoolAbi, opSepoliaPublicClient } from '../shared/mark';

type Groth16Proof = {
  pi_a: [string, string, string];
  pi_b: [[string, string], [string, string], [string, string]];
  pi_c: [string, string, string];
};

type FullProveResult = {
  proof: Groth16Proof;
  publicSignals: string[];
};

const circuitsDir = resolve('circuits');
const wasmPath = resolve(circuitsDir, 'build/MARKPool_js/MARKPool.wasm');
const zkeyPath = resolve(circuitsDir, 'build/markpool_final.zkey');

if (!existsSync(wasmPath) || !existsSync(zkeyPath)) {
  throw new Error(
    'Missing circuit artifacts. Run: cd circuits && npm install && npm run build && node setup.mjs'
  );
}

const requireFromCircuits = createRequire(resolve(circuitsDir, 'package.json'));
const snarkjs = requireFromCircuits('snarkjs') as {
  groth16: {
    fullProve(
      input: Record<string, unknown>,
      wasmFile: string,
      zkeyFileName: string
    ): Promise<FullProveResult>;
  };
};
const { buildPoseidon } = requireFromCircuits('circomlibjs') as {
  buildPoseidon(): Promise<{
    F: { toObject(value: unknown): bigint };
    (inputs: bigint[]): unknown;
  }>;
};

const publicClient = opSepoliaPublicClient();
const [merkleRoot, protocolEpoch] = await Promise.all([
  publicClient.readContract({
    address: markAddresses.markPool,
    abi: markPoolAbi,
    functionName: 'getMerkleRoot',
  }),
  publicClient.readContract({
    address: markAddresses.markPool,
    abi: markPoolAbi,
    functionName: 'protocolEpoch',
  }),
]);

const inputPath = process.env.MARK_POOL_INPUT ? resolve(process.env.MARK_POOL_INPUT) : undefined;
const input = inputPath
  ? (JSON.parse(readFileSync(inputPath, 'utf8')) as Record<string, unknown>)
  : await buildDemoInput();

input.chainId = '11155420';
input.dstChainId ??= '11155420';
input.protocolEpoch = protocolEpoch.toString();

if (process.env.MARK_POOL_USE_LIVE_ROOT === 'true') {
  input.merkleRoot = BigInt(merkleRoot).toString();
}

console.log(`Generating MARKPool proof from ${inputPath ?? 'generated demo witness'}`);
console.log(`OP Sepolia pool root: ${merkleRoot}`);
console.log(`Witness root: ${input.merkleRoot}`);

const { proof, publicSignals } = await snarkjs.groth16.fullProve(input, wasmPath, zkeyPath);

const a = [BigInt(proof.pi_a[0]), BigInt(proof.pi_a[1])] as const;
const bSnarkjs = [
  [BigInt(proof.pi_b[0][0]), BigInt(proof.pi_b[0][1])],
  [BigInt(proof.pi_b[1][0]), BigInt(proof.pi_b[1][1])],
] as const;
const c = [BigInt(proof.pi_c[0]), BigInt(proof.pi_c[1])] as const;

console.log('Proof generated.');
console.log(
  JSON.stringify(
    {
      publicSignals,
      contractArgs: {
        a: a.map(String),
        bSnarkjs: bSnarkjs.map(row => row.map(String)),
        c: c.map(String),
      },
    },
    null,
    2
  )
);

async function buildDemoInput(): Promise<Record<string, unknown>> {
  const poseidon = await buildPoseidon();
  const poseidonHash = (...inputs: bigint[]) => poseidon.F.toObject(poseidon(inputs));
  const depth = 20;
  const chainId = 11155420n;
  const domainCommitment = 111n;
  const domainNullifier = 112n;

  const zeros = [0n];
  for (let i = 1; i <= depth; i++) {
    zeros.push(poseidonHash(zeros[i - 1], zeros[i - 1]));
  }

  const makeNote = (amount: bigint, secret: bigint, blinding: bigint) => ({
    amount,
    secret,
    blinding,
    commitment: poseidonHash(domainCommitment, amount, secret, blinding),
  });

  const in0 = makeNote(500n, 111n, 222n);
  const in1 = makeNote(500n, 333n, 444n);
  const out0Amount = 400n;
  const out1Amount = 100n;
  const out0Secret = 555n;
  const out1Secret = 777n;
  const out0Blinding = 666n;
  const out1Blinding = 888n;

  let root = poseidonHash(in0.commitment, in1.commitment);
  for (let i = 1; i < depth; i++) {
    root = poseidonHash(root, zeros[i]);
  }

  return stringifyBigInts({
    inAmount: [in0.amount, in1.amount],
    inSecret: [in0.secret, in1.secret],
    inBlinding: [in0.blinding, in1.blinding],
    inPathElements: [
      [in1.commitment, ...zeros.slice(1, depth)],
      [in0.commitment, ...zeros.slice(1, depth)],
    ],
    inPathIndices: [Array(depth).fill(0n), [1n, ...Array(depth - 1).fill(0n)]],
    outAmount: [out0Amount, out1Amount],
    outSecret: [out0Secret, out1Secret],
    outBlinding: [out0Blinding, out1Blinding],
    merkleRoot: root,
    fee: 500n,
    relayer: 0n,
    nullifier: [
      poseidonHash(domainNullifier, in0.secret, in0.commitment, chainId),
      poseidonHash(domainNullifier, in1.secret, in1.commitment, chainId),
    ],
    outCommitment: [
      poseidonHash(domainCommitment, out0Amount, out0Secret, out0Blinding + chainId),
      poseidonHash(domainCommitment, out1Amount, out1Secret, out1Blinding + chainId),
    ],
    withdrawOwner: 0n,
    withdrawRecipient: 0n,
    withdrawAmount: 0n,
  });
}

function stringifyBigInts(value: unknown): Record<string, unknown> {
  return JSON.parse(
    JSON.stringify(value, (_key, nestedValue) =>
      typeof nestedValue === 'bigint' ? nestedValue.toString() : nestedValue
    )
  ) as Record<string, unknown>;
}
