"""Everything a check reads the machine through: the command runner, file paths (moved under a test's
directory by root and home), the config, the last run's state and the one this run builds."""
import json
import os
import shutil
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path

from .runner import Runner
from .state import State

RICE = Path(__file__).resolve().parent.parent / "rice"


def systemctl(scope, *args):
    """systemctl for scope "system" or "user"."""
    return ["systemctl", "--user", *args] if scope == "user" else ["systemctl", *args]


def as_root(argv):
    """argv under sudo that never asks: the password was asked once, before the cures ran (sudo -v)."""
    return ["sudo", "-n", *argv]


def journal_of_unit(scope, unit):
    return ["journalctl", "--user-unit" if scope == "user" else "--unit", unit, "-b", "-n", "5", "-o", "cat",
            "--no-pager", "-q"]


@dataclass
class Context:
    runner: Runner
    config: object
    previous: State
    home: Path
    root: Path = Path("/")
    full: bool = False
    env: dict = field(default_factory=lambda: dict(os.environ))
    uid: int = field(default_factory=os.getuid)
    kernel_release: str = field(default_factory=lambda: os.uname().release)
    now: datetime = field(default_factory=lambda: datetime.now().astimezone())
    observed: State = field(default_factory=State)  # what this run saw, saved as the next run's previous
    _memo: dict = field(default_factory=dict)

    def path(self, absolute):
        """A system path, under root: the tests put a fake /sys, /etc, /var there."""
        return self.root / str(absolute).lstrip("/")

    def run(self, argv, timeout=30):
        return self.runner.run(argv, timeout=timeout)

    def forget(self):
        """Drops what was read once per run: a cure has changed the machine, the check reads it again."""
        self._memo.clear()

    def memo(self, name, produce):
        if name not in self._memo:
            self._memo[name] = produce()
        return self._memo[name]

    def updates(self):
        """{package: new version} from checkupdates, or None when it could not tell (no network, no tool).
        checkupdates syncs a copy of the databases, so the system's own stay untouched."""
        def produce():
            result = self.run(["checkupdates", "--nocolor"], timeout=90)
            if result.code == 2:  # its "no updates"
                return {}
            if not result.ok:
                return None
            return {line.split()[0]: line.split()[-1] for line in result.lines}
        return self.memo("updates", produce)

    def coredumps(self):
        """Core dumps of the last two days, oldest first: dicts with time (µs), pid, sig, exe."""
        def produce():
            result = self.run(["coredumpctl", "--json=short", "--no-pager", "--since=-48h", "list"])
            if not result.ok:  # it fails with "No coredumps found" too
                return []
            try:
                return json.loads(result.out)
            except ValueError:
                return []
        return self.memo("coredumps", produce)

    def has(self, program):
        return shutil.which(program, path=self.env.get("PATH", "")) is not None

    def hyprland_running(self):
        return bool(self.env.get("HYPRLAND_INSTANCE_SIGNATURE"))
