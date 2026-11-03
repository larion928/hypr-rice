"""Chromium, Brave, Chrome: an unpacked theme extension (colours, the wallpaper on the new tab page, the
theme's emblem in its corner) that the browsers load from their flags file on start."""
import json
import shutil
import subprocess
import time

from . import browser
from .colors import mix, rgb
from .files import with_block, write
from .paths import HOME

# command: (flags file its launcher reads, profile root, process name). The flags files are read
# by Arch's chromium, brave-bin and google-chrome (AUR) launchers.
BROWSERS = {
    "chromium": (".config/chromium-flags.conf", ".config/chromium", "chromium"),
    "brave": (".config/brave-flags.conf", ".config/BraveSoftware/Brave-Browser", "brave"),
    "google-chrome-stable": (".config/chrome-flags.conf", ".config/google-chrome", "chrome"),
}
EXTENSION_DIR = HOME / ".local/share/hypr-themes/chromium"
FLAGS_BEGIN = "# hypr-rice begin: the theme extension, rewritten on every theme change"
FLAGS_END = "# hypr-rice end"


def apply(theme, wallpaper):
    installed = [cmd for cmd in BROWSERS if shutil.which(cmd)]
    if not installed:
        return
    write_extension(theme, wallpaper)
    for cmd in installed:
        flags_file, profile_root, process = BROWSERS[cmd]
        write_flags(HOME / flags_file)
        set_dark_mode(HOME / profile_root, process)


def write_extension(theme, wallpaper):
    look = browser.look(theme)
    toolbar = mix(look["bg2"], look["accent"], 0.06)
    frame_colors = {
        "frame": look["side"], "frame_inactive": look["bg"],
        "frame_incognito": look["bg"], "frame_incognito_inactive": look["bg"],
        "toolbar": toolbar, "toolbar_text": look["fg"], "toolbar_button_icon": look["fg"],
        "tab_text": look["fg"], "tab_background_text": look["muted"],
        "tab_background_text_inactive": look["muted"], "bookmark_text": look["fg"],
        "omnibox_background": look["field"], "omnibox_text": look["fg"],
        "ntp_background": look["bg"], "ntp_text": look["fg"], "ntp_link": look["accent"],
    }
    images, properties = {}, {}
    images_dir = EXTENSION_DIR / "images"
    shutil.rmtree(images_dir, ignore_errors=True)
    images_dir.mkdir(parents=True)
    if wallpaper:
        (images_dir / "ntp.jpg").write_bytes(browser.wallpaper_jpeg(wallpaper, 1920, 85))
        images["theme_ntp_background"] = "images/ntp.jpg"
        properties.update(ntp_background_alignment="center", ntp_background_repeat="no-repeat",
                          ntp_logo_alternate=1)
    emblem = browser.theme_emblem(theme)
    if emblem and shutil.which("rsvg-convert"):
        subprocess.run(["rsvg-convert", "-w", "88", "-h", "88", str(emblem), "-o", str(images_dir / "emblem.png")],
                       check=False)
        images["theme_ntp_attribution"] = "images/emblem.png"
    # A new version makes the browser rebuild its cached theme pack.
    minutes = int(time.time()) // 60
    manifest = {
        "manifest_version": 3,
        "name": f"Hypr {look['label']}",
        "version": f"1.{minutes // 65536}.{minutes % 65536}",
        "theme": {"colors": {key: list(rgb(value)) for key, value in frame_colors.items()}, "images": images,
                  "properties": properties},
    }
    write(EXTENSION_DIR / "manifest.json", json.dumps(manifest, indent=2) + "\n")


def write_flags(path):
    text = path.read_text() if path.exists() else ""
    # Chromium 137+ ignores --load-extension unless this feature is switched off.
    block = ["--disable-features=DisableLoadExtensionCommandLineSwitch", f"--load-extension={EXTENSION_DIR}"]
    write(path, with_block(text, FLAGS_BEGIN, FLAGS_END, block))


def set_dark_mode(base, process):
    """Dark mode in every profile. Also drops the new tab background older rice versions set
    (<profile>/background.jpg): it would cover the theme's wallpaper. A running browser rewrites
    Preferences on exit, so it is left alone until the next theme change."""
    if subprocess.run(["pgrep", "-x", process], capture_output=True).returncode == 0:
        return
    for profile in [base / "Default", *base.glob("Profile *")]:
        prefs_path = profile / "Preferences"
        if not prefs_path.exists():
            continue
        try:
            prefs = json.loads(prefs_path.read_text())
        except ValueError:
            continue
        browser_theme = prefs.setdefault("browser", {}).setdefault("theme", {})
        ntp = prefs.setdefault("ntp", {})
        if browser_theme.get("color_scheme2") == 2 and "custom_background_local_to_device" not in ntp:
            continue
        browser_theme["color_scheme2"] = 2
        ntp.pop("custom_background_local_to_device", None)
        (profile / "background.jpg").unlink(missing_ok=True)
        prefs_path.write_text(json.dumps(prefs, separators=(",", ":")))

