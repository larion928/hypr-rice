"""Battery icon: a cherry blossom of five notched petals. On click it turns by one petal (72°) while
a loose petal tumbles down past its right side."""
import math

PETAL = "M0 0 C-3.3 -2.2 -3.5 -6.6 -1.3 -8 L0 -6.9 L1.3 -8 C3.5 -6.6 3.3 -2.2 0 0 Z"


def frames(colors, draw):
    icons = [draw.svg(blossom(colors, 0))]
    for i in range(1, 6):
        progress = i / 5
        turned = 72 * progress * progress * (3 - 2 * progress)  # eased, one petal's turn at the end
        falling = (18.5 + 2.2 * math.sin(progress * math.pi * 2), 8 + 14 * progress, 40 + 260 * progress,
                   round(1 - 0.5 * progress, 2))
        icons.append(draw.svg(blossom(colors, turned) + falling_petal(colors, *falling)))
    return icons


def blossom(colors, rotation):
    petals = "".join(f'<path d="{PETAL}" fill="{colors["accent"]}" stroke="{colors["accent2"]}" stroke-width="0.5" '
                     f'transform="translate(11 11) rotate({rotation + k * 72})"/>' for k in range(5))
    return (petals + f'<circle cx="11" cy="11" r="1.9" fill="{colors["accent3"]}"/>'
            f'<circle cx="11" cy="11" r="0.8" fill="{colors["warn"]}"/>')


def falling_petal(colors, x, y, angle, opacity):
    return (f'<path d="{PETAL}" fill="{colors["accent"]}" opacity="{opacity}" '
            f'transform="translate({x} {y}) rotate({angle}) scale(0.5)"/>')
