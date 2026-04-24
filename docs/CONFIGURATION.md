# Configuration Reference

Config location:
- **macOS:** `~/.config/claude-tap/config.json`
- **Linux:** `~/.config/claude-tap/config.json`
- **Windows:** `%LOCALAPPDATA%\claude-tap\config.json`

Changes take effect immediately - no recompile or restart needed. The notification binary and shell scripts read this file fresh on every invocation.

If the config file is missing or contains invalid JSON, all settings fall back to their defaults. You can also omit any field you don't want to customize - only the fields you include will override the defaults.

> **Note:** macOS is the primary tested platform. Linux (Python/GTK3 overlay, falls back to `notify-send`) and Windows are included but not currently tested. The config format is the same on all platforms, but `terminal_apps` uses different identifiers (see below).

---

## Markdown rendering

Notification messages support inline markdown. The following syntax is rendered natively in the overlay (macOS and Linux):

| Syntax | Rendered as |
|--------|-------------|
| `**bold**` | **bold** |
| `*italic*` or `_italic_` | *italic* |
| `` `code` `` | monospaced code |
| `[text](url)` | Clickable link (macOS/Linux) |
| `# Header` | Bold header text |
| `- item` or `* item` | Bullet list item |

Windows notifications do not render markdown (text is shown as-is).

---

## Theme presets

The installer offers 6 built-in color themes. Themes are stored in `assets/themes.json` and set all 12 color values (3 urgency levels x 4 roles) at once:

| Theme | Description |
|-------|-------------|
| `dark` | Default — near-black background, warm orange accents |
| `light` | White/light gray background, dark text |
| `solarized-dark` | Solarized dark palette with cyan/orange accents |
| `catppuccin-mocha` | Catppuccin Mocha with pink/mauve accents |
| `dracula` | Dracula palette with purple accents |
| `nord` | Nord polar night with frost blue accents |

Select a theme during `./install.sh --reconfigure`, or choose "Custom" to enter RGBA values manually. You can also edit `config.json` directly — theme selection just pre-fills the `notification.colors` values.

### Auto-theme (day/night switching)

Automatically switch between two themes based on time of day. The overlay checks the current time on every notification and loads the appropriate theme from `themes.json`.

### theme.auto

| Type | Default |
|------|---------|
| boolean | `false` |

Set to `true` to enable automatic theme switching. When enabled, `notification.colors` in your config is overridden at runtime by the selected theme.

### theme.day / theme.night

| Type | Default |
|------|---------|
| string | `"light"` / `"dark"` |

Theme names to use during day and night. Must match a key in `assets/themes.json`: `dark`, `light`, `solarized-dark`, `catppuccin-mocha`, `dracula`, `nord`.

### theme.day_start / theme.night_start

| Type | Default |
|------|---------|
| string (HH:MM) | `"08:00"` / `"18:00"` |

Time boundaries in 24-hour format. Day theme is active from `day_start` to `night_start`, night theme at all other times.

### Example

```json
{
  "theme": {
    "auto": true,
    "day": "light",
    "night": "catppuccin-mocha",
    "day_start": "07:30",
    "night_start": "19:00"
  }
}
```

---

## notification

### notification.enabled

| Type | Default |
|------|---------|
| boolean | `true` |

Set to `false` to disable the visual notification overlay entirely. Sound will still play if `sound.enabled` is `true`.

### notification.show_on_waiting

| Type | Default |
|------|---------|
| boolean | `false` |

Controls **idle "Claude is waiting for your input"** pings only. These fire roughly every 60 seconds whenever Claude is idle-waiting on you and are noisy by design, so they stay suppressed by default (no sound, no overlay, no history entry). Set to `true` if you want a heartbeat every time Claude is idle. Tool-permission prompts are handled by `show_on_permission` below — changing this value has no effect on them.

### notification.show_on_permission

| Type | Default |
|------|---------|
| boolean | `true` |

Controls **tool-permission prompts** — the blocking "Claude needs your permission to use X" events fired by the `Notification` hook. Shown by default since Claude halts until you respond. Set to `false` if you drive Claude only via pre-approved tools and don't want permission overlays.

Classification is done by substring-matching the message delivered to the hook: anything containing `permission` (case-insensitive) is treated as a permission prompt; messages containing `waiting for your input` are treated as idle-waiting; any other Notification-hook message falls through to `permission` so unexpected attention-required events still surface.

### notification.dedup_window_secs

| Type | Default |
|------|---------|
| integer | `2` |

Suppress a repeat notification when the previous one had the **same hook type, title, and message** and fired within this many seconds. Catches cases where Claude Code re-fires the same `Notification` hook back-to-back (e.g. on reconnect). Set to `0` to disable deduplication.

The comparison key is `hook_type|title|message`, stored in `$TMPDIR/claude-last-notif`. Within-window duplicates exit before the history writer, so they don't pollute `history.json` either.

### notification.position

| Type | Default |
|------|---------|
| string | `"top-center"` |

Where the notification appears on screen.

| Option | Description |
|--------|-------------|
| `"top-center"` | Below the menu bar, centered (default) |
| `"top-left"` | Below the menu bar, left side |
| `"top-right"` | Below the menu bar, right side |
| `"bottom-center"` | Above the dock, centered |
| `"bottom-left"` | Above the dock, left side |
| `"bottom-right"` | Above the dock, right side |

The slide animation direction adapts automatically - top positions slide down from above, bottom positions slide up from below.

### notification.width

| Type | Default |
|------|---------|
| number | `380` |

Width of the notification card in points. The height is calculated automatically based on the message content.

### notification.max_lines

| Type | Default |
|------|---------|
| integer | `3` |

Maximum number of lines for the message text. Messages longer than this are truncated with an ellipsis. The notification height adapts to the actual number of lines used (1 to `max_lines`).

### notification.corner_radius

| Type | Default |
|------|---------|
| number | `16` |

Corner rounding of the notification card in points. Set to `0` for sharp corners.

### notification.duration_seconds

| Type | Default |
|------|---------|
| number | `5.5` |

How long the notification stays visible before auto-dismissing (in seconds). The notification can also be dismissed early by clicking it.

### notification.icon

| Type | Default |
|------|---------|
| string (path) | `""` (uses bundled Claude icon) |

Path to a custom icon image displayed in the notification. Supports PNG format. The `~` is expanded automatically. When empty or the file doesn't exist, the bundled Claude icon is used.

Example:

```json
{
  "notification": {
    "icon": "~/Pictures/my-icon.png"
  }
}
```

### notification.colors

Colors for each urgency level. Each urgency (`normal`, `warning`, `critical`) has four color roles:

| Role | Description |
|------|-------------|
| `background` | Card background color |
| `border` | Subtle border around the card |
| `title` | Title text color (e.g., "Task Complete") |
| `text` | Message body text color |

Each color is an `[R, G, B, A]` array with float values from `0.0` to `1.0`:

```json
"background": [0.05, 0.05, 0.07, 0.96]
```

The alpha channel controls transparency. A value of `0.96` gives a near-opaque look with a hint of the desktop showing through.

**Default colors:**

| Urgency | Background | Appearance |
|---------|-----------|------------|
| `normal` | `[0.05, 0.05, 0.07, 0.96]` | Near-black |
| `warning` | `[0.12, 0.09, 0.04, 0.96]` | Dark amber |
| `critical` | `[0.14, 0.04, 0.04, 0.96]` | Dark red |

You can define custom urgency colors while leaving others at their defaults - just include the ones you want to change.

---

## sound

### sound.enabled

| Type | Default |
|------|---------|
| boolean | `true` |

Set to `false` to disable the notification sound. The visual overlay will still appear if `notification.enabled` is `true`.

### sound.file

| Type | Default |
|------|---------|
| string (path) | `"~/.config/claude-tap/default.wav"` |

Path to the audio file to play. The `~` is expanded automatically.

- **macOS:** Supports `.wav` and `.aiff` formats (anything `afplay` can handle).
- **Linux:** `.wav` format via `paplay` (PulseAudio), `pw-play` (PipeWire), or `aplay` (ALSA).
- **Windows:** Only `.wav` format is supported (`System.Media.SoundPlayer`). MP3 and other formats will not work.

**macOS system sounds** are located at `/System/Library/Sounds/`. Some popular choices:

| Sound | Path |
|-------|------|
| Glass | `/System/Library/Sounds/Glass.aiff` |
| Ping | `/System/Library/Sounds/Ping.aiff` |
| Pop | `/System/Library/Sounds/Pop.aiff` |
| Purr | `/System/Library/Sounds/Purr.aiff` |
| Submarine | `/System/Library/Sounds/Submarine.aiff` |
| Tink | `/System/Library/Sounds/Tink.aiff` |

### sound.volume

| Type | Default | Range |
|------|---------|-------|
| number | `0.15` | `0.0` - `1.0` |

Playback volume. `0.0` is silent, `1.0` is full system volume. The default `0.15` is deliberately quiet.

**Linux note:** Volume is mapped to `paplay`'s 0-65536 range (multiply by 65536). `pw-play` uses native 0.0-1.0 floats. `aplay` does not support volume control.

### sound.files

Per-event sound overrides. Each entry is a file path. When set and the file exists, it is used instead of `sound.file` for that event type. When empty (`""`), falls back to `sound.file`.

| Key | Event |
|-----|-------|
| `sound.files.stop` | Claude finished a task (Stop hook) |
| `sound.files.notification` | Claude needs attention (Notification hook) |
| `sound.files.rate_limit_warning` | Rate limit threshold crossed |

Example:

```json
{
  "sound": {
    "file": "~/.config/claude-tap/default.wav",
    "volume": 0.15,
    "files": {
      "stop": "/System/Library/Sounds/Glass.aiff",
      "notification": "/System/Library/Sounds/Ping.aiff",
      "rate_limit_warning": "/System/Library/Sounds/Sosumi.aiff"
    }
  }
}
```

**Windows note:** Volume control is not currently supported on Windows. The sound plays at system volume regardless of this setting. This is a limitation of `System.Media.SoundPlayer`.

---

## terminal_apps

| Type | Default |
|------|---------|
| array of strings | *(see below)* |

Terminal identifiers. Used for two purposes:

1. **Skip-if-focused** - When `skip_if_focused` is `true` and a Stop event fires, the notification is suppressed if any of these apps is the frontmost window.
2. **Click-to-focus** - Clicking the notification brings your terminal to the foreground. It scans this list in order and activates the first running match. If you use Ghostty, for example, clicking the notification will switch to your Ghostty window. The notification is also dismissed on click.

**macOS** - uses bundle IDs. Default:

```json
[
  "com.apple.Terminal",
  "com.googlecode.iterm2",
  "net.kovidgoyal.kitty",
  "co.zeit.hyper",
  "com.mitchellh.ghostty",
  "io.alacritty",
  "dev.warp.Warp-Stable",
  "com.microsoft.VSCode",
  "com.microsoft.VSCodeInsiders",
  "com.todesktop.230313mzl4w4u92"
]
```

To find your terminal's bundle ID:

```bash
osascript -e 'id of app "YourTerminalName"'
```

**Linux** - uses process names (as shown by `ps`). Default:

```json
[
  "kitty",
  "alacritty",
  "ghostty",
  "wezterm",
  "foot",
  "gnome-terminal",
  "konsole",
  "xfce4-terminal",
  "xterm",
  "code",
  "code-insiders",
  "cursor"
]
```

Terminal focus detection uses `xdotool` (X11). On Wayland, focus detection may not work — notifications will always be shown.

**Windows (not tested)** - uses process names (as shown in Task Manager). Default:

```json
[
  "WindowsTerminal",
  "powershell",
  "pwsh",
  "cmd",
  "mintty",
  "git-bash",
  "alacritty",
  "ghostty",
  "Hyper",
  "Warp",
  "Code",
  "Code - Insiders",
  "Cursor"
]
```

---

## rate_limits

### rate_limits.warning_threshold

| Type | Default |
|------|---------|
| integer | `80` |

When the 5-hour rate limit usage reaches this percentage, a one-time notification with amber tinting is shown. The warning resets when usage drops below this value.

### rate_limits.critical_threshold

| Type | Default |
|------|---------|
| integer | `90` |

When the 5-hour rate limit usage reaches this percentage, a one-time notification with red tinting is shown. All subsequent task-complete notifications also use red tinting while above this threshold.

---

## status_line

### status_line.enabled

| Type | Default |
|------|---------|
| boolean | `true` |

Set to `false` to disable the status line entirely. No output will be produced.

### status_line.show_context_bar

| Type | Default |
|------|---------|
| boolean | `true` |

Show the context window usage percentage with a 10-block progress bar. Colors shift from green (<50%) to yellow (50-80%) to red (>80%).

### status_line.show_rate_5h

| Type | Default |
|------|---------|
| boolean | `true` |

Show the 5-hour rolling rate limit usage with a countdown and absolute reset clock time. Format: `2h34m · 15:00` when the reset is under 24 hours away, or `3d4h17m · Thu 22:00` when further out. This section also triggers rate limit warning notifications.

### status_line.show_rate_7d

| Type | Default |
|------|---------|
| boolean | `true` |

Show the 7-day rolling rate limit usage with a countdown and absolute reset clock time. Format: `2h34m · 15:00` when the reset is under 24 hours away, or `3d4h17m · Thu 22:00` when further out.

### status_line.show_lines_changed

| Type | Default |
|------|---------|
| boolean | `true` |

Show lines added (green) and removed (red) in the current session.

### status_line.show_git_branch

| Type | Default |
|------|---------|
| boolean | `true` |

Show the current git branch (or short SHA in detached HEAD) for the session's working directory. Suppressed silently when outside a git repository or when `git` is not installed.

---

## message

### message.max_length

| Type | Default |
|------|---------|
| integer | `300` |

Maximum character length for notification messages. Claude's response is collapsed from multi-line to single-line and truncated to this length. An ellipsis (`...`) is appended if the original was longer.

---

## skip_if_focused

| Type | Default |
|------|---------|
| boolean | `true` |

When `true`, Stop hook notifications (task complete) are suppressed if any app in `terminal_apps` is the frontmost application. This prevents notifications from appearing when you're already looking at Claude Code.

Notification hook events (Claude needs attention) are always shown regardless of this setting.

---

## quiet_hours

Do Not Disturb / Quiet Hours. When active, sound and overlay notifications are suppressed entirely. The status line continues to function normally and shows a `DND` indicator.

### quiet_hours.enabled

| Type | Default |
|------|---------|
| boolean | `false` |

Set to `true` to enable scheduled quiet hours. When the current time falls within the `start`-`end` range, notifications are silenced.

### quiet_hours.start

| Type | Default |
|------|---------|
| string (HH:MM) | `"22:00"` |

Start time for quiet hours in 24-hour format. Midnight-crossing ranges are supported (e.g., `"22:00"` to `"07:00"` means quiet from 10 PM to 7 AM).

### quiet_hours.end

| Type | Default |
|------|---------|
| string (HH:MM) | `"07:00"` |

End time for quiet hours in 24-hour format.

### Manual DND toggle

You can also enable Do Not Disturb manually at any time by creating a file:

- **macOS/Linux:** `touch ~/.config/claude-tap/dnd`
- **Windows:** Create `%LOCALAPPDATA%\claude-tap\dnd`

Remove the file to disable DND:

- **macOS/Linux:** `rm ~/.config/claude-tap/dnd`
- **Windows:** Delete `%LOCALAPPDATA%\claude-tap\dnd`

The manual DND toggle takes **absolute precedence** — if the `dnd` file exists, notifications are suppressed regardless of the `quiet_hours` schedule or whether `quiet_hours.enabled` is `true` or `false`.

### Example

```json
{
  "quiet_hours": {
    "enabled": true,
    "start": "23:00",
    "end": "08:00"
  }
}
```

---

## history

Notification history logs every notification (including those suppressed by DND/quiet hours) to a local JSON file. This provides a record of all Claude Code events.

### history.enabled

| Type | Default |
|------|---------|
| boolean | `true` |

Set to `false` to disable notification history logging.

### history.max_entries

| Type | Default |
|------|---------|
| integer | `100` |

Maximum number of entries to keep in the history file. When this limit is reached, the oldest entries are trimmed on each write. This prevents unbounded disk usage.

### history.clear_after_days

| Type | Default |
|------|---------|
| integer | `30` |

Automatically delete history entries older than this many days. Set to `0` to disable time-based pruning (entries will only be limited by `max_entries`). Both limits are applied on every write — whichever is more restrictive wins.

### History file location

- **macOS/Linux:** `~/.config/claude-tap/history.json`
- **Windows:** `%LOCALAPPDATA%\claude-tap\history.json`

The file is created automatically on the first notification. It is stored with user-only permissions (`0600` on macOS/Linux) since it may contain snippets of Claude's responses.

### Viewing history

Use the included viewer script:

```bash
# Show last 20 entries (default)
./scripts/history.sh

# Show last 50 entries
./scripts/history.sh --last 50
```

### Entry format

Each entry contains:

```json
{
  "timestamp": "2026-03-29T14:30:00",
  "title": "Task Complete",
  "message": "Full untruncated message text...",
  "urgency": "normal",
  "hook_type": "stop"
}
```

| Field | Description |
|-------|-------------|
| `timestamp` | ISO 8601 local time |
| `title` | Notification title |
| `message` | Full, untruncated message |
| `urgency` | `"normal"`, `"warning"`, or `"critical"` |
| `hook_type` | `"stop"` (task complete) or `"notification"` (needs attention) |

---

## auto_update

Controls the automatic update checking behavior.

### auto_update.check_on_install

| Type | Default |
|------|---------|
| boolean | `true` |

When `true`, the installer checks for available updates by comparing your local `VERSION` file against the latest version on GitHub. This is a lightweight HTTPS request to fetch a single small file.

### auto_update.notify_only

| Type | Default |
|------|---------|
| boolean | `true` |

When `true`, the update check only prints a message if an update is available. When `false`, the update script will also `git pull` and re-run the installer automatically.

### Manual update commands

```bash
# macOS/Linux: check only
./scripts/update.sh --check-only

# macOS/Linux: check and update
./scripts/update.sh

# Windows: check only
powershell -ExecutionPolicy Bypass -File scripts\update.ps1 -CheckOnly

# Windows: check and update
powershell -ExecutionPolicy Bypass -File scripts\update.ps1
```
