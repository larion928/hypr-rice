"""What the Firefox and Chromium themes share."""
import hashlib
import io
from pathlib import Path

from PIL import Image

from ..colors import css_rgba, mix
from ..files import write_bytes
from ..paths import HOME


def theme_emblem(theme):
    """The theme's full battery icon (Clawd, the coffee cup, the jellyfish...): the browsers show it
    as their menu button and on the new tab page."""
    icons = (theme.dir / "assets").glob("battery-*.svg")
    icons = sorted(icons, key=lambda icon: int(icon.stem.split("-")[1]))
    return icons[-1] if icons else None


def look(theme):
    """Colours, shape and fonts shared by the Firefox and Chromium themes."""
    colors = theme.colors
    ui = theme.ui
    side = mix(colors["bg"], colors["bg2"], 0.5)
    return {
        "label": theme.label, "bg": colors["bg"], "bg2": colors["bg2"], "fg": colors["fg"], "muted": colors["muted"],
        "accent": colors["accent"], "accent2": colors["accent2"], "side": side,
        "field": mix(colors["bg"], "#000000", 0.25),
        "selected": mix(side, colors["accent"], 0.16),
        "hover": css_rgba(colors["fg"], 0.08),
        "border": mix(colors["bg2"], colors["muted"], 0.3),
        "dim": css_rgba(colors["bg"], 0.72),
        "sidebar_glass": css_rgba(side, 0.82),
        "accent_soft": css_rgba(colors["accent"], 0.45),
        # Tabs and fields stay usable at the rounder themes' 18-22px.
        "radius": min(ui.get("radius", 12), 14),
        "line": ui.get("border") or 1,
        # The selection bar beside a vertical tab reads better a bit thicker than borders.
        "line_zen": (ui.get("border") or 1) + 2,
        "font": theme.body_font,
        "display": theme.display,
        "title_style": "italic" if ui.get("italicTitle") else "normal",
        "title_case": "uppercase" if ui.get("upperTitle") else "none",
        # Neon themes: selected tab and focused fields glow in the accent.
        "glow": f", 0 0 12px {css_rgba(colors['accent'], 0.55)}" if ui.get("glow") else "",
    }


# The browsers' wallpaper JPEGs. Decoding the wallpaper and encoding it again took 75-210 ms per size
# (Firefox wants two, Chromium one) on every theme change; the wallpapers are few and rarely change.
JPEG_CACHE = HOME / ".cache/hypr-rice/browser-wallpapers"


def wallpaper_jpeg(wallpaper, width, quality):
    """The wallpaper as a JPEG at most width pixels wide and tall, from JPEG_CACHE when this version of
    the file (its modification time and size) was encoded so before. A new version replaces the old one's
    entry."""
    source = Path(wallpaper)
    version = source.stat()
    entry_prefix = hashlib.sha1(f"{source}\0{width}\0{quality}".encode()).hexdigest()[:16]
    cached = JPEG_CACHE / f"{entry_prefix}-{version.st_mtime_ns}-{version.st_size}.jpg"
    if cached.exists():
        return cached.read_bytes()
    for outdated in JPEG_CACHE.glob(f"{entry_prefix}-*.jpg"):
        outdated.unlink(missing_ok=True)
    jpeg = encode_jpeg(source, width, quality)
    write_bytes(cached, jpeg)
    return jpeg


def encode_jpeg(wallpaper, width, quality):
    image = Image.open(wallpaper).convert("RGB")
    image.thumbnail((width, width))
    buffer = io.BytesIO()
    image.save(buffer, "JPEG", quality=quality)
    return buffer.getvalue()

