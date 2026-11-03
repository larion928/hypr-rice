"""SVG pieces the themes' battery.py draw their icons with."""


def svg(body, view="0 0 24 24"):
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{view}">{body}</svg>'


def pixel_art(grid, body, eyes):
    rects = []
    for y, row in enumerate(grid):
        for x, cell in enumerate(row):
            if cell in "XB":
                fill = body if cell == "X" else eyes
                rects.append(f'<rect x="{x}" y="{y}" width="1.02" height="1.02" fill="{fill}"/>')
    return svg("".join(rects), "0 -2 12 12")


def sparkle(x, y, radius, color):
    """A four-pointed star centred on x, y."""
    inner = radius * 0.28
    return (f'<path d="M{x} {y - radius} L{x + inner} {y - inner} L{x + radius} {y} L{x + inner} {y + inner} '
            f'L{x} {y + radius} L{x - inner} {y + inner} L{x - radius} {y} L{x - inner} {y - inner} Z" '
            f'fill="{color}"/>')

