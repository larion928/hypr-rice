"""A wallpaper as one still picture, for what cannot play an animation: the lock screen, the login
screen, the browsers' themes. awww plays an animated GIF on the desktop; the others get its first
frame, kept next to it in .stills/ (the login screen reads the picture from the theme's folder:
the root helper takes only wallpapers under ~/.config/hypr/themes)."""
from pathlib import Path

from PIL import Image

ANIMATED_SUFFIXES = (".gif",)
STILLS = ".stills"


def still(wallpaper):
    """The path of a picture showing wallpaper: wallpaper itself, or an animation's first frame."""
    path = Path(wallpaper)
    if path.suffix.lower() not in ANIMATED_SUFFIXES:
        return str(path)
    target = path.parent / STILLS / f"{path.stem}.png"
    if not target.exists() or target.stat().st_mtime < path.stat().st_mtime:
        target.parent.mkdir(exist_ok=True)
        Image.open(path).convert("RGB").save(target)  # a GIF opens on its first frame
    return str(target)
