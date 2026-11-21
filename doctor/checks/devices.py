"""The mouse, the keyboard and the sound output: settings kept for a mouse that is not the one plugged in,
keyboard layouts that differ from the config, no sound output at all, the charge of wireless devices.
Nothing here is cured unasked or asked: which mouse or layout is right is the user's to say.
The microphone is not checked: a muted or quiet one is the user's choice as often as a fault."""
import json
import sys
from pathlib import Path

from ..model import Finding, Severity

# mice.py and devices_lua.py ship with the rice, in the repo the doctor runs from.
sys.path.append(str(Path(__file__).resolve().parents[2] / "home/.config/hypr/scripts"))
import devices_lua  # noqa: E402
import mice  # noqa: E402

TITLE = "Мышь, клавиатура, звук"
MOUSE_SETTINGS = ("sensitivity", "rotation", "accel_profile")
UPOWER_KINDS = {"mouse": "мышь", "keyboard": "клавиатура", "headset": "гарнитура", "headphones": "наушники",
                "gaming-input": "геймпад"}


def detect(ctx):
    return [*mouse(ctx), *keyboard(ctx), *sound_output(ctx), *wireless_batteries(ctx)]


def mouse(ctx):
    """A plugged-in mouse without its devices.lua line, while a line exists for a mouse that is not here:
    often the same mouse, named differently by cable and by its wireless dongle."""
    configured = devices_lua.read(ctx.home / ".config/hypr/devices.lua")
    present = [pointer.name for pointer in mice.pointers(ctx.root)]
    absent = [name for name, settings in configured.items()
              if name not in present and any(key in settings for key in MOUSE_SETTINGS)]
    if not absent:
        return []
    findings = []
    for name in (pointer.name for pointer in mice.external_mice(ctx.root)):
        if name in configured:
            continue
        findings.append(Finding(
            key=f"devices:mouse-unconfigured:{name}", severity=Severity.WARNING,
            text=f"мышь {name} работает с общими настройками: своей строки в devices.lua у неё нет, "
                 f"а есть для неподключённой {', '.join(absent)}",
            hint="если это та же мышь под другим именем (по проводу и через донгл имена разные) — "
                 "mouse-sens: выбери её (Tab) и сохрани (s)"))
    return findings


def keyboard(ctx):
    if not ctx.hyprland_running():
        return []
    main = main_keyboard(ctx)
    if main is None:
        return []
    configured = devices_lua.read(ctx.home / ".config/hypr/devices.lua").get(main["name"], {})
    expected = configured.get("kb_layout") or hyprland_option(ctx, "input:kb_layout")
    if expected is not None and main["layout"] != expected:
        return [Finding(key="devices:keyboard-layouts", severity=Severity.WARNING,
                        text=f"у клавиатуры {main['name']} раскладки {main['layout']}, а в настройке {expected}",
                        hint="hyprctl reload; если не помогло — hyprctl configerrors покажет ошибку в конфиге")]
    text = f"клавиатура {main['name']}: раскладки {main['layout']}"
    if "," in main["layout"] and "grp:" not in main["options"]:
        return [Finding(key="devices:keyboard", severity=Severity.INFO,
                        text=text + ", переключение не задано в kb_options",
                        hint="если своей клавиши переключения нет — добавь, например, grp:win_space_toggle "
                             "в kb_options (hyprland.lua)")]
    return [Finding(key="devices:keyboard", severity=Severity.INFO, text=text)]


def main_keyboard(ctx):
    result = ctx.run(["hyprctl", "devices", "-j"])
    try:
        keyboards = json.loads(result.out).get("keyboards", []) if result.ok else []
    except ValueError:
        return None
    return next((board for board in keyboards if board.get("main")), None)


def hyprland_option(ctx, option):
    result = ctx.run(["hyprctl", "getoption", option, "-j"])
    try:
        return json.loads(result.out).get("str") if result.ok else None
    except ValueError:
        return None


def sound_output(ctx):
    """With PipeWire and WirePlumber running (system.py checks them), a missing default sink means there is
    nothing to play sound on."""
    if not ctx.run(["systemctl", "--user", "is-active", "pipewire.service", "wireplumber.service"]).ok:
        return []
    sink = ctx.run(["wpctl", "inspect", "@DEFAULT_AUDIO_SINK@"])
    if not sink.ok:
        return [Finding(key="devices:no-sound-output", severity=Severity.PROBLEM,
                        text="звуку некуда выводиться: ни одного устройства вывода",
                        evidence=tuple(sink.err.strip().splitlines()[:2]),
                        hint="подключи наушники или колонки; встроенный звук не виден — "
                             "посмотри wpctl status и aplay -l")]
    description = node_property(sink.lines, "node.description") or node_property(sink.lines, "node.name")
    return [Finding(key="devices:sound-output", severity=Severity.INFO, text=f"звук выводится на: {description}")]


def node_property(lines, name):
    """wpctl inspect prints `  * node.name = "..."`, the star marking the properties it shows first."""
    for line in lines:
        key, _, value = line.lstrip(" *").partition(" = ")
        if key == name:
            return value.strip().strip('"')
    return ""


def wireless_batteries(ctx):
    found = ctx.run(["upower", "-e"])
    if not found.ok:
        return []
    findings = []
    for path in found.lines:
        shown = ctx.run(["upower", "-i", path.strip()])
        kind = next((line.strip() for line in shown.lines if line.strip() in UPOWER_KINDS), None)
        details = dict(line.strip().split(":", 1) for line in shown.lines if ":" in line)
        percentage = details.get("percentage", "").strip()
        if kind is None or not percentage:
            continue
        model = details.get("model", "").strip() or path.rsplit("/", 1)[-1]
        findings.append(Finding(key=f"devices:battery:{path.strip()}", severity=Severity.INFO,
                                text=f"{UPOWER_KINDS[kind]} {model}: заряд {percentage}"))
    return findings
