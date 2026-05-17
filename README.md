# MARK

Privacy-first settlement infrastructure leveraging zero-knowledge technologies for secure, scalable, and private transactions on EVM-compatible blockchains, with native support for the Optimism Superchain.

Code is a rule. No DAO, no drama. Don't Trust, Verify.

Settlement rules are enforced on-chain. Whether operators run it as a centralised service or a decentralised network is their choice — the contracts don't care.

## Getting Started

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Node.js + pnpm

### 1. Clone the repository

```bash
git clone https://github.com/trade/mark.git
cd mark
```

### 2. Install dependencies

```bash
pnpm i
```

### 3. Start development

```bash
pnpm dev
```

This will:

- Start a local Superchain network (1 L1 + 2 L2 chains) via [supersim](https://github.com/ethereum-optimism/supersim)
- Launch the frontend at http://localhost:5173
- Deploy contracts to the local network

## Branching Policy

Full policy is documented in [BRANCHING.md](./BRANCHING.md).

- `dev` — active integration and testnet (OP Sepolia auto-deploys on push)
- `main` — mainnet-ready only
- Release promotion path: `dev -> main`
- Production readiness workflow is gated to `main`

## Deploying Contracts

MARK uses `super-cli` (`sup`) for contract deployment across the Superchain.

### Interactive mode

```bash
pnpm sup
```

### Non-interactive mode

```bash
pnpm sup deploy create2 --chains supersiml2a,supersiml2b --salt ethers phoenix --forge-artifact-path contracts/out/<Contract>.sol/<Contract>.json --network supersim --private-key <private-key>
```

### Prepare mode (print command without running)

```bash
pnpm sup --prepare
```

### Build before deploying

```bash
pnpm build:contracts
```

## Overview

### Contracts

- **RYLA Credits** (`RYLA`) — Superchain-compatible credit token. Mintable and burnable only by the settlement module.
- **MARKSettlementModule** — Operator-gated settlement boundary with replay protection and optional ZK proof verification.
- **MARKBridgeAdapter** — Operator-gated bridge adapter routing RYLA cross-chain via SuperchainTokenBridge with rate limits.
- **AttestedSettlementVerifier** — EIP-712 signature-based verifier for settlement intents.

### Tools

- **[supersim](https://github.com/ethereum-optimism/supersim)** — local Superchain test environment with pre-deployed contracts
- **[sup (super-cli)](https://github.com/ethereum-optimism/super-cli)** — multi-chain deployment with sponsored transactions
- **foundry** — smart contract development framework
- **wagmi / viem** — TypeScript libraries for the EVM
- **vite / tailwind / shadcn** — frontend tooling and UI components

### Directory Structure

```
mark/
├── contracts/          # Smart contract code (Foundry)
├── src/                # Frontend code (vite, tailwind, shadcn, wagmi, viem)
├── public/             # Static assets
├── supersim-logs/      # Local supersim logs
├── package.json        # Project dependencies and scripts
└── mprocs.yaml         # Multi-process dev runner
```

## Deployed Contracts

### OP Sepolia (chainId: 11155420)

| Contract | Address |
|---|---|
| RYLA | [`0xa27360e124B94449249D1E919d3363BfF1c10c02`](https://sepolia-optimism.etherscan.io/address/0xa27360e124B94449249D1E919d3363BfF1c10c02) |
| MARKSettlementModule | [`0xB1CD6e5B88EF5979AE5306A11302Aa2F19c6Ad59`](https://sepolia-optimism.etherscan.io/address/0xB1CD6e5B88EF5979AE5306A11302Aa2F19c6Ad59) |
| MARKBridgeAdapter | [`0x5F3823739E510981A821aC5E99235e36f65cBc71`](https://sepolia-optimism.etherscan.io/address/0x5F3823739E510981A821aC5E99235e36f65cBc71) |
| AttestedSettlementVerifier | [`0xECBd3bEf80fd4c05DBEdE45464A1d264E0884260`](https://sepolia-optimism.etherscan.io/address/0xECBd3bEf80fd4c05DBEdE45464A1d264E0884260) |

Staging rehearsal: [run 25979311184](https://github.com/trade/mark/actions/runs/25979311184) — production lock verified.

## Debugging

- Full interoperability error signatures: [abi-signatures.md](https://github.com/ethereum-optimism/ecosystem/blob/main/packages/viem/docs/abi-signatures.md)
- Common errors:
  - `TargetCallFailed()`: `0xeda86850`
  - `MessageAlreadyRelayed`: `0x9ca9480b`
  - `Unauthorized()`: `0x82b42900`

## Resources

- Interop guides: https://docs.optimism.io/app-developers/tutorials/interop
- Superchain Dev Console: https://console.optimism.io/

## License

Files are licensed under the [MIT license](./LICENSE).
