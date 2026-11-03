"""The palette as GTK @define-color lines, which waybar's and histui's stylesheets import."""
from .files import GENERATED, write
from .paths import HOME, RICE_CONF


def apply(theme):
    body = "".join(f"@define-color {key:<8}{value};\n" for key, value in theme.colors.items())
    text = f"/* Палитра темы «{theme.name}». {GENERATED} */\n{body}"
    write(RICE_CONF / "waybar/wallust-colors.css", text)
    write(HOME / ".config/histui/colors.css", text)
