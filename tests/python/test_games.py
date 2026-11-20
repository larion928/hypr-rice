"""games.py, the game library behind the games window."""
import fcntl
import json
import subprocess
import time
import unittest

from rice_sandbox import Sandbox


class GamesTest(unittest.TestCase):
    def setUp(self):
        self.sandbox = Sandbox()
        self.library = self.sandbox.home / ".config/hypr-rice/games.json"

    def tearDown(self):
        self.sandbox.cleanup()

    def games(self, *args):
        return self.sandbox.run(["python3", self.sandbox.home / ".config/hypr/scripts/games.py", *args])

    def write_library(self, *entries):
        self.library.write_text(json.dumps(list(entries)))

    def test_a_program_that_cannot_start_is_a_message(self):
        program = self.sandbox.home / "game.exe"
        program.write_bytes(b"MZ")
        self.write_library({"id": "a1", "kind": "exe", "target": str(program), "name": "Game", "added": 0,
                            "played": 0})
        result = self.games("launch", "a1")  # the sandbox has no ~/.local/bin/proton-run
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertNotIn("Traceback", result.stderr)

    def test_a_windows_program_is_known_by_its_first_bytes(self):
        program = self.sandbox.home / "game"
        program.write_bytes(b"MZ" + bytes(100))
        result = self.games("add-file", program)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["kind"], "exe")

    def test_a_game_looked_for_offline_is_looked_for_again(self):
        self.write_library({"id": "a1", "kind": "native", "target": "/nowhere/game", "name": "Game", "added": 0,
                            "played": 0})
        result = self.sandbox.python("""
import urllib.error, urllib.request
def offline(*args, **kwargs):
    raise urllib.error.URLError("no network")
urllib.request.urlopen = offline
from gamelib import library, pictures
pictures.find_pictures()
assert "looked" not in library.games()[0], library.games()
""")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_a_change_waits_for_the_library_lock(self):
        self.write_library({"id": "a1", "kind": "native", "target": "/nowhere/game", "name": "Old", "added": 0,
                            "played": 0})
        lock_file = self.sandbox.home / ".config/hypr-rice/games.lock"
        with lock_file.open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            rename = subprocess.Popen(["python3", str(self.sandbox.home / ".config/hypr/scripts/games.py"),
                                       "rename", "a1", "New"], env=self.sandbox.env())
            time.sleep(1)
            self.assertIsNone(rename.poll(), "renamed while the library was locked")
            self.assertEqual(json.loads(self.library.read_text())[0]["name"], "Old")
        self.assertEqual(rename.wait(timeout=10), 0)
        self.assertEqual(json.loads(self.library.read_text())[0]["name"], "New")

    def test_the_listing_asks_for_the_icon_theme_once(self):
        entries = [{"id": f"a{n}", "kind": "app", "target": "x", "name": f"G{n}", "icon": "folder", "added": 0,
                    "played": 0} for n in range(3)]
        self.write_library(*entries)
        result = self.games("list")
        if "gi" in result.stderr:
            self.skipTest("no GTK for Python")
        self.assertEqual(result.returncode, 0, result.stderr)
        asked = [call for call in self.sandbox.recorded() if call.startswith("gsettings get")]
        self.assertLessEqual(len(asked), 1, asked)


if __name__ == "__main__":
    unittest.main()
