"""A fake $HOME for running the live rice scripts (~/.config/hypr/scripts, ~/.local/bin) without touching
the session they run in: every program that would act on it (systemctl, hyprctl, pkill, sudo, ...) is a
stub that records its call in the sandbox's calls file and succeeds; pgrep reports nothing running.
RICE_HOME points the tests at another copy of the rice: the repo's home/ (CI), an older version."""
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

LIVE_HOME = Path(os.environ.get("RICE_HOME", Path.home()))
LIVE_SCRIPTS = LIVE_HOME / ".config/hypr/scripts"
LIVE_BIN = LIVE_HOME / ".local/bin"
LIVE_THEMES = LIVE_HOME / ".config/hypr/themes"
RECORDED = ("sudo", "gsettings", "systemctl", "pkill", "hyprctl", "code-oss", "busctl", "notify-send", "awww",
            "waybar", "mpvpaper")
THEME_FILES = ("palette.json", "ui.json", "hyprlock.conf", "hypr.lua", "style.css", "histui.css", "waybar.json")


class Sandbox:
    def __init__(self):
        self.root = Path(tempfile.mkdtemp(prefix="rice-test-"))
        self.home = self.root / "home"
        self.stubs = self.root / "bin"
        self.calls = self.root / "calls"
        self.runtime = self.root / "run"
        for folder in (self.home / ".config/hypr/themes", self.home / ".config/hypr-rice/waybar", self.stubs,
                       self.runtime):
            folder.mkdir(parents=True)
        (self.home / ".config/hypr/scripts").symlink_to(LIVE_SCRIPTS)
        shutil.copy(LIVE_HOME / ".config/hypr-rice/waybar/config.base.json", self.home / ".config/hypr-rice/waybar/")
        for name in RECORDED:
            self.stub(name)
        self.stub("pgrep", "exit 1")

    def cleanup(self):
        shutil.rmtree(self.root, ignore_errors=True)

    def stub(self, name, body=""):
        """A program on PATH that records "name args" and then runs body (sh)."""
        script = self.stubs / name
        script.write_text(f'#!/bin/sh\necho "{name} $*" >> "{self.calls}"\n{body}\n')
        script.chmod(0o755)

    def recorded(self):
        return self.calls.read_text().splitlines() if self.calls.exists() else []

    def add_theme(self, name, source="night"):
        """A theme of the sandbox: the live theme source's files, without its pictures and sounds."""
        folder = self.home / ".config/hypr/themes" / name
        folder.mkdir()
        for file_name in THEME_FILES:
            if (LIVE_THEMES / source / file_name).exists():
                shutil.copy(LIVE_THEMES / source / file_name, folder)
        return folder

    def env(self, **extra):
        return {"HOME": str(self.home), "PATH": f"{self.stubs}:/usr/bin", "XDG_RUNTIME_DIR": str(self.runtime),
                "PYTHONDONTWRITEBYTECODE": "1", "LANG": "C.UTF-8", **extra}

    def run(self, argv, timeout=60, **extra_env):
        return subprocess.run([str(part) for part in argv], env=self.env(**extra_env), capture_output=True,
                              text=True, timeout=timeout)

    def themegen(self, *args):
        return self.run(["python3", self.home / ".config/hypr/scripts/themegen.py", *args])

    def python(self, code, **extra_env):
        """code run with the live scripts importable and $HOME the sandbox's; it fails by raising."""
        prelude = f"import sys; sys.path.insert(0, {str(self.home / '.config/hypr/scripts')!r})\n"
        return self.run(["python3", "-c", prelude + code], **extra_env)
