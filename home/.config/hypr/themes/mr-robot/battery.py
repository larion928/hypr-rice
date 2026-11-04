"""Battery icon: the pixel "f" of the fsociety logo; on click it glitches, slices pushed aside in white."""

STEADY = [
    "......XXXX..",
    ".....XX.....",
    ".....XX.....",
    "...XXXXXX...",
    ".....XX.....",
    ".....XX.....",
    ".....XX.....",
    ".....XX.....",
    ".....XX.....",
    ".....XX.....",
]
GLITCHED = [
    "......XXXX..",
    ".....XX.....",
    ".....XX.....",
    ".XXXXXX.BB..",
    ".....XX.....",
    "......XX....",
    "...BBXX.....",
    ".....XX.....",
    "....XX......",
    ".....XX.....",
]


def frames(colors, draw):
    return [draw.pixel_art(grid, colors["accent"], colors["accent2"]) for grid in (STEADY, GLITCHED)]
