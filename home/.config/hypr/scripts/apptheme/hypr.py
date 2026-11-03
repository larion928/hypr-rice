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
    # The current theme as the panels read it, with the user's fonts in place (the theme folder has its own).
    write(HYPR / "palette.json", json.dumps(theme.palette, indent=2) + "\n")
    write(HYPR / "ui.json", json.dumps(theme.ui, indent=2, ensure_ascii=False) + "\n")
    write(HYPR / "current-theme", theme.name + "\n")

