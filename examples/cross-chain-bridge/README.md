# Cross-Chain Bridge

Bridge RYLA from OP Sepolia through `MARKBridgeAdapter`.

## Prerequisites

- Node.js 20+ and pnpm 9+
- An OP Sepolia RPC URL
- A funded OP Sepolia private key with RYLA balance and `OPERATOR_ROLE` on `MARKBridgeAdapter`
- An allowlisted `DESTINATION_CHAIN_ID`
- Enough ETH on OP Sepolia for gas

Deployed OP Sepolia contracts are listed in the root [README.md](../../README.md#deployed-contracts).

## Usage

```bash
OP_SEPOLIA_RPC_URL=https://sepolia.optimism.io \
PRIVATE_KEY=0x... \
BRIDGE_RECIPIENT=0x... \
BRIDGE_AMOUNT=1 \
DESTINATION_CHAIN_ID=... \
pnpm dlx tsx examples/cross-chain-bridge/index.ts
```

The example checks destination allowlisting, reads bridge limits, approves RYLA when needed, simulates `bridgeTo`, submits the bridge transaction, and waits for the OP Sepolia receipt.
