"""A theme back to how the rice ships it («К заводским» in the settings window): no edits from the
window, the wallpapers added there gone, and for a theme of the rice its files taken again from the
rice's copy of its repository, which undoes changes made by hand in its folder too. A theme of the
user's own has no such copy: it loses its edits and stays as it was made.
What was saved for every theme (the shared panel layout) stays: it is not this theme's."""
import shutil

from .paths import HOME, THEMES
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
    shutil.rmtree(THEMES / name)
    shutil.copytree(source, THEMES / name)
