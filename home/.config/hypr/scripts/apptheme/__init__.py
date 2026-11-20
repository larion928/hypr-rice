"""Theme generators for the programs hypr-rice themes; themegen.py runs them. Shared by all of them:
paths (where the rice keeps its files), files (writing generated files), colors (arithmetic on "#rrggbb"),
steam (the Steam library folders).

  themes/      a theme itself: loading it with the user's edits, the user's own themes, removed and factory ones
  apps/        one module per program outside the desktop: Firefox, Chromium, Code - OSS, Vesktop, ...
  desktop/     the Hyprland session: Hyprland, its windows, the lock screen, waybar, the battery icon, root helpers
  wallpapers/  wallpapers: animated ones and their stills, single frames, Wallpaper Engine
  cursors/     cursor themes: the one a theme sets, the installed ones, adding and removing
  icons/       icon themes and the Nerd Font's icons
"""
