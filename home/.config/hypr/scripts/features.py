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
import grp
import json
import os
import pwd
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

from apptheme.files import write
from command_table import Command, printing, printing_json, run

STATE = Path.home() / ".config/hypr-rice/features.json"
UFW_CONFIG = Path("/etc/ufw/ufw.conf")
UFW_RULES = Path("/etc/ufw/user.rules")


@dataclass(frozen=True)
class Feature:
    """hyprland: hyprland.lua reads it, so switching it reloads Hyprland. unit: a user unit that runs only
    while the feature is on. needs: packages it cannot work without; it is not switched on while one is
    missing (the settings window offers to install them). forget: the command that erases what the feature
    kept, run when it is switched off (not by `write`, which only makes the session follow the state).
    restarts: another feature's unit that reads this feature's state when it starts, restarted when this one
    is switched (only if it runs). experimental: still being tried out; the settings window says so. ports: what
    it has to receive from the network ("1714:1764/tcp"); groups: the system groups the user must be in ("input"
    to read the keyboard). While ufw closes a port or the user is not in a group, switching it on offers to allow
    them under one password (grant)."""
    id: str
    group: str
    name: str
    about: str
    default: bool = True
    hyprland: bool = False
    unit: str = ""
    needs: tuple = ()
    forget: tuple = ()
    restarts: str = ""
    experimental: bool = False
    ports: tuple = ()
    groups: tuple = ()


FEATURES = (
    Feature("animations", "Анимации", "Анимации окон",
            "Окна, рабочие столы и меню появляются и исчезают плавно", hyprland=True),
    Feature("shot-animation", "Анимации", "Анимация скриншота",
            "Эффект темы после снимка; без неё снимок сохраняется и экран сразу свободен"),
    Feature("shutter-sound", "Звук", "Звук затвора", "Щелчок темы, когда сделан скриншот"),
    # tesseract is in base.txt: a feature on by default has to find its packages installed.
    Feature("ocr", "Скриншоты", "Распознавание текста",
            "Alt+Shift+Print — выделить область, её текст (русский и английский) копируется в буфер",
            needs=("tesseract", "tesseract-data-rus", "tesseract-data-eng")),
    Feature("color-picker", "Скриншоты", "Пипетка",
            "Alt+Shift+C — лупа над экраном, клик копирует цвет точки как #rrggbb"),
    Feature("gestures", "Ввод", "Свайп тремя пальцами",
            "На тачпаде: три пальца влево или вправо — соседний рабочий стол; с прокруткой окон три пальца "
            "двигают ленту, а рабочий стол — четыре", hyprland=True),
    Feature("scrolling", "Окна", "Прокрутка окон",
            "Окна встают колонками в бесконечную ленту, как в niri; Alt+P — ширина колонки, Alt+Shift+P — "
            "уместить видимые колонки на экране",
            default=False, hyprland=True, experimental=True),
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
    # udiskie is in base.txt: a feature on by default has to find its package installed. Under
    # hyprland-session.target like the clipboard history.
    Feature("automount", "Устройства", "Автомонтирование USB-дисков",
            "Флешки и карты памяти подключаются сами; пока диск вставлен, его значок в трее панели "
            "(Тема → Панель → Трей); извлечь — из значка или в Thunar", unit="rice-udiskie.service", needs=("udiskie",)),
    Feature("automount-notify", "Устройства", "Уведомления о дисках",
            "Уведомление, когда диск смонтирован (с кнопкой «Открыть») или отмонтирован; работает вместе с "
            "автомонтированием",
            default=False, restarts="rice-udiskie.service"),
    # The phone finds the computer on ports 1714-1764 (KDE Connect's ufw profile). zenity is the window that
    # picks the files to send.
    Feature("kdeconnect", "Устройства", "Телефон (KDE Connect)",
            "Батарея телефона на панели (Тема → Панель → Телефон) и меню по клику: найти телефон, отправить файлы и "
            "буфер обмена, открыть файлы телефона; в Thunar — «Отправить через KDE Connect»",
            default=False, unit="rice-kdeconnect.service", needs=("kdeconnect", "sshfs", "python-gobject", "zenity"),
            ports=("1714:1764/tcp", "1714:1764/udp")),
    # Reads the keyboards (/dev/input) and types through its own virtual one (/dev/uinput): both need the input
    # group, with which any program of the user could read the keys too, so it is asked for, never assumed.
    Feature("layout-fix", "Ввод", "Исправление раскладки",
            "Alt+Shift+Пробел — последнее слово перепечатывается в другой раскладке, ещё раз — обратно; "
            "Alt+Ctrl+Пробел — выделенный текст. Нажатия не записываются: в памяти только текущее слово",
            default=False, hyprland=True, unit="rice-layout-fixer.service", groups=("input",)),
    Feature("layout-auto", "Ввод", "Автоисправление раскладки",
            "Слово, набранное не в той раскладке, исправляется само после пробела, если в другой раскладке это "
            "слово (словари русский и английский); отменить — Alt+Shift+Пробел. Не срабатывает в полноэкранных "
            "окнах; работает вместе с исправлением раскладки",
            default=False, needs=("hunspell", "hunspell-ru", "hunspell-en_us"), restarts="rice-layout-fixer.service"),
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
             "needs": list(item.needs), "missing": missing_packages(item), "experimental": item.experimental,
             "closedPorts": closed_ports(item), "missingGroups": missing_groups(item)}
            for item in FEATURES]


def shown():
    """The list as `rice features` prints it."""
    current = state()
    width = max(len(item.id) for item in FEATURES)
    lines = [f"  {'вкл ' if current[item.id] else 'выкл'}  {item.id:<{width}}  {item.name}"
             + (" (экспериментальная)" if item.experimental else "") for item in FEATURES]
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
    if item.restarts and subprocess.run(["systemctl", "--user", "try-restart", item.restarts],
                                        capture_output=True).returncode:
        print(f"systemctl --user try-restart {item.restarts} не прошёл", file=sys.stderr)
    if not on and item.forget:
        forget(item)
    if on and closed_ports(item):
        print(f"ufw не пропускает {' '.join(closed_ports(item))}: открыть — rice features grant {item.id}")
    if on and missing_groups(item):
        groups = " ".join(missing_groups(item))
        print(f"нужна группа {groups}: добавить — rice features grant {item.id}, затем перезайти")


def ufw_enabled():
    try:
        return re.search(r"^ENABLED=yes", UFW_CONFIG.read_text(), re.M) is not None
    except OSError:
        return False


def closed_ports(item):
    """The feature's ports that ufw, while it is on, does not let in: an IPv4 allow rule from anywhere for the
    port and its protocol (or any protocol), as `ufw allow 1714:1764/tcp` writes it. A rule ufw keeps in another
    form (an app profile) is not recognised: the port counts as closed, and opening it again changes nothing."""
    if not item.ports or not ufw_enabled():
        return []
    try:
        rules = UFW_RULES.read_text()
    except OSError:
        return list(item.ports)
    allowed = set(re.findall(r"^### tuple ### allow (\w+) (\S+) 0\.0\.0\.0/0 any 0\.0\.0\.0/0 in\b", rules, re.M))
    closed = []
    for port in item.ports:
        number, protocol = port.split("/")
        if (protocol, number) not in allowed and ("any", number) not in allowed:
            closed.append(port)
    return closed


def missing_groups(item):
    """The feature's groups the user is not in, as /etc/group says: right after joining one this is empty,
    though the session gets it only at the next login."""
    user = pwd.getpwuid(os.getuid())
    missing = []
    for name in item.groups:
        try:
            group = grp.getgrnam(name)
        except KeyError:
            missing.append(name)
            continue
        if user.pw_name not in group.gr_mem and user.pw_gid != group.gr_gid:
            missing.append(name)
    return missing


GRANT_SCRIPT = """user=$1; shift
for item; do
    case $item in
        port:*) ufw allow "${item#port:}" || exit ;;
        group:*) gpasswd -a "$user" "${item#group:}" || exit ;;
    esac
done"""


def grant(feature_id):
    """What the system has to allow the feature, under one administrator password (pkexec: the rice's polkit
    window): ufw allow for each closed port, gpasswd -a for each missing group."""
    item = feature(feature_id)
    asked = [f"port:{port}" for port in closed_ports(item)] + [f"group:{name}" for name in missing_groups(item)]
    if not asked:
        return 0
    user = pwd.getpwuid(os.getuid()).pw_name
    result = subprocess.run(["pkexec", "/bin/sh", "-c", GRANT_SCRIPT, "sh", user, *asked],
                            capture_output=True, text=True)
    if result.returncode:
        raise OSError(f"Не разрешено: {result.stderr.strip() or 'pkexec код ' + str(result.returncode)}")
    return 0


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
    "list": Command(printing_json(listing), "",
                    "every feature as JSON: id, group, name, about, on, needs, missing, experimental, closedPorts, "
                    "missingGroups",
                    ERRORS),
    "show": Command(printing(shown), "", "every feature and whether it is on, for a terminal", ERRORS),
    "on": Command(lambda feature_id: switch(feature_id, True), "<id>",
                  "switches the feature on; refused while a package it needs is missing", ERRORS),
    "off": Command(lambda feature_id: switch(feature_id, False), "<id>", "switches the feature off", ERRORS),
    "grant": Command(grant, "<id>", "opens the feature's ports in ufw and adds the user to its groups (asks the "
                     "password)", ERRORS),
    "is": Command(is_on, "<id>", "exit status 0 when the feature is on, 1 when it is off", ERRORS),
    "write": Command(write_all, "",
                     "writes every feature's state (new ones get their defaults) and makes the session follow it",
                     ERRORS),
}


if __name__ == "__main__":
    sys.exit(run("features.py", COMMANDS, sys.argv[1:]))
