#!/usr/bin/env python3
"""theme-list.py OUT — write every theme to OUT as JSON for the theme picker and the settings
window: name, folder, palette.json and ui.json (with the fonts the user picked for it), the fonts
picked, a wallpaper thumbnail and whether it is current. Thumbnails are cached in
~/.cache/theme-thumbs and rebuilt only when the wallpaper is newer."""
import json
import sys
from pathlib import Path

from PIL import Image

# themegen's loader, so each theme comes with the fonts the user picked for it.
sys.path.insert(0, str(Path.home() / ".config/hypr/scripts"))
from apptheme.theme import all_names, load

HYPR = Path.home() / ".config/hypr"
THUMBS = Path.home() / ".cache/theme-thumbs"
WALLPAPER_SUFFIXES = (".png", ".jpg", ".jpeg", ".webp")


def thumbnail(theme_dir):
    walls = sorted(p for p in theme_dir.iterdir() if p.suffix.lower() in WALLPAPER_SUFFIXES)
    if not walls:
        return ""
    thumb = THUMBS / f"{theme_dir.name}.jpg"
    if not thumb.exists() or thumb.stat().st_mtime < walls[0].stat().st_mtime:
        image = Image.open(walls[0]).convert("RGB")
        image.thumbnail((640, 360))
        image.save(thumb, quality=88)
    return str(thumb)


def main():
    THUMBS.mkdir(parents=True, exist_ok=True)
    current_file = HYPR / "current-theme"
    current = current_file.read_text().strip() if current_file.exists() else ""
    themes = []
    for theme in map(load, all_names()):
        themes.append({"name": theme.name, "dir": str(theme.dir), "thumb": thumbnail(theme.dir),
                       "current": theme.name == current, "pal": theme.palette, "ui": theme.ui,
                       "chosenFonts": theme.chosen_fonts, "ownFonts": theme.own_fonts})
    Path(sys.argv[1]).write_text(json.dumps(themes, ensure_ascii=False))


main()
