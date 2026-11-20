"""What keeps a theme switch fast: the browsers' wallpaper JPEGs come from a cache and are not made at all
without a browser profile, GTK is reloaded only for new sheets and waits for the settings portal instead of
a fixed time."""
import shutil
import unittest

from rice_sandbox import Sandbox


class BrowserWallpaperTest(unittest.TestCase):
    def setUp(self):
        self.sandbox = Sandbox()
        self.sandbox.add_theme("night")

    def tearDown(self):
        self.sandbox.cleanup()

    def check(self, code):
        result = self.sandbox.python(code)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_a_wallpaper_is_encoded_once_per_version_and_size(self):
        self.check("""
import os
from pathlib import Path
from PIL import Image
from apptheme.apps import browser
wallpaper = Path.home() / "wall.png"
Image.new("RGB", (64, 32), (200, 0, 0)).save(wallpaper)
first = browser.wallpaper_jpeg(wallpaper, 16, 80)
real_open = browser.Image.open
def no_decoding(*args):
    raise AssertionError("decoded again")
browser.Image.open = no_decoding
assert browser.wallpaper_jpeg(wallpaper, 16, 80) == first
browser.Image.open = real_open
assert browser.wallpaper_jpeg(wallpaper, 8, 80) != first, "another size is another picture"

Image.new("RGB", (64, 32), (0, 0, 200)).save(wallpaper)
os.utime(wallpaper, ns=(1, 1))
changed = browser.wallpaper_jpeg(wallpaper, 16, 80)
assert changed != first, "a changed wallpaper came from the cache"
entries = sorted(browser.JPEG_CACHE.iterdir())
assert len(entries) == 2, entries  # the old version's 16 px entry is gone, the 8 px one stays
""")

    def test_firefox_without_profiles_decodes_nothing(self):
        self.check("""
from pathlib import Path
from PIL import Image
from apptheme.apps import browser, firefox
from apptheme.themes.theme import load
wallpaper = Path.home() / "wall.png"
Image.new("RGB", (64, 32)).save(wallpaper)
def no_decoding(*args):
    raise AssertionError("decoded without a profile")
browser.Image.open = no_decoding
firefox.apply(load("night"), str(wallpaper))
""")


class GtkReloadTest(unittest.TestCase):
    def setUp(self):
        self.sandbox = Sandbox()
        self.sandbox.add_theme("night")

    def tearDown(self):
        self.sandbox.cleanup()

    def test_only_new_sheets_reload_gtk(self):
        day = self.sandbox.add_theme("day")
        (day / "palette.json").write_text((day / "palette.json").read_text().replace('"night"', '"day"', 1))
        result = self.sandbox.python("""
from apptheme.apps import gtk
from apptheme.themes.theme import load
started = []
gtk.reload = lambda: started.append("reload")
gtk.apply(load("night"))
gtk.apply(load("night"))
assert started == ["reload"], started
gtk.apply(load("day"))
assert started == ["reload", "reload"], started
""")
        self.assertEqual(result.returncode, 0, result.stderr)

    @unittest.skipUnless(shutil.which("dbus-run-session") and shutil.which("gdbus"), "no D-Bus tools")
    def test_the_theme_goes_back_once_the_portal_passed_it_on(self):
        # A settings portal on a bus of the test's own: every change of the setting is passed on at once.
        self.sandbox.stub("gsettings", "gdbus emit --session --object-path /org/freedesktop/portal/desktop "
                                       "--signal org.freedesktop.portal.Settings.SettingChanged "
                                       "org.gnome.desktop.interface gtk-theme \"<'$4'>\"")
        elapsed = self.reload_on_own_bus()
        self.assertLess(elapsed, 0.25, "a fixed wait instead of the portal's word")
        self.assert_bounced_to_base()

    @unittest.skipUnless(shutil.which("dbus-run-session"), "no D-Bus tools")
    def test_a_silent_portal_still_gets_the_base_theme_back(self):
        elapsed = self.reload_on_own_bus()
        self.assertGreaterEqual(elapsed, 0.9, "the theme went back without waiting for the portal")
        self.assert_bounced_to_base()

    def test_without_a_session_bus_nothing_is_waited_for(self):
        result = self.sandbox.python("""
import time
from apptheme.apps import gtk
start = time.monotonic()
gtk.reload()
print(time.monotonic() - start)
""")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertLess(float(result.stdout), 0.25)
        self.assert_bounced_to_base()

    def reload_on_own_bus(self):
        """Seconds gtk.reload() took on a D-Bus session bus of its own."""
        scripts = self.sandbox.home / ".config/hypr/scripts"
        code = f"""
import sys, time
sys.path.insert(0, {str(scripts)!r})
from apptheme.apps import gtk
import gi.repository.Gio
start = time.monotonic()
gtk.reload()
print(time.monotonic() - start)
"""
        result = self.sandbox.run(["dbus-run-session", "--", "python3", "-c", code])
        self.assertEqual(result.returncode, 0, result.stderr)
        return float(result.stdout.strip().splitlines()[-1])

    def assert_bounced_to_base(self):
        themes = [call.split()[-1] for call in self.sandbox.recorded() if call.startswith("gsettings set")]
        self.assertEqual(len(themes), 2, themes)
        self.assertNotEqual(themes[0], themes[1])
        self.assertIn(themes[1], ("Graphite-Dark", "Adwaita-dark"))
        self.assertIn("systemctl --user --no-block try-restart xdg-desktop-portal-gtk.service", self.sandbox.recorded())


if __name__ == "__main__":
    unittest.main()
