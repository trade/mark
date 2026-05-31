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
  --check)  CHECK_ONLY=true ;;
  --help|-h)
    sed -n '2,8p' "$0" | sed 's/^# \?//'
    exit 0
    ;;
  "")
    ;;
  *)
    echo "Unknown option: $1" >&2
    echo "Usage: $0 [--check|--help]" >&2
    exit 1
    ;;
esac

# Helper functions
info()    { echo -e "[\033[1;34mINFO\033[0m]  $*"; }
success() { echo -e "[\033[1;32mOK\033[0m]    $*"; }
warning() { echo -e "[\033[1;33mWARN\033[0m]  $*"; }
error()   { echo -e "[\033[1;31mERROR\033[0m] $*" >&2; }
skip()    { echo -e "[\033[1;36mSKIP\033[0m]  $*"; }

# ---- Detect OS/Arch -------------------------------------------------
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64)    ARCH_LABEL="x64" ;;
  aarch64|arm64) ARCH_LABEL="arm64" ;;
  *) error "Unsupported architecture: $ARCH"; exit 1 ;;
esac

case "$OS" in
  darwin) OS_LABEL="macos" ;;
  linux)  OS_LABEL="linux" ;;
  *) error "Unsupported OS: $OS"; exit 1 ;;
esac

info "Detected: ${OS_LABEL}-${ARCH_LABEL}"
echo

# Track results for summary
OK=()
WARN=()
FAIL=()

record_ok()    { OK+=("$1"); }
record_warn()  { WARN+=("$1"); }
record_fail()  { FAIL+=("$1"); }

# ---- mise (installs and manages Node.js) ---------------------------
info "Checking mise..."
if command -v mise &>/dev/null; then
  success "mise already installed ($(mise --version | awk '{print $1}'))"
  record_ok "mise"
else
  if $CHECK_ONLY; then
    skip "mise not installed"
    record_warn "mise (not installed)"
  else
    info "Installing mise via official script..."
    set +o pipefail
    curl https://mise.run | sh
    local_mise_ok=$?
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

# ---- Foundry -------------------------------------------------------
FOUNDRY_BIN="$HOME/.foundry/bin"
info "Checking Foundry..."
if command -v forge &>/dev/null; then
  success "Foundry available ($(forge --version | head -1))"
  record_ok "foundry"
elif $CHECK_ONLY; then
  skip "Foundry not installed"
  record_warn "foundry (not installed)"
else
  info "Installing Foundry..."
  curl -L https://foundry.paradigm.xyz | bash
  # Source the updated PATH
  export PATH="$FOUNDRY_BIN:$PATH"
  if [[ -f "$HOME/.bashrc" ]]; then source "$HOME/.bashrc" 2>/dev/null || true; fi
  if [[ -f "$HOME/.zshrc" ]]; then source "$HOME/.zshrc" 2>/dev/null || true; fi
  # Run foundryup
  if [[ -x "$FOUNDRY_BIN/foundryup" ]]; then
    "$FOUNDRY_BIN/foundryup"
  fi
  if command -v forge &>/dev/null; then
    success "Foundry installed ($(forge --version | head -1))"
    record_ok "foundry"
  else
    error "Foundry installation may have failed — restart your shell and run 'foundryup'"
    record_warn "foundry (needs shell restart)"
  fi
fi

# ---- super-cli -----------------------------------------------------
info "Checking super-cli..."
if command -v super &>/dev/null; then
  success "super-cli ($(super --version 2>&1 | head -1))"
  record_ok "super-cli"
elif $CHECK_ONLY; then
  skip "super-cli not installed"
  record_warn "super-cli (not installed)"
else
  if command -v npm &>/dev/null; then
    info "Installing super-cli via npm..."
    npm install -g @ethereum-optimism/super-cli && {
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
info "Checking uv..."
if command -v uv &>/dev/null; then
  success "uv ($(uv --version | awk '{print $1}'))"
  record_ok "uv"
elif $CHECK_ONLY; then
  skip "uv not installed"
  record_warn "uv (not installed)"
else
  info "Installing uv via astral.sh..."
  set +o pipefail
  curl -LsSf https://astral.sh/uv/install.sh | sh
  local_uv_ok=$?
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

# ---- Optional: gitleaks --------------------------------------------
info "Checking gitleaks (optional)..."
if command -v gitleaks &>/dev/null; then
  success "gitleaks ($(gitleaks --version 2>&1 | head -1))"
  record_ok "gitleaks"
elif $CHECK_ONLY; then
  skip "gitleaks not installed"
  record_warn "gitleaks (not installed)"
else
  warning "gitleaks not found — installing..."
  if [[ -x "./scripts/install-gitleaks.sh" ]]; then
    ./scripts/install-gitleaks.sh && {
      success "gitleaks installed"
      record_ok "gitleaks"
    } || {
      record_warn "gitleaks (install failed)"
    }
  else
    # Download the installer from the repo
    TMP_INSTALLER="$(mktemp)"
    if curl -fsSL "https://raw.githubusercontent.com/trade/mark/master/scripts/install-gitleaks.sh" -o "$TMP_INSTALLER"; then
      bash "$TMP_INSTALLER"
      if command -v gitleaks &>/dev/null; then
        success "gitleaks installed"
        record_ok "gitleaks"
      else
        record_warn "gitleaks (install may have failed)"
      fi
    else
      warning "Could not download gitleaks installer"
      record_warn "gitleaks (download failed)"
    fi
    rm -f "$TMP_INSTALLER"
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
