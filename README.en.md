# hypr-rice

[Русский](README.md) · **English**

Hyprland (0.56, Lua config) + Quickshell + Waybar. Eight themes, each with its own palette, fonts,
window animations, lock screen, screenshot animation and shutter sound, waybar battery icon,
volume/brightness OSD and SDDM login screen. Code-OSS, AyuGram, kitty, GTK/Thunar, drift and
neoHtop follow the theme too.

![themes](docs/themes.jpg)

## Install

On a fresh Arch (or Arch-based: CachyOS, EndeavourOS, …) system, logged in as your normal user:

```sh
curl -fsSL https://raw.githubusercontent.com/larion928/hypr-rice/main/install.sh | bash
```

The installer asks everything up front and then runs unattended:

1. **sudo password**, once.
2. **Existing rice.** If another desktop is configured (`~/.config/hypr`, `waybar`, `rofi`,
   `dunst`, …) it asks first and moves it to `~/.rice-backup-<date>/`. Nothing is deleted.
3. **Programs.** A checklist (space to tick, enter to go on; nothing is ticked by default):
   browsers (Firefox, Chromium, Brave, Zen, LibreWolf, Vivaldi), AyuGram, Telegram, Discord,
   Steam, Proton for `.exe`, osu!, Prism Launcher, Claude Code, Code-OSS, OBS, LibreOffice, Happ
   and about forty more, see [`packages/apps.txt`](packages/apps.txt).
4. **Install.** Hyprland and everything the rice needs, configs, the SDDM login screen (Hyprland
   preselected), GTK theme, icons, the WhiteCat cursor, services, Fn Lock on Lenovo IdeaPads,
   the claude theme.

Reboot afterwards: the login screen comes up with Hyprland selected.

### Next to another desktop

When another rice or desktop is found (niri, KDE, GNOME, another Hyprland rice, …) the installer asks:

- **Replace.** The old configs move to `~/.rice-backup-<date>/`; Hyprland becomes the default.
- **Side by side.** Nothing of the other desktop is touched; you pick one on the login screen.
  The rice keeps its waybar and kitty configs in `~/.config/hypr-rice/`, its notification daemon
  and portal restarts run only inside Hyprland, and the other desktop keeps its `~/.config/waybar`,
  `kitty`, `mako`, `fish`. Only a foreign Hyprland config is replaced. The GTK theme (Thunar, file
  dialogs) stays shared. You may keep your own login screen; Hyprland shows up in its session list.

### When something is blocked

- **AUR unreachable** (`TLS connect error … unexpected eof`): nothing to do. AUR packages come
  prebuilt and signed from [hypr-rice-pkgs](https://github.com/larion928/hypr-rice-pkgs), which
  GitHub rebuilds weekly; anything missing there is built from the GitHub mirror of the AUR.
- **pacman mirrors stall** (`Operation too slow`): downloads are retried up to 6 times, with
  fallback mirrors from the second retry (the original list is kept as
  `/etc/pacman.d/mirrorlist.rice-backup`).

## The `rice` manager

`rice` stays installed; run it in a terminal or from the launcher (Alt+R → "Менеджер райса"):

| Command | |
|---|---|
| `rice apps` | add programs (the same checklist; installed ones start ticked) |
| `rice remove` | remove programs from the catalog |
| `rice update` | update the rice from GitHub (keeps the theme and machine files) |
| `rice upgrade` | update the system and programs, AUR included |
| `rice repair` | re-apply the SDDM login screen, GTK theme and services |
| `rice report` | write `~/rice-report.txt` for whoever helps you debug |
| `rice uninstall` | remove the rice and restore the last backup |

## Keys

| Keys | |
|---|---|
| Alt + F1 | help with every hotkey |
| Alt + Shift + T | theme picker (or `changetheme <name>`) |
| Alt + R | launcher (apps and system commands) |
| Alt + Enter | kitty |
| Alt + B | default browser |
| Alt + E | files (Thunar) |
| Print / Shift + Print | screenshot of an area or window / the whole screen |
| Super + F12 | key passthrough for VMs (QEMU windows and the like turn it on by themselves) |

Themes: `claude`, `night`, `hacker`, `cyberpunk`, `frieren`, `sakura`, `coffee`, `ocean`.

## Installer options

Environment variables before `bash`, e.g. `curl … | RICE_THEME=ocean bash`:

| Variable | |
|---|---|
| `RICE_THEME=ocean` | theme after the install |
| `RICE_APPS=steam,obs,firefox` | programs without the checklist (`all` / `none`) |
| `RICE_ASSUME=y` | answer yes to every question (unattended installs) |
| `RICE_MODE=coexist` | install side by side without asking (`replace` to replace) |
| `RICE_BRANCH=dev` | install from another branch |

## Layout

```
install.sh        bootstrap: fetches the repo and runs `rice install`
rice              the manager (install, programs, update, repair, report)
sync.sh           (author) copy the live rice into the repo, check for secrets, commit, push
packages/         base.txt (repos), aur.txt, apps.txt (program catalog)
home/             goes to ~ ; __HOME__ is replaced with your home path
system/           root helper (folder colours, SDDM), SDDM config, Fn Lock rule, package repo key
```

A theme lives in `home/.config/hypr/themes/<name>/`: `palette.json`, `ui.json`, `hypr.lua`,
`style.css` (waybar), `histui.css`, `hyprlock.conf`, `screenshot.qml`, `shutter.wav`, wallpapers.
Shared app configs are generated from the palette by `~/.config/hypr/scripts/themegen.py`.

Wallpapers belong to their authors (most come from wallhaven.cc).
