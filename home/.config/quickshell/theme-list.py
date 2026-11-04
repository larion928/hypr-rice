#!/usr/bin/env python3
"""theme-list.py OUT — write every theme to OUT as JSON for the theme picker and the settings
window: name, folder, palette.json and ui.json with the user's edits in place, the edits themselves
and the theme's own fonts and colours, its wallpapers, its waybar layout, a thumbnail, whether it is
current and whether it is one of the user's own (~/.config/hypr-rice/themes).
Thumbnails are cached in ~/.cache/theme-thumbs and rebuilt only when the wallpaper is newer."""
import hashlib
import json
import sys
from pathlib import Path

from PIL import Image

# themegen's loader, so each theme comes with the user's edits.
sys.path.insert(0, str(Path.home() / ".config/hypr/scripts"))
from apptheme import waybar, windows
from apptheme.theme import all_names, load
from apptheme.user_themes import is_user_theme

HYPR = Path.home() / ".config/hypr"
THUMBS = Path.home() / ".cache/theme-thumbs"


def thumbnail(wallpaper):
    """A small copy of the wallpaper for the cards, cached under a name made from its path."""
    thumb = THUMBS / (hashlib.sha1(str(wallpaper).encode()).hexdigest()[:16] + ".jpg")
    if not thumb.exists() or thumb.stat().st_mtime < wallpaper.stat().st_mtime:
        image = Image.open(wallpaper).convert("RGB")
        image.thumbnail((640, 360))
        image.save(thumb, quality=88)
    return str(thumb)


def main():
    THUMBS.mkdir(parents=True, exist_ok=True)
    current_file = HYPR / "current-theme"
    current = current_file.read_text().strip() if current_file.exists() else ""
    themes = []
    for theme in map(load, all_names()):
        added = [Path(path) for path in theme.edits.get("wallpapers", {}).get("added", []) if Path(path).is_file()]
        themes.append({"name": theme.name, "dir": str(theme.dir), "current": theme.name == current,
                       "user": is_user_theme(theme.name),
                       "thumb": thumbnail(theme.wallpapers[0]) if theme.wallpapers else "",
                       "pal": theme.palette, "ui": theme.ui, "edits": theme.edits, "own": theme.own,
                       "wallpapers": [{"path": str(path), "thumb": thumbnail(path), "added": path in added,
                                       "on": path in theme.wallpapers}
                                      for path in theme.own_wallpapers + added],
                       "waybar": waybar.layout(theme), "windows": windows.own(theme)})
    Path(sys.argv[1]).write_text(json.dumps(themes, ensure_ascii=False))


main()
