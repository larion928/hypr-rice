#!/usr/bin/env python3
"""The game library of the games window (Alt+G, ~/.config/quickshell/games): what it lists, adds and
starts. The library is the user's own file, ~/.config/hypr-rice/games.json, which rice updates
never touch; covers picked for games are copied to ~/.local/share/hypr-rice/game-covers.

A game is one of:
  exe       a Windows program, started through Proton (proton-run, with its loading card)
  appimage  an AppImage, made executable and started as it is
  native    any other program file of this machine
  app       an installed program, by its .desktop entry (osu!, a game installed from the AUR, ...)
  steam     a game of the Steam library, started by Steam

  games.py list                 the library as JSON, most recently played first
  games.py steam                the installed Steam games as JSON (Proton and runtimes left out)
  games.py add-file PATH        adds a program file; prints the new game as JSON
  games.py add-app ID NAME ICON adds an installed program by its .desktop id
  games.py add-steam APPID NAME adds a Steam game
  games.py rename ID NAME
  games.py cover ID IMAGE       copies IMAGE as the game's cover
  games.py uncover ID           the game without a cover: its icon, or its first letter
  games.py find                 looks for a picture for each game that has none yet (the window runs it)
  games.py remove ID
  games.py launch ID            starts the game and remembers when
"""
import json
import os
import re
import secrets
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.parse
import urllib.request
from pathlib import Path

from apptheme import steam

HOME = Path.home()
LIBRARY = HOME / ".config/hypr-rice/games.json"
COVERS = HOME / ".local/share/hypr-rice/game-covers"
STEAM = steam.STEAM
# Switched on in rice → Игры: оптимизация: games run under gamemoderun. A Windows game gets it from
# proton-run, a Steam game only from its launch options in Steam (Steam starts it, not this script).
GAMEMODE_MARK = HOME / ".config/hypr-rice/gamemode"
# The Steam client added as a program is a launcher, not a game: under gamemoderun every one of its
# helpers loads gamemode's library too, and its browser part (steamwebhelper, in Steam's own container)
# then does not start: error 0x3018. Its games get GameMode from their launch options in Steam.
NOT_UNDER_GAMEMODE = ("steam", "com.valvesoftware.Steam")
WINDOWS_SUFFIXES = (".exe", ".msi", ".bat", ".lnk")
# Steam lists its own tools among the games.
STEAM_TOOLS = re.compile(r"^(Proton|Steam Linux Runtime|Steamworks Common|Steam Runtime)")


def main(argv):
    command, args = (argv[0], argv[1:]) if argv else ("", [])
    try:
        if command == "list" and not args:
            print(json.dumps(listing(), ensure_ascii=False))
        elif command == "steam" and not args:
            print(json.dumps(steam_games(), ensure_ascii=False))
        elif command == "add-file" and len(args) == 1:
            print(json.dumps(add_file(Path(args[0])), ensure_ascii=False))
        elif command == "add-app" and len(args) == 3:
            print(json.dumps(add({"kind": "app", "target": args[0], "name": args[1], "icon": args[2]}), ensure_ascii=False))
        elif command == "add-steam" and len(args) == 2:
            print(json.dumps(add({"kind": "steam", "target": args[0], "name": args[1]}), ensure_ascii=False))
        elif command == "rename" and len(args) == 2:
            change(args[0], name=args[1].strip() or game(args[0])["name"])
        elif command == "cover" and len(args) == 2:
            set_cover(args[0], Path(args[1]))
        elif command == "uncover" and len(args) == 1:
            uncover(args[0])
        elif command == "find" and not args:
            find_pictures()
        elif command == "remove" and len(args) == 1:
            remove(args[0])
        elif command == "launch" and len(args) == 1:
            launch(args[0])
        else:
            print(__doc__.strip(), file=sys.stderr)
            return 2
    except ValueError as error:
        print(error, file=sys.stderr)
        return 1
    return 0


# ---------- the library ----------

def games():
    if not LIBRARY.exists():
        return []
    try:
        return json.loads(LIBRARY.read_text())
    except ValueError:
        raise ValueError(f"{LIBRARY} не читается: поправь или удали его")


def save(library):
    LIBRARY.parent.mkdir(parents=True, exist_ok=True)
    temporary = LIBRARY.with_suffix(".tmp")
    temporary.write_text(json.dumps(library, indent=2, ensure_ascii=False) + "\n")
    temporary.replace(LIBRARY)


def game(game_id):
    for entry in games():
        if entry["id"] == game_id:
            return entry
    raise ValueError(f"нет игры {game_id}")


def add(entry):
    library = games()
    same = next((g for g in library if g["kind"] == entry["kind"] and g["target"] == entry["target"]), None)
    if same:
        return same  # added before: the same game twice is no use
    entry = {"id": secrets.token_hex(4), **entry, "added": int(time.time()), "played": 0}
    save(library + [entry])
    return entry


def change(game_id, **fields):
    library = games()
    for entry in library:
        if entry["id"] == game_id:
            entry.update(fields)
    save(library)


def remove(game_id):
    for picture in COVERS.glob(f"{game_id}*"):  # its cover and an icon found for it
        picture.unlink()
    save([entry for entry in games() if entry["id"] != game_id])


def add_file(path):
    """A program file: a Windows one, an AppImage or one of this machine. The kind from the name and
    the first bytes; the name from the file name."""
    path = path.resolve()
    if not path.is_file():
        raise ValueError(f"нет файла {path}")
    name = re.sub(r"[_.-]+", " ", path.stem).strip() or path.name
    if path.suffix.lower() in WINDOWS_SUFFIXES or path.read_bytes()[:2] == b"MZ":
        kind = "exe"
    elif path.suffix.lower() == ".appimage":
        kind = "appimage"
    elif os.access(path, os.X_OK):
        kind = "native"
    else:
        raise ValueError(f"{path.name}: не программа (нужен .exe, .AppImage или исполняемый файл)")
    return add({"kind": kind, "target": str(path), "name": name})


def set_cover(game_id, image):
    game(game_id)  # a cover for a game that is not there would be left behind
    if not image.is_file():
        raise ValueError(f"нет файла {image}")
    COVERS.mkdir(parents=True, exist_ok=True)
    for old in COVERS.glob(f"{game_id}.*"):
        old.unlink()
    target = COVERS / f"{game_id}{image.suffix.lower()}"
    shutil.copy(image, target)
    change(game_id, cover=str(target))


def uncover(game_id):
    for cover in COVERS.glob(f"{game_id}.*"):
        cover.unlink()
    change(game_id, cover="")


# ---------- pictures found by themselves ----------
# What a card shows when no cover was picked: the store's cover of a game of the very same name (a
# similar one is someone else's game: "osu!" finds only "McOsu"), else an icon: the program's
# own, an AppImage's own, a picture in the game's folder. Looked for once per game, in the background
# (the window runs games.py find); "looked" keeps a game with nothing to find from being searched again.
STORE_SEARCH = "https://store.steampowered.com/api/storesearch/?term={}&l=english&cc=us"
STORE_COVERS = ("https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/{}/library_600x900_2x.jpg",
                "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/{}/library_600x900.jpg")
FOLDER_ICONS = ("icon.png", "icon.ico", "logo.png", "icon.jpg")


def find_pictures():
    found = {}
    for entry in games():
        if entry.get("looked") or entry["kind"] == "steam":
            continue
        fields = {"looked": int(time.time())}
        if not entry.get("cover"):
            fields["cover"] = store_cover(entry)
        if not entry.get("icon") and not fields.get("cover"):
            fields["icon"] = own_icon(entry)
        found[entry["id"]] = {key: value for key, value in fields.items() if value}
    # Read again: the window may have added or renamed a game while the store was asked.
    library = games()
    for entry in library:
        entry.update(found.get(entry["id"], {}))
    save(library)


def comparable(name):
    return re.sub(r"[^0-9a-zа-яё]+", "", name.lower())


def store_cover(entry):
    """The Steam store's tall cover of the game with exactly this name, saved as the game's cover."""
    try:
        with urllib.request.urlopen(STORE_SEARCH.format(urllib.parse.quote(entry["name"])), timeout=8) as reply:
            items = json.load(reply).get("items", [])
    except (OSError, ValueError):
        return ""  # offline, or the store answered something else
    appid = next((item["id"] for item in items if comparable(item["name"]) == comparable(entry["name"])), None)
    if appid is None:
        return ""
    for url in STORE_COVERS:  # the double-size one first; older games have only the plain one
        try:
            with urllib.request.urlopen(url.format(appid), timeout=15) as reply:
                picture = reply.read()
        except OSError:
            continue
        if picture.startswith(b"\xff\xd8"):  # a JPEG, not an error page
            COVERS.mkdir(parents=True, exist_ok=True)
            target = COVERS / f"{entry['id']}.jpg"
            target.write_bytes(picture)
            return str(target)
    return ""


def own_icon(entry):
    """An AppImage's built-in icon, or a picture in the folder of a game file."""
    if entry["kind"] == "appimage":
        return appimage_icon(entry)
    if entry["kind"] in ("exe", "native"):
        folder = Path(entry["target"]).parent
        stem = Path(entry["target"]).stem
        for name in (*FOLDER_ICONS, f"{stem}.png", f"{stem}.ico"):
            if (folder / name).is_file():
                return str(folder / name)
    return ""


def appimage_icon(entry):
    """The AppImage's .DirIcon (often a link to its real icon), unpacked into the covers folder."""
    with tempfile.TemporaryDirectory() as temporary:
        try:
            extract_from_appimage(entry["target"], ".DirIcon", temporary)
            icon = Path(temporary) / "squashfs-root/.DirIcon"
            if icon.is_symlink():
                extract_from_appimage(entry["target"], os.readlink(icon), temporary)
            if not icon.exists():
                return ""
            COVERS.mkdir(parents=True, exist_ok=True)
            target = COVERS / f"{entry['id']}-icon.png"
            shutil.copy(icon.resolve(), target)
            return str(target)
        except (OSError, subprocess.SubprocessError):
            return ""


def extract_from_appimage(appimage, member, folder):
    """member of the AppImage's files into folder/squashfs-root (its runtime unpacks, nothing runs)."""
    subprocess.run([appimage, "--appimage-extract", member], cwd=folder, timeout=30,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)


# ---------- what the window shows ----------

def listing():
    """The library, each game with its cover (the one picked, or Steam's), its icon as a file and
    whether it is still there."""
    out = []
    for entry in games():
        out.append({**entry, "cover": cover_of(entry), "icon": icon_file(entry.get("icon", "")),
                     "present": present(entry)})
    return sorted(out, key=lambda entry: (-entry["played"], entry["name"].lower()))


def icon_file(icon):
    """An icon name as the file of the system's icon theme (the window's own lookup knows another
    theme: osu! is only in Papirus); a path stays as it is."""
    if not icon or icon.startswith("/"):
        return icon
    try:
        import gi
        gi.require_version("Gtk", "3.0")
        from gi.repository import Gtk
    except (ImportError, ValueError):
        return icon
    theme = Gtk.IconTheme.new()
    theme.set_custom_theme(system_icon_theme())
    found = theme.lookup_icon(icon, 256, 0)
    return found.get_filename() if found else icon


def system_icon_theme():
    current = subprocess.run(["gsettings", "get", "org.gnome.desktop.interface", "icon-theme"],
                             capture_output=True, text=True).stdout.strip().strip("'")
    return current or "Papirus-Dark"


def cover_of(entry):
    if entry.get("cover") and Path(entry["cover"]).is_file():
        return entry["cover"]
    if entry["kind"] == "steam":
        return steam_cover(entry["target"])
    return ""


def present(entry):
    if entry["kind"] in ("exe", "appimage", "native"):
        return Path(entry["target"]).is_file()
    if entry["kind"] == "app":
        return desktop_file(entry["target"]) is not None
    return steam_library_of(entry["target"]) is not None


# ---------- Steam ----------

def manifest_fields(manifest):
    text = manifest.read_text(errors="replace")
    return dict(re.findall(r'^\s*"(appid|name)"\s*"(.*)"\s*$', text, re.M))


def steam_games():
    found = {}
    for library in steam.libraries():
        for manifest in sorted((library / "steamapps").glob("appmanifest_*.acf")):
            fields = manifest_fields(manifest)
            if "appid" in fields and "name" in fields and not STEAM_TOOLS.match(fields["name"]):
                found[fields["appid"]] = {"appid": fields["appid"], "name": fields["name"],
                                          "cover": steam_cover(fields["appid"])}
    return sorted(found.values(), key=lambda entry: entry["name"].lower())


def steam_library_of(appid):
    for library in steam.libraries():
        if (library / f"steamapps/appmanifest_{appid}.acf").exists():
            return library
    return None


# Steam's own pictures of a game, the tall shelf one first. Newer Steam keeps each in a subfolder
# named by its hash, under another name.
STEAM_COVERS = ("library_600x900.jpg", "*/library_capsule.jpg", "header.jpg", "*/library_header.jpg")


def steam_cover(appid):
    folder = STEAM / "appcache/librarycache" / str(appid)
    for pattern in STEAM_COVERS:
        found = sorted(folder.glob(pattern))
        if found:
            return str(found[0])
    return ""


# ---------- starting ----------

def desktop_file(desktop_id):
    data_home = Path(os.environ.get("XDG_DATA_HOME", HOME / ".local/share"))
    data_dirs = os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":")
    for folder in [data_home, *map(Path, data_dirs)]:
        candidate = folder / "applications" / f"{desktop_id}.desktop"
        if candidate.is_file():
            return candidate
    return None


def command_for(entry):
    target = entry["target"]
    if entry["kind"] == "exe":
        return [str(HOME / ".local/bin/proton-run"), target]
    if entry["kind"] == "steam":
        return ["steam", f"steam://rungameid/{target}"]
    if entry["kind"] == "app":
        prefix = [] if target in NOT_UNDER_GAMEMODE else gamemode()
        return [*prefix, "gtk-launch", target]
    Path(target).chmod(Path(target).stat().st_mode | 0o111)
    return [*gamemode(), target]


def gamemode():
    return ["gamemoderun"] if GAMEMODE_MARK.exists() and shutil.which("gamemoderun") else []


def launch(game_id):
    entry = game(game_id)
    if not present(entry):
        raise ValueError(f"«{entry['name']}» больше нет на месте: {entry['target']}")
    folder = Path(entry["target"]).parent if entry["kind"] in ("exe", "appimage", "native") else HOME
    subprocess.Popen(command_for(entry), cwd=folder, start_new_session=True,
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    change(game_id, played=int(time.time()))


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
