// NotchNotification.swift
// Claude Tap - Dynamic Island-style notification overlay for macOS.
//
// Displays a compact notification near the top of the screen with support for:
//   - Markdown rendering (bold, italic, inline code)
//   - Responsive height (adapts to message length)
//   - Urgency-based color tinting (normal, warning, critical)
//   - Configurable position, size, colors, duration, and terminal apps
//
// Configuration is read at runtime from ~/.config/claude-tap/config.json.
// All values have sensible defaults - the binary works even without a config file.
//
// Usage:
//   notch-notify <title> <message> [icon_path] [urgency] [focus_hint]
//
//   urgency: "normal" (default), "warning", or "critical"
//   focus_hint: "k=v;k=v" string describing the originating terminal session,
//               used on click to raise the exact window/tab. Keys:
//                 program    — iterm2 | apple_terminal | vscode | ghostty | warp
//                 session_id — iTerm2 session UUID (hex and dashes only)
//                 tty        — /dev/ttysNNN path (for Terminal.app)
//               Unrecognized or missing values fall back to generic app activation.

import AppKit

// MARK: - Configuration

/// Reads ~/.config/claude-tap/config.json and provides typed access
/// to every setting, with hardcoded fallback defaults.
struct NotifierConfig {
    // Notification layout
    var enabled: Bool = true
    var position: String = "top-center"       // top-center, top-left, top-right, bottom-center, bottom-left, bottom-right
    var width: CGFloat = 380
    var maxLines: Int = 3
    var cornerRadius: CGFloat = 16
    var durationSeconds: Double = 5.5

    // Colors per urgency level - each is [R, G, B, A] with values 0.0-1.0
    var colors: [String: [String: [CGFloat]]] = [
        "normal": [
            "background": [0.05, 0.05, 0.07, 0.96],
            "border":     [1.0, 1.0, 1.0, 0.08],
            "title":      [0.85, 0.55, 0.40, 1.0],
            "text":       [0.95, 0.95, 0.95, 1.0]
        ],
        "warning": [
            "background": [0.12, 0.09, 0.04, 0.96],
            "border":     [0.85, 0.65, 0.20, 0.25],
            "title":      [0.85, 0.55, 0.40, 1.0],
            "text":       [0.95, 0.95, 0.95, 1.0]
        ],
        "critical": [
            "background": [0.14, 0.04, 0.04, 0.96],
            "border":     [0.90, 0.25, 0.20, 0.30],
            "title":      [0.85, 0.55, 0.40, 1.0],
            "text":       [0.95, 0.95, 0.95, 1.0]
        ]
    ]

    // Terminal bundle IDs - used for click-to-focus
    var terminalApps: [String] = [
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

    /// Load config from disk. Missing or malformed fields fall back to defaults.
    static func load() -> NotifierConfig {
        var config = NotifierConfig()
        let path = NSString("~/.config/claude-tap/config.json").expandingTildeInPath

        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return config }

        // Notification settings
        if let notif = json["notification"] as? [String: Any] {
            config.enabled = notif["enabled"] as? Bool ?? config.enabled
            config.position = notif["position"] as? String ?? config.position
            if let w = notif["width"] as? NSNumber { config.width = CGFloat(w.doubleValue) }
            config.maxLines = notif["max_lines"] as? Int ?? config.maxLines
            if let cr = notif["corner_radius"] as? NSNumber { config.cornerRadius = CGFloat(cr.doubleValue) }
            if let ds = notif["duration_seconds"] as? NSNumber { config.durationSeconds = ds.doubleValue }

            // Parse color definitions for each urgency level
            if let colorsJson = notif["colors"] as? [String: [String: [NSNumber]]] {
                for (urgency, fields) in colorsJson {
                    for (field, values) in fields {
                        if values.count == 4 {
                            let floats = values.map { CGFloat($0.doubleValue) }
                            if config.colors[urgency] == nil {
                                config.colors[urgency] = [:]
                            }
                            config.colors[urgency]?[field] = floats
                        }
                    }
                }
            }
        }

        // Terminal apps
        if let apps = json["terminal_apps"] as? [String] {
            config.terminalApps = apps
        }

        // Auto-theme: switch colors based on time of day
        if let theme = json["theme"] as? [String: Any],
           theme["auto"] as? Bool == true {
            let dayStart = theme["day_start"] as? String ?? "08:00"
            let nightStart = theme["night_start"] as? String ?? "18:00"
            let dayTheme = theme["day"] as? String ?? "light"
            let nightTheme = theme["night"] as? String ?? "dark"

            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            let now = formatter.string(from: Date())
            let isDay = now >= dayStart && now < nightStart
            let themeName = isDay ? dayTheme : nightTheme

            // Load theme colors from themes.json
            let themesPath = NSString("~/.config/claude-tap/themes.json").expandingTildeInPath
            // Also try the repo assets location (for when installed via Homebrew)
            let altPath = (path as NSString).deletingLastPathComponent + "/themes.json"
            let themesData = FileManager.default.contents(atPath: themesPath)
                ?? FileManager.default.contents(atPath: altPath)

            if let tData = themesData,
               let themesJson = try? JSONSerialization.jsonObject(with: tData) as? [String: Any],
               let selectedTheme = themesJson[themeName] as? [String: Any],
               let themeColors = selectedTheme["colors"] as? [String: [String: [NSNumber]]] {
                for (urgency, fields) in themeColors {
                    for (field, values) in fields {
                        if values.count == 4 {
                            let floats = values.map { CGFloat($0.doubleValue) }
                            if config.colors[urgency] == nil { config.colors[urgency] = [:] }
                            config.colors[urgency]?[field] = floats
                        }
                    }
                }
            }
        }

        return config
    }

    // MARK: - Color helpers

    /// Returns an NSColor for the given urgency and color role, with fallback to normal.
    func color(urgency: String, role: String) -> NSColor {
        let rgba = colors[urgency]?[role]
            ?? colors["normal"]?[role]
            ?? [0.5, 0.5, 0.5, 1.0]
        return NSColor(red: rgba[0], green: rgba[1], blue: rgba[2], alpha: rgba[3])
    }
}

// MARK: - Clickable View

/// A simple NSView that responds to mouse clicks with a callback.
class ClickableView: NSView {
    var onClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

// MARK: - Markdown Parser

/// Converts a subset of Markdown into an NSAttributedString.
///
/// Supported syntax:
///   - `**bold**`  → semibold weight
///   - `*italic*`  → italic trait
///   - `_italic_`  → italic trait
///   - `` `code` `` → monospaced font
///
/// Unmatched markers are left as plain text. Nesting is not supported;
/// the first (leftmost) match wins when patterns overlap.
func parseMarkdown(_ text: String, baseFont: NSFont, baseColor: NSColor) -> NSAttributedString {
    // Pre-process: bullet lists and headers
    let preprocessed = text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("- ") || (trimmed.hasPrefix("* ") && !trimmed.hasPrefix("**")) {
            return " \u{2022} " + String(trimmed.dropFirst(2))
        }
        if let range = trimmed.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
            return "**" + String(trimmed[range.upperBound...]) + "**"
        }
        return String(line)
    }.joined(separator: "\n")

    let result = NSMutableAttributedString()
    let baseAttrs: [NSAttributedString.Key: Any] = [.font: baseFont, .foregroundColor: baseColor]

    struct Match {
        let range: Range<String.Index>
        let captured: String
        let attrs: [NSAttributedString.Key: Any]
    }

    // Patterns are checked in order: code, bold, italic-asterisk, italic-underscore.
    // Bold must precede single-asterisk italic to avoid partial matches.
    let patterns: [(String, [NSAttributedString.Key: Any])] = [
        ("`([^`]+)`", [
            .font: NSFont.monospacedSystemFont(ofSize: baseFont.pointSize - 1, weight: .regular),
            .foregroundColor: baseColor
        ]),
        ("\\*\\*([^*]+)\\*\\*", [
            .font: NSFont.systemFont(ofSize: baseFont.pointSize, weight: .semibold),
            .foregroundColor: baseColor
        ]),
        ("(?<!\\*)\\*([^*]+)\\*(?!\\*)", [
            .font: NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask),
            .foregroundColor: baseColor
        ]),
        ("(?<!_)_([^_]+)_(?!_)", [
            .font: NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask),
            .foregroundColor: baseColor
        ]),
    ]

    // Collect all regex matches across all patterns
    var matches: [Match] = []
    for (pattern, attrs) in patterns {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
        let nsStr = preprocessed as NSString
        let results = regex.matches(in: preprocessed, range: NSRange(location: 0, length: nsStr.length))
        for r in results {
            guard let fullRange = Range(r.range, in: preprocessed),
                  let capturedRange = Range(r.range(at: 1), in: preprocessed) else { continue }
            matches.append(Match(range: fullRange, captured: String(preprocessed[capturedRange]), attrs: attrs))
        }
    }

    // Sort by position and discard overlapping matches (earlier match wins)
    matches.sort { $0.range.lowerBound < $1.range.lowerBound }
    var filtered: [Match] = []
    for m in matches {
        if let last = filtered.last, m.range.lowerBound < last.range.upperBound { continue }
        filtered.append(m)
    }

    // Build the attributed string: plain text between matches, styled text for matches
    var cursor = preprocessed.startIndex
    for m in filtered {
        if cursor < m.range.lowerBound {
            result.append(NSAttributedString(string: String(preprocessed[cursor..<m.range.lowerBound]), attributes: baseAttrs))
        }
        result.append(NSAttributedString(string: m.captured, attributes: m.attrs))
        cursor = m.range.upperBound
    }
    if cursor < preprocessed.endIndex {
        result.append(NSAttributedString(string: String(preprocessed[cursor...]), attributes: baseAttrs))
    }

    // Post-process: convert [text](url) links to clickable attributed strings
    let linkPattern = "\\[([^\\]]+)\\]\\(([^)]+)\\)"
    if let linkRegex = try? NSRegularExpression(pattern: linkPattern) {
        let fullString = result.string as NSString
        let linkMatches = linkRegex.matches(in: result.string, range: NSRange(location: 0, length: fullString.length))
        // Process in reverse to preserve indices
        for lm in linkMatches.reversed() {
            guard lm.numberOfRanges >= 3 else { continue }
            let textRange = lm.range(at: 1)
            let urlRange = lm.range(at: 2)
            let linkText = fullString.substring(with: textRange)
            let urlString = fullString.substring(with: urlRange)
            guard let url = URL(string: urlString) else { continue }
            let linkAttrs: [NSAttributedString.Key: Any] = [
                .font: baseFont,
                .foregroundColor: NSColor.linkColor,
                .link: url,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ]
            result.replaceCharacters(in: lm.range, with: NSAttributedString(string: linkText, attributes: linkAttrs))
        }
    }

    return result
}

// MARK: - Notification Stack Manager

/// Manages a file-based stack to prevent overlapping notifications.
struct NotifStack {
    struct Entry: Codable {
        let pid: Int32
        let y: Double
        let height: Double
        let timestamp: Double
    }

    static let path: String = {
        let tmpDir = ProcessInfo.processInfo.environment["TMPDIR"] ?? "/tmp"
        return tmpDir + "/claude-notif-stack"
    }()

    static func read() -> [Entry] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              var entries = try? JSONDecoder().decode([Entry].self, from: data) else {
            return []
        }
        // Prune stale entries (older than 30s) and dead processes
        let now = Date().timeIntervalSince1970
        entries = entries.filter { entry in
            guard now - entry.timestamp < 30 else { return false }
            return kill(entry.pid, 0) == 0  // process still alive
        }
        return entries
    }

    static func register(y: CGFloat, height: CGFloat) {
        var entries = read()
        entries.append(Entry(
            pid: ProcessInfo.processInfo.processIdentifier,
            y: Double(y), height: Double(height),
            timestamp: Date().timeIntervalSince1970
        ))
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
        }
    }

    static func unregister() {
        var entries = read()
        let myPid = ProcessInfo.processInfo.processIdentifier
        entries.removeAll { $0.pid == myPid }
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
        }
    }

    static func nextYOffset(baseY: CGFloat, height: CGFloat, isBottom: Bool, gap: CGFloat = 6) -> CGFloat {
        let entries = read()
        if entries.isEmpty { return baseY }
        // Calculate total stacked height
        let totalOffset = entries.reduce(CGFloat(0)) { $0 + CGFloat($1.height) + gap }
        if isBottom {
            return baseY + totalOffset
        } else {
            return baseY - totalOffset
        }
    }
}

// MARK: - Close Button Helper

/// Target for the close button action (prevents retain cycle issues with closures).
class CloseButtonTarget: NSObject {
    weak var overlay: NotchOverlay?
    @objc func closeClicked(_ sender: Any?) {
        overlay?.dismiss()
    }
}

// MARK: - Notification Overlay Window

/// A borderless, floating window that renders the notification overlay.
/// Slides in from above, displays for a configurable duration, then slides out.
class NotchOverlay: NSWindow {
    private let messageLabel = NSTextField(labelWithString: "")
    private var isDismissing = false
    private let titleLabel = NSTextField(labelWithString: "")
    private let iconView = NSImageView()
    private let closeButton = NSButton(frame: .zero)
    private let closeTarget = CloseButtonTarget()
    private var isBottomPosition = false

    /// Parse a "k=v;k=v" focus hint and raise the originating window/tab.
    /// Falls back to a generic `activate` on the first running terminal in
    /// `fallbackApps` when the hint is empty, the program is unknown, or the
    /// targeted AppleScript fails (e.g. the tab has since closed).
    static func focusTerminal(hint: String, fallbackApps: [String]) {
        var parts: [String: String] = [:]
        for seg in hint.split(separator: ";") {
            let kv = seg.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2 { parts[kv[0]] = kv[1] }
        }

        // Belt-and-suspenders sanitization against AppleScript injection: hint
        // values originate from env vars set by the user's terminal, which are
        // usually benign, but we still allow only narrow character classes.
        let uuidRegex = try? NSRegularExpression(pattern: "^[A-Fa-f0-9-]+$")
        let ttyRegex  = try? NSRegularExpression(pattern: "^/dev/ttys[0-9]+$")
        func matches(_ re: NSRegularExpression?, _ s: String) -> Bool {
            guard let re = re else { return false }
            let range = NSRange(s.startIndex..., in: s)
            return re.firstMatch(in: s, options: [], range: range) != nil
        }

        var targeted: String? = nil
        switch parts["program"] ?? "" {
        case "iterm2":
            if let sid = parts["session_id"], matches(uuidRegex, sid) {
                targeted = """
                tell application "iTerm2"
                    activate
                    repeat with theWindow in windows
                        repeat with theTab in tabs of theWindow
                            repeat with theSession in sessions of theTab
                                if id of theSession is "\(sid)" then
                                    select theSession
                                    return
                                end if
                            end repeat
                        end repeat
                    end repeat
                end tell
                """
            }
        case "apple_terminal":
            if let tty = parts["tty"], matches(ttyRegex, tty) {
                targeted = """
                tell application "Terminal"
                    activate
                    repeat with theWindow in windows
                        repeat with theTab in tabs of theWindow
                            if tty of theTab is "\(tty)" then
                                set selected of theTab to true
                                set index of theWindow to 1
                                return
                            end if
                        end repeat
                    end repeat
                end tell
                """
            }
        default:
            break
        }

        if let source = targeted, let script = NSAppleScript(source: source) {
            var err: NSDictionary?
            script.executeAndReturnError(&err)
            if err == nil { return }
        }

        // Accessibility-based fallback: for terminals without per-window
        // AppleScript targeting (Ghostty, VS Code, Warp, …) enumerate the
        // app's on-screen windows via AXUIElement and raise whichever title
        // contains the session's cwd or its basename. First click triggers
        // the macOS Accessibility permission prompt; denying it leaves us
        // with the generic `activate` below.
        if let rawCwd = parts["cwd"], let cwd = percentDecode(rawCwd), !cwd.isEmpty {
            let bundleForProgram: [String: String] = [
                "iterm2":         "com.googlecode.iterm2",
                "apple_terminal": "com.apple.Terminal",
                "ghostty":        "com.mitchellh.ghostty",
                "vscode":         "com.microsoft.VSCode",
                "warp":           "dev.warp.Warp-Stable"
            ]
            let program = parts["program"] ?? ""
            let basename = (cwd as NSString).lastPathComponent

            var bundleOrder: [String] = []
            if let b = bundleForProgram[program] { bundleOrder.append(b) }
            bundleOrder.append(contentsOf: fallbackApps.filter { !bundleOrder.contains($0) })

            for bundleID in bundleOrder {
                if raiseWindow(bundleID: bundleID, titleNeedles: [cwd, basename]) {
                    return
                }
            }
        }

        let runningApps = NSWorkspace.shared.runningApplications
        for bundleID in fallbackApps {
            if runningApps.contains(where: { $0.bundleIdentifier == bundleID }) {
                let source = "tell application id \"\(bundleID)\" to activate"
                if let script = NSAppleScript(source: source) {
                    script.executeAndReturnError(nil)
                }
                break
            }
        }
    }

    /// Percent-decode a value encoded by notify.sh (handles %25 %3B %3D only).
    private static func percentDecode(_ s: String) -> String? {
        return s.removingPercentEncoding ?? s
    }

    /// Enumerate an app's on-screen windows via Accessibility and raise the
    /// first one whose title contains any of the needles. Returns true if a
    /// match was raised; false if the app isn't running, has no AX-visible
    /// windows, permission is denied, or no title matches.
    private static func raiseWindow(bundleID: String, titleNeedles: [String]) -> Bool {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) else {
            return false
        }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var windowsValue: AnyObject?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement], !windows.isEmpty else {
            return false
        }

        for window in windows {
            var titleValue: AnyObject?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue)
            guard let title = titleValue as? String, !title.isEmpty else { continue }
            if titleNeedles.contains(where: { !$0.isEmpty && title.contains($0) }) {
                AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                app.activate(options: [])
                return true
            }
        }
        return false
    }

    init(title: String, message: String, iconPath: String, urgency: String = "normal", focusHint: String = "") {
        let config = NotifierConfig.load()

        // If notifications are disabled, exit immediately
        guard config.enabled else { exit(0) }

        guard let screen = NSScreen.main else { exit(1) }

        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame

        // Layout constants
        let expandedWidth = config.width
        let iconSize: CGFloat = 36
        let iconPadding: CGFloat = 16
        let textX: CGFloat = iconPadding + iconSize + 12
        let textWidth: CGFloat = expandedWidth - textX - 20
        let titleHeight: CGFloat = 18
        let lineHeight: CGFloat = 18
        let topPadding: CGFloat = 12
        let bottomPadding: CGFloat = 10

        // Resolve colors for the current urgency level
        let textColor = config.color(urgency: urgency, role: "text")
        let titleColor = config.color(urgency: urgency, role: "title")
        let bgColor = config.color(urgency: urgency, role: "background")
        let borderColor = config.color(urgency: urgency, role: "border")

        // Parse markdown and measure how many lines the message needs
        let baseFont = NSFont.systemFont(ofSize: 13, weight: .regular)
        let attrMessage = parseMarkdown(message, baseFont: baseFont, baseColor: textColor)

        let measureLabel = NSTextField(labelWithString: "")
        measureLabel.attributedStringValue = attrMessage
        measureLabel.preferredMaxLayoutWidth = textWidth
        measureLabel.maximumNumberOfLines = config.maxLines
        measureLabel.lineBreakMode = .byWordWrapping
        let measuredSize = measureLabel.sizeThatFits(NSSize(width: textWidth, height: CGFloat.greatestFiniteMagnitude))
        let messageLines = min(config.maxLines, max(1, Int(ceil(measuredSize.height / lineHeight))))
        let messageHeight = CGFloat(messageLines) * lineHeight

        // Responsive height based on actual content
        let expandedHeight = topPadding + titleHeight + 2 + messageHeight + bottomPadding

        // Position on screen - supports top-* and bottom-* positions
        let menuBarHeight = screenFrame.height - visibleFrame.height - (visibleFrame.origin.y - screenFrame.origin.y)
        let isBottom = config.position.hasPrefix("bottom")

        let baseYPos: CGFloat
        if isBottom {
            baseYPos = visibleFrame.minY + 6
        } else {
            baseYPos = screenFrame.maxY - menuBarHeight - expandedHeight - 6
        }
        // Stack-aware Y position (offset from other active notifications)
        let yPos = NotifStack.nextYOffset(baseY: baseYPos, height: expandedHeight, isBottom: isBottom)

        let xPos: CGFloat
        if config.position.hasSuffix("left") {
            xPos = screenFrame.minX + 20
        } else if config.position.hasSuffix("right") {
            xPos = screenFrame.maxX - expandedWidth - 20
        } else {
            xPos = screenFrame.midX - expandedWidth / 2
        }

        // Start offset for slide animation (slides toward screen edge)
        let slideOffset: CGFloat = isBottom ? -20 : 20
        let startFrame = NSRect(x: xPos, y: yPos + slideOffset, width: expandedWidth, height: expandedHeight)

        super.init(
            contentRect: startFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.level = .statusBar + 1
        self.isBottomPosition = isBottom
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Container with rounded corners and urgency-tinted background
        let container = ClickableView(frame: NSRect(x: 0, y: 0, width: expandedWidth, height: expandedHeight))
        container.wantsLayer = true
        container.layer?.backgroundColor = bgColor.cgColor
        container.layer?.cornerRadius = config.cornerRadius
        container.layer?.masksToBounds = true
        container.layer?.borderColor = borderColor.cgColor
        container.layer?.borderWidth = 0.5

        // Click to focus the originating terminal window/tab, then dismiss.
        // When a focus hint is available we target the specific session; otherwise
        // we fall back to bringing the terminal app generically to the front.
        let capturedHint = focusHint
        container.onClick = { [weak self] in
            NotchOverlay.focusTerminal(hint: capturedHint, fallbackApps: config.terminalApps)
            self?.dismiss()
        }

        // Close button (✕) - dismiss without focusing terminal
        let closeBtnSize: CGFloat = 28
        closeButton.frame = NSRect(
            x: expandedWidth - closeBtnSize - 6,
            y: expandedHeight - topPadding - closeBtnSize + 6,
            width: closeBtnSize,
            height: closeBtnSize
        )
        closeButton.bezelStyle = .regularSquare
        closeButton.isBordered = false
        closeButton.attributedTitle = NSAttributedString(
            string: "✕",
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: titleColor.withAlphaComponent(0.6)
            ]
        )
        closeButton.alphaValue = 0
        closeTarget.overlay = self
        closeButton.target = closeTarget
        closeButton.action = #selector(CloseButtonTarget.closeClicked(_:))

        // Icon - aligned with the title at the top
        iconView.frame = NSRect(
            x: iconPadding,
            y: expandedHeight - topPadding - iconSize,
            width: iconSize,
            height: iconSize
        )
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = 8
        iconView.layer?.masksToBounds = true
        iconView.alphaValue = 0

        if let image = NSImage(contentsOfFile: iconPath) {
            iconView.image = image
        }

        // Title label - pinned to top
        titleLabel.stringValue = title
        titleLabel.font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        titleLabel.textColor = titleColor
        titleLabel.frame = NSRect(x: textX, y: expandedHeight - topPadding - titleHeight, width: textWidth, height: titleHeight)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.alphaValue = 0

        // Message label - fills remaining space below title
        messageLabel.attributedStringValue = attrMessage
        messageLabel.frame = NSRect(x: textX, y: bottomPadding, width: textWidth, height: messageHeight)
        messageLabel.maximumNumberOfLines = config.maxLines
        messageLabel.lineBreakMode = .byTruncatingTail
        messageLabel.alphaValue = 0

        container.addSubview(iconView)
        container.addSubview(titleLabel)
        container.addSubview(messageLabel)
        container.addSubview(closeButton)
        self.contentView = container

        // Final resting position
        let expandedFrame = NSRect(x: xPos, y: yPos, width: expandedWidth, height: expandedHeight)

        // Register in notification stack
        NotifStack.register(y: yPos, height: expandedHeight)

        // Animate: slide down + fade in
        self.alphaValue = 0
        self.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.4
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1
            self.animator().setFrame(expandedFrame, display: true)
        }) {
            // Then reveal content elements
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.25
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.iconView.animator().alphaValue = 1
                self.titleLabel.animator().alphaValue = 1
                self.messageLabel.animator().alphaValue = 1
                self.closeButton.animator().alphaValue = 1
            })
        }

        // Auto-dismiss after configured duration
        DispatchQueue.main.asyncAfter(deadline: .now() + config.durationSeconds) {
            self.dismiss()
        }
    }

    /// Animate out: slide away from screen edge + fade, then terminate.
    func dismiss() {
        guard !isDismissing else { return }
        isDismissing = true
        NotifStack.unregister()
        let dismissOffset: CGFloat = isBottomPosition ? -20 : 20
        let slideOutFrame = NSRect(
            x: self.frame.origin.x,
            y: self.frame.origin.y + dismissOffset,
            width: self.frame.width,
            height: self.frame.height
        )

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0
            self.animator().setFrame(slideOutFrame, display: true)
        }) {
            NSApp.terminate(nil)
        }
    }
}

// MARK: - Entry Point

let args = CommandLine.arguments
let title = args.count > 1 ? args[1] : "Claude Code"
let message = args.count > 2 ? args[2] : "Needs your attention"
let iconPath = args.count > 3 ? args[3] : ""
let urgency = args.count > 4 ? args[4] : "normal"
let focusHint = args.count > 5 ? args[5] : ""

let app = NSApplication.shared
app.setActivationPolicy(.accessory)  // No dock icon

let _ = NotchOverlay(title: title, message: message, iconPath: iconPath, urgency: urgency, focusHint: focusHint)

app.run()
