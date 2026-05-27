# Gitleaks Installation Script

Quick installer for gitleaks (secrets detection tool).

## Usage

```bash
bash scripts/install-gitleaks.sh
```

## What It Does

1. Detects your OS (macOS/Linux) and architecture (x86_64/arm64)
2. Downloads gitleaks v8.30.1 from GitHub releases
3. **Verifies SHA256 checksum** (prevents compromised downloads)
4. Installs to `~/.local/bin/gitleaks`
5. Verifies installation

## Supported Platforms

- ✅ macOS (Intel x86_64)
- ✅ macOS (Apple Silicon arm64)
- ✅ Linux (x86_64)
- ✅ Linux (arm64)

## Custom Install Location

```bash
INSTALL_DIR=/usr/local/bin bash scripts/install-gitleaks.sh
```

## Verify Installation

```bash
gitleaks version
# Should output: 8.30.1
```

## Add to PATH

If `~/.local/bin` is not in your PATH:

```bash
# Add to ~/.bashrc or ~/.zshrc
export PATH="$HOME/.local/bin:$PATH"

# Reload shell
source ~/.bashrc  # or source ~/.zshrc
```

## Alternative Installation Methods

**macOS (Homebrew)**:
```bash
brew install gitleaks
```

**macOS (MacPorts)**:
```bash
sudo port install gitleaks
```

**Linux (package manager)**:
```bash
# Arch
yay -S gitleaks

# Debian/Ubuntu (manual)
wget https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_linux_x64.tar.gz
tar -xzf gitleaks_8.30.1_linux_x64.tar.gz
sudo mv gitleaks /usr/local/bin/
```

## Why Gitleaks?

Gitleaks scans for secrets (API keys, passwords, tokens) in your code before you commit them. It runs automatically in the pre-commit hook if installed.

**Without gitleaks**: Secrets are caught in CI (after push)  
**With gitleaks**: Secrets are caught before commit (earlier detection)

## Security

The installation script verifies SHA256 checksums from the official GitHub release:
- Source: https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_checksums.txt
- Prevents compromised or tampered downloads
- Fails installation if checksum doesn't match
