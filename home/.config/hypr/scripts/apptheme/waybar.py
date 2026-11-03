"""waybar: config.json from the shared modules, the theme's changes and the machine's own; fonts.css
with the user's font for the theme."""
import json

from .files import write
from .paths import RICE_CONF


def deep_merge(base, over):
    out = dict(base)
    for key, value in over.items():
        out[key] = deep_merge(out[key], value) if isinstance(value, dict) and isinstance(out.get(key), dict) else value
    return out


def apply(theme):
    write_config(theme)
    write_fonts(theme)


def write_config(theme):
    # Shared modules live in config.base.json; a theme may override parts of it in waybar.json.
    base_path = RICE_CONF / "waybar/config.base.json"
    if not base_path.exists():
        return
    config = json.loads(base_path.read_text())
    over = theme.dir / "waybar.json"
    if over.exists():
        config = deep_merge(config, json.loads(over.read_text()))
    # Machine-specific bits (outputs in persistent-workspaces, ...), not part of the rice repo.
    local = RICE_CONF / "waybar/config.local.json"
    if local.exists():
        # One level deep: a module option given here replaces the shared one as a whole.
        for module, options in json.loads(local.read_text()).items():
            shared = config.get(module)
            both_tables = isinstance(options, dict) and isinstance(shared, dict)
            config[module] = {**shared, **options} if both_tables else options
    write(RICE_CONF / "waybar/config.json", json.dumps(config, indent=4, ensure_ascii=False) + "\n")


def write_fonts(theme):
    """fonts.css, which waybar-start puts after the theme's style.css: the user's main font for the
    theme, with the Nerd Font behind it for the icons. Empty while the theme's own font is used."""
    rule = ""
    if "font" in theme.chosen_fonts:
        rule = f'* {{ font-family: "{theme.font}", "JetBrainsMono Nerd Font", sans-serif; }}\n'
    write(RICE_CONF / "waybar/fonts.css", rule)
