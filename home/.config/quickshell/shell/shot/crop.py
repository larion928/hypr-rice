#!/usr/bin/env python3
"""crop.py SRC X Y W H LOGICAL_W LOGICAL_H OUT — cut a region (logical coords) out of a frozen
output capture, save it as PNG and put it on the clipboard."""
import subprocess
import sys

from PIL import Image


def physical_box(image, region, logical_size):
    """The region (x, y, w, h in the overlay's logical coords) as a crop box in the capture's pixels, or None
    when nothing of it is left. grim captures in physical pixels, the overlay works in logical ones."""
    x, y, w, h = region
    logical_w, logical_h = logical_size
    sx = image.width / logical_w
    sy = image.height / logical_h
    box = (
        max(0, round(x * sx)),
        max(0, round(y * sy)),
        min(image.width, round((x + w) * sx)),
        min(image.height, round((y + h) * sy)),
    )
    if box[2] - box[0] < 1 or box[3] - box[1] < 1:
        return None
    return box


def main():
    src, out = sys.argv[1], sys.argv[8]
    x, y, w, h, lw, lh = map(float, sys.argv[2:8])
    im = Image.open(src)
    box = physical_box(im, (x, y, w, h), (lw, lh))
    if box is None:
        return 1
    im.crop(box).save(out)
    with open(out, "rb") as f:
        subprocess.run(["wl-copy", "--type", "image/png"], stdin=f, check=False)
    print(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
