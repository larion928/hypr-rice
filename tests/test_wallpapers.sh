# Wallpapers: GIFs and videos, stills, frames, the wallpaper command, Wallpaper Engine.

# An animated GIF is a wallpaper like any other; what cannot play it (lock and login screens,
# browsers) gets its first frame from .stills/, which a copy of the theme leaves out.
test_gif_wallpaper() {
    user_theme_home
    python3 - "$HOME/.config/hypr/scripts" "$HOME" <<'PY' || fail "GIF-обои не так"
import sys
from pathlib import Path
from PIL import Image
sys.path.insert(0, sys.argv[1])
from apptheme.themes import bake
from apptheme.wallpapers import wallpaper_still
from apptheme.themes.theme import load
home = Path(sys.argv[2])
coffee = home / ".config/hypr/themes/coffee"
frames = [Image.new("RGB", (8, 8), color) for color in ((200, 0, 0), (0, 0, 200))]
frames[0].save(coffee / "zz-animated.gif", save_all=True, append_images=frames[1:], duration=100, loop=0)

assert coffee / "zz-animated.gif" in load("coffee").own_wallpapers
still = Path(wallpaper_still.still(coffee / "zz-animated.gif"))
assert still == coffee / ".stills/zz-animated.png", still
assert Image.open(still).convert("RGB").getpixel((0, 0)) == (200, 0, 0), "кадр не первый"
plain = next(p for p in load("coffee").own_wallpapers if p.suffix == ".png")
assert wallpaper_still.still(plain) == str(plain)

bake.copy_theme(coffee, home / "copy")
assert (home / "copy/zz-animated.gif").exists() and not (home / "copy/.stills").exists()
PY
}

# A wallpaper from a moment of a GIF (by frame) or a video (by second, when ffmpeg is there).
test_wallpaper_frames() {
    python3 - "$REPO/home/.config/hypr/scripts" "$HOME" <<'PY' || fail "кадр вынут не так"
import shutil, subprocess, sys
from pathlib import Path
from PIL import Image
sys.path.insert(0, sys.argv[1])
from apptheme.wallpapers import frames
home = Path(sys.argv[2])
pictures = [Image.new("RGB", (40, 20), color) for color in ((200, 0, 0), (0, 200, 0), (0, 0, 200))]
pictures[0].save(home / "a.gif", save_all=True, append_images=pictures[1:], duration=100)
assert frames.length(home / "a.gif") == {"kind": "gif", "frames": 3}
frames.frame(home / "a.gif", 1, home / "frame.png")
assert Image.open(home / "frame.png").convert("RGB").getpixel((5, 5))[1] > 150, "не второй кадр"
frames.frame(home / "a.gif", 2, home / "small.png", 20)
assert Image.open(home / "small.png").size == (20, 10)
if shutil.which("ffmpeg"):
    subprocess.run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i", "color=c=blue:s=64x36:d=2", str(home / "v.mp4")], check=True)
    assert 1.5 < frames.length(home / "v.mp4")["seconds"] < 2.5
    frames.frame(home / "v.mp4", 1.0, home / "v.png")
    assert Image.open(home / "v.png").size == (64, 36)
    # A GIF is read through an mp4 made once; the user's own files are never removed.
    prepared = frames.prepare(home / "a.gif")
    assert prepared["kind"] == "video" and prepared["source"].endswith(".mp4"), prepared
    # ffmpeg gives the first frame starting at or after the moment: at 0.1 s the GIF's second one. The
    # preview and the saved frame come the same way, so what is picked is what was seen.
    frames.frame(prepared["source"], 0.1, home / "from-mp4.png")
    assert Image.open(home / "from-mp4.png").convert("RGB").getpixel((20, 10))[1] > 150, "не второй кадр GIF"
    frames.frame(prepared["source"], 0.1, home / "preview.png", 20)
    assert Image.open(home / "preview.png").convert("RGB").getpixel((10, 5))[1] > 150, "превью не тот кадр, что сохранён"
    assert frames.prepare(home / "v.mp4")["source"] == str(home / "v.mp4")
    frames.forget(home / "v.mp4")
    assert (home / "v.mp4").exists(), "удалено видео пользователя"
    frames.forget(prepared["source"])
    assert not Path(prepared["source"]).exists()
    # A frame wider than any screen is kept at 3840.
    subprocess.run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i", "color=c=red:s=4000x200:d=1", str(home / "wide.mp4")], check=True)
    frames.frame(home / "wide.mp4", 0.2, home / "wide.png")
    assert Image.open(home / "wide.png").size[0] == 3840, Image.open(home / "wide.png").size
try:
    frames.length(home / "frame.png")
    raise AssertionError("кадр из картинки")
except ValueError:
    pass
PY
}

# Animated wallpapers play from one format: an H.264 mp4 in yuv420p, no wider than the screen, at most
# 30 frames a second, no sound; one already like that plays as it is.
test_animated_wallpapers_one_format() {
    command -v ffmpeg >/dev/null || { echo "нет ffmpeg, пропускаю"; return 0; }
    mkdir -p "$HOME/w"
    ffmpeg -v error -f lavfi -i testsrc2=s=1280x720:r=60:d=1 -f lavfi -i sine=d=1 -shortest -c:v libx264 -c:a aac "$HOME/w/clip.mkv"
    ffmpeg -v error -f lavfi -i testsrc2=s=320x180:r=10:d=1 "$HOME/w/anim.gif"
    python3 - "$REPO/home/.config/hypr/scripts" "$HOME" <<'PY' || fail "анимированные обои не в одном формате"
import json, subprocess, sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
from apptheme.wallpapers import animated, wallpaper_still
home = Path(sys.argv[2])
animated.screen_width = lambda: 640

def streams(video):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "stream=codec_type,codec_name,pix_fmt,width,avg_frame_rate",
                          "-of", "json", video], capture_output=True, text=True).stdout
    return json.loads(out)["streams"]

clip = animated.playable(home / "w/clip.mkv")
assert clip == str(home / "w/.animated/clip.mp4"), clip
[video] = streams(clip)  # one stream: the sound is gone
assert (video["codec_name"], video["pix_fmt"], video["width"], video["avg_frame_rate"]) == ("h264", "yuv420p", 640, "30/1"), video
assert animated.playable(clip) == clip, "подходящий mp4 переделан заново"
gif = animated.playable(home / "w/anim.gif")
assert streams(gif)[0]["avg_frame_rate"] == "10/1", "у GIF прибавились кадры"

kept = animated.import_into(home / "w/clip.mkv", home / "added")
assert kept == str(home / "added/clip.mp4") and animated.fits(Path(kept))
assert animated.import_into(kept, home / "added2") == str(home / "added2/clip.mp4")

still = Path(wallpaper_still.still(home / "w/clip.mkv"))
assert still == home / "w/.stills/clip.png" and still.stat().st_size > 0
PY
}

# ~/.local/bin/wallpaper: a picture through awww, an animation through mpvpaper over its first frame;
# without mpvpaper a GIF plays in awww and a video shows its first frame.
test_wallpaper_command() {
    command -v ffmpeg >/dev/null || { echo "нет ffmpeg, пропускаю"; return 0; }
    mkdir -p "$HOME/bin" "$HOME/.config/hypr" "$HOME/w"
    cp -r "$REPO/home/.config/hypr/scripts" "$HOME/.config/hypr/"
    for name in awww pkill notify-send hyprctl; do
        printf '#!/bin/sh\necho "%s $*" >> "%s/calls"\n' "$name" "$HOME" > "$HOME/bin/$name"
    done
    chmod +x "$HOME/bin"/*
    ffmpeg -v error -f lavfi -i testsrc2=s=320x180:r=10:d=1 "$HOME/w/anim.gif"
    ffmpeg -v error -f lavfi -i testsrc2=s=320x180:r=10:d=1 -c:v libx264 -pix_fmt yuv420p "$HOME/w/clip.mp4"
    touch "$HOME/w/pic.png"
    run_wallpaper() {
        : > "$HOME/calls"
        WALLPAPER_PLAYER="$HOME/bin/player" PATH="$HOME/bin:/usr/bin" "$REPO/home/.local/bin/wallpaper" "$1"
    }

    run_wallpaper "$HOME/w/pic.png"
    grep -qx "awww img $HOME/w/pic.png" "$HOME/calls" || fail "картинка: $(cat "$HOME/calls")"

    run_wallpaper "$HOME/w/anim.gif"  # no player yet
    grep -qx "awww img $HOME/w/anim.gif" "$HOME/calls" || fail "GIF без mpvpaper: $(cat "$HOME/calls")"
    run_wallpaper "$HOME/w/clip.mp4"
    grep -qx "awww img $HOME/w/.stills/clip.png" "$HOME/calls" && grep -q '^notify-send' "$HOME/calls" \
        || fail "видео без mpvpaper: $(cat "$HOME/calls")"

    printf '#!/bin/sh\necho "mpvpaper $*" >> "%s/calls"\n' "$HOME" > "$HOME/bin/player"
    chmod +x "$HOME/bin/player"
    run_wallpaper "$HOME/w/anim.gif"
    grep -qx "awww img $HOME/w/.stills/anim.png" "$HOME/calls" \
        && grep -q "^mpvpaper .* ALL $HOME/w/.animated/anim.mp4$" "$HOME/calls" || fail "GIF через mpvpaper: $(cat "$HOME/calls")"
}

# Without mpvpaper (or the ffmpeg it brings) the settings window is told which package to offer, and an
# animation added meanwhile is kept as it is, to be converted once ffmpeg is there.
test_animated_wallpapers_need_mpvpaper() {
    mkdir -p "$HOME/empty-path" "$HOME/w"
    printf 'GIF89a' > "$HOME/w/anim.gif"
    PATH="$HOME/empty-path" /usr/bin/python3 - "$REPO/home/.config/hypr/scripts" "$HOME" <<'PY' || fail "без mpvpaper не так"
import sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
from apptheme.wallpapers import animated
home = Path(sys.argv[2])
assert animated.missing_package() == "mpvpaper", animated.missing_package()
kept = animated.import_into(home / "w/anim.gif", home / "added")
assert kept == str(home / "added/anim.gif") and Path(kept).read_bytes() == b"GIF89a", kept
PY
}

# Wallpaper Engine's subscriptions: listed with their type, a video one added as an mp4 named after its
# title; a scene is not a video and is refused, a broken project.json is skipped.
test_wallpaper_engine_videos() {
    command -v ffmpeg >/dev/null || { echo "нет ffmpeg, пропускаю"; return 0; }
    local workshop="$HOME/.local/share/Steam/steamapps/workshop/content/431960"
    mkdir -p "$workshop/111" "$workshop/222" "$workshop/333" "$workshop/444"
    python3 - "$REPO/home/.config/hypr/scripts" "$HOME" <<'PY' || fail "Wallpaper Engine не так"
import json, subprocess, sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
from apptheme.wallpapers import animated, wallpaper_engine
home = Path(sys.argv[2])
workshop = home / ".local/share/Steam/steamapps/workshop/content/431960"
animated.screen_width = lambda: 640

assert wallpaper_engine.listing() == {"installed": False, "items": []}, wallpaper_engine.listing()

subprocess.run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i", "testsrc2=s=320x180:r=10:d=1", str(workshop / "111/video.webm")], check=True)
(workshop / "111/preview.jpg").write_bytes(b"jpg")
(workshop / "111/project.json").write_text(json.dumps({"title": "Neon / City", "type": "Video", "file": "video.webm", "preview": "preview.jpg"}))
(workshop / "222/project.json").write_text(json.dumps({"title": "A scene", "type": "scene", "file": "scene.json"}))
(workshop / "333/project.json").write_text(json.dumps({"title": "Web one", "type": "web", "file": "index.html"}))
(workshop / "444/project.json").write_text("{broken")
(home / ".local/share/Steam/steamapps/appmanifest_431960.acf").write_text("x")

listed = wallpaper_engine.listing()
assert listed["installed"]
assert [(i["title"], i["type"], i["addable"]) for i in listed["items"]] == \
    [("A scene", "scene", False), ("Neon / City", "video", True), ("Web one", "web", False)], listed
assert listed["items"][1]["preview"].endswith("111/preview.jpg")

kept = wallpaper_engine.add("111", home / "added")
assert kept == str(home / "added/Neon _ City.mp4") and animated.fits(Path(kept)), kept
try:
    wallpaper_engine.add("222", home / "added")
    raise AssertionError("сцена добавлена как видео")
except ValueError as error:
    assert "не видео" in str(error), error
PY
}
