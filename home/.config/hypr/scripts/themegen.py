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

Each program has its module in apptheme/.
"""
import json
import os
import sys
from pathlib import Path

from apptheme import (bar_preview, battery, chromium, css_palette, drift, firefox, gtk, hypr, hyprlock, kitty, neohtop,
                      obsidian, system, telegram, vesktop, vscode, waybar)
from apptheme.paths import HYPR
from apptheme.theme import all_names, load


def apply(name, wallpaper=None):
    theme = load(name)
    # changetheme reloads Hyprland, which drops any screen shader; keep screen-fx in sync.
    (Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp")) / "screen-fx-on").unlink(missing_ok=True)
    hypr.apply(theme)
    css_palette.apply(theme)
    waybar.apply(theme)
    kitty.apply(theme)
    hyprlock.apply(theme, wallpaper)
    gtk.apply(theme)
    drift.apply(theme)
    vscode.apply(theme)
    system.apply(theme, wallpaper)
    obsidian.apply(theme)
    vesktop.apply(theme)
    firefox.apply(theme, wallpaper)
    chromium.apply(theme, wallpaper)
    gtk.reload()


def build():
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
    elif len(argv) >= 2 and argv[0] == "bar-preview":
        print(json.dumps(bar_preview.preview(load(argv[1])), ensure_ascii=False))
    else:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    return 0


def wallpaper_argument(argv):
    """The path after --wallpaper; None when it is missing or empty."""
    if "--wallpaper" not in argv:
        return None
    rest = argv[argv.index("--wallpaper") + 1:]
    return rest[0] if rest and rest[0] else None


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
