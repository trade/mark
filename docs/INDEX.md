# MARK Protocol Documentation Index

## Getting Started

1. **[README.md](../README.md)** — Project overview and quick start
2. **[CONTRIBUTING.md](../CONTRIBUTING.md)** — Development setup, code standards, testing
3. **[ARCHITECTURE.md](./ARCHITECTURE.md)** — System design, domain rules, contract interactions
4. **[TUTORIAL.md](./TUTORIAL.md)** — End-to-end transaction flow walkthrough

## Development

- **[TROUBLESHOOTING.md](./TROUBLESHOOTING.md)** — Common issues and solutions
- **[BRANCHING.md](./BRANCHING.md)** — Git workflow, release process, CI/CD
- **[contracts/README.md](../contracts/README.md)** — Smart contract details and testing
- **[contracts/ARCHITECTURE.md](../contracts/ARCHITECTURE.md)** — Contract domain boundaries

## Deployment

- **[DEPLOYMENT.md](./DEPLOYMENT.md)** — Step-by-step deployment to testnet and mainnet
- **[contracts/RUNBOOK.md](../contracts/RUNBOOK.md)** — Operational procedures

## Security

- **[SECURITY.md](../SECURITY.md)** — Reporting vulnerabilities
- **[THREAT_MODEL.md](./THREAT_MODEL.md)** — Security assumptions and role compromise impact
- **[KNOWN_ISSUES.md](./KNOWN_ISSUES.md)** — Accepted design decisions and limitations

## Additional Resources

- **[CHANGELOG.md](../CHANGELOG.md)** — Release history and version notes
- **[CONTRIBUTORS.md](../CONTRIBUTORS.md)** — Contributor recognition

## Quick Reference

### Essential Commands

```bash
pnpm dev                          # Start dev environment
cd contracts && make ci-fast      # Quick checks
cd contracts && make ci-full      # Full gate
```

### Architecture Rules

- `bridge` ↔ `settlement`: NO cross-imports
- `pool` ↔ `settlement`: NO cross-imports
- See [contracts/ARCHITECTURE.md](../contracts/ARCHITECTURE.md) for details

### Getting Help

- Check [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) first
- Review [CONTRIBUTING.md](../CONTRIBUTING.md) for standards
- Open an issue for bugs or questions
