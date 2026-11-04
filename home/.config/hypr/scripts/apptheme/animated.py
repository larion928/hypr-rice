"""Animated wallpapers in one format: whatever was added (a GIF, an .mp4, .webm, .mkv, ...) is played
from an H.264 mp4 by mpvpaper (~/.local/bin/wallpaper), which the GPU decodes: yuv420p, no wider than
the screen, at most 30 frames a second, no sound. A file already like that plays as it is; any other
is converted once into .animated/ next to it."""
import json
import shutil
import subprocess
from pathlib import Path

from .frames import need_ffmpeg

ANIMATED_SUFFIXES = (".gif", ".mp4", ".webm", ".mkv", ".mov", ".avi", ".m4v")
CONVERTED = ".animated"
MAX_FPS = 30
DEFAULT_SCREEN_WIDTH = 1920


def is_animated(path):
    return Path(path).suffix.lower() in ANIMATED_SUFFIXES


def playable(path):
    """The mp4 mpvpaper plays for the animated wallpaper at path."""
    path = Path(path)
    if path.suffix.lower() == ".mp4" and fits(path):
        return str(path)
    target = path.parent / CONVERTED / f"{path.stem}.mp4"
    if not target.exists() or target.stat().st_mtime < path.stat().st_mtime:
        convert(path, target)
    return str(target)


def import_into(source, folder):
    """An animation added in the settings window, kept in folder as the mp4 it plays from (a file
    already fit for playing is copied as it is); the kept file's path."""
    source, folder = Path(source), Path(folder)
    target = folder / f"{source.stem}.mp4"
    folder.mkdir(parents=True, exist_ok=True)
    if source.suffix.lower() == ".mp4" and fits(source):
        if source.resolve() != target.resolve():
            shutil.copy(source, target)
    else:
        convert(source, target)
    return str(target)


def fits(video):
    """H.264 in yuv420p, no sound, no wider than the screen, at most MAX_FPS frames a second."""
    probe = subprocess.run(["ffprobe", "-v", "error", "-show_entries",
                            "stream=codec_type,codec_name,pix_fmt,width,avg_frame_rate", "-of", "json", str(video)],
                           capture_output=True, text=True)
    try:
        streams = json.loads(probe.stdout)["streams"]
    except (ValueError, KeyError):
        return False
    videos = [stream for stream in streams if stream.get("codec_type") == "video"]
    if len(videos) != 1 or len(streams) != 1:  # a second stream is sound (or subtitles)
        return False
    stream = videos[0]
    return (stream.get("codec_name") == "h264" and stream.get("pix_fmt") == "yuv420p"
            and stream.get("width", 0) <= screen_width() and frame_rate(stream) <= MAX_FPS)


def convert(source, target):
    need_ffmpeg()
    target.parent.mkdir(exist_ok=True)
    width = screen_width()
    # Even sizes for yuv420p; never wider than the screen, never upscaled; no more than MAX_FPS frames.
    scale = f"scale='trunc(min({width},iw)/2)*2':-2,fps='min({MAX_FPS},source_fps)'"
    made = subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(source), "-an", "-vf", scale,
                           "-c:v", "libx264", "-preset", "medium", "-crf", "23", "-pix_fmt", "yuv420p",
                           "-movflags", "+faststart", str(target)], capture_output=True, text=True)
    if made.returncode != 0:
        target.unlink(missing_ok=True)
        raise ValueError(f"{source.name} не перевёлся в mp4: {made.stderr.strip()[:200]}")


def frame_rate(stream):
    numerator, _, denominator = str(stream.get("avg_frame_rate", "0/1")).partition("/")
    try:
        return float(numerator) / float(denominator or 1)
    except (ValueError, ZeroDivisionError):
        return 0


def screen_width():
    """The widest monitor's width; DEFAULT_SCREEN_WIDTH outside Hyprland."""
    try:
        monitors = json.loads(subprocess.run(["hyprctl", "monitors", "-j"], capture_output=True, text=True,
                                             timeout=3).stdout)
        return max(monitor["width"] for monitor in monitors)
    except (OSError, subprocess.SubprocessError, ValueError, KeyError):
        return DEFAULT_SCREEN_WIDTH
