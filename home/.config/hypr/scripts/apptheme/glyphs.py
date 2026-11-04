"""Every icon of the Nerd Font, with its name (md-memory, fa-power_off, ...), for the icon picker in the
settings window. Read from the font file itself, so it is whatever the installed font has."""
import subprocess

from fontTools.ttLib import TTFont

FONT = "JetBrainsMono Nerd Font"


def all_icons():
    """[[glyph, name], ...] for the font's private-use code points, where the Nerd Font icons live."""
    path = subprocess.run(["fc-match", "-f", "%{file}", FONT], capture_output=True, text=True).stdout.strip()
    cmap = TTFont(path, lazy=True).getBestCmap()
    return [[chr(code), name] for code, name in sorted(cmap.items()) if 0xE000 <= code <= 0xF8FF or code >= 0xF0000]
