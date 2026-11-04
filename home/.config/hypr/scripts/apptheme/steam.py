"""Where Steam keeps things: its folder and the library folders it puts games (and Workshop items) in."""
import re
from pathlib import Path

from .paths import HOME

STEAM = HOME / ".local/share/Steam"


def libraries():
    """The library folders of libraryfolders.vdf, the default one first; only those that exist."""
    vdf = STEAM / "steamapps/libraryfolders.vdf"
    folders = [STEAM]
    if vdf.exists():
        for found in re.findall(r'^\s*"path"\s*"(.*)"\s*$', vdf.read_text(errors="replace"), re.M):
            folder = Path(found)
            if folder not in folders:
                folders.append(folder)
    return [folder for folder in folders if (folder / "steamapps").is_dir()]
