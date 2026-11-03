"""Where the rice keeps its files."""
from pathlib import Path

HOME = Path.home()
HYPR = HOME / ".config/hypr"
THEMES = HYPR / "themes"
# Configs of programs another desktop may share (waybar, kitty) live here instead of ~/.config/<app>.
RICE_CONF = HOME / ".config/hypr-rice"
