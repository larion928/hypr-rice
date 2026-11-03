"""drift (screensaver): every theme as a [theme.<name>] table, the current one as engine.theme."""
import re

from .colors import mix
from .files import write, without_block
from .paths import HOME

CONFIG = HOME / ".config/drift/config.toml"
BLOCK_BEGIN = "# >>> hypr themes (themegen.py) >>>"
BLOCK_END = "# <<< hypr themes (themegen.py) <<<"


def set_engine_theme(text, name):
    if re.search(r"^\[engine\]", text, re.M) is None:
        return f'[engine]\ntheme = "{name}"\n\n' + text
    engine = re.search(r"^\[engine\][^\[]*", text, re.M)
    section = engine.group(0)
    if re.search(r"^theme\s*=", section, re.M):
        new = re.sub(r'^theme\s*=.*$', f'theme = "{name}"', section, count=1, flags=re.M)
    else:
        new = section.replace("[engine]\n", f'[engine]\ntheme = "{name}"\n', 1)
    return text[:engine.start()] + new + text[engine.end():]


def apply(theme):
    text = CONFIG.read_text() if CONFIG.exists() else ""
    write(CONFIG, set_engine_theme(text, theme.name))


def build(themes):
    blocks = [BLOCK_BEGIN]
    for theme in themes:
        colors = theme.colors
        accents = [colors["accent"], colors["accent2"], colors["accent3"], colors["good"], colors["warn"]]
        dim = [mix(color, colors["bg"], 0.7) for color in accents]
        blocks.append(f"[theme.{theme.name}]")
        blocks.append(f'bright  = "{mix(colors["fg"], "#ffffff", 0.5)}"')
        blocks.append("palette = [" + ", ".join(f'"{color}"' for color in accents) + "]")
        blocks.append("dim     = [" + ", ".join(f'"{color}"' for color in dim) + "]")
        blocks.append("")
    blocks.append(BLOCK_END)
    text = CONFIG.read_text() if CONFIG.exists() else ""
    text = without_block(text, BLOCK_BEGIN, BLOCK_END)
    write(CONFIG, text.rstrip("\n") + ("\n\n" if text.strip() else "") + "\n".join(blocks) + "\n")
