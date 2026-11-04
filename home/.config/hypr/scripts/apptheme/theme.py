"""A theme as the generators see it: themes/<name>/palette.json and ui.json, with the user's edits
from the settings window on top."""
import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

from .paths import RICE_CONF, THEMES

# What the user changed per theme in the settings window (Alt+F2, «Тема»); the user's own file, not
# part of the rice repo, so updates leave it alone:
#   {"themes": {"coffee": {"fonts": {"font": "Iosevka", "display": "", "body": "Inter"},
#                          "colors": {"accent": "#e0a050"},
#                          "wallpapers": {"added": ["/home/me/Pictures/a.png"], "off": ["…/02.png"]},
#                          "waybar": {"modules-left": […], "modules-center": […], "modules-right": […],
#                                     "position": "bottom"},
#                          "icons": {"cpu": "󰻠"}, "battery": "night", "folders": "teal",
#                          "iconTheme": "breeze-dark"}},
#    "everywhere": {"waybar": {…}}}
# "everywhere" holds what was saved for all themes; a theme's own edit wins over it. An empty font or
# a missing key keeps the theme's own.
EDITS = RICE_CONF / "theme-edits.json"
WALLPAPER_SUFFIXES = (".png", ".jpg", ".jpeg", ".webp")
COLOR = re.compile(r"#[0-9a-fA-F]{6}")
BATTERY_ANIMATION = ("batteryAnim", "batteryStep")  # ui.json keys that go with a battery drawing


@dataclass(frozen=True)
class Theme:
    name: str
    label: str
    font: str      # the main font; monospace in every theme
    display: str   # the titles' font
    colors: dict
    palette: dict  # palette.json with the user's fonts and colors in place
    ui: dict       # ui.json: shape and font choices, with the user's text font; {} without one
    dir: Path
    edits: dict = field(default_factory=dict)   # this theme's part of EDITS
    shared: dict = field(default_factory=dict)  # EDITS "everywhere"
    own: dict = field(default_factory=dict)    # the theme's own fonts and colors, before the edits

    @property
    def code_colors(self):
        """Colours for code: palette.json may carry calmer ones under "code" (hacker does: all-green
        text is unreadable for real work)."""
        return {**self.colors, **self.palette.get("code", {})}

    @property
    def body_font(self):
        return resolve_body_font(self.ui, self.font, self.display)

    @property
    def chosen_fonts(self):
        return {key: value for key, value in self.edits.get("fonts", {}).items() if value}

    @property
    def own_wallpapers(self):
        return sorted(p for p in self.dir.iterdir() if p.suffix.lower() in WALLPAPER_SUFFIXES)

    @property
    def wallpapers(self):
        """What changetheme picks from: the theme's own and the user's added ones, minus those switched
        off; all of the theme's own if that leaves nothing."""
        settings = self.edits.get("wallpapers", {})
        added = [Path(path) for path in settings.get("added", []) if Path(path).is_file()]
        off = set(settings.get("off", []))
        usable = [path for path in self.own_wallpapers + added if str(path) not in off]
        return usable or self.own_wallpapers


def resolve_body_font(ui, font, display):
    """ui.json "bodyFont": "font" (the default), "display" or a font's own name."""
    choice = ui.get("bodyFont") or "font"
    return {"font": font, "display": display}.get(choice, choice)


def load(name):
    folder = THEMES / name
    palette = json.loads((folder / "palette.json").read_text())
    ui = read_ui(folder)
    own = {"fonts": {"font": palette["font"], "display": palette["display"],
                     "body": resolve_body_font(ui, palette["font"], palette["display"])},
           "colors": palette["colors"], "folders": ui.get("folders", "")}
    every_edit = read_edits()
    edits = every_edit.get("themes", {}).get(name, {})
    fonts = {key: value for key, value in edits.get("fonts", {}).items() if value}
    colors = {key: value for key, value in edits.get("colors", {}).items()
              if key in palette["colors"] and COLOR.fullmatch(str(value))}
    palette = {**palette, **{key: fonts[key] for key in ("font", "display") if key in fonts},
               "colors": {**palette["colors"], **colors}}
    if "body" in fonts:
        ui = {**ui, "bodyFont": fonts["body"]}
    if edits.get("folders"):
        ui = {**ui, "folders": edits["folders"]}
    battery_source = battery_theme(name, edits)
    if battery_source != name:
        # The drawing comes with its own animation (the moon wanes back, the jellyfish relaxes).
        source_ui = read_ui(THEMES / battery_source)
        ui = {**{key: value for key, value in ui.items() if key not in BATTERY_ANIMATION},
              **{key: source_ui[key] for key in BATTERY_ANIMATION if key in source_ui}}
    return Theme(name=palette["name"], label=palette["label"], font=palette["font"], display=palette["display"],
                 colors=palette["colors"], palette=palette, ui=ui, dir=folder, edits=edits,
                 shared=every_edit.get("everywhere", {}), own=own)


def read_ui(folder):
    ui_file = folder / "ui.json"
    return json.loads(ui_file.read_text()) if ui_file.exists() else {}


def battery_theme(name, edits):
    """The theme whose battery drawing this one uses: its own, or the one picked in the settings."""
    source = edits.get("battery")
    return source if source and (THEMES / source / "battery.py").exists() else name


def read_edits():
    """The whole EDITS file; {} without it or with a broken one."""
    if not EDITS.exists():
        return {}
    try:
        edits = json.loads(EDITS.read_text())
        if not isinstance(edits, dict):
            raise ValueError("not a JSON object")
        return edits
    except ValueError as error:
        print(f"{EDITS}: не читается ({error}), темы остаются без правок", file=sys.stderr)
        return {}


def forget_edits(name):
    """Drops what the settings window saved for the theme name (deleted, or its edits written in)."""
    every_edit = read_edits()
    if every_edit.get("themes", {}).pop(name, None) is not None:
        EDITS.write_text(json.dumps(every_edit, indent=2, ensure_ascii=False) + "\n")


def all_names():
    return sorted(p.parent.name for p in THEMES.glob("*/palette.json"))
