"""Battery icon: a lightning bolt that glitches on click."""


def frames(colors, draw):
    bolt = "M13.5 2 L5 13.5 H11 L9.5 22 L19 9.5 H13 Z"
    idle = draw.svg(f'<path d="{bolt}" fill="{colors["accent"]}"/>')
    glitch = draw.svg(f'<path d="{bolt}" fill="{colors["accent2"]}" transform="translate(1.6 0)" opacity="0.85"/>'
                      f'<path d="{bolt}" fill="{colors["accent"]}" transform="translate(-1.6 0.6)" opacity="0.85"/>'
                      f'<rect x="3" y="11" width="18" height="1.4" fill="{colors["bg"]}"/>')
    return [idle, glitch]
