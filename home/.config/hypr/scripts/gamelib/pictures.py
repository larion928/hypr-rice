"""What a card shows when no cover was picked: the store's cover of a game of the very same name (a
similar one is someone else's game: "osu!" finds only "McOsu"), else an icon: the program's own, an
AppImage's own, a picture in the game's folder. Looked for once per game, in the background (the window
runs games.py find); "looked" keeps a game with nothing to find from being searched again. A game whose
search did not reach the store (offline) is not marked: the next find asks again."""
import json
import os
import re
import shutil
import subprocess
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

from .library import COVERS, games, locked, save

STORE_SEARCH = "https://store.steampowered.com/api/storesearch/?term={}&l=english&cc=us"
STORE_COVERS = ("https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/{}/library_600x900_2x.jpg",
                "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/{}/library_600x900.jpg")
FOLDER_ICONS = ("icon.png", "icon.ico", "logo.png", "icon.jpg")


def find_pictures():
    found = {}
    for entry in games():
        if entry.get("looked") or entry["kind"] == "steam":
            continue
        fields = {}
        try:
            if not entry.get("cover"):
                fields["cover"] = store_cover(entry)
            fields["looked"] = int(time.time())
        except (OSError, ValueError):
            pass  # the store did not answer: left unlooked, asked again next time; its own icon is found now
        if not entry.get("icon") and not fields.get("cover"):
            fields["icon"] = own_icon(entry)
        found[entry["id"]] = {key: value for key, value in fields.items() if value}
    # Read again: the window may have added or renamed a game while the store was asked.
    with locked():
        library = games()
        for entry in library:
            entry.update(found.get(entry["id"], {}))
        save(library)


def comparable(name):
    return re.sub(r"[^0-9a-zа-яё]+", "", name.lower())


def store_cover(entry):
    """The Steam store's tall cover of the game with exactly this name, saved as the game's cover; "" when
    the store has none. OSError when the store cannot be reached, ValueError when it answers no JSON."""
    with urllib.request.urlopen(STORE_SEARCH.format(urllib.parse.quote(entry["name"])), timeout=8) as reply:
        items = json.load(reply).get("items", [])
    appid = next((item["id"] for item in items if comparable(item["name"]) == comparable(entry["name"])), None)
    if appid is None:
        return ""
    for url in STORE_COVERS:  # the double-size one first; older games have only the plain one
        try:
            with urllib.request.urlopen(url.format(appid), timeout=15) as reply:
                picture = reply.read()
        except urllib.error.HTTPError:
            continue  # the store has not this size; a connection lost halfway goes up as OSError
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
