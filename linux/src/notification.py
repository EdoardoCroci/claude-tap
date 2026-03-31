#!/usr/bin/env python3
"""
Claude Tap - GTK3 notification overlay for Linux.

Displays a Dynamic Island-style notification overlay with animations,
markdown rendering, and click-to-focus terminal support.

Falls back to notify-send if GTK3 is not available.

Usage:
    notification.py <title> <message> [icon_path] [urgency]

Urgency: "normal" (default), "warning", "critical"
"""

import json
import os
import re
import shutil
import subprocess
import sys

# ──────────────────────────────────────────────────────────────
# Configuration
# ──────────────────────────────────────────────────────────────

CONFIG_PATH = os.path.expanduser("~/.config/claude-tap/config.json")

DEFAULT_CONFIG = {
    "notification": {
        "position": "top-center",
        "width": 380,
        "max_lines": 3,
        "corner_radius": 16,
        "duration_seconds": 5.5,
        "colors": {
            "normal": {
                "background": [0.05, 0.05, 0.07, 0.96],
                "border": [1.0, 1.0, 1.0, 0.08],
                "title": [0.85, 0.55, 0.40, 1.0],
                "text": [0.95, 0.95, 0.95, 1.0],
            },
            "warning": {
                "background": [0.12, 0.09, 0.04, 0.96],
                "border": [0.85, 0.65, 0.20, 0.25],
                "title": [0.85, 0.55, 0.40, 1.0],
                "text": [0.95, 0.95, 0.95, 1.0],
            },
            "critical": {
                "background": [0.14, 0.04, 0.04, 0.96],
                "border": [0.90, 0.25, 0.20, 0.30],
                "title": [0.85, 0.55, 0.40, 1.0],
                "text": [0.95, 0.95, 0.95, 1.0],
            },
        },
    },
    "terminal_apps": [
        "kitty", "alacritty", "ghostty", "wezterm", "foot",
        "gnome-terminal", "konsole", "xfce4-terminal", "xterm",
        "code", "code-insiders", "cursor",
    ],
}


def load_config():
    """Load config from JSON file, falling back to defaults.

    If theme.auto is enabled, overrides notification.colors based on time of day.
    """
    try:
        with open(CONFIG_PATH) as f:
            config = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return DEFAULT_CONFIG

    # Auto-theme: switch colors based on time of day
    theme_cfg = config.get("theme", {})
    if theme_cfg.get("auto", False):
        import datetime
        now = datetime.datetime.now().strftime("%H:%M")
        day_start = theme_cfg.get("day_start", "08:00")
        night_start = theme_cfg.get("night_start", "18:00")
        is_day = day_start <= now < night_start
        theme_name = theme_cfg.get("day", "light") if is_day else theme_cfg.get("night", "dark")

        # Try loading themes.json from config dir, then from repo assets
        themes_paths = [
            os.path.expanduser("~/.config/claude-tap/themes.json"),
            os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "themes.json"),
        ]
        for tp in themes_paths:
            try:
                with open(tp) as f:
                    themes = json.load(f)
                if theme_name in themes:
                    config.setdefault("notification", {})["colors"] = themes[theme_name]["colors"]
                    break
            except (FileNotFoundError, json.JSONDecodeError, KeyError):
                continue

    return config


def get_color(config, urgency, role):
    """Get an RGBA color tuple from config for given urgency and role."""
    colors = config.get("notification", {}).get("colors", {})
    urgency_colors = colors.get(urgency, DEFAULT_CONFIG["notification"]["colors"].get(urgency, {}))
    default_colors = DEFAULT_CONFIG["notification"]["colors"].get(urgency, {})
    return urgency_colors.get(role, default_colors.get(role, [0.5, 0.5, 0.5, 1.0]))


# ──────────────────────────────────────────────────────────────
# Fallback: notify-send
# ──────────────────────────────────────────────────────────────

def fallback_notify(title, message, icon_path, urgency):
    """Use notify-send as fallback when GTK3 is not available."""
    cmd = ["notify-send", title, message]
    if icon_path and os.path.isfile(icon_path):
        cmd.extend(["--icon", icon_path])
    urgency_map = {"normal": "normal", "warning": "normal", "critical": "critical"}
    cmd.extend(["--urgency", urgency_map.get(urgency, "normal")])
    try:
        subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except FileNotFoundError:
        pass  # notify-send not available either
    sys.exit(0)


# ──────────────────────────────────────────────────────────────
# Try to import GTK3
# ──────────────────────────────────────────────────────────────

# ──────────────────────────────────────────────────────────────
# Notification Stack Manager
# ──────────────────────────────────────────────────────────────

STACK_PATH = os.path.join(os.environ.get("TMPDIR", "/tmp"), "claude-notif-stack")


def _read_stack():
    """Read and prune stale entries from the notification stack."""
    try:
        with open(STACK_PATH) as f:
            entries = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return []
    now = __import__("time").time()
    alive = []
    for e in entries:
        if now - e.get("timestamp", 0) > 30:
            continue
        try:
            os.kill(e["pid"], 0)
            alive.append(e)
        except (OSError, KeyError):
            continue
    return alive


def _write_stack_locked(entries):
    """Write stack entries with file locking."""
    import fcntl
    fd = os.open(STACK_PATH, os.O_RDWR | os.O_CREAT, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        f = os.fdopen(fd, "w")
        json.dump(entries, f)
        f.truncate()
        f.close()
    except Exception:
        try:
            os.close(fd)
        except OSError:
            pass


def _register_in_stack(y, height):
    """Register this notification in the stack (file-locked)."""
    entries = _read_stack()
    entries.append({
        "pid": os.getpid(),
        "y": y,
        "height": height,
        "timestamp": __import__("time").time(),
    })
    _write_stack_locked(entries)


def _unregister_from_stack():
    """Remove this notification from the stack (file-locked)."""
    entries = _read_stack()
    my_pid = os.getpid()
    entries = [e for e in entries if e.get("pid") != my_pid]
    _write_stack_locked(entries)


def _next_y_offset(base_y, height, is_bottom, gap=6):
    """Calculate the next available Y position based on stacked notifications."""
    entries = _read_stack()
    if not entries:
        return base_y
    total_offset = sum(e.get("height", 0) + gap for e in entries)
    if is_bottom:
        return base_y + total_offset
    else:
        return base_y - total_offset


try:
    import gi
    gi.require_version("Gtk", "3.0")
    gi.require_version("Gdk", "3.0")
    gi.require_version("Pango", "1.0")
    from gi.repository import Gtk, Gdk, GLib, Pango, GdkPixbuf
    HAS_GTK = True
except (ImportError, ValueError):
    HAS_GTK = False


# ──────────────────────────────────────────────────────────────
# Markdown to Pango markup
# ──────────────────────────────────────────────────────────────

def markdown_to_pango(text):
    """Convert markdown (bold, italic, code, bullets, headers, links) to Pango markup.

    Input is escaped first to prevent markup injection.
    """
    # Pre-process bullet lists before escaping (- item or * item, but not **bold**)
    lines = text.split('\n')
    processed = []
    for line in lines:
        stripped = line.strip()
        if stripped.startswith('- ') or (stripped.startswith('* ') and not stripped.startswith('**')):
            processed.append(' \u2022 ' + stripped[2:])
        elif re.match(r'^#{1,6}\s+', stripped):
            header_text = re.sub(r'^#{1,6}\s+', '', stripped)
            processed.append('__HEADER__' + header_text)
        else:
            processed.append(line)
    text = '\n'.join(processed)

    # Escape for Pango safety
    text = GLib.markup_escape_text(text)

    # Headers (marked before escaping)
    text = re.sub(r'__HEADER__(.+?)(?=\n|$)', r'<b><big>\1</big></b>', text)
    # Bold: **text**
    text = re.sub(r'\*\*(.+?)\*\*', r'<b>\1</b>', text)
    # Italic: *text*
    text = re.sub(r'\*(.+?)\*', r'<i>\1</i>', text)
    # Code: `text`
    text = re.sub(r'`(.+?)`', r'<tt>\1</tt>', text)
    # Links: [text](url) — URL is escaped to prevent markup injection
    text = re.sub(
        r'\[(.+?)\]\((.+?)\)',
        lambda m: '<a href="{}">{}</a>'.format(GLib.markup_escape_text(m.group(2)), m.group(1)),
        text
    )
    return text


# ──────────────────────────────────────────────────────────────
# GTK3 Notification Window
# ──────────────────────────────────────────────────────────────

if HAS_GTK:

    class NotificationWindow(Gtk.Window):
        def __init__(self, title_text, message, icon_path, urgency):
            super().__init__(type=Gtk.WindowType.POPUP)
            self.config = load_config()
            self.urgency = urgency
            self._opacity = 0.0
            self._target_y = 0
            self._current_y = 0

            notif = self.config.get("notification", {})
            self.width = notif.get("width", 380)
            self.max_lines = notif.get("max_lines", 3)
            self.corner_radius = notif.get("corner_radius", 16)
            self.duration = notif.get("duration_seconds", 5.5)
            self.position = notif.get("position", "top-center")
            self.terminal_apps = self.config.get("terminal_apps",
                DEFAULT_CONFIG["terminal_apps"])

            # Window properties
            self.set_decorated(False)
            self.set_skip_taskbar_hint(True)
            self.set_skip_pager_hint(True)
            self.set_keep_above(True)
            self.set_accept_focus(False)
            self.set_app_paintable(True)
            self.set_type_hint(Gdk.WindowTypeHint.NOTIFICATION)

            # Enable transparency
            screen = self.get_screen()
            visual = screen.get_rgba_visual()
            if visual:
                self.set_visual(visual)

            # Colors
            self.bg_color = get_color(self.config, urgency, "background")
            self.border_color = get_color(self.config, urgency, "border")
            self.title_color = get_color(self.config, urgency, "title")
            self.text_color = get_color(self.config, urgency, "text")

            # Layout
            self._build_ui(title_text, message, icon_path)

            # Events
            self.connect("draw", self._on_draw)
            self.add_events(Gdk.EventMask.BUTTON_PRESS_MASK)
            self.connect("button-press-event", self._on_click)

            # Calculate position
            display = Gdk.Display.get_default()
            monitor = display.get_primary_monitor() or display.get_monitor(0)
            geom = monitor.get_geometry()
            scale = monitor.get_scale_factor()

            # Account for HiDPI
            screen_w = geom.width
            screen_h = geom.height
            win_w = self.width

            # Estimate height based on content
            win_h = 80 + (min(self.max_lines, 3) * 20)

            self.set_default_size(win_w, win_h)

            # Position
            margin = 20
            if "left" in self.position:
                x = geom.x + margin
            elif "right" in self.position:
                x = geom.x + screen_w - win_w - margin
            else:
                x = geom.x + (screen_w - win_w) // 2

            is_bottom = "bottom" in self.position
            if is_bottom:
                base_y = geom.y + screen_h - win_h - margin
                self._target_y = _next_y_offset(base_y, win_h, True)
                self._current_y = geom.y + screen_h + 10  # Start below screen
            else:
                base_y = geom.y + margin + 30  # Below panel
                self._target_y = _next_y_offset(base_y, win_h, False)
                self._current_y = geom.y - win_h - 10  # Start above screen
            self._win_h = win_h
            self._is_dismissing = False

            self._x = x
            self.move(x, self._current_y)

        def _build_ui(self, title_text, message, icon_path):
            """Build the notification content."""
            hbox = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
            hbox.set_margin_top(14)
            hbox.set_margin_bottom(14)
            hbox.set_margin_start(16)
            hbox.set_margin_end(16)

            # Icon
            if icon_path and os.path.isfile(icon_path):
                try:
                    pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(icon_path, 36, 36, True)
                    icon_widget = Gtk.Image.new_from_pixbuf(pixbuf)
                    icon_widget.set_valign(Gtk.Align.START)
                    hbox.pack_start(icon_widget, False, False, 0)
                except GLib.Error:
                    pass

            # Text container
            vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)

            # Title
            title_label = Gtk.Label()
            title_markup = f'<span foreground="rgba({int(self.title_color[0]*255)},{int(self.title_color[1]*255)},{int(self.title_color[2]*255)},{self.title_color[3]})"><b>{GLib.markup_escape_text(title_text)}</b></span>'
            title_label.set_markup(title_markup)
            title_label.set_halign(Gtk.Align.START)
            title_label.set_ellipsize(Pango.EllipsizeMode.END)
            vbox.pack_start(title_label, False, False, 0)

            # Message
            msg_label = Gtk.Label()
            msg_pango = markdown_to_pango(message)
            msg_markup = f'<span foreground="rgba({int(self.text_color[0]*255)},{int(self.text_color[1]*255)},{int(self.text_color[2]*255)},{self.text_color[3]})">{msg_pango}</span>'
            msg_label.set_markup(msg_markup)
            msg_label.set_halign(Gtk.Align.START)
            msg_label.set_line_wrap(True)
            msg_label.set_line_wrap_mode(Pango.WrapMode.WORD_CHAR)
            msg_label.set_max_width_chars(45)
            msg_label.set_lines(self.max_lines)
            msg_label.set_ellipsize(Pango.EllipsizeMode.END)
            vbox.pack_start(msg_label, False, False, 0)

            hbox.pack_start(vbox, True, True, 0)
            self.add(hbox)

        def _on_draw(self, widget, cr):
            """Draw the notification background with rounded corners."""
            alloc = widget.get_allocation()
            w, h = alloc.width, alloc.height
            r = self.corner_radius

            # Rounded rectangle path
            cr.new_path()
            cr.arc(w - r, r, r, -0.5 * 3.14159, 0)
            cr.arc(w - r, h - r, r, 0, 0.5 * 3.14159)
            cr.arc(r, h - r, r, 0.5 * 3.14159, 3.14159)
            cr.arc(r, r, r, 3.14159, 1.5 * 3.14159)
            cr.close_path()

            # Background
            cr.set_source_rgba(*self.bg_color)
            cr.fill_preserve()

            # Border
            cr.set_source_rgba(*self.border_color)
            cr.set_line_width(1)
            cr.stroke()

            # Apply overall opacity
            if self._opacity < 1.0:
                cr.set_source_rgba(0, 0, 0, 0)

            return False

        def _on_click(self, widget, event):
            """Click to dismiss, then focus terminal in the background."""
            # Dismiss first (while window still has focus for animation)
            self._dismiss()
            # Focus terminal after a short delay
            GLib.timeout_add(100, self._focus_terminal)

        def _focus_terminal(self):
            """Try to focus the first running terminal from terminal_apps."""
            for app in self.terminal_apps:
                if shutil.which("xdotool"):
                    try:
                        result = subprocess.run(
                            ["xdotool", "search", "--name", app],
                            capture_output=True, text=True, timeout=2
                        )
                        windows = result.stdout.strip().split("\n")
                        if windows and windows[0]:
                            subprocess.run(
                                ["xdotool", "windowactivate", windows[0]],
                                timeout=2
                            )
                            return
                    except (subprocess.TimeoutExpired, FileNotFoundError):
                        continue
                if shutil.which("wmctrl"):
                    try:
                        subprocess.run(
                            ["wmctrl", "-a", app],
                            timeout=2
                        )
                        return
                    except (subprocess.TimeoutExpired, FileNotFoundError):
                        continue

        def animate_in(self):
            """Slide and fade in."""
            _register_in_stack(self._target_y, self._win_h)
            self.show_all()
            self._opacity = 0.0
            self.set_opacity(0.0)

            steps = 20
            step_time = 20  # ms
            dy = (self._target_y - self._current_y) / steps
            self._step_counter = [0]

            def animate_step():
                self._step_counter[0] += 1
                i = self._step_counter[0]
                if i >= steps:
                    self._current_y = self._target_y
                    self.move(self._x, self._target_y)
                    self._opacity = 1.0
                    self.set_opacity(1.0)
                    GLib.timeout_add(int(self.duration * 1000), self._dismiss)
                    return False

                progress = i / steps
                ease = 1 - (1 - progress) ** 3

                self._current_y = self._current_y + dy
                self.move(self._x, int(self._current_y))
                self._opacity = ease
                self.set_opacity(ease)
                self.queue_draw()
                return True

            GLib.timeout_add(step_time, animate_step)

        def _dismiss(self):
            """Fade out and close."""
            if self._is_dismissing:
                return False
            self._is_dismissing = True
            _unregister_from_stack()
            steps = 15
            step_time = 23

            self._fade_step = [0]

            def fade_out():
                self._fade_step[0] += 1
                i = self._fade_step[0]
                if i >= steps:
                    Gtk.main_quit()
                    return False
                progress = i / steps
                self.set_opacity(1.0 - progress)
                return True

            GLib.timeout_add(step_time, fade_out)
            return False


# ──────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────

def main():
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <title> <message> [icon_path] [urgency]", file=sys.stderr)
        sys.exit(1)

    title = sys.argv[1]
    message = sys.argv[2]
    icon_path = sys.argv[3] if len(sys.argv) > 3 else ""
    urgency = sys.argv[4] if len(sys.argv) > 4 else "normal"

    if urgency not in ("normal", "warning", "critical"):
        urgency = "normal"

    if not HAS_GTK:
        fallback_notify(title, message, icon_path, urgency)
        return

    # Safety timeout: force exit after duration + 5 seconds to prevent hangs
    config = load_config()
    max_duration = config.get("notification", {}).get("duration_seconds", 5.5) + 5
    GLib.timeout_add(int(max_duration * 1000), lambda: (Gtk.main_quit(), False)[1])

    win = NotificationWindow(title, message, icon_path, urgency)
    win.animate_in()
    Gtk.main()


if __name__ == "__main__":
    main()
