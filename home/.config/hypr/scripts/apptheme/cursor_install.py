"""Cursor themes added from a file in the settings window (Тема → Курсор → «Добавить из файла»): an
archive as cursor themes are shared (a folder with cursors/ and index.theme, in .tar.gz, .tar.xz,
.tar.bz2 or .zip; one archive may carry several), or an osu! skin (.osk), made into a cursor theme by
build-cursor.py as the rice's own WhiteCat is. They go to ~/.local/share/icons, where every program
looks for cursors, and can be removed from there again; the rice's WhiteCat cannot."""
import shutil
import subprocess
import tarfile
import tempfile
import zipfile
from pathlib import Path

from .paths import HOME, HYPR

USER_ICONS = HOME / ".local/share/icons"
RICE_CURSOR = "WhiteCat"
ARCHIVE_SUFFIXES = (".tar.gz", ".tgz", ".tar.xz", ".txz", ".tar.bz2", ".zip")
# A cursor archive unpacked is a few MB to tens of MB; more is not a cursor theme.
MAX_UNPACKED_BYTES = 300 * 1024 * 1024


def install(path):
    """The cursor themes in the file at path, installed; their names."""
    path = Path(path)
    if path.suffix.lower() == ".osk":
        return [from_skin(path)]
    if path.name.lower().endswith(ARCHIVE_SUFFIXES):
        return from_archive(path)
    raise ValueError(f"{path.name}: нужен архив с курсором (.tar.gz, .tar.xz, .zip) или скин osu! (.osk)")


def from_archive(path):
    with tempfile.TemporaryDirectory() as temporary:
        unpack(path, Path(temporary))
        found = sorted(cursors.parent for cursors in Path(temporary).rglob("cursors")
                       if cursors.is_dir() and any(cursors.iterdir()))
        if not found:
            raise ValueError(f"в {path.name} нет темы курсора (папки с cursors/)")
        installed = []
        for theme in found:
            # A theme packed without a folder of its own is named after the archive.
            name = archive_stem(path) if theme == Path(temporary) else theme.name
            target = USER_ICONS / name
            if target.exists():
                continue  # a theme of that name is there already; not overwritten
            USER_ICONS.mkdir(parents=True, exist_ok=True)
            shutil.copytree(theme, target, symlinks=True)
            installed.append(name)
    if not installed:
        raise ValueError("такие курсоры уже установлены: " + ", ".join(theme.name for theme in found))
    return installed


def archive_stem(archive):
    name = archive.name
    for suffix in ARCHIVE_SUFFIXES:
        if name.lower().endswith(suffix):
            return name[:-len(suffix)]
    return archive.stem


def unpack(archive, folder):
    """The archive into folder; nothing may land outside it, and nothing bigger than a cursor theme."""
    if archive.name.lower().endswith(".zip"):
        with zipfile.ZipFile(archive) as source:
            members = source.infolist()
            if sum(member.file_size for member in members) > MAX_UNPACKED_BYTES:
                raise ValueError("архив слишком большой для курсора")
            for member in members:
                name = Path(member.filename)
                if name.is_absolute() or ".." in name.parts:
                    raise ValueError(f"в архиве путь за его пределы: {member.filename}")
            source.extractall(folder)
        return
    try:
        with tarfile.open(archive) as source:
            if sum(member.size for member in source.getmembers()) > MAX_UNPACKED_BYTES:
                raise ValueError("архив слишком большой для курсора")
            # The "data" filter refuses absolute paths, ".." and links pointing out of folder.
            source.extractall(folder, filter="data")
    except (tarfile.TarError, OSError) as error:
        raise ValueError(f"архив не распаковался: {error}") from error


def from_skin(skin):
    """An osu! skin made into a cursor theme named after the skin's file."""
    name = skin.stem.strip() or "osu-cursor"
    if (USER_ICONS / name).exists():
        raise ValueError(f"курсор «{name}» уже есть")
    built = subprocess.run(["python3", str(HYPR / "scripts/build-cursor.py"), str(skin), "--name", name,
                            "--out", str(USER_ICONS)], capture_output=True, text=True)
    if built.returncode != 0:
        shutil.rmtree(USER_ICONS / name, ignore_errors=True)
        reason = (built.stderr.strip().splitlines() or ["build-cursor.py завершился с ошибкой"])[-1]
        raise ValueError(f"из скина {skin.name} курсор не собрался: {reason}")
    return name


def removable(name):
    """A cursor theme the user added: in their own icons folder, and not the rice's."""
    folder = USER_ICONS / name
    return name != RICE_CURSOR and folder.is_dir() and (folder / "cursors").is_dir()


def remove(name):
    if not removable(name):
        raise ValueError(f"«{name}» удалить нельзя: это курсор системы или райса")
    shutil.rmtree(USER_ICONS / name)
