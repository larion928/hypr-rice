"""Battery icon: Frieren's staff, with sparkles around it on click."""
import math


def frames(colors, draw):
    wood, metal = colors["accent3"], colors["accent2"]
    staff = (f'<line x1="6.4" y1="22.6" x2="14.6" y2="9.4" stroke="{wood}" stroke-width="1.5" stroke-linecap="round"/>'
             f'<line x1="13.5" y1="9.6" x2="15.6" y2="10.9" stroke="{metal}" stroke-width="1.6" '
             f'stroke-linecap="round"/>'
             f'<polyline points="{crook()}" fill="none" stroke="{metal}" stroke-width="1.5" '
             f'stroke-linecap="round" stroke-linejoin="round"/>'
             f'<circle cx="12.3" cy="2.6" r="0.75" fill="{metal}"/>'
             f'<circle cx="20.1" cy="2.8" r="0.75" fill="{metal}"/>'
             f'<circle cx="6.2" cy="22.9" r="0.9" fill="{metal}"/>')
    return [draw.svg(staff),
            draw.svg(staff + draw.sparkle(4.5, 4, 2.4, colors["accent2"]) + draw.sparkle(19.5, 10, 1.8, colors["fg"])),
            draw.svg(staff + draw.sparkle(21.5, 9, 2.4, colors["accent2"]) + draw.sparkle(5, 12, 1.8, colors["fg"]))]


def crook():
    """The spiral on top of the shaft, from its bottom-left winding inwards, as polyline points."""
    centre_x, centre_y = 16.2, 5.6
    points = []
    for i in range(61):
        angle = math.pi * 0.62 + i / 60 * math.pi * 3.1
        radius = 4.1 - i / 60 * 3.4
        points.append(f"{centre_x + radius * math.cos(angle):.2f},{centre_y + radius * math.sin(angle):.2f}")
    return " ".join(points)
