# Changelog

All notable changes to MARK Protocol will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- RYLA token (ERC-7802 SuperchainERC20)
- MARKSettlementModule with ZK proof verification
- MARKBridgeAdapter for cross-chain transfers
- MARKPool ZK UTXO pool with Groth16 verifier
- RYLACreditLedger for pool credit accounting
- MARKWithdrawAdapter for EIP-191 signature-based withdrawals
- Evidence-based release workflow with signed manifests
- Production lock safety mechanism (irreversible proof validation)
- Comprehensive CI/CD with Slither, CodeQL, and secrets scanning
- Multi-chain deployment via super-cli

### Deployed
- OP Sepolia (chainId: 11155420):
  - RYLA: 0xa27360e124B94449249D1E919d3363BfF1c10c02
  - MARKSettlementModule: 0xB1CD6e5B88EF5979AE5306A11302Aa2F19c6Ad59
  - MARKBridgeAdapter: 0x5F3823739E510981A821aC5E99235e36f65cBc71
  - AttestedSettlementVerifier: 0xECBd3bEf80fd4c05DBEdE45464A1d264E0884260
  - MARKPoolVerifier: 0xEE8aE1d7FE8193411AAfC8eC6a53D7897BB3581a
  - MARKPool: 0xD73594f95Cd154a79252d0187C0704D744bFFCAA
  - RYLACreditLedger: 0x68F3D477FBb82b5cF835F31015532275E5d6fc5B
  - MARKWithdrawAdapter: 0xC5fD2Aef37606D34d1DC978AEbB8521980E72328

## [0.1.0] - 2026-05-19

Initial testnet deployment.
