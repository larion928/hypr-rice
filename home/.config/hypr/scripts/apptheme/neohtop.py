"""neoHtop (a source checkout in ~/neohtop): every theme as an entry in its theme list."""
from .colors import mix
from .files import GENERATED, write
from .paths import HOME


def colors_of(theme):
    # The theme's own colours, not the user's edits: the author publishes the build with these.
    colors = theme.own["colors"]
    bg, bg2, fg, muted = colors["bg"], colors["bg2"], colors["fg"], colors["muted"]
    return {
        "base": bg, "mantle": mix(bg, "#000000", 0.15), "crust": mix(bg, "#000000", 0.3),
        "text": fg, "subtext0": muted, "subtext1": mix(muted, fg, 0.4),
        "surface0": bg2, "surface1": mix(bg2, muted, 0.2), "surface2": mix(bg2, muted, 0.4),
        "overlay0": mix(muted, bg, 0.2), "overlay1": muted,
        "blue": colors["accent"], "lavender": colors["accent2"], "sapphire": colors["accent3"],
        "sky": colors["accent2"], "red": colors["crit"], "maroon": mix(colors["crit"], fg, 0.25),
        "peach": mix(colors["warn"], colors["crit"], 0.35),
        "yellow": colors["warn"], "green": colors["good"], "teal": mix(colors["good"], colors["accent2"], 0.5),
    }


def build(themes):
    repo = HOME / "neohtop"
    if not repo.exists():
        return None
    entries = []
    for theme in themes:
        entry_colors = "\n".join(f'      {key}: "{value}",' for key, value in colors_of(theme).items())
        entries.append(f'  {theme.name}: {{\n    name: "{theme.name}",\n    label: "{theme.label}",\n'
                       f'    colors: {{\n{entry_colors}\n    }},\n  }},')
    text = ("// " + GENERATED + "\n"
            'import type { Theme } from "$lib/types";\n\n'
            "export const hyprThemes: Record<string, Theme> = {\n" + "\n".join(entries) + "\n};\n")
    path = repo / "src/lib/definitions/hyprThemes.ts"
    write(path, text)
    return path
