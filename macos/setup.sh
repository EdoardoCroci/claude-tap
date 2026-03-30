#!/bin/bash
# Claude Tap - Non-interactive setup
#
# Performs all non-interactive setup steps:
#   1. Creates ~/.config/claude-tap/ and copies assets
#   2. Writes default config.json (only if none exists)
#   3. Compiles the Swift notification binary
#   4. Makes hook scripts executable
#   5. Registers Claude Code hooks in ~/.claude/settings.json
#
# Called by: Homebrew post_install, install.sh, or manually.
#
# Usage: setup.sh [BASE_DIR] [--quiet]
#   BASE_DIR  = root of the claude-tap repo/install (default: parent of this script)
#   --quiet   = suppress informational output

BASE_DIR="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
QUIET=""
for arg in "$@"; do [ "$arg" = "--quiet" ] && QUIET="1"; done

CONFIG_DIR="$HOME/.config/claude-tap"
CLAUDE_DIR="$HOME/.claude"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
SCRIPT_DIR="$BASE_DIR/macos"

# ──────────────────────────────────────────────────────────────
# Output helpers (silenced with --quiet, except errors/warnings)
# ──────────────────────────────────────────────────────────────

_info()    { [ -z "$QUIET" ] && echo -e "\033[0;36m[info]\033[0m  $1" || true; }
_success() { [ -z "$QUIET" ] && echo -e "\033[0;32m[ok]\033[0m    $1" || true; }
_warn()    { echo -e "\033[0;33m[warn]\033[0m  $1" >&2; }
_err()     { echo -e "\033[0;31m[error]\033[0m $1" >&2; }

ERRORS=0

# ──────────────────────────────────────────────────────────────
# Validate BASE_DIR has expected files
# ──────────────────────────────────────────────────────────────

if [ ! -d "$BASE_DIR" ]; then
    _err "BASE_DIR does not exist: $BASE_DIR"
    exit 1
fi

for required in "assets/claude-icon.png" "assets/sounds/default.wav" "assets/themes.json" \
                "config.example.json" "macos/src/notify.sh" "macos/src/statusline.sh"; do
    if [ ! -f "$BASE_DIR/$required" ]; then
        _err "Missing required file: $BASE_DIR/$required"
        ERRORS=1
    fi
done

if [ "$ERRORS" = "1" ]; then
    _err "Setup aborted - required files missing from $BASE_DIR"
    exit 1
fi

# ──────────────────────────────────────────────────────────────
# Resolve hook paths (use Homebrew /opt symlink if in Cellar)
# ──────────────────────────────────────────────────────────────

HOOK_BASE="$BASE_DIR"
if [[ "$BASE_DIR" == */Cellar/* ]]; then
    FORMULA_NAME=$(echo "$BASE_DIR" | sed 's|.*/Cellar/\([^/]*\)/.*|\1|')
    OPT_DIR="$(dirname "$(dirname "$BASE_DIR")")/../opt/$FORMULA_NAME"
    if [ -d "$OPT_DIR" ]; then
        HOOK_BASE="$(cd "$OPT_DIR" && pwd)"
    fi
fi

# ──────────────────────────────────────────────────────────────
# 1. Create config directory and copy assets
# ──────────────────────────────────────────────────────────────

_info "Setting up $CONFIG_DIR..."
mkdir -p "$CONFIG_DIR" || { _err "Failed to create $CONFIG_DIR"; exit 1; }
mkdir -p "$CLAUDE_DIR" || { _err "Failed to create $CLAUDE_DIR"; exit 1; }

cp "$BASE_DIR/assets/claude-icon.png" "$CONFIG_DIR/claude-icon.png" || { _warn "Failed to copy icon"; ERRORS=1; }
cp "$BASE_DIR/assets/sounds/default.wav" "$CONFIG_DIR/default.wav" || { _warn "Failed to copy sound"; ERRORS=1; }
cp "$BASE_DIR/assets/themes.json" "$CONFIG_DIR/themes.json" || { _warn "Failed to copy themes"; ERRORS=1; }
chmod 0600 "$CONFIG_DIR/claude-icon.png" "$CONFIG_DIR/default.wav" "$CONFIG_DIR/themes.json" 2>/dev/null
_success "Assets copied (icon + sound + themes)"

# ──────────────────────────────────────────────────────────────
# 2. Write default config (only if none exists)
# ──────────────────────────────────────────────────────────────

if [ ! -f "$CONFIG_DIR/config.json" ]; then
    _info "Writing default config..."
    if cp "$BASE_DIR/config.example.json" "$CONFIG_DIR/config.json"; then
        chmod 0600 "$CONFIG_DIR/config.json"
        _success "Default config written: $CONFIG_DIR/config.json"
    else
        _err "Failed to write default config"
        ERRORS=1
    fi
else
    _success "Config file preserved (already exists)"
fi

# ──────────────────────────────────────────────────────────────
# 3. Compile Swift notification binary
# ──────────────────────────────────────────────────────────────

if command -v swiftc &>/dev/null; then
    _info "Compiling notification overlay..."
    if swiftc -O \
        -o "$CONFIG_DIR/notch-notify" \
        "$SCRIPT_DIR/src/NotchNotification.swift" \
        -framework AppKit \
        2>&1; then
        chmod +x "$CONFIG_DIR/notch-notify"
        _success "Binary compiled"
    else
        _warn "Swift compilation failed. Notification overlay will not work."
        _warn "Run 'xcode-select --install' and re-run this script."
    fi
else
    _warn "swiftc not found. Notification overlay will not be compiled."
    _warn "Install Xcode Command Line Tools: xcode-select --install"
    _warn "Then re-run: $0 $BASE_DIR"
fi

# ──────────────────────────────────────────────────────────────
# 4. Make hook scripts executable
# ──────────────────────────────────────────────────────────────

chmod +x "$SCRIPT_DIR/src/notify.sh" 2>/dev/null || _warn "Could not set notify.sh executable"
chmod +x "$SCRIPT_DIR/src/statusline.sh" 2>/dev/null || _warn "Could not set statusline.sh executable"

# ──────────────────────────────────────────────────────────────
# 5. Register Claude Code hooks
# ──────────────────────────────────────────────────────────────

if command -v python3 &>/dev/null; then
    _info "Registering Claude Code hooks..."

    if python3 -c "
import json, os, sys

settings_path = '$SETTINGS_FILE'
notify_cmd = '$HOOK_BASE/macos/src/notify.sh'
statusline_cmd = '$HOOK_BASE/macos/src/statusline.sh'

# Load existing settings or start fresh
try:
    with open(settings_path) as f:
        settings = json.load(f)
except:
    settings = {}

# Ensure hooks structure exists
if 'hooks' not in settings:
    settings['hooks'] = {}

# Hook entry format: matcher + hooks array (required by Claude Code)
hook_entry = {
    'matcher': '',
    'hooks': [{'type': 'command', 'command': notify_cmd}]
}

# Remove previous claude-tap entries (check nested hooks array)
def has_cmd(entry, cmd):
    if 'notify.sh' in entry.get('command', ''):
        return True
    for h in entry.get('hooks', []):
        if 'notify.sh' in h.get('command', ''):
            return True
    return False

# Register Notification hook
existing_notif = settings['hooks'].get('Notification', [])
existing_notif = [h for h in existing_notif if not has_cmd(h, notify_cmd)]
existing_notif.append(hook_entry)
settings['hooks']['Notification'] = existing_notif

# Register Stop hook
existing_stop = settings['hooks'].get('Stop', [])
existing_stop = [h for h in existing_stop if not has_cmd(h, notify_cmd)]
existing_stop.append(hook_entry)
settings['hooks']['Stop'] = existing_stop

# Register status line
settings['statusLine'] = {
    'type': 'command',
    'command': statusline_cmd,
    'padding': 2
}

# Backup existing settings
if os.path.exists(settings_path):
    import shutil
    from datetime import datetime
    backup = settings_path + '.backup.' + datetime.now().strftime('%Y%m%d%H%M%S')
    shutil.copy2(settings_path, backup)

# Write updated settings
with open(settings_path, 'w') as f:
    json.dump(settings, f, indent=2)
    f.write('\n')
" 2>&1; then
        _success "Hooks registered in $SETTINGS_FILE"
    else
        _err "Failed to register hooks in $SETTINGS_FILE"
        ERRORS=1
    fi
else
    _warn "python3 not found. Could not register Claude Code hooks."
    _warn "Run the full installer instead: $BASE_DIR/macos/install.sh"
    ERRORS=1
fi

if [ "$ERRORS" = "1" ]; then
    _warn "Setup completed with warnings. Some features may not work."
    exit 1
fi
