#!/usr/bin/env python3
"""crop.py SRC X Y W H LOGICAL_W LOGICAL_H OUT — cut a region (logical coords) out of a frozen
output capture, save it as PNG and put it on the clipboard."""
import subprocess
import sys

from PIL import Image


def main():
    src, x, y, w, h, lw, lh, out = sys.argv[1:9]
    x, y, w, h, lw, lh = map(float, (x, y, w, h, lw, lh))
    im = Image.open(src)
    # grim captures in physical pixels, the overlay works in logical ones.
    sx, sy = im.width / lw, im.height / lh
    box = (
        max(0, round(x * sx)),
        max(0, round(y * sy)),
        min(im.width, round((x + w) * sx)),
        min(im.height, round((y + h) * sy)),
    )
    if box[2] - box[0] < 1 or box[3] - box[1] < 1:
        return 1
    im.crop(box).save(out)
    with open(out, "rb") as f:
        subprocess.run(["wl-copy", "--type", "image/png"], stdin=f, check=False)
    print(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
