"""hyprlock: the palette and fonts as hyprlang variables, and the theme's own hyprlock.conf."""
from .files import GENERATED, write
from .paths import HYPR


def apply(theme, wallpaper):
    lines = [f"# Палитра темы «{theme.name}». {GENERATED}"]
    for key, value in theme.colors.items():
        rgb_hex = value.lstrip("#")
        # hyprlang cannot append alpha to a variable, so ship the variants themes need.
        lines.append(f"${key} = rgb({rgb_hex})")
        lines.append(f"${key}_glass = rgba({rgb_hex}cc)")
        lines.append(f"${key}_soft = rgba({rgb_hex}55)")
    lines.append(f"$font = {theme.font}")
    lines.append(f"$display_font = {theme.display}")
    lines.append(f"$theme_dir = {theme.dir}")
    if wallpaper:
        lines.append(f"$wallpaper = {wallpaper}")
    else:
        # hyprlock needs some value; fall back to a screenshot of the current screen.
        lines.append("$wallpaper = screenshot")
    write(HYPR / "hyprlock-colors.conf", "\n".join(lines) + "\n")
    theme_conf = theme.dir / "hyprlock.conf"
    link = HYPR / "hyprlock.conf"
    if theme_conf.exists():
        if link.exists() or link.is_symlink():
            link.unlink()
        link.symlink_to(theme_conf)
