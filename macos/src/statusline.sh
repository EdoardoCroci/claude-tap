#!/usr/bin/env bash
# Claude Tap - Status line script for Claude Code.
#
# This script runs after each assistant message and outputs a single line
# displayed at the bottom of the Claude Code interface. It shows:
#   - Model name (bold, orange)
#   - Context window usage with progress bar (green/yellow/red)
#   - 5-hour rate limit with reset countdown
#   - 7-day rate limit with reset countdown
#   - Lines added/removed in the session
#
# Each section can be toggled on/off in config.json under "status_line".
# Rate limit warnings are triggered here (via the notification binary)
# when usage crosses the configured thresholds.
#
# Input: JSON on stdin (provided by Claude Code)
# Output: ANSI-colored text line on stdout

CONFIG_FILE="$HOME/.config/claude-tap/config.json"
CONFIG_DIR="$HOME/.config/claude-tap"

input=$(cat)

# ──────────────────────────────────────────────────────────────
# Parse JSON fields from Claude Code
# ──────────────────────────────────────────────────────────────

model=$(echo "$input" | jq -r '.model.display_name // "Claude"')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
five_hour=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
five_hour_resets=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
seven_day=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
seven_day_resets=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')
lines_added=$(echo "$input" | jq -r '.cost.total_lines_added // empty')
lines_removed=$(echo "$input" | jq -r '.cost.total_lines_removed // empty')

# ──────────────────────────────────────────────────────────────
# Read config toggles (via python3 for JSON parsing)
# ──────────────────────────────────────────────────────────────

eval "$(python3 -c "
import json, os
path = os.path.expanduser('~/.config/claude-tap/config.json')
try:
    with open(path) as f:
        c = json.load(f)
except:
    c = {}
sl = c.get('status_line', {})
rl = c.get('rate_limits', {})
import shlex
print(f'SL_ENABLED={shlex.quote(str(sl.get(\"enabled\", True)).lower())}')
print(f'SHOW_CTX={shlex.quote(str(sl.get(\"show_context_bar\", True)).lower())}')
print(f'SHOW_5H={shlex.quote(str(sl.get(\"show_rate_5h\", True)).lower())}')
print(f'SHOW_7D={shlex.quote(str(sl.get(\"show_rate_7d\", True)).lower())}')
print(f'SHOW_LINES={shlex.quote(str(sl.get(\"show_lines_changed\", True)).lower())}')
print(f'WARN_THRESHOLD={shlex.quote(str(int(rl.get(\"warning_threshold\", 80))))}')
print(f'CRIT_THRESHOLD={shlex.quote(str(int(rl.get(\"critical_threshold\", 90))))}')
snd = c.get('sound', {})
print(f'SND_ENABLED={shlex.quote(str(snd.get(\"enabled\", True)).lower())}')
print(f'SND_VOLUME={shlex.quote(str(snd.get(\"volume\", 0.15)))}')
rate_warn_snd = snd.get('files', {}).get('rate_limit_warning', '')
rate_warn_snd = os.path.expanduser(rate_warn_snd) if rate_warn_snd else ''
default_snd = os.path.expanduser(snd.get('file', '~/.config/claude-tap/default.wav'))
print(f'SND_RATE_WARN={shlex.quote(rate_warn_snd)}')
print(f'SND_DEFAULT={shlex.quote(default_snd)}')
qh = c.get('quiet_hours', {})
quiet_enabled = qh.get('enabled', False)
quiet_start = qh.get('start', '22:00')
quiet_end = qh.get('end', '07:00')
print(f'QUIET_ENABLED={shlex.quote(str(quiet_enabled).lower())}')
print(f'QUIET_START={shlex.quote(quiet_start)}')
print(f'QUIET_END={shlex.quote(quiet_end)}')
" 2>/dev/null)" || {
    SL_ENABLED="true"
    SHOW_CTX="true"
    SHOW_5H="true"
    SHOW_7D="true"
    SHOW_LINES="true"
    WARN_THRESHOLD=80
    CRIT_THRESHOLD=90
    SND_ENABLED="true"
    SND_VOLUME="0.15"
    SND_RATE_WARN=""
    SND_DEFAULT="$HOME/.config/claude-tap/default.wav"
    QUIET_ENABLED="false"
    QUIET_START="22:00"
    QUIET_END="07:00"
}

# Exit silently if status line is disabled
[ "$SL_ENABLED" != "true" ] && exit 0

# ──────────────────────────────────────────────────────────────
# ANSI color definitions
# ──────────────────────────────────────────────────────────────

RESET='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'
ORANGE='\033[38;5;215m'
GREEN='\033[38;5;114m'
RED='\033[38;5;174m'
YELLOW='\033[38;5;222m'
GRAY='\033[38;5;245m'

# ──────────────────────────────────────────────────────────────
# Helper functions
# ──────────────────────────────────────────────────────────────

# Returns a color escape code based on a percentage (green < 50 < yellow < 80 < red)
pct_color() {
  local pct=$1
  if [ "$pct" -lt 50 ]; then
    echo "$GREEN"
  elif [ "$pct" -lt 80 ]; then
    echo "$YELLOW"
  else
    echo "$RED"
  fi
}

# Formats a Unix epoch timestamp as a human-readable countdown (e.g., "2h34m")
format_reset() {
  local resets_at="$1"
  if [ -n "$resets_at" ]; then
    local now resets_sec diff
    now=$(date +%s)
    resets_sec=$(printf '%.0f' "$resets_at")
    diff=$((resets_sec - now))
    if [ "$diff" -gt 0 ]; then
      local days=$((diff / 86400))
      local hours=$(( (diff % 86400) / 3600 ))
      local mins=$(( (diff % 3600) / 60 ))
      if [ "$days" -gt 0 ]; then
        echo "${days}d${hours}h${mins}m"
      else
        echo "${hours}h${mins}m"
      fi
    fi
  fi
}

# ──────────────────────────────────────────────────────────────
# Build status line sections
# ──────────────────────────────────────────────────────────────

# Context window usage - 10-block progress bar
ctx_part=""
if [ "$SHOW_CTX" = "true" ] && [ -n "$used_pct" ]; then
  pct_int=$(printf '%.0f' "$used_pct")
  filled=$(echo "$used_pct" | awk '{printf "%d", int($1 / 10 + 0.5)}')
  BAR_COLOR=$(pct_color "$pct_int")
  bar=""
  for i in $(seq 1 10); do
    if [ "$i" -le "$filled" ]; then
      bar="${bar}▓"
    else
      bar="${bar}░"
    fi
  done
  ctx_part="${BAR_COLOR}${pct_int}%${RESET} ${BAR_COLOR}${bar}${RESET}"
elif [ "$SHOW_CTX" = "true" ]; then
  ctx_part="${DIM}ctx: n/a${RESET}"
fi

# 5-hour rate limit with reset countdown
rate_5h_part=""
if [ "$SHOW_5H" = "true" ] && [ -n "$five_hour" ]; then
  rate_int=$(printf '%.0f' "$five_hour")
  RATE_COLOR=$(pct_color "$rate_int")
  rate_5h_part="${GRAY}5h:${RESET} ${RATE_COLOR}${rate_int}%${RESET}"
  reset_str=$(format_reset "$five_hour_resets")
  [ -n "$reset_str" ] && rate_5h_part="${rate_5h_part} ${DIM}(${reset_str})${RESET}"

  # Cache rate limit percentage for notification tinting (use $TMPDIR for per-user isolation)
  CLAUDE_TMPDIR="${TMPDIR:-/tmp}"
  echo "$rate_int" > "$CLAUDE_TMPDIR/claude-rate-limit"



  # Trigger rate limit warning notifications at configured thresholds
  if [ "$rate_int" -ge "$CRIT_THRESHOLD" ]; then
    if [ ! -f "$CLAUDE_TMPDIR/claude-rate-warn-critical" ]; then
      touch "$CLAUDE_TMPDIR/claude-rate-warn-critical"
      reset_msg=""
      [ -n "$reset_str" ] && reset_msg=" Resets in ${reset_str}."
      "$CONFIG_DIR/notch-notify" "Rate Limit Warning" "5h usage at ${rate_int}%.${reset_msg} Consider slowing down." "$CONFIG_DIR/claude-icon.png" "critical" &
      if [ "$SND_ENABLED" = "true" ]; then
          RATE_SND="${SND_RATE_WARN:-$SND_DEFAULT}"
          [ -f "$RATE_SND" ] && afplay -v "$SND_VOLUME" "$RATE_SND" &
      fi
    fi
  elif [ "$rate_int" -ge "$WARN_THRESHOLD" ]; then
    if [ ! -f "$CLAUDE_TMPDIR/claude-rate-warn-warning" ]; then
      touch "$CLAUDE_TMPDIR/claude-rate-warn-warning"
      reset_msg=""
      [ -n "$reset_str" ] && reset_msg=" Resets in ${reset_str}."
      "$CONFIG_DIR/notch-notify" "Rate Limit Warning" "5h usage at ${rate_int}%.${reset_msg}" "$CONFIG_DIR/claude-icon.png" "warning" &
      if [ "$SND_ENABLED" = "true" ]; then
          RATE_SND="${SND_RATE_WARN:-$SND_DEFAULT}"
          [ -f "$RATE_SND" ] && afplay -v "$SND_VOLUME" "$RATE_SND" &
      fi
    fi
  else
    # Reset warning markers when usage drops back down
    rm -f "$CLAUDE_TMPDIR/claude-rate-warn-warning" "$CLAUDE_TMPDIR/claude-rate-warn-critical"
  fi
fi

# 7-day rate limit with reset countdown
rate_7d_part=""
if [ "$SHOW_7D" = "true" ] && [ -n "$seven_day" ]; then
  rate_7d_int=$(printf '%.0f' "$seven_day")
  RATE_7D_COLOR=$(pct_color "$rate_7d_int")
  rate_7d_part="${GRAY}7d:${RESET} ${RATE_7D_COLOR}${rate_7d_int}%${RESET}"
  reset_7d_str=$(format_reset "$seven_day_resets")
  [ -n "$reset_7d_str" ] && rate_7d_part="${rate_7d_part} ${DIM}(${reset_7d_str})${RESET}"
fi

# Lines added/removed
lines_part=""
if [ "$SHOW_LINES" = "true" ]; then
  if [ -n "$lines_added" ] || [ -n "$lines_removed" ]; then
    added=${lines_added:-0}
    removed=${lines_removed:-0}
    lines_part="${GREEN}+$(printf '%.0f' "$added")${RESET} ${RED}-$(printf '%.0f' "$removed")${RESET}"
  fi
fi

# DND indicator
dnd_part=""
DND_ACTIVE="false"
if [ -f "$HOME/.config/claude-tap/dnd" ]; then
    DND_ACTIVE="true"
fi
if [ "$QUIET_ENABLED" = "true" ] && [ "$DND_ACTIVE" = "false" ]; then
    CURRENT_TIME=$(date +%H:%M)
    if [[ "$QUIET_START" > "$QUIET_END" ]]; then
        if [[ ! "$CURRENT_TIME" < "$QUIET_START" || "$CURRENT_TIME" < "$QUIET_END" ]]; then
            DND_ACTIVE="true"
        fi
    else
        if [[ ! "$CURRENT_TIME" < "$QUIET_START" && "$CURRENT_TIME" < "$QUIET_END" ]]; then
            DND_ACTIVE="true"
        fi
    fi
fi
if [ "$DND_ACTIVE" = "true" ]; then
    dnd_part="${DIM}DND${RESET}"
fi

# ──────────────────────────────────────────────────────────────
# Assemble and output
# ──────────────────────────────────────────────────────────────

out="${BOLD}${ORANGE}${model}${RESET}"
[ -n "$ctx_part" ]     && out="${out} ${GRAY}│${RESET} ${ctx_part}"
[ -n "$rate_5h_part" ] && out="${out} ${GRAY}│${RESET} ${rate_5h_part}"
[ -n "$rate_7d_part" ] && out="${out} ${GRAY}│${RESET} ${rate_7d_part}"
[ -n "$lines_part" ]   && out="${out} ${GRAY}│${RESET} ${lines_part}"
[ -n "$dnd_part" ]     && out="${out} ${GRAY}│${RESET} ${dnd_part}"

echo -e "$out"
