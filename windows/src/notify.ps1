# Claude Tap - Hook script for Claude Code (Windows).
#
# This script is registered as both a Notification hook and a Stop hook.
# It reads JSON from stdin, extracts the relevant fields, and:
#   1. Optionally skips if the terminal is already focused
#   2. Plays a configurable sound
#   3. Shows a notification overlay
#
# All behavior is controlled by %LOCALAPPDATA%\claude-tap\config.json.
# See docs/CONFIGURATION.md for the full reference.
#
# NOTE: Windows support is not currently tested. Please report issues.

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigDir = Join-Path $env:LOCALAPPDATA "claude-tap"
$ConfigFile = Join-Path $ConfigDir "config.json"

# ──────────────────────────────────────────────────────────────
# Read configuration
# ──────────────────────────────────────────────────────────────

$config = @{
    notification_enabled = $true
    show_on_waiting = $false
    sound_enabled = $true
    sound_file = (Join-Path $ConfigDir "default.wav")
    sound_volume = 0.15
    skip_if_focused = $true
    max_length = 300
    terminal_apps = @(
        "WindowsTerminal", "powershell", "pwsh", "cmd",
        "mintty", "git-bash", "alacritty", "ghostty",
        "Hyper", "Warp", "Code", "Code - Insiders", "Cursor"
    )
    warning_threshold = 80
    critical_threshold = 90
    icon_path = ""
    sound_file_stop = ""
    sound_file_notif = ""
    quiet_enabled = $false
    quiet_start = "22:00"
    quiet_end = "07:00"
    history_enabled = $true
    history_max = 100
    history_days = 30
}

if (Test-Path $ConfigFile) {
    try {
        $json = Get-Content $ConfigFile -Raw | ConvertFrom-Json

        if ($null -ne $json.notification.enabled) { $config.notification_enabled = $json.notification.enabled }
        if ($null -ne $json.notification.show_on_waiting) { $config.show_on_waiting = $json.notification.show_on_waiting }
        if ($null -ne $json.sound.enabled) { $config.sound_enabled = $json.sound.enabled }
        if ($json.sound.file) {
            $sf = $json.sound.file -replace '^~', $env:LOCALAPPDATA
            $config.sound_file = $sf
        }
        if ($null -ne $json.sound.volume) { $config.sound_volume = [double]$json.sound.volume }
        if ($null -ne $json.skip_if_focused) { $config.skip_if_focused = $json.skip_if_focused }
        if ($null -ne $json.message.max_length) { $config.max_length = [int]$json.message.max_length }
        if ($json.terminal_apps) { $config.terminal_apps = @($json.terminal_apps) }
        if ($null -ne $json.rate_limits.warning_threshold) { $config.warning_threshold = [int]$json.rate_limits.warning_threshold }
        if ($null -ne $json.rate_limits.critical_threshold) { $config.critical_threshold = [int]$json.rate_limits.critical_threshold }
        if ($json.notification.icon) { $config.icon_path = $json.notification.icon -replace '^~', $env:LOCALAPPDATA }
        if ($json.sound.files.stop) { $config.sound_file_stop = $json.sound.files.stop -replace '^~', $env:LOCALAPPDATA }
        if ($json.sound.files.notification) { $config.sound_file_notif = $json.sound.files.notification -replace '^~', $env:LOCALAPPDATA }
        if ($null -ne $json.quiet_hours.enabled) { $config.quiet_enabled = $json.quiet_hours.enabled }
        if ($json.quiet_hours.start) { $config.quiet_start = $json.quiet_hours.start }
        if ($json.quiet_hours.end) { $config.quiet_end = $json.quiet_hours.end }
        if ($null -ne $json.history.enabled) { $config.history_enabled = $json.history.enabled }
        if ($null -ne $json.history.max_entries) { $config.history_max = [int]$json.history.max_entries }
        if ($null -ne $json.history.clear_after_days) { $config.history_days = [int]$json.history.clear_after_days }
    } catch {
        # Config parse failed - use defaults
    }
}

# ──────────────────────────────────────────────────────────────
# Read hook event from stdin
# ──────────────────────────────────────────────────────────────

$inputJson = $null
try {
    $inputText = [Console]::In.ReadToEnd()
    $inputJson = $inputText | ConvertFrom-Json
} catch {
    $inputJson = $null
}

if ($inputJson -and $null -ne $inputJson.last_assistant_message) {
    # Stop hook: Claude finished responding
    $HookType = "stop"
    $NotifTitle = "Task Complete"
    $msg = if ($inputJson.last_assistant_message) { $inputJson.last_assistant_message } else { "" }

    # Collapse lines, truncate
    $collapsed = ($msg -split "`n" | Where-Object { $_.Trim() } | ForEach-Object { $_.Trim() }) -join " "
    $FullMessage = $collapsed  # untruncated for history
    if ($collapsed.Length -gt $config.max_length) {
        $NotifMessage = $collapsed.Substring(0, $config.max_length) + "..."
    } elseif ($collapsed) {
        $NotifMessage = $collapsed
    } else {
        $NotifMessage = "Claude has finished."
    }
} else {
    # Notification hook
    $HookType = "notification"
    $NotifTitle = if ($inputJson -and $inputJson.title) { $inputJson.title } else { "Claude Code" }
    $NotifMessage = if ($inputJson -and $inputJson.message) { $inputJson.message } else { "Claude needs your attention" }
    $FullMessage = $NotifMessage
}

# Suppress Notification-hook events (idle "waiting for input", permission prompts)
# entirely when show_on_waiting is off — no sound, no overlay, no history entry.
if ($HookType -eq "notification" -and -not $config.show_on_waiting) {
    exit 0
}

# ──────────────────────────────────────────────────────────────
# Skip if terminal is focused (Stop events only)
# ──────────────────────────────────────────────────────────────

if ($config.skip_if_focused -and $NotifTitle -eq "Task Complete") {
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32FG {
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
}
"@ -ErrorAction SilentlyContinue

    try {
        $hwnd = [Win32FG]::GetForegroundWindow()
        $fgPid = [uint32]0
        [Win32FG]::GetWindowThreadProcessId($hwnd, [ref]$fgPid) | Out-Null
        $fgProcess = Get-Process -Id $fgPid -ErrorAction SilentlyContinue

        if ($fgProcess) {
            foreach ($app in $config.terminal_apps) {
                if ($fgProcess.ProcessName -eq $app) {
                    exit 0
                }
            }
        }
    } catch {
        # Can't determine foreground window - continue with notification
    }
}

# ──────────────────────────────────────────────────────────────
# Log to notification history (before DND gate so all events are recorded)
# ──────────────────────────────────────────────────────────────

if ($config.history_enabled) {
    try {
        $historyPath = Join-Path $ConfigDir "history.json"
        $entry = @{
            timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss")
            title = $NotifTitle
            message = $FullMessage
            urgency = "normal"
            hook_type = $HookType
        }

        # File locking via exclusive FileStream
        $lockStream = $null
        try {
            $lockStream = [System.IO.File]::Open($historyPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
            $reader = [System.IO.StreamReader]::new($lockStream)
            $content = $reader.ReadToEnd()
            $reader.Dispose()

            $history = @()
            if ($content.Trim()) {
                try { $history = @($content | ConvertFrom-Json) } catch { $history = @() }
            }
            $history += $entry
            # Prune entries older than clear_after_days
            if ($config.history_days -gt 0) {
                $cutoff = (Get-Date).AddDays(-$config.history_days).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss")
                $history = @($history | Where-Object { $_.timestamp -ge $cutoff })
            }
            # Enforce max_entries limit
            if ($history.Count -gt $config.history_max) {
                $history = $history[($history.Count - $config.history_max)..($history.Count - 1)]
            }
            $lockStream.SetLength(0)
            $lockStream.Position = 0
            $writer = [System.IO.StreamWriter]::new($lockStream)
            $writer.Write(($history | ConvertTo-Json -Depth 3))
            $writer.Flush()
            $writer.Dispose()
        } finally {
            if ($lockStream) { $lockStream.Dispose() }
        }
    } catch {
        # History logging failed silently
    }
}

# ──────────────────────────────────────────────────────────────
# Do Not Disturb / Quiet Hours gate
# ──────────────────────────────────────────────────────────────

$DndActive = $false

# Manual DND toggle: create %LOCALAPPDATA%\claude-tap\dnd to enable
if (Test-Path (Join-Path $ConfigDir "dnd")) {
    $DndActive = $true
}

# Quiet hours check (handles midnight-crossing ranges)
if ($config.quiet_enabled -and -not $DndActive) {
    $now = [DateTime]::Now.ToString("HH:mm")
    if ($config.quiet_start -gt $config.quiet_end) {
        # Overnight range (e.g., 22:00 to 07:00)
        if ($now -ge $config.quiet_start -or $now -lt $config.quiet_end) {
            $DndActive = $true
        }
    } else {
        # Same-day range (e.g., 09:00 to 17:00)
        if ($now -ge $config.quiet_start -and $now -lt $config.quiet_end) {
            $DndActive = $true
        }
    }
}

if ($DndActive) {
    exit 0
}

# ──────────────────────────────────────────────────────────────
# Determine urgency from cached rate limit
# ──────────────────────────────────────────────────────────────

$Urgency = "normal"
$rateLimitFile = Join-Path $env:TEMP "claude-rate-limit"
if (Test-Path $rateLimitFile) {
    try {
        $ratePct = [int](Get-Content $rateLimitFile -Raw).Trim()
        if ($ratePct -ge $config.critical_threshold) {
            $Urgency = "critical"
        } elseif ($ratePct -ge $config.warning_threshold) {
            $Urgency = "warning"
        }
    } catch {
        # Can't read rate limit - use normal
    }
}

# ──────────────────────────────────────────────────────────────
# Play sound
# ──────────────────────────────────────────────────────────────

# Note: SoundPlayer does not support volume control. Sound plays at system volume.
# The sound.volume config setting is a placeholder for future implementations.
if ($config.sound_enabled) {
    # Resolve per-event sound with fallback to default
    $playSound = $config.sound_file
    if ($HookType -eq "stop" -and $config.sound_file_stop -and (Test-Path $config.sound_file_stop)) {
        $playSound = $config.sound_file_stop
    } elseif ($HookType -eq "notification" -and $config.sound_file_notif -and (Test-Path $config.sound_file_notif)) {
        $playSound = $config.sound_file_notif
    }
    if (Test-Path $playSound) {
        Start-Job -ScriptBlock {
            param($file)
            Add-Type -AssemblyName System.Media
            $player = [System.Media.SoundPlayer]::new($file)
            $player.PlaySync()
        } -ArgumentList $playSound | Out-Null
    }
}

# ──────────────────────────────────────────────────────────────
# Show notification overlay
# ──────────────────────────────────────────────────────────────

if ($config.notification_enabled) {
    $notifScript = Join-Path $ScriptDir "NotchNotification.ps1"
    # Use custom icon from config, fall back to default
    $iconPath = Join-Path $ConfigDir "claude-icon.png"
    if ($config.icon_path -and (Test-Path $config.icon_path)) {
        $iconPath = $config.icon_path
    }

    # Encode title and message as Base64 to avoid argument injection issues
    $encodedTitle = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($NotifTitle))
    $encodedMsg = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($NotifMessage))
    $cmd = @"
`$t = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$encodedTitle'))
`$m = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$encodedMsg'))
& '$notifScript' -Title `$t -Message `$m -IconPath '$iconPath' -Urgency '$Urgency'
"@
    Start-Process -NoNewWindow -FilePath "powershell.exe" -ArgumentList @(
        "-STA", "-ExecutionPolicy", "Bypass", "-Command", $cmd
    )
}
