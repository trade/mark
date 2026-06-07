FROM ghcr.io/foundry-rs/foundry:latest

USER root

RUN apt-get update \
  && apt-get install -y --no-install-recommends curl git jq python3 python3-pip ca-certificates \
  && rm -rf /var/lib/apt/lists/*

# Pin Node + pnpm for deterministic JS tooling in CI steps.
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
  && apt-get update \
  && apt-get install -y --no-install-recommends nodejs \
  && corepack enable \
  && corepack prepare pnpm@9.0.2 --activate

# Slither analyzer is required by mainnet-readiness/release hardening checks.
RUN python3 -m pip install --no-cache-dir slither-analyzer==0.11.5

# Create non-root user for CI execution
RUN useradd --create-home --shell /bin/bash appuser \
  && chown -R appuser:appuser /repo 2>/dev/null || true

USER appuser

WORKDIR /repo/contracts