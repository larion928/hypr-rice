"""Icon themes for the settings window: the installed ones with a few of their icons to show, and the
ones the rice offers to install (checked to exist in the repos or the AUR)."""
import subprocess
from pathlib import Path

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gtk  # imported once the version above is set

from .paths import HOME

ICON_DIRS = (HOME / ".local/share/icons", HOME / ".icons", Path("/usr/share/icons"))
NOT_THEMES = ("hicolor", "default", "locolor")
PREVIEW = ("folder", "user-home", "utilities-terminal", "firefox", "accessories-text-editor", "preferences-system")
# package, what it is called, where it comes from
DOWNLOADABLE = (
    ("papirus-icon-theme", "Papirus", "repo"), ("breeze-icons", "Breeze", "repo"),
    ("adwaita-icon-theme", "Adwaita", "repo"), ("deepin-icon-theme", "Deepin", "repo"),
    ("elementary-icon-theme", "elementary", "repo"), ("tela-circle-icon-theme-git", "Tela Circle", "aur"),
    ("colloid-icon-theme-git", "Colloid", "aur"), ("qogir-icon-theme", "Qogir", "aur"),
    ("numix-circle-icon-theme-git", "Numix Circle", "aur"), ("candy-icons-git", "Candy", "aur"),
    ("whitesur-icon-theme", "WhiteSur", "aur"), ("fluent-icon-theme-git", "Fluent", "aur"),
    ("kora-icon-theme", "Kora", "aur"),
)


def listing():
    return {"installed": installed(), "downloadable": downloadable()}


def installed():
    """Icon themes with icons of their own (cursor themes have none), each once, by the name shown."""
    themes = {}
    for root in ICON_DIRS:
        for index in sorted(root.glob("*/index.theme")):
            name = index.parent.name
            fields = index_fields(index)
            if name in NOT_THEMES or name in themes or not fields.get("Directories"):
                continue
            themes[name] = {"name": name, "label": fields.get("Name", name), "previews": previews(name)}
    return sorted(themes.values(), key=lambda theme: theme["label"].lower())


def index_fields(index):
    fields = {}
    for line in index.read_text(errors="replace").splitlines():
        if line.startswith("[") and fields:
            break  # only the [Icon Theme] section
        key, _, value = line.partition("=")
        if value:
            fields[key.strip()] = value.strip()
    return fields


def previews(name):
    """Paths of PREVIEW's icons as the theme draws them (falling back the way programs do)."""
    theme = Gtk.IconTheme.new()
    theme.set_custom_theme(name)
    found = (theme.lookup_icon(icon, 48, 0) for icon in PREVIEW)
    return [info.get_filename() for info in found if info]


def downloadable():
    packages = [package for package, _, _ in DOWNLOADABLE]
    present = subprocess.run(["pacman", "-Q", *packages], capture_output=True, text=True).stdout
    have = {line.split()[0] for line in present.splitlines()}
    return [{"package": package, "title": title, "source": source, "installed": package in have}
            for package, title, source in DOWNLOADABLE]
