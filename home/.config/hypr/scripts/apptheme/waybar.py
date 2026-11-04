"""waybar: config.json from the shared modules, the theme's changes, the layout the user saved in the
settings window and the machine's own; fonts.css with the user's font for the theme."""
import dataclasses
import json
import re
from pathlib import Path

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
    if isinstance(config.get("temperature"), dict):
        config["temperature"] = {**cpu_sensor(), **config["temperature"]}
    # Machine-specific bits (outputs in persistent-workspaces, ...), not part of the rice repo.
    local = RICE_CONF / "waybar/config.local.json"
    if local.exists():
        # One level deep: a module option given here replaces the shared one as a whole.
        for module, options in json.loads(local.read_text()).items():
            shared = config.get(module)
            both_tables = isinstance(options, dict) and isinstance(shared, dict)
            config[module] = {**shared, **options} if both_tables else options
    write(RICE_CONF / "waybar/config.json", json.dumps(config, indent=4, ensure_ascii=False) + "\n")


# Waybar's temperature module reads thermal_zone0 unless told otherwise, and a laptop without that zone
# (AMD ones often) silently shows no temperature at all.
THERMAL_ZONE = Path("/sys/class/thermal/thermal_zone0")
HWMON = Path("/sys/class/hwmon")
CPU_SENSORS = ("k10temp", "coretemp", "zenpower", "cpu_thermal")


def cpu_sensor():
    """Where the temperature module should read, without thermal_zone0: the CPU's own sensor, by its
    device's path since the hwmon number changes between boots. {} when the zone is there or no CPU
    sensor is."""
    if THERMAL_ZONE.exists():
        return {}
    for hwmon in sorted(HWMON.glob("hwmon*")):
        name = hwmon / "name"
        if name.exists() and name.read_text().strip() in CPU_SENSORS and (hwmon / "temp1_input").exists():
            return {"hwmon-path-abs": str(hwmon.resolve().parent), "input-filename": "temp1_input"}
    return {}


def config_for(theme):
    """config.base.json, then the theme's waybar.json, then the layout saved for every theme, then the
    one saved for this theme."""
    config = json.loads(BASE.read_text())
    over = theme.dir / "waybar.json"
    if over.exists():
        config = deep_merge(config, json.loads(over.read_text()))
    for layout in (theme.shared.get("waybar", {}), theme.edits.get("waybar", {})):
        config.update({key: value for key, value in layout.items() if key in (*SIDES, "position")})
    for module, glyph in {**theme.shared.get("icons", {}), **theme.edits.get("icons", {})}.items():
        if icon_key(module, config.get(module)) and glyph:
            config[module] = with_icon(module, config[module], glyph)
    if config.get("position") == "bottom" and "margin-top" in config:
        config["margin-bottom"] = config.pop("margin-top")
    # A layout saved for every theme may carry a module only one theme defines (claude's usage meter).
    for side in SIDES:
        if side in config:
            config[side] = [module for module in config[side] if defined(module, config)]
    return config


# Modules whose icon says something (which workspace, inhibited or not, the power profile) keep it.
ICON_SAYS_SOMETHING = ("hyprland/workspaces", "idle_inhibitor", "power-profiles-daemon")


def icon_key(module, options):
    """The format key whose icon the settings window can change: an {icon} or a glyph in front; None
    for modules without one, those whose script prints the icon, and ICON_SAYS_SOMETHING."""
    if module in ICON_SAYS_SOMETHING or not isinstance(options, dict):
        return None
    key = "format-wifi" if module == "network" else "format"
    look = options.get(key)
    if not isinstance(look, str):
        return None
    return key if "{icon}" in look or starts_with_glyph(look) else None


def starts_with_glyph(text):
    return bool(text) and ord(text[0]) >= 0xE000 and not text.startswith("{")


def with_icon(module, options, glyph):
    """options with glyph in place of the module's icon: the one {icon} stood for (every level gets
    the same then) or the glyph its format starts with."""
    key = icon_key(module, options)
    look = options[key].replace("{icon}", glyph)
    if starts_with_glyph(look):
        look = glyph + look[1:]
    return {**options, key: look}


def defined(module, config):
    return not module.startswith(("custom/", "group/")) or module in config


def layout(theme):
    """For the settings window: the bar as it is, without this theme's own layout, as the theme made it,
    and the modules that can be put on it."""
    config = config_for(theme)
    without_own = config_for(dataclasses.replace(theme, edits={}))
    themes_own = config_for(dataclasses.replace(theme, edits={}, shared={}))
    modules = sorted({key for key, value in config.items() if isinstance(value, dict) and defined(key, config)}
                     | set(BUILT_IN))
    return {"current": pick_layout(config), "withoutOwn": pick_layout(without_own),
            "themesOwn": pick_layout(themes_own), "available": modules,
            "preview": {module: preview(module, config.get(module)) for module in modules},
            # Judged on the theme's own formats: an icon already replaced must stay replaceable.
            "iconEditable": [module for module in modules
                             if icon_key(module, themes_own.get(module) or config.get(module))]}


# How a module looks on the bar in the settings window: its own "format" with sample values, or this
# for the modules that get their text from a script, have none, or are waybar's own.
SAMPLE_VALUES = {"usage": "12", "temperatureC": "48", "capacity": "58", "volume": "70", "short": "ru", "": "41",
                 "percent": "80", "percentage_used": "40"}
SAMPLE_LOOKS = {
    "hyprland/workspaces": "1 2 3 4", "hyprland/window": "Заголовок окна", "clock": "13:37",
    "network": "󰖩", "custom/battery": "󰁹 58%", "custom/power": "󰾅", "custom/updates": "󰏗 3",
    "custom/histui": "󰂚", "custom/claude": "✻ 42%", "tray": "󰀻 󰍹", "mpris": "󰎈 Песня",
}


def preview(module, options):
    if module in SAMPLE_LOOKS:
        return SAMPLE_LOOKS[module]
    look = options.get("format", "") if isinstance(options, dict) else ""
    icons = options.get("format-icons") if isinstance(options, dict) else None
    first_icon = (next(iter(icons.values()), "") if isinstance(icons, dict)
                  else icons[-1] if isinstance(icons, list) and icons else "")
    look = look.replace("{icon}", first_icon)
    return re.sub(r"\{(\w*)\}", lambda match: SAMPLE_VALUES.get(match.group(1), ""), look).strip() or module


def pick_layout(config):
    return {**{side: config.get(side, []) for side in SIDES}, "position": config.get("position", "top")}


def write_fonts(theme):
    """fonts.css, which waybar-start puts after the theme's style.css: the user's main font for the
    theme, with the Nerd Font behind it for the icons. Empty while the theme's own font is used."""
    rule = ""
    if "font" in theme.chosen_fonts:
        rule = f'* {{ font-family: "{theme.font}", "JetBrainsMono Nerd Font", sans-serif; }}\n'
    write(RICE_CONF / "waybar/fonts.css", rule)
