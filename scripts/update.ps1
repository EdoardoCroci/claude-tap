# Claude Tap - Update script (Windows)
#
# Checks for updates by comparing the local VERSION file against
# the remote VERSION on GitHub. Optionally pulls and re-installs.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File scripts\update.ps1
#   powershell -ExecutionPolicy Bypass -File scripts\update.ps1 -CheckOnly
#
# NOTE: Windows support is not currently tested. Please report issues.

param(
    [switch]$CheckOnly
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoDir = Split-Path -Parent $ScriptDir
$VersionFile = Join-Path $RepoDir "VERSION"
$RemoteUrl = "https://raw.githubusercontent.com/EdoardoCroci/claude-tap/main/VERSION"

# ──────────────────────────────────────────────────────────────
# Output helpers
# ──────────────────────────────────────────────────────────────

function Write-Info($msg)    { Write-Host "  [info]  $msg" -ForegroundColor Cyan }
function Write-Ok($msg)      { Write-Host "  [ok]    $msg" -ForegroundColor Green }
function Write-Warn($msg)    { Write-Host "  [warn]  $msg" -ForegroundColor Yellow }
function Write-Fail($msg)    { Write-Host "  [error] $msg" -ForegroundColor Red; exit 1 }

# ──────────────────────────────────────────────────────────────
# Read local version
# ──────────────────────────────────────────────────────────────

if (-not (Test-Path $VersionFile)) {
    Write-Fail "VERSION file not found at $VersionFile"
}

$localVersion = (Get-Content $VersionFile -Raw).Trim()

if ($localVersion -notmatch '^\d+\.\d+\.\d+$') {
    Write-Fail "Invalid local version format: '$localVersion' (expected X.Y.Z)"
}

Write-Info "Local version: $localVersion"

# ──────────────────────────────────────────────────────────────
# Fetch remote version
# ──────────────────────────────────────────────────────────────

Write-Info "Checking for updates..."

try {
    $response = Invoke-WebRequest -Uri $RemoteUrl -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop
    $remoteVersion = $response.Content.Trim()
} catch {
    Write-Warn "Could not reach update server. Skipping update check."
    exit 0
}

if ($remoteVersion -notmatch '^\d+\.\d+\.\d+$') {
    Write-Warn "Invalid remote version format: '$remoteVersion'. Skipping update check."
    exit 0
}

Write-Info "Remote version: $remoteVersion"

# ──────────────────────────────────────────────────────────────
# Compare versions
# ──────────────────────────────────────────────────────────────

function Compare-SemVer($v1, $v2) {
    $parts1 = $v1 -split '\.' | ForEach-Object { [int]$_ }
    $parts2 = $v2 -split '\.' | ForEach-Object { [int]$_ }
    for ($i = 0; $i -lt 3; $i++) {
        if ($parts1[$i] -gt $parts2[$i]) { return 1 }
        if ($parts1[$i] -lt $parts2[$i]) { return -1 }
    }
    return 0
}

$cmp = Compare-SemVer $remoteVersion $localVersion
if ($cmp -le 0) {
    Write-Ok "You are up to date ($localVersion)"
    exit 0
}

Write-Host ""
Write-Host "  Update available: $localVersion -> $remoteVersion" -ForegroundColor Yellow
Write-Host ""

if ($CheckOnly) {
    Write-Host "  Run: powershell -ExecutionPolicy Bypass -File scripts\update.ps1" -ForegroundColor Cyan
    exit 0
}

# ──────────────────────────────────────────────────────────────
# Pull and re-install
# ──────────────────────────────────────────────────────────────

Write-Info "Pulling latest changes..."
Push-Location $RepoDir
try {
    & git pull
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "git pull failed. Resolve any conflicts and try again."
    }
} finally {
    Pop-Location
}

Write-Info "Re-running Windows installer..."
& powershell -ExecutionPolicy Bypass -File (Join-Path $RepoDir "windows\install.ps1")

Write-Host ""
Write-Ok "Updated to $remoteVersion"
