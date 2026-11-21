#!/usr/bin/env python3
"""The rice's features the user switches on and off: Alt+F2 → Функции, or `rice features` in a terminal.
FEATURES is the list; COMMANDS is the command line.

The state is ~/.config/hypr-rice/features.json, a flat {"id": true|false} of every feature, written only
here. Each part of the rice reads it on its own: hyprland.lua parses it at every config load (so a
Hyprland feature takes effect on `hyprctl reload`), the menus watch it (common/Features.qml), and a
feature with a systemd unit has that unit enabled or disabled here. `write`, run by every rice install,
update and repair, adds the features a new version brought with their defaults and keeps the user's
choices for the others.
"""
import json
import os
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

from apptheme.files import write
from command_table import Command, printing, printing_json, run

STATE = Path.home() / ".config/hypr-rice/features.json"


@dataclass(frozen=True)
class Feature:
    """hyprland: hyprland.lua reads it, so switching it reloads Hyprland. unit: a user unit that runs only
    while the feature is on. needs: packages it cannot work without; it is not switched on while one is
    missing (the settings window offers to install them). forget: the command that erases what the feature
    kept, run when it is switched off (not by `write`, which only makes the session follow the state)."""
    id: str
    group: str
    name: str
    about: str
    default: bool = True
    hyprland: bool = False
    unit: str = ""
    needs: tuple = ()
    forget: tuple = ()


FEATURES = (
    Feature("animations", "Анимации", "Анимации окон",
            "Окна, рабочие столы и меню появляются и исчезают плавно", hyprland=True),
    Feature("shot-animation", "Анимации", "Анимация скриншота",
            "Эффект темы после снимка; без неё снимок сохраняется и экран сразу свободен"),
    Feature("shutter-sound", "Звук", "Звук затвора", "Щелчок темы, когда сделан скриншот"),
    Feature("gestures", "Ввод", "Свайп тремя пальцами",
            "На тачпаде: три пальца влево или вправо — соседний рабочий стол", hyprland=True),
    Feature("menu-blur", "Внешний вид", "Размытие под меню",
            "Фон под лаунчером, уведомлениями и другими меню размыт; без него легче видеокарте",
            hyprland=True),
    Feature("wallpaper-pause", "Обои", "Пауза анимированных обоев",
            "Обои замирают, пока их целиком закрывают полноэкранные окна: меньше нагрузка в играх и видео",
            hyprland=True),
    Feature("daily-check", "Система", "Ежедневная проверка системы",
            "rice doctor раз в день; о найденном приходит уведомление", unit="rice-doctor.timer"),
    # The unit is wanted by hyprland-session.target, which Hyprland 0.57+ starts itself (not under uwsm).
    Feature("clipboard", "Ввод", "История буфера обмена",
            "Alt+Shift+V — последние 100 скопированных записей, до 100 МБ; при выключении история стирается",
            default=False, unit="rice-clipboard.service", needs=("cliphist",), forget=("cliphist", "wipe")),
)
BY_ID = {feature.id: feature for feature in FEATURES}


def feature(feature_id):
    if feature_id not in BY_ID:
        raise ValueError(f"нет такой функции: {feature_id} (rice features — список)")
    return BY_ID[feature_id]


def state():
    """Every feature's state: the user's choice, or its default when there is none (a new feature, a file
    that is missing or does not parse). Choices of features that no longer exist are dropped."""
    try:
        saved = json.loads(STATE.read_text())
    except (OSError, ValueError):
        saved = {}
    if not isinstance(saved, dict):
        saved = {}
    return {item.id: saved[item.id] if isinstance(saved.get(item.id), bool) else item.default
            for item in FEATURES}


def missing_packages(item):
    if not item.needs:
        return []
    # pacman -T prints the ones that are not installed, and fails when there are any.
    result = subprocess.run(["pacman", "-T", *item.needs], capture_output=True, text=True)
    return result.stdout.split()


def listing():
    """Every feature as the settings window shows it."""
    current = state()
    return [{"id": item.id, "group": item.group, "name": item.name, "about": item.about, "on": current[item.id],
             "needs": list(item.needs), "missing": missing_packages(item)} for item in FEATURES]


def shown():
    """The list as `rice features` prints it."""
    current = state()
    width = max(len(item.id) for item in FEATURES)
    lines = [f"  {'вкл ' if current[item.id] else 'выкл'}  {item.id:<{width}}  {item.name}" for item in FEATURES]
    return "\n".join(lines + ["", "  rice features on|off <id>"])


def switch(feature_id, on):
    item = feature(feature_id)
    missing = missing_packages(item) if on else []
    if missing:
        raise ValueError(f"«{item.name}» не включена: нужны пакеты {' '.join(missing)}")
    current = state()
    current[item.id] = on
    save(current)
    apply([item], current)
    if not on and item.forget:
        forget(item)


def forget(item):
    """After its unit has stopped, so nothing is kept again; with the program gone there is nothing to erase."""
    try:
        subprocess.run(item.forget, capture_output=True)
    except FileNotFoundError:
        pass


def save(current):
    write(STATE, json.dumps(current, ensure_ascii=False, indent=2) + "\n")


def apply(items, current):
    """Makes the session follow current for items: their units, and Hyprland once when any of them is its."""
    for item in items:
        if item.unit:
            action = "enable" if current[item.id] else "disable"
            if subprocess.run(["systemctl", "--user", action, "--now", item.unit], capture_output=True).returncode:
                print(f"systemctl --user {action} --now {item.unit} не прошёл", file=sys.stderr)
    # Only inside a Hyprland session: an install from a TTY or another desktop has none to reload.
    if any(item.hyprland for item in items) and os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
        subprocess.run(["hyprctl", "reload"], capture_output=True)


def write_all():
    current = state()
    save(current)
    apply(FEATURES, current)


def is_on(feature_id):
    return 0 if state()[feature(feature_id).id] else 1


ERRORS = (ValueError, OSError)

COMMANDS = {
    "list": Command(printing_json(listing), "", "every feature as JSON: id, group, name, about, on, needs, missing",
                    ERRORS),
    "show": Command(printing(shown), "", "every feature and whether it is on, for a terminal", ERRORS),
    "on": Command(lambda feature_id: switch(feature_id, True), "<id>",
                  "switches the feature on; refused while a package it needs is missing", ERRORS),
    "off": Command(lambda feature_id: switch(feature_id, False), "<id>", "switches the feature off", ERRORS),
    "is": Command(is_on, "<id>", "exit status 0 when the feature is on, 1 when it is off", ERRORS),
    "write": Command(write_all, "",
                     "writes every feature's state (new ones get their defaults) and makes the session follow it",
                     ERRORS),
}


if __name__ == "__main__":
    sys.exit(run("features.py", COMMANDS, sys.argv[1:]))
