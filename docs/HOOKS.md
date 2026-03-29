# Claude Code Hooks Integration

This document explains how Claude Tap integrates with Claude Code's hooks system.

> **Note:** The hook format is the same on all platforms. macOS and Linux use bash scripts, Windows uses PowerShell. Linux and Windows support is not currently tested. If you encounter issues, please [report them](https://github.com/EdoardoCroci/claude-tap/issues).

## What are hooks?

Hooks are shell commands that Claude Code runs automatically in response to specific events. They're configured in `~/.claude/settings.json` under the `hooks` key.

Claude Tap registers two hooks and a status line command. The installer handles this automatically.

Clicking on any notification brings your terminal (Terminal, Ghostty, iTerm2, Kitty, Warp, Hyper, or Alacritty) to the foreground and dismisses the notification. The list of supported terminals is configurable via the `terminal_apps` setting.

## Registered hooks

### Notification hook

**Event:** Claude Code needs the user's attention (e.g., a permission prompt, a question).

**What happens:**
1. Claude Code sends a JSON payload to `notify.sh` via stdin
2. The script extracts `title` and `message` fields
3. A sound is played and the notification overlay is shown

**Stdin JSON shape:**
```json
{
  "title": "Claude Code",
  "message": "Claude needs your attention"
}
```

### Stop hook

**Event:** Claude Code finishes responding (the assistant turn is complete).

**What happens:**
1. Claude Code sends a JSON payload to `notify.sh` via stdin
2. The script extracts `last_assistant_message`
3. If the terminal is focused and `skip_if_focused` is `true`, the notification is suppressed
4. Otherwise, a sound is played and the notification overlay is shown with the response preview

**Stdin JSON shape:**
```json
{
  "last_assistant_message": "I've updated the file with the changes you requested. The function now handles edge cases for empty input..."
}
```

The message is collapsed from multiple lines into one and truncated to `message.max_length` characters (default: 300).

### Status line

**Event:** After each assistant message, on permission mode change, and on vim mode toggle. Debounced at 300ms.

**What happens:**
1. Claude Code sends a JSON payload to `statusline.sh` via stdin
2. The script extracts context window, rate limit, and cost data
3. It outputs an ANSI-colored line that Claude Code displays at the bottom of the interface
4. If rate limit thresholds are crossed, a warning notification is triggered

**Stdin JSON shape (key fields):**
```json
{
  "model": { "display_name": "Claude Opus 4.6" },
  "context_window": {
    "used_percentage": 42.5,
    "remaining_percentage": 57.5,
    "context_window_size": 200000
  },
  "rate_limits": {
    "five_hour": {
      "used_percentage": 76.3,
      "resets_at": 1711555200
    },
    "seven_day": {
      "used_percentage": 45.1,
      "resets_at": 1712073600
    }
  },
  "cost": {
    "total_lines_added": 234,
    "total_lines_removed": 56
  }
}
```

## How hooks are registered

The installer adds entries to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/claude-tap/macos/src/notify.sh"
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/claude-tap/macos/src/notify.sh"
          }
        ]
      }
    ]
  },
  "statusLine": {
    "type": "command",
    "command": "/path/to/claude-tap/macos/src/statusline.sh",
    "padding": 2
  }
}
```

Each hook entry requires a `matcher` (empty string to match all events) and a `hooks` array containing the command definitions. This is the format Claude Code expects - using the wrong structure will cause validation errors.

The same `notify.sh` script handles both Notification and Stop events - it detects which type of event it received by checking for the presence of `last_assistant_message` in the stdin JSON.

## Manual hook management

To verify hooks are registered, run `/hooks` inside Claude Code.

To manually add or remove hooks, edit `~/.claude/settings.json` directly. The installer backs up this file before modifying it.

To temporarily disable hooks without uninstalling, set `notification.enabled`, `sound.enabled`, and `status_line.enabled` to `false` in your config file.

## Security

Hook scripts run with your user permissions. The `notify.sh` script:
- Reads stdin JSON (from Claude Code)
- Reads the config file
- Runs `osascript` to check which app is frontmost
- Runs `afplay` to play a sound
- Launches the compiled `notch-notify` binary

No data is sent to external services. Everything runs locally.
