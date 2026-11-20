#!/usr/bin/env python3
"""The rice author's publishing step: every theme of the rice as an entry in neoHtop's theme list.

neoHtop is built from a source checkout in ~/neohtop that only the author keeps; this writes
src/lib/definitions/hyprThemes.ts there. Run it by hand after the themes changed. It is not part of
`themegen.py build`, so nothing on a user's machine looks for the checkout.
"""
import sys

from apptheme.colors import mix
from apptheme.files import GENERATED, write
from apptheme.paths import HOME
from apptheme.themes.theme import all_names, load

DEFINITIONS = HOME / "neohtop/src/lib/definitions"


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


def entry_of(theme):
    colors = "\n".join(f'      {key}: "{value}",' for key, value in colors_of(theme).items())
    return (f'  {theme.name}: {{\n    name: "{theme.name}",\n    label: "{theme.label}",\n'
            f'    colors: {{\n{colors}\n    }},\n  }},')


def main():
    if not DEFINITIONS.is_dir():
        print(f"нет исходников neoHtop: {DEFINITIONS}", file=sys.stderr)
        return 1
    entries = [entry_of(load(name)) for name in all_names()]
    path = DEFINITIONS / "hyprThemes.ts"
    write(path, "// " + GENERATED + "\n"
                'import type { Theme } from "$lib/types";\n\n'
                "export const hyprThemes: Record<string, Theme> = {\n" + "\n".join(entries) + "\n};\n")
    print(path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
