"""waybar: config.json from the shared modules, the theme's changes, the layout the user saved in the
settings window and the machine's own; fonts.css with the user's font for the theme."""
import dataclasses
import json

from .files import write
from .paths import RICE_CONF

BASE = RICE_CONF / "waybar/config.base.json"
SIDES = ("modules-left", "modules-center", "modules-right")
# Waybar's own modules that work without any settings, offered in the settings window besides the ones
# config.base.json and the theme define.
BUILT_IN = ("tray", "backlight", "bluetooth", "idle_inhibitor", "mpris", "disk", "power-profiles-daemon")


def deep_merge(base, over):
    out = dict(base)
    for key, value in over.items():
        out[key] = deep_merge(out[key], value) if isinstance(value, dict) and isinstance(out.get(key), dict) else value
    return out


def apply(theme):
    write_config(theme)
    write_fonts(theme)


def write_config(theme):
    if not BASE.exists():
        return
    config = config_for(theme)
    # Machine-specific bits (outputs in persistent-workspaces, ...), not part of the rice repo.
    local = RICE_CONF / "waybar/config.local.json"
    if local.exists():
        # One level deep: a module option given here replaces the shared one as a whole.
        for module, options in json.loads(local.read_text()).items():
            shared = config.get(module)
            both_tables = isinstance(options, dict) and isinstance(shared, dict)
            config[module] = {**shared, **options} if both_tables else options
    write(RICE_CONF / "waybar/config.json", json.dumps(config, indent=4, ensure_ascii=False) + "\n")


def config_for(theme):
    """config.base.json, then the theme's waybar.json, then the layout saved for every theme, then the
    one saved for this theme."""
    config = json.loads(BASE.read_text())
    over = theme.dir / "waybar.json"
    if over.exists():
        config = deep_merge(config, json.loads(over.read_text()))
    for layout in (theme.shared.get("waybar", {}), theme.edits.get("waybar", {})):
        config.update({key: value for key, value in layout.items() if key in (*SIDES, "position")})
    if config.get("position") == "bottom" and "margin-top" in config:
        config["margin-bottom"] = config.pop("margin-top")
    # A layout saved for every theme may carry a module only one theme defines (claude's usage meter).
    for side in SIDES:
        if side in config:
            config[side] = [module for module in config[side] if defined(module, config)]
    return config


def defined(module, config):
    return not module.startswith(("custom/", "group/")) or module in config


def layout(theme):
    """For the settings window: the bar as it is, without this theme's own layout, as the theme made it,
    and the modules that can be put on it."""
    config = config_for(theme)
    without_own = config_for(dataclasses.replace(theme, edits={}))
    themes_own = config_for(dataclasses.replace(theme, edits={}, shared={}))
    modules = [key for key, value in config.items() if isinstance(value, dict) and defined(key, config)]
    return {"current": pick_layout(config), "withoutOwn": pick_layout(without_own),
            "themesOwn": pick_layout(themes_own), "available": sorted(set(modules) | set(BUILT_IN))}


def pick_layout(config):
    return {**{side: config.get(side, []) for side in SIDES}, "position": config.get("position", "top")}


def write_fonts(theme):
    """fonts.css, which waybar-start puts after the theme's style.css: the user's main font for the
    theme, with the Nerd Font behind it for the icons. Empty while the theme's own font is used."""
    rule = ""
    if "font" in theme.chosen_fonts:
        rule = f'* {{ font-family: "{theme.font}", "JetBrainsMono Nerd Font", sans-serif; }}\n'
    write(RICE_CONF / "waybar/fonts.css", rule)
