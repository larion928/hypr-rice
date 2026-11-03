"""What the Firefox and Chromium themes share."""
import io

from PIL import Image

from .colors import css_rgba, mix


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


def wallpaper_jpeg(wallpaper, width, quality):
    image = Image.open(wallpaper).convert("RGB")
    image.thumbnail((width, width))
    buffer = io.BytesIO()
    image.save(buffer, "JPEG", quality=quality)
    return buffer.getvalue()

