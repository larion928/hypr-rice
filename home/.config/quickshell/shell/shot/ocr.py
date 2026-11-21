#!/usr/bin/env python3
"""ocr.py SRC X Y W H LOGICAL_W LOGICAL_H — read the text in a region (logical coords) of a frozen output
capture with tesseract, in Russian and English, put it on the clipboard and say so in a notification.
Run by the screenshot overlay in its "ocr" mode (`shot ocr`, Alt+Shift+Print)."""
import io
import subprocess
import sys

from PIL import Image

from crop import physical_box

# tesseract is made for scanned pages, whose letters are several times taller than a screen's; enlarging the
# region first reads small interface text better. A parameter, not a measured optimum.
UPSCALE = 2
LANGUAGES = "rus+eng"
PREVIEW_CHARS = 120


def notify(title, body, urgency="normal"):
    subprocess.run(["notify-send", "-u", urgency, "-a", "Распознавание текста", title, body], check=False)


def read_text(image):
    enlarged = image.resize((image.width * UPSCALE, image.height * UPSCALE), Image.Resampling.LANCZOS)
    png = io.BytesIO()
    enlarged.save(png, "PNG")
    result = subprocess.run(["tesseract", "stdin", "stdout", "-l", LANGUAGES],
                            input=png.getvalue(), capture_output=True, check=False)
    if result.returncode != 0:
        last_line = result.stderr.decode(errors="replace").strip().splitlines()[-1:]
        raise RuntimeError("".join(last_line) or f"tesseract завершился с кодом {result.returncode}")
    return result.stdout.decode(errors="replace").strip()


def main():
    src = sys.argv[1]
    x, y, w, h, lw, lh = map(float, sys.argv[2:8])
    im = Image.open(src)
    box = physical_box(im, (x, y, w, h), (lw, lh))
    if box is None:
        return 1
    try:
        text = read_text(im.crop(box))
    except (OSError, RuntimeError) as error:
        notify("Не удалось распознать текст", str(error), "critical")
        return 1
    if not text:
        notify("Текст не найден", "В выделенной области tesseract не нашёл текста")
        return 0
    subprocess.run(["wl-copy"], input=text.encode(), check=False)
    preview = " ".join(text.split())
    if len(preview) > PREVIEW_CHARS:
        preview = preview[:PREVIEW_CHARS] + "…"
    notify("Текст скопирован", preview)
    return 0


if __name__ == "__main__":
    sys.exit(main())
