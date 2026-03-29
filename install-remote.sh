#!/bin/bash
# Claude Tap - Remote installer
#
# One-liner install:
#   curl -fsSL https://raw.githubusercontent.com/EdoardoCroci/claude-tap/main/install-remote.sh | bash
#
# This script clones (or updates) the repo and runs the platform-appropriate installer.

set -e

REPO="https://github.com/EdoardoCroci/claude-tap.git"
INSTALL_DIR="$HOME/.local/share/claude-tap"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

echo ""
echo -e "${BOLD}Claude Tap - Remote Installer${RESET}"
echo ""

# Check for git
if ! command -v git &>/dev/null; then
    echo -e "${RED}[error]${RESET} git is required. Install it first."
    exit 1
fi

# Clone or update
if [ -d "$INSTALL_DIR/.git" ]; then
    echo -e "${CYAN}[info]${RESET}  Updating existing installation..."
    git -C "$INSTALL_DIR" pull --ff-only || {
        echo -e "${RED}[error]${RESET} git pull failed. Try deleting $INSTALL_DIR and re-running."
        exit 1
    }
else
    echo -e "${CYAN}[info]${RESET}  Cloning repository..."
    mkdir -p "$(dirname "$INSTALL_DIR")"
    git clone --depth 1 "$REPO" "$INSTALL_DIR"
fi

# Detect OS and run installer
OS="$(uname -s)"
case "$OS" in
    Darwin)
        echo -e "${GREEN}[ok]${RESET}    Running macOS installer..."
        echo ""
        "$INSTALL_DIR/macos/install.sh"
        ;;
    Linux)
        echo -e "${GREEN}[ok]${RESET}    Running Linux installer..."
        echo ""
        "$INSTALL_DIR/linux/install.sh"
        ;;
    *)
        echo -e "${RED}[error]${RESET} Unsupported OS: $OS"
        echo "  For Windows, see: https://github.com/EdoardoCroci/claude-tap#windows-not-currently-tested"
        exit 1
        ;;
esac
