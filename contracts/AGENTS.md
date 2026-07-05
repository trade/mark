# Contracts (agent notes)

Parent runbook: [`../AGENTS.md`](../AGENTS.md). Architecture: [`ARCHITECTURE.md`](ARCHITECTURE.md).

## Fast loop (agents)

```bash
cd contracts
FOUNDRY_PROFILE=default make architecture-guard layering-guard
FOUNDRY_PROFILE=default forge test --no-match-path 'test/{invariant,integration}/**'
```

`.mise.toml` sets `FOUNDRY_PROFILE=ci` in the repo shell — override with `FOUNDRY_PROFILE=default` for local iteration.

## Scoped tests

```bash
FOUNDRY_PROFILE=default forge test --match-path 'test/unit/**/*.t.sol'
FOUNDRY_PROFILE=default forge test --match-contract CrossChainDoubleSpend
```

## Pre-PR

```bash
make ci-fast    # guards + core tests (no invariants)
make ci-full    # + invariants + production-lock checks
```

From repo root, use `mise run ci-fast` for the root local pipeline or `pnpm contracts:ci-full` for the contract full gate. Root `package.json` does not define `contracts:ci-fast`.

## Integration / reorg

```bash
mise run reorg-sim    # needs OP_SEPOLIA_RPC
```
