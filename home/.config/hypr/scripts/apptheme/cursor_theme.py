"""The cursor picked for a theme in the settings window (or written into its ui.json), wherever a
cursor is read: Hyprland now (hyprctl setcursor) and at its next start (~/.config/hypr/cursor.lua,
which hyprland.lua loads), GTK programs (gsettings, settings.ini) and X11 ones (~/.icons/default).
Without a pick the rice's own, WhiteCat."""
import re
import subprocess

from .files import GENERATED, write
from .icon_theme import SETTINGS_FILES
from .paths import HOME, HYPR

DEFAULT = "WhiteCat"
DEFAULT_SIZE = 24
CURSOR_LUA = HYPR / "cursor.lua"


def chosen(theme):
    return theme.edits.get("cursor") or theme.ui.get("cursor") or DEFAULT


def size(theme):
    return int(theme.edits.get("cursorSize") or theme.ui.get("cursorSize") or DEFAULT_SIZE)


def apply(theme):
    name, pixels = chosen(theme), size(theme)
    write(CURSOR_LUA, "\n".join([
        f"-- Курсор темы «{theme.name}» (Alt+F2 → Тема → Курсор). {GENERATED}",
        *(f'hl.env("{variable}", "{value}")' for variable, value in (
            ("XCURSOR_THEME", name), ("XCURSOR_SIZE", pixels), ("HYPRCURSOR_THEME", name), ("HYPRCURSOR_SIZE", pixels))),
    ]) + "\n")
    subprocess.run(["hyprctl", "setcursor", name, str(pixels)], capture_output=True, check=False)
    subprocess.run(["gsettings", "set", "org.gnome.desktop.interface", "cursor-theme", name], check=False)
    subprocess.run(["gsettings", "set", "org.gnome.desktop.interface", "cursor-size", str(pixels)], check=False)
    for settings in SETTINGS_FILES:
        if settings.exists():
            text = re.sub(r"^gtk-cursor-theme-name=.*$", f"gtk-cursor-theme-name={name}", settings.read_text(), flags=re.M)
            text = re.sub(r"^gtk-cursor-theme-size=.*$", f"gtk-cursor-theme-size={pixels}", text, flags=re.M)
            settings.write_text(text)
    # X11 programs that read no setting take the cursor of the "default" theme.
    write(HOME / ".icons/default/index.theme", f"[Icon Theme]\nName=Default\nInherits={name}\n")
