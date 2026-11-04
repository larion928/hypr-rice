"""Themes of the rice the user removed. Their names stay in ~/.config/hypr-rice/removed-themes, which
rice reads so that an update does not bring them back; a removed theme comes back from the rice's own
copy of its repository (the folder of ~/.local/bin/rice), which rice update keeps current."""
import json
import os
import shutil
from pathlib import Path

from .paths import HOME, RICE_CONF, THEMES

REMOVED = RICE_CONF / "removed-themes"


def names():
    if not REMOVED.exists():
        return []
    return [line.strip() for line in REMOVED.read_text().splitlines() if line.strip()]


def rice_themes():
    """The themes folder of the rice's copy of its repository."""
    rice = HOME / ".local/bin/rice"
    if not rice.exists():
        raise ValueError("не найдена копия райса (~/.local/bin/rice): вернуть тему неоткуда")
    return Path(os.path.realpath(rice)).parent / "home/.config/hypr/themes"


def listing():
    """The removed themes that can come back, with the names they are shown under."""
    try:
        source = rice_themes()
    except ValueError:
        return []
    out = []
    for name in names():
        palette = source / name / "palette.json"
        if palette.exists():
            out.append({"name": name, "label": json.loads(palette.read_text()).get("label", name)})
    return out


def remove(name):
    """Removes a theme of the rice; its edits stay, for when it comes back."""
    folder = THEMES / name
    if folder.is_symlink() or not (folder / "palette.json").exists():
        raise ValueError(f"нет темы райса «{name}»")
    shutil.rmtree(folder)
    REMOVED.parent.mkdir(parents=True, exist_ok=True)
    REMOVED.write_text("".join(f"{removed}\n" for removed in [*names(), name]))


def restore(name):
    if name not in names():
        raise ValueError(f"«{name}» не удалена")
    source = rice_themes() / name
    if not (source / "palette.json").exists():
        raise ValueError(f"в райсе больше нет темы «{name}»")
    shutil.copytree(source, THEMES / name)
    REMOVED.write_text("".join(f"{removed}\n" for removed in names() if removed != name))
