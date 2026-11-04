"""Cursor themes for the settings window: the installed ones with a few of their cursors drawn as
pictures, and the ones the rice offers to install (checked to exist in the repos or the AUR)."""
import struct
import subprocess
from pathlib import Path

from PIL import Image

from .icon_themes import ICON_DIRS, index_fields
from .paths import HOME

PREVIEWS = HOME / ".cache/hypr-rice/cursor-previews"
# The cursors shown for a theme, each under the names themes use for it.
SAMPLES = (("left_ptr", "default", "arrow"), ("pointer", "hand2", "hand1"), ("text", "xterm"), ("wait", "watch"))
# package, what it is called, where it comes from
DOWNLOADABLE = (
    ("capitaine-cursors", "Capitaine", "repo"), ("xcursor-vanilla-dmz", "Vanilla DMZ", "repo"),
    ("breeze-cursors", "Breeze", "repo"), ("adwaita-cursors", "Adwaita", "repo"),
    ("bibata-cursor-theme-bin", "Bibata", "aur"), ("phinger-cursors", "Phinger", "aur"),
    ("catppuccin-cursors-mocha", "Catppuccin Mocha", "aur"), ("whitesur-cursor-theme-git", "WhiteSur", "aur"),
    ("rose-pine-cursor", "Rosé Pine", "aur"), ("volantes-cursors", "Volantes", "aur"),
    ("nordzy-cursors", "Nordzy", "aur"), ("layan-cursor-theme-git", "Layan", "aur"),
)


def listing():
    return {"installed": installed(), "downloadable": downloadable()}


def installed():
    """Themes with a cursors folder, each once, by the name shown."""
    themes = {}
    for root in ICON_DIRS:
        for cursors in sorted(root.glob("*/cursors")):
            name = cursors.parent.name
            if name in themes or name == "default":
                continue
            index = cursors.parent / "index.theme"
            label = index_fields(index).get("Name", name) if index.exists() else name
            themes[name] = {"name": name, "label": label, "previews": previews(cursors)}
    return sorted(themes.values(), key=lambda theme: theme["label"].lower())


def previews(cursors):
    """PNG pictures of SAMPLES as the theme draws them, made once and kept in PREVIEWS."""
    out = []
    for names in SAMPLES:
        source = next((cursors / name for name in names if (cursors / name).is_file()), None)
        if source is None:
            continue
        picture = PREVIEWS / cursors.parent.name / f"{names[0]}.png"
        if not picture.exists() or picture.stat().st_mtime < source.stat().st_mtime:
            image = xcursor_image(source.read_bytes())
            if image is None:
                continue
            picture.parent.mkdir(parents=True, exist_ok=True)
            image.save(picture)
        out.append(str(picture))
    return out


XCURSOR_IMAGE = 0xFFFD0002
PREVIEW_SIZE = 48


def xcursor_image(data):
    """The first picture of an Xcursor file at the size nearest PREVIEW_SIZE; None if it is not one.
    The file: "Xcur", header size, version, entry count, then entries (type, nominal size, offset);
    a picture is a chunk of 9 words (header size, type, size, version, width, height, hotspot x and y,
    delay) followed by width × height premultiplied ARGB pixels."""
    if data[:4] != b"Xcur":
        return None
    count = struct.unpack_from("<I", data, 12)[0]
    entries = [struct.unpack_from("<III", data, 16 + 12 * index) for index in range(count)]
    pictures = [(size, offset) for kind, size, offset in entries if kind == XCURSOR_IMAGE]
    if not pictures:
        return None
    _, offset = min(pictures, key=lambda picture: abs(picture[0] - PREVIEW_SIZE))
    width, height = struct.unpack_from("<II", data, offset + 16)
    pixels = data[offset + 36:offset + 36 + width * height * 4]
    return Image.frombytes("RGBA", (width, height), unpremultiplied(pixels))


def unpremultiplied(pixels):
    """Little-endian premultiplied ARGB words as straight RGBA bytes."""
    out = bytearray(len(pixels))
    for start in range(0, len(pixels), 4):
        blue, green, red, alpha = pixels[start:start + 4]
        if alpha:
            red, green, blue = (min(255, channel * 255 // alpha) for channel in (red, green, blue))
        out[start:start + 4] = bytes((red, green, blue, alpha))
    return bytes(out)


def downloadable():
    packages = [package for package, _, _ in DOWNLOADABLE]
    present = subprocess.run(["pacman", "-Q", *packages], capture_output=True, text=True).stdout
    have = {line.split()[0] for line in present.splitlines()}
    return [{"package": package, "title": title, "source": source, "installed": package in have}
            for package, title, source in DOWNLOADABLE]
