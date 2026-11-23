"""How colourful a clip is, second by second, for a theme whose menus follow its animated wallpaper
(ui.json "clipColour"): 1 = the theme's palette as it is, 0 = the palette turned grey.

A second's colour is the mean chroma of its lit pixels against their brightness, so a dark frame is not
taken for a grey one. It is judged against the clip's own usual colour (its median second), since one clip
is warm throughout and another pale throughout.
"""
import statistics
import subprocess

from .frames import need_ffmpeg

# A few small frames a second tell the colour as well as the full picture does, in a fraction of the time.
FRAMES_A_SECOND = 4
WIDTH, HEIGHT = 64, 36
# Pixels darker than this (0..255) carry no colour worth judging: black bars, the night sky.
LIT = 25
# Parts of the clip's usual colour: at or below GREY_AT a second counts as grey, at or above FULL_AT as fully
# coloured, in between it blends. Tuned on «если я буду в средневековье»: its grey part sits at 0.54.
GREY_AT = 0.6
FULL_AT = 0.9


def per_second(video):
    """[colourfulness 0..1, rounded to 0.01] for every second of video."""
    need_ffmpeg()
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", str(video), "-vf", f"fps={FRAMES_A_SECOND},scale={WIDTH}:{HEIGHT}",
                          "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], capture_output=True, check=True).stdout
    frame_size = WIDTH * HEIGHT * 3
    chroma = [frame_chroma(raw[start:start + frame_size]) for start in range(0, len(raw) - frame_size + 1, frame_size)]
    seconds = [statistics.fmean(chroma[start:start + FRAMES_A_SECOND]) for start in range(0, len(chroma), FRAMES_A_SECOND)]
    usual = statistics.median(seconds) or 1
    return [round(blend(second / usual), 2) for second in seconds]


def frame_chroma(frame):
    chroma = 0
    brightness = 0
    for start in range(0, len(frame), 3):
        pixel = frame[start:start + 3]
        brightest = max(pixel)
        if brightest >= LIT:
            chroma += brightest - min(pixel)
            brightness += brightest
    return chroma / brightness if brightness else 0


def blend(share_of_usual):
    return min(1, max(0, (share_of_usual - GREY_AT) / (FULL_AT - GREY_AT)))
