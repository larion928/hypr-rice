"""changetheme, wallpaper and waybar-start, run in a sandbox: nothing reaches the session they run in."""
import shutil
import unittest

from PIL import Image

from rice_sandbox import LIVE_BIN, Sandbox

# A stand-in that records its arguments and which of the rice's lock files it holds open.
RECORD_LOCKS = 'ls -l /proc/$$/fd | grep -o "hypr-rice-[a-z-]*\\.lock" >> "{locks}" || true'


class ChangethemeTest(unittest.TestCase):
    def setUp(self):
        self.sandbox = Sandbox()
        self.locks = self.sandbox.root / "locks"
        bin_dir = self.sandbox.home / ".local/bin"
        bin_dir.mkdir(parents=True)
        for name, status in (("wallpaper", 0), ("waybar-start", 1)):
            (bin_dir / name).write_text(f'#!/bin/sh\necho "{name} $*" >> "{self.sandbox.calls}"\n'
                                        + RECORD_LOCKS.format(locks=self.locks) + f"\nexit {status}\n")
            (bin_dir / name).chmod(0o755)
        self.sandbox.stub("systemctl", 'case "$*" in *MainPID*) echo 42 ;; *NeedDaemonReload*) echo no ;; esac')
        self.sandbox.stub("busctl", 'echo "u 42"')

    def tearDown(self):
        self.sandbox.cleanup()

    def changetheme(self, *args):
        return self.sandbox.run([LIVE_BIN / "changetheme", *args])

    def test_a_theme_with_capitals_is_selectable(self):
        self.sandbox.add_theme("MyTheme")
        result = self.changetheme("--offline", "MyTheme")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.sandbox.home / ".config/histui/theme.env").read_text(), "HISTUI_THEME=MyTheme\n")

    def test_a_path_is_not_a_theme_name(self):
        outside = self.sandbox.home / ".config/hypr/outside"
        outside.mkdir()
        result = self.changetheme("--offline", "../outside")
        self.assertEqual(result.returncode, 1)
        self.assertIn("не имя темы", result.stdout)

    def test_a_failing_wallpaper_list_is_not_an_empty_one(self):
        theme = self.sandbox.add_theme("night")
        (theme / "palette.json").write_text("{ broken")
        result = self.changetheme("--offline", "night")
        self.assertIn("не смог перечислить обои", result.stdout)
        self.assertNotIn("нет изображений", result.stdout)
        self.assertEqual(result.returncode, 1)

    def test_histuid_gets_the_theme_without_daemon_reload(self):
        theme = self.sandbox.add_theme("night")
        Image.new("RGB", (8, 8)).save(theme / "wall.png")
        result = self.changetheme("night")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Обновлена тема уведомлений для histui: night", result.stdout)
        calls = self.sandbox.recorded()
        self.assertIn("systemctl --user restart histuid", calls)
        self.assertNotIn("systemctl --user daemon-reload", calls)
        self.assertEqual((self.sandbox.home / ".config/histui/theme.env").read_text(), "HISTUI_THEME=night\n")
        # What changetheme starts does not keep its lock.
        self.assertTrue(any(call.startswith("wallpaper ") for call in calls), calls)
        held = self.locks.read_text() if self.locks.exists() else ""
        self.assertNotIn("hypr-rice-changetheme.lock", held)

    def test_one_python_start_picks_the_wallpaper_and_applies(self):
        theme = self.sandbox.add_theme("night")
        Image.new("RGB", (8, 8)).save(theme / "wall.png")
        self.sandbox.stub("python3", 'exec /usr/bin/python3 "$@"')
        result = self.changetheme("night")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(f"Устанавливаю обои: {theme / 'wall.png'}\n", result.stdout)
        self.assertIn("Применена палитра темы: night\n", result.stdout)
        self.assertEqual((self.sandbox.home / ".config/hypr/current-wallpaper").read_text(), f"{theme / 'wall.png'}\n")
        calls = self.sandbox.recorded()
        themegen_starts = [call for call in calls if call.startswith("python3 ") and "themegen.py" in call]
        self.assertEqual(len(themegen_starts), 1, themegen_starts)
        # The wallpaper is shown before the apps are themed.
        self.assertLess(calls.index(f"wallpaper {theme / 'wall.png'}"), calls.index("pkill -USR1 -x kitty"))

    def test_keep_wallpaper_keeps_the_current_one_of_the_theme(self):
        theme = self.sandbox.add_theme("night")
        for name in ("a.png", "b.png"):
            Image.new("RGB", (8, 8)).save(theme / name)
        (self.sandbox.home / ".config/hypr/current-wallpaper").write_text(f"{theme / 'b.png'}\n")
        result = self.changetheme("--keep-wallpaper", "night")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(f"Обои остаются: {theme / 'b.png'}\n", result.stdout)
        self.assertFalse(any(call.startswith("wallpaper ") for call in self.sandbox.recorded()))

    def test_a_theme_without_palette_keeps_its_colors_and_says_so(self):
        theme = self.sandbox.add_theme("night")
        (theme / "palette.json").unlink()
        result = self.changetheme("--offline", "night")
        self.assertEqual(result.returncode, 1)
        self.assertIn("не смог перечислить обои", result.stdout)
        self.assertIn("в теме нет palette.json", result.stdout)
        self.assertNotIn("Применена палитра", result.stdout)


class WallpaperTest(unittest.TestCase):
    def setUp(self):
        self.sandbox = Sandbox()
        self.locks = self.sandbox.root / "locks"

    def tearDown(self):
        self.sandbox.cleanup()

    @unittest.skipUnless(shutil.which("ffmpeg"), "no ffmpeg")
    def test_the_player_does_not_hold_the_lock(self):
        clip = self.sandbox.home / "clip.mp4"
        made = self.sandbox.run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i", "testsrc2=s=320x180:r=10:d=1",
                                 "-c:v", "libx264", "-pix_fmt", "yuv420p", clip])
        self.assertEqual(made.returncode, 0, made.stderr)
        self.sandbox.stub("player", RECORD_LOCKS.format(locks=self.locks))
        result = self.sandbox.run([LIVE_BIN / "wallpaper", clip], WALLPAPER_PLAYER=str(self.sandbox.stubs / "player"))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(any(call.startswith("player ") for call in self.sandbox.recorded()), self.sandbox.recorded())
        self.assertNotIn("hypr-rice-wallpaper.lock", self.locks.read_text() if self.locks.exists() else "")


class WaybarStartTest(unittest.TestCase):
    def setUp(self):
        self.sandbox = Sandbox()
        self.locks = self.sandbox.root / "locks"
        self.log = self.sandbox.home / ".cache/waybar-start.log"

    def tearDown(self):
        self.sandbox.cleanup()

    def test_a_bar_that_never_shows_is_status_1_and_the_log_stays_short(self):
        self.log.parent.mkdir(parents=True)
        self.log.write_text("old line\n" * 1000)
        self.sandbox.stub("hyprctl", 'echo "[]"')  # no waybar layer: the bar never shows
        self.sandbox.stub("waybar", RECORD_LOCKS.format(locks=self.locks))
        result = self.sandbox.run([LIVE_BIN / "waybar-start"], timeout=60)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertEqual(sum(call.startswith("waybar ") for call in self.sandbox.recorded()), 3)
        self.assertLessEqual(len(self.log.read_text().splitlines()), 300)
        self.assertNotIn("hypr-rice-waybar-start.lock", self.locks.read_text() if self.locks.exists() else "")


if __name__ == "__main__":
    unittest.main()
