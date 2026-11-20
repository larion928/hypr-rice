"""What the games window shows of each game: its cover and icon as files, and whether it is still there."""
import functools
import os
import subprocess
from pathlib import Path

from . import steam_games
from .library import HOME, games


def listing():
    """The library, each game with its cover (the one picked, or Steam's), its icon as a file and
    whether it is still there."""
    out = []
    for entry in games():
        out.append({**entry, "cover": cover_of(entry), "icon": icon_file(entry.get("icon", "")),
                     "present": present(entry)})
    return sorted(out, key=lambda entry: (-entry["played"], entry["name"].lower()))


def icon_file(icon):
    """An icon name as the file of the system's icon theme (the window's own lookup knows another
    theme: osu! is only in Papirus); a path stays as it is."""
    if not icon or icon.startswith("/"):
        return icon
    try:
        theme = system_icons()
    except (ImportError, ValueError):  # no GTK for Python: the window's own lookup does
        return icon
    found = theme.lookup_icon(icon, 256, 0)
    return found.get_filename() if found else icon


@functools.cache
def system_icons():
    """The system's icon theme, made once per run: a listing asks it for every game."""
    import gi
    gi.require_version("Gtk", "3.0")
    from gi.repository import Gtk
    theme = Gtk.IconTheme.new()
    theme.set_custom_theme(system_icon_theme())
    return theme


def system_icon_theme():
    current = subprocess.run(["gsettings", "get", "org.gnome.desktop.interface", "icon-theme"],
                             capture_output=True, text=True).stdout.strip().strip("'")
    return current or "Papirus-Dark"


def cover_of(entry):
    if entry.get("cover") and Path(entry["cover"]).is_file():
        return entry["cover"]
    if entry["kind"] == "steam":
        return steam_games.cover(entry["target"])
    return ""


def present(entry):
    if entry["kind"] in ("exe", "appimage", "native"):
        return Path(entry["target"]).is_file()
    if entry["kind"] == "app":
        return desktop_file(entry["target"]) is not None
    return steam_games.library_of(entry["target"]) is not None


def desktop_file(desktop_id):
    data_home = Path(os.environ.get("XDG_DATA_HOME", HOME / ".local/share"))
    data_dirs = os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":")
    for folder in [data_home, *map(Path, data_dirs)]:
        candidate = folder / "applications" / f"{desktop_id}.desktop"
        if candidate.is_file():
            return candidate
    return None
