"""A theme's edits from the settings window written into a copy of its files, so the copy carries them
itself: a new theme made from it, a theme exported for someone else, a theme made part of the rice.
What was saved for every theme ("everywhere") stays out: it belongs to this machine, not the theme."""
import dataclasses
import json
import shutil

from . import waybar, windows
from .theme import battery_theme
from .paths import THEMES

# themegen build draws these from battery.py in the user's colours; a copy needs none.
GENERATED_FILES = ("__pycache__", "battery-*.svg")


def copy_theme(source, folder):
    """The files of the theme folder source (a link followed) in folder, without generated ones."""
    shutil.copytree(source.resolve(), folder, ignore=shutil.ignore_patterns(*GENERATED_FILES))


def bake(theme, folder):
    """Writes theme's edits into folder, a copy of theme's files."""
    write_json(folder / "palette.json", theme.palette)
    ui = dict(theme.ui)
    if theme.edits.get("iconTheme"):
        ui["iconTheme"] = theme.edits["iconTheme"]
    if ui:
        write_json(folder / "ui.json", ui)
    source = battery_theme(theme.name, theme.edits)
    if source != theme.name:
        shutil.copy(THEMES / source / "battery.py", folder / "battery.py")
    bake_wallpapers(theme, folder)
    bake_waybar(theme, folder)
    bake_windows(theme, folder)


def bake_wallpapers(theme, folder):
    """The copy keeps the wallpapers in use: its own ones switched on and the ones the user added."""
    chosen = theme.wallpapers
    for own in theme.own_wallpapers:
        if own not in chosen:
            (folder / own.name).unlink()
    for added in chosen:
        if added.parent != theme.dir:
            target = folder / added.name
            if target.exists():
                target = folder / f"added-{added.name}"
            shutil.copy(added, target)


def bake_waybar(theme, folder):
    """The layout and module icons the user saved for this theme, in the copy's waybar.json."""
    layout = theme.edits.get("waybar", {})
    icons = theme.edits.get("icons", {})
    if not layout and not icons:
        return
    over_file = folder / "waybar.json"
    over = json.loads(over_file.read_text()) if over_file.exists() else {}
    over.update({key: value for key, value in layout.items() if key in (*waybar.SIDES, "position")})
    # A module's look with the new icon depends on the shared modules too: take the finished one.
    final = waybar.config_for(dataclasses.replace(theme, shared={}))
    for module in icons:
        if module in final:
            over[module] = final[module]
    write_json(over_file, over)


def bake_windows(theme, folder):
    lines = windows.edit_lines(theme)
    if lines:
        with (folder / "hypr.lua").open("a") as hypr_lua:
            hypr_lua.write("\n-- Правки окон из настроек, вписанные в тему (последнее значение побеждает).\n")
            hypr_lua.write("\n".join(lines) + "\n")


def write_json(path, data):
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
