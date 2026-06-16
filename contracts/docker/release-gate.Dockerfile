FROM ghcr.io/foundry-rs/foundry:nightly-a0b37374f5bad527749da20bf4550dd51f34e8bc@sha256:b931fe558985857a454a953cd1684202dffc4e417e45c30487cfe57656b0f6f0
# Tag includes Foundry commit SHA (a0b37374f5bad527749da20bf4550dd51f34e8bc)
# Pinned by sha256 digest for reproducible builds (Scorecard Pinned-Dependencies)

USER root

RUN apt-get update \
  && apt-get install -y --no-install-recommends curl git jq python3 python3-pip ca-certificates \
  && rm -rf /var/lib/apt/lists/*

# Pin Node + pnpm for deterministic JS tooling in CI steps.
# NodeSource only provides major version setup scripts (setup_22.x); patch version
# is controlled by the apt repository. We pin the nodejs package explicitly.
# Ubuntu 22.04 nodejs=22.14.0-1nodesource1 (resolved at build time)
# sha256: 575583bbac2fccc0b5edd0dbc03e222d9f9dc8d724da996d22754d6411104fd1
RUN nodesource_script=$(mktemp) \
  && curl -fsSL https://deb.nodesource.com/setup_22.x > "$nodesource_script" \
  && echo "575583bbac2fccc0b5edd0dbc03e222d9f9dc8d724da996d22754d6411104fd1  $nodesource_script" | sha256sum -c - \
  && bash "$nodesource_script" \
  && rm -f "$nodesource_script" \
  && apt-get update \
  && apt-get install -y --no-install-recommends nodejs=22.14.0-1nodesource1 \
  && corepack enable \
  && corepack prepare pnpm@9.0.2 --activate

# Slither analyzer is required by mainnet-readiness/release hardening checks.
# Installed from a fully hash-pinned requirements file (the whole transitive
# tree, resolved for Python 3.10). --require-hashes rejects an install unless
# every requirement, including transitive deps, carries a hash, so pinning only
# slither-analyzer on the command line cannot satisfy it.
COPY contracts/docker/slither-requirements.txt /tmp/slither-requirements.txt
RUN python3 -m pip install --no-cache-dir --upgrade pip \
  && python3 -m pip install --no-cache-dir --require-hashes \
  -r /tmp/slither-requirements.txt \
  && rm -f /tmp/slither-requirements.txt

# Create non-root user for CI execution
RUN useradd --create-home --shell /bin/bash appuser \
  && chown -R appuser:appuser /repo 2>/dev/null || true

USER appuser

WORKDIR /repo/contracts