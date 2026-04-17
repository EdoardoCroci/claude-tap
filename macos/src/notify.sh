#!/bin/bash
# Claude Tap - Hook script for Claude Code.
#
# This script is registered as both a Notification hook and a Stop hook.
# It reads JSON from stdin, extracts the relevant fields, and:
#   1. Optionally skips if the terminal is already focused
#   2. Plays a configurable sound
#   3. Shows a Dynamic Island-style notification overlay
#
# All behavior is controlled by ~/.config/claude-tap/config.json.
# See docs/CONFIGURATION.md for the full reference.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$HOME/.config/claude-tap"
CONFIG_FILE="$CONFIG_DIR/config.json"

# ──────────────────────────────────────────────────────────────
# Bootstrap: auto-setup on first run if config is missing
# ──────────────────────────────────────────────────────────────

if [ ! -f "$CONFIG_FILE" ]; then
    SETUP_SCRIPT="$SCRIPT_DIR/../../macos/setup.sh"
    [ -f "$SETUP_SCRIPT" ] || SETUP_SCRIPT="$SCRIPT_DIR/../setup.sh"
    if [ -f "$SETUP_SCRIPT" ]; then
        BASE_DIR="$(cd "$(dirname "$SETUP_SCRIPT")/.." && pwd)"
        "$SETUP_SCRIPT" "$BASE_DIR" --quiet 2>/dev/null
    fi
fi

# ──────────────────────────────────────────────────────────────
# Read configuration (via python3, which ships with macOS)
# ──────────────────────────────────────────────────────────────

eval "$(python3 -c "
import json, sys, os, shlex

# Load config
config_path = os.path.expanduser('~/.config/claude-tap/config.json')
try:
    with open(config_path) as f:
        config = json.load(f)
except:
    config = {}

# Extract config values with defaults
notif_enabled  = config.get('notification', {}).get('enabled', True)
show_on_waiting = config.get('notification', {}).get('show_on_waiting', False)
sound_enabled  = config.get('sound', {}).get('enabled', True)
sound_file     = config.get('sound', {}).get('file', '~/.config/claude-tap/default.wav')
sound_volume   = config.get('sound', {}).get('volume', 0.15)
skip_focused   = config.get('skip_if_focused', True)
max_length     = config.get('message', {}).get('max_length', 300)
terminal_apps  = config.get('terminal_apps', [
    'com.apple.Terminal', 'com.googlecode.iterm2', 'net.kovidgoyal.kitty',
    'co.zeit.hyper', 'com.mitchellh.ghostty', 'io.alacritty', 'dev.warp.Warp-Stable',
    'com.microsoft.VSCode', 'com.microsoft.VSCodeInsiders', 'com.todesktop.230313mzl4w4u92'
])
warn_threshold = config.get('rate_limits', {}).get('warning_threshold', 80)
crit_threshold = config.get('rate_limits', {}).get('critical_threshold', 90)
icon_path      = config.get('notification', {}).get('icon', '')
sound_files    = config.get('sound', {}).get('files', {})
sound_stop     = os.path.expanduser(sound_files.get('stop', '')) if sound_files.get('stop') else ''
sound_notif    = os.path.expanduser(sound_files.get('notification', '')) if sound_files.get('notification') else ''
quiet_hours    = config.get('quiet_hours', {})
quiet_enabled  = quiet_hours.get('enabled', False)
quiet_start    = quiet_hours.get('start', '22:00')
quiet_end      = quiet_hours.get('end', '07:00')
history_cfg    = config.get('history', {})
history_enabled = history_cfg.get('enabled', True)
history_max    = history_cfg.get('max_entries', 100)
history_days   = history_cfg.get('clear_after_days', 30)

# Expand ~ in paths
sound_file = os.path.expanduser(sound_file)
icon_path = os.path.expanduser(icon_path) if icon_path else ''

# Parse stdin JSON (hook event data)
try:
    data = json.load(sys.stdin)
except:
    data = {}

if 'last_assistant_message' in data:
    # Stop hook: Claude finished responding
    hook_type = 'stop'
    title = 'Task Complete'
    msg = data['last_assistant_message'] or ''
    # Collapse multiple lines into one, truncate to configured max length
    collapsed = ' '.join(line.strip() for line in msg.strip().split('\n') if line.strip())
    full_message = collapsed  # untruncated for history
    truncated = collapsed[:max_length]
    if len(collapsed) > max_length:
        truncated += '...'
    message = truncated if truncated else 'Claude has finished.'
else:
    # Notification hook: Claude needs attention
    hook_type = 'notification'
    title = data.get('title', 'Claude Code')
    message = data.get('message', 'Claude needs your attention')
    full_message = message

# Capture the originating session's working directory so the click handler
# can identify the right terminal window via window-title matching (needed
# for terminals like Ghostty that don't expose per-window AppleScript).
session_cwd = (
    data.get('cwd')
    or (data.get('workspace') or {}).get('current_dir')
    or os.environ.get('PWD', '')
)

# Output shell variables
print(f'NOTIF_TITLE={shlex.quote(title)}')
print(f'NOTIF_MESSAGE={shlex.quote(message)}')
print(f'NOTIF_ENABLED={shlex.quote(str(notif_enabled).lower())}')
print(f'SHOW_ON_WAITING={shlex.quote(str(show_on_waiting).lower())}')
print(f'SOUND_ENABLED={shlex.quote(str(sound_enabled).lower())}')
print(f'SOUND_FILE={shlex.quote(sound_file)}')
print(f'SOUND_VOLUME={shlex.quote(str(sound_volume))}')
print(f'SKIP_FOCUSED={shlex.quote(str(skip_focused).lower())}')
print(f'TERMINAL_APPS={shlex.quote(\"|\".join(terminal_apps))}')
print(f'WARN_THRESHOLD={warn_threshold}')
print(f'CRIT_THRESHOLD={crit_threshold}')
print(f'ICON_PATH={shlex.quote(icon_path)}')
print(f'SOUND_FILE_STOP={shlex.quote(sound_stop)}')
print(f'SOUND_FILE_NOTIF={shlex.quote(sound_notif)}')
print(f'QUIET_ENABLED={shlex.quote(str(quiet_enabled).lower())}')
print(f'QUIET_START={shlex.quote(quiet_start)}')
print(f'QUIET_END={shlex.quote(quiet_end)}')
print(f'HISTORY_ENABLED={shlex.quote(str(history_enabled).lower())}')
print(f'HISTORY_MAX={history_max}')
print(f'HISTORY_DAYS={history_days}')
print(f'HOOK_TYPE={shlex.quote(hook_type)}')
print(f'FULL_MESSAGE={shlex.quote(full_message)}')
print(f'SESSION_CWD={shlex.quote(session_cwd)}')
")" || {
    NOTIF_TITLE="Claude Code"
    NOTIF_MESSAGE="Claude needs your attention"
    NOTIF_ENABLED="true"
    SHOW_ON_WAITING="false"
    SOUND_ENABLED="true"
    SOUND_FILE="$CONFIG_DIR/default.wav"
    SOUND_VOLUME="0.15"
    SKIP_FOCUSED="true"
    TERMINAL_APPS="com.apple.Terminal|com.googlecode.iterm2|net.kovidgoyal.kitty|co.zeit.hyper|com.mitchellh.ghostty|io.alacritty|dev.warp.Warp-Stable|com.microsoft.VSCode|com.microsoft.VSCodeInsiders|com.todesktop.230313mzl4w4u92"
    WARN_THRESHOLD=80
    CRIT_THRESHOLD=90
    QUIET_ENABLED="false"
    QUIET_START="22:00"
    QUIET_END="07:00"
    HISTORY_ENABLED="true"
    HISTORY_MAX=100
    HISTORY_DAYS=30
    HOOK_TYPE="notification"
    FULL_MESSAGE=""
    SESSION_CWD="$PWD"
}

# ──────────────────────────────────────────────────────────────
# Skip if terminal is focused (for Stop events only)
# ──────────────────────────────────────────────────────────────

# Suppress Notification-hook events (idle "waiting for input", permission prompts)
# entirely when show_on_waiting is off — no sound, no overlay, no history entry.
if [ "$HOOK_TYPE" = "notification" ] && [ "$SHOW_ON_WAITING" != "true" ]; then
    exit 0
fi

if [ "$SKIP_FOCUSED" = "true" ] && [ "$NOTIF_TITLE" = "Task Complete" ]; then
    FRONTMOST=$(osascript -e 'tell application "System Events" to get bundle identifier of first process whose frontmost is true' 2>/dev/null)
    IFS='|' read -ra APPS <<< "$TERMINAL_APPS"
    for app in "${APPS[@]}"; do
        if [ "$FRONTMOST" = "$app" ]; then
            exit 0
        fi
    done
fi

# ──────────────────────────────────────────────────────────────
# Log to notification history (before DND gate so all events are recorded)
# ──────────────────────────────────────────────────────────────

if [ "$HISTORY_ENABLED" = "true" ]; then
    NOTIF_TITLE="$NOTIF_TITLE" FULL_MESSAGE="$FULL_MESSAGE" HOOK_TYPE="$HOOK_TYPE" HISTORY_MAX="$HISTORY_MAX" HISTORY_DAYS="$HISTORY_DAYS" \
    python3 -c "
import json, os, fcntl, datetime

history_path = os.path.expanduser('~/.config/claude-tap/history.json')
max_entries = int(os.environ.get('HISTORY_MAX', 100))
clear_days = int(os.environ.get('HISTORY_DAYS', 30))
title = os.environ.get('NOTIF_TITLE', '')
message = os.environ.get('FULL_MESSAGE', '')
hook_type = os.environ.get('HOOK_TYPE', 'notification')
now = datetime.datetime.now()

entry = {
    'timestamp': now.isoformat(timespec='seconds'),
    'title': title,
    'message': message,
    'urgency': 'normal',
    'hook_type': hook_type
}

# Atomic read-modify-write with file locking
fd = os.open(history_path, os.O_RDWR | os.O_CREAT, 0o600)
try:
    fcntl.flock(fd, fcntl.LOCK_EX)
    f = os.fdopen(fd, 'r+')
    try:
        content = f.read()
        history = json.loads(content) if content.strip() else []
    except (json.JSONDecodeError, ValueError):
        history = []
    history.append(entry)
    # Prune entries older than clear_after_days
    if clear_days > 0:
        cutoff = (now - datetime.timedelta(days=clear_days)).isoformat(timespec='seconds')
        history = [e for e in history if e.get('timestamp', '') >= cutoff]
    # Enforce max_entries limit
    if len(history) > max_entries:
        history = history[-max_entries:]
    f.seek(0)
    f.truncate()
    json.dump(history, f, indent=2)
    f.write('\n')
except Exception:
    pass
finally:
    try:
        f.close()
    except Exception:
        os.close(fd)
" 2>/dev/null &
fi

# ──────────────────────────────────────────────────────────────
# Do Not Disturb / Quiet Hours gate
# ──────────────────────────────────────────────────────────────

DND_ACTIVE="false"

# Manual DND toggle: touch ~/.config/claude-tap/dnd to enable
if [ -f "$CONFIG_DIR/dnd" ]; then
    DND_ACTIVE="true"
fi

# Quiet hours check (handles midnight-crossing ranges)
if [ "$QUIET_ENABLED" = "true" ] && [ "$DND_ACTIVE" = "false" ]; then
    CURRENT_TIME=$(date +%H:%M)
    if [[ "$QUIET_START" > "$QUIET_END" ]]; then
        # Overnight range (e.g., 22:00 to 07:00)
        if [[ ! "$CURRENT_TIME" < "$QUIET_START" || "$CURRENT_TIME" < "$QUIET_END" ]]; then
            DND_ACTIVE="true"
        fi
    else
        # Same-day range (e.g., 12:00 to 13:00)
        if [[ ! "$CURRENT_TIME" < "$QUIET_START" && "$CURRENT_TIME" < "$QUIET_END" ]]; then
            DND_ACTIVE="true"
        fi
    fi
fi

# If DND is active, skip sound and overlay (exit silently)
if [ "$DND_ACTIVE" = "true" ]; then
    exit 0
fi

# ──────────────────────────────────────────────────────────────
# Determine urgency from cached rate limit
# ──────────────────────────────────────────────────────────────

URGENCY="normal"
CLAUDE_TMPDIR="${TMPDIR:-/tmp}"
if [ -f "$CLAUDE_TMPDIR/claude-rate-limit" ]; then
    RATE_PCT=$(cat "$CLAUDE_TMPDIR/claude-rate-limit" 2>/dev/null)
    if [ -n "$RATE_PCT" ] && [ "$RATE_PCT" -ge "$CRIT_THRESHOLD" ] 2>/dev/null; then
        URGENCY="critical"
    elif [ -n "$RATE_PCT" ] && [ "$RATE_PCT" -ge "$WARN_THRESHOLD" ] 2>/dev/null; then
        URGENCY="warning"
    fi
fi

# ──────────────────────────────────────────────────────────────
# Play sound
# ──────────────────────────────────────────────────────────────

if [ "$SOUND_ENABLED" = "true" ]; then
    # Resolve per-event sound with fallback to default
    PLAY_SOUND="$SOUND_FILE"
    if [ "$HOOK_TYPE" = "stop" ] && [ -n "$SOUND_FILE_STOP" ] && [ -f "$SOUND_FILE_STOP" ]; then
        PLAY_SOUND="$SOUND_FILE_STOP"
    elif [ "$HOOK_TYPE" = "notification" ] && [ -n "$SOUND_FILE_NOTIF" ] && [ -f "$SOUND_FILE_NOTIF" ]; then
        PLAY_SOUND="$SOUND_FILE_NOTIF"
    fi
    [ -f "$PLAY_SOUND" ] && afplay -v "$SOUND_VOLUME" "$PLAY_SOUND" &
fi

# ──────────────────────────────────────────────────────────────
# Show notification overlay
# ──────────────────────────────────────────────────────────────

if [ "$NOTIF_ENABLED" = "true" ]; then
    # Use custom icon from config, fall back to default
    if [ -n "$ICON_PATH" ] && [ -f "$ICON_PATH" ]; then
        ICON="$ICON_PATH"
    else
        ICON="$CONFIG_DIR/claude-icon.png"
    fi

    # Build a focus hint so notch-notify can raise the ORIGINATING window on
    # click (not just bring the terminal app to the front). Format is
    # "k=v;k=v" with keys program / session_id / tty / cwd. Values are
    # validated against strict allowlists to block AppleScript injection.
    # cwd is the escape hatch for terminals with no per-window scripting API
    # (Ghostty, VS Code, Warp, etc.): the Swift click handler uses the
    # Accessibility API to raise whichever window has the cwd in its title.
    FOCUS_HINT=""
    case "$TERM_PROGRAM" in
        iTerm.app)
            FOCUS_HINT="program=iterm2"
            if [ -n "$ITERM_SESSION_ID" ]; then
                # ITERM_SESSION_ID is "w<N>t<N>p<N>:<UUID>" — keep only the UUID.
                uuid="${ITERM_SESSION_ID##*:}"
                if [[ "$uuid" =~ ^[A-Fa-f0-9-]+$ ]]; then
                    FOCUS_HINT="${FOCUS_HINT};session_id=${uuid}"
                fi
            fi
            ;;
        Apple_Terminal)
            FOCUS_HINT="program=apple_terminal"
            # Walk up the process tree to find the first ancestor with a real tty
            # (the shell inside the tab). notify.sh itself may have no ctty.
            probe_pid=$$
            while [ "$probe_pid" -gt 1 ]; do
                probe_tty=$(ps -o tty= -p "$probe_pid" 2>/dev/null | tr -d ' ')
                if [ -n "$probe_tty" ] && [ "$probe_tty" != "??" ]; then
                    if [[ "$probe_tty" =~ ^ttys[0-9]+$ ]]; then
                        FOCUS_HINT="${FOCUS_HINT};tty=/dev/${probe_tty}"
                    fi
                    break
                fi
                probe_pid=$(ps -o ppid= -p "$probe_pid" 2>/dev/null | tr -d ' ')
                [ -z "$probe_pid" ] && break
            done
            ;;
        vscode)     FOCUS_HINT="program=vscode" ;;
        ghostty)    FOCUS_HINT="program=ghostty" ;;
        WarpTerminal) FOCUS_HINT="program=warp" ;;
    esac

    # Attach cwd for the AX title-match fallback. Semicolons aren't legal in
    # POSIX paths in practice; the Swift side still percent-decodes to be safe.
    if [ -n "$SESSION_CWD" ]; then
        encoded_cwd=$(printf '%s' "$SESSION_CWD" | sed -e 's/%/%25/g' -e 's/;/%3B/g' -e 's/=/%3D/g')
        [ -n "$FOCUS_HINT" ] || FOCUS_HINT="program=unknown"
        FOCUS_HINT="${FOCUS_HINT};cwd=${encoded_cwd}"
    fi

    "$CONFIG_DIR/notch-notify" "$NOTIF_TITLE" "$NOTIF_MESSAGE" "$ICON" "$URGENCY" "$FOCUS_HINT" &
fi
