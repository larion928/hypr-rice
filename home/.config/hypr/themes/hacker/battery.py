"""Battery icon: a terminal whose cursor blinks on click."""


def frames(colors, draw):
    accent = colors["accent"]
    screen = (f'<rect x="2" y="4" width="20" height="16" rx="1" fill="none" stroke="{accent}" stroke-width="1.6"/>'
              f'<path d="M6 9 L9.5 12 L6 15" fill="none" stroke="{accent}" stroke-width="1.8"/>')
    cursor = f'<rect x="11" y="14" width="6" height="1.8" fill="{colors["accent2"]}"/>'
    return [draw.svg(screen + cursor), draw.svg(screen)]
