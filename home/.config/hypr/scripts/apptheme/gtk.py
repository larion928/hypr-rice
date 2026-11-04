"""GTK 3 and 4 apps: the palette over the Graphite-Dark base theme."""
import subprocess
import time
from pathlib import Path

from .colors import css_rgba, mix
from .files import GENERATED, write
from .paths import HOME

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
    head = f"/* Тема «{theme.name}» поверх Graphite-Dark. {GENERATED} */\n"
    write(HOME / ".config/gtk-3.0/gtk.css", head + gtk3_defines + rules)
    gtk4_base = "/usr/share/themes/Graphite-Dark/gtk-4.0"
    for file_name in ("gtk.css", "gtk-dark.css"):
        write(HOME / ".config/gtk-4.0" / file_name,
              head + f'@import url("file://{gtk4_base}/{file_name}");\n' + gtk4_defines + rules)


def base_theme():
    """The GTK theme gtk.css is written over; the rice installer falls back to Adwaita-dark the same way."""
    return "Graphite-Dark" if Path("/usr/share/themes/Graphite-Dark").is_dir() else "Adwaita-dark"


def reload():
    # GTK3 only rereads the user gtk.css when the theme name changes, so bounce it. It lands on the
    # base theme, not on the name found in the setting: once the setting held another theme (the
    # stand-in, after a bounce cut short), every later bounce restored that one.
    try:
        base = base_theme()
        # A dark stand-in: bouncing through light Adwaita left white toolbars in open windows.
        bounce = "Adwaita-dark" if base != "Adwaita-dark" else "Adwaita"
        subprocess.run(["gsettings", "set", "org.gnome.desktop.interface", "gtk-theme", bounce], timeout=5)
        time.sleep(0.3)
        subprocess.run(["gsettings", "set", "org.gnome.desktop.interface", "gtk-theme", base], timeout=5)
        # File chooser dialogs (Code - OSS, browsers, ...) come from this portal; it does not
        # follow the bounce above, so restart it. It is D-Bus activated, nothing is lost.
        subprocess.run(["systemctl", "--user", "try-restart", "xdg-desktop-portal-gtk.service"], timeout=10)
    except (OSError, subprocess.SubprocessError):
        pass
