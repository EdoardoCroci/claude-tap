#!/bin/bash
# Claude Tap - Installer
#
# This script:
#   1. Checks prerequisites (macOS, swiftc, python3)
#   2. Asks you to configure notifications, status line, and colors
#   3. Compiles the Swift notification binary
#   4. Copies assets (icon, sound) to ~/.config/claude-tap/
#   5. Generates config.json from your choices
#   6. Registers Claude Code hooks and status line in ~/.claude/settings.json
#
# Safe to run multiple times - it recompiles the binary and re-registers
# hooks. Pass --reconfigure to re-run the interactive setup even if a
# config already exists.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_DIR="$HOME/.config/claude-tap"
CLAUDE_DIR="$HOME/.claude"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"

# ──────────────────────────────────────────────────────────────
# Colors for installer output
# ──────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

info()    { echo -e "${CYAN}[info]${RESET}  $1"; }
success() { echo -e "${GREEN}[ok]${RESET}    $1"; }
warn()    { echo -e "${YELLOW}[warn]${RESET}  $1"; }
fail()    { echo -e "${RED}[error]${RESET} $1"; exit 1; }

# Helper: prompt with a default value. Usage: ask "prompt" "default"
ask() {
    local prompt="$1"
    local default="$2"
    local reply
    read -rp "$(echo -e "  ${prompt} ${DIM}[${default}]${RESET}: ")" reply
    echo "${reply:-$default}"
}

# Helper: yes/no prompt. Usage: ask_yn "prompt" "Y" -> returns "true"/"false"
ask_yn() {
    local prompt="$1"
    local default="$2"  # "Y" or "N"
    local hint
    if [ "$default" = "Y" ]; then hint="Y/n"; else hint="y/N"; fi
    local reply
    read -rp "$(echo -e "  ${prompt} ${DIM}[${hint}]${RESET}: ")" reply
    reply="${reply:-$default}"
    case "$reply" in
        [Yy]*) echo "true" ;;
        *)     echo "false" ;;
    esac
}

# Helper: ask for RGBA color. Usage: ask_rgba "label" "0.05 0.05 0.07 0.96"
ask_rgba() {
    local label="$1"
    local default="$2"
    local reply
    read -rp "$(echo -e "    ${label} ${DIM}[${default}]${RESET}: ")" reply
    reply="${reply:-$default}"
    # Convert "0.1 0.2 0.3 0.4" to "[0.1, 0.2, 0.3, 0.4]"
    echo "$reply" | awk '{printf "[%s, %s, %s, %s]", $1, $2, $3, $4}'
}

echo ""
echo -e "${BOLD}Claude Tap - Installer${RESET}"
echo ""

# ──────────────────────────────────────────────────────────────
# 1. Preflight checks
# ──────────────────────────────────────────────────────────────

info "Checking prerequisites..."

[ "$(uname -s)" = "Darwin" ] || fail "This tool only works on macOS."

if command -v swiftc &>/dev/null; then
    success "swiftc found"
else
    fail "swiftc not found. Install Xcode Command Line Tools: xcode-select --install"
fi

if command -v python3 &>/dev/null; then
    success "python3 found"
else
    fail "python3 not found. It should ship with macOS - check your PATH."
fi

if command -v jq &>/dev/null; then
    success "jq found"
else
    warn "jq not found. The status line requires jq. Install via: brew install jq"
fi

echo ""

# ──────────────────────────────────────────────────────────────
# 1b. Check for updates (if existing config has auto_update.check_on_install)
# ──────────────────────────────────────────────────────────────

if [ -f "$CONFIG_DIR/config.json" ]; then
    CHECK_UPDATE=$(python3 -c "
import json, os
try:
    with open(os.path.expanduser('$CONFIG_DIR/config.json')) as f:
        c = json.load(f)
    print('true' if c.get('auto_update', {}).get('check_on_install', True) else 'false')
except:
    print('false')
" 2>/dev/null) || CHECK_UPDATE="false"

    if [ "$CHECK_UPDATE" = "true" ]; then
        if [ -f "$REPO_DIR/scripts/update.sh" ]; then
            "$REPO_DIR/scripts/update.sh" --check-only 2>/dev/null || true
        fi
    fi
fi

# ──────────────────────────────────────────────────────────────
# 2. Interactive configuration
# ──────────────────────────────────────────────────────────────

SHOULD_CONFIGURE="true"
if [ -f "$CONFIG_DIR/config.json" ] && [ "$1" != "--reconfigure" ]; then
    echo -e "  ${CYAN}Existing config found.${RESET} Your customizations will be preserved."
    echo -e "  Run ${CYAN}./install.sh --reconfigure${RESET} to change settings."
    echo ""
    SHOULD_CONFIGURE="false"
fi

if [ "$SHOULD_CONFIGURE" = "true" ]; then

    # -- Load existing config values as defaults (if config exists) --
    if [ -f "$CONFIG_DIR/config.json" ]; then
        info "Loading current config as defaults (press Enter to keep, type to change)"
        eval "$(python3 -c "
import json, os, shlex
path = os.path.expanduser('$CONFIG_DIR/config.json')
try:
    with open(path) as f:
        c = json.load(f)
except:
    c = {}
n = c.get('notification', {})
s = c.get('sound', {})
sl = c.get('status_line', {})
rl = c.get('rate_limits', {})
# Map position to menu number
pos_map = {'top-center':'1','top-left':'2','top-right':'3','bottom-center':'4','bottom-left':'5','bottom-right':'6'}
print(f'D_POS={shlex.quote(pos_map.get(n.get(\"position\",\"top-center\"),\"1\"))}')
print(f'D_DURATION={shlex.quote(str(n.get(\"duration_seconds\",5.5)))}')
print(f'D_MAX_LINES={shlex.quote(str(n.get(\"max_lines\",3)))}')
print(f'D_WIDTH={shlex.quote(str(n.get(\"width\",380)))}')
print(f'D_CORNER={shlex.quote(str(n.get(\"corner_radius\",16)))}')
print(f'D_ICON={shlex.quote(n.get(\"icon\",\"\"))}')
print(f'D_SOUND_ENABLED={shlex.quote(\"Y\" if s.get(\"enabled\",True) else \"N\")}')
print(f'D_SOUND_VOLUME={shlex.quote(str(s.get(\"volume\",0.15)))}')
print(f'D_SOUND_FILE={shlex.quote(s.get(\"file\",\"~/.config/claude-tap/default.wav\"))}')
print(f'D_SL_ENABLED={shlex.quote(\"Y\" if sl.get(\"enabled\",True) else \"N\")}')
print(f'D_SHOW_CTX={shlex.quote(\"Y\" if sl.get(\"show_context_bar\",True) else \"N\")}')
print(f'D_SHOW_5H={shlex.quote(\"Y\" if sl.get(\"show_rate_5h\",True) else \"N\")}')
print(f'D_SHOW_7D={shlex.quote(\"Y\" if sl.get(\"show_rate_7d\",True) else \"N\")}')
print(f'D_SHOW_LINES={shlex.quote(\"Y\" if sl.get(\"show_lines_changed\",True) else \"N\")}')
print(f'D_WARN={shlex.quote(str(rl.get(\"warning_threshold\",80)))}')
print(f'D_CRIT={shlex.quote(str(rl.get(\"critical_threshold\",90)))}')
print(f'D_SKIP={shlex.quote(\"Y\" if c.get(\"skip_if_focused\",True) else \"N\")}')
qh = c.get('quiet_hours', {})
print(f'D_QUIET_ENABLED={shlex.quote(\"Y\" if qh.get(\"enabled\",False) else \"N\")}')
print(f'D_QUIET_START={shlex.quote(qh.get(\"start\",\"22:00\"))}')
print(f'D_QUIET_END={shlex.quote(qh.get(\"end\",\"07:00\"))}')
hi = c.get('history', {})
print(f'D_HISTORY_ENABLED={shlex.quote(\"Y\" if hi.get(\"enabled\",True) else \"N\")}')
print(f'D_HISTORY_MAX={shlex.quote(str(hi.get(\"max_entries\",100)))}')
print(f'D_HISTORY_DAYS={shlex.quote(str(hi.get(\"clear_after_days\",30)))}')
au = c.get('auto_update', {})
print(f'D_UPDATE_CHECK={shlex.quote(\"Y\" if au.get(\"check_on_install\",True) else \"N\")}')
print(f'D_UPDATE_NOTIFY_ONLY={shlex.quote(\"Y\" if au.get(\"notify_only\",True) else \"N\")}')
th = c.get('theme', {})
print(f'D_THEME_AUTO={shlex.quote(\"Y\" if th.get(\"auto\",False) else \"N\")}')
print(f'D_THEME_DAY={shlex.quote(th.get(\"day\",\"light\"))}')
print(f'D_THEME_NIGHT={shlex.quote(th.get(\"night\",\"dark\"))}')
print(f'D_THEME_DAY_START={shlex.quote(th.get(\"day_start\",\"08:00\"))}')
print(f'D_THEME_NIGHT_START={shlex.quote(th.get(\"night_start\",\"18:00\"))}')
# Colors
for urgency in ['normal','warning','critical']:
    for role in ['background','border','title','text']:
        vals = n.get('colors',{}).get(urgency,{}).get(role,[])
        if vals and len(vals)==4:
            print(f'D_{urgency.upper()}_{role.upper()}={shlex.quote(\"[\" + \", \".join(str(v) for v in vals) + \"]\"))}')
" 2>/dev/null)" || true
    fi

    # Set fallback defaults for first-time install
    : "${D_POS:=1}" "${D_DURATION:=5.5}" "${D_MAX_LINES:=3}" "${D_WIDTH:=380}" "${D_CORNER:=16}"
    : "${D_ICON:=}" "${D_SOUND_ENABLED:=Y}" "${D_SOUND_VOLUME:=0.15}"
    : "${D_SOUND_FILE:=~/.config/claude-tap/default.wav}"
    : "${D_SL_ENABLED:=Y}" "${D_SHOW_CTX:=Y}" "${D_SHOW_5H:=Y}" "${D_SHOW_7D:=Y}" "${D_SHOW_LINES:=Y}"
    : "${D_WARN:=80}" "${D_CRIT:=90}" "${D_SKIP:=Y}"
    : "${D_QUIET_ENABLED:=N}" "${D_QUIET_START:=22:00}" "${D_QUIET_END:=07:00}"
    : "${D_HISTORY_ENABLED:=Y}" "${D_HISTORY_MAX:=100}" "${D_HISTORY_DAYS:=30}"
    : "${D_UPDATE_CHECK:=Y}" "${D_UPDATE_NOTIFY_ONLY:=Y}"
    : "${D_THEME_AUTO:=N}" "${D_THEME_DAY:=light}" "${D_THEME_NIGHT:=dark}"
    : "${D_THEME_DAY_START:=08:00}" "${D_THEME_NIGHT_START:=18:00}"
    : "${D_NORMAL_BACKGROUND:=[0.05, 0.05, 0.07, 0.96]}" "${D_NORMAL_BORDER:=[1.0, 1.0, 1.0, 0.08]}"
    : "${D_NORMAL_TITLE:=[0.85, 0.55, 0.40, 1.0]}" "${D_NORMAL_TEXT:=[0.95, 0.95, 0.95, 1.0]}"
    : "${D_WARNING_BACKGROUND:=[0.12, 0.09, 0.04, 0.96]}" "${D_WARNING_BORDER:=[0.85, 0.65, 0.20, 0.25]}"
    : "${D_WARNING_TITLE:=[0.85, 0.55, 0.40, 1.0]}" "${D_WARNING_TEXT:=[0.95, 0.95, 0.95, 1.0]}"
    : "${D_CRITICAL_BACKGROUND:=[0.14, 0.04, 0.04, 0.96]}" "${D_CRITICAL_BORDER:=[0.90, 0.25, 0.20, 0.30]}"
    : "${D_CRITICAL_TITLE:=[0.85, 0.55, 0.40, 1.0]}" "${D_CRITICAL_TEXT:=[0.95, 0.95, 0.95, 1.0]}"

    echo -e "${BOLD}Let's configure your notifications!${RESET}"
    echo -e "${DIM}  Press Enter to keep current value, type to change.${RESET}"
    echo ""

    # -- Notification position --
    echo -e "  ${BOLD}Notification position:${RESET}"
    echo -e "    1) Top center"
    echo -e "    2) Top left"
    echo -e "    3) Top right"
    echo -e "    4) Bottom center"
    echo -e "    5) Bottom left"
    echo -e "    6) Bottom right"
    POS_CHOICE=$(ask "Choose" "$D_POS")
    case "$POS_CHOICE" in
        2) POSITION="top-left" ;;
        3) POSITION="top-right" ;;
        4) POSITION="bottom-center" ;;
        5) POSITION="bottom-left" ;;
        6) POSITION="bottom-right" ;;
        *) POSITION="top-center" ;;
    esac
    echo ""

    # -- Notification settings --
    echo -e "  ${BOLD}Notification settings:${RESET}"
    DURATION=$(ask "Duration in seconds" "$D_DURATION")
    MAX_LINES=$(ask "Max message lines (1-5)" "$D_MAX_LINES")
    WIDTH=$(ask "Width in points" "$D_WIDTH")
    CORNER_RADIUS=$(ask "Corner radius" "$D_CORNER")
    echo -e "    ${DIM}Tip: use any PNG image as the notification icon${RESET}"
    ICON_FILE=$(ask "Custom icon path (empty = default Claude icon)" "$D_ICON")
    echo ""

    # -- Sound --
    echo -e "  ${BOLD}Sound:${RESET}"
    SOUND_ENABLED=$(ask_yn "Enable sound" "$D_SOUND_ENABLED")
    if [ "$SOUND_ENABLED" = "true" ]; then
        SOUND_VOLUME=$(ask "Volume (0.0-1.0)" "$D_SOUND_VOLUME")
        echo -e "    ${DIM}Tip: use a macOS system sound like /System/Library/Sounds/Glass.aiff${RESET}"
        SOUND_FILE=$(ask "Sound file path" "$D_SOUND_FILE")
        # -- Sound preview --
        RESOLVED_SOUND="${SOUND_FILE/#\~/$HOME}"
        [ ! -f "$RESOLVED_SOUND" ] && RESOLVED_SOUND="$REPO_DIR/assets/sounds/default.wav"
        PREVIEW_LOOP="true"
        while [ "$PREVIEW_LOOP" = "true" ]; do
            echo -e "  ${DIM}Playing sound preview...${RESET}"
            afplay -v "$SOUND_VOLUME" "$RESOLVED_SOUND" 2>/dev/null
            echo -e "    1) Sounds good - continue"
            echo -e "    2) Play again"
            echo -e "    3) Adjust volume"
            echo -e "    4) Change sound file"
            PREVIEW_CHOICE=$(ask "Choose" "1")
            case "$PREVIEW_CHOICE" in
                2) ;;
                3) SOUND_VOLUME=$(ask "Volume (0.0-1.0)" "$SOUND_VOLUME") ;;
                4)
                    SOUND_FILE=$(ask "Sound file path" "$SOUND_FILE")
                    RESOLVED_SOUND="${SOUND_FILE/#\~/$HOME}"
                    [ ! -f "$RESOLVED_SOUND" ] && RESOLVED_SOUND="$REPO_DIR/assets/sounds/default.wav"
                    ;;
                *) PREVIEW_LOOP="false" ;;
            esac
        done
    else
        SOUND_VOLUME="$D_SOUND_VOLUME"
        SOUND_FILE="$D_SOUND_FILE"
    fi
    echo ""

    # -- Status line --
    echo -e "  ${BOLD}Status line - what to show:${RESET}"
    SL_ENABLED=$(ask_yn "Enable status line" "$D_SL_ENABLED")
    if [ "$SL_ENABLED" = "true" ]; then
        SHOW_CTX=$(ask_yn "Context window bar" "$D_SHOW_CTX")
        SHOW_5H=$(ask_yn "5-hour rate limit" "$D_SHOW_5H")
        SHOW_7D=$(ask_yn "7-day rate limit" "$D_SHOW_7D")
        SHOW_LINES=$(ask_yn "Lines changed" "$D_SHOW_LINES")
    else
        SHOW_CTX="true"; SHOW_5H="true"; SHOW_7D="true"; SHOW_LINES="true"
    fi
    echo ""

    # -- Rate limits --
    echo -e "  ${BOLD}Rate limit warnings:${RESET}"
    WARN_THRESHOLD=$(ask "Warning threshold (%)" "$D_WARN")
    CRIT_THRESHOLD=$(ask "Critical threshold (%)" "$D_CRIT")
    echo ""

    # -- Other --
    SKIP_FOCUSED=$(ask_yn "Skip notifications when terminal is focused" "$D_SKIP")
    echo ""

    # -- Quiet hours --
    echo -e "  ${BOLD}Quiet hours (Do Not Disturb):${RESET}"
    echo -e "    ${DIM}Suppress sound and overlay during specified hours.${RESET}"
    echo -e "    ${DIM}You can also toggle DND manually: touch ~/.config/claude-tap/dnd${RESET}"
    QUIET_ENABLED=$(ask_yn "Enable quiet hours" "$D_QUIET_ENABLED")
    if [ "$QUIET_ENABLED" = "true" ]; then
        QUIET_START=$(ask "Start time (HH:MM, 24h)" "$D_QUIET_START")
        QUIET_END=$(ask "End time (HH:MM, 24h)" "$D_QUIET_END")
    else
        QUIET_START="$D_QUIET_START"
        QUIET_END="$D_QUIET_END"
    fi
    echo ""

    # -- History --
    echo -e "  ${BOLD}Notification history:${RESET}"
    echo -e "    ${DIM}Log all notifications to ~/.config/claude-tap/history.json${RESET}"
    HISTORY_ENABLED=$(ask_yn "Enable notification history" "$D_HISTORY_ENABLED")
    if [ "$HISTORY_ENABLED" = "true" ]; then
        HISTORY_MAX=$(ask "Max entries to keep" "$D_HISTORY_MAX")
        HISTORY_DAYS=$(ask "Auto-delete entries older than N days (0 = never)" "$D_HISTORY_DAYS")
    else
        HISTORY_MAX="$D_HISTORY_MAX"
        HISTORY_DAYS="$D_HISTORY_DAYS"
    fi
    echo ""

    # -- Auto-theme (day/night) --
    echo -e "  ${BOLD}Auto-theme (day/night):${RESET}"
    echo -e "    ${DIM}Automatically switch between themes based on time of day.${RESET}"
    THEME_AUTO=$(ask_yn "Enable auto-theme" "$D_THEME_AUTO")
    if [ "$THEME_AUTO" = "true" ]; then
        echo -e "    ${DIM}Available themes: dark, light, solarized-dark, catppuccin-mocha, dracula, nord${RESET}"
        THEME_DAY=$(ask "Day theme" "$D_THEME_DAY")
        THEME_NIGHT=$(ask "Night theme" "$D_THEME_NIGHT")
        THEME_DAY_START=$(ask "Day starts at (HH:MM, 24h)" "$D_THEME_DAY_START")
        THEME_NIGHT_START=$(ask "Night starts at (HH:MM, 24h)" "$D_THEME_NIGHT_START")
    else
        THEME_DAY="$D_THEME_DAY"
        THEME_NIGHT="$D_THEME_NIGHT"
        THEME_DAY_START="$D_THEME_DAY_START"
        THEME_NIGHT_START="$D_THEME_NIGHT_START"
    fi
    echo ""

    # -- Auto-update --
    echo -e "  ${BOLD}Auto-update:${RESET}"
    UPDATE_CHECK=$(ask_yn "Check for updates when running the installer" "$D_UPDATE_CHECK")
    UPDATE_NOTIFY_ONLY=$(ask_yn "Notify only (don't auto-pull)" "$D_UPDATE_NOTIFY_ONLY")
    echo ""

    # -- Colors / Theme --
    echo -e "  ${BOLD}Color theme:${RESET}"
    echo -e "    1) dark ${DIM}(default)${RESET}"
    echo -e "    2) light"
    echo -e "    3) solarized-dark"
    echo -e "    4) catppuccin-mocha"
    echo -e "    5) dracula"
    echo -e "    6) nord"
    echo -e "    7) Custom ${DIM}(enter RGBA values manually)${RESET}"
    THEME_CHOICE=$(ask "Choose" "1")

    if [ "$THEME_CHOICE" = "7" ]; then
        # Manual RGBA entry
        echo ""
        echo -e "    ${DIM}Enter colors as: R G B A (values 0.0-1.0, space-separated)${RESET}"
        echo ""
        echo -e "    ${BOLD}Normal state:${RESET}"
        NORMAL_BG=$(ask_rgba "Background" "0.05 0.05 0.07 0.96")
        NORMAL_BORDER=$(ask_rgba "Border" "1.0 1.0 1.0 0.08")
        NORMAL_TITLE=$(ask_rgba "Title text" "0.85 0.55 0.40 1.0")
        NORMAL_TEXT=$(ask_rgba "Message text" "0.95 0.95 0.95 1.0")
        echo ""
        echo -e "    ${BOLD}Warning state (rate limit > ${WARN_THRESHOLD}%):${RESET}"
        WARNING_BG=$(ask_rgba "Background" "0.12 0.09 0.04 0.96")
        WARNING_BORDER=$(ask_rgba "Border" "0.85 0.65 0.20 0.25")
        WARNING_TITLE=$(ask_rgba "Title text" "0.85 0.55 0.40 1.0")
        WARNING_TEXT=$(ask_rgba "Message text" "0.95 0.95 0.95 1.0")
        echo ""
        echo -e "    ${BOLD}Critical state (rate limit > ${CRIT_THRESHOLD}%):${RESET}"
        CRITICAL_BG=$(ask_rgba "Background" "0.14 0.04 0.04 0.96")
        CRITICAL_BORDER=$(ask_rgba "Border" "0.90 0.25 0.20 0.30")
        CRITICAL_TITLE=$(ask_rgba "Title text" "0.85 0.55 0.40 1.0")
        CRITICAL_TEXT=$(ask_rgba "Message text" "0.95 0.95 0.95 1.0")
    else
        # Load theme from themes.json
        eval "$(python3 -c "
import json, shlex
theme_map = {'1':'dark','2':'light','3':'solarized-dark','4':'catppuccin-mocha','5':'dracula','6':'nord'}
theme_name = theme_map.get('$THEME_CHOICE', 'dark')
with open('$REPO_DIR/assets/themes.json') as f:
    themes = json.load(f)
theme = themes.get(theme_name, themes['dark'])
colors = theme['colors']
# Map to installer variable names: NORMAL_BG, NORMAL_BORDER, etc.
role_map = {'background': 'BG', 'border': 'BORDER', 'title': 'TITLE', 'text': 'TEXT'}
for urgency in ['normal','warning','critical']:
    for role, short in role_map.items():
        vals = colors[urgency][role]
        var = urgency.upper() + '_' + short
        val = '[' + ', '.join(str(v) for v in vals) + ']'
        print(f'{var}={shlex.quote(val)}')
" 2>&1)" || {
            warn "Failed to load theme - using dark defaults"
            NORMAL_BG="[0.05, 0.05, 0.07, 0.96]"; NORMAL_BORDER="[1.0, 1.0, 1.0, 0.08]"
            NORMAL_TITLE="[0.85, 0.55, 0.40, 1.0]"; NORMAL_TEXT="[0.95, 0.95, 0.95, 1.0]"
            WARNING_BG="[0.12, 0.09, 0.04, 0.96]"; WARNING_BORDER="[0.85, 0.65, 0.20, 0.25]"
            WARNING_TITLE="[0.85, 0.55, 0.40, 1.0]"; WARNING_TEXT="[0.95, 0.95, 0.95, 1.0]"
            CRITICAL_BG="[0.14, 0.04, 0.04, 0.96]"; CRITICAL_BORDER="[0.90, 0.25, 0.20, 0.30]"
            CRITICAL_TITLE="[0.85, 0.55, 0.40, 1.0]"; CRITICAL_TEXT="[0.95, 0.95, 0.95, 1.0]"
        }
    fi
    echo ""
fi

# ──────────────────────────────────────────────────────────────
# 3. Write config file (if interactive config was done)
# ──────────────────────────────────────────────────────────────

if [ "$SHOULD_CONFIGURE" = "true" ]; then
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_DIR/config.json" << CONFIGEOF
{
  "notification": {
    "enabled": true,
    "position": "${POSITION}",
    "width": ${WIDTH},
    "max_lines": ${MAX_LINES},
    "corner_radius": ${CORNER_RADIUS},
    "duration_seconds": ${DURATION},
    "icon": "${ICON_FILE}",

    "colors": {
      "normal": {
        "background": ${NORMAL_BG},
        "border": ${NORMAL_BORDER},
        "title": ${NORMAL_TITLE},
        "text": ${NORMAL_TEXT}
      },
      "warning": {
        "background": ${WARNING_BG},
        "border": ${WARNING_BORDER},
        "title": ${WARNING_TITLE},
        "text": ${WARNING_TEXT}
      },
      "critical": {
        "background": ${CRITICAL_BG},
        "border": ${CRITICAL_BORDER},
        "title": ${CRITICAL_TITLE},
        "text": ${CRITICAL_TEXT}
      }
    }
  },

  "sound": {
    "enabled": ${SOUND_ENABLED},
    "file": "${SOUND_FILE}",
    "volume": ${SOUND_VOLUME}
  },

  "terminal_apps": [
    "com.apple.Terminal",
    "com.googlecode.iterm2",
    "net.kovidgoyal.kitty",
    "co.zeit.hyper",
    "com.mitchellh.ghostty",
    "io.alacritty",
    "dev.warp.Warp-Stable"
  ],

  "rate_limits": {
    "warning_threshold": ${WARN_THRESHOLD},
    "critical_threshold": ${CRIT_THRESHOLD}
  },

  "status_line": {
    "enabled": ${SL_ENABLED},
    "show_context_bar": ${SHOW_CTX},
    "show_rate_5h": ${SHOW_5H},
    "show_rate_7d": ${SHOW_7D},
    "show_lines_changed": ${SHOW_LINES}
  },

  "message": {
    "max_length": 300
  },

  "skip_if_focused": ${SKIP_FOCUSED},

  "quiet_hours": {
    "enabled": ${QUIET_ENABLED},
    "start": "${QUIET_START}",
    "end": "${QUIET_END}"
  },

  "history": {
    "enabled": ${HISTORY_ENABLED},
    "max_entries": ${HISTORY_MAX},
    "clear_after_days": ${HISTORY_DAYS}
  },

  "theme": {
    "auto": ${THEME_AUTO},
    "day": "${THEME_DAY}",
    "night": "${THEME_NIGHT}",
    "day_start": "${THEME_DAY_START}",
    "night_start": "${THEME_NIGHT_START}"
  },

  "auto_update": {
    "check_on_install": ${UPDATE_CHECK},
    "notify_only": ${UPDATE_NOTIFY_ONLY}
  }
}
CONFIGEOF
    chmod 0600 "$CONFIG_DIR/config.json"
    success "Config written: $CONFIG_DIR/config.json"
fi

# ──────────────────────────────────────────────────────────────
# 4. Run non-interactive setup (assets, compile, hooks)
# ──────────────────────────────────────────────────────────────

"$SCRIPT_DIR/setup.sh" "$REPO_DIR"

echo ""

# ──────────────────────────────────────────────────────────────
# Done!
# ──────────────────────────────────────────────────────────────

echo -e "${BOLD}${GREEN}Installation complete!${RESET}"
echo ""
echo -e "  Config:  ${CYAN}$CONFIG_DIR/config.json${RESET}"
echo -e "  Binary:  ${CYAN}$CONFIG_DIR/notch-notify${RESET}"
echo -e "  Hooks:   ${CYAN}$SETTINGS_FILE${RESET}"
echo ""
echo -e "  ${BOLD}Next steps:${RESET}"
echo -e "  1. Restart Claude Code (or start a new session)"
echo -e "  2. Run ${CYAN}/hooks${RESET} inside Claude Code to verify"
echo -e "  3. Edit ${CYAN}$CONFIG_DIR/config.json${RESET} anytime to tweak settings"
echo -e "     Changes take effect immediately - no recompile needed."
echo -e "  4. Run ${CYAN}./install.sh --reconfigure${RESET} to re-run this setup wizard"
echo ""

# Show a test notification to confirm it works
"$CONFIG_DIR/notch-notify" "Claude Tap" "Installation successful! Click to focus terminal." "$CONFIG_DIR/claude-icon.png" &
