"""The apptheme modules' own rules: how files are written, what a theme falls back to."""
import unittest

from rice_sandbox import Sandbox


class AppthemeTest(unittest.TestCase):
    def setUp(self):
        self.sandbox = Sandbox()

    def tearDown(self):
        self.sandbox.cleanup()

    def check(self, code):
        result = self.sandbox.python(code)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result

    def test_write_keeps_the_mode_and_leaves_no_temporary_file(self):
        self.check("""
import os
from pathlib import Path
from apptheme.files import write
path = Path.home() / "conf/settings.json"
path.parent.mkdir()
path.write_text("old")
path.chmod(0o600)
write(path, "new")
assert path.read_text() == "new" and (path.stat().st_mode & 0o777) == 0o600, oct(path.stat().st_mode)
assert sorted(p.name for p in path.parent.iterdir()) == ["settings.json"], list(path.parent.iterdir())
""")

    def test_a_failed_write_leaves_the_old_file(self):
        self.check("""
import os
from pathlib import Path
from apptheme import files
path = Path.home() / "settings.json"
path.write_text("old")
def failing_replace(source, target):
    raise OSError("disk full")
os.replace = failing_replace
try:
    files.write(path, "new")
    raise AssertionError("no error")
except OSError:
    pass
assert path.read_text() == "old"
assert [p.name for p in Path.home().iterdir() if p.name.startswith(".settings")] == []
""")

    def test_write_replaces_a_symlink_and_writes_through_a_resolved_one(self):
        self.check("""
from pathlib import Path
from apptheme.files import write
home = Path.home()
(home / "theme.css").write_text("the theme's own")
(home / "generated.css").symlink_to(home / "theme.css")
write(home / "generated.css", "generated")
assert not (home / "generated.css").is_symlink() and (home / "theme.css").read_text() == "the theme's own"
(home / "dotfiles.json").write_text("{}")
(home / "settings.json").symlink_to(home / "dotfiles.json")
write((home / "settings.json").resolve(), "{1}")
assert (home / "settings.json").is_symlink() and (home / "dotfiles.json").read_text() == "{1}"
""")

    def test_set_gtk_ini_adds_a_missing_key(self):
        self.check("""
from apptheme.icon_theme import SETTINGS_FILES, set_gtk_ini
gtk3, gtk4 = SETTINGS_FILES
gtk3.parent.mkdir(parents=True)
gtk4.parent.mkdir(parents=True)
gtk3.write_text("[Settings]\\ngtk-theme-name=Graphite-Dark\\ngtk-icon-theme-name=Papirus\\n")
gtk4.write_text("gtk-theme-name=Graphite-Dark")
set_gtk_ini("gtk-icon-theme-name", "breeze-dark")
set_gtk_ini("gtk-cursor-theme-size", 32)
assert gtk3.read_text() == ("[Settings]\\ngtk-cursor-theme-size=32\\ngtk-theme-name=Graphite-Dark\\n"
                            "gtk-icon-theme-name=breeze-dark\\n"), gtk3.read_text()
assert gtk4.read_text() == ("gtk-theme-name=Graphite-Dark\\n[Settings]\\ngtk-cursor-theme-size=32\\n"
                            "gtk-icon-theme-name=breeze-dark\\n"), gtk4.read_text()
""")

    def test_a_failed_factory_copy_keeps_the_theme(self):
        self.check("""
from pathlib import Path
from apptheme import factory_reset
from apptheme.paths import THEMES
folder = THEMES / "night"
folder.mkdir(parents=True)
(folder / "palette.json").write_text("mine")
source = Path.home() / "rice-copy/night"
source.mkdir(parents=True)
(source / "palette.json").write_text("rice")
(source / "broken-link").symlink_to(source / "missing")  # copytree cannot copy what a link points at
try:
    factory_reset.replace_folder(folder, source)
    raise AssertionError("no error")
except OSError:
    pass
assert (folder / "palette.json").read_text() == "mine"
(source / "broken-link").unlink()
factory_reset.replace_folder(folder, source)
assert (folder / "palette.json").read_text() == "rice"
assert sorted(p.name for p in THEMES.parent.iterdir()) == ["scripts", "themes"], list(THEMES.parent.iterdir())
""")

    def test_gtk4_imports_the_base_theme_that_was_chosen(self):
        self.check("""
from apptheme import gtk
assert gtk.gtk4_import("Adwaita-dark", "gtk.css") == ""
graphite = gtk.Path("/usr/share/themes/Graphite-Dark/gtk-4.0/gtk.css")
if graphite.exists():
    assert gtk.gtk4_import("Graphite-Dark", "gtk.css") == f'@import url("file://{graphite}");\\n'
""")

    def test_a_theme_without_hyprlock_conf_gets_the_plain_one(self):
        self.sandbox.add_theme("night")
        bare = self.sandbox.add_theme("bare")
        (bare / "hyprlock.conf").unlink()
        self.check("""
from apptheme import hyprlock
from apptheme.files import GENERATED
from apptheme.paths import HYPR
from apptheme.theme import load
hyprlock.apply(load("night"), None)
assert (HYPR / "hyprlock.conf").is_symlink()
hyprlock.apply(load("bare"), None)
link = HYPR / "hyprlock.conf"
assert not link.is_symlink() and GENERATED in link.read_text() and "input-field" in link.read_text()
""")

    def test_config_local_json_must_keep_modules_as_tables(self):
        self.sandbox.add_theme("night")
        local = self.sandbox.home / ".config/hypr-rice/waybar/config.local.json"
        local.write_text('{"clock": ["not", "a", "module"]}')
        result = self.sandbox.python("""
from apptheme import waybar
from apptheme.theme import load
waybar.write_config(load("night"))
""")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("config.local.json", result.stderr)
        self.assertIn("«clock»", result.stderr)
        local.write_text('{"clock": {"format": "x"}, "height": 30}')
        self.check("""
import json
from apptheme import waybar
from apptheme.paths import RICE_CONF
from apptheme.theme import load
waybar.write_config(load("night"))
config = json.loads((RICE_CONF / "waybar/config.json").read_text())
assert config["clock"]["format"] == "x" and len(config["clock"]) > 1 and config["height"] == 30, config["clock"]
""")

    def test_the_extension_under_its_old_id_is_uninstalled(self):
        self.sandbox.add_theme("night")
        old = self.sandbox.home / ".vscode-oss/extensions/larion.hypr-themes-1.0.1"
        old.mkdir(parents=True)
        self.check("""
from apptheme import vscode
from apptheme.theme import load
vscode.build([load("night")])
""")
        calls = self.sandbox.recorded()
        self.assertTrue(any(call.startswith("code-oss --install-extension") for call in calls), calls)
        self.assertIn("code-oss --uninstall-extension larion.hypr-themes", calls)
        old.rmdir()
        self.sandbox.calls.unlink()
        self.check("""
from apptheme import vscode
from apptheme.theme import load
vscode.build([load("night")])
""")
        self.assertFalse(any("--uninstall-extension" in call for call in self.sandbox.recorded()))

    def test_neohtop_without_a_checkout_does_nothing(self):
        self.sandbox.add_theme("night")
        (self.sandbox.home / "neohtop").mkdir()  # some other folder of that name
        self.check("""
from apptheme import neohtop
from apptheme.theme import load
assert neohtop.build([load("night")]) is None
""")
        self.assertEqual(list((self.sandbox.home / "neohtop").iterdir()), [])


if __name__ == "__main__":
    unittest.main()
