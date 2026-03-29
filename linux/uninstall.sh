#!/bin/bash
# Claude Tap - Uninstaller (Linux)
#
# Removes:
#   - Claude Code hooks (Notification, Stop) pointing to this tool
#   - Status line configuration
#   - ~/.config/claude-tap/ directory (assets, config, notification.py)
#   - Temporary rate limit files
#
# Does NOT remove the cloned repository itself.

set -e

CONFIG_DIR="$HOME/.config/claude-tap"
CLAUDE_DIR="$HOME/.claude"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info()    { echo -e "${CYAN}[info]${RESET}  $1"; }
success() { echo -e "${GREEN}[ok]${RESET}    $1"; }

echo ""
echo -e "${BOLD}Claude Tap - Uninstaller (Linux)${RESET}"
echo ""

# ──────────────────────────────────────────────────────────────
# 1. Remove hooks from Claude Code settings
# ──────────────────────────────────────────────────────────────

if [ -f "$SETTINGS_FILE" ]; then
    info "Removing hooks from $SETTINGS_FILE..."
    python3 -c "
import json, os, shutil
from datetime import datetime

path = '$SETTINGS_FILE'
notify_cmd = '$SCRIPT_DIR/src/notify.sh'

with open(path) as f:
    settings = json.load(f)

# Backup
backup = path + '.backup.' + datetime.now().strftime('%Y%m%d%H%M%S')
shutil.copy2(path, backup)
print(f'Backed up to {backup}')

# Remove our hooks (check nested hooks array structure)
def has_cmd(entry, cmd):
    if cmd in entry.get('command', ''):
        return True
    for h in entry.get('hooks', []):
        if cmd in h.get('command', ''):
            return True
    return False

for hook_type in ['Notification', 'Stop']:
    hooks = settings.get('hooks', {}).get(hook_type, [])
    settings.setdefault('hooks', {})[hook_type] = [
        h for h in hooks if not has_cmd(h, notify_cmd)
    ]
    if not settings['hooks'][hook_type]:
        del settings['hooks'][hook_type]

if not settings.get('hooks'):
    settings.pop('hooks', None)

sl = settings.get('statusLine', {})
if 'statusline.sh' in sl.get('command', '') and 'claude-tap' in sl.get('command', ''):
    del settings['statusLine']

with open(path, 'w') as f:
    json.dump(settings, f, indent=2)
    f.write('\n')
" 2>&1
    success "Hooks removed"
else
    info "No settings file found - skipping hook removal"
fi

# ──────────────────────────────────────────────────────────────
# 2. Remove config directory
# ──────────────────────────────────────────────────────────────

if [ -d "$CONFIG_DIR" ]; then
    info "Removing $CONFIG_DIR..."
    rm -rf "$CONFIG_DIR"
    success "Config directory removed"
else
    info "Config directory not found - skipping"
fi

# ──────────────────────────────────────────────────────────────
# 3. Clean up temp files
# ──────────────────────────────────────────────────────────────

CLAUDE_TMPDIR="${TMPDIR:-/tmp}"
rm -f "$CLAUDE_TMPDIR/claude-rate-limit" "$CLAUDE_TMPDIR/claude-rate-warn-warning" "$CLAUDE_TMPDIR/claude-rate-warn-critical"
success "Temporary files cleaned up"

echo ""
echo -e "${BOLD}${GREEN}Uninstall complete.${RESET}"
echo -e "Restart Claude Code to apply changes."
echo -e "You can safely delete the ${CYAN}$(cd "$SCRIPT_DIR/.." && basename "$(pwd)")/${RESET} folder if you no longer need it."
echo ""
