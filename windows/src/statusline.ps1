# Claude Tap - Status line script for Claude Code (Windows).
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
# Rate limit warnings are triggered here (via the notification script)
# when usage crosses the configured thresholds.
#
# Input: JSON on stdin (provided by Claude Code)
# Output: ANSI-colored text line on stdout
#
# NOTE: Windows support is not currently tested. Please report issues.

$ConfigDir = Join-Path $env:LOCALAPPDATA "claude-tap"
$ConfigFile = Join-Path $ConfigDir "config.json"

# ──────────────────────────────────────────────────────────────
# Read stdin JSON
# ──────────────────────────────────────────────────────────────

$inputText = [Console]::In.ReadToEnd()
try {
    $data = $inputText | ConvertFrom-Json
} catch {
    $data = $null
}

if (-not $data) { exit 0 }

$model = if ($data.model.display_name) { $data.model.display_name } else { "Claude" }
$usedPct = $data.context_window.used_percentage
$fiveHour = $data.rate_limits.five_hour.used_percentage
$fiveHourResets = $data.rate_limits.five_hour.resets_at
$sevenDay = $data.rate_limits.seven_day.used_percentage
$sevenDayResets = $data.rate_limits.seven_day.resets_at
$linesAdded = $data.cost.total_lines_added
$linesRemoved = $data.cost.total_lines_removed
$cwd = $data.workspace.current_dir
if (-not $cwd) { $cwd = (Get-Location).Path }

# ──────────────────────────────────────────────────────────────
# Read config
# ──────────────────────────────────────────────────────────────

$sl = @{ enabled = $true; show_context_bar = $true; show_rate_5h = $true; show_rate_7d = $true; show_lines_changed = $true; show_git_branch = $true }
$warnThreshold = 80
$critThreshold = 90
$quietEnabled = $false
$quietStart = "22:00"
$quietEnd = "07:00"

if (Test-Path $ConfigFile) {
    try {
        $json = Get-Content $ConfigFile -Raw | ConvertFrom-Json
        if ($null -ne $json.status_line.enabled) { $sl.enabled = $json.status_line.enabled }
        if ($null -ne $json.status_line.show_context_bar) { $sl.show_context_bar = $json.status_line.show_context_bar }
        if ($null -ne $json.status_line.show_rate_5h) { $sl.show_rate_5h = $json.status_line.show_rate_5h }
        if ($null -ne $json.status_line.show_rate_7d) { $sl.show_rate_7d = $json.status_line.show_rate_7d }
        if ($null -ne $json.status_line.show_lines_changed) { $sl.show_lines_changed = $json.status_line.show_lines_changed }
        if ($null -ne $json.status_line.show_git_branch) { $sl.show_git_branch = $json.status_line.show_git_branch }
        if ($null -ne $json.rate_limits.warning_threshold) { $warnThreshold = [int]$json.rate_limits.warning_threshold }
        if ($null -ne $json.rate_limits.critical_threshold) { $critThreshold = [int]$json.rate_limits.critical_threshold }
        if ($null -ne $json.quiet_hours.enabled) { $quietEnabled = $json.quiet_hours.enabled }
        if ($json.quiet_hours.start) { $quietStart = $json.quiet_hours.start }
        if ($json.quiet_hours.end) { $quietEnd = $json.quiet_hours.end }
    } catch {}
}

if (-not $sl.enabled) { exit 0 }

# ──────────────────────────────────────────────────────────────
# ANSI color codes
# ──────────────────────────────────────────────────────────────

$ESC = [char]27
$RESET = "${ESC}[0m"
$BOLD = "${ESC}[1m"
$DIM = "${ESC}[2m"
$ORANGE = "${ESC}[38;5;215m"
$GREEN = "${ESC}[38;5;114m"
$RED = "${ESC}[38;5;174m"
$YELLOW = "${ESC}[38;5;222m"
$GRAY = "${ESC}[38;5;245m"

# ──────────────────────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────────────────────

function Get-PctColor([int]$pct) {
    if ($pct -lt 50) { return $GREEN }
    elseif ($pct -lt 80) { return $YELLOW }
    else { return $RED }
}

function Format-ResetCountdown($resetsAt) {
    if ($null -eq $resetsAt) { return "" }
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $diff = [int]$resetsAt - $now
    if ($diff -le 0) { return "" }
    $days  = [Math]::Floor($diff / 86400)
    $hours = [Math]::Floor(($diff % 86400) / 3600)
    $mins  = [Math]::Floor(($diff % 3600) / 60)
    $local = [DateTimeOffset]::FromUnixTimeSeconds([int64]$resetsAt).LocalDateTime
    if ($days -gt 0) {
        $duration = "${days}d${hours}h${mins}m"
        $clock = $local.ToString("ddd HH:mm", [System.Globalization.CultureInfo]::InvariantCulture)
    } else {
        $duration = "${hours}h${mins}m"
        $clock = $local.ToString("HH:mm")
    }
    return "$duration $([char]0x00B7) $clock"
}

# ──────────────────────────────────────────────────────────────
# Build sections
# ──────────────────────────────────────────────────────────────

$parts = @()

# Git branch (or short SHA in detached HEAD)
if ($sl.show_git_branch -and $cwd -and (Get-Command git -ErrorAction SilentlyContinue)) {
    $branch = & git -C $cwd symbolic-ref --short HEAD 2>$null
    if (-not $branch) { $branch = & git -C $cwd rev-parse --short HEAD 2>$null }
    if ($branch) { $parts += "${GRAY}$([char]0x238B) ${branch}${RESET}" }
}

# Context bar
if ($sl.show_context_bar -and $null -ne $usedPct) {
    $pctInt = [Math]::Round([double]$usedPct)
    $filled = [Math]::Round([double]$usedPct / 10)
    $barColor = Get-PctColor $pctInt
    $bar = ""
    for ($i = 1; $i -le 10; $i++) {
        if ($i -le $filled) { $bar += [char]0x2593 } else { $bar += [char]0x2591 }
    }
    $parts += "${barColor}${pctInt}%${RESET} ${barColor}${bar}${RESET}"
} elseif ($sl.show_context_bar) {
    $parts += "${DIM}ctx: n/a${RESET}"
}

# 5-hour rate limit
if ($sl.show_rate_5h -and $null -ne $fiveHour) {
    $rateInt = [Math]::Round([double]$fiveHour)
    $rateColor = Get-PctColor $rateInt
    $ratePart = "${GRAY}5h:${RESET} ${rateColor}${rateInt}%${RESET}"
    $resetStr = Format-ResetCountdown $fiveHourResets
    if ($resetStr) { $ratePart += " ${DIM}(${resetStr})${RESET}" }
    $parts += $ratePart

    # Cache rate limit for notification tinting
    $rateLimitFile = Join-Path $env:TEMP "claude-rate-limit"
    Set-Content -Path $rateLimitFile -Value $rateInt -NoNewline


    # Trigger rate limit warnings
    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $notifScript = Join-Path $ScriptDir "NotchNotification.ps1"
    $iconPath = Join-Path $ConfigDir "claude-icon.png"
    $warnFile = Join-Path $env:TEMP "claude-rate-warn-warning"
    $critFile = Join-Path $env:TEMP "claude-rate-warn-critical"

    if ($rateInt -ge $critThreshold) {
        if (-not (Test-Path $critFile)) {
            New-Item -Path $critFile -ItemType File -Force | Out-Null
            $resetMsg = if ($resetStr) { " Resets in ${resetStr}." } else { "" }
            Start-Process -NoNewWindow -FilePath "powershell.exe" -ArgumentList @(
                "-ExecutionPolicy", "Bypass", "-File", $notifScript,
                "-Title", '"Rate Limit Warning"',
                "-Message", "`"5h usage at ${rateInt}%.${resetMsg} Consider slowing down.`"",
                "-IconPath", "`"$iconPath`"", "-Urgency", "critical"
            )
        }
    } elseif ($rateInt -ge $warnThreshold) {
        if (-not (Test-Path $warnFile)) {
            New-Item -Path $warnFile -ItemType File -Force | Out-Null
            $resetMsg = if ($resetStr) { " Resets in ${resetStr}." } else { "" }
            Start-Process -NoNewWindow -FilePath "powershell.exe" -ArgumentList @(
                "-ExecutionPolicy", "Bypass", "-File", $notifScript,
                "-Title", '"Rate Limit Warning"',
                "-Message", "`"5h usage at ${rateInt}%.${resetMsg}`"",
                "-IconPath", "`"$iconPath`"", "-Urgency", "warning"
            )
        }
    } else {
        Remove-Item -Path $warnFile -ErrorAction SilentlyContinue
        Remove-Item -Path $critFile -ErrorAction SilentlyContinue
    }
}

# 7-day rate limit
if ($sl.show_rate_7d -and $null -ne $sevenDay) {
    $rate7dInt = [Math]::Round([double]$sevenDay)
    $rate7dColor = Get-PctColor $rate7dInt
    $rate7dPart = "${GRAY}7d:${RESET} ${rate7dColor}${rate7dInt}%${RESET}"
    $reset7dStr = Format-ResetCountdown $sevenDayResets
    if ($reset7dStr) { $rate7dPart += " ${DIM}(${reset7dStr})${RESET}" }
    $parts += $rate7dPart
}

# Lines changed
if ($sl.show_lines_changed -and ($null -ne $linesAdded -or $null -ne $linesRemoved)) {
    $added = if ($null -ne $linesAdded) { [Math]::Round([double]$linesAdded) } else { 0 }
    $removed = if ($null -ne $linesRemoved) { [Math]::Round([double]$linesRemoved) } else { 0 }
    $parts += "${GREEN}+${added}${RESET} ${RED}-${removed}${RESET}"
}

# DND indicator
$DndActive = $false
$dndFile = Join-Path $ConfigDir "dnd"
if (Test-Path $dndFile) {
    $DndActive = $true
}
if ($quietEnabled -and -not $DndActive) {
    $now = [DateTime]::Now.ToString("HH:mm")
    if ($quietStart -gt $quietEnd) {
        if ($now -ge $quietStart -or $now -lt $quietEnd) { $DndActive = $true }
    } else {
        if ($now -ge $quietStart -and $now -lt $quietEnd) { $DndActive = $true }
    }
}
if ($DndActive) {
    $parts += "${DIM}DND${RESET}"
}

# ──────────────────────────────────────────────────────────────
# Output
# ──────────────────────────────────────────────────────────────

$sep = " ${GRAY}|${RESET} "
$out = "${BOLD}${ORANGE}${model}${RESET}"
if ($parts.Count -gt 0) {
    $out += " ${GRAY}|${RESET} " + ($parts -join $sep)
}

Write-Host $out
