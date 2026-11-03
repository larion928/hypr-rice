"""A theme as the generators see it: themes/<name>/palette.json and ui.json."""
import json
from dataclasses import dataclass
from pathlib import Path

from .paths import THEMES


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

    @property
    def code_colors(self):
        """Colours for code: palette.json may carry calmer ones under "code" (hacker does: all-green
        text is unreadable for real work)."""
        return {**self.colors, **self.palette.get("code", {})}

    @property
    def body_font(self):
        """ui.json "bodyFont": "font" (the default), "display" or a font's own name."""
        choice = self.ui.get("bodyFont") or "font"
        return {"font": self.font, "display": self.display}.get(choice, choice)


def load(name):
    folder = THEMES / name
    palette = json.loads((folder / "palette.json").read_text())
    ui_file = folder / "ui.json"
    ui = json.loads(ui_file.read_text()) if ui_file.exists() else {}
    return Theme(name=palette["name"], label=palette["label"], font=palette["font"], display=palette["display"],
                 colors=palette["colors"], palette=palette, ui=ui, dir=folder)


def all_names():
    return sorted(p.parent.name for p in THEMES.glob("*/palette.json"))
