# Troubleshooting

> **Note:** macOS is the primary tested platform. Linux and Windows support is included but not currently tested. If you encounter issues, please [report them](https://github.com/EdoardoCroci/claude-tap/issues).

## Installation issues (macOS)

### "swiftc not found"

The Swift compiler is part of Xcode Command Line Tools. Install them:

```bash
xcode-select --install
```

Then run `./install.sh` again.

### "jq not found"

`jq` is needed for the status line (not for notifications). Install via Homebrew:

```bash
brew install jq
```

### Compilation fails with architecture errors

If you see errors about unsupported architectures, ensure you're running the install on the same machine where you'll use the tool. The binary is compiled for your current architecture (arm64 on Apple Silicon, x86_64 on Intel).

## Installation issues (Windows - not tested)

### "Execution policy" error

PowerShell may block script execution by default. Run the installer with:

```powershell
powershell -ExecutionPolicy Bypass -File install.ps1
```

Or set your execution policy:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Notification window doesn't appear

The Windows notification uses WPF, which requires .NET Framework (ships with Windows 10+). If you're on an older system or a stripped-down Windows installation, WPF may not be available.

### Terminal focus detection doesn't work

The `terminal_apps` config on Windows uses process names (as shown in Task Manager), not bundle IDs. Make sure the process name matches exactly. Common names:

| Terminal | Process name |
|----------|-------------|
| Windows Terminal | `WindowsTerminal` |
| PowerShell 7 | `pwsh` |
| PowerShell 5 | `powershell` |
| CMD | `cmd` |
| Git Bash | `mintty` |
| Alacritty | `alacritty` |
| Ghostty | `ghostty` |
| VS Code | `Code` |
| VS Code Insiders | `Code - Insiders` |
| Cursor | `Cursor` |

## Installation issues (Linux)

### "GTK3 (PyGObject) not found"

The custom overlay requires PyGObject and GTK3. Install for your distribution:

```bash
# Debian/Ubuntu
sudo apt install python3-gi gir1.2-gtk-3.0

# Fedora
sudo dnf install python3-gobject gtk3

# Arch
sudo pacman -S python-gobject gtk3
```

Without GTK3, the installer will use `notify-send` as a fallback — standard desktop notifications instead of the custom overlay.

### No sound on Linux

The notify script tries `paplay` (PulseAudio), `pw-play` (PipeWire), and `aplay` (ALSA) in that order. Install at least one:

```bash
# PulseAudio (most common)
sudo apt install pulseaudio-utils

# PipeWire
sudo apt install pipewire

# ALSA
sudo apt install alsa-utils
```

### Terminal focus detection doesn't work on Wayland

`xdotool` only works on X11. On Wayland compositors (GNOME 40+, Sway, Hyprland), focus detection is not yet supported. Notifications will always be shown. This is a known limitation.

For Sway users, `swaymsg` support may be added in a future release.

---

## VS Code / Cursor integrated terminal

VS Code, VS Code Insiders, and Cursor are included in the default `terminal_apps` list starting from v1.3.0. If you installed an earlier version, add the appropriate identifier to your config:

| Editor | macOS bundle ID | Linux/Windows process |
|--------|----------------|----------------------|
| VS Code | `com.microsoft.VSCode` | `code` / `Code` |
| VS Code Insiders | `com.microsoft.VSCodeInsiders` | `code-insiders` / `Code - Insiders` |
| Cursor | `com.todesktop.230313mzl4w4u92` | `cursor` / `Cursor` |

If you upgraded from an older version, your existing `config.json` still has the old defaults. Either add the entries manually or delete your config and re-run the installer to regenerate it.

---

## Notification issues

### Notification doesn't appear

1. **Check if notifications are enabled:**
   ```bash
   cat ~/.config/claude-tap/config.json | python3 -c "import json,sys; print(json.load(sys.stdin)['notification']['enabled'])"
   ```

2. **Test the binary directly:**
   ```bash
   ~/.config/claude-tap/notch-notify "Test" "Hello" ~/.config/claude-tap/claude-icon.png
   ```

3. **Check if hooks are registered** - run `/hooks` inside Claude Code.

4. **Check if your terminal is being detected as focused** - if `skip_if_focused` is `true` and you're looking at your terminal, Stop hook notifications are intentionally suppressed. Test by switching to a different app first.

### Notification appears but I'm at my terminal

Your terminal's bundle ID might not be in the `terminal_apps` list. Find it:

```bash
osascript -e 'id of app "YourTerminalName"'
```

Add the result to the `terminal_apps` array in your config.

### Notification appears in the wrong position

Check the `notification.position` setting. Valid values are `"top-center"`, `"top-left"`, `"top-right"`, `"bottom-center"`, `"bottom-left"`, `"bottom-right"`.

### Notification is too small / too large

Adjust `notification.width` (default: `380`) and `notification.max_lines` (default: `3`) in your config.

---

## Sound issues

### No sound plays

1. **Check if sound is enabled:**
   ```bash
   cat ~/.config/claude-tap/config.json | python3 -c "import json,sys; print(json.load(sys.stdin)['sound']['enabled'])"
   ```

2. **Check if the sound file exists:**
   ```bash
   ls -la "$(python3 -c "import os; print(os.path.expanduser('$(cat ~/.config/claude-tap/config.json | python3 -c "import json,sys; print(json.load(sys.stdin)['sound']['file'])")'))")"
   ```

3. **Test the sound directly:**
   ```bash
   afplay -v 0.5 ~/.config/claude-tap/default.wav
   ```

4. **Check macOS volume** - `afplay` respects the system volume. Make sure your Mac isn't muted.

### Sound is too loud / too quiet

Adjust `sound.volume` in your config. Range is `0.0` (silent) to `1.0` (full). Default is `0.15`.

---

## Status line issues

### Status line doesn't appear

1. **Check if it's enabled** in your config under `status_line.enabled`.
2. **Verify jq is installed:** `which jq`
3. **Check settings.json** has a `statusLine` entry - run `/hooks` in Claude Code.
4. The status line only appears after the first assistant message in a session.

### Status line shows "ctx: n/a"

This is normal before the first API response. The context window data isn't available until Claude responds at least once.

### Rate limit fields are empty

Rate limit data (`5h`, `7d`) is only available for Pro and Max subscribers. API key users won't see this data.

---

## Config issues

### Changes to config aren't taking effect

1. **Validate your JSON:**
   ```bash
   python3 -m json.tool ~/.config/claude-tap/config.json
   ```
   If this prints an error, your JSON is malformed. Common issues: trailing commas, missing quotes, mismatched brackets.

2. **Check file location** - the config must be at exactly `~/.config/claude-tap/config.json`.

3. **Note:** Most changes take effect on the next notification/status line update. You don't need to restart Claude Code.

### I broke my config and want to start fresh

```bash
cp /path/to/claude-tap/config.example.json ~/.config/claude-tap/config.json
```

Or delete it and re-run the installer:

```bash
rm ~/.config/claude-tap/config.json
./install.sh
```

---

## Rate limit warnings

### I keep getting rate limit warnings

Adjust the thresholds in your config:

```json
{
  "rate_limits": {
    "warning_threshold": 90,
    "critical_threshold": 95
  }
}
```

Or set them both to `100` to effectively disable warnings.

### Warning triggered again after it already fired

Warnings reset when your usage drops below the threshold. If your usage fluctuates around the boundary, you may see repeated warnings. Consider raising the threshold slightly above the fluctuation range.

---

## Multiple sessions / terminals

### Status line shows different data in different terminals

This is expected. Each Claude Code session has its own context window, cost, and lines changed - these are per-session metrics. The status line updates when you interact with that session (send a message, change permission mode, etc.).

Rate limits (5h and 7d) are account-wide and should be similar across sessions, but they only refresh when a session communicates with the API. An idle session will show the rate limit from its last update.

There is no auto-refresh mechanism - the status line runs on events, not on a timer. If you want fresh data in an idle session, send any message to trigger an update.

---

## Getting help

If your issue isn't covered here, please [open an issue](https://github.com/EdoardoCroci/claude-tap/issues) with:

1. Your OS version (`sw_vers` on macOS, `lsb_release -a` on Linux)
2. Your Swift version on macOS (`swiftc --version`) or Python version on Linux (`python3 --version`)
3. The output of `./install.sh`
4. The contents of `~/.config/claude-tap/config.json`
5. Any error messages you're seeing
