#!/usr/bin/env python3
"""color.py SRC X Y LOGICAL_W LOGICAL_H — the colour of the pixel at a point (logical coords) of a frozen output
capture, as #rrggbb on the clipboard and in a notification. Run by the colour picker (`shot color`,
Alt+Shift+C); read here from the capture because QML cannot read an image's pixels."""
import subprocess
import sys

from PIL import Image


def main():
    src = sys.argv[1]
    x, y, lw, lh = map(float, sys.argv[2:6])
    im = Image.open(src).convert("RGB")
    # grim captures in physical pixels, the picker works in logical ones.
    column = min(im.width - 1, int(x * im.width / lw))
    row = min(im.height - 1, int(y * im.height / lh))
    red, green, blue = im.getpixel((column, row))
    color = f"#{red:02x}{green:02x}{blue:02x}"
    subprocess.run(["wl-copy", color], check=False)
    subprocess.run(["notify-send", "-a", "Пипетка", "Цвет скопирован", color], check=False)
    print(color)
    return 0


if __name__ == "__main__":
    sys.exit(main())
