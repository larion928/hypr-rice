"""The waybar battery icon (custom/battery): every theme draws its own in themes/<name>/battery.py,
whose frames(colors, draw) returns SVG frames: the first is the resting icon, the rest play on click.
draw is the drawing module. They are written as themes/<name>/assets/battery-<N>.svg."""
import importlib.util

from ..paths import THEMES
from ..themes.theme import battery_theme
from . import drawing


def frames(theme):
    """The theme's own drawing, or the one picked for it in the settings, in the theme's colours."""
    return drawing_of(battery_theme(theme.name, theme.edits), theme)


def drawing_of(name, theme):
    """The frames of the theme name's battery.py in the colours of theme; none without one."""
    source = THEMES / name / "battery.py"
    if not source.exists():
        return []
    spec = importlib.util.spec_from_file_location(f"battery_{name}", source)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.frames(theme.colors, drawing)


# The settings offer every theme's own drawing, whichever one the theme wears now. Not battery-*.svg: those
# are the frames the bar counts.
OWN = "own-battery.svg"


def build(themes):
    for theme in themes:
        assets = theme.dir / "assets"
        assets.mkdir(parents=True, exist_ok=True)
        for old in [*assets.glob("battery-*.svg"), assets / OWN]:
            old.unlink(missing_ok=True)
        for number, frame in enumerate(frames(theme)):
            (assets / f"battery-{number}.svg").write_text(frame)
        own = drawing_of(theme.name, theme)
        if own:
            (assets / OWN).write_text(own[0])
