"""GTK 3 and 4 apps: the palette over the base theme (Graphite-Dark, else Adwaita-dark)."""
import subprocess
import time
from pathlib import Path

from ..colors import css_rgba, mix
from ..files import GENERATED, write
from ..paths import HOME

GTK_COMMON = """
window, .background {{ background-color: {bg}; color: {fg}; }}
headerbar, .titlebar, headerbar.titlebar {{
    background: {bg2}; color: {fg}; border-color: {border}; box-shadow: none;
}}
headerbar:backdrop, .titlebar:backdrop {{ background: {bg}; color: {muted}; }}
.sidebar, placessidebar, placessidebar list, placessidebar row, .navigation-sidebar {{
    background-color: {sidebar}; color: {fg};
}}
.view, iconview, treeview.view, textview text, list, list row, gridview, columnview {{
    background-color: {bg}; color: {fg};
}}
.view:selected, iconview:selected, treeview.view:selected, list row:selected,
placessidebar row:selected, .navigation-sidebar row:selected, *:selected {{
    background-color: {sel}; color: {fg};
}}
.view:hover, list row:hover, placessidebar row:hover {{ background-color: {hover}; }}
/* The drag-selection box is drawn with the view's own style context, so without this it
   inherits the opaque .view background above and covers the files as a solid square. */
.view.rubberband, .rubberband, rubberband, iconview.rubberband, treeview.view.rubberband,
flowbox rubberband, gridview > rubberband, columnview > rubberband {{
    background-color: {rubber}; border: 1px solid {accent};
}}
entry, spinbutton, searchbar entry {{
    background-color: {bg2}; color: {fg}; border-color: {border}; caret-color: {accent};
}}
entry:focus, spinbutton:focus {{ border-color: {accent}; box-shadow: inset 0 0 0 1px {accent}; }}
button {{ background-image: none; background-color: {bg2}; color: {fg}; border-color: {border}; }}
button:hover {{ background-color: {hover}; }}
button:checked, button:active {{ background-color: {sel}; }}
button.suggested-action {{ background-color: {accent}; color: {bg}; }}
button.destructive-action {{ background-color: {crit}; color: {bg}; }}
menu, .menu, .context-menu, popover, popover > contents, popover.background {{
    background-color: {bg2}; color: {fg};
}}
menu menuitem:hover, popover modelbutton:hover, .menu menuitem:hover {{
    background-color: {sel}; color: {fg};
}}
tooltip, tooltip.background {{ background-color: {bg2}; color: {fg}; border: 1px solid {border}; }}
scrollbar slider {{ background-color: {scroll}; }}
scrollbar slider:hover {{ background-color: {accent}; }}
link, *:link {{ color: {accent}; }}
progressbar progress, scale highlight, levelbar block.filled {{ background-color: {accent}; }}
switch:checked {{ background-color: {accent}; }}
check:checked, radio:checked {{ background-color: {accent}; color: {bg}; }}
statusbar, .statusbar {{ background-color: {bg2}; color: {muted}; }}
/* Thunar's toolbar and location bar draw their own backgrounds; without these they keep the
   base theme's (white with a light or missing base theme). */
toolbar, .toolbar, .primary-toolbar, .inline-toolbar, .location-button, .path-bar,
.path-bar button, .linked > button, .pathbar, .pathbar button {{
    background-image: none; background-color: {bg2}; color: {fg}; border-color: {border};
}}
.path-bar button:checked, .pathbar button:checked {{ background-color: {sel}; }}
toolbar entry, .location-bar entry, .location-entry {{ background-color: {bg}; color: {fg}; }}
/* Pane dividers and frame borders (Thunar's sidebar edge, the lines above and below its file list)
   take the base theme's colour otherwise: light grey with Adwaita. */
paned > separator {{ background-image: image({border}); }}
frame > border, .frame {{ border-color: {border}; }}
"""


def apply(theme):
    colors = theme.colors
    rule_colors = {
        "bg": colors["bg"], "bg2": colors["bg2"], "fg": colors["fg"], "muted": colors["muted"],
        "accent": colors["accent"], "crit": colors["crit"],
        "sidebar": mix(colors["bg"], colors["bg2"], 0.6),
        "border": mix(colors["bg2"], colors["muted"], 0.35),
        "sel": css_rgba(colors["accent"], 0.32),
        "hover": css_rgba(colors["accent"], 0.14),
        "rubber": css_rgba(colors["accent"], 0.18),
        "scroll": css_rgba(colors["fg"], 0.25),
    }
    gtk3_colors = {
        "theme_bg_color": colors["bg"], "theme_fg_color": colors["fg"], "theme_base_color": colors["bg"],
        "theme_text_color": colors["fg"], "theme_selected_bg_color": colors["accent"],
        "theme_selected_fg_color": colors["bg"], "accent_color": colors["accent"],
        "accent_bg_color": colors["accent"], "accent_fg_color": colors["bg"],
        "borders": rule_colors["border"], "headerbar_bg_color": colors["bg2"], "headerbar_fg_color": colors["fg"],
        "popover_bg_color": colors["bg2"], "popover_fg_color": colors["fg"],
        "error_color": colors["crit"], "warning_color": colors["warn"], "success_color": colors["good"],
    }
    gtk4_colors = {
        **gtk3_colors,
        "window_bg_color": colors["bg"], "window_fg_color": colors["fg"],
        "view_bg_color": colors["bg"], "view_fg_color": colors["fg"],
        "sidebar_bg_color": rule_colors["sidebar"], "sidebar_fg_color": colors["fg"],
        "card_bg_color": colors["bg2"], "card_fg_color": colors["fg"],
        "dialog_bg_color": colors["bg2"], "dialog_fg_color": colors["fg"],
        "destructive_bg_color": colors["crit"], "destructive_color": colors["crit"],
    }
    gtk3_defines = "".join(f"@define-color {key} {value};\n" for key, value in gtk3_colors.items())
    gtk4_defines = "".join(f"@define-color {key} {value};\n" for key, value in gtk4_colors.items())
    rules = GTK_COMMON.format(**rule_colors)
    base = base_theme()
    head = f"/* Тема «{theme.name}» поверх {base}. {GENERATED} */\n"
    sheets = {HOME / ".config/gtk-3.0/gtk.css": head + gtk3_defines + rules}
    for file_name in ("gtk.css", "gtk-dark.css"):
        sheets[HOME / ".config/gtk-4.0" / file_name] = head + gtk4_import(base, file_name) + gtk4_defines + rules
    if write_changed(sheets):
        # The same sheets again (the theme reapplied for its fonts) leave open apps as they are.
        reload()


def write_changed(sheets):
    """Writes each {path: text} whose file holds other text; whether any was written."""
    changed = [path for path, text in sheets.items() if not path.exists() or path.read_text() != text]
    for path in changed:
        write(path, sheets[path])
    return bool(changed)


def gtk4_import(base, file_name):
    """GTK 4 picks no theme by name: the user's gtk.css imports the base theme's own. Adwaita ships none,
    it is built into GTK 4."""
    css = Path("/usr/share/themes") / base / "gtk-4.0" / file_name
    return f'@import url("file://{css}");\n' if css.exists() else ""


def base_theme():
    """The GTK theme gtk.css is written over; the rice installer falls back to Adwaita-dark the same way."""
    return "Graphite-Dark" if Path("/usr/share/themes/Graphite-Dark").is_dir() else "Adwaita-dark"


def reload():
    """Makes open GTK apps reread the user gtk.css, which they do only when the theme name changes: the
    name goes to a stand-in and back. It lands on the base theme, not on the name found in the setting:
    once the setting held another theme (the stand-in, after a bounce cut short), every later bounce
    restored that one."""
    try:
        base = base_theme()
        # A dark stand-in: bouncing through light Adwaita left white toolbars in open windows.
        set_theme_seen_by_apps("Adwaita-dark" if base != "Adwaita-dark" else "Adwaita")
        set_theme_seen_by_apps(base)
        # File chooser dialogs (Code - OSS, browsers, ...) come from this portal; it does not follow
        # the bounce above, so restart it, once it has sent the base theme on (it is the settings
        # portal too). It is D-Bus activated, nothing is lost. Not waited for (~80 ms): the next
        # bounce comes with the next theme change, after changetheme's later steps.
        subprocess.run(["systemctl", "--user", "--no-block", "try-restart", "xdg-desktop-portal-gtk.service"],
                       timeout=10)
    except (OSError, subprocess.SubprocessError):
        pass


# The apps get the setting from the settings portal, which passes a change on within milliseconds. A
# heuristic: when it is this late, the theme goes back all the same; above the fixed wait used before.
PORTAL_TIMEOUT_MS = 500
# Without PyGObject to watch the portal with: that fixed wait.
UNWATCHED_WAIT_S = 0.3


def set_theme_seen_by_apps(name):
    """Sets the theme name and returns once the settings portal has sent it to the apps. Set back sooner,
    the change can be lost: the portal sends the value the setting has when it gets to a change, and
    two changes 10 ms apart came out as the second one twice (seen with the real portal on a private
    D-Bus session), so the apps saw no change at all."""
    try:
        from gi.repository import Gio, GLib
    except ImportError:
        set_theme(name)
        time.sleep(UNWATCHED_WAIT_S)
        return
    try:
        bus = Gio.bus_get_sync(Gio.BusType.SESSION)
    except GLib.Error:  # no session bus: gsettings has no dconf to write to, no app is told anything
        set_theme(name)
        return
    loop = GLib.MainLoop()
    announced = []

    def on_setting_changed(_bus, _sender, _path, _interface, _signal, parameters):
        if parameters.unpack() == ("org.gnome.desktop.interface", "gtk-theme", name):
            announced.append(name)
            loop.quit()

    subscription = bus.signal_subscribe(None, "org.freedesktop.portal.Settings", "SettingChanged",
                                        "/org/freedesktop/portal/desktop", None, Gio.DBusSignalFlags.NONE,
                                        on_setting_changed)
    set_theme(name)
    timeout = GLib.timeout_add(PORTAL_TIMEOUT_MS, loop.quit)
    loop.run()
    if announced:
        GLib.source_remove(timeout)
    bus.signal_unsubscribe(subscription)


def set_theme(name):
    subprocess.run(["gsettings", "set", "org.gnome.desktop.interface", "gtk-theme", name], timeout=5)
