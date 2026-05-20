# ZK Proof Generation

Generate a MARKPool Groth16 proof with `snarkjs`, then format the proof for the deployed OP Sepolia `MARKPool`.

## Prerequisites

- Node.js 20+ and pnpm 9+
- An OP Sepolia RPC URL
- Circuit artifacts generated under `circuits/build`
- Optional: a witness input JSON matching `circuits/mark/MARKPool.circom`

Build the circuit artifacts first:

```bash
cd circuits
npm install
npm run build
node setup.mjs
cd ..
```

Deployed OP Sepolia contracts are listed in the root [README.md](../../README.md#deployed-contracts).

## Usage

```bash
OP_SEPOLIA_RPC_URL=https://sepolia.optimism.io \
pnpm dlx tsx examples/zk-proof-generation/index.ts
```

The default run generates a valid demo witness, reads the current OP Sepolia pool root and protocol epoch, generates a Groth16 proof, and prints `a`, `bSnarkjs`, and `c` values in the shape expected by `MARKPool.transact`.

For a real OP Sepolia note, pass your own witness input and bind it to the live pool root:

```bash
OP_SEPOLIA_RPC_URL=https://sepolia.optimism.io \
MARK_POOL_INPUT=path/to/mark-pool-input.json \
MARK_POOL_USE_LIVE_ROOT=true \
pnpm dlx tsx examples/zk-proof-generation/index.ts
```

`input.example.json` documents the expected witness shape. Replace it with real note secrets, Merkle paths, nullifiers, and output commitments from your MARK integration before submitting a proof on-chain.
