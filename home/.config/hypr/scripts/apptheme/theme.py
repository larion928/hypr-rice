"""A theme as the generators see it: themes/<name>/palette.json and ui.json."""
import json
import sys
from dataclasses import dataclass, field
from pathlib import Path

from .paths import RICE_CONF, THEMES

# The fonts the user picked per theme in the settings window (Alt+F2, «Тема»); the user's own file,
# not part of the rice repo: {"claude": {"font": "Iosevka", "display": "Lora", "body": "Inter"}}.
CHOSEN_FONTS = RICE_CONF / "fonts.json"


@dataclass(frozen=True)
class Theme:
    name: str
    label: str
    font: str      # the main font; monospace in every theme
    display: str   # the titles' font
    colors: dict
    palette: dict  # palette.json as the theme wrote it
    ui: dict       # ui.json: shape and font choices; {} for a theme without one
    dir: Path
    chosen_fonts: dict = field(default_factory=dict)  # what the user changed: font, display, body
    own_fonts: dict = field(default_factory=dict)     # the theme's: font, display, body

    @property
    def code_colors(self):
        """Colours for code: palette.json may carry calmer ones under "code" (hacker does: all-green
        text is unreadable for real work)."""
        return {**self.colors, **self.palette.get("code", {})}

    @property
    def body_font(self):
        return resolve_body_font(self.ui, self.font, self.display)


def resolve_body_font(ui, font, display):
    """ui.json "bodyFont": "font" (the default), "display" or a font's own name."""
    choice = ui.get("bodyFont") or "font"
    return {"font": font, "display": display}.get(choice, choice)


def load(name):
    """The theme with the user's fonts in place of its own; palette and ui are what the panels read."""
    folder = THEMES / name
    palette = json.loads((folder / "palette.json").read_text())
    ui_file = folder / "ui.json"
    ui = json.loads(ui_file.read_text()) if ui_file.exists() else {}
    own = {"font": palette["font"], "display": palette["display"],
           "body": resolve_body_font(ui, palette["font"], palette["display"])}
    chosen = {key: value for key, value in read_chosen_fonts().get(name, {}).items() if value}
    palette = {**palette, **{key: chosen[key] for key in ("font", "display") if key in chosen}}
    if "body" in chosen:
        ui = {**ui, "bodyFont": chosen["body"]}
    return Theme(name=palette["name"], label=palette["label"], font=palette["font"], display=palette["display"],
                 colors=palette["colors"], palette=palette, ui=ui, dir=folder,
                 chosen_fonts=chosen, own_fonts=own)


def read_chosen_fonts():
    if not CHOSEN_FONTS.exists():
        return {}
    try:
        return json.loads(CHOSEN_FONTS.read_text())
    except ValueError as error:
        print(f"{CHOSEN_FONTS}: не читается ({error}), шрифты тем остаются свои", file=sys.stderr)
        return {}


def all_names():
    return sorted(p.parent.name for p in THEMES.glob("*/palette.json"))
