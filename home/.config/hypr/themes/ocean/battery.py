"""Battery icon: a jellyfish. On click the bell squeezes and the whole body pushes up (frames 1..4),
then relaxes back (ui.json "batteryAnim": "pingpong")."""


def frames(colors, draw):
    return [draw.svg(jellyfish(colors, i / 4)) for i in range(5)]


def jellyfish(colors, squeeze):
    eased = squeeze * squeeze * (3 - 2 * squeeze)
    span, height, rim = 7 - 1.4 * eased, 6.5 + 1 * eased, 11.5 - 2 * eased  # bell's half width, height, bottom
    top = rim - height * 1.33
    left, right = 12 - span, 12 + span
    bell = (f'M{left:.2f} {rim:.2f} C{left:.2f} {top:.2f} {right:.2f} {top:.2f} {right:.2f} {rim:.2f} '
            f'Q{12 + span / 2:.2f} {rim + 1.3:.2f} 12 {rim:.2f} '
            f'Q{12 - span / 2:.2f} {rim + 1.3:.2f} {left:.2f} {rim:.2f} Z')
    return (f'<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1">'
            f'<stop offset="0" stop-color="{colors["accent"]}"/><stop offset="1" stop-color="{colors["accent2"]}"/>'
            f'</linearGradient></defs>'
            f'{tentacles(colors, span, rim, eased)}<path d="{bell}" fill="url(#g)" opacity="0.92"/>'
            f'<ellipse cx="12" cy="{rim - height * 0.45:.2f}" rx="{span * 0.4:.2f}" ry="{height * 0.22:.2f}" '
            f'fill="{colors["fg"]}" opacity="0.45"/>')


def tentacles(colors, span, rim, eased):
    length = 9 + 1.5 * eased
    paths = ""
    for number, offset in enumerate((-0.6, -0.2, 0.2, 0.6)):
        x = 12 + offset * span * 1.1
        sway = (1.2 - 0.8 * eased) * (1 if number % 2 else -1)
        paths += (f'<path d="M{x:.2f} {rim + 0.6:.2f} '
                  f'C{x + sway:.2f} {rim + length * 0.35:.2f} {x - sway:.2f} {rim + length * 0.65:.2f} '
                  f'{x + sway * 0.5:.2f} {rim + length:.2f}" fill="none" stroke="{colors["accent2"]}" stroke-width="1" '
                  f'stroke-linecap="round" opacity="0.85"/>')
    return paths
