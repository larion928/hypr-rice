"""The library file, ~/.config/hypr-rice/games.json: read, changed under a lock and written; the game
files and covers the user adds to it."""
import contextlib
import fcntl
import json
import os
import re
import secrets
import shutil
import time
from pathlib import Path

from apptheme.files import write

HOME = Path.home()
LIBRARY = HOME / ".config/hypr-rice/games.json"
# Held while the library is read, changed and written: the window's changes and a `find` running in the
# background would otherwise each write over the other's.
LIBRARY_LOCK = HOME / ".config/hypr-rice/games.lock"
COVERS = HOME / ".local/share/hypr-rice/game-covers"
WINDOWS_SUFFIXES = (".exe", ".msi", ".bat", ".lnk")


def games():
    if not LIBRARY.exists():
        return []
    try:
        return json.loads(LIBRARY.read_text())
    except ValueError:
        raise ValueError(f"{LIBRARY} не читается: поправь или удали его")


def save(library):
    write(LIBRARY.resolve(), json.dumps(library, indent=2, ensure_ascii=False) + "\n")


@contextlib.contextmanager
def locked():
    """The library to itself while a change is read and written (not while the store is asked)."""
    LIBRARY_LOCK.parent.mkdir(parents=True, exist_ok=True)
    with LIBRARY_LOCK.open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        yield


def game(game_id):
    for entry in games():
        if entry["id"] == game_id:
            return entry
    raise ValueError(f"нет игры {game_id}")


def add(entry):
    with locked():
        library = games()
        same = next((g for g in library if g["kind"] == entry["kind"] and g["target"] == entry["target"]), None)
        if same:
            return same  # added before: the same game twice is no use
        entry = {"id": secrets.token_hex(4), **entry, "added": int(time.time()), "played": 0}
        save(library + [entry])
        return entry


def change(game_id, **fields):
    with locked():
        library = games()
        for entry in library:
            if entry["id"] == game_id:
                entry.update(fields)
        save(library)


def rename(game_id, name):
    """A blank name keeps the old one."""
    change(game_id, name=name.strip() or game(game_id)["name"])


def remove(game_id):
    for picture in COVERS.glob(f"{game_id}*"):  # its cover and an icon found for it
        picture.unlink()
    with locked():
        save([entry for entry in games() if entry["id"] != game_id])


def add_file(path):
    """A program file: a Windows one, an AppImage or one of this machine. The kind from the name and
    the first bytes; the name from the file name."""
    path = path.resolve()
    if not path.is_file():
        raise ValueError(f"нет файла {path}")
    name = re.sub(r"[_.-]+", " ", path.stem).strip() or path.name
    if path.suffix.lower() in WINDOWS_SUFFIXES or starts_with(path, b"MZ"):
        kind = "exe"
    elif path.suffix.lower() == ".appimage":
        kind = "appimage"
    elif os.access(path, os.X_OK):
        kind = "native"
    else:
        raise ValueError(f"{path.name}: не программа (нужен .exe, .AppImage или исполняемый файл)")
    return add({"kind": kind, "target": str(path), "name": name})


def starts_with(path, magic):
    with path.open("rb") as file:
        return file.read(len(magic)) == magic


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
