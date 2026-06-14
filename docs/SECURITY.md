# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| main    | ✅ Active          |
| dev     | ✅ Pre-release     |

Only `main` and `dev` branches receive security updates.

## Reporting a Vulnerability

**Do not open public issues for security vulnerabilities.**

Report vulnerabilities privately via:

- **GitHub Security Advisories**: Use the "Report a vulnerability" tab in this repository

### What to Include

- Description of the vulnerability
- Steps to reproduce or proof-of-concept
- Affected components (contracts, circuits, frontend, bridge)
- Potential impact (funds at risk, privacy loss, DoS, etc.)
- Suggested fix if available

### Response Timeline

| Severity | Initial Response | Fix Target |
| -------- | ---------------- | ---------- |
| Critical (funds drain, nullifier reuse) | 24 hours | 72 hours |
| High (privacy breach, DoS) | 48 hours | 7 days |
| Medium (info leak, grindable) | 7 days | 30 days |
| Low (code quality, no exploit) | 14 days | Next release |

## Scope

### In Scope

- Smart contracts: `contracts/src/pool`, `contracts/src/bridge`, `contracts/src/settlement`
- ZK Circuits: `packages/circuits/circuits/`
- Bridge relayer logic: `packages/relayer/`
- Frontend: `packages/frontend/` (client-side only)
- Deployment scripts: `contracts/script/`

### Out of Scope

- Third-party dependencies (report upstream)
- Social engineering / phishing
- Infrastructure not controlled by MARK (RPC providers, sequencers)
- Theoretical issues without exploit path

## Disclosure Policy

- We follow **coordinated disclosure**.
- We will acknowledge receipt within the timelines above.
- We will keep you informed of progress.
- We will credit you in the advisory (unless you request anonymity).
- We request you **not** disclose publicly until we release a fix.

## Bug Bounty

MARK Protocol does not currently operate a formal bug bounty program. 
Critical vulnerabilities affecting user funds will be rewarded at the team's discretion.

## Security Architecture Notes

MARK Protocol relies on **on-chain enforcement over trust assumptions**:

- **Nullifier uniqueness** enforced by contract storage, not relayers
- **Circuit soundness** verified on-chain via Groth16/Plonk verifiers
- **No admin keys** can mint notes, set roots, or reuse nullifiers
- **Bridge adapters** are unprivileged; they only submit proofs
- **Reorg safety** via L2 block finality checks in withdrawal paths

See `contracts/ARCHITECTURE.md` and `docs/ZK_SECURITY.md` for details.

## Security Tooling

Continuous validation runs on every PR:

| Tool | Purpose |
| ---- | ------- |
| Foundry Fuzz / Invariant | Property-based contract testing |
| Semgrep (Solidity) | Static analysis ruleset |
| Circomspect | Circuit static analysis |
| TruffleHog | Secret scanning |
| CodeQL (JS/TS) | Code scanning for frontend/relayer |
| Dependency Review | Supply chain vulnerabilities |

CodeQL Solidity and Slither are known gaps — tracked in CI but not required.

