"""Wallpapers from Wallpaper Engine (Steam app 431960): the ones the user subscribed to in its Steam
Workshop, which Steam keeps in steamapps/workshop/content/431960/<id>/, each with a project.json
(title, type, main file, preview). A video wallpaper is added to a theme like any animated one:
converted once into the mp4 mpvpaper plays and kept with the theme's added wallpapers, so it stays
when the subscription goes. Scenes and web wallpapers are programs, not videos: listed, not added."""
import json
import re
from pathlib import Path

from . import animated, steam

APP_ID = "431960"


def listing():
    """{"installed": whether Wallpaper Engine is in a Steam library, "items": the subscribed wallpapers}."""
    return {"installed": installed(), "items": items()}


def installed():
    return any((library / f"steamapps/appmanifest_{APP_ID}.acf").exists() for library in steam.libraries())


def items():
    found = []
    for library in steam.libraries():
        for project in sorted((library / "steamapps/workshop/content" / APP_ID).glob("*/project.json")):
            item = read_item(project)
            if item:
                found.append(item)
    return sorted(found, key=lambda item: item["title"].lower())


def read_item(project):
    """One wallpaper from its project.json; None for one that does not read."""
    try:
        data = json.loads(project.read_text(errors="replace"))
    except ValueError:
        return None
    folder = project.parent
    kind = str(data.get("type", "")).lower()
    main = folder / str(data.get("file", ""))
    preview = folder / str(data.get("preview", ""))
    return {"id": folder.name, "title": str(data.get("title") or folder.name), "type": kind, "main": str(main),
            "preview": str(preview) if data.get("preview") and preview.is_file() else "",
            "addable": kind == "video" and main.is_file() and animated.is_animated(main)}


def add(item_id, folder):
    """The video wallpaper item_id kept in folder as an mp4 named after its title; the kept path."""
    item = next((item for item in items() if item["id"] == str(item_id)), None)
    if item is None:
        raise ValueError(f"обоев {item_id} нет среди подписок Wallpaper Engine")
    if not item["addable"]:
        raise ValueError(f"«{item['title']}» — не видео ({item['type'] or 'тип неизвестен'}): так пока нельзя")
    return animated.import_into(item["main"], folder, file_name(item["title"]))


def file_name(title):
    """A title as a file name: no slashes and the like, not too long."""
    return re.sub(r"[^\w .()-]+", "_", title).strip(" ._")[:80] or "wallpaper-engine"
