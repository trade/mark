# Security Policy

## Reporting a Vulnerability

Use [GitHub private vulnerability reporting](https://github.com/trade/mark/security/advisories/new) to report security issues. This keeps the disclosure private until a fix is ready.

Do not open a public issue for security vulnerabilities.

## Scope

In scope:

- Smart contracts (`contracts/src/`)
- Deployment and operational scripts (`contracts/script/`)
- CI/CD workflows (`.github/workflows/`)

Out of scope:

- The frontend (`src/`) — it is a read-only dev dashboard with no wallet interaction or user funds
- Local development tooling (`supersim`, `super-cli`, `mprocs`)
- Known transitive dependency alerts from `@eth-optimism/super-cli` with no upstream fix available

## Response

- Acknowledgement within 3 business days
- Status update within 7 business days
- Coordinated disclosure after a fix is available or a risk decision is made

## Supported Versions

Only the latest commit on `main` is supported. Pre-production branches (`dev`, `canary`) are not considered production.
