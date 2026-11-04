"""The icon theme picked for a theme in the settings window, for GTK programs (gsettings and the
settings.ini of GTK 3 and 4). Without one the rice's own stays; a theme left with one of its own puts
that back, which is why the last one set is remembered."""
import re
import subprocess

from .paths import HOME

DEFAULT = "Papirus-Dark"  # what the rice's gtk-3.0/settings.ini ships
SET_BY_RICE = HOME / ".cache/hypr-rice/icon-theme"
SETTINGS_FILES = (HOME / ".config/gtk-3.0/settings.ini", HOME / ".config/gtk-4.0/settings.ini")


def current(theme):
    return chosen(theme) or DEFAULT


def chosen(theme):
    """Picked in the settings, or written into the theme's ui.json (a theme made in the settings)."""
    return theme.edits.get("iconTheme") or theme.ui.get("iconTheme")


def apply(theme):
    wanted = chosen(theme)
    if wanted:
        set_icon_theme(wanted)
        SET_BY_RICE.parent.mkdir(parents=True, exist_ok=True)
        SET_BY_RICE.write_text(wanted + "\n")
    elif SET_BY_RICE.exists():
        set_icon_theme(DEFAULT)
        SET_BY_RICE.unlink()


def set_icon_theme(name):
    subprocess.run(["gsettings", "set", "org.gnome.desktop.interface", "icon-theme", name], check=False)
    for settings in SETTINGS_FILES:
        if settings.exists():
            text = re.sub(r"^gtk-icon-theme-name=.*$", f"gtk-icon-theme-name={name}", settings.read_text(), flags=re.M)
            settings.write_text(text)
