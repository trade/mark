FROM ghcr.io/foundry-rs/foundry:nightly-a0b37374f5bad527749da20bf4550dd51f34e8bc
# Tag includes Foundry commit SHA (a0b37374f5bad527749da20bf4550dd51f34e8bc)
# For full digest pinning, resolve sha256:<digest> in CI and update FROM line

USER root

RUN apt-get update \
  && apt-get install -y --no-install-recommends curl git jq python3 python3-pip ca-certificates \
  && rm -rf /var/lib/apt/lists/*

# Pin Node + pnpm for deterministic JS tooling in CI steps.
# NodeSource only provides major version setup scripts (setup_22.x); patch version
# is controlled by the apt repository. We pin the nodejs package explicitly.
# Ubuntu 22.04 nodejs=22.14.0-1nodesource1 (resolved at build time)
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
  && apt-get update \
  && apt-get install -y --no-install-recommends nodejs=22.14.0-1nodesource1 \
  && corepack enable \
  && corepack prepare pnpm@9.0.2 --activate

# Slither analyzer is required by mainnet-readiness/release hardening checks.
# Pinned to specific version
RUN python3 -m pip install --no-cache-dir slither-analyzer==0.11.5

# Create non-root user for CI execution
RUN useradd --create-home --shell /bin/bash appuser \
  && chown -R appuser:appuser /repo 2>/dev/null || true

USER appuser

WORKDIR /repo/contracts