# MARK

[![Gitleaks](https://github.com/trade/mark/workflows/Secrets%20Scan/badge.svg)](https://github.com/trade/mark/actions/workflows/secrets-scan.yml)

Privacy-first settlement infrastructure leveraging zero-knowledge technologies for secure, private, and scalable transactions. Built for EVM-compatible blockchains, with native support for the Optimism Superchain.

**Code is a rule.** No DAO, no drama. Don't Trust, Verify.

Settlement rules are enforced on-chain. Whether operators run it as a centralized service or a decentralized network is their choice — the contracts don't care.

## Quick Start

```bash
# Prerequisites: Node.js 20/22, pnpm 9.0.2+, Foundry
git clone https://github.com/trade/mark.git
cd mark
pnpm i && pnpm dev
```

Visit http://localhost:5173 to see the MARK dashboard running on a local Superchain (1 L1 + 2 L2 chains).

**Missing prerequisites?** See [Getting Started](./CONTRIBUTING.md#getting-started) for installation instructions.

## Documentation

### Core Documentation
- **[Getting Started](./CONTRIBUTING.md)** — Development setup, code standards, and contribution guidelines
- **[Architecture](./docs/ARCHITECTURE.md)** — System design, domain rules, and contract interactions
- **[Deployment](./docs/DEPLOYMENT.md)** — Step-by-step deployment to testnet and mainnet
- **[Branching Strategy](./docs/BRANCHING.md)** — Git workflow, release process, and CI/CD
- **[Troubleshooting](./docs/TROUBLESHOOTING.md)** — Common issues and solutions

### Additional Resources
- **[CHANGELOG](./CHANGELOG.md)** — Release history and version notes
- **[Contracts README](./contracts/README.md)** — Smart contract details and testing
- **[Threat Model](./docs/THREAT_MODEL.md)** — Security assumptions and role compromise impact
- **[Known Issues](./docs/KNOWN_ISSUES.md)** — Accepted design decisions and limitations
- **[CONTRIBUTORS](./CONTRIBUTORS.md)** — Contributor recognition

## Deployed Contracts

### OP Sepolia (chainId: 11155420)

| Contract | Address |
|---|---|
| RYLA | [`0xa27360e124B94449249D1E919d3363BfF1c10c02`](https://sepolia-optimism.etherscan.io/address/0xa27360e124B94449249D1E919d3363BfF1c10c02) |
| MARKSettlementModule | [`0xB1CD6e5B88EF5979AE5306A11302Aa2F19c6Ad59`](https://sepolia-optimism.etherscan.io/address/0xB1CD6e5B88EF5979AE5306A11302Aa2F19c6Ad59) |
| MARKBridgeAdapter | [`0x5F3823739E510981A821aC5E99235e36f65cBc71`](https://sepolia-optimism.etherscan.io/address/0x5F3823739E510981A821aC5E99235e36f65cBc71) |
| AttestedSettlementVerifier | [`0xECBd3bEf80fd4c05DBEdE45464A1d264E0884260`](https://sepolia-optimism.etherscan.io/address/0xECBd3bEf80fd4c05DBEdE45464A1d264E0884260) |
| MARKPoolVerifier | [`0xEE8aE1d7FE8193411AAfC8eC6a53D7897BB3581a`](https://sepolia-optimism.etherscan.io/address/0xEE8aE1d7FE8193411AAfC8eC6a53D7897BB3581a) |
| MARKPool | [`0xD73594f95Cd154a79252d0187C0704D744bFFCAA`](https://sepolia-optimism.etherscan.io/address/0xD73594f95Cd154a79252d0187C0704D744bFFCAA) |
| RYLACreditLedger | [`0x68F3D477FBb82b5cF835F31015532275E5d6fc5B`](https://sepolia-optimism.etherscan.io/address/0x68F3D477FBb82b5cF835F31015532275E5d6fc5B) |
| MARKWithdrawAdapter | [`0xC5fD2Aef37606D34d1DC978AEbB8521980E72328`](https://sepolia-optimism.etherscan.io/address/0xC5fD2Aef37606D34d1DC978AEbB8521980E72328) |

**Verification:**
- Staging rehearsal: [run 25979311184](https://github.com/trade/mark/actions/runs/25979311184)
- Pool deployment: [run 25994552682](https://github.com/trade/mark/actions/runs/25994552682)

## Key Features

- **RYLA Token** — Superchain-compatible ERC-7802 credit token with role-gated mint/burn
- **Settlement Module** — Operator-gated settlement with replay protection and ZK proof verification
- **Bridge Adapter** — Cross-chain RYLA transfers via SuperchainTokenBridge with rate limits
- **ZK UTXO Pool** — Privacy-preserving pool with Groth16 proof verification and nullifier registry
- **Withdrawal System** — EIP-191 signature-based withdrawals with dual-signature security

See [contracts/README.md](./contracts/README.md) for detailed contract documentation.

## External Resources

- **Optimism Interop Guides**: https://docs.optimism.io/app-developers/tutorials/interop
- **Superchain Dev Console**: https://console.optimism.io/
- **Supersim (Local Testnet)**: https://github.com/ethereum-optimism/supersim
- **Super CLI (Deployment)**: https://github.com/ethereum-optimism/super-cli

## Security

Report vulnerabilities via [GitHub Security Advisories](https://github.com/trade/mark/security/advisories/new). See [SECURITY.md](./SECURITY.md) for details.

## License

Licensed under the [MIT License](./LICENSE).
