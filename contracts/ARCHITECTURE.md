# Contracts Architecture

## Domains

- `src/token`: token primitives (`RYLA`).
- `src/bridge`: bridge adapter domain.
- `src/settlement`: settlement module + verifier domain.
- `src/errors`: shared error types.

## Dependency Rules

- `src/bridge/**` must not import from `src/settlement/**`.
- `src/settlement/**` must not import from `src/bridge/**`.
- Cross-domain sharing should be done through narrow interfaces and shared types only.
- `src/token/**` is an allowed dependency for both bridge and settlement domains.

## Enforcement

- CI runs `make architecture-guard`.
- Guard implementation: `script/ci/architecture-guard.sh`.
- CI runs `make layering-guard`.
- Guard implementation: `script/ci/layering-guard.sh`.
- Any forbidden cross-domain import causes CI failure.
