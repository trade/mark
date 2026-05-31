#!/usr/bin/env bash
# MARK Protocol bootstrap script
# Installs/verifies all prerequisites for local development.

set -euo pipefail

# Default install directory for user‑local binaries
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
mkdir -p "$INSTALL_DIR"

# Helper functions
info() { echo -e "[\033[1;34mINFO\033[0m] $*"; }
success() { echo -e "[\033[1;32mOK\033[0m] $*"; }
warning() { echo -e "[\033[1;33mWARN\033[0m] $*"; }
error() { echo -e "[\033[1;31mERROR\033[0m] $*" >&2; }

# ---- Detect OS/Arch -------------------------------------------------
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64) ARCH="x64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *) error "Unsupported architecture: $ARCH"; exit 1 ;;
esac

case "$OS" in
  darwin) OS="darwin" ;;
  linux) OS="linux" ;;
  *) error "Unsupported OS: $OS"; exit 1 ;;
esac

# ---- Node.js 24 via mise -------------------------------------------
info "Checking Node.js 24 (via mise)..."
if ! command -v mise &>/dev/null; then
  info "mise not found – installing via Homebrew (macOS) or official script..."
  if [[ "$OS" == "darwin" ]]; then
    if ! command -v brew &>/dev/null; then
      error "Homebrew required to install mise on macOS. Install brew first: https://brew.sh"
      exit 1
    fi
    brew install mise
  else
    # Linux: use the official install script
    curl https://mise.run | sh
    # mise will be added to ~/.local/bin; ensure it's in PATH for this session
    export PATH="$HOME/.local/bin:$PATH"
  fi
fi

# Ensure Node.js 24 is installed and set as global
if ! mise ls node | grep -q "24"; then
  info "Installing Node.js 24 via mise..."
  mise use -g node@24
else
  success "Node.js 24 already managed by mise"
fi
# Make sure the node from mise is in PATH
eval "$(mise activate bash)"

# ---- pnpm 9.x via corepack -----------------------------------------
info "Checking pnpm (via corepack)..."
# corepack ships with Node; ensure it's enabled
corepack enable
# Ensure we have the desired version
if ! pnpm --version | grep -q "^9\."; then
  info "Setting up pnpm 9.x via corepack..."
  corepack prepare pnpm@9.0.2 --activate
else
  success "pnpm 9.x ready"
fi

# ---- Foundry -------------------------------------------------------
info "Checking Foundry..."
if ! command -v forge &>/dev/null || ! forge --version | grep -q "0.2.0"; then
  info "Installing Foundry..."
  curl -L https://foundry.paradigm.xyz | bash
  # The installer adds ~/.foundry/bin to PATH in the shell profile; source it for this session
  if [[ -f "$HOME/.bashrc" ]]; then
    # shellcheck source=/dev/null
    source "$HOME/.bashrc" 2>/dev/null || true
  fi
  if [[ -f "$HOME/.zshrc" ]]; then
    # shellcheck source=/dev/null
    source "$HOME/.zshrc" 2>/dev/null || true
  fi
else
  success "Foundry up-to-date"
fi

# ---- super-cli -----------------------------------------------------
info "Checking super-cli..."
if ! command -v super &>/dev/null || ! super --version | grep -q "0.4.0"; then
  info "Installing super-cli via npm..."
  npm install -g @ethereum-optimism/super-cli
else
  success "super-cli ready"
fi

# ---- mise (already handled via Node.js check) ----------------------
if command -v mise &>/dev/null; then
  success "mise is available"
else
  error "mise installation failed"
  exit 1
fi

# ---- Optional: gitleaks --------------------------------------------
info "Checking optional gitleaks (recommended)..."
if ! command -v gitleaks &>/dev/null; then
  warning "gitleaks not found – installing via script..."
  # Re-use the existing installer but avoid duplicate effort
  if [[ -x "./scripts/install-gitleaks.sh" ]]; then
    ./scripts/install-gitleaks.sh
  else
    # Fallback: download and run the installer inline
    curl -fsSL https://raw.githubusercontent.com/trade/mark/master/scripts/install-gitleaks.sh | bash
  fi
else
  success "gitleaks available"
fi

# ---- Final summary -------------------------------------------------
echo
success "All prerequisites are satisfied!"
echo
info "Next steps:"
echo "  git clone https://github.com/trade/mark.git  (if you haven't already)"
echo "  cd mark"
echo "  pnpm install"
echo "  pnpm dev   # start local Superchain + frontend"
echo
info "Tip: You can re-run this script anytime to update tools."
echo
