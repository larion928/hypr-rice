"""Battery icon: the moon. On click the crescent fills up to a full moon (frames 1..6) and wanes back
(ui.json "batteryAnim": "pingpong")."""


def frames(colors, draw):
    return [draw.svg(moon(colors, i / 6)) for i in range(7)]


def moon(colors, fullness):
    # A shadow disc (r=8) slides along the crescent's axis from 5.8 to 17 units away from the moon's
    # centre: at 17 = 9 + 8 it stops touching the moon, which is then full.
    eased = fullness * fullness * (3 - 2 * fullness)
    distance = 5.83 + eased * (17 - 5.83)
    shadow_x, shadow_y = 12 + distance * 5 / 5.83, 12 - distance * 3 / 5.83
    return (f'<defs><mask id="m"><rect width="24" height="24" fill="white"/>'
            f'<circle cx="{shadow_x:.2f}" cy="{shadow_y:.2f}" r="8" fill="black"/></mask></defs>'
            f'<circle cx="12" cy="12" r="9" fill="{colors["fg"]}" mask="url(#m)"/>')
