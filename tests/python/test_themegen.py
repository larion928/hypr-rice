"""themegen.py as changetheme and the settings window run it."""
import unittest

from rice_sandbox import Sandbox


class ApplyTest(unittest.TestCase):
    def setUp(self):
        self.sandbox = Sandbox()
        self.sandbox.add_theme("night")
        self.hypr = self.sandbox.home / ".config/hypr"

    def tearDown(self):
        self.sandbox.cleanup()

    def test_a_broken_step_leaves_the_others_applied(self):
        local = self.sandbox.home / ".config/hypr-rice/waybar/config.local.json"
        local.write_text("{ not json")
        result = self.sandbox.themegen("apply", "night")
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("waybar", result.stderr)
        self.assertIn("config.local.json", result.stderr)
        self.assertNotIn("Traceback", result.stderr)
        # Steps after waybar's ran all the same.
        for written in (self.hypr / "hyprlock-colors.conf", self.sandbox.home / ".config/gtk-3.0/gtk.css",
                        self.sandbox.home / ".config/hypr-rice/kitty/theme.conf"):
            self.assertTrue(written.exists(), written)

    def test_a_good_theme_applies_with_status_0(self):
        result = self.sandbox.themegen("apply", "night")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_a_theme_that_is_not_there_is_one_line(self):
        for name in ("nope", "../themes/night", ".."):
            result = self.sandbox.themegen("apply", name)
            self.assertEqual(result.returncode, 1, name)
            self.assertEqual(result.stderr.strip(), f"нет темы «{name}»")

    def test_commands_work_without_gtk_and_fonttools(self):
        blocked = self.sandbox.root / "blocked"
        for module in ("gi", "fontTools"):
            (blocked / module).mkdir(parents=True)
            (blocked / module / "__init__.py").write_text("raise ImportError('blocked by the test')\n")
        result = self.sandbox.run(["python3", self.sandbox.home / ".config/hypr/scripts/themegen.py",
                                   "wallpapers", "night"], PYTHONPATH=str(blocked))
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
