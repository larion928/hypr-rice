"""What each waybar module shows on this machine right now, for the bar in the settings window: its
text, made from its own "format" the way waybar makes it, and whether it is on the bar at all.

  state "shown"   waybar draws it
  state "sometimes"  only at times (an empty tray, nothing playing, no updates); note says when
  state "missing" not on this machine (no battery, no sensor, a service not running); note says why
"""
import json
import os
import re
import shutil
import subprocess
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from . import waybar

POWER_SUPPLY = Path("/sys/class/power_supply")
BACKLIGHT = Path("/sys/class/backlight")
BLUETOOTH = Path("/sys/class/bluetooth")
# Seconds a module's script gets (the updates check goes online), and any other command. Every module
# is asked at once, so the slowest decides how long the settings window waits.
SCRIPT_TIMEOUT = 8
COMMAND_TIMEOUT = 3


def preview(theme):
    """{module: {"text", "state", "note"}} for every module the settings window offers."""
    config = waybar.config_for(theme)
    if isinstance(config.get("temperature"), dict):
        config["temperature"] = {**waybar.cpu_sensor(), **config["temperature"]}
    modules = waybar.layout(theme)["available"]
    with ThreadPoolExecutor(max_workers=len(modules)) as pool:
        results = pool.map(lambda module: describe(module, config.get(module) or {}), modules)
    return dict(zip(modules, results))


def describe(module, options):
    if options.get("exec"):
        return from_script(module, options, run_script(options))
    reader = READERS.get(module)
    if reader is None:
        return shown(waybar.preview(module, options))
    return reader(options)


# ---------- the result

def shown(text):
    return {"text": text, "state": "shown", "note": ""}


def sometimes(text, note):
    return {"text": text, "state": "sometimes", "note": note}


def missing(text, note):
    return {"text": text, "state": "missing", "note": note}


# ---------- formats: waybar's {placeholder} and {icon}

def render(look, values, icons=None, percent=None):
    """look with its {name} placeholders filled from values and {icon} picked from icons by percent."""
    look = look.replace("{icon}", pick_icon(icons, percent))
    return re.sub(r"\{(\w*)\}", lambda match: str(values.get(match.group(1), "")), look).strip()


def pick_icon(icons, percent):
    if isinstance(icons, dict):
        icons = icons.get("default", next(iter(icons.values()), ""))
    if isinstance(icons, str):
        return icons
    if not icons:
        return ""
    if percent is None:
        return icons[-1]
    return icons[min(len(icons) - 1, int(percent / 100 * len(icons)))]


# ---------- modules with a script

def run_script(options):
    """The script's last line, as waybar would read it; None when it takes too long."""
    command = os.path.expanduser(options["exec"])
    try:
        result = subprocess.run(["sh", "-c", command], capture_output=True, text=True, timeout=SCRIPT_TIMEOUT)
    except subprocess.TimeoutExpired:
        return None
    return result.stdout.strip().splitlines()[-1] if result.stdout.strip() else ""


def from_script(module, options, output):
    if output is None:
        return sometimes(waybar.preview(module, options), f"скрипт модуля не ответил за {SCRIPT_TIMEOUT} с")
    text = output
    if options.get("return-type") == "json" and output:
        try:
            text = json.loads(output).get("text", "")
        except ValueError:
            text = output
    if not text:
        when = {"custom/battery": "только на ноутбуке с батареей", "custom/updates": "когда есть обновления"}
        return sometimes(waybar.preview(module, options), when.get(module, "когда скрипт модуля что-то выдаёт"))
    look = options.get("format", "{}")
    return shown(render(look, {"": text}) or text)


# ---------- waybar's own modules

def read_workspaces(options):
    workspaces = hyprctl("workspaces") or []
    active = (hyprctl("activeworkspace") or {}).get("id")
    persistent = options.get("persistent-workspaces", {}).get("*", [])
    ids = sorted({workspace["id"] for workspace in workspaces if workspace["id"] > 0} | set(persistent))
    marker = options.get("format-icons", {}).get("active", "●")
    return shown(" ".join(marker if number == active else str(number) for number in ids))


def read_window(options):
    title = (hyprctl("activewindow") or {}).get("title", "")
    title = options.get("rewrite", {}).get(title, title)
    limit = options.get("max-length")
    return shown(title[:limit] if limit else title)


def read_language(options):
    keyboards = (hyprctl("devices") or {}).get("keyboards", [])
    main = next((keyboard for keyboard in keyboards if keyboard.get("main")), keyboards[0] if keyboards else {})
    layouts = main.get("layout", "us").split(",")
    index = main.get("active_layout_index", 0)
    short = layouts[index] if index < len(layouts) else layouts[0]
    return shown(render(options.get("format", "{short}"), {"short": short, "long": main.get("active_keymap", "")}))


def read_volume(options):
    output = command_output(["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"])
    if not output:
        return missing(waybar.preview("pulseaudio", options), "звук недоступен")
    volume = round(float(output.split()[1]) * 100)
    if "MUTED" in output:
        return shown(render(options.get("format-muted", "{volume}%"), {"volume": volume, "format_source": ""}))
    return shown(render(options.get("format", "{volume}%"), {"volume": volume, "format_source": ""},
                        options.get("format-icons"), volume))


def read_cpu(options):
    def sample():
        fields = [int(value) for value in Path("/proc/stat").read_text().splitlines()[0].split()[1:]]
        return fields[3] + fields[4], sum(fields)  # idle + iowait, total
    idle_before, total_before = sample()
    time.sleep(0.25)
    idle_after, total_after = sample()
    usage = round(100 * (1 - (idle_after - idle_before) / max(1, total_after - total_before)))
    return shown(render(options.get("format", "{usage}%"), {"usage": usage}, options.get("format-icons"), usage))


def read_memory(options):
    info = {line.split(":")[0]: int(line.split()[1]) for line in Path("/proc/meminfo").read_text().splitlines()}
    used = round(100 * (1 - info["MemAvailable"] / info["MemTotal"]))
    return shown(render(options.get("format", "{}%"), {"": used, "percentage": used}, options.get("format-icons"), used))


def read_temperature(options):
    folder = options.get("hwmon-path-abs")
    if folder:
        sensors = sorted(Path(folder).glob("hwmon*/" + options.get("input-filename", "temp1_input")))
        sensor = sensors[0] if sensors else None
    else:
        sensor = Path("/sys/class/thermal/thermal_zone0/temp")
    if not sensor or not sensor.exists():
        return missing(waybar.preview("temperature", options), "на этой машине не найден датчик температуры")
    celsius = round(int(sensor.read_text()) / 1000)
    critical = options.get("critical-threshold", 80)
    return shown(render(options.get("format", "{temperatureC}°C"), {"temperatureC": celsius},
                        options.get("format-icons"), min(100, 100 * celsius / critical)))


def laptop_battery():
    for supply in sorted(POWER_SUPPLY.glob("*")):
        kind = (supply / "type").read_text().strip() if (supply / "type").exists() else ""
        scope = (supply / "scope").read_text().strip() if (supply / "scope").exists() else ""
        if kind == "Battery" and scope != "Device" and (supply / "capacity").exists():
            return supply
    return None


def read_battery(options):
    battery = laptop_battery()
    if battery is None:
        return missing(waybar.preview("battery", options), "нет батареи: это не ноутбук")
    capacity = int((battery / "capacity").read_text())
    return shown(render(options.get("format", "{capacity}%"), {"capacity": capacity}, options.get("format-icons"), capacity))


def read_network(options):
    devices = [line.split(":") for line in command_output(["nmcli", "-t", "-f", "TYPE,STATE,CONNECTION", "dev"]).splitlines()]
    wifi = next((device for device in devices if device[0] == "wifi" and device[1] == "connected"), None)
    wired = next((device for device in devices if device[0] == "ethernet" and device[1] == "connected"), None)
    if wifi:
        # Without --rescan no nmcli scans for networks first, which takes seconds.
        listing = command_output(["nmcli", "-t", "-f", "IN-USE,SIGNAL", "dev", "wifi", "list", "--rescan", "no"])
        signal = next((line.split(":")[1] for line in listing.splitlines() if line.startswith("*")), "")
        return shown(render(options.get("format-wifi", "{essid}"), {"signalStrength": signal, "essid": wifi[2]}))
    if wired:
        return shown(render(options.get("format-ethernet", "{ifname}"), {"cidr": "", "ifname": wired[2]}))
    return shown(render(options.get("format-disconnected", "⚠"), {}))


def read_clock(options):
    look = options.get("format", "{:%H:%M}")
    return shown(re.sub(r"\{:([^}]*)\}", lambda match: time.strftime(match.group(1)), look))


def read_backlight(options):
    screens = sorted(BACKLIGHT.glob("*"))
    if not screens:
        return missing(waybar.preview("backlight", options), "нет подсветки экрана: обычно это ПК с монитором")
    percent = round(100 * int((screens[0] / "brightness").read_text()) / max(1, int((screens[0] / "max_brightness").read_text())))
    return shown(render(options.get("format", "{percent}%"), {"percent": percent}, options.get("format-icons"), percent))


def read_disk(options):
    usage = shutil.disk_usage(options.get("path", "/"))
    percent = round(100 * usage.used / usage.total)
    return shown(render(options.get("format", "{percentage_used}%"), {"percentage_used": percent, "percentage_free": 100 - percent}))


def read_bluetooth(options):
    if not BLUETOOTH.exists() or not any(BLUETOOTH.iterdir()):
        return missing(waybar.preview("bluetooth", options), "нет Bluetooth-адаптера")
    powered = "Powered: yes" in command_output(["bluetoothctl", "show"])
    connected = len(command_output(["bluetoothctl", "devices", "Connected"]).splitlines())
    if not powered:
        return shown(render(options.get("format-off", options.get("format", "")), {}))
    if connected:
        return shown(render(options.get("format-connected", options.get("format", "")), {"num_connections": connected}))
    return shown(render(options.get("format", ""), {}))


def read_idle_inhibitor(options):
    return shown(render(options.get("format", "{icon}"), {}, options.get("format-icons", {}).get("deactivated", "")))


def read_player(options):
    status = command_output(["playerctl", "status"])
    if status not in ("Playing", "Paused"):
        return sometimes(waybar.preview("mpris", options), "когда что-то играет")
    title = command_output(["playerctl", "metadata", "title"])
    look = options.get("format-paused" if status == "Paused" else "format", "{title}")
    values = {"title": title, "player_icon": options.get("player-icons", {}).get("default", ""),
              "status_icon": options.get("status-icons", {}).get("paused", "")}
    limit = options.get("max-length")
    text = render(look, values)
    return shown(text[:limit] if limit else text)


def read_power_profiles(options):
    if command_output(["systemctl", "is-active", "power-profiles-daemon"]) != "active":
        return missing(waybar.preview("power-profiles-daemon", options),
                       "служба power-profiles-daemon не запущена (режим питания райса — модуль «Режим питания»)")
    profile = command_output(["powerprofilesctl", "get"])
    icons = options.get("format-icons", {})
    return shown(render(options.get("format", "{icon}"), {}, icons.get(profile, icons.get("default", ""))))


def read_tray(options):
    items = command_output(["busctl", "--user", "get-property", "org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher",
                            "org.kde.StatusNotifierWatcher", "RegisteredStatusNotifierItems"])
    if items.startswith("as 0") or not items:
        return sometimes("", "когда у программ есть значки в трее; сейчас ни одного")
    return shown("")  # the settings window draws the real icons itself


READERS = {
    "hyprland/workspaces": read_workspaces, "hyprland/window": read_window, "hyprland/language": read_language,
    "pulseaudio": read_volume, "cpu": read_cpu, "memory": read_memory, "temperature": read_temperature,
    "battery": read_battery, "network": read_network, "clock": read_clock, "backlight": read_backlight,
    "disk": read_disk, "bluetooth": read_bluetooth, "idle_inhibitor": read_idle_inhibitor, "mpris": read_player,
    "power-profiles-daemon": read_power_profiles, "tray": read_tray,
}


# ---------- helpers

def hyprctl(what):
    output = command_output(["hyprctl", what, "-j"])
    try:
        return json.loads(output)
    except ValueError:
        return None


def command_output(argv):
    try:
        return subprocess.run(argv, capture_output=True, text=True, timeout=COMMAND_TIMEOUT).stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return ""
