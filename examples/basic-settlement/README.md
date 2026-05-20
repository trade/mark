# Basic Settlement

Submit a settlement mint intent to the OP Sepolia `MARKSettlementModule`.

## Prerequisites

- Node.js 20+ and pnpm 9+
- An OP Sepolia RPC URL
- A funded OP Sepolia operator private key with `OPERATOR_ROLE` on `MARKSettlementModule`
- A unique 32-byte `SETTLEMENT_INTENT_ID`
- `SETTLEMENT_PROOF` when proof validation is enabled for the deployment

Deployed OP Sepolia contracts are listed in the root [README.md](../../README.md#deployed-contracts).

## Usage

```bash
OP_SEPOLIA_RPC_URL=https://sepolia.optimism.io \
PRIVATE_KEY=0x... \
SETTLEMENT_RECIPIENT=0x... \
SETTLEMENT_AMOUNT=1 \
SETTLEMENT_INTENT_ID=0x... \
SETTLEMENT_PROOF=0x \
pnpm dlx tsx examples/basic-settlement/index.ts
```

The example simulates `settleMint` first, then submits the transaction and waits for the receipt. It was built for the OP Sepolia deployment in the project README.
