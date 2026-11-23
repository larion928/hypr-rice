"""Themes from the catalog, github.com/larion928/hypr-rice-themes: themes in packs, each a zip archive in
that repository's releases. The list, catalog.json, comes from a shallow clone of the repository whose
commit must be signed by the rice's author with the key rice update trusts (~/.config/hypr-rice/
allowed_signers); it names each archive's sha256 and size, so an archive is used only when it matches.
A catalog theme may carry programs (hypr.lua, battery.py, screenshot.qml): the author reads every theme
before signing it. An installed one lives with the user's own themes and is listed in INSTALLED with
the sha256 it came from, so an update knows which ones changed."""
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import zipfile
from pathlib import Path

from ..files import write
from ..paths import HOME, RICE_CONF, THEMES
from . import user_themes

REPOSITORY = os.environ.get("RICE_THEMES_REPO", "https://github.com/larion928/hypr-rice-themes.git")
CLONE = HOME / ".cache/hypr-rice/theme-catalog"
TRUST = RICE_CONF / "allowed_signers"
INSTALLED = RICE_CONF / "catalog-themes.json"


def listing():
    """The catalog's packs, each theme with its preview picture and its state here: "absent", "installed",
    "changed" (the catalog has a newer archive) or "taken" (a theme of another origin has its name)."""
    catalog = fetched()
    installed = read_installed()
    packs = []
    for pack in catalog["packs"]:
        themes = [{"name": theme["name"], "label": theme["label"], "size": theme["size"],
                   "preview": str(CLONE / theme["preview"]), "state": state(theme, installed)}
                  for theme in pack["themes"]]
        packs.append({"id": pack["id"], "label": pack["label"], "about": pack.get("about", ""), "themes": themes})
    return packs


def state(theme, installed):
    name = theme["name"]
    if name in installed:
        return "installed" if installed[name]["sha256"] == theme["sha256"] else "changed"
    return "taken" if taken(name) else "absent"


def taken(name):
    """A theme of the rice or one of the user's own has the name."""
    return (THEMES / name).exists() or (user_themes.USER_THEMES / name).exists()


def install(name):
    """The theme name, or every theme of the pack name, from the catalog; already installed ones are
    downloaded again. The names installed, one per line."""
    catalog = fetched()
    for pack in catalog["packs"]:
        if pack["id"] == name:
            for theme in pack["themes"]:
                install_theme(catalog, pack, theme)
            return
        for theme in pack["themes"]:
            if theme["name"] == name:
                install_theme(catalog, pack, theme)
                return
    raise ValueError(f'в каталоге нет темы или пака "{name}"')


def update_installed():
    """Installed catalog themes whose archive changed in the catalog, downloaded again. Without any
    installed the catalog is not even fetched."""
    installed = read_installed()
    if not installed:
        return
    catalog = fetched()
    for pack in catalog["packs"]:
        for theme in pack["themes"]:
            if theme["name"] in installed and installed[theme["name"]]["sha256"] != theme["sha256"]:
                install_theme(catalog, pack, theme)


def is_catalog_theme(name):
    return name in read_installed() and user_themes.is_user_theme(name)


def remove(name):
    """Removes an installed catalog theme with its edits; install brings it back."""
    if not is_catalog_theme(name):
        raise ValueError(f'"{name}" не из каталога')
    user_themes.delete(name)
    installed = read_installed()
    del installed[name]
    write(INSTALLED, json.dumps(installed, indent=2) + "\n")


# The catalog: a clone holding catalog.json and previews/ only (the themes' sources stay on GitHub),
# brought up to date and checked before every use.
def fetched():
    if not TRUST.is_file():
        raise ValueError(f"нет ключа автора райса ({TRUST}): выполни rice update, тогда каталог откроется")
    if not (CLONE / ".git").is_dir():
        shutil.rmtree(CLONE, ignore_errors=True)
        CLONE.parent.mkdir(parents=True, exist_ok=True)
        git(None, "clone", "-q", "--depth", "1", "--filter=blob:none", "--sparse", "--no-checkout",
            REPOSITORY, str(CLONE))
        git(CLONE, "sparse-checkout", "set", "--no-cone", "/catalog.json", "/previews/")
    git(CLONE, "fetch", "-q", "--depth", "1", "--filter=blob:none", "origin", "main")
    if not signed_by_author("FETCH_HEAD"):
        raise ValueError("каталог тем на GitHub не подписан ключом автора райса: темы не ставлю")
    git(CLONE, "checkout", "-q", "-f", "--detach", "FETCH_HEAD")
    return checked_catalog(json.loads((CLONE / "catalog.json").read_text()))


def git(where, *arguments):
    command = ["git", *(["-C", str(where)] if where else []), *arguments]
    # Never a login prompt: GitHub answers "authorization needed" for a repository that is not there.
    result = subprocess.run(command, capture_output=True, text=True, env={**os.environ, "GIT_TERMINAL_PROMPT": "0"})
    if result.returncode != 0:
        reason = result.stderr.strip() or str(result.returncode)
        if "couldn't find remote ref" in reason:
            reason = "автор его ещё не опубликовал"
        elif "could not read Username" in reason:
            reason = f"нет открытого репозитория {REPOSITORY} (аккаунт GitHub для каталога не нужен)"
        raise ValueError(f"каталог тем не скачался: {reason}")


def signed_by_author(revision):
    command = ["git", "-C", str(CLONE), "-c", "gpg.format=ssh", "-c", f"gpg.ssh.allowedSignersFile={TRUST}",
               "verify-commit", revision]
    return subprocess.run(command, capture_output=True).returncode == 0


# Names go into paths: a signed catalog with a mistake in it must not reach outside its folders.
NAME = re.compile(r"[a-z0-9][a-z0-9-]*")
ARCHIVE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]*\.zip")
PREVIEW = re.compile(r"previews/[A-Za-z0-9][A-Za-z0-9._-]*")


def checked_catalog(catalog):
    for pack in catalog["packs"]:
        for theme in pack["themes"]:
            if not (NAME.fullmatch(theme["name"]) and ARCHIVE.fullmatch(theme["archive"])
                    and PREVIEW.fullmatch(theme["preview"])):
                raise ValueError(f"в каталоге неверная запись темы: {theme}")
    return catalog


# Installing: the archive checked against the catalog, then against what a theme may hold.
def install_theme(catalog, pack, theme):
    name = theme["name"]
    if taken(name) and not is_catalog_theme(name):
        raise ValueError(f'тема "{name}" уже есть (своя или райса): переименуй свою, тогда поставлю')
    RICE_CONF.mkdir(parents=True, exist_ok=True)
    # Beside the user's themes, so the finished folder is moved in by a rename.
    with tempfile.TemporaryDirectory(dir=RICE_CONF, prefix=".catalog-") as temporary:
        archive = Path(temporary) / theme["archive"]
        print(f'Скачиваю "{theme["label"]}" ({size_text(theme["size"])})', file=sys.stderr, flush=True)
        download(catalog["archives"] + theme["archive"], theme, archive)
        folder = unpacked(archive, name, Path(temporary) / "unpacked")
        put_in_place(folder, user_themes.USER_THEMES / name)
    installed = read_installed()
    installed[name] = {"pack": pack["id"], "sha256": theme["sha256"]}
    write(INSTALLED, json.dumps(installed, indent=2) + "\n")
    user_themes.link()
    print(name)


def size_text(size):
    return f"{size // 1_000_000} МБ" if size >= 1_000_000 else f"{max(1, size // 1000)} КБ"


def download(url, theme, path):
    digest = hashlib.sha256()
    try:
        with urllib.request.urlopen(url, timeout=60) as response, path.open("wb") as out:
            while chunk := response.read(1 << 20):
                digest.update(chunk)
                out.write(chunk)
                if out.tell() > theme["size"]:
                    raise ValueError(f'архив "{theme["name"]}" больше, чем сказано в каталоге: не ставлю')
    except OSError as error:
        raise ValueError(f'архив "{theme["name"]}" не скачался: {error}') from error
    if digest.hexdigest() != theme["sha256"]:
        raise ValueError(f'архив "{theme["name"]}" не совпал с контрольной суммой каталога: не ставлю')


# What a theme folder may hold; anything else in an archive means it was not packed by the catalog.
THEME_FILE = re.compile(r"(palette\.json|ui\.json|hypr\.lua|style\.css|histui\.css|hyprlock\.conf|waybar\.json"
                        r"|battery\.py|screenshot\.qml|screen\.frag|shutter\.wav"
                        r"|[^/]+\.(png|jpg|jpeg|webp|gif|mp4)"
                        r"|assets/[^/]+\.(svg|png|jpg|webp))")


def unpacked(archive, name, into):
    """The theme folder unpacked from archive into the folder into, checked and set for this home."""
    with zipfile.ZipFile(archive) as source:
        if user_themes.checked_top_folder(source) != name:
            raise ValueError(f'в архиве "{name}" другая тема')
        for member in source.infolist():
            inside = member.filename.removeprefix(f"{name}/")
            if not member.is_dir() and not THEME_FILE.fullmatch(inside):
                raise ValueError(f'в архиве "{name}" лишний файл: {inside}')
        source.extractall(into)
    folder = into / name
    user_themes.check_theme(folder)
    user_themes.replace_in_text(folder, user_themes.HOME_PLACEHOLDER, str(HOME))
    return folder


def put_in_place(folder, target):
    """folder becomes target; the old target is kept until then, so a failure leaves it as it was."""
    old = folder.parent / "old"
    if target.exists():
        target.rename(old)
    try:
        target.parent.mkdir(parents=True, exist_ok=True)
        folder.rename(target)
    except BaseException:
        if old.exists():
            old.rename(target)
        raise


def read_installed():
    return json.loads(INSTALLED.read_text()) if INSTALLED.exists() else {}
