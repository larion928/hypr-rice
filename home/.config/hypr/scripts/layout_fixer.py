#!/usr/bin/env python3
"""Text typed in the wrong layout (us/ru), typed again in the other one: features "layout-fix" (the keys) and
"layout-auto" (after a space, by the dictionaries). rice-layout-fixer.service runs it.

It reads the keyboards and mice (/dev/input; the input group) without taking them, and keeps the keys typed
since the last reset: a click, a change of window, Enter, an arrow, a Ctrl/Alt/Super combination or the lock
screen forget them, and nothing is written anywhere. A fix erases the last word (with the spaces after it),
switches the layout and presses the same keys again through its own virtual keyboard (/dev/uinput), so it works
in any program whatever it does with text; a second fix of the same word switches it back.
  layout-fix word        (SIGUSR1) the last word
  layout-fix selection   (SIGUSR2) the selected text (the primary selection), typed over it in the other layout
"""
import fcntl
import json
import os
import select
import signal
import socket
import struct
import subprocess
import sys
import time
from pathlib import Path

import layout_keys as keys

EVENT = struct.Struct("llHHi")  # struct input_event: time (seconds, microseconds), type, code, value
EV_SYN, EV_KEY = 0, 1
KEY_UP, KEY_DOWN, KEY_REPEAT = 0, 1, 2
SHIFTS = {keys.LEFT_SHIFT, 54}
COMBINING = {29, 97, 56, 100, 125, 126}  # Ctrl, Alt, Super, left and right
CAPS_LOCK = 58
BUTTONS = range(272, 277)  # mouse buttons: a click moves the text cursor
KEY_A, BTN_LEFT = 30, 272
# Kept at most: a word and its spaces are what is fixed, older keys only make the buffer longer.
STROKE_LIMIT = 64
# A hotkey is a combination, which resets the buffer before its request arrives: the buffer as it was just
# before still counts this long.
HOTKEY_GRACE_S = 1.0
# Keyboards plugged in later are looked for this often.
RESCAN_S = 5
# Time for Hyprland to switch the layout before the keys come, and between two keys of the virtual keyboard.
SWITCH_PAUSE_S = 0.05
KEY_PAUSE_S = 0.004
VIRTUAL_NAME = "rice-layout-fixer"
SETTINGS = Path.home() / ".config/hypr-rice/layout-fix.json"


class Strokes:
    """The keys typed since the last reset, as (code, shifted)."""

    def __init__(self):
        self.keys = []

    def add(self, stroke):
        self.keys = (self.keys + [stroke])[-STROKE_LIMIT:]

    def backspace(self):
        if self.keys:
            self.keys.pop()

    def reset(self):
        self.keys = []

    def tail(self):
        """The last word and the spaces typed after it."""
        end = len(self.keys)
        start = end
        while start > 0 and self.keys[start - 1][0] == keys.SPACE:
            start -= 1
        while start > 0 and self.keys[start - 1][0] != keys.SPACE:
            start -= 1
        return self.keys[start:end]

    def finished_word(self):
        """The word a space just ended, without that space; [] when the last key is not a space after a word."""
        if len(self.keys) < 2 or self.keys[-1][0] != keys.SPACE:
            return []
        word = self.keys[:-1]
        start = len(word)
        while start > 0 and word[start - 1][0] != keys.SPACE:
            start -= 1
        return word[start:]


class Speller:
    """hunspell -a for one dictionary, kept running: a line per word, "*", "+" or "-" when it is a word."""

    def __init__(self, dictionary):
        self.process = subprocess.Popen(["hunspell", "-a", "-i", "utf-8", "-d", dictionary], stdin=subprocess.PIPE,
                                        stdout=subprocess.PIPE, text=True, encoding="utf-8")
        self.process.stdout.readline()  # the version banner

    def knows(self, word):
        # "^" keeps a word that starts with a hunspell command character a word.
        self.process.stdin.write("^" + word + "\n")
        self.process.stdin.flush()
        answers = []
        while (line := self.process.stdout.readline().rstrip("\n")) != "":
            answers.append(line)
        return bool(answers) and answers[0][:1] in "*+-"


class Session:
    """Hyprland as hyprctl shows it: the layouts, the active one, the active window; and whether the screen is
    locked (hyprlock running)."""

    def __init__(self):
        self.locked_checked = 0.0
        self.locked_now = False

    def hyprctl(self, *args):
        return subprocess.run(["hyprctl", *args], capture_output=True, text=True, timeout=5).stdout

    def layouts(self):
        return json.loads(self.hyprctl("getoption", "input:kb_layout", "-j")).get("str", "").split(",")

    def layout(self):
        """The active layout's name ("us", "ru"), from the main keyboard."""
        keyboards = json.loads(self.hyprctl("devices", "-j")).get("keyboards", [])
        main = next((keyboard for keyboard in keyboards if keyboard.get("main")), None)
        index = main.get("active_layout_index", 0) if main else 0
        layouts = self.layouts()
        return layouts[index] if index < len(layouts) else layouts[0]

    def switch(self, layout):
        subprocess.run(["hyprctl", "switchxkblayout", "all", str(self.layouts().index(layout))],
                       capture_output=True, timeout=5)

    def window(self):
        """The active window's class and whether it is fullscreen."""
        window = json.loads(self.hyprctl("activewindow", "-j") or "{}")
        return window.get("class", ""), bool(window.get("fullscreen"))

    def locked(self):
        now = time.monotonic()
        if now - self.locked_checked > 1:
            self.locked_checked = now
            self.locked_now = any(self.comm(pid) == "hyprlock" for pid in os.listdir("/proc") if pid.isdigit())
        return self.locked_now

    @staticmethod
    def comm(pid):
        try:
            return Path(f"/proc/{pid}/comm").read_text().strip()
        except OSError:
            return ""


class VirtualKeyboard:
    """A keyboard of its own on /dev/uinput, which presses the keys of a fix."""
    UI_SET_EVBIT = 0x40045564
    UI_SET_KEYBIT = 0x40045565
    UI_DEV_CREATE = 0x5501
    USER_DEV = struct.Struct("80sHHHHi256i")  # struct uinput_user_dev, the legacy setup

    def __init__(self, device="/dev/uinput"):
        self.fd = os.open(device, os.O_WRONLY | os.O_NONBLOCK)
        fcntl.ioctl(self.fd, self.UI_SET_EVBIT, EV_KEY)
        for code in {*keys.TYPING_KEYS, keys.BACKSPACE, keys.LEFT_SHIFT}:
            fcntl.ioctl(self.fd, self.UI_SET_KEYBIT, code)
        os.write(self.fd, self.USER_DEV.pack(VIRTUAL_NAME.encode(), 0x06, 0x1, 0x1, 1, 0, *[0] * 256))
        fcntl.ioctl(self.fd, self.UI_DEV_CREATE)

    def send(self, code, value):
        os.write(self.fd, EVENT.pack(0, 0, EV_KEY, code, value) + EVENT.pack(0, 0, EV_SYN, 0, 0))
        time.sleep(KEY_PAUSE_S)

    def tap(self, code, shifted=False):
        if shifted:
            self.send(keys.LEFT_SHIFT, KEY_DOWN)
        self.send(code, KEY_DOWN)
        self.send(code, KEY_UP)
        if shifted:
            self.send(keys.LEFT_SHIFT, KEY_UP)


class Fixer:
    """What the keys mean for the buffer, and the fixes. session, keyboard and speller are Session,
    VirtualKeyboard and a {layout: Speller} (None without layout-auto)."""

    def __init__(self, session, keyboard, spellers, excluded=()):
        self.session = session
        self.keyboard = keyboard
        self.spellers = spellers
        self.excluded = set(excluded)
        self.strokes = Strokes()
        self.held = set()        # modifier keys held now
        self.before_combination = ([], 0.0)
        self.request = None      # "word" or "selection", carried out once the modifiers are up

    def key(self, code, value):
        if code in SHIFTS | COMBINING and value == KEY_UP:
            self.held.discard(code)
        elif code in SHIFTS | COMBINING:
            self.held.add(code)
        elif value != KEY_UP and code != CAPS_LOCK:
            self.pressed(code)
        if self.request and not self.held:
            self.carry_out()

    def pressed(self, code):
        if self.held & COMBINING:
            self.before_combination = (self.strokes.keys, time.monotonic())
            self.strokes.reset()
        elif self.session.locked():
            self.strokes.reset()
        elif code == keys.BACKSPACE:
            self.strokes.backspace()
        elif (code, False) in keys.CHARACTERS["us"]:
            self.strokes.add((code, bool(self.held & SHIFTS)))
            if code == keys.SPACE and self.spellers:
                self.check_finished_word()
        else:
            self.strokes.reset()

    def reset(self):
        """A click or another window: the text cursor may be anywhere now."""
        self.strokes.reset()

    def ask(self, request):
        kept, at = self.before_combination
        if not self.strokes.keys and time.monotonic() - at < HOTKEY_GRACE_S:
            self.strokes.keys = kept
        self.request = request
        if not self.held:
            self.carry_out()

    def carry_out(self):
        request, self.request = self.request, None
        if self.session.locked():
            return
        if request == "word":
            self.retype(self.strokes.tail())
        elif request == "selection":
            self.retype_selection()

    def retype(self, strokes):
        """Erases the strokes, switches the layout and types them again: a word in the other layout."""
        if all(code == keys.SPACE for code, _ in strokes):
            return
        target = keys.other(self.session.layout())
        for _ in strokes:
            self.keyboard.tap(keys.BACKSPACE)
        self.switch(target)
        for code, shifted in strokes:
            self.keyboard.tap(code, shifted)

    def retype_selection(self):
        text = subprocess.run(["wl-paste", "--primary", "--no-newline"], capture_output=True, text=True).stdout
        source = keys.layout_of(text)
        strokes = keys.strokes_for(source, text)
        if not text or strokes is None:
            return
        self.strokes.reset()
        self.switch(keys.other(source))
        for code, shifted in strokes:
            self.keyboard.tap(code, shifted)

    def switch(self, layout):
        self.session.switch(layout)
        time.sleep(SWITCH_PAUSE_S)

    def check_finished_word(self):
        word = self.strokes.finished_word()
        if not self.wrong_layout(word):
            return
        window_class, fullscreen = self.session.window()
        if not fullscreen and window_class not in self.excluded:
            self.retype(self.strokes.tail())

    def wrong_layout(self, word):
        """A word of two letters or more that is no word in the layout it was typed in, and is one in the other."""
        if len(word) < 2 or any(code in keys.DIGIT_KEYS and not shifted for code, shifted in word):
            return False
        current = self.session.layout()
        typed = keys.typed(current, word).strip(".,;:!?\"'()")
        meant = keys.typed(keys.other(current), word).strip(".,;:!?\"'()")
        if len(typed) < 2 or not typed.isalpha() or not meant.isalpha():
            return False
        return not self.spellers[current].knows(typed) and self.spellers[keys.other(current)].knows(meant)


class Inputs:
    """The keyboards and mice under /dev/input, opened for reading (not taken), looked for again from time to
    time: a keyboard plugged in later is read too. The fixer's own virtual keyboard is left out."""

    def __init__(self):
        self.opened = {}  # fd → (path, is_keyboard)

    def rescan(self):
        known = {path for path, _ in self.opened.values()}
        for node in sorted(Path("/dev/input").glob("event*")):
            if str(node) in known:
                continue
            kind = self.kind(node.name)
            if kind is None:
                continue
            try:
                fd = os.open(node, os.O_RDONLY | os.O_NONBLOCK)
            except OSError:
                continue
            self.opened[fd] = (str(node), kind == "keyboard")

    @staticmethod
    def kind(name):
        """"keyboard", "mouse" or None, from the key bits the kernel lists for the device."""
        device = Path("/sys/class/input") / name / "device"
        try:
            if (device / "name").read_text().strip() == VIRTUAL_NAME:
                return None
            words = (device / "capabilities/key").read_text().split()
        except OSError:
            return None
        bits = int("".join(word.zfill(16) for word in words) or "0", 16)
        if bits >> KEY_A & 1:
            return "keyboard"
        return "mouse" if bits >> BTN_LEFT & 1 else None

    def events(self, fd):
        """The key events waiting on fd as (code, value); a device that is gone is closed."""
        try:
            data = os.read(fd, EVENT.size * 64)
        except BlockingIOError:
            return []
        except OSError:
            data = b""
        if not data:
            os.close(fd)
            del self.opened[fd]
            return []
        events = (EVENT.unpack_from(data, offset) for offset in range(0, len(data) - EVENT.size + 1, EVENT.size))
        return [(code, value) for _, _, kind, code, value in events if kind == EV_KEY]


def hyprland_events():
    """Hyprland's event socket, or None outside a Hyprland session."""
    signature = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")
    path = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp")) / "hypr" / signature / ".socket2.sock"
    if not signature or not path.exists():
        return None
    connection = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    connection.connect(str(path))
    return connection


def excluded_classes():
    """Window classes the automatic fix leaves alone: "exclude" in ~/.config/hypr-rice/layout-fix.json."""
    try:
        return json.loads(SETTINGS.read_text()).get("exclude", [])
    except (OSError, ValueError, AttributeError):
        return []


def automatic():
    result = subprocess.run([sys.executable, str(Path(__file__).with_name("features.py")), "is", "layout-auto"],
                            capture_output=True)
    return result.returncode == 0


def run_daemon():
    session = Session()
    if sorted(session.layouts()) != ["ru", "us"]:
        raise SystemExit(f"исправление раскладки работает с раскладками us и ru, а здесь {session.layouts()}")
    no_access = "нужна группа input (Alt+F2 → Функции, затем перезайти)"
    inputs = Inputs()
    inputs.rescan()
    if not any(is_keyboard for _, is_keyboard in inputs.opened.values()):
        raise SystemExit("нет доступа к клавиатуре в /dev/input: " + no_access)
    try:
        keyboard = VirtualKeyboard()
    except PermissionError:
        raise SystemExit("нет доступа к /dev/uinput: " + no_access)
    spellers = {"us": Speller("en_US"), "ru": Speller("ru_RU")} if automatic() else None
    fixer = Fixer(session, keyboard, spellers, excluded_classes())
    events = hyprland_events()

    wakeup_read, wakeup_write = os.pipe()
    os.set_blocking(wakeup_write, False)
    signal.set_wakeup_fd(wakeup_write)
    signal.signal(signal.SIGUSR1, lambda *_: fixer.ask("word"))
    signal.signal(signal.SIGUSR2, lambda *_: fixer.ask("selection"))

    scanned = time.monotonic()
    while True:
        watched = [*inputs.opened, wakeup_read] + ([events] if events else [])
        ready, _, _ = select.select(watched, [], [], RESCAN_S)
        if time.monotonic() - scanned >= RESCAN_S:
            inputs.rescan()
            scanned = time.monotonic()
        for item in ready:
            if item == wakeup_read:
                os.read(wakeup_read, 64)
            elif item is events:
                received = events.recv(4096)
                if not received:  # Hyprland is gone: the session ends, and the unit with it
                    events = None
                elif b"activewindowv2>>" in received:
                    fixer.reset()
            elif item in inputs.opened:
                is_keyboard = inputs.opened[item][1]
                for code, value in inputs.events(item):
                    if not is_keyboard and code in BUTTONS:
                        fixer.reset()
                    elif is_keyboard:
                        fixer.key(code, value)


if __name__ == "__main__":
    run_daemon()
