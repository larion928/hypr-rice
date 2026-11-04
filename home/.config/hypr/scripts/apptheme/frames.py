"""A moment of a GIF or a video as a still picture: a wallpaper picked from it in the settings window
(Тема → Обои → «Кадр из GIF или видео»). The window first asks prepare(): a GIF becomes an mp4 once,
since a GIF has no way to jump to a frame (frame 300 of 300 took 0.6 s, the same in a video 0.26 s
wherever it is); a video is used as it is, ffmpeg jumps in it directly. Without ffmpeg a GIF is read
by Pillow, frame by frame."""
import hashlib
import json
import shutil
import subprocess
from pathlib import Path

from PIL import Image

from .paths import HOME

VIDEO_SUFFIXES = (".mp4", ".webm", ".mkv", ".mov", ".avi", ".m4v")
PREPARED = HOME / ".cache/hypr-rice/frame-sources"
# A wallpaper wider than any screen is only scaled down again by awww.
MAX_WIDTH = 3840


def prepare(path):
    """What the frame picker reads: {"source": file, "kind": "video", "seconds": S}, a GIF made into
    an mp4 when ffmpeg is there; else {"source": gif, "kind": "gif", "frames": N}."""
    path = Path(path)
    if path.suffix.lower() == ".gif" and has_ffmpeg():
        target = PREPARED / (hashlib.sha1(f"{path}:{path.stat().st_mtime}".encode()).hexdigest()[:16] + ".mp4")
        if not target.exists():
            PREPARED.mkdir(parents=True, exist_ok=True)
            # Nearly lossless (no colour subsampling) and a key frame every 15 frames, for quick jumps.
            made = subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(path), "-c:v", "libx264", "-preset", "veryfast",
                                   "-crf", "10", "-pix_fmt", "yuv444p", "-g", "15", str(target)],
                                  capture_output=True, text=True)
            if made.returncode != 0:
                target.unlink(missing_ok=True)
                raise ValueError(f"GIF не перевёлся в видео: {made.stderr.strip()[:200]}")
        return {"source": str(target), **length(target)}
    return {"source": str(path), **length(path)}


def forget(source):
    """Removes a GIF's mp4 once the picker is done with it; a user's own file is never touched."""
    source = Path(source)
    if source.parent == PREPARED:
        source.unlink(missing_ok=True)


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
        picture.thumbnail((width or MAX_WIDTH, (width or MAX_WIDTH) * 4))
        picture.save(out)
        return
    need_ffmpeg()
    scale = ["-vf", f"scale={int(width)}:-2" if width else f"scale='min({MAX_WIDTH},iw)':-2"]
    made = subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", str(float(at)), "-i", str(path), "-frames:v", "1",
                           *scale, str(out)], capture_output=True, text=True)
    if made.returncode != 0 or not out.exists():
        raise ValueError(f"кадр не вынут: {made.stderr.strip()[:200]}")


def has_ffmpeg():
    return bool(shutil.which("ffmpeg") and shutil.which("ffprobe"))


def need_ffmpeg():
    if not has_ffmpeg():
        raise ValueError("для кадра из видео нужен ffmpeg: sudo pacman -S ffmpeg")
