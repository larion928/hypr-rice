"""The sandbox itself: what a test starts cannot outlive it and reach the live session."""
import os
import time
import unittest

from rice_sandbox import Sandbox


def alive(pid):
    """Running: neither gone nor a zombie (state Z in /proc)."""
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    try:
        with open(f"/proc/{pid}/stat") as stat:
            return stat.read().rsplit(")", 1)[1].split()[0] != "Z"
    except (FileNotFoundError, ProcessLookupError):  # gone between the two looks
        return False


class SandboxTest(unittest.TestCase):
    def test_a_background_child_does_not_outlive_the_sandbox(self):
        sandbox = Sandbox()
        result = sandbox.run(["sh", "-c", "sleep 30 >/dev/null 2>&1 & echo $!"])
        child = int(result.stdout)
        sandbox.cleanup()
        # A killed process lingers as a zombie until whoever adopted it reaps it: give that a moment.
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline and alive(child):
            time.sleep(0.02)
        self.assertFalse(alive(child))

    def test_the_journal_is_a_stub(self):
        sandbox = Sandbox()
        try:
            sandbox.run(["sh", "-c", "echo hello | systemd-cat -t rice-test; logger -t rice-test hello"])
            self.assertIn("systemd-cat -t rice-test", sandbox.recorded())
            self.assertIn("logger -t rice-test hello", sandbox.recorded())
        finally:
            sandbox.cleanup()
