"""A stand-in for the doctor's command runner and a context whose every path is under a temporary folder:
no test of the doctor runs a real command or reads the live session."""
import os
import shutil
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from doctor import config  # noqa: E402
from doctor.context import Context  # noqa: E402
from doctor.runner import NOT_FOUND, Result  # noqa: E402
from doctor.state import State  # noqa: E402

NOW = datetime(2026, 11, 21, 12, 0, tzinfo=timezone.utc)


class FakeRunner:
    """Answers each command by the first stub whose argv prefix it starts with; anything else is "not found"."""

    def __init__(self):
        self.stubs = []
        self.calls = []
        self.interactive_calls = []
        self.spawned = []
        self.interactive_code = 0

    def on(self, prefix, out="", code=0, err=""):
        """prefix: the argv start, as one string split on spaces; out may be a function of the call count."""
        self.stubs.insert(0, (prefix.split(), out, code, err))
        return self

    def run(self, argv, timeout=30, stdin_text=None):
        argv = [str(part) for part in argv]
        self.calls.append(argv)
        for prefix, out, code, err in self.stubs:
            if argv[:len(prefix)] == prefix:
                text = out() if callable(out) else out
                return Result(code, text, err)
        return Result(NOT_FOUND, "", f"{argv[0]}: не заглушено")

    def interactive(self, argv):
        self.interactive_calls.append([str(part) for part in argv])
        return self.interactive_code

    def spawn(self, argv):
        self.spawned.append([str(part) for part in argv])
        return True

    def called(self, prefix):
        return [call for call in self.calls if call[:len(prefix.split())] == prefix.split()]


class Machine:
    """A fake machine in a temporary folder: root/ stands for /, home/ for ~."""

    def __init__(self):
        self.folder = Path(tempfile.mkdtemp(prefix="doctor-test-"))
        self.root = self.folder / "root"
        self.home = self.folder / "home"
        self.home.mkdir(parents=True)
        self.write("/proc/sys/kernel/random/boot_id", "boot-1\n")
        self.write("/proc/swaps", "Filename Type Size Used Priority\n/dev/zram0 partition 1 0 100\n")
        (self.root / "usr/lib/modules/6.0-test").mkdir(parents=True)
        self.runner = FakeRunner()

    def healthy(self):
        """Stubs for the checks that call a missing tool a problem (network, sound, clock), and the running
        kernel's modules: what is left to find is what a test sets up."""
        (self.root / "usr/lib/modules" / os.uname().release).mkdir(parents=True, exist_ok=True)
        self.runner.on("getent ahosts").on("curl").on("systemctl --user is-active")
        self.runner.on("wpctl inspect @DEFAULT_AUDIO_SINK@", 'id 38\n  * node.description = "Test sink"\n')
        self.runner.on("timedatectl show", "NTP=yes\nNTPSynchronized=yes\n")
        return self

    def cleanup(self):
        shutil.rmtree(self.folder, ignore_errors=True)

    def write(self, absolute, text):
        path = self.root / absolute.lstrip("/")
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def write_home(self, relative, text):
        path = self.home / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def context(self, previous=None, conf="", env=None, full=False):
        conf_path = self.home / ".config/hypr-rice/doctor.conf"
        conf_path.parent.mkdir(parents=True, exist_ok=True)
        conf_path.write_text(conf)
        return Context(runner=self.runner, config=config.load(conf_path), previous=previous or State(),
                       home=self.home, root=self.root, full=full, env=env if env is not None else {"PATH": ""},
                       uid=1000, kernel_release="6.0-test", now=NOW)


def keys(findings):
    return [finding.key for finding in findings]
