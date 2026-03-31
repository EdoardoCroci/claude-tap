# NotchNotification.ps1
# Claude Tap - Toast-style notification overlay for Windows.
#
# Displays a compact notification near the edge of the screen with support for:
#   - Markdown rendering (bold, italic, inline code)
#   - Responsive height (adapts to message length)
#   - Urgency-based color tinting (normal, warning, critical)
#   - Configurable position, size, colors, duration, and terminal apps
#
# Configuration is read at runtime from %LOCALAPPDATA%\claude-tap\config.json.
# All values have sensible defaults - the script works even without a config file.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File NotchNotification.ps1 <title> <message> [icon_path] [urgency]
#
# NOTE: Windows support is not currently tested. Please report issues.

param(
    [string]$Title = "Claude Code",
    [string]$Message = "Needs your attention",
    [string]$IconPath = "",
    [string]$Urgency = "normal"
)

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Drawing

# ──────────────────────────────────────────────────────────────
# Configuration
# ──────────────────────────────────────────────────────────────

function Load-Config {
    $configPath = Join-Path $env:LOCALAPPDATA "claude-tap\config.json"
    $config = @{
        enabled = $true
        position = "top-center"
        width = 380
        max_lines = 3
        corner_radius = 16
        duration_seconds = 5.5
        colors = @{
            normal = @{
                background = @(0.05, 0.05, 0.07, 0.96)
                border = @(1.0, 1.0, 1.0, 0.08)
                title = @(0.85, 0.55, 0.40, 1.0)
                text = @(0.95, 0.95, 0.95, 1.0)
            }
            warning = @{
                background = @(0.12, 0.09, 0.04, 0.96)
                border = @(0.85, 0.65, 0.20, 0.25)
                title = @(0.85, 0.55, 0.40, 1.0)
                text = @(0.95, 0.95, 0.95, 1.0)
            }
            critical = @{
                background = @(0.14, 0.04, 0.04, 0.96)
                border = @(0.90, 0.25, 0.20, 0.30)
                title = @(0.85, 0.55, 0.40, 1.0)
                text = @(0.95, 0.95, 0.95, 1.0)
            }
        }
        terminal_apps = @(
            "WindowsTerminal", "powershell", "pwsh", "cmd",
            "mintty", "git-bash", "alacritty", "ghostty",
            "Hyper", "Warp", "Code", "Code - Insiders", "Cursor"
        )
    }

    if (Test-Path $configPath) {
        try {
            $json = Get-Content $configPath -Raw | ConvertFrom-Json

            if ($json.notification) {
                $n = $json.notification
                if ($null -ne $n.enabled) { $config.enabled = $n.enabled }
                if ($n.position) { $config.position = $n.position }
                if ($null -ne $n.width) { $config.width = [double]$n.width }
                if ($null -ne $n.max_lines) { $config.max_lines = [int]$n.max_lines }
                if ($null -ne $n.corner_radius) { $config.corner_radius = [double]$n.corner_radius }
                if ($null -ne $n.duration_seconds) { $config.duration_seconds = [double]$n.duration_seconds }

                if ($n.colors) {
                    foreach ($urgencyLevel in @("normal", "warning", "critical")) {
                        if ($n.colors.$urgencyLevel) {
                            foreach ($role in @("background", "border", "title", "text")) {
                                $val = $n.colors.$urgencyLevel.$role
                                if ($val -and $val.Count -eq 4) {
                                    $config.colors[$urgencyLevel][$role] = @([double]$val[0], [double]$val[1], [double]$val[2], [double]$val[3])
                                }
                            }
                        }
                    }
                }
            }

            if ($json.terminal_apps) {
                $config.terminal_apps = @($json.terminal_apps)
            }
        } catch {
            # Config parse failed - use defaults
        }
    }

    return $config
}

# Convert RGBA (0.0-1.0) to WPF Color
function New-Color([double[]]$rgba) {
    [System.Windows.Media.Color]::FromArgb(
        [byte]([Math]::Round($rgba[3] * 255)),
        [byte]([Math]::Round($rgba[0] * 255)),
        [byte]([Math]::Round($rgba[1] * 255)),
        [byte]([Math]::Round($rgba[2] * 255))
    )
}

# Get color for urgency level and role
function Get-UrgencyColor($config, [string]$urgency, [string]$role) {
    $rgba = $config.colors[$urgency][$role]
    if (-not $rgba) { $rgba = $config.colors["normal"][$role] }
    if (-not $rgba) { $rgba = @(0.5, 0.5, 0.5, 1.0) }
    return (New-Color $rgba)
}

# ──────────────────────────────────────────────────────────────
# Markdown parser - converts to WPF TextBlock Inlines
# ──────────────────────────────────────────────────────────────

function Add-MarkdownInlines([System.Windows.Controls.TextBlock]$textBlock, [string]$text, $config, [string]$urgency) {
    $textColor = Get-UrgencyColor $config $urgency "text"
    $brush = [System.Windows.Media.SolidColorBrush]::new($textColor)

    # Pre-process headers and bullets (before inline parsing)
    $lines = $text -split "`n"
    $processed = @()
    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^#{1,6}\s+(.+)') {
            $processed += '**' + $Matches[1] + '**'
        } elseif ($trimmed -match '^[-*]\s+(.+)' -and -not $trimmed.StartsWith('**')) {
            $processed += ' ' + [char]0x2022 + ' ' + $Matches[1]
        } else {
            $processed += $line
        }
    }
    $text = $processed -join "`n"

    # Pattern: type, regex, handler
    $patterns = @(
        @{ pattern = '`([^`]+)`'; type = 'code' },
        @{ pattern = '\*\*([^*]+)\*\*'; type = 'bold' },
        @{ pattern = '(?<!\*)\*([^*]+)\*(?!\*)'; type = 'italic' },
        @{ pattern = '(?<!_)_([^_]+)_(?!_)'; type = 'italic' }
    )

    # Collect all matches
    $matches = @()
    foreach ($p in $patterns) {
        $regex = [regex]::new($p.pattern)
        $m = $regex.Matches($text)
        foreach ($match in $m) {
            $matches += @{
                index = $match.Index
                length = $match.Length
                captured = $match.Groups[1].Value
                type = $p.type
            }
        }
    }

    # Sort by position, remove overlaps
    $matches = $matches | Sort-Object { $_.index }
    $filtered = @()
    foreach ($m in $matches) {
        if ($filtered.Count -eq 0 -or $m.index -ge ($filtered[-1].index + $filtered[-1].length)) {
            $filtered += $m
        }
    }

    # Build inlines
    $cursor = 0
    foreach ($m in $filtered) {
        if ($cursor -lt $m.index) {
            $run = [System.Windows.Documents.Run]::new($text.Substring($cursor, $m.index - $cursor))
            $run.Foreground = $brush
            $textBlock.Inlines.Add($run)
        }

        $run = [System.Windows.Documents.Run]::new($m.captured)
        $run.Foreground = $brush
        switch ($m.type) {
            'bold' { $run.FontWeight = [System.Windows.FontWeights]::SemiBold }
            'italic' { $run.FontStyle = [System.Windows.FontStyles]::Italic }
            'code' { $run.FontFamily = [System.Windows.Media.FontFamily]::new("Cascadia Mono, Consolas, Courier New") }
        }
        $textBlock.Inlines.Add($run)
        $cursor = $m.index + $m.length
    }

    if ($cursor -lt $text.Length) {
        $run = [System.Windows.Documents.Run]::new($text.Substring($cursor))
        $run.Foreground = $brush
        $textBlock.Inlines.Add($run)
    }
}

# ──────────────────────────────────────────────────────────────
# Focus terminal on click
# ──────────────────────────────────────────────────────────────

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32Focus {
    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
}
"@

function Focus-Terminal($config) {
    foreach ($appName in $config.terminal_apps) {
        $proc = Get-Process -Name $appName -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($proc -and $proc.MainWindowHandle -ne [IntPtr]::Zero) {
            [Win32Focus]::SetForegroundWindow($proc.MainWindowHandle) | Out-Null
            return
        }
    }
}

# ──────────────────────────────────────────────────────────────
# Build and show notification window
# ──────────────────────────────────────────────────────────────

$config = Load-Config
if (-not $config.enabled) { exit 0 }

$isBottom = $config.position.StartsWith("bottom")

# Colors for current urgency
$bgColor = Get-UrgencyColor $config $Urgency "background"
$borderColor = Get-UrgencyColor $config $Urgency "border"
$titleColor = Get-UrgencyColor $config $Urgency "title"

# Screen dimensions
$screen = [System.Windows.SystemParameters]::WorkArea
$screenFull = [System.Windows.SystemParameters]::PrimaryScreenWidth

# Layout constants
$expandedWidth = $config.width
$iconSize = 36
$iconPadding = 16
$textX = $iconPadding + $iconSize + 12
$textWidth = $expandedWidth - $textX - 20
$titleHeight = 18
$lineHeight = 18
$topPadding = 12
$bottomPadding = 10

# Estimate message lines (rough: ~45 chars per line at 13px)
$charsPerLine = [Math]::Max(1, [Math]::Floor($textWidth / 8.5))
$messageLines = [Math]::Min($config.max_lines, [Math]::Max(1, [Math]::Ceiling($Message.Length / $charsPerLine)))
$messageHeight = $messageLines * $lineHeight
$expandedHeight = $topPadding + $titleHeight + 2 + $messageHeight + $bottomPadding

# Position
if ($config.position -match "left$") {
    $xPos = $screen.Left + 20
} elseif ($config.position -match "right$") {
    $xPos = $screen.Right - $expandedWidth - 20
} else {
    $xPos = ($screen.Left + $screen.Right) / 2 - $expandedWidth / 2
}

if ($isBottom) {
    $yPos = $screen.Bottom - $expandedHeight - 6
} else {
    $yPos = $screen.Top + 6
}

# Force invariant culture for XAML numeric formatting (avoids comma decimals in EU locales)
$inv = [System.Globalization.CultureInfo]::InvariantCulture
$fWidth = $expandedWidth.ToString($inv)
$fHeight = $expandedHeight.ToString($inv)
$fXPos = $xPos.ToString($inv)
$fYPos = $yPos.ToString($inv)
$fCorner = $config.corner_radius.ToString($inv)
$fIconPad = $iconPadding.ToString($inv)
$fIconSz = $iconSize.ToString($inv)
$fTopPad = $topPadding.ToString($inv)
$fTitleH = $titleHeight.ToString($inv)
$fBotPad = $bottomPadding.ToString($inv)

# Create XAML window
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="True" ShowInTaskbar="False" ResizeMode="NoResize"
        Width="$fWidth" Height="$fHeight"
        Left="$fXPos" Top="$fYPos">
    <Border x:Name="Container" CornerRadius="$fCorner" BorderThickness="0.5" Cursor="Hand">
        <Grid>
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="$fIconPad"/>
                <ColumnDefinition Width="$fIconSz"/>
                <ColumnDefinition Width="12"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="20"/>
            </Grid.ColumnDefinitions>
            <Grid.RowDefinitions>
                <RowDefinition Height="$fTopPad"/>
                <RowDefinition Height="$fTitleH"/>
                <RowDefinition Height="2"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="$fBotPad"/>
            </Grid.RowDefinitions>

            <Image x:Name="Icon" Grid.Column="1" Grid.Row="1" Grid.RowSpan="3"
                   Width="$fIconSz" Height="$fIconSz" VerticalAlignment="Top"
                   Stretch="UniformToFill">
                <Image.Clip>
                    <RectangleGeometry Rect="0,0,$fIconSz,$fIconSz" RadiusX="8" RadiusY="8"/>
                </Image.Clip>
            </Image>

            <TextBlock x:Name="TitleText" Grid.Column="3" Grid.Row="1"
                       FontSize="12.5" FontWeight="SemiBold"
                       TextTrimming="CharacterEllipsis" VerticalAlignment="Center"/>

            <TextBlock x:Name="MessageText" Grid.Column="3" Grid.Row="3"
                       FontSize="13" TextWrapping="Wrap"
                       TextTrimming="CharacterEllipsis" VerticalAlignment="Top"/>
        </Grid>
    </Border>
</Window>
"@

$reader = [System.Xml.XmlNodeReader]::new($xaml)
$window = [System.Windows.Markup.XamlReader]::Load($reader)

# Get elements
$container = $window.FindName("Container")
$iconImage = $window.FindName("Icon")
$titleText = $window.FindName("TitleText")
$messageText = $window.FindName("MessageText")

# Apply colors
$container.Background = [System.Windows.Media.SolidColorBrush]::new($bgColor)
$container.BorderBrush = [System.Windows.Media.SolidColorBrush]::new($borderColor)
$titleText.Foreground = [System.Windows.Media.SolidColorBrush]::new($titleColor)
$titleText.Text = $Title

# Max lines via TextBlock
$messageText.MaxHeight = $config.max_lines * $lineHeight

# Markdown rendering
Add-MarkdownInlines $messageText $Message $config $Urgency

# Load icon
if ($IconPath -and (Test-Path $IconPath)) {
    try {
        $bitmap = [System.Windows.Media.Imaging.BitmapImage]::new()
        $bitmap.BeginInit()
        $bitmap.UriSource = [Uri]::new($IconPath)
        $bitmap.EndInit()
        $iconImage.Source = $bitmap
    } catch {
        # Icon load failed - continue without it
    }
}

# Click handler - focus terminal and close
$window.Add_MouseDown({
    Focus-Terminal $config
    $window.Close()
})

# Fade-in animation
$window.Opacity = 0
$slideFrom = if ($isBottom) { $yPos + 20 } else { $yPos - 20 }
$window.Top = $slideFrom

$window.Add_Loaded({
    # Fade in
    $fadeIn = [System.Windows.Media.Animation.DoubleAnimation]::new(0, 1, [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(400)))
    $fadeIn.EasingFunction = [System.Windows.Media.Animation.QuadraticEase]::new()
    $window.BeginAnimation([System.Windows.Window]::OpacityProperty, $fadeIn)

    # Slide in
    $slideIn = [System.Windows.Media.Animation.DoubleAnimation]::new($slideFrom, $yPos, [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(400)))
    $slideIn.EasingFunction = [System.Windows.Media.Animation.QuadraticEase]::new()
    $window.BeginAnimation([System.Windows.Window]::TopProperty, $slideIn)

    # Auto-dismiss timer
    $timer = [System.Windows.Threading.DispatcherTimer]::new()
    $timer.Interval = [TimeSpan]::FromSeconds($config.duration_seconds)
    $timer.Add_Tick({
        $timer.Stop()

        # Fade out
        $fadeOut = [System.Windows.Media.Animation.DoubleAnimation]::new(1, 0, [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(350)))
        $fadeOut.EasingFunction = [System.Windows.Media.Animation.QuadraticEase]::new()
        $fadeOut.Add_Completed({ $window.Close() })
        $window.BeginAnimation([System.Windows.Window]::OpacityProperty, $fadeOut)

        # Slide out
        $slideTo = if ($isBottom) { $yPos + 20 } else { $yPos - 20 }
        $slideOut = [System.Windows.Media.Animation.DoubleAnimation]::new($yPos, $slideTo, [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(350)))
        $slideOut.EasingFunction = [System.Windows.Media.Animation.QuadraticEase]::new()
        $window.BeginAnimation([System.Windows.Window]::TopProperty, $slideOut)
    }.GetNewClosure())
    $timer.Start()
}.GetNewClosure())

# Show window
$window.ShowDialog() | Out-Null
