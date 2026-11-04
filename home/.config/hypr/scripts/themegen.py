#!/usr/bin/env python3
"""Generate app configs from ~/.config/hypr/themes/<name>/palette.json and ui.json.

  themegen.py apply <theme> [--wallpaper PATH]   write configs for the active theme
  themegen.py build                              regenerate artifacts that bundle every theme
                                                 (drift themes, Code - OSS extension, neoHtop,
                                                 Telegram themes, battery icons)
  themegen.py refresh                            re-theme apps that appeared since the last change
                                                 (Firefox profiles, Obsidian vaults); run at login
  themegen.py offer <theme>                      offer the theme to a running Telegram / AyuGram, which
                                                 opens its full-screen preview; changetheme runs it last
  themegen.py wallpapers <theme>                 the wallpapers changetheme picks from, one per line
                                                 (the theme's own and the user's, minus those switched off)
  themegen.py bar-preview <theme>                what each waybar module shows on this machine now, as JSON,
                                                 for the bar in the settings window
  themegen.py icons                              every icon of the Nerd Font with its name, as JSON, for
                                                 the icon picker in the settings window
  themegen.py icon-themes                        installed icon themes with sample icons and the ones to
                                                 install, as JSON, for the settings window
  themegen.py cursor-themes                      installed cursor themes with pictures of a few cursors and
                                                 the ones to install, as JSON, for the settings window
  themegen.py new <label> --from <theme>         a theme of the user's own (~/.config/hypr-rice/themes):
                                                 a copy of <theme> with its edits written in; prints its name
  themegen.py import <file.zip>                  a theme from an archive made by export; prints its name
  themegen.py export <theme> <file.zip>          the theme with its edits written in, for someone else
  themegen.py delete <theme>                     removes a theme: one of the user's own for good, one of
                                                 the rice until restore (updates leave it out meanwhile)
  themegen.py restore <theme>                    brings a removed theme of the rice back
  themegen.py factory <theme>                    the theme as the rice ships it: no edits, its files again
  themegen.py removed-themes                     the removed themes of the rice, as JSON
  themegen.py promote <theme>                    makes a theme of the user's own part of the rice
                                                 (~/.config/hypr/themes, which sync.sh publishes)

Each program has its module in apptheme/.
"""
import contextlib
import json
import os
import sys
import zipfile
from pathlib import Path

from apptheme import (bar_preview, battery, chromium, css_palette, cursor_theme, cursor_themes, drift, factory_reset,
                      firefox, glyphs, gtk, hypr, hyprlock, icon_theme, icon_themes, kitty, neohtop, obsidian,
                      removed_themes, system, telegram, user_themes, vesktop, vscode, wallpaper_still, waybar,
                      windows)
from apptheme.paths import HYPR
from apptheme.theme import all_names, load


def apply(name, wallpaper=None):
    theme = load(name)
    # awww already plays an animated wallpaper; the lock and login screens and the browsers get a still.
    wallpaper = wallpaper_still.still(wallpaper) if wallpaper else None
    # changetheme reloads Hyprland, which drops any screen shader; keep screen-fx in sync.
    (Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp")) / "screen-fx-on").unlink(missing_ok=True)
    hypr.apply(theme)
    windows.apply(theme)
    css_palette.apply(theme)
    waybar.apply(theme)
    kitty.apply(theme)
    hyprlock.apply(theme, wallpaper)
    gtk.apply(theme)
    icon_theme.apply(theme)
    cursor_theme.apply(theme)
    drift.apply(theme)
    vscode.apply(theme)
    system.apply(theme, wallpaper)
    obsidian.apply(theme)
    vesktop.apply(theme)
    firefox.apply(theme, wallpaper)
    chromium.apply(theme, wallpaper)
    gtk.reload()


def build():
    user_themes.link()  # an update may have brought a theme of the same name, or the links are new
    themes = [load(name) for name in all_names()]
    drift.build(themes)
    print("vscode:", vscode.build(themes))
    print("neohtop:", neohtop.build(themes))
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
        return
    obsidian.apply(theme)
    vesktop.apply(theme)
    wallpaper = current_wallpaper()
    wallpaper = wallpaper_still.still(wallpaper) if wallpaper else None
    firefox.apply(theme, wallpaper)
    chromium.apply(theme, wallpaper)


def current_theme():
    """The theme changetheme last applied, None before the first one or when it is gone."""
    marker = HYPR / "current-theme"
    name = marker.read_text().strip() if marker.exists() else ""
    return load(name) if name and (HYPR / "themes" / name / "palette.json").exists() else None


def current_wallpaper():
    marker = HYPR / "current-wallpaper"
    wallpaper = marker.read_text().strip() if marker.exists() else ""
    return wallpaper if wallpaper and Path(wallpaper).exists() else None


def main(argv):
    if len(argv) >= 2 and argv[0] == "apply":
        apply(argv[1], wallpaper_argument(argv))
    elif argv[:1] == ["build"]:
        build()
    elif argv[:1] == ["refresh"]:
        refresh()
    elif len(argv) >= 2 and argv[0] == "offer":
        telegram.offer(load(argv[1]))
    elif len(argv) >= 2 and argv[0] == "wallpapers":
        print(*load(argv[1]).wallpapers, sep="\n")
    elif argv[:1] == ["icon-themes"]:
        print(json.dumps(icon_themes.listing(), ensure_ascii=False))
    elif argv[:1] == ["cursor-themes"]:
        print(json.dumps(cursor_themes.listing(), ensure_ascii=False))
    elif argv[:1] == ["icons"]:
        print(json.dumps(glyphs.all_icons(), ensure_ascii=False))
    elif len(argv) >= 2 and argv[0] == "bar-preview":
        print(json.dumps(bar_preview.preview(load(argv[1])), ensure_ascii=False))
    elif argv[:1] == ["removed-themes"]:
        print(json.dumps(removed_themes.listing(), ensure_ascii=False))
    elif argv[:1] in (["new"], ["import"], ["export"], ["delete"], ["restore"], ["factory"], ["promote"]):
        return manage_themes(argv)
    else:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    return 0


def manage_themes(argv):
    """Adding and removing themes: new, import, export, delete, restore, factory, promote. 1 with the reason on
    stderr when the theme or the archive does not fit."""
    command, rest = argv[0], argv[1:]
    try:
        if command == "new" and len(rest) == 3 and rest[1] == "--from":
            print(user_themes.create(rest[0], rest[2]))
        elif command == "import" and len(rest) == 1:
            print(user_themes.import_archive(rest[0]))
        elif command == "export" and len(rest) == 2:
            user_themes.export(rest[0], rest[1])
            return 0
        elif command == "delete" and len(rest) == 1:
            delete_theme(rest[0])
        elif command == "restore" and len(rest) == 1:
            removed_themes.restore(rest[0])
        elif command == "factory" and len(rest) == 1:
            factory_reset.reset(rest[0])
        elif command == "promote" and len(rest) == 1:
            user_themes.promote(rest[0])
        else:
            print(__doc__.strip(), file=sys.stderr)
            return 2
    except (ValueError, OSError, zipfile.BadZipFile) as error:
        print(error, file=sys.stderr)
        return 1
    # The theme list changed: drift, Code - OSS, Telegram and the battery icons follow it. Its report
    # goes to stderr: stdout carries only the new theme's name.
    with contextlib.redirect_stdout(sys.stderr):
        build()
    return 0


def delete_theme(name):
    current = current_theme()
    if current and current.name == name:
        raise ValueError("эта тема сейчас включена: сначала включи другую")
    if user_themes.is_user_theme(name):
        user_themes.delete(name)
    else:
        removed_themes.remove(name)


def wallpaper_argument(argv):
    """The path after --wallpaper; None when it is missing or empty."""
    if "--wallpaper" not in argv:
        return None
    rest = argv[argv.index("--wallpaper") + 1:]
    return rest[0] if rest and rest[0] else None


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
