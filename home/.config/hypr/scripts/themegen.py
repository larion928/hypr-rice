#!/usr/bin/env python3
"""Generate app configs from ~/.config/hypr/themes/<name>/palette.json and ui.json: one module per
program in apptheme/ (apps/, desktop/, cursors/, icons/, wallpapers/), the themes themselves in
apptheme/themes/. COMMANDS at the end of this file is the list of commands; running it without one
(or with arguments that do not fit) prints them with their arguments."""
import contextlib
import os
import random
import subprocess
import sys
import traceback
import zipfile
from functools import partial
from pathlib import Path

from command_table import Command, printing, printing_json, run
from apptheme.apps import chromium, drift, firefox, gtk, kitty, obsidian, telegram, vesktop, vscode
from apptheme.cursors import cursor_install, cursor_theme, cursor_themes
from apptheme.desktop import bar_preview, battery, css_palette, hypr, hyprlock, system, waybar, windows
from apptheme.files import write
from apptheme.icons import glyphs, icon_theme, icon_themes
from apptheme.paths import HOME, HYPR, THEMES
from apptheme.themes import factory_reset, removed_themes, user_themes
from apptheme.themes.theme import all_names, load
from apptheme.wallpapers import animated, frames, wallpaper_engine, wallpaper_still


def switch(name, keep_wallpaper, offline):
    """changetheme's wallpaper and palette steps in one python start, with its messages. 0, or 1 when the
    wallpapers could not be listed or the theme not applied in full."""
    # The messages keep their order with the errors on stderr and the wallpaper script's output.
    sys.stdout.reconfigure(line_buffering=True)
    try:
        wallpapers = load(name).wallpapers
    except ValueError as error:
        print(error, file=sys.stderr)
        print("ОШИБКА: themegen.py не смог перечислить обои темы (см. ошибку выше), обои остаются прежними")
        wallpaper, status = None, 1
    else:
        wallpaper, status = change_wallpaper(wallpapers, keep_wallpaper, offline), 0

    if not (THEMES / name / "palette.json").is_file():
        print("Предупреждение: в теме нет palette.json — цвета остаются от прежней темы")
        return status
    try:
        applied = apply(name, wallpaper) == 0
    except ValueError as error:
        print(error, file=sys.stderr)
        applied = False
    if applied:
        print(f"Применена палитра темы: {name}")
        return status
    print("ОШИБКА: themegen.py не смог применить палитру, часть приложений осталась в прежней теме")
    return 1


def change_wallpaper(wallpapers, keep_wallpaper, offline):
    """The wallpaper the theme change leaves on the desktop, None when the theme has none. keep_wallpaper
    keeps the current one if the theme has it; otherwise a random one is picked, remembered and, unless
    offline, shown."""
    if not wallpapers:
        print("Предупреждение: В папке темы нет изображений.")
        return None
    current = current_wallpaper()
    if keep_wallpaper and current in map(str, wallpapers):
        print(f"Обои остаются: {current}")
        return current
    wallpaper = str(random.choice(wallpapers))
    print(f"Устанавливаю обои: {wallpaper}")
    # Restored by the autostart in hyprland.lua, so a theme set offline gets its wallpaper too.
    write(HYPR / "current-wallpaper", wallpaper + "\n")
    if not offline:
        # Before apply: the desktop changes first, and an animation's still is made once, by the
        # wallpaper script (apply then finds it made).
        try:
            subprocess.run([HOME / ".local/bin/wallpaper", wallpaper], check=False)
        except OSError as error:  # the theme is still applied, as when the script itself fails
            report_failure("wallpaper", error)
    return wallpaper


def apply(name, wallpaper=None):
    """0, or 1 when a program's step failed (each failure on stderr; the other programs still change)."""
    theme = load(name)
    # awww already plays an animated wallpaper; the lock and login screens and the browsers get a still.
    status, wallpaper = still_of(wallpaper)
    # changetheme reloads Hyprland, which drops any screen shader; keep screen-fx in sync.
    (Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp")) / "screen-fx-on").unlink(missing_ok=True)
    steps = (
        partial(hypr.apply, theme), partial(windows.apply, theme), partial(css_palette.apply, theme),
        partial(waybar.apply, theme), partial(kitty.apply, theme), partial(hyprlock.apply, theme, wallpaper),
        partial(gtk.apply, theme), partial(icon_theme.apply, theme), partial(cursor_theme.apply, theme),
        partial(drift.apply, theme), partial(vscode.apply, theme), partial(system.apply, theme, wallpaper),
        partial(obsidian.apply, theme), partial(vesktop.apply, theme), partial(firefox.apply, theme, wallpaper),
        partial(chromium.apply, theme, wallpaper),
    )
    return max(status, run_each(steps))


def still_of(wallpaper):
    """(status, the wallpaper's still picture): (0, None) without a wallpaper, (1, None) when no still
    can be made (a GIF without ffmpeg); the steps then do without one, as with no wallpaper."""
    if not wallpaper:
        return 0, None
    try:
        return 0, wallpaper_still.still(wallpaper)
    except Exception as error:  # whatever breaks, the theme still has to be applied
        report_failure("wallpaper_still", error)
        return 1, None


def run_each(steps):
    """Runs every step, also after one failed: one broken program's file must not leave every program
    after it in the old theme. 0, or 1 when a step failed, with the failure on stderr."""
    status = 0
    for step in steps:
        try:
            step()
        except Exception as error:  # any failure is one program's, the rest go on
            report_failure(getattr(step, "func", step).__module__.rpartition(".")[2], error)
            status = 1
    return status


def report_failure(step, error):
    """One line on stderr: the step, where it broke and why."""
    where = traceback.extract_tb(error.__traceback__)[-1]
    print(f"{step}: {type(error).__name__}: {error} ({Path(where.filename).name}:{where.lineno})", file=sys.stderr)


def build():
    user_themes.link()  # an update may have brought a theme of the same name, or the links are new
    themes = [load(name) for name in all_names()]
    drift.build(themes)
    print("vscode:", vscode.build(themes))
    print("telegram:", telegram.build(themes))
    battery.build(themes)
    current = current_theme()
    if current:
        drift.apply(current)


def refresh():
    """Theme what appeared since the last theme change (a new Firefox profile, an Obsidian vault);
    run at every Hyprland start."""
    theme = current_theme()
    if not theme:
        return 0
    status, wallpaper = still_of(current_wallpaper())
    steps = (partial(obsidian.apply, theme), partial(vesktop.apply, theme),
             partial(firefox.apply, theme, wallpaper), partial(chromium.apply, theme, wallpaper))
    return max(status, run_each(steps))


def current_theme():
    """The theme changetheme last applied, None before the first one or when it is gone."""
    marker = HYPR / "current-theme"
    name = marker.read_text().strip() if marker.exists() else ""
    return load(name) if name and (HYPR / "themes" / name / "palette.json").exists() else None


def current_wallpaper():
    marker = HYPR / "current-wallpaper"
    wallpaper = marker.read_text().strip() if marker.exists() else ""
    return wallpaper if wallpaper and Path(wallpaper).exists() else None


def delete_theme(name):
    current = current_theme()
    if current and current.name == name:
        raise ValueError("эта тема сейчас включена: сначала включи другую")
    if user_themes.is_user_theme(name):
        user_themes.delete(name)
    else:
        removed_themes.remove(name)


def wallpaper_argument(options):
    """The path after --wallpaper; None when it is missing or empty."""
    if "--wallpaper" not in options:
        return None
    rest = options[options.index("--wallpaper") + 1:]
    return rest[0] if rest and rest[0] else None


def wallpaper_play(file):
    """The wallpaper's still picture and, for an animation, the mp4 that is played: one per line."""
    print(wallpaper_still.still(file))
    if animated.is_animated(file):
        print(animated.playable(file))


def frame(file, at, out, width="0"):
    frames.frame(file, float(at), out, int(width))


def rebuilding_themes(change):
    """change, then the files that bundle every theme built again: drift, Code - OSS, Telegram and the
    battery icons follow the theme list. build's report goes to stderr: stdout carries only what change
    prints, the new theme's name."""
    def changed_and_rebuilt(*arguments):
        change(*arguments)
        with contextlib.redirect_stdout(sys.stderr):
            build()
    return changed_and_rebuilt


FILE_ERRORS = (OSError,)
ARCHIVE_ERRORS = (OSError, zipfile.BadZipFile)

COMMANDS = {
    "switch": Command(
        lambda name, *flags: switch(name, "--keep-wallpaper" in flags, "--offline" in flags),
        "<theme> [--keep-wallpaper] [--offline]",
        "changetheme's wallpaper and palette steps: picks a wallpaper, shows it (not --offline), applies the theme"),
    "apply": Command(
        lambda name, *options: apply(name, wallpaper_argument(options)),
        "<theme> [--wallpaper PATH]", "write configs for the active theme"),
    "build": Command(
        build, "",
        "regenerate what bundles every theme (drift themes, Code - OSS extension, Telegram themes, battery icons)"),
    "refresh": Command(
        refresh, "",
        "re-theme apps that appeared since the last change (Firefox profiles, Obsidian vaults); run at login"),
    "offer": Command(
        lambda name: telegram.offer(load(name)), "<theme>",
        "offer the theme to a running Telegram / AyuGram, which opens its full-screen preview"),
    "bar-preview": Command(
        printing_json(lambda name: bar_preview.preview(load(name))), "<theme>",
        "what each waybar module shows on this machine now, as JSON, for the bar in the settings window"),
    "icons": Command(
        printing_json(glyphs.all_icons), "",
        "every icon of the Nerd Font with its name, as JSON, for the icon picker in the settings window"),
    "icon-themes": Command(
        printing_json(icon_themes.listing), "",
        "installed icon themes with sample icons and the ones to install, as JSON, for the settings window"),
    "cursor-themes": Command(
        printing_json(cursor_themes.listing), "",
        "installed cursor themes with pictures of a few cursors and the ones to install, as JSON"),
    "cursor-add": Command(
        printing_json(cursor_install.install), "<file>",
        "a cursor theme from an archive or an osu! skin (.osk); prints the names installed, as JSON",
        FILE_ERRORS),
    "cursor-remove": Command(
        cursor_install.remove, "<name>", "removes a cursor theme the user added", FILE_ERRORS),
    "frame-length": Command(
        printing_json(frames.length), "<file>",
        "how long a GIF (frames) or a video (seconds) is, as JSON", FILE_ERRORS),
    "frame-prepare": Command(
        printing_json(frames.prepare), "<file>",
        "what the frame picker reads (a GIF made into an mp4), as JSON", FILE_ERRORS),
    "frame-forget": Command(
        frames.forget, "<file>", "removes a GIF's mp4 made by frame-prepare", FILE_ERRORS),
    "frame": Command(
        frame, "<file> <at> <out.png> [<width>]",
        "that moment of it as a PNG (a preview when width is given)", FILE_ERRORS),
    "wallpaper-play": Command(
        wallpaper_play, "<file>",
        "for ~/.local/bin/wallpaper: the wallpaper's still picture and, for an animation, the mp4 mpvpaper plays",
        FILE_ERRORS),
    "wallpaper-import": Command(
        printing(animated.import_into), "<file> <folder>",
        "an animation kept in folder as the mp4 it plays from; prints it", FILE_ERRORS),
    "wallpaper-needs": Command(
        printing(animated.missing_package), "",
        "the package animated wallpapers still need, or nothing", FILE_ERRORS),
    "wallpaper-engine": Command(
        printing_json(wallpaper_engine.listing), "",
        "Wallpaper Engine's subscribed wallpapers, as JSON", FILE_ERRORS),
    "wallpaper-engine-add": Command(
        printing(wallpaper_engine.add), "<id> <folder>",
        "a video one kept in folder as the mp4 it plays from; prints it", FILE_ERRORS),
    "new": Command(
        rebuilding_themes(printing(lambda label, _from, theme: user_themes.create(label, theme))),
        "<label> --from <theme>",
        "a theme of the user's own (~/.config/hypr-rice/themes): a copy of <theme> with its edits written in; "
        "prints its name", ARCHIVE_ERRORS),
    "import": Command(
        rebuilding_themes(printing(user_themes.import_archive)), "<file.zip>",
        "a theme from an archive made by export; prints its name", ARCHIVE_ERRORS),
    "export": Command(
        user_themes.export, "<theme> <file.zip>",
        "the theme with its edits written in, for someone else", ARCHIVE_ERRORS),
    "delete": Command(
        rebuilding_themes(delete_theme), "<theme>",
        "removes a theme: one of the user's own for good, one of the rice until restore", ARCHIVE_ERRORS),
    "restore": Command(
        rebuilding_themes(removed_themes.restore), "<theme>", "brings a removed theme of the rice back",
        ARCHIVE_ERRORS),
    "factory": Command(
        rebuilding_themes(factory_reset.reset), "<theme>",
        "the theme as the rice ships it: no edits, its files again", ARCHIVE_ERRORS),
    "removed-themes": Command(
        printing_json(removed_themes.listing), "", "the removed themes of the rice, as JSON"),
    "promote": Command(
        rebuilding_themes(user_themes.promote), "<theme>",
        "makes a theme of the user's own part of the rice (~/.config/hypr/themes, which sync.sh publishes)",
        ARCHIVE_ERRORS),
}


def main(argv):
    """The command's exit status; a theme that is not there is a line on stderr and 1, not a traceback."""
    try:
        return run("themegen.py", COMMANDS, argv)
    except ValueError as error:
        print(error, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
