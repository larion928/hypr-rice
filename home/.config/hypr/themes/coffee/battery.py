"""Battery icon: a cup on a saucer; on click two wisps of steam rise and fade out."""
import math

WISP = "M0 8 C-1.3 6.6 1.3 5.4 0 4 C-1.3 2.6 1.3 1.4 0 0"


def frames(colors, draw):
    accent = colors["accent"]
    cup = (f'<path d="M4.5 11 H16.5 V14.6 C16.5 18.4 14 20 10.5 20 C7 20 4.5 18.4 4.5 14.6 Z" fill="{accent}"/>'
           f'<path d="M16.4 12.4 C20.4 12.4 20.4 17.4 16.2 17.4" fill="none" stroke="{accent}" stroke-width="1.6"/>'
           f'<ellipse cx="10.5" cy="11" rx="6" ry="1.1" fill="{colors["accent3"]}"/>'
           f'<line x1="2.8" y1="21.4" x2="18.2" y2="21.4" stroke="{colors["accent2"]}" stroke-width="1.4" '
           f'stroke-linecap="round"/>')
    icons = [draw.svg(cup)]
    for i in range(1, 6):
        first = i / 5
        second = max(0.0, first - 0.2) / 0.8  # the second wisp trails the first a little
        icons.append(draw.svg(cup + steam(colors, 8.5, 3 - 4.5 * first, first)
                              + steam(colors, 12.5, 3.5 - 4.5 * second, second)))
    return icons


def steam(colors, x, y, progress):
    """A wisp that fades in and out again as progress goes from 0 to 1."""
    opacity = round(math.sin(min(1, progress) * math.pi) * 0.95, 2)
    return (f'<path d="{WISP}" fill="none" stroke="{colors["fg"]}" stroke-width="1.2" stroke-linecap="round" '
            f'opacity="{opacity}" transform="translate({x} {y})"/>')
