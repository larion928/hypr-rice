"""Battery icon: Clawd, who waves on click."""
IDLE = ["..XXXXXXXX..", "..XXXXXXXX..", "..XBXXXXBX..", "XXXBXXXXBXXX",
        "XXXXXXXXXXXX", "..XXXXXXXX..", "..X.X..X.X..", "..X.X..X.X.."]
WAVE = ["..XXXXXXXX.X", "..XXXXXXXX.X", "..XBXXXXBXX.", "XXXBXXXXBX..",
        "XXXXXXXXXX..", "..XXXXXXXX..", "..X.X..X.X..", "..X.X..X.X.."]


def frames(colors, draw):
    return [draw.pixel_art(IDLE, colors["accent"], colors["bg"]), draw.pixel_art(WAVE, colors["accent"], colors["bg"])]
