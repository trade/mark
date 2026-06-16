#!/usr/bin/env bash
# MARK Protocol bootstrap script
# Installs/verifies all prerequisites for local development.
#
# Usage:
#   ./scripts/bootstrap.sh          # install/verify everything
#   ./scripts/bootstrap.sh --check  # only check, don't install anything
#   ./scripts/bootstrap.sh --help   # show this help

set -euo pipefail

# Default install directory for user‑local binaries
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
mkdir -p "$INSTALL_DIR"

# Parse args
CHECK_ONLY=false
case "${1:-}" in
  --check) CHECK_ONLY=true ;;
  --help | -h)
    sed -n '2,8p' "$0" | sed 's/^# \?//'
    exit 0
    ;;
  "") ;;
  *)
    echo "Unknown option: $1" >&2
    echo "Usage: $0 [--check|--help]" >&2
    exit 1
    ;;
esac

# Helper functions
info() { echo -e "[\033[1;34mINFO\033[0m]  $*"; }
success() { echo -e "[\033[1;32mOK\033[0m]    $*"; }
warning() { echo -e "[\033[1;33mWARN\033[0m]  $*"; }
error() { echo -e "[\033[1;31mERROR\033[0m] $*" >&2; }
skip() { echo -e "[\033[1;36mSKIP\033[0m]  $*"; }

# ---- Detect OS/Arch -------------------------------------------------
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64) ARCH_LABEL="x64" ;;
  aarch64 | arm64) ARCH_LABEL="arm64" ;;
  *)
    error "Unsupported architecture: $ARCH"
    exit 1
    ;;
esac

case "$OS" in
  darwin) OS_LABEL="macos" ;;
  linux) OS_LABEL="linux" ;;
  *)
    error "Unsupported OS: $OS"
    exit 1
    ;;
esac

info "Detected: ${OS_LABEL}-${ARCH_LABEL}"
echo

# Track results for summary
OK=()
WARN=()
FAIL=()

record_ok() { OK+=("$1"); }
record_warn() { WARN+=("$1"); }
record_fail() { FAIL+=("$1"); }

# ---- mise (installs and manages Node.js) ---------------------------
# Pin to version tag for mise.run installer compatibility (v2026.5.11)
# Commit: 5687a3f823c6324509a0fde013c0c6b504d803ef
MISE_VERSION="2026.5.11"
info "Checking mise..."
if command -v mise &>/dev/null; then
  success "mise already installed ($(mise --version | awk '{print $1}'))"
  record_ok "mise"
else
  if $CHECK_ONLY; then
    skip "mise not installed"
    record_warn "mise (not installed)"
  else
    info "Installing mise via official script (pinned to v$MISE_VERSION)..."
    # sha256: aad081ff2ae662b051c64341057dd759b3b79dc6b841d593832bdeb9e2726fd8
    set +o pipefail
    mise_script=$(mktemp)
    curl -fsSL https://mise.run > "$mise_script"
    echo "aad081ff2ae662b051c64341057dd759b3b79dc6b841d593832bdeb9e2726fd8  $mise_script" | sha256sum -c -
    MISE_VERSION="$MISE_VERSION" sh "$mise_script"
    local_mise_ok=$?
    rm -f "$mise_script"
    set -o pipefail
    export PATH="$HOME/.local/bin:$PATH"
    if [[ $local_mise_ok -eq 0 ]] && command -v mise &>/dev/null; then
      success "mise installed ($(mise --version | awk '{print $1}'))"
      record_ok "mise"
    else
      error "mise installation failed (exit code: $local_mise_ok)"
      record_fail "mise"
    fi
  fi
fi
# Make mise available in this session
if command -v mise &>/dev/null; then
  eval "$(mise activate bash 2>/dev/null || true)"
  export PATH="$(mise bin-paths 2>/dev/null || echo "$HOME/.local/bin"):$PATH"
fi

# ---- Node.js 24 via mise -------------------------------------------
info "Checking Node.js..."
if command -v mise &>/dev/null; then
  if mise ls node 2>/dev/null | grep -q "24"; then
    success "Node.js 24 configured in mise"
    record_ok "node"
  elif $CHECK_ONLY; then
    skip "Node.js 24 not configured in mise"
    record_warn "node (not configured)"
  else
    info "Installing Node.js 24 via mise..."
    mise use -g node@24 && {
      success "Node.js 24 installed and set as global"
      record_ok "node"
    } || {
      record_fail "node"
    }
  fi
else
  warning "Skipping Node.js check — mise not available"
  record_warn "node (mise unavailable)"
fi

# ---- pnpm 9.x via corepack -----------------------------------------
info "Checking pnpm..."
if command -v pnpm &>/dev/null && pnpm --version | grep -q "^9\."; then
  success "pnpm 9.x ready ($(pnpm --version))"
  record_ok "pnpm"
elif $CHECK_ONLY; then
  skip "pnpm 9.x not available"
  record_warn "pnpm (not available)"
else
  # corepack ships with Node.js; enable it
  if command -v corepack &>/dev/null; then
    corepack enable
    corepack prepare pnpm@9.0.2 --activate && {
      success "pnpm 9.x ready ($(pnpm --version))"
      record_ok "pnpm"
    } || {
      record_fail "pnpm"
    }
  else
    warning "corepack not available — install Node.js 24 first"
    record_warn "pnpm (corepack unavailable)"
  fi
fi

# ---- Foundry (via mise) --------------------------------------------
info "Checking Foundry..."
if command -v forge &>/dev/null; then
  success "Foundry available ($(forge --version | head -1))"
  record_ok "foundry"
elif $CHECK_ONLY; then
  skip "Foundry not installed (will be installed by: mise install foundry)"
  record_warn "foundry (not installed)"
else
  if command -v mise &>/dev/null; then
    info "Installing Foundry via mise..."
    mise install foundry && {
      eval "$(mise activate bash 2>/dev/null || true)"
      success "Foundry installed ($(forge --version | head -1))"
      record_ok "foundry"
    } || {
      error "Foundry installation failed"
      record_fail "foundry"
    }
  else
    warning "mise not available — install foundry manually: https://book.getfoundry.sh/getting-started/installation"
    record_warn "foundry (mise unavailable)"
  fi
fi

# ---- super-cli -----------------------------------------------------
# Pin to commit SHA for reproducibility (no tagged releases yet)
SUPER_CLI_COMMIT="57288e4b634159f8705e9d686de5d50768adb15a"
info "Checking super-cli..."
if command -v super &>/dev/null; then
  success "super-cli ($(super --version 2>&1 | head -1))"
  record_ok "super-cli"
elif $CHECK_ONLY; then
  skip "super-cli not installed"
  record_warn "super-cli (not installed)"
else
  if command -v npm &>/dev/null; then
    info "Installing super-cli via npm (pinned to commit $SUPER_CLI_COMMIT)..."
    npm install -g "https://github.com/ethereum-optimism/super-cli.git#${SUPER_CLI_COMMIT}" && {
      success "super-cli installed"
      record_ok "super-cli"
    } || {
      record_fail "super-cli"
    }
  else
    warning "npm not available — install Node.js 24 first"
    record_warn "super-cli (npm unavailable)"
  fi
fi

# ---- uv (Python package manager) -----------------------------------
# Pin to versioned installer from GitHub releases (v0.5.4)
# Commit: c62c83c37ada63eae4efb77551e2ec7a0f0113d8
# Installer: https://github.com/astral-sh/uv/releases/download/0.5.4/uv-installer.sh
# SHA256: a1b2c3d4e5f6... (verify at release page before updating)
UV_VERSION="0.5.4"
info "Checking uv..."
if command -v uv &>/dev/null; then
  success "uv ($(uv --version | awk '{print $1}'))"
  record_ok "uv"
elif $CHECK_ONLY; then
  skip "uv not installed"
  record_warn "uv (not installed)"
else
  info "Installing uv via GitHub releases (pinned to v$UV_VERSION)..."
  # sha256: 4c99c45e4727adb1c36da70779c4f2a51b19197ea44aa8a89656d2e9bc793eeb
  set +o pipefail
  uv_script=$(mktemp)
  curl -fsSL "https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-installer.sh" > "$uv_script"
  echo "4c99c45e4727adb1c36da70779c4f2a51b19197ea44aa8a89656d2e9bc793eeb  $uv_script" | sha256sum -c -
  sh "$uv_script"
  local_uv_ok=$?
  rm -f "$uv_script"
  set -o pipefail
  export PATH="$HOME/.local/bin:$PATH"
  if [[ $local_uv_ok -eq 0 ]] && command -v uv &>/dev/null; then
    success "uv installed ($(uv --version | awk '{print $1}'))"
    record_ok "uv"
  else
    error "uv installation failed (exit code: $local_uv_ok)"
    record_fail "uv"
  fi
fi

# ---- Summary -------------------------------------------------------
echo
echo "========================================"
if [[ ${#FAIL[@]} -eq 0 && ${#WARN[@]} -eq 0 ]]; then
  success "All prerequisites satisfied!"
elif [[ ${#FAIL[@]} -eq 0 ]]; then
  echo "Core tools ready. ${#WARN[@]} optional item(s) skipped."
else
  echo "Some tools need attention."
fi

if [[ ${#OK[@]} -gt 0 ]]; then
  echo
  echo "Installed/verified:"
  for t in "${OK[@]}"; do echo "  ✓ $t"; done
fi

if [[ ${#WARN[@]} -gt 0 ]]; then
  echo
  echo "Skipped/warnings:"
  for t in "${WARN[@]}"; do echo "  ○ $t"; done
fi

if [[ ${#FAIL[@]} -gt 0 ]]; then
  echo
  echo "Failed:"
  for t in "${FAIL[@]}"; do echo "  ✗ $t"; done
fi

echo
if [[ ${#FAIL[@]} -eq 0 && ${#WARN[@]} -eq 0 ]]; then
  info "Next steps:"
  echo "  pnpm install"
  echo "  pnpm dev      # start local Superchain + frontend"
  echo
  echo "First time here? Run the tutorial:"
  echo "  pnpm dev      # in one terminal"
  echo "  docs/TUTORIAL.md"
else
  echo "Re-run this script after addressing the items above."
fi
echo "Tip: Re-running this script is safe — it checks before installing."
echo

# Exit with error if any required tools failed
if [[ ${#FAIL[@]} -gt 0 ]]; then
  exit 1
fi
