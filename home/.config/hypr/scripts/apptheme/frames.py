"""A moment of a GIF or a video as a still picture: a wallpaper picked from it in the settings window
(Тема → Обои → «Кадр из GIF или видео»). A GIF is read by Pillow, frame by frame; a video by ffmpeg,
at a time in seconds."""
import json
import shutil
import subprocess
from pathlib import Path

from PIL import Image

VIDEO_SUFFIXES = (".mp4", ".webm", ".mkv", ".mov", ".avi", ".m4v")


def length(path):
    """{"kind": "gif", "frames": N} or {"kind": "video", "seconds": S}."""
    path = Path(path)
    if path.suffix.lower() == ".gif":
        with Image.open(path) as image:
            return {"kind": "gif", "frames": getattr(image, "n_frames", 1)}
    if path.suffix.lower() in VIDEO_SUFFIXES:
        need_ffmpeg()
        probe = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "json", str(path)],
                               capture_output=True, text=True)
        try:
            return {"kind": "video", "seconds": float(json.loads(probe.stdout)["format"]["duration"])}
        except (ValueError, KeyError) as error:
            raise ValueError(f"{path.name}: не видео, которое понимает ffmpeg") from error
    raise ValueError(f"{path.name}: нужен GIF или видео ({', '.join(VIDEO_SUFFIXES)})")


def frame(path, at, out, width=0):
    """The moment at of path (a frame number of a GIF, seconds of a video) saved as a PNG at out;
    width > 0 makes it that wide (a preview), 0 keeps the full size."""
    path, out = Path(path), Path(out)
    out.parent.mkdir(parents=True, exist_ok=True)
    if path.suffix.lower() == ".gif":
        with Image.open(path) as image:
            image.seek(min(int(at), getattr(image, "n_frames", 1) - 1))
            picture = image.convert("RGB")
        if width:
            picture.thumbnail((width, width * 4))
        picture.save(out)
        return
    need_ffmpeg()
    scale = ["-vf", f"scale={int(width)}:-2"] if width else []
    made = subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", str(float(at)), "-i", str(path), "-frames:v", "1",
                           *scale, str(out)], capture_output=True, text=True)
    if made.returncode != 0 or not out.exists():
        raise ValueError(f"кадр не вынут: {made.stderr.strip()[:200]}")


def need_ffmpeg():
    if not shutil.which("ffmpeg") or not shutil.which("ffprobe"):
        raise ValueError("для кадра из видео нужен ffmpeg: sudo pacman -S ffmpeg")
