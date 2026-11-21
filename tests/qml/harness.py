"""Runs the rice's Quickshell menus offscreen, in a fake $HOME, and drives them over Quickshell's IPC.

The menus are copied from $RICE_HOME/.config/quickshell (default: the live ~), so the same tests run against any
version of them. Two layouts are known:
  resident  ~/.config/quickshell/shell: one shell holds every menu; `quickshell ipc call menus open|close|...`.
  per-panel ~/.config/quickshell/<menu>: one Quickshell process per open menu (the layout before the resident
            shell); the launcher scripts passed what the menu needs in environment variables.

Offscreen there is no layer shell, so the copy is changed in two ways before it runs:
  - `PanelWindow {` becomes `PanelStub {`: a floating window with PanelWindow's properties (PanelStub.qml is put
    next to every file that needs it), and lines setting `WlrLayershell.` are dropped: on a window that is not a
    layer surface they break the shell's IPC.
  - the document holding ShellRoot gets an IPC target "test": `eval <menu> <expression>` returns the expression's
    value as JSON (the menu's root object is `menu`), `key <key> <modifiers>` sends a key with QtTest's keyClick
    to the focused window. The expression goes percent-encoded: `quickshell ipc` splits arguments at commas.
    keyClick carries no scan code: letters by key position cannot be tested this way.

Every program the menus run is a stub in front of PATH that records its arguments in calls.log; a few answer
with the fixtures in fixtures/ (hyprctl, histui, nmcli, games.py, themegen.py, features.py, theme-list.py)."""
import json
import os
import shutil
import signal
import struct
import subprocess
import tempfile
import time
import zlib
from urllib.parse import quote
from pathlib import Path

FIXTURES = Path(__file__).parent / "fixtures"
SOURCE_HOME = Path(os.environ.get("RICE_HOME", Path.home()))
SOURCE = SOURCE_HOME / ".config/quickshell"
MENUS = ("launcher", "settings", "themes", "help", "power", "notif", "network", "games", "shots")
CURRENT_THEME = "claude"

# QML errors worth failing a test for; a missing picture or font is not one, nor PipeWire missing in the fake
# runtime directory (the OSD connects to it).
ERROR_MARKERS = ("TypeError", "ReferenceError", "SyntaxError", "is not defined", "is not a function",
                 "Unable to assign", "Cannot assign", "Cannot read property", "Failed to load", "unavailable",
                 "Type error", "non-existent", "ERROR")

PANEL_STUB = """import QtQuick
import Quickshell

// PanelWindow's properties on a floating window, for running the menus offscreen (tests/qml/harness.py).
FloatingWindow {
    component Edges: QtObject { property bool top; property bool bottom; property bool left; property bool right }
    component Margins: QtObject { property int top; property int bottom; property int left; property int right }
    property Edges anchors: Edges {}
    property Margins margins: Margins {}
    property int exclusionMode
    property int exclusiveZone
    property var mask
}
"""

# Recorded calls go to $CALLS; the answer, if any, comes from the case below.
STUB_HEAD = '#!/bin/sh\nprintf "%s\\n" "$(basename "$0") $*" >> "$CALLS"\n'
ANSWERS = {
    "hyprctl": """case "$*" in
    "monitors all -j"|"monitors -j") cat "$FIXTURES/monitors.json" ;;
    "binds -j") cat "$FIXTURES/binds.json" ;;
    "globalshortcuts -j"|"clients -j") echo "[]" ;;
    submap) echo default ;;
esac""",
    "histui": """case "$*" in
    "get --format json --limit 300") cat "$RUNTIME/notifications.json" ;;
    "dnd status") echo "disabled" ;;
esac""",
    "nmcli": """case "$*" in
    "radio wifi") echo enabled ;;
    "-t -f DEVICE,TYPE,STATE,CONNECTION device") printf 'wlan0:wifi:connected:Home\\nlo:loopback:connected (externally):lo\\n' ;;
    "-g IP4.ADDRESS device show wlan0") echo "192.168.1.5/24" ;;
    "-t -f NAME,TYPE connection show") printf 'Home:802-11-wireless\\nCafe\\\\:Free:802-11-wireless\\n' ;;
    *"device wifi list"*) printf '*:Home:80:WPA2:5180 MHz\\n :Cafe\\\\:Free:40:WPA2:2412 MHz\\n :Neighbour:60:WPA2:2437 MHz\\n :Neighbour:30:WPA2:2462 MHz\\n' ;;
esac""",
}
RECORDED = ("notify-send", "wl-copy", "zenity", "xdg-open", "changetheme", "pw-play", "gio", "thunar", "systemctl",
            "hyprlock", "nm-connection-editor", "grim")

GAMES_PY = """import json, os, sys
open(os.environ["CALLS"], "a").write("games.py " + " ".join(sys.argv[1:]) + "\\n")
if sys.argv[1] == "list":
    print(open(os.environ["FIXTURES"] + "/games.json").read())
elif sys.argv[1] == "steam":
    print("[]")
"""
THEMEGEN_PY = """import json, os, sys
open(os.environ["CALLS"], "a").write("themegen.py " + " ".join(sys.argv[1:]) + "\\n")
answers = {"icon-themes": {"installed": [], "downloadable": []}, "cursor-themes": {"installed": [], "downloadable": []},
           "removed-themes": [], "icons": [], "bar-preview": {}}
if sys.argv[1] in answers:
    print(json.dumps(answers[sys.argv[1]]))
"""
# features.py: the fixture's list with the switches made so far (kept where the real one keeps them) and without
# the packages ~/.local/bin/rice-install-package installed; `on` is refused, as by the real one, while a package
# the feature needs is missing.
FEATURES_PY = """import json, os, sys
open(os.environ["CALLS"], "a").write("features.py " + " ".join(sys.argv[1:]) + "\\n")
state_file = os.path.expanduser("~/.config/hypr-rice/features.json")
state = json.load(open(state_file)) if os.path.exists(state_file) else {}
features = json.load(open(os.environ["FIXTURES"] + "/features.json"))
installed = os.environ["RUNTIME"] + "/installed-packages"
installed = open(installed).read().split() if os.path.exists(installed) else []
for feature in features:
    feature["on"] = state.get(feature["id"], feature["on"])
    feature["missing"] = [package for package in feature["missing"] if package not in installed]
if sys.argv[1] == "list":
    print(json.dumps(features, ensure_ascii=False))
elif sys.argv[1] in ("on", "off"):
    feature = next(feature for feature in features if feature["id"] == sys.argv[2])
    if sys.argv[1] == "on" and feature["missing"]:
        print("«" + feature["name"] + "» не включена: нужны пакеты " + " ".join(feature["missing"]), file=sys.stderr)
        sys.exit(1)
    state[feature["id"]] = sys.argv[1] == "on"
    json.dump(state, open(state_file, "w"))
"""
# rice-install-package: "secret" is the right sudo password; the install is over at once, its log says so.
RICE_INSTALL_PACKAGE = STUB_HEAD + """IFS= read -r password
[ "$password" = secret ] || exit 2
echo "$1" >> "$RUNTIME/installed-packages"
printf 'Ставлю %s\\n@@done 0\\n' "$1" > "$XDG_RUNTIME_DIR/rice-install-$1.log"
"""
# The per-panel layout passed a file name to write to; the resident shell reads stdout.
THEME_LIST_PY = """import os, sys
text = open(os.environ["RUNTIME"] + "/theme-list.json").read()
if len(sys.argv) > 1:
    open(sys.argv[1], "w").write(text)
else:
    print(text)
"""
def png(width, height):
    """A grey PNG of that size."""
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    rows = b"".join(b"\0" + b"\x80" * (width * 3) for _ in range(height))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))


def resident(source=SOURCE):
    return (source / "shell/shell.qml").exists()


class MenuSandbox:
    """A fake $HOME with a copy of the menus, and the Quickshell processes running them."""

    def __init__(self, source=SOURCE):
        self.source = source
        self.resident = resident(source)
        self.root = Path(tempfile.mkdtemp(prefix="rice-qml-"))
        self.home = self.root / "home"
        self.runtime = self.root / "run"
        self.stubs = self.root / "bin"
        self.calls = self.root / "calls.log"
        self.logs = self.root / "logs"
        self.processes = {}  # menu (or "shell") -> Popen
        for folder in (self.home, self.runtime, self.stubs, self.logs):
            folder.mkdir(parents=True)
        self.runtime.chmod(0o700)
        self.calls.touch()
        self.config = self.home / ".config/quickshell"
        shutil.copytree(source, self.config, symlinks=True, ignore=shutil.ignore_patterns("__pycache__"))
        self._make_offscreen()
        self._write_home()
        self._write_stubs()

    # ---------- setup ----------

    def _make_offscreen(self):
        for qml in self.config.rglob("*.qml"):
            if qml.is_symlink() or any(part.is_symlink() for part in qml.parents if self.config in part.parents):
                continue
            text = qml.read_text()
            if "PanelWindow {" not in text and "WlrLayershell." not in text:
                continue
            lines = [line.replace("PanelWindow {", "PanelStub {") for line in text.split("\n")
                     if "WlrLayershell." not in line]
            qml.write_text("\n".join(lines))
            (qml.parent / "PanelStub.qml").write_text(PANEL_STUB)
        for script in self.config.rglob("theme-list.py"):
            script.write_text(THEME_LIST_PY)
        if self.resident:
            self._add_test_target(self.config / "shell/shell.qml", "shell.menu(name)")
        else:
            for menu in MENUS + ("osd",):
                self._add_test_target(self.config / menu / "shell.qml", "root")

    def _add_test_target(self, qml, menu_expression):
        """The IPC target "test" in the document with ShellRoot. In the resident shell the settings window's
        stores are reached as menu.mon, menu.keys, ...; in a per-panel settings document they are ids already."""
        stores = ("mon", "keys", "themeEdit", "ownThemes", "userFiles", "features", "net")
        locals_ = "".join(f"const {name} = menu ? menu.{name} : undefined; " for name in stores) if self.resident else ""
        target = f"""
    TestCase {{ id: harnessKeys; when: false; running: false }}
    IpcHandler {{
        target: "test"
        function evaluate(name: string, expression: string): string {{
            try {{
                const menu = {menu_expression};
                {locals_}
                const value = eval(decodeURIComponent(expression));
                return JSON.stringify(value === undefined ? null : value);
            }} catch (error) {{
                return "ERROR " + error;
            }}
        }}
        function key(key: int, modifiers: int): void {{ harnessKeys.keyClick(key, modifiers); }}
    }}
"""
        text = qml.read_text()
        opening = text.index("ShellRoot {")
        line_end = text.index("\n", opening)
        text = text[:line_end + 1] + target + text[line_end + 1:]
        imports = "import QtTest\nimport Quickshell.Io\n" + ("import qs.common\n" if self.resident else "")
        qml.write_text(imports + text)

    def _write_home(self):
        themes = json.loads((FIXTURES / "theme-list.json").read_text().replace("@HOME@", str(self.home)))
        hypr = self.home / ".config/hypr"
        for theme in themes:
            folder = hypr / "themes" / theme["name"]
            folder.mkdir(parents=True)
            (folder / "palette.json").write_text(json.dumps(theme["pal"], ensure_ascii=False))
            (folder / "ui.json").write_text(json.dumps(theme["ui"], ensure_ascii=False))
        current = next(theme for theme in themes if theme["name"] == CURRENT_THEME)
        self.palette = current["pal"]
        self.write_theme(current["pal"], current["ui"])
        (hypr / "current-theme").write_text(CURRENT_THEME + "\n")
        (hypr / "monitors.lua").write_text('-- mine\nhl.monitor({ output = "eDP-1", mode = "1920x1080@60", transform = 1 })\n'
                                           'hl.workspace_rule({ workspace = "1", monitor = "eDP-1" })\n')
        (self.home / ".config/hypr-rice").mkdir()
        scripts = hypr / "scripts"
        scripts.mkdir()
        (scripts / "games.py").write_text(GAMES_PY)
        (scripts / "themegen.py").write_text(THEMEGEN_PY)
        (scripts / "features.py").write_text(FEATURES_PY)
        installer = self.home / ".local/bin/rice-install-package"
        installer.parent.mkdir(parents=True)
        installer.write_text(RICE_INSTALL_PACKAGE)
        installer.chmod(0o755)
        shots = self.home / "Pictures/screenshots"
        shots.mkdir(parents=True)
        for name in ("screenshot_20261006_143300.png", "screenshot_20261007_090500.png"):
            (shots / name).write_bytes(png(4, 4))
        (self.runtime / "theme-list.json").write_text(json.dumps(themes, ensure_ascii=False))
        shutil.copy(FIXTURES / "binds-registry.json", self.runtime / "hypr-binds-registry.json")
        shutil.copy(FIXTURES / "binds.json", self.runtime / "help-binds.json")
        now = int(time.time())
        notifications = (FIXTURES / "notifications.json").read_text().replace("@NOW_MINUS_MINUTE@", str(now - 60)) \
            .replace("@NOW@", str(now)).replace("@LAST_YEAR@", str(now - 400 * 86400))
        (self.runtime / "notifications.json").write_text(notifications)

    def freeze_screens(self):
        """What ~/.local/bin/shot leaves for the overlay: the frozen frame of the one offscreen screen (named "")
        and Hyprland's monitors and windows."""
        shot = self.runtime / "shot"
        shot.mkdir(exist_ok=True)
        (shot / ".png").write_bytes(png(64, 48))
        (shot / "monitors.json").write_text(json.dumps([{"name": "", "x": 0, "y": 0, "focused": True,
                                                          "activeWorkspace": {"id": 1}, "specialWorkspace": {"id": 0}}]))
        (shot / "clients.json").write_text("[]")

    def write_theme(self, palette, ui):
        hypr = self.home / ".config/hypr"
        (hypr / "palette.json").write_text(json.dumps(palette, ensure_ascii=False))
        (hypr / "ui.json").write_text(json.dumps(ui, ensure_ascii=False))

    def _write_stubs(self):
        for name in RECORDED + tuple(ANSWERS):
            stub = self.stubs / name
            stub.write_text(STUB_HEAD + ANSWERS.get(name, "") + "\nexit 0\n")
            stub.chmod(0o755)

    def env(self):
        env = {key: value for key, value in os.environ.items()
               if key not in ("WAYLAND_DISPLAY", "DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE", "QS_CONFIG_PATH",
                              "DBUS_SESSION_BUS_ADDRESS")}
        env.update(HOME=str(self.home), XDG_RUNTIME_DIR=str(self.runtime), XDG_CONFIG_HOME=str(self.home / ".config"),
                   XDG_CACHE_HOME=str(self.home / ".cache"), XDG_STATE_HOME=str(self.home / ".local/state"),
                   QT_QPA_PLATFORM="offscreen", PATH=f"{self.stubs}:{os.environ['PATH']}", CALLS=str(self.calls),
                   FIXTURES=str(FIXTURES), RUNTIME=str(self.runtime))
        return env

    def panel_env(self, menu, argument):
        """What the per-panel launcher scripts exported before starting a panel."""
        themes = json.loads((self.runtime / "theme-list.json").read_text())
        return dict(RICE_THEME_DIR=str(self.home / ".config/hypr/themes" / CURRENT_THEME), RICE_MONITOR="",
                    RICE_THEME_LIST=str(self.runtime / "theme-list.json"), HELP_BINDS=str(self.runtime / "help-binds.json"),
                    SHOTS_DIR=str(self.home / "Pictures/screenshots"), SETTINGS_PAGE=argument or "monitors",
                    LAUNCHER_THEMES=json.dumps([{"name": t["name"], "label": t["pal"]["label"]} for t in themes],
                                               ensure_ascii=False))

    # ---------- processes ----------

    def _start(self, key, config, extra_env=None):
        env = self.env()
        env.update(extra_env or {})
        with open(self.logs / f"{key}.log", "a") as log:
            process = subprocess.Popen(["quickshell", "-p", str(config)], env=env, stdout=log, stderr=subprocess.STDOUT,
                                       start_new_session=True)
        self.processes[key] = process
        self._wait(lambda: self._ipc(process, "test", "evaluate", "", "1") == "1", f"{key} did not start")
        return process

    def start_shell(self):
        if self.resident:
            self._start("shell", self.config / "shell")
        else:
            self._start("osd", self.config / "osd")

    def _ipc(self, process, *args):
        result = subprocess.run(["quickshell", "ipc", "--pid", str(process.pid), "call", *args], env=self.env(),
                                capture_output=True, text=True, timeout=10)
        return result.stdout.strip()

    def _process_for(self, menu):
        return self.processes["shell"] if self.resident else self.processes.get(menu)

    def open(self, menu, argument=""):
        if self.resident:
            self._ipc(self.processes["shell"], "menus", "open", menu, argument)
            self._wait(lambda: self.is_open(menu), f"{menu} did not open")
        else:
            self._start(menu, self.config / menu, self.panel_env(menu, argument))
        # The window is shown and has the keyboard once its first frame is out.
        time.sleep(0.4)

    def toggle(self, menu, argument=""):
        self._ipc(self.processes["shell"], "menus", "toggle", menu, argument)

    def is_open(self, menu):
        if self.resident:
            return self._ipc(self.processes["shell"], "menus", "isOpen", menu) == "true"
        process = self.processes.get(menu)
        return process is not None and process.poll() is None

    def close(self, menu):
        process = self._process_for(menu)
        if self.resident:
            self._ipc(process, "menus", "close", menu)
        else:
            self._ipc(process, "panel", "close")

    def wait_closed(self, menu, timeout=3):
        self._wait(lambda: not self.is_open(menu), f"{menu} did not close", timeout)

    def eval(self, menu, expression):
        # Percent-encoded: `quickshell ipc` splits arguments at commas.
        answer = self._ipc(self._process_for(menu), "test", "evaluate", menu, quote(expression, safe=""))
        if answer.startswith("ERROR"):
            raise AssertionError(f"{expression}: {answer}")
        return json.loads(answer) if answer else None

    def wait_for(self, menu, expression, expected, timeout=5):
        self._wait(lambda: self.eval(menu, expression) == expected,
                   f"{expression} never became {expected!r} (last: {self.eval(menu, expression)!r})", timeout)

    def key(self, menu, key, modifiers=0):
        self._ipc(self._process_for(menu), "test", "key", str(key), str(modifiers))
        time.sleep(0.05)

    def recorded(self):
        return self.calls.read_text().splitlines()

    def errors(self):
        found = []
        for log in self.logs.glob("*.log"):
            found += [line for line in log.read_text().splitlines()
                      if any(marker in line for marker in ERROR_MARKERS) and "pipewire" not in line]
        return found

    @staticmethod
    def _wait(condition, message, timeout=8):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            try:
                if condition():
                    return
            except (subprocess.TimeoutExpired, json.JSONDecodeError, AssertionError):
                pass
            time.sleep(0.05)
        raise AssertionError(message)

    def cleanup(self):
        for process in self.processes.values():
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
        shutil.rmtree(self.root, ignore_errors=True)


# Qt key codes the tests send.
KEY = dict(Escape=0x01000000, Tab=0x01000001, Backtab=0x01000002, Return=0x01000004, Left=0x01000012, Up=0x01000013,
           Right=0x01000014, Down=0x01000015, PageDown=0x01000017, F1=0x01000030)
