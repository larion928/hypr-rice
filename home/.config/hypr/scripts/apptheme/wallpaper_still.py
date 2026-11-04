"""A wallpaper as one still picture, for what cannot play an animation: the lock screen, the login
screen, the browsers' themes, Telegram's chat background, the thumbnails in the settings. An animated
wallpaper (a GIF or a video, played by ~/.local/bin/wallpaper) gives its first frame, kept next to it
in .stills/ (the login screen reads the picture from the theme's folder: the root helper takes only
wallpapers under ~/.config/hypr/themes)."""
from pathlib import Path

from . import frames
from .animated import is_animated

STILLS = ".stills"


def still(wallpaper):
    """The path of a picture showing wallpaper: wallpaper itself, or an animation's first frame."""
    path = Path(wallpaper)
    if not is_animated(path):
        return str(path)
    target = path.parent / STILLS / f"{path.stem}.png"
    if not target.exists() or target.stat().st_mtime < path.stat().st_mtime:
        target.parent.mkdir(exist_ok=True)
        frames.frame(path, 0, target)
    return str(target)
