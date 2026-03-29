# Claude Tap - Uninstaller (Windows)
#
# Removes:
#   - Claude Code hooks (Notification, Stop) pointing to this tool
#   - Status line configuration
#   - %LOCALAPPDATA%\claude-tap\ directory (assets, config)
#   - Temporary rate limit files
#
# Does NOT remove the cloned repository itself.
#
# NOTE: Windows support is not currently tested. Please report issues.

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigDir = Join-Path $env:LOCALAPPDATA "claude-tap"
$ClaudeDir = Join-Path $env:USERPROFILE ".claude"
$SettingsFile = Join-Path $ClaudeDir "settings.json"

function Write-Info($msg)    { Write-Host "  [info]  $msg" -ForegroundColor Cyan }
function Write-Ok($msg)      { Write-Host "  [ok]    $msg" -ForegroundColor Green }

Write-Host ""
Write-Host "  Claude Tap - Uninstaller (Windows)" -ForegroundColor White
Write-Host ""

# ──────────────────────────────────────────────────────────────
# 1. Remove hooks from Claude Code settings
# ──────────────────────────────────────────────────────────────

if (Test-Path $SettingsFile) {
    Write-Info "Removing hooks from $SettingsFile..."

    # Backup
    $backup = "${SettingsFile}.backup.$(Get-Date -Format 'yyyyMMddHHmmss')"
    Copy-Item $SettingsFile $backup
    Write-Info "Backed up to $backup"

    try {
        # Use python for PS 5.1-safe JSON manipulation
        $settingsJson = Get-Content $SettingsFile -Raw
        $pythonCmd = if (Get-Command python3 -ErrorAction SilentlyContinue) { "python3" }
                     elseif (Get-Command python -ErrorAction SilentlyContinue) { "python" }
                     else { $null }

        if ($pythonCmd) {
            $cleanScript = @'
import json, sys
try:
    settings = json.loads(sys.stdin.read())
except:
    settings = {}
def has_cmd(entry, cmd):
    if cmd in entry.get('command', ''):
        return True
    for h in entry.get('hooks', []):
        if cmd in h.get('command', ''):
            return True
    return False
for ht in ['Notification', 'Stop']:
    hooks = settings.get('hooks', {}).get(ht, [])
    settings.setdefault('hooks', {})[ht] = [h for h in hooks if not has_cmd(h, 'claude-tap')]
    if not settings['hooks'][ht]:
        del settings['hooks'][ht]
if not settings.get('hooks'):
    settings.pop('hooks', None)
sl = settings.get('statusLine', {})
if 'claude-tap' in sl.get('command', ''):
    settings.pop('statusLine', None)
print(json.dumps(settings, indent=2))
'@
            $newSettings = ($settingsJson | & $pythonCmd -c $cleanScript) 2>&1
            Set-Content $SettingsFile -Value $newSettings -Encoding UTF8
        } else {
            Write-Host "  [warn]  Python not found - please manually remove claude-tap hooks from $SettingsFile" -ForegroundColor Yellow
        }
        Write-Ok "Hooks removed"
    } catch {
        Write-Host "  [warn]  Failed to update settings: $_" -ForegroundColor Yellow
    }
} else {
    Write-Info "No settings file found - skipping hook removal"
}

# ──────────────────────────────────────────────────────────────
# 2. Remove config directory
# ──────────────────────────────────────────────────────────────

if (Test-Path $ConfigDir) {
    Write-Info "Removing $ConfigDir..."
    Remove-Item -Recurse -Force $ConfigDir
    Write-Ok "Config directory removed"
} else {
    Write-Info "Config directory not found - skipping"
}

# ──────────────────────────────────────────────────────────────
# 3. Clean up temp files
# ──────────────────────────────────────────────────────────────

Remove-Item -Path (Join-Path $env:TEMP "claude-rate-limit") -ErrorAction SilentlyContinue
Remove-Item -Path (Join-Path $env:TEMP "claude-rate-warn-warning") -ErrorAction SilentlyContinue
Remove-Item -Path (Join-Path $env:TEMP "claude-rate-warn-critical") -ErrorAction SilentlyContinue
Write-Ok "Temporary files cleaned up"

Write-Host ""
Write-Host "  Uninstall complete." -ForegroundColor Green
Write-Host "  Restart Claude Code to apply changes."
Write-Host "  You can safely delete the claude-tap folder if you no longer need it."
Write-Host ""
