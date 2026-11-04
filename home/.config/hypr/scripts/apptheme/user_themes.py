"""The user's own themes: ~/.config/hypr-rice/themes/<name>, a folder rice updates never touch. Each is
reached through a link in ~/.config/hypr/themes, so every program finds it like a theme of the rice.
A theme of the rice with the same name wins: an update that brings one replaces the link with its
folder, and the user's folder stays where it is."""
import json
import re
import shutil
import sys
import tempfile
import zipfile
from pathlib import Path

from . import bake
from .paths import HOME, RICE_CONF, THEMES
from .theme import COLOR, forget_edits, load

USER_THEMES = RICE_CONF / "themes"
NEEDED_FILES = ("palette.json", "hypr.lua", "style.css")
NEEDED_COLORS = ("bg", "bg2", "fg", "accent", "accent2", "accent3", "muted", "warn", "crit", "good")
# An archive bigger than this unpacked is not a theme (wallpapers included).
MAX_UNPACKED_BYTES = 300 * 1024 * 1024


def link():
    """A link for every user theme, none left for a deleted one."""
    THEMES.mkdir(parents=True, exist_ok=True)
    for entry in THEMES.iterdir():
        if entry.is_symlink() and not entry.exists():
            entry.unlink()
    for palette in sorted(USER_THEMES.glob("*/palette.json")):
        folder = palette.parent
        target = THEMES / folder.name
        if target.is_symlink():
            if target.resolve() == folder.resolve():
                continue
            target.unlink()
        elif target.exists():
            print(f"{folder}: в райсе есть тема с тем же именем, твоя скрыта; переименуй папку", file=sys.stderr)
            continue
        target.symlink_to(folder)


def is_user_theme(name):
    return (THEMES / name).is_symlink() and (USER_THEMES / name).is_dir()


def create(label, source):
    """A new theme called label: a copy of the theme source with its edits written in. Its name."""
    name = free_name(slug(label))
    folder = USER_THEMES / name
    USER_THEMES.mkdir(parents=True, exist_ok=True)
    bake.copy_theme(THEMES / source, folder)
    bake.bake(load(source), folder)
    rename(folder, name, label)
    replace_in_text(folder, theme_path(source), theme_path(name))
    link()
    return name


def export(name, archive):
    """The theme with its edits written in, as a zip archive with the theme's folder inside."""
    with tempfile.TemporaryDirectory() as temporary:
        folder = Path(temporary) / name
        bake.copy_theme(THEMES / name, folder)
        bake.bake(load(name), folder)
        replace_in_text(folder, str(HOME), HOME_PLACEHOLDER)
        with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as out:
            for path in sorted(folder.rglob("*")):
                out.write(path, path.relative_to(folder.parent))


def import_archive(archive):
    """A theme from a zip archive made by export (or by hand: one folder with the theme's files)
    as a user theme. Its name; ValueError with the reason for an archive that is not a theme."""
    with zipfile.ZipFile(archive) as source, tempfile.TemporaryDirectory() as temporary:
        top = checked_top_folder(source)
        source.extractall(temporary)
        folder = Path(temporary) / top
        palette = check_theme(folder)
        name = free_name(slug(palette.get("name") or top))
        replace_in_text(folder, theme_path(palette.get("name") or top), theme_path(name))
        replace_in_text(folder, HOME_PLACEHOLDER, str(HOME))
        USER_THEMES.mkdir(parents=True, exist_ok=True)
        shutil.move(folder, USER_THEMES / name)
    rename(USER_THEMES / name, name, palette.get("label") or name)
    link()
    return name


def checked_top_folder(source):
    """The one folder every member of the archive is in; ValueError for anything else."""
    members = source.infolist()
    if sum(member.file_size for member in members) > MAX_UNPACKED_BYTES:
        raise ValueError("архив слишком большой для темы")
    tops = set()
    for member in members:
        path = Path(member.filename)
        if path.is_absolute() or ".." in path.parts:
            raise ValueError(f"в архиве путь за пределы темы: {member.filename}")
        tops.add(path.parts[0])
    if len(tops) != 1:
        raise ValueError("в архиве должна быть одна папка с темой")
    return tops.pop()


def check_theme(folder):
    """The theme's palette.json; ValueError when the folder misses what changetheme needs."""
    for needed in NEEDED_FILES:
        if not (folder / needed).is_file():
            raise ValueError(f"в теме нет {needed}")
    try:
        palette = json.loads((folder / "palette.json").read_text())
    except ValueError as error:
        raise ValueError(f"palette.json не читается: {error}") from error
    colors = palette.get("colors", {}) if isinstance(palette, dict) else {}
    missing = [key for key in NEEDED_COLORS if not COLOR.fullmatch(str(colors.get(key, "")))]
    if missing:
        raise ValueError("в palette.json нет цветов " + ", ".join(missing))
    if not palette.get("font") or not palette.get("display"):
        raise ValueError("в palette.json нет шрифтов")
    if not any(path.suffix.lower() in (".png", ".jpg", ".jpeg", ".webp") for path in folder.iterdir()):
        raise ValueError("в теме нет обоев")
    return palette


def delete(name):
    """Removes a user theme: its folder, its link and its edits."""
    if not is_user_theme(name):
        raise ValueError(f"«{name}» — тема райса, удалить можно только свою")
    (THEMES / name).unlink()
    shutil.rmtree(USER_THEMES / name)
    forget_edits(name)


def promote(name):
    """A user theme made a theme of the rice (for its author): its edits written in, its folder moved
    into ~/.config/hypr/themes in place of the link, where sync.sh picks it up."""
    if not is_user_theme(name):
        raise ValueError(f"«{name}» уже тема райса")
    bake.bake(load(name), USER_THEMES / name)
    (THEMES / name).unlink()
    shutil.move(USER_THEMES / name, THEMES / name)
    forget_edits(name)


# A theme's files name its own folder by full path (waybar's style.css: file:// URLs of the battery
# pictures), so a copy under another name, or on another machine, has to have them rewritten.
# An exported theme carries the rice's placeholder for the home folder, as the rice's repository does.
HOME_PLACEHOLDER = "__HOME__"
TEXT_SUFFIXES = (".css", ".qml", ".conf", ".lua", ".json", ".frag", ".py")


def theme_path(name):
    return f"/.config/hypr/themes/{name}/"


def replace_in_text(folder, old, new):
    for path in folder.rglob("*"):
        if path.suffix in TEXT_SUFFIXES and path.is_file():
            text = path.read_text()
            if old in text:
                path.write_text(text.replace(old, new))


def rename(folder, name, label):
    palette_file = folder / "palette.json"
    palette = json.loads(palette_file.read_text())
    palette.update(name=name, label=label)
    bake.write_json(palette_file, palette)


# Theme names go into file names and program settings (drift, Code - OSS, Telegram): latin only.
CYRILLIC = dict(zip("абвгдеёжзийклмнопрстуфхцчшщъыьэюя",
                    ["a", "b", "v", "g", "d", "e", "e", "zh", "z", "i", "y", "k", "l", "m", "n", "o", "p",
                     "r", "s", "t", "u", "f", "h", "ts", "ch", "sh", "sch", "", "y", "", "e", "yu", "ya"]))


def slug(label):
    latin = "".join(CYRILLIC.get(char, char) for char in label.lower())
    return re.sub(r"[^a-z0-9]+", "-", latin).strip("-") or "theme"


def free_name(name):
    candidate, number = name, 2
    while (THEMES / candidate).exists() or (THEMES / candidate).is_symlink() or (USER_THEMES / candidate).exists():
        candidate, number = f"{name}-{number}", number + 1
    return candidate
