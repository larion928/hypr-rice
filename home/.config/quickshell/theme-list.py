#!/usr/bin/env python3
"""theme-list.py OUT — write every theme to OUT as JSON for the theme picker and the settings
window: name, folder, palette.json, ui.json, a wallpaper thumbnail and whether it is current.
Thumbnails are cached in ~/.cache/theme-thumbs and rebuilt only when the wallpaper is newer."""
import json
import sys
from pathlib import Path

from PIL import Image

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


def read_json(path):
    return json.loads(path.read_text()) if path.exists() else {}


def main():
    THUMBS.mkdir(parents=True, exist_ok=True)
    current_file = HYPR / "current-theme"
    current = current_file.read_text().strip() if current_file.exists() else ""
    themes = []
    for theme_dir in sorted(p for p in (HYPR / "themes").iterdir() if (p / "palette.json").exists()):
        themes.append({"name": theme_dir.name, "dir": str(theme_dir), "thumb": thumbnail(theme_dir),
                       "current": theme_dir.name == current,
                       "pal": read_json(theme_dir / "palette.json"), "ui": read_json(theme_dir / "ui.json")})
    Path(sys.argv[1]).write_text(json.dumps(themes, ensure_ascii=False))


main()
