#!/bin/bash
# Claude Tap - History viewer
#
# Displays recent notification history from ~/.config/claude-tap/history.json
# Usage: ./scripts/history.sh [--last N]

set -e

HISTORY_FILE="$HOME/.config/claude-tap/history.json"

# Parse arguments
LAST=20
while [ $# -gt 0 ]; do
    case "$1" in
        --last) LAST="$2"; shift 2 ;;
        --last=*) LAST="${1#--last=}"; shift ;;
        -h|--help)
            echo "Usage: history.sh [--last N]"
            echo "  --last N    Show last N entries (default: 20)"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [ ! -f "$HISTORY_FILE" ]; then
    echo "No history found at $HISTORY_FILE"
    exit 0
fi

python3 -c "
import json, sys

RESET = '\033[0m'
BOLD = '\033[1m'
DIM = '\033[2m'
CYAN = '\033[0;36m'
ORANGE = '\033[38;5;215m'
GREEN = '\033[38;5;114m'
RED = '\033[38;5;174m'
YELLOW = '\033[38;5;222m'
GRAY = '\033[38;5;245m'

try:
    with open('$HISTORY_FILE') as f:
        history = json.load(f)
except (json.JSONDecodeError, FileNotFoundError):
    print('No valid history data.')
    sys.exit(0)

last = int('$LAST')
entries = history[-last:] if len(history) > last else history

if not entries:
    print('No notifications in history.')
    sys.exit(0)

print(f'{BOLD}Notification History{RESET} ({len(entries)} of {len(history)} entries)')
print(f'{GRAY}{\"─\" * 60}{RESET}')

for entry in entries:
    ts = entry.get('timestamp', '?')
    title = entry.get('title', '?')
    msg = entry.get('message', '')
    hook = entry.get('hook_type', '?')
    urgency = entry.get('urgency', 'normal')

    # Color by hook type
    hook_color = GREEN if hook == 'stop' else YELLOW

    # Truncate message for display
    if len(msg) > 120:
        msg = msg[:117] + '...'

    print(f'{DIM}{ts}{RESET}  {hook_color}{hook:<12}{RESET}  {ORANGE}{title}{RESET}')
    if msg:
        print(f'  {msg}')
    print()
" 2>/dev/null
