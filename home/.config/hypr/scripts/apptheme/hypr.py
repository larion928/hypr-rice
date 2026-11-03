"""Hyprland: the palette its config and the theme's hypr.lua read, and which theme is current."""
import json

from .colors import with_alpha
from .files import GENERATED, write
from .paths import HYPR


def apply(theme):
    colors = theme.colors
    write(HYPR / "palette.lua", f"""-- Палитра темы «{theme.name}». {GENERATED}
return {{
    active   = "{colors['accent']}",
    active2  = "{colors['accent2']}",
    inactive = "{with_alpha(colors['muted'], 0.67)}",
}}
""")
    # Read by the Quickshell screenshot overlay and anything else that wants the full palette.
    write(HYPR / "palette.json", json.dumps(theme.palette, indent=2) + "\n")
    write(HYPR / "current-theme", theme.name + "\n")

