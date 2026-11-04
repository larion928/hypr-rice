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
import time
from pathlib import Path

HOME = Path.home()
LIBRARY = HOME / ".config/hypr-rice/games.json"
COVERS = HOME / ".local/share/hypr-rice/game-covers"
STEAM = HOME / ".local/share/Steam"
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
    for cover in COVERS.glob(f"{game_id}.*"):
        cover.unlink()
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


# ---------- what the window shows ----------

def listing():
    """The library, each game with its cover (the one picked, or Steam's) and whether it is still there."""
    out = []
    for entry in games():
        out.append({**entry, "cover": cover_of(entry), "present": present(entry)})
    return sorted(out, key=lambda entry: (-entry["played"], entry["name"].lower()))


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

def steam_libraries():
    """The library folders Steam keeps games in (libraryfolders.vdf), the default one first."""
    vdf = STEAM / "steamapps/libraryfolders.vdf"
    folders = [STEAM]
    if vdf.exists():
        for found in re.findall(r'^\s*"path"\s*"(.*)"\s*$', vdf.read_text(errors="replace"), re.M):
            folder = Path(found)
            if folder not in folders:
                folders.append(folder)
    return [folder for folder in folders if (folder / "steamapps").is_dir()]


def manifest_fields(manifest):
    text = manifest.read_text(errors="replace")
    return dict(re.findall(r'^\s*"(appid|name)"\s*"(.*)"\s*$', text, re.M))


def steam_games():
    found = {}
    for library in steam_libraries():
        for manifest in sorted((library / "steamapps").glob("appmanifest_*.acf")):
            fields = manifest_fields(manifest)
            if "appid" in fields and "name" in fields and not STEAM_TOOLS.match(fields["name"]):
                found[fields["appid"]] = {"appid": fields["appid"], "name": fields["name"],
                                          "cover": steam_cover(fields["appid"])}
    return sorted(found.values(), key=lambda entry: entry["name"].lower())


def steam_library_of(appid):
    for library in steam_libraries():
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
    if entry["kind"] in ("appimage", "native"):
        Path(target).chmod(Path(target).stat().st_mode | 0o111)
        return [target]
    if entry["kind"] == "app":
        return ["gtk-launch", target]
    return ["steam", f"steam://rungameid/{target}"]


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
