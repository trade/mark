#!/usr/bin/env bash
# Install gitleaks from GitHub releases
# Works on macOS (x86_64/arm64) and Linux (x86_64/arm64)

set -e

VERSION="8.30.1"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"

# Detect OS and architecture
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

case "$ARCH" in
  x86_64) ARCH="x64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

case "$OS" in
  darwin) OS="darwin" ;;
  linux) OS="linux" ;;
  *) echo "Unsupported OS: $OS"; exit 1 ;;
esac

FILENAME="gitleaks_${VERSION}_${OS}_${ARCH}.tar.gz"
URL="https://github.com/gitleaks/gitleaks/releases/download/v${VERSION}/${FILENAME}"

# SHA256 checksums from GitHub releases
# Source: https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_checksums.txt
declare -A CHECKSUMS
CHECKSUMS["gitleaks_8.30.1_darwin_x64.tar.gz"]="dfe101a4db2255fc85120ac7f3d25e4342c3c20cf749f2c20a18081af1952709"
CHECKSUMS["gitleaks_8.30.1_darwin_arm64.tar.gz"]="b40ab0ae55c505963e365f271a8d3846efbc170aa17f2607f13df610a9aeb6a5"
CHECKSUMS["gitleaks_8.30.1_linux_x64.tar.gz"]="551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb"
CHECKSUMS["gitleaks_8.30.1_linux_arm64.tar.gz"]="e4a487ee7ccd7d3a7f7ec08657610aa3606637dab924210b3aee62570fb4b080"

EXPECTED_SHA="${CHECKSUMS[$FILENAME]}"

if [ -z "$EXPECTED_SHA" ]; then
  echo "⚠️  No checksum available for $FILENAME"
  echo "   Skipping SHA256 verification (not recommended)"
  echo "   Verify manually: https://github.com/gitleaks/gitleaks/releases/tag/v${VERSION}"
  read -p "Continue anyway? (y/N) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
  fi
fi

echo "Installing gitleaks v${VERSION} for ${OS}_${ARCH}..."
echo "Download URL: $URL"

# Create install directory
mkdir -p "$INSTALL_DIR"

# Download to temp file
TMP_FILE="$(mktemp)"
trap 'rm -f "$TMP_FILE"' EXIT

echo "Downloading..."
curl -sSfL "$URL" -o "$TMP_FILE"

# Verify SHA256 if available
if [ -n "$EXPECTED_SHA" ]; then
  echo "Verifying SHA256 checksum..."
  
  if command -v shasum >/dev/null 2>&1; then
    ACTUAL_SHA=$(shasum -a 256 "$TMP_FILE" | awk '{print $1}')
  elif command -v sha256sum >/dev/null 2>&1; then
    ACTUAL_SHA=$(sha256sum "$TMP_FILE" | awk '{print $1}')
  else
    echo "⚠️  sha256sum/shasum not found, skipping verification"
    ACTUAL_SHA="$EXPECTED_SHA"  # Skip check
  fi
  
  if [ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]; then
    echo "✗ SHA256 mismatch!"
    echo "  Expected: $EXPECTED_SHA"
    echo "  Got:      $ACTUAL_SHA"
    echo "  This could indicate a compromised download."
    exit 1
  fi
  
  echo "✓ SHA256 verified"
fi

# Extract
echo "Extracting..."
tar -xzf "$TMP_FILE" -C "$INSTALL_DIR" gitleaks

# Verify installation
if [ -x "$INSTALL_DIR/gitleaks" ]; then
  echo "✓ gitleaks installed to $INSTALL_DIR/gitleaks"
  echo ""
  
  # Check if in PATH
  if echo "$PATH" | grep -q "$INSTALL_DIR"; then
    echo "✓ $INSTALL_DIR is in your PATH"
    "$INSTALL_DIR/gitleaks" version
  else
    echo "⚠️  Add to PATH: export PATH=\"$INSTALL_DIR:\$PATH\""
    echo "   Add this to your ~/.bashrc or ~/.zshrc"
  fi
else
  echo "✗ Installation failed"
  exit 1
fi
