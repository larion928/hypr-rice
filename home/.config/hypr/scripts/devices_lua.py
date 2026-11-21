"""~/.config/hypr/devices.lua, the per-device input settings: one hl.device({ name = "...", key = value })
call per line, read by hyprland.lua and written by mouse-sens and rice mouse-test. Saving one setting of a
device keeps its other settings and every other line as they are."""
import json
import re
from pathlib import Path

PATH = Path.home() / ".config/hypr/devices.lua"
LINE = re.compile(r"^hl\.device\(\{(?P<body>.*)\}\)\s*$")
FIELD = re.compile(r'(\w+)\s*=\s*("(?:[^"\\]|\\.)*"|[^,]+)')


def read(path=PATH):
    """{device name: {setting: value}} of every hl.device line."""
    devices = {}
    for line in lines(path):
        settings = parse(line)
        if settings is not None and "name" in settings:
            devices[settings.pop("name")] = settings
    return devices


def save(name, settings, path=PATH):
    """Sets the given settings of one device, adding its line at the end when it has none."""
    kept = lines(path)
    for index, line in enumerate(kept):
        current = parse(line)
        if current is not None and current.pop("name", None) == name:
            kept[index] = device_line(name, current | settings)
            break
    else:
        kept.append(device_line(name, settings))
    path.write_text("\n".join(kept) + "\n")


def device_line(name, settings):
    """The hl.device call for a device: what devices.lua holds and what `hyprctl eval` applies live."""
    fields = [f"name = {json.dumps(name)}", *(f"{key} = {lua_value(value)}" for key, value in settings.items())]
    return "hl.device({ " + ", ".join(fields) + " })"


def lines(path):
    return path.read_text().splitlines() if path.exists() else []


def parse(line):
    """The settings of an hl.device line, or None for any other line (a comment, a blank)."""
    matched = LINE.match(line.strip())
    if not matched:
        return None
    return {key: python_value(raw.strip()) for key, raw in FIELD.findall(matched["body"])}


def python_value(raw):
    if raw.startswith('"'):
        return json.loads(raw)
    if raw in ("true", "false"):
        return raw == "true"
    try:
        return int(raw)
    except ValueError:
        return float(raw)


def lua_value(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, float):  # a sensitivity, set in steps of 0.05
        return f"{value:.2f}"
    if isinstance(value, int):
        return str(value)
    return json.dumps(value)
