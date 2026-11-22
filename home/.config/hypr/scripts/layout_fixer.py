#!/usr/bin/env python3
"""Text typed in the wrong layout (us/ru), typed again in the other one: features "layout-fix" (the keys) and
"layout-auto" (after a space, by the dictionaries); "layout-typo" adds the dictionaries' suggestions to the key.
rice-layout-fixer.service runs it.

It reads the keyboards and mice (/dev/input; the input group) without taking them, and keeps the keys typed
since the last reset: a click, a change of window, Enter, an arrow, a Ctrl/Alt/Super combination or the lock
screen forget them, and nothing is written anywhere. A fix erases the last word (with the spaces after it),
switches the layout and presses the same keys again through its own virtual keyboard (/dev/uinput), so it works
in any program whatever it does with text; a second fix of the same word switches it back. With layout-typo a word
that is a word in neither layout goes to the other layout at the first press, then through hunspell's suggestions,
then back to what was typed; a word neither dictionary knew that is left on the screen after the key (typing goes
on) is learnt into the user's own dictionary.
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
from dataclasses import dataclass
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
# The user's own words, hunspell's personal dictionaries: a word per line, "word/model" declines like model.
OWN_WORDS = {"us": Path.home() / ".config/hypr-rice/words-en.dic", "ru": Path.home() / ".config/hypr-rice/words-ru.dic"}
RUSSIAN_WORDS = Path(__file__).with_name("layout_words_ru.txt")


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

    def replace_tail(self, count, strokes):
        """The last count keys are now strokes (a fix typed them over)."""
        self.keys = (self.keys[:len(self.keys) - count] + strokes)[-STROKE_LIMIT:]

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
    """hunspell -a for one dictionary, kept running: a line per word, "*", "+" or "-" when it is a word,
    "& word count offset: first, second, ..." when it is not and something is close, "#" when nothing is."""

    def __init__(self, dictionary, own_words, frequent=()):
        self.own_words = own_words
        self.rank = {word: place for place, word in enumerate(frequent)}
        self.process = subprocess.Popen(["hunspell", "-a", "-i", "utf-8", "-d", dictionary, "-p", str(own_words)],
                                        stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, encoding="utf-8")
        self.process.stdout.readline()  # the version banner

    def knows(self, word):
        return self.answer(word)[:1] in "*+-"

    def suggestions(self, word):
        """The words hunspell offers for a word it does not know: the most frequent first when frequent words were
        given (hunspell's own order put the meant Russian word as low as fifth), hunspell's order among the rest."""
        answer = self.answer(word)
        offered = answer.split(": ", 1)[1].split(", ") if answer.startswith("&") else []
        return sorted(offered, key=lambda suggestion: self.rank.get(suggestion.lower(), len(self.rank)))

    def learn(self, word):
        """The word is the user's: hunspell knows it from now on, and the user's dictionary keeps it for later."""
        self.process.stdin.write("@" + word + "\n")  # hunspell answers nothing to "@"
        self.process.stdin.flush()
        self.own_words.parent.mkdir(parents=True, exist_ok=True)
        with open(self.own_words, "a", encoding="utf-8") as file:
            file.write(word + "\n")

    def answer(self, word):
        """hunspell's line about the word ("" when it said nothing)."""
        # "^" keeps a word that starts with a hunspell command character a word.
        self.process.stdin.write("^" + word + "\n")
        self.process.stdin.flush()
        answers = []
        while (line := self.process.stdout.readline().rstrip("\n")) != "":
            answers.append(line)
        return answers[0] if answers else ""


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


@dataclass(frozen=True)
class Modes:
    """The features beside layout-fix: automatic is layout-auto (a fix after a space, never in the excluded window
    classes), typos is layout-typo (the key offers the dictionaries' suggestions)."""
    automatic: bool = False
    typos: bool = False
    excluded: frozenset = frozenset()


class Cycle:
    """What the last word can become under the key: what was typed, then each candidate, then what was typed again.
    A choice is (layout, strokes): the keys that put it on the screen in that layout, its punctuation and spaces
    included."""

    def __init__(self, typed, candidates):
        self.choices = [typed, *candidates]
        self.index = 0

    def shown(self):
        return self.choices[self.index]

    def next(self):
        self.index = (self.index + 1) % len(self.choices)
        return self.choices[self.index]


# Punctuation a word carries before or after it; the dictionaries are asked about the word without it.
WORD_EDGES = ".,;:!?\"'() "
# The key goes through this many of hunspell's suggestions, closest first, before it gives back what was typed.
SUGGESTIONS_OFFERED = 5


def bare(text):
    return text.strip(WORD_EDGES)


class Fixer:
    """What the keys mean for the buffer, and the fixes. session, keyboard and spellers are Session,
    VirtualKeyboard and a {layout: Speller} (None when neither layout-auto nor layout-typo is on)."""

    def __init__(self, session, keyboard, spellers, modes=Modes()):
        self.session = session
        self.keyboard = keyboard
        self.spellers = spellers
        self.modes = modes
        self.strokes = Strokes()
        self.held = set()        # modifier keys held now
        self.before_combination = ([], 0.0)
        self.request = None      # "word" or "selection", carried out once the modifiers are up
        self.cycle = None        # the last word's Cycle while the buffer still ends with its choice

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
            # The hotkey itself is a combination: its Cycle has to survive it.
            self.before_combination = (self.strokes.keys, time.monotonic())
            self.strokes.reset()
            return
        if self.cycle and (code == keys.ENTER or (code, False) in keys.CHARACTERS["us"]):
            self.learn_shown()
        self.cycle = None
        if self.session.locked():
            self.strokes.reset()
        elif code == keys.BACKSPACE:
            self.strokes.backspace()
        elif (code, False) in keys.CHARACTERS["us"]:
            self.strokes.add((code, bool(self.held & SHIFTS)))
            if code == keys.SPACE and self.modes.automatic:
                self.check_finished_word()
        else:
            self.strokes.reset()

    def reset(self):
        """A click or another window: the text cursor may be anywhere now."""
        self.strokes.reset()
        self.cycle = None

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
            self.fix_word()
        elif request == "selection":
            self.retype_selection()

    def fix_word(self):
        """The last word becomes the next choice of its Cycle; a new Cycle when the word is not the one shown."""
        tail = self.strokes.tail()
        if all(code == keys.SPACE for code, _ in tail):
            return
        if self.cycle is None or self.cycle.shown()[1] != tail:
            self.cycle = Cycle((self.session.layout(), tail), self.candidates(tail))
        self.put(tail, *self.cycle.next())

    def candidates(self, tail):
        """What the key offers for the word in tail, typed in the current layout: the same keys in the other layout;
        with layout-typo, for a word that is a word in neither layout, hunspell's suggestions after them."""
        layout = self.session.layout()
        other = keys.other(layout)
        switched = [(other, tail)]
        if not self.modes.typos:
            return switched
        text = keys.typed(layout, tail)
        word = bare(text)
        if not word.replace("-", "").isalpha():
            return switched
        if self.spellers[layout].knows(word) or self.spellers[other].knows(bare(keys.typed(other, tail))):
            return switched
        # A word neither dictionary knows may be slang typed in the wrong layout, not a typo (fqnb = айти):
        # the layout first.
        return switched + self.suggested(layout, text, word)

    def suggested(self, layout, text, word):
        """text with each of hunspell's closest suggestions for its word in place of the word, as choices; one
        with a character that is not on the layout is left out."""
        start = text.index(word)  # what precedes the word is punctuation, so its first match is the word
        before, after = text[:start], text[start + len(word):]
        offered = self.spellers[layout].suggestions(word)[:SUGGESTIONS_OFFERED]
        choices = (keys.strokes_for(layout, before + suggestion + after) for suggestion in offered)
        return [(layout, strokes) for strokes in choices if strokes is not None]

    def learn_shown(self):
        """Typing went on after the key: with layout-typo, the word left on the screen is the user's, learnt when
        its dictionary did not know it."""
        if not self.modes.typos:
            return
        layout, strokes = self.cycle.shown()
        word = bare(keys.typed(layout, strokes)).lower()
        if len(word) >= 2 and word.replace("-", "").isalpha() and not self.spellers[layout].knows(word):
            self.spellers[layout].learn(word)

    def put(self, shown, layout, strokes):
        """Erases the shown strokes and types strokes in layout; the buffer holds them instead."""
        for _ in shown:
            self.keyboard.tap(keys.BACKSPACE)
        if layout != self.session.layout():
            self.switch(layout)
        for code, shifted in strokes:
            self.keyboard.tap(code, shifted)
        self.strokes.replace_tail(len(shown), strokes)

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
        if not fullscreen and window_class not in self.modes.excluded:
            tail = self.strokes.tail()
            self.put(tail, keys.other(self.session.layout()), tail)

    def wrong_layout(self, word):
        """A word of two letters or more that is no word in the layout it was typed in, and is one in the other."""
        if len(word) < 2 or any(code in keys.DIGIT_KEYS and not shifted for code, shifted in word):
            return False
        current = self.session.layout()
        typed = bare(keys.typed(current, word))
        meant = bare(keys.typed(keys.other(current), word))
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


def frequent_words(path):
    """The words of a frequency list: one per line, the most frequent first; "#" lines are comments."""
    with open(path, encoding="utf-8") as lines:
        return [line.strip() for line in lines if line.strip() and not line.startswith("#")]


def feature_on(feature_id):
    result = subprocess.run([sys.executable, str(Path(__file__).with_name("features.py")), "is", feature_id],
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
    modes = Modes(feature_on("layout-auto"), feature_on("layout-typo"), frozenset(excluded_classes()))
    spellers = None
    if modes.automatic or modes.typos:
        # English needs no frequencies: hunspell's first suggestion for it was the meant word.
        spellers = {"us": Speller("en_US", OWN_WORDS["us"]),
                    "ru": Speller("ru_RU", OWN_WORDS["ru"], frequent_words(RUSSIAN_WORDS))}
    fixer = Fixer(session, keyboard, spellers, modes)
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
