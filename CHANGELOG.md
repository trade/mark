# Changelog

All notable changes to MARK Protocol will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Gas snapshot tracking for contract tests (147 measurements, excludes invariants)
- 5-minute quick start guide in README
- Comprehensive CI/CD with Slither, CodeQL, and secrets scanning
- Evidence-based release workflow with signed manifests
- Multi-chain deployment via super-cli
- docs/INDEX.md (central documentation index)
- `docs-ci` workflow: internal link checker runs on every PR touching markdown files
- `labels.yml` config and sync workflow (EndBug/label-sync) — labels as code, 15 labels defined
- GitHub issue templates: bug report, feature request, config (blank issues disabled)
- `circuits/` added as separate Dependabot npm ecosystem entry
- KI-9: documented circuits transitive dependency vulnerabilities with resolution path
- `contracts/config/profiles/local.env.example` for supersim local development (#230)
- Warning comment for public test key in local.env.example (#231)

### Changed
- Workflow concurrency control added to 4 CI workflows (20-30% CI time reduction)
- Dynamic pnpm version extraction from package.json (eliminates version drift)
- Migrated to mise for Node version management (removed .nvmrc)
- Removed pnpm-workspace.yaml (single-package project)
- Updated frontend dependencies (minor/patch versions)
- Streamlined README.md (57% reduction, navigation hub)
- Updated docs/DEPLOYMENT.md (Sourcify verification, gas tracker fixes)
- All GitHub Actions pinned to commit SHAs across 22 workflow files (supply chain hardening)
- Added least-privilege `permissions` blocks to 14 workflow files (OpenSSF Token-Permissions)
- CodeRabbit GitHub bot auto-review disabled — local CLI pre-push hook is the enforcement point
- `staging.env` RPC URL replaced with `MARK_STAGING_RPC_URL` env var (CWE-798)
- CODEOWNERS paths corrected to `docs/` prefix; removed non-existent `remappings.txt` entry
- `setup-foundry` and `setup-node-pnpm` composite actions pinned to commit SHAs
- `governance-policy-guard` path filter corrected to `docs/BRANCHING.md`
- `dependency-review` redundant top-level permissions block removed
- `contracts-ci` unit and integration jobs given `timeout-minutes: 20`
- `circom` binary download now verified with SHA256 checksum
- Release PR template header corrected: `canary -> main` → `dev -> main`
- `Internal Link Check` added to required status checks on `dev` branch

### Fixed
- Gas snapshot now excludes non-deterministic invariant tests for stable CI
- Dead links in documentation (4 broken internal links fixed)
- Typos (British → US English spelling)
- `testDeployMARKPoolRevertsWhenMissingTokenAdmin` flaky test: `PRIVATE_KEY` now explicitly set in test body so `_loadConfig()` succeeds in fresh-process contexts (e.g. `make gas-check`)
- Stale transfer scripts removed (`pretransfer-readiness.sh`, `posttransfer-bootstrap.sh`)
- `.vscode` exception rules removed from `.gitignore`

### Removed
- Unused button component from frontend (#233)

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
