"""Whether each waybar module is on the bar on this machine, for the bar in the settings window:

  state "shown"      waybar draws it
  state "sometimes"  only at times (an empty tray, nothing playing, no updates); note says when
  state "missing"    not on this machine (no battery, no sensor, a service not running); note says why
"""
import json
import os
import subprocess
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


def presence(theme):
    """{module: {"state", "note"}} for every module the settings window offers."""
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
    check = CHECKS.get(module)
    return check(options) if check else shown()


# ---------- the result

def shown():
    return {"state": "shown", "note": ""}


def sometimes(note):
    return {"state": "sometimes", "note": note}


def missing(note):
    return {"state": "missing", "note": note}


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
        return sometimes(f"скрипт модуля не ответил за {SCRIPT_TIMEOUT} с")
    text = output
    if options.get("return-type") == "json" and output:
        try:
            text = json.loads(output).get("text", "")
        except ValueError:
            text = output
    if text:
        return shown()
    when = {"custom/battery": "только на ноутбуке с батареей", "custom/updates": "когда есть обновления"}
    return sometimes(when.get(module, "когда скрипт модуля что-то выдаёт"))


# ---------- waybar's own modules that are not always there

def check_volume(options):
    if not command_output(["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]):
        return missing("звук недоступен")
    return shown()


def check_temperature(options):
    folder = options.get("hwmon-path-abs")
    if folder:
        sensors = sorted(Path(folder).glob("hwmon*/" + options.get("input-filename", "temp1_input")))
        sensor = sensors[0] if sensors else None
    else:
        sensor = Path("/sys/class/thermal/thermal_zone0/temp")
    if not sensor or not sensor.exists():
        return missing("на этой машине не найден датчик температуры")
    return shown()


def check_battery(options):
    for supply in sorted(POWER_SUPPLY.glob("*")):
        kind = (supply / "type").read_text().strip() if (supply / "type").exists() else ""
        scope = (supply / "scope").read_text().strip() if (supply / "scope").exists() else ""
        if kind == "Battery" and scope != "Device" and (supply / "capacity").exists():
            return shown()
    return missing("нет батареи: это не ноутбук")


def check_backlight(options):
    if not any(BACKLIGHT.glob("*")):
        return missing("нет подсветки экрана: обычно это ПК с монитором")
    return shown()


def check_bluetooth(options):
    if not BLUETOOTH.exists() or not any(BLUETOOTH.iterdir()):
        return missing("нет Bluetooth-адаптера")
    return shown()


def check_player(options):
    if command_output(["playerctl", "status"]) not in ("Playing", "Paused"):
        return sometimes("когда что-то играет")
    return shown()


def check_power_profiles(options):
    if command_output(["systemctl", "is-active", "power-profiles-daemon"]) != "active":
        return missing('служба power-profiles-daemon не запущена (режим питания райса: модуль "Режим питания")')
    return shown()


def check_tray(options):
    items = command_output(["busctl", "--user", "get-property", "org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher",
                            "org.kde.StatusNotifierWatcher", "RegisteredStatusNotifierItems"])
    if items.startswith("as 0") or not items:
        return sometimes("когда у программ есть значки в трее; сейчас ни одного")
    return shown()


CHECKS = {
    "pulseaudio": check_volume, "temperature": check_temperature, "battery": check_battery,
    "backlight": check_backlight, "bluetooth": check_bluetooth, "mpris": check_player,
    "power-profiles-daemon": check_power_profiles, "tray": check_tray,
}


def command_output(argv):
    try:
        return subprocess.run(argv, capture_output=True, text=True, timeout=COMMAND_TIMEOUT).stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return ""
