#!/bin/bash
# Claude Tap - Update script
#
# Checks for updates by comparing the local VERSION file against
# the remote VERSION on GitHub. Optionally pulls and re-installs.
#
# Usage:
#   ./scripts/update.sh              # Check and update
#   ./scripts/update.sh --check-only # Just check, don't update

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION_FILE="$REPO_DIR/VERSION"
REMOTE_URL="https://raw.githubusercontent.com/EdoardoCroci/claude-tap/main/VERSION"

# ──────────────────────────────────────────────────────────────
# Colors
# ──────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info()    { echo -e "${CYAN}[info]${RESET}  $1"; }
success() { echo -e "${GREEN}[ok]${RESET}    $1"; }
warn()    { echo -e "${YELLOW}[warn]${RESET}  $1"; }
fail()    { echo -e "${RED}[error]${RESET} $1"; exit 1; }

# ──────────────────────────────────────────────────────────────
# Parse arguments
# ──────────────────────────────────────────────────────────────

CHECK_ONLY="false"
while [ $# -gt 0 ]; do
    case "$1" in
        --check-only) CHECK_ONLY="true"; shift ;;
        -h|--help)
            echo "Usage: update.sh [--check-only]"
            echo "  --check-only    Only check for updates, don't install"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# ──────────────────────────────────────────────────────────────
# Read local version
# ──────────────────────────────────────────────────────────────

if [ ! -f "$VERSION_FILE" ]; then
    fail "VERSION file not found at $VERSION_FILE"
fi

LOCAL_VERSION=$(tr -d '[:space:]' < "$VERSION_FILE")

# Validate version format (semver: X.Y.Z)
if ! echo "$LOCAL_VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    fail "Invalid local version format: '$LOCAL_VERSION' (expected X.Y.Z)"
fi

info "Local version: ${BOLD}$LOCAL_VERSION${RESET}"

# ──────────────────────────────────────────────────────────────
# Fetch remote version
# ──────────────────────────────────────────────────────────────

info "Checking for updates..."

REMOTE_VERSION=$(curl --fail --silent --max-time 5 "$REMOTE_URL" 2>/dev/null | tr -d '[:space:]') || {
    warn "Could not reach update server. Skipping update check."
    exit 0
}

# Validate remote version format
if ! echo "$REMOTE_VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    warn "Invalid remote version format: '$REMOTE_VERSION'. Skipping update check."
    exit 0
fi

info "Remote version: ${BOLD}$REMOTE_VERSION${RESET}"

# ──────────────────────────────────────────────────────────────
# Compare versions (semver-aware)
# ──────────────────────────────────────────────────────────────

version_gt() {
    # Returns 0 if $1 > $2 (semver comparison)
    local IFS=.
    local i v1=($1) v2=($2)
    for ((i=0; i<3; i++)); do
        if [ "${v1[i]:-0}" -gt "${v2[i]:-0}" ]; then return 0; fi
        if [ "${v1[i]:-0}" -lt "${v2[i]:-0}" ]; then return 1; fi
    done
    return 1  # equal
}

if ! version_gt "$REMOTE_VERSION" "$LOCAL_VERSION"; then
    success "You are up to date (${BOLD}$LOCAL_VERSION${RESET})"
    exit 0
fi

echo ""
echo -e "  ${YELLOW}Update available:${RESET} ${BOLD}$LOCAL_VERSION${RESET} → ${BOLD}$REMOTE_VERSION${RESET}"
echo ""

if [ "$CHECK_ONLY" = "true" ]; then
    echo -e "  Run ${CYAN}./scripts/update.sh${RESET} to update."
    exit 0
fi

# ──────────────────────────────────────────────────────────────
# Pull and re-install
# ──────────────────────────────────────────────────────────────

info "Pulling latest changes..."
cd "$REPO_DIR"
git pull || fail "git pull failed. Resolve any conflicts and try again."

# Detect OS and re-run the appropriate installer
OS="$(uname -s)"
case "$OS" in
    Darwin)
        info "Re-running macOS installer..."
        "$REPO_DIR/macos/install.sh"
        ;;
    Linux)
        if [ -f "$REPO_DIR/linux/install.sh" ]; then
            info "Re-running Linux installer..."
            "$REPO_DIR/linux/install.sh"
        else
            warn "Linux installer not found. Pull complete - run install manually."
        fi
        ;;
    *)
        warn "Unknown OS '$OS'. Pull complete - run the appropriate installer manually."
        ;;
esac

echo ""
success "Updated to ${BOLD}$REMOTE_VERSION${RESET}"
