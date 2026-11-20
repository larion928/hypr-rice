"""Every system command the doctor runs goes through Runner, so the tests can put a stub in its place."""
import os
import subprocess
from dataclasses import dataclass


@dataclass(frozen=True)
class Result:
    code: int
    out: str
    err: str = ""

    @property
    def ok(self):
        return self.code == 0

    @property
    def lines(self):
        return [line for line in self.out.splitlines() if line.strip()]


NOT_FOUND = 127
TIMED_OUT = 124


class Runner:
    def __init__(self, env=None):
        self.user_env = dict(env if env is not None else os.environ)
        # Captured output is parsed: the C locale makes it the same on a Russian desktop. What the user
        # sees or what keeps running (a terminal program, a daemon) keeps the user's own locale.
        self.parsed_env = {**self.user_env, "LC_ALL": "C.UTF-8"}

    def run(self, argv, timeout=30, stdin_text=None):
        """argv's output, captured; a missing program and a timeout are results, not exceptions."""
        try:
            done = subprocess.run(argv, input=stdin_text, stdin=None if stdin_text else subprocess.DEVNULL,
                                  capture_output=True, text=True, errors="replace", timeout=timeout,
                                  env=self.parsed_env)
        except FileNotFoundError:
            return Result(NOT_FOUND, "", f"{argv[0]}: нет такой программы")
        except subprocess.TimeoutExpired:
            return Result(TIMED_OUT, "", f"{argv[0]}: не ответил за {timeout} с")
        return Result(done.returncode, done.stdout, done.stderr)

    def interactive(self, argv):
        """argv on the user's terminal (sudo's password, pacman's questions, pacdiff); its exit code."""
        try:
            return subprocess.run(argv, env=self.user_env).returncode
        except FileNotFoundError:
            return NOT_FOUND

    def spawn(self, argv):
        """argv started in a session of its own, outliving the doctor: a daemon the rice keeps running."""
        try:
            subprocess.Popen(argv, env=self.user_env, start_new_session=True, stdin=subprocess.DEVNULL,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except FileNotFoundError:
            return False
        return True
