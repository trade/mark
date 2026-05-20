# Changelog

All notable changes to MARK Protocol will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Gas snapshot tracking for contract tests (147 measurements, excludes invariants)
- 5-minute quick start guide in README
- CodeRabbit reviews for documentation and config files (.md, .yml, .toml)
- Comprehensive CI/CD with Slither, CodeQL, and secrets scanning
- Evidence-based release workflow with signed manifests
- Multi-chain deployment via super-cli
- docs/INDEX.md (central documentation index)

### Changed
- Migrated to mise for Node version management (removed .nvmrc)
- Removed pnpm-workspace.yaml (single-package project)
- Updated 16 frontend dependencies (minor/patch versions)
- Streamlined README.md (57% reduction, navigation hub)
- Updated docs/DEPLOYMENT.md (Sourcify verification, gas tracker fixes)

### Fixed
- Gas snapshot now excludes non-deterministic invariant tests for stable CI
- Dead links in documentation (6 links fixed)
- Typos (British → US English spelling)

## [0.1.0] - 2026-05-19

Initial testnet deployment.

### Added
- RYLA token (ERC-7802 SuperchainERC20)
- MARKSettlementModule with ZK proof verification
- MARKBridgeAdapter for cross-chain transfers
- MARKPool ZK UTXO pool with Groth16 verifier
- RYLACreditLedger for pool credit accounting
- MARKWithdrawAdapter for EIP-191 signature-based withdrawals
- Production lock safety mechanism (irreversible proof validation)

### Deployed to OP Sepolia (chainId: 11155420)
- RYLA: 0xa27360e124B94449249D1E919d3363BfF1c10c02
- MARKSettlementModule: 0xB1CD6e5B88EF5979AE5306A11302Aa2F19c6Ad59
- MARKBridgeAdapter: 0x5F3823739E510981A821aC5E99235e36f65cBc71
- AttestedSettlementVerifier: 0xECBd3bEf80fd4c05DBEdE45464A1d264E0884260
- MARKPoolVerifier: 0xEE8aE1d7FE8193411AAfC8eC6a53D7897BB3581a
- MARKPool: 0xD73594f95Cd154a79252d0187C0704D744bFFCAA
- RYLACreditLedger: 0x68F3D477FBb82b5cF835F31015532275E5d6fc5B
- MARKWithdrawAdapter: 0xC5fD2Aef37606D34d1DC978AEbB8521980E72328

[Unreleased]: https://github.com/trade/mark/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/trade/mark/releases/tag/v0.1.0
