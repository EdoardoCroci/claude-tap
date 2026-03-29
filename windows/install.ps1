# Claude Tap - Installer (Windows)
#
# This script:
#   1. Checks prerequisites (Windows, PowerShell 5.1+)
#   2. Asks you to configure notifications, status line, and colors
#   3. Copies assets (icon, sound) to %LOCALAPPDATA%\claude-tap\
#   4. Generates config.json from your choices
#   5. Registers Claude Code hooks and status line in ~/.claude/settings.json
#
# Safe to run multiple times. Pass -Reconfigure to re-run the interactive setup
# even if a config already exists.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File install.ps1 [-Reconfigure]
#
# NOTE: Windows support is not currently tested. Please report issues.

param(
    [switch]$Reconfigure
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoDir = Split-Path -Parent $ScriptDir
$ConfigDir = Join-Path $env:LOCALAPPDATA "claude-tap"
$ClaudeDir = Join-Path $env:USERPROFILE ".claude"
$SettingsFile = Join-Path $ClaudeDir "settings.json"

# ──────────────────────────────────────────────────────────────
# Output helpers
# ──────────────────────────────────────────────────────────────

function Write-Info($msg)    { Write-Host "  [info]  $msg" -ForegroundColor Cyan }
function Write-Ok($msg)      { Write-Host "  [ok]    $msg" -ForegroundColor Green }
function Write-Warn($msg)    { Write-Host "  [warn]  $msg" -ForegroundColor Yellow }
function Write-Fail($msg)    { Write-Host "  [error] $msg" -ForegroundColor Red; exit 1 }

function Ask($prompt, $default) {
    $reply = Read-Host "  $prompt [$default]"
    if ([string]::IsNullOrWhiteSpace($reply)) { return $default }
    return $reply
}

function Ask-YN($prompt, $default) {
    $hint = if ($default -eq "Y") { "Y/n" } else { "y/N" }
    $reply = Read-Host "  $prompt [$hint]"
    if ([string]::IsNullOrWhiteSpace($reply)) { $reply = $default }
    return ($reply -match '^[Yy]')
}

function Ask-RGBA($label, $default) {
    $reply = Read-Host "    $label [$default]"
    if ([string]::IsNullOrWhiteSpace($reply)) { $reply = $default }
    $parts = $reply -split '\s+'
    return "[$($parts[0]), $($parts[1]), $($parts[2]), $($parts[3])]"
}

Write-Host ""
Write-Host "  Claude Tap - Installer (Windows)" -ForegroundColor White
Write-Host ""

# ──────────────────────────────────────────────────────────────
# 1. Preflight checks
# ──────────────────────────────────────────────────────────────

Write-Info "Checking prerequisites..."

if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Fail "PowerShell 5.1+ required. You have $($PSVersionTable.PSVersion)."
}
Write-Ok "PowerShell $($PSVersionTable.PSVersion)"

if (-not ([Environment]::OSVersion.Platform -eq 'Win32NT')) {
    Write-Fail "This installer is for Windows only. Use macos/install.sh on macOS."
}
Write-Ok "Windows $([Environment]::OSVersion.Version.Major)"

Write-Host ""

# ──────────────────────────────────────────────────────────────
# 1b. Check for updates (if existing config has auto_update.check_on_install)
# ──────────────────────────────────────────────────────────────

$existingConfigCheck = Join-Path $ConfigDir "config.json"
if (Test-Path $existingConfigCheck) {
    try {
        $ecCheck = Get-Content $existingConfigCheck -Raw | ConvertFrom-Json
        if ($ecCheck.auto_update.check_on_install -ne $false) {
            $updateScript = Join-Path $RepoDir "scripts\update.ps1"
            if (Test-Path $updateScript) {
                & powershell -ExecutionPolicy Bypass -File $updateScript -CheckOnly 2>$null
            }
        }
    } catch {}
}

# ──────────────────────────────────────────────────────────────
# 2. Interactive configuration
# ──────────────────────────────────────────────────────────────

$ShouldConfigure = $true
if ((Test-Path (Join-Path $ConfigDir "config.json")) -and -not $Reconfigure) {
    Write-Host "  Existing config found. Your customizations will be preserved." -ForegroundColor Cyan
    Write-Host "  Run: install.ps1 -Reconfigure to change settings." -ForegroundColor Cyan
    Write-Host ""
    $ShouldConfigure = $false
}

if ($ShouldConfigure) {

    # -- Load existing config values as defaults --
    $D = @{
        pos="1"; duration="5.5"; max_lines="3"; width="380"; corner="16"; icon=""
        sound_enabled="Y"; sound_volume="0.15"; sound_file="default.wav"
        sl_enabled="Y"; show_ctx="Y"; show_5h="Y"; show_7d="Y"; show_lines="Y"
        warn="80"; crit="90"; skip="Y"
        quiet_enabled="N"; quiet_start="22:00"; quiet_end="07:00"
        history_enabled="Y"; history_max="100"; history_days="30"
        update_check="Y"; update_notify_only="Y"
    }
    $existingConfig = Join-Path $ConfigDir "config.json"
    if (Test-Path $existingConfig) {
        try {
            Write-Info "Loading current config as defaults (press Enter to keep, type to change)"
            $ec = Get-Content $existingConfig -Raw | ConvertFrom-Json
            $posMap = @{ "top-center"="1"; "top-left"="2"; "top-right"="3"; "bottom-center"="4"; "bottom-left"="5"; "bottom-right"="6" }
            if ($ec.notification.position -and $posMap[$ec.notification.position]) { $D.pos = $posMap[$ec.notification.position] }
            if ($null -ne $ec.notification.duration_seconds) { $D.duration = "$($ec.notification.duration_seconds)" }
            if ($null -ne $ec.notification.max_lines) { $D.max_lines = "$($ec.notification.max_lines)" }
            if ($null -ne $ec.notification.width) { $D.width = "$($ec.notification.width)" }
            if ($null -ne $ec.notification.corner_radius) { $D.corner = "$($ec.notification.corner_radius)" }
            if ($ec.notification.icon) { $D.icon = $ec.notification.icon }
            if ($null -ne $ec.sound.enabled) { $D.sound_enabled = if ($ec.sound.enabled) { "Y" } else { "N" } }
            if ($null -ne $ec.sound.volume) { $D.sound_volume = "$($ec.sound.volume)" }
            if ($ec.sound.file) { $D.sound_file = $ec.sound.file }
            if ($null -ne $ec.status_line.enabled) { $D.sl_enabled = if ($ec.status_line.enabled) { "Y" } else { "N" } }
            if ($null -ne $ec.status_line.show_context_bar) { $D.show_ctx = if ($ec.status_line.show_context_bar) { "Y" } else { "N" } }
            if ($null -ne $ec.status_line.show_rate_5h) { $D.show_5h = if ($ec.status_line.show_rate_5h) { "Y" } else { "N" } }
            if ($null -ne $ec.status_line.show_rate_7d) { $D.show_7d = if ($ec.status_line.show_rate_7d) { "Y" } else { "N" } }
            if ($null -ne $ec.status_line.show_lines_changed) { $D.show_lines = if ($ec.status_line.show_lines_changed) { "Y" } else { "N" } }
            if ($null -ne $ec.rate_limits.warning_threshold) { $D.warn = "$($ec.rate_limits.warning_threshold)" }
            if ($null -ne $ec.rate_limits.critical_threshold) { $D.crit = "$($ec.rate_limits.critical_threshold)" }
            if ($null -ne $ec.skip_if_focused) { $D.skip = if ($ec.skip_if_focused) { "Y" } else { "N" } }
            if ($null -ne $ec.quiet_hours.enabled) { $D.quiet_enabled = if ($ec.quiet_hours.enabled) { "Y" } else { "N" } }
            if ($ec.quiet_hours.start) { $D.quiet_start = $ec.quiet_hours.start }
            if ($ec.quiet_hours.end) { $D.quiet_end = $ec.quiet_hours.end }
            if ($null -ne $ec.history.enabled) { $D.history_enabled = if ($ec.history.enabled) { "Y" } else { "N" } }
            if ($null -ne $ec.history.max_entries) { $D.history_max = "$($ec.history.max_entries)" }
            if ($null -ne $ec.history.clear_after_days) { $D.history_days = "$($ec.history.clear_after_days)" }
            if ($null -ne $ec.auto_update.check_on_install) { $D.update_check = if ($ec.auto_update.check_on_install) { "Y" } else { "N" } }
            if ($null -ne $ec.auto_update.notify_only) { $D.update_notify_only = if ($ec.auto_update.notify_only) { "Y" } else { "N" } }
        } catch {}
    }

    Write-Host "  Let's configure your notifications!" -ForegroundColor White
    Write-Host "  Press Enter to keep current value, type to change." -ForegroundColor DarkGray
    Write-Host ""

    # -- Position --
    Write-Host "  Notification position:" -ForegroundColor White
    Write-Host "    1) Top center"
    Write-Host "    2) Top left"
    Write-Host "    3) Top right"
    Write-Host "    4) Bottom center"
    Write-Host "    5) Bottom left"
    Write-Host "    6) Bottom right"
    $posChoice = Ask "Choose" $D.pos
    $Position = switch ($posChoice) {
        "2" { "top-left" }
        "3" { "top-right" }
        "4" { "bottom-center" }
        "5" { "bottom-left" }
        "6" { "bottom-right" }
        default { "top-center" }
    }
    Write-Host ""

    # -- Notification settings --
    Write-Host "  Notification settings:" -ForegroundColor White
    $Duration = Ask "Duration in seconds" $D.duration
    $MaxLines = Ask "Max message lines (1-5)" $D.max_lines
    $Width = Ask "Width in points" $D.width
    $CornerRadius = Ask "Corner radius" $D.corner
    Write-Host "    Tip: use any PNG image as the notification icon" -ForegroundColor DarkGray
    $IconFile = Ask "Custom icon path (empty = default Claude icon)" $D.icon
    Write-Host ""

    # -- Sound --
    Write-Host "  Sound:" -ForegroundColor White
    $SoundEnabled = Ask-YN "Enable sound" $D.sound_enabled
    if ($SoundEnabled) {
        $SoundVolume = Ask "Volume (0.0-1.0)" $D.sound_volume
        $SoundFile = Ask "Sound file path" $D.sound_file
    } else {
        $SoundVolume = $D.sound_volume
        $SoundFile = $D.sound_file
    }
    $SoundEnabledJson = if ($SoundEnabled) { "true" } else { "false" }
    Write-Host ""

    # -- Status line --
    Write-Host "  Status line - what to show:" -ForegroundColor White
    $SlEnabled = Ask-YN "Enable status line" $D.sl_enabled
    if ($SlEnabled) {
        $ShowCtx = Ask-YN "Context window bar" $D.show_ctx
        $Show5h = Ask-YN "5-hour rate limit" $D.show_5h
        $Show7d = Ask-YN "7-day rate limit" $D.show_7d
        $ShowLines = Ask-YN "Lines changed" $D.show_lines
    } else {
        $ShowCtx = $true; $Show5h = $true; $Show7d = $true; $ShowLines = $true
    }
    $SlEnabledJson = if ($SlEnabled) { "true" } else { "false" }
    $ShowCtxJson = if ($ShowCtx) { "true" } else { "false" }
    $Show5hJson = if ($Show5h) { "true" } else { "false" }
    $Show7dJson = if ($Show7d) { "true" } else { "false" }
    $ShowLinesJson = if ($ShowLines) { "true" } else { "false" }
    Write-Host ""

    # -- Rate limits --
    Write-Host "  Rate limit warnings:" -ForegroundColor White
    $WarnThreshold = Ask "Warning threshold (%)" $D.warn
    $CritThreshold = Ask "Critical threshold (%)" $D.crit
    Write-Host ""

    # -- Other --
    $SkipFocused = Ask-YN "Skip notifications when terminal is focused" $D.skip
    $SkipFocusedJson = if ($SkipFocused) { "true" } else { "false" }
    Write-Host ""

    # -- Quiet hours --
    Write-Host "  Quiet hours (Do Not Disturb):" -ForegroundColor White
    Write-Host "    Suppress sound and overlay during specified hours." -ForegroundColor DarkGray
    Write-Host "    You can also toggle DND manually by creating: %LOCALAPPDATA%\claude-tap\dnd" -ForegroundColor DarkGray
    $QuietEnabled = Ask-YN "Enable quiet hours" $D.quiet_enabled
    if ($QuietEnabled) {
        $QuietStart = Ask "Start time (HH:MM, 24h)" $D.quiet_start
        $QuietEnd = Ask "End time (HH:MM, 24h)" $D.quiet_end
    } else {
        $QuietStart = $D.quiet_start
        $QuietEnd = $D.quiet_end
    }
    $QuietEnabledJson = if ($QuietEnabled) { "true" } else { "false" }
    Write-Host ""

    # -- History --
    Write-Host "  Notification history:" -ForegroundColor White
    Write-Host "    Log all notifications to history.json" -ForegroundColor DarkGray
    $HistoryEnabled = Ask-YN "Enable notification history" $D.history_enabled
    if ($HistoryEnabled) {
        $HistoryMax = Ask "Max entries to keep" $D.history_max
        $HistoryDays = Ask "Auto-delete entries older than N days (0 = never)" $D.history_days
    } else {
        $HistoryMax = $D.history_max
        $HistoryDays = $D.history_days
    }
    $HistoryEnabledJson = if ($HistoryEnabled) { "true" } else { "false" }
    Write-Host ""

    # -- Auto-update --
    Write-Host "  Auto-update:" -ForegroundColor White
    $UpdateCheck = Ask-YN "Check for updates when running the installer" $D.update_check
    $UpdateNotifyOnly = Ask-YN "Notify only (don't auto-pull)" $D.update_notify_only
    $UpdateCheckJson = if ($UpdateCheck) { "true" } else { "false" }
    $UpdateNotifyOnlyJson = if ($UpdateNotifyOnly) { "true" } else { "false" }
    Write-Host ""

    # -- Colors --
    Write-Host "  Colors:" -ForegroundColor White
    $CustomizeColors = Ask-YN "Customize colors" "N"

    # Defaults
    $NormalBg = "[0.05, 0.05, 0.07, 0.96]"
    $NormalBorder = "[1.0, 1.0, 1.0, 0.08]"
    $NormalTitle = "[0.85, 0.55, 0.40, 1.0]"
    $NormalText = "[0.95, 0.95, 0.95, 1.0]"
    $WarningBg = "[0.12, 0.09, 0.04, 0.96]"
    $WarningBorder = "[0.85, 0.65, 0.20, 0.25]"
    $WarningTitle = "[0.85, 0.55, 0.40, 1.0]"
    $WarningText = "[0.95, 0.95, 0.95, 1.0]"
    $CriticalBg = "[0.14, 0.04, 0.04, 0.96]"
    $CriticalBorder = "[0.90, 0.25, 0.20, 0.30]"
    $CriticalTitle = "[0.85, 0.55, 0.40, 1.0]"
    $CriticalText = "[0.95, 0.95, 0.95, 1.0]"

    if ($CustomizeColors) {
        Write-Host ""
        Write-Host "    Enter colors as: R G B A (values 0.0-1.0, space-separated)" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "    Normal state:" -ForegroundColor White
        $NormalBg = Ask-RGBA "Background" "0.05 0.05 0.07 0.96"
        $NormalBorder = Ask-RGBA "Border" "1.0 1.0 1.0 0.08"
        $NormalTitle = Ask-RGBA "Title text" "0.85 0.55 0.40 1.0"
        $NormalText = Ask-RGBA "Message text" "0.95 0.95 0.95 1.0"
        Write-Host ""
        Write-Host "    Warning state (rate limit > ${WarnThreshold}%):" -ForegroundColor White
        $WarningBg = Ask-RGBA "Background" "0.12 0.09 0.04 0.96"
        $WarningBorder = Ask-RGBA "Border" "0.85 0.65 0.20 0.25"
        $WarningTitle = Ask-RGBA "Title text" "0.85 0.55 0.40 1.0"
        $WarningText = Ask-RGBA "Message text" "0.95 0.95 0.95 1.0"
        Write-Host ""
        Write-Host "    Critical state (rate limit > ${CritThreshold}%):" -ForegroundColor White
        $CriticalBg = Ask-RGBA "Background" "0.14 0.04 0.04 0.96"
        $CriticalBorder = Ask-RGBA "Border" "0.90 0.25 0.20 0.30"
        $CriticalTitle = Ask-RGBA "Title text" "0.85 0.55 0.40 1.0"
        $CriticalText = Ask-RGBA "Message text" "0.95 0.95 0.95 1.0"
    }
    Write-Host ""
}

# ──────────────────────────────────────────────────────────────
# 3. Create config directory and copy assets
# ──────────────────────────────────────────────────────────────

Write-Info "Setting up $ConfigDir..."
New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null
Copy-Item (Join-Path $RepoDir "assets\claude-icon.png") (Join-Path $ConfigDir "claude-icon.png") -Force
Copy-Item (Join-Path $RepoDir "assets\sounds\default.wav") (Join-Path $ConfigDir "default.wav") -Force
Write-Ok "Assets copied (icon + sound)"

# ──────────────────────────────────────────────────────────────
# 4. Write config file
# ──────────────────────────────────────────────────────────────

$configPath = Join-Path $ConfigDir "config.json"

if ($ShouldConfigure) {
    $configJson = @"
{
  "notification": {
    "enabled": true,
    "position": "$Position",
    "width": $Width,
    "max_lines": $MaxLines,
    "corner_radius": $CornerRadius,
    "duration_seconds": $Duration,
    "icon": "$IconFile",

    "colors": {
      "normal": {
        "background": $NormalBg,
        "border": $NormalBorder,
        "title": $NormalTitle,
        "text": $NormalText
      },
      "warning": {
        "background": $WarningBg,
        "border": $WarningBorder,
        "title": $WarningTitle,
        "text": $WarningText
      },
      "critical": {
        "background": $CriticalBg,
        "border": $CriticalBorder,
        "title": $CriticalTitle,
        "text": $CriticalText
      }
    }
  },

  "sound": {
    "enabled": $SoundEnabledJson,
    "file": "$SoundFile",
    "volume": $SoundVolume
  },

  "terminal_apps": [
    "WindowsTerminal",
    "powershell",
    "pwsh",
    "cmd",
    "mintty",
    "git-bash",
    "alacritty",
    "ghostty",
    "Hyper",
    "Warp"
  ],

  "rate_limits": {
    "warning_threshold": $WarnThreshold,
    "critical_threshold": $CritThreshold
  },

  "status_line": {
    "enabled": $SlEnabledJson,
    "show_context_bar": $ShowCtxJson,
    "show_rate_5h": $Show5hJson,
    "show_rate_7d": $Show7dJson,
    "show_lines_changed": $ShowLinesJson
  },

  "message": {
    "max_length": 300
  },

  "skip_if_focused": $SkipFocusedJson,

  "quiet_hours": {
    "enabled": $QuietEnabledJson,
    "start": "$QuietStart",
    "end": "$QuietEnd"
  },

  "history": {
    "enabled": $HistoryEnabledJson,
    "max_entries": $HistoryMax,
    "clear_after_days": $HistoryDays
  },

  "auto_update": {
    "check_on_install": $UpdateCheckJson,
    "notify_only": $UpdateNotifyOnlyJson
  }
}
"@
    Set-Content -Path $configPath -Value $configJson -Encoding UTF8
    Write-Ok "Config written: $configPath"
} else {
    Write-Ok "Config file preserved"
}

# ──────────────────────────────────────────────────────────────
# 5. Register Claude Code hooks
# ──────────────────────────────────────────────────────────────

Write-Info "Registering Claude Code hooks..."

New-Item -ItemType Directory -Force -Path $ClaudeDir | Out-Null

$notifyCmd = "powershell -ExecutionPolicy Bypass -File `"$(Join-Path $ScriptDir 'src\notify.ps1')`""
$statuslineCmd = "powershell -ExecutionPolicy Bypass -File `"$(Join-Path $ScriptDir 'src\statusline.ps1')`""

# Load existing settings (PS 5.1 compatible - no -AsHashtable)
# We use python3 or a manual JSON approach to avoid PSCustomObject limitations
$settingsJson = "{}"
if (Test-Path $SettingsFile) {
    try {
        $backup = "${SettingsFile}.backup.$(Get-Date -Format 'yyyyMMddHHmmss')"
        Copy-Item $SettingsFile $backup
        Write-Info "Backed up existing settings"
        $settingsJson = Get-Content $SettingsFile -Raw
    } catch {
        $settingsJson = "{}"
    }
}

# Use Python to safely merge hooks into settings (pipe JSON via stdin to avoid injection)
$mergeScript = @'
import json, sys

# Read existing settings from stdin line 1, notify_cmd from line 2, statusline_cmd from line 3
lines = sys.stdin.read().split('\n')
try:
    settings = json.loads(lines[0]) if lines[0].strip() else {}
except:
    settings = {}
notify_cmd = lines[1].strip() if len(lines) > 1 else ''
statusline_cmd = lines[2].strip() if len(lines) > 2 else ''

if 'hooks' not in settings:
    settings['hooks'] = {}

hook_entry = {'matcher': '', 'hooks': [{'type': 'command', 'command': notify_cmd}]}

def has_cmd(entry, cmd):
    if cmd in entry.get('command', ''):
        return True
    for h in entry.get('hooks', []):
        if cmd in h.get('command', ''):
            return True
    return False

existing_notif = [h for h in settings['hooks'].get('Notification', []) if not has_cmd(h, 'claude-tap')]
existing_notif.append(hook_entry)
settings['hooks']['Notification'] = existing_notif

existing_stop = [h for h in settings['hooks'].get('Stop', []) if not has_cmd(h, 'claude-tap')]
existing_stop.append(hook_entry)
settings['hooks']['Stop'] = existing_stop

settings['statusLine'] = {'type': 'command', 'command': statusline_cmd, 'padding': 2}

print(json.dumps(settings, indent=2))
'@

# Try python3 first (most reliable for JSON), fall back to python
$pythonCmd = if (Get-Command python3 -ErrorAction SilentlyContinue) { "python3" }
             elseif (Get-Command python -ErrorAction SilentlyContinue) { "python" }
             else { $null }

if ($pythonCmd) {
    # Pipe settings JSON + commands via stdin (avoids string injection)
    $stdinData = "$settingsJson`n$notifyCmd`n$statuslineCmd"
    $newSettings = ($stdinData | & $pythonCmd -c $mergeScript) 2>&1
    Set-Content $SettingsFile -Value $newSettings -Encoding UTF8
} else {
    # Fallback: write a minimal settings file if no python available
    $escapedNotify = $notifyCmd -replace '\\', '\\\\' -replace '"', '\"'
    $escapedStatus = $statuslineCmd -replace '\\', '\\\\' -replace '"', '\"'
    $minimalSettings = @"
{
  "hooks": {
    "Notification": [{"matcher": "", "hooks": [{"type": "command", "command": "$escapedNotify"}]}],
    "Stop": [{"matcher": "", "hooks": [{"type": "command", "command": "$escapedNotify"}]}]
  },
  "statusLine": {
    "type": "command",
    "command": "$escapedStatus",
    "padding": 2
  }
}
"@
    Set-Content $SettingsFile -Value $minimalSettings -Encoding UTF8
    Write-Warn "Python not found - wrote minimal settings (existing hooks may have been overwritten)"
}
Write-Ok "Hooks registered in $SettingsFile"

Write-Host ""

# ──────────────────────────────────────────────────────────────
# Done!
# ──────────────────────────────────────────────────────────────

Write-Host "  Installation complete!" -ForegroundColor Green
Write-Host ""
Write-Host "  Config:  $configPath" -ForegroundColor Cyan
Write-Host "  Hooks:   $SettingsFile" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Next steps:" -ForegroundColor White
Write-Host "  1. Restart Claude Code (or start a new session)"
Write-Host "  2. Run /hooks inside Claude Code to verify"
Write-Host "  3. Edit $configPath anytime to tweak settings"
Write-Host "     Changes take effect immediately."
Write-Host "  4. Run install.ps1 -Reconfigure to re-run this setup wizard"
Write-Host ""
# Show a test notification to confirm it works
$notifPs1 = Join-Path $ScriptDir "src\NotchNotification.ps1"
$testIcon = Join-Path $ConfigDir "claude-icon.png"
Start-Process -NoNewWindow -FilePath "powershell.exe" -ArgumentList @(
    "-STA", "-ExecutionPolicy", "Bypass", "-File", $notifPs1,
    "-Title", "Claude Tap",
    "-Message", "Installation successful! Click to focus terminal.",
    "-IconPath", $testIcon
)
Write-Host ""
