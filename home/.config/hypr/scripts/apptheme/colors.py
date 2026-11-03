"""Colour arithmetic on "#rrggbb" strings."""


def rgb(color):
    color = color.lstrip("#")
    return tuple(int(color[i:i + 2], 16) for i in (0, 2, 4))


def to_hex(channels):
    return "#" + "".join(f"{max(0, min(255, round(v))):02x}" for v in channels)


def mix(a, b, amount):
    """amount=0 -> a, amount=1 -> b."""
    return to_hex(x + (y - x) * amount for x, y in zip(rgb(a), rgb(b)))


def with_alpha(color, opacity):
    """color as "#rrggbbaa"."""
    return f"{color}{round(opacity * 255):02x}"


def css_rgba(color, opacity):
    r, g, b = rgb(color)
    return f"rgba({r}, {g}, {b}, {opacity})"
