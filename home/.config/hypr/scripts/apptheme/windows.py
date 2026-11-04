"""Hyprland windows: the gaps, border, rounding, blur, opacity and animation speed the user set for the
theme in the settings window, as ~/.config/hypr/theme-edits.lua, which hyprland.lua loads right after
the theme's own hypr.lua. Without edits the file only says so, and the theme is as it made itself."""
import re

from .files import GENERATED, write
from .paths import HYPR

EDITS_LUA = HYPR / "theme-edits.lua"
# Hyprland's own defaults, for what a theme's hypr.lua does not set.
DEFAULTS = {"gaps_in": 5, "gaps_out": 20, "border_size": 1, "rounding": 0, "blur": True, "blur_size": 8,
            "active_opacity": 1.0, "inactive_opacity": 1.0}
# Animation speed is a duration in Hyprland: a bigger number is a slower animation.
SPEED_FACTORS = {"fast": 0.6, "slow": 1.6}
ANIMATION = re.compile(r"^hl\.animation\(\{.*\}\)$", re.M)


def own(theme):
    """What the theme's hypr.lua sets (or Hyprland's default), for «как в теме» in the window."""
    source = (theme.dir / "hypr.lua").read_text()
    values = dict(DEFAULTS)
    for key in ("gaps_in", "gaps_out", "border_size", "rounding"):
        found = re.search(rf"\b{key}\s*=\s*(\d+)", source)
        if found:
            values[key] = int(found.group(1))
    blur = re.search(r"blur\s*=\s*\{([^}]*)\}", source)
    if blur:
        values["blur"] = "enabled = false" not in blur.group(1)
        size = re.search(r"\bsize\s*=\s*(\d+)", blur.group(1))
        if size:
            values["blur_size"] = int(size.group(1))
    for key in ("active_opacity", "inactive_opacity"):
        found = re.search(rf"\b{key}\s*=\s*([\d.]+)", source)
        if found:
            values[key] = float(found.group(1))
    return values


def apply(theme):
    edits = theme.edits.get("windows", {})
    lines = [f"-- Правки окон темы «{theme.name}» из настроек (Alt+F2 → Тема → Окна). {GENERATED}"]
    general = {key: edits[key] for key in ("gaps_in", "gaps_out", "border_size") if key in edits}
    decoration = {key: edits[key] for key in ("rounding", "active_opacity", "inactive_opacity") if key in edits}
    blur = {}
    if "blur" in edits:
        blur["enabled"] = bool(edits["blur"])
    if "blur_size" in edits:
        blur["size"] = edits["blur_size"]
    if blur:
        decoration["blur"] = blur
    if general or decoration:
        sections = {name: values for name, values in (("general", general), ("decoration", decoration)) if values}
        lines.append(f"hl.config({lua_table(sections)})")
    animations = edits.get("animations")
    if animations == "off":
        lines.append("hl.config({ animations = { enabled = false } })")
    elif animations in SPEED_FACTORS:
        lines += scaled_animations(theme, SPEED_FACTORS[animations])
    write(EDITS_LUA, "\n".join(lines) + "\n")


def scaled_animations(theme, factor):
    """The theme's own hl.animation lines with every speed multiplied by factor."""
    source = (theme.dir / "hypr.lua").read_text()
    return [re.sub(r"(speed\s*=\s*)([\d.]+)", lambda match: f"{match.group(1)}{round(float(match.group(2)) * factor, 2)}", line)
            for line in ANIMATION.findall(source)]


def lua_table(value):
    if isinstance(value, dict):
        return "{ " + ", ".join(f"{key} = {lua_table(item)}" for key, item in value.items()) + " }"
    if isinstance(value, bool):
        return "true" if value else "false"
    return str(value)
