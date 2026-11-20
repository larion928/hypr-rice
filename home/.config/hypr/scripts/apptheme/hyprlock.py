"""hyprlock: the palette and fonts as hyprlang variables, and the theme's own hyprlock.conf (a plain one
for a theme without its own)."""
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
    if not theme_conf.exists():
        # Not the last theme's: its look would come with another palette.
        write(link, PLAIN_CONF.format(header=f"# Тема «{theme.name}» без своего экрана блокировки. {GENERATED}"))
        return
    if link.exists() or link.is_symlink():
        link.unlink()
    link.symlink_to(theme_conf)


PLAIN_CONF = """{header}
source = ~/.config/hypr/hyprlock-colors.conf

general {{
    hide_cursor = true
}}

background {{
    monitor =
    path = $wallpaper
    color = $bg
    blur_passes = 3
    blur_size = 8
    brightness = 0.5
}}

label {{
    monitor =
    text = $TIME
    font_family = $display_font
    font_size = 80
    color = $fg
    position = 0, 80
    halign = center
    valign = center
}}

input-field {{
    monitor =
    size = 280, 44
    outline_thickness = 2
    rounding = 10
    outer_color = $accent
    inner_color = $bg_glass
    font_color = $fg
    font_family = $font
    placeholder_text = пароль
    fail_text = $ATTEMPTS
    check_color = $accent2
    fail_color = $crit
    capslock_color = $warn
    fade_on_empty = false
    position = 0, -60
    halign = center
    valign = center
}}
"""
