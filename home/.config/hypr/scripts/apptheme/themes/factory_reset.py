"""A theme back to how the rice ships it («К заводским» in the settings window): no edits from the
window, the wallpapers added there gone, and for a theme of the rice its files taken again from the
rice's copy of its repository, which undoes changes made by hand in its folder too. A theme of the
user's own has no such copy: it loses its edits and stays as it was made.
What was saved for every theme (the shared panel layout) stays: it is not this theme's."""
import shutil

from ..paths import HOME, THEMES
from .removed_themes import rice_themes
from .theme import forget_edits
from .user_themes import is_user_theme

ADDED_WALLPAPERS = HOME / ".local/share/hypr-rice/wallpapers"  # where the settings window copies them


def reset(name):
    if not (THEMES / name / "palette.json").exists():
        raise ValueError(f"нет темы «{name}»")
    forget_edits(name)
    shutil.rmtree(ADDED_WALLPAPERS / name, ignore_errors=True)
    if is_user_theme(name):
        return
    source = rice_themes() / name
    if not (source / "palette.json").exists():
        raise ValueError(f"в райсе нет темы «{name}»: правки убраны, файлы темы остались как были")
    replace_folder(THEMES / name, source)


def replace_folder(folder, source):
    """folder becomes a copy of source; a copy that fails halfway (a full disk) leaves folder as it was.
    The copy and the old folder wait beside THEMES, where no theme list looks."""
    fresh = THEMES.parent / f".{folder.name}.factory-new"
    old = THEMES.parent / f".{folder.name}.factory-old"
    for leftover in (fresh, old):  # from a run that was killed
        shutil.rmtree(leftover, ignore_errors=True)
    try:
        shutil.copytree(source, fresh)
    except BaseException:
        shutil.rmtree(fresh, ignore_errors=True)
        raise
    folder.rename(old)
    fresh.rename(folder)
    shutil.rmtree(old)
