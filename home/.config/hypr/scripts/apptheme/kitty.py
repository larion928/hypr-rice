"""kitty: the colour theme its config includes."""
import subprocess

from .colors import mix
from .files import GENERATED, write
from .paths import RICE_CONF


def apply(theme):
    colors = theme.colors
    bg, fg = colors["bg"], colors["fg"]
    ansi = [colors["bg2"], colors["crit"], colors["good"], colors["warn"],
            colors["accent"], colors["accent3"], colors["accent2"], fg]
    bright = [colors["muted"]] + [mix(color, "#ffffff", 0.22) for color in ansi[1:7]] + [mix(fg, "#ffffff", 0.5)]
    lines = [f"# Тема «{theme.name}». {GENERATED}",
             f"foreground {fg}", f"background {bg}",
             f"cursor {colors['accent']}", f"cursor_text_color {bg}",
             f"selection_foreground {fg}", f"selection_background {mix(colors['accent'], bg, 0.55)}",
             f"url_color {colors['accent2']}",
             f"active_border_color {colors['accent']}", f"inactive_border_color {colors['muted']}",
             f"active_tab_foreground {bg}", f"active_tab_background {colors['accent']}",
             f"inactive_tab_foreground {colors['muted']}", f"inactive_tab_background {colors['bg2']}",
             f"tab_bar_background {bg}", f"mark1_background {colors['accent2']}"]
    lines += [f"color{i} {color}" for i, color in enumerate(ansi + bright)]
    if "font" in theme.chosen_fonts:
        # Otherwise kitty keeps the font of its own kitty.conf.
        lines.append(f"font_family {theme.font}")
    write(RICE_CONF / "kitty/theme.conf", "\n".join(lines) + "\n")
    # kitty re-reads its config on SIGUSR1, so open windows pick the colours up at once.
    subprocess.run(["pkill", "-USR1", "-x", "kitty"], check=False)
