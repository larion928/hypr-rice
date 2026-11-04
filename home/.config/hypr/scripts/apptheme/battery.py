"""The waybar battery icon (custom/battery): every theme draws its own in themes/<name>/battery.py,
whose frames(colors, draw) returns SVG frames: the first is the resting icon, the rest play on click.
draw is the drawing module. They are written as themes/<name>/assets/battery-<N>.svg."""
import importlib.util

from . import drawing
from .paths import THEMES
from .theme import battery_theme


def frames(theme):
    """The theme's own drawing, or the one picked for it in the settings, in the theme's colours."""
    source = THEMES / battery_theme(theme.name, theme.edits) / "battery.py"
    if not source.exists():
        return []
    spec = importlib.util.spec_from_file_location(f"battery_{theme.name}", source)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.frames(theme.colors, drawing)


def build(themes):
    for theme in themes:
        assets = theme.dir / "assets"
        assets.mkdir(parents=True, exist_ok=True)
        for old in assets.glob("battery-*.svg"):
            old.unlink()
        for number, frame in enumerate(frames(theme)):
            (assets / f"battery-{number}.svg").write_text(frame)
