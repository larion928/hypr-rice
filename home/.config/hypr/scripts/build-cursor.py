#!/usr/bin/env python3
"""Build a cursor theme (XCursor + hyprcursor) from an osu! skin's cursor.

  build-cursor.py SKIN.osk [--name WhiteCat] [--ring "#ffff00"] [--out ~/.local/share/icons]

The arrow cursor is the skin's cursor@2x.png; the other shapes (text, resize, wait, ...)
are drawn in the same white-core / coloured-glow style so they match it.
"""
import argparse
import io
import math
import shutil
import struct
import subprocess
import tempfile
import zipfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

CANVAS = 256  # every shape is drawn at this size, then scaled down
SIZES = [24, 32, 48, 64, 96]
WAIT_FRAMES = 12
WAIT_DELAY_MS = 60


def hex_rgb(c):
    c = c.lstrip("#")
    return tuple(int(c[i:i + 2], 16) for i in (0, 2, 4))


# ---------- shapes ----------

def skin_cursor(osk):
    with zipfile.ZipFile(osk) as z:
        name = next((n for n in ("cursor@2x.png", "cursor.png") if n in z.namelist()), None)
        if not name:
            raise SystemExit("no cursor.png in the skin")
        im = Image.open(io.BytesIO(z.read(name))).convert("RGBA")
    im = im.crop(im.getbbox())
    side = max(im.size)
    sq = Image.new("RGBA", (side, side))
    sq.paste(im, ((side - im.width) // 2, (side - im.height) // 2))
    return sq.resize((CANVAS, CANVAS), Image.LANCZOS)


def recolor_ring(base, ring):
    """Swap the skin's ring/glow colour for `ring`, keep the white core."""
    r, g, b = hex_rgb(ring)
    out = Image.new("RGBA", base.size)
    src = base.load()
    dst = out.load()
    for y in range(base.height):
        for x in range(base.width):
            pr, pg, pb, pa = src[x, y]
            white = min(pr, pg, pb) / 255  # how much of the pixel is the white core
            dst[x, y] = (round(r + (255 - r) * white), round(g + (255 - g) * white),
                         round(b + (255 - b) * white), pa)
    return out


def glow_stroke(draw_fn, ring, core_w=10, ring_w=26, blur=14):
    """Draw a shape with draw_fn(draw, width, fill) as white core + coloured outline + glow."""
    layer_ring = Image.new("RGBA", (CANVAS, CANVAS))
    draw_fn(ImageDraw.Draw(layer_ring), ring_w, ring + (255,))
    glow = layer_ring.filter(ImageFilter.GaussianBlur(blur))
    core = Image.new("RGBA", (CANVAS, CANVAS))
    draw_fn(ImageDraw.Draw(core), core_w, (255, 255, 255, 255))
    out = Image.new("RGBA", (CANVAS, CANVAS))
    for layer in (glow, glow, layer_ring, core):
        out = Image.alpha_composite(out, layer)
    return out


def shrink(im, k):
    s = round(CANVAS * k)
    small = im.resize((s, s), Image.LANCZOS)
    out = Image.new("RGBA", (CANVAS, CANVAS))
    out.paste(small, ((CANVAS - s) // 2, (CANVAS - s) // 2), small)
    return out


def arrow(draw, w, fill, angle, length=86, head=30):
    c = CANVAS / 2
    dx, dy = math.cos(angle), math.sin(angle)
    for sgn in (1, -1):
        tip = (c + sgn * dx * length, c + sgn * dy * length)
        draw.line([(c, c), tip], fill=fill, width=w)
        for side in (1, -1):
            a = angle + (0 if sgn == 1 else math.pi) + math.pi + side * 0.6
            draw.line([tip, (tip[0] + math.cos(a) * head, tip[1] + math.sin(a) * head)], fill=fill, width=w)
        draw.ellipse([tip[0] - w / 2, tip[1] - w / 2, tip[0] + w / 2, tip[1] + w / 2], fill=fill)


def build_shapes(osk, ring):
    rgb = hex_rgb(ring)
    base = recolor_ring(skin_cursor(osk), ring)
    small = shrink(base, 0.55)

    def ibeam(d, w, f):
        c = CANVAS / 2
        d.line([(c, 48), (c, 208)], fill=f, width=w)
        d.line([(c - 26, 48), (c + 26, 48)], fill=f, width=w)
        d.line([(c - 26, 208), (c + 26, 208)], fill=f, width=w)

    def cross(d, w, f):
        c = CANVAS / 2
        d.line([(c, 40), (c, 100)], fill=f, width=w)
        d.line([(c, 156), (c, 216)], fill=f, width=w)
        d.line([(40, c), (100, c)], fill=f, width=w)
        d.line([(156, c), (216, c)], fill=f, width=w)

    def slash(d, w, f):
        c = CANVAS / 2
        d.ellipse([c - 88, c - 88, c + 88, c + 88], outline=f, width=w)
        d.line([(c - 62, c + 62), (c + 62, c - 62)], fill=f, width=w)

    def arrows(angle):
        return lambda d, w, f: arrow(d, w, f, angle)

    def four(d, w, f):
        arrow(d, w, f, 0, length=90, head=26)
        arrow(d, w, f, math.pi / 2, length=90, head=26)

    def with_dot(im):
        return Image.alpha_composite(im, shrink(base, 0.35))

    shapes = {
        "default": [base],
        "pointer": [Image.alpha_composite(
            glow_stroke(lambda d, w, f: d.ellipse([28, 28, 228, 228], outline=f, width=w), rgb, 6, 14, 10),
            shrink(base, 0.8))],
        "text": [glow_stroke(ibeam, rgb)],
        "crosshair": [with_dot(glow_stroke(cross, rgb, 8, 20, 10))],
        "not-allowed": [glow_stroke(slash, rgb, 10, 24, 12)],
        "grab": [shrink(base, 0.85)],
        "grabbing": [shrink(base, 0.65)],
        "move": [with_dot(glow_stroke(four, rgb, 9, 22, 12))],
        "ew-resize": [with_dot(glow_stroke(arrows(0), rgb))],
        "ns-resize": [with_dot(glow_stroke(arrows(math.pi / 2), rgb))],
        "nwse-resize": [with_dot(glow_stroke(arrows(math.pi / 4), rgb))],
        "nesw-resize": [with_dot(glow_stroke(arrows(-math.pi / 4), rgb))],
    }
    # wait: the small skin cursor with a coloured arc spinning around it.
    frames = []
    for i in range(WAIT_FRAMES):
        start = i * 360 / WAIT_FRAMES
        arc = glow_stroke(lambda d, w, f, s=start: d.arc([22, 22, 234, 234], s, s + 110, fill=f, width=w),
                          rgb, 10, 22, 10)
        frames.append(Image.alpha_composite(arc, small))
    shapes["wait"] = frames
    shapes["progress"] = frames
    return shapes


# Extra names so every toolkit finds a matching shape (XCursor names and CSS names).
ALIASES = {
    "default": ["left_ptr", "arrow", "top_left_arrow", "context-menu", "help", "question_arrow",
                "whats_this", "copy", "alias", "dnd-copy", "dnd-move", "dnd-link", "cell",
                "vertical-text", "zoom-in", "zoom-out", "default"],
    "pointer": ["hand1", "hand2", "pointing_hand", "pointer"],
    "text": ["xterm", "ibeam", "text"],
    "crosshair": ["cross", "tcross", "crosshair"],
    "not-allowed": ["crossed_circle", "circle", "forbidden", "no-drop", "dnd-no-drop", "not-allowed"],
    "grab": ["openhand", "fleur_grab", "grab"],
    "grabbing": ["closedhand", "dnd-none", "grabbing"],
    "move": ["fleur", "all-scroll", "size_all", "move"],
    "ew-resize": ["sb_h_double_arrow", "h_double_arrow", "size_hor", "col-resize", "split_h",
                  "left_side", "right_side", "e-resize", "w-resize", "ew-resize"],
    "ns-resize": ["sb_v_double_arrow", "v_double_arrow", "size_ver", "row-resize", "split_v",
                  "top_side", "bottom_side", "n-resize", "s-resize", "ns-resize"],
    "nwse-resize": ["bd_double_arrow", "size_fdiag", "top_left_corner", "bottom_right_corner",
                    "nw-resize", "se-resize", "nwse-resize"],
    "nesw-resize": ["fd_double_arrow", "size_bdiag", "top_right_corner", "bottom_left_corner",
                    "ne-resize", "sw-resize", "nesw-resize"],
    "wait": ["watch", "wait"],
    "progress": ["left_ptr_watch", "half-busy", "progress"],
}


# ---------- XCursor ----------

def xcursor_bytes(frames, sizes, delay):
    images = []
    for size in sizes:
        for f in frames:
            im = f.resize((size, size), Image.LANCZOS)
            raw = im.tobytes()
            px = bytearray()
            for i in range(0, len(raw), 4):
                r, g, b, a = raw[i:i + 4]
                # XCursor pixels are premultiplied ARGB, little endian.
                px += struct.pack("<I", (a << 24) | ((r * a // 255) << 16) | ((g * a // 255) << 8) | (b * a // 255))
            hot = size // 2
            header = struct.pack("<IIIIIIIII", 36, 0xFFFD0002, size, 1, size, size, hot, hot,
                                 delay if len(frames) > 1 else 0)
            images.append((size, header + bytes(px)))
    ntoc = len(images)
    out = bytearray(struct.pack("<4sIII", b"Xcur", 16, 0x10000, ntoc))
    pos = 16 + ntoc * 12
    for size, chunk in images:
        out += struct.pack("<III", 0xFFFD0002, size, pos)
        pos += len(chunk)
    for _, chunk in images:
        out += chunk
    return bytes(out)


# ---------- hyprcursor ----------

def write_hyprcursor_src(src, shapes, name):
    (src / "manifest.hl").write_text(
        f"name = {name}\ndescription = osu! skin cursor\nversion = 1.0\ncursors_directory = hyprcursors\n")
    for shape, frames in shapes.items():
        d = src / "hyprcursors" / shape
        d.mkdir(parents=True)
        lines = ["resize_algorithm = bilinear", "hotspot_x = 0.5", "hotspot_y = 0.5"]
        lines += [f"define_override = {a}" for a in ALIASES.get(shape, []) if a != shape]
        for i, f in enumerate(frames):
            fname = f"{shape}_{i}.png"
            f.resize((128, 128), Image.LANCZOS).save(d / fname)
            lines.append(f"define_size = 0, {fname}" + (f", {WAIT_DELAY_MS}" if len(frames) > 1 else ""))
        (d / "meta.hl").write_text("\n".join(lines) + "\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("osk")
    ap.add_argument("--name", default="WhiteCat")
    ap.add_argument("--ring", default="#ffff00")
    ap.add_argument("--out", default=str(Path.home() / ".local/share/icons"))
    args = ap.parse_args()

    shapes = build_shapes(args.osk, args.ring)
    theme = Path(args.out).expanduser() / args.name
    if theme.exists():
        shutil.rmtree(theme)
    cursors = theme / "cursors"
    cursors.mkdir(parents=True)

    for shape, frames in shapes.items():
        (cursors / shape).write_bytes(xcursor_bytes(frames, SIZES, WAIT_DELAY_MS))
        for alias in ALIASES.get(shape, []):
            link = cursors / alias
            if alias != shape and not link.exists():
                link.symlink_to(shape)

    with tempfile.TemporaryDirectory() as tmp:
        src = Path(tmp) / "src"
        src.mkdir()
        write_hyprcursor_src(src, shapes, args.name)
        subprocess.run(["hyprcursor-util", "--create", str(src), "--output", tmp], check=True,
                       stdout=subprocess.DEVNULL)
        built = next(Path(tmp).glob("theme_*"))
        shutil.copy(built / "manifest.hl", theme / "manifest.hl")
        shutil.copytree(built / "hyprcursors", theme / "hyprcursors")

    (theme / "index.theme").write_text(
        f"[Icon Theme]\nName={args.name}\nComment=osu! skin cursor\nInherits=Adwaita\n")
    preview = Image.new("RGBA", (64 * len(shapes) + 16, 80), (40, 40, 48, 255))
    for i, (shape, frames) in enumerate(shapes.items()):
        im = frames[0].resize((56, 56), Image.LANCZOS)
        preview.paste(im, (8 + i * 64, 12), im)
    preview.save(theme / "preview.png")
    print(theme)


if __name__ == "__main__":
    main()
