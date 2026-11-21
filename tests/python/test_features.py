"""features.py, the registry of the rice's features, and the Hyprland config that follows its state."""
import json
import shutil
import subprocess
import sys
import unittest
from unittest import mock

from rice_sandbox import LIVE_HOME, LIVE_SCRIPTS, Sandbox

sys.path.insert(0, str(LIVE_SCRIPTS))
import features  # noqa: E402  (the live scripts folder goes on the path first)


class FeaturesCommandTest(unittest.TestCase):
    def setUp(self):
        self.sandbox = Sandbox()
        self.state = self.sandbox.home / ".config/hypr-rice/features.json"

    def tearDown(self):
        self.sandbox.cleanup()

    def features(self, *args, **env):
        return self.sandbox.run(["python3", self.sandbox.home / ".config/hypr/scripts/features.py", *args], **env)

    def saved(self):
        return json.loads(self.state.read_text())

    def test_write_keeps_choices_adds_new_features_and_drops_gone_ones(self):
        self.state.parent.mkdir(parents=True, exist_ok=True)
        self.state.write_text('{"animations": false, "removed-long-ago": true}')
        result = self.features("write")
        self.assertEqual(result.returncode, 0, result.stderr)
        expected = {item.id: item.default for item in features.FEATURES}
        expected["animations"] = False
        self.assertEqual(self.saved(), expected)
        self.assertIn("systemctl --user enable --now rice-doctor.timer", self.sandbox.recorded())

    def test_a_broken_file_gives_the_defaults(self):
        self.state.parent.mkdir(parents=True, exist_ok=True)
        self.state.write_text("{not json")
        self.assertEqual(self.features("write").returncode, 0)
        self.assertEqual(self.saved(), {item.id: item.default for item in features.FEATURES})

    def test_off_and_on_switch_one_feature_and_its_unit(self):
        self.assertEqual(self.features("off", "daily-check").returncode, 0)
        self.assertFalse(self.saved()["daily-check"])
        self.assertTrue(self.saved()["animations"])
        self.assertEqual(self.features("is", "daily-check").returncode, 1)
        self.assertEqual(self.features("on", "daily-check").returncode, 0)
        self.assertEqual(self.features("is", "daily-check").returncode, 0)
        self.assertEqual([call for call in self.sandbox.recorded() if call.startswith("systemctl")],
                         ["systemctl --user disable --now rice-doctor.timer",
                          "systemctl --user enable --now rice-doctor.timer"])

    def test_clipboard_history_is_off_by_default_and_wiped_when_switched_off(self):
        self.assertFalse(features.BY_ID["clipboard"].default)
        self.sandbox.stub("cliphist")
        self.sandbox.stub("pacman")  # pacman -T: every package is installed
        self.assertEqual(self.features("on", "clipboard").returncode, 0)
        self.assertEqual(self.features("off", "clipboard").returncode, 0)
        calls = [call for call in self.sandbox.recorded() if call.startswith(("systemctl", "cliphist"))]
        self.assertEqual(calls, ["systemctl --user enable --now rice-clipboard.service",
                                 "systemctl --user disable --now rice-clipboard.service",
                                 "cliphist wipe"])

    def test_write_never_wipes_the_clipboard_history(self):
        self.sandbox.stub("cliphist")
        self.assertEqual(self.features("write").returncode, 0)
        self.assertNotIn("cliphist wipe", self.sandbox.recorded())

    def test_hyprland_reloads_only_inside_its_session_and_for_its_features(self):
        self.features("off", "animations")
        self.assertNotIn("hyprctl reload", self.sandbox.recorded())
        self.features("off", "animations", HYPRLAND_INSTANCE_SIGNATURE="test")
        self.assertIn("hyprctl reload", self.sandbox.recorded())
        self.sandbox.calls.unlink()
        self.features("off", "shutter-sound", HYPRLAND_INSTANCE_SIGNATURE="test")
        self.assertNotIn("hyprctl reload", self.sandbox.recorded())

    def test_an_unknown_feature_is_a_message(self):
        result = self.features("on", "no-such-feature")
        self.assertEqual(result.returncode, 1)
        self.assertIn("нет такой функции", result.stderr)
        self.assertFalse(self.state.exists())

    def test_list_gives_every_feature_in_order(self):
        result = self.features("list")
        self.assertEqual(result.returncode, 0, result.stderr)
        listed = json.loads(result.stdout)
        self.assertEqual([item["id"] for item in listed], [item.id for item in features.FEATURES])
        self.assertEqual(set(listed[0]), {"id", "group", "name", "about", "on", "needs", "missing"})


class MissingPackageTest(unittest.TestCase):
    """A feature that needs a package which is not installed is not switched on."""

    def setUp(self):
        self.sandbox = Sandbox()
        needy = features.Feature("needy", "Тест", "Нужен пакет", "", default=False, needs=("cliphist",))
        self.patches = [mock.patch.object(features, "STATE", self.sandbox.home / "features.json"),
                        mock.patch.object(features, "FEATURES", features.FEATURES + (needy,)),
                        mock.patch.dict(features.BY_ID, {"needy": needy})]
        for patch in self.patches:
            patch.start()

    def tearDown(self):
        for patch in reversed(self.patches):
            patch.stop()
        self.sandbox.cleanup()

    def pacman_says_missing(self, missing):
        return mock.patch.object(features.subprocess, "run", return_value=subprocess.CompletedProcess(
            [], 127 if missing else 0, stdout="\n".join(missing), stderr=""))

    def test_refused_while_missing(self):
        with self.pacman_says_missing(["cliphist"]):
            with self.assertRaisesRegex(ValueError, "cliphist"):
                features.switch("needy", True)
            self.assertEqual(features.listing()[-1]["missing"], ["cliphist"])
        self.assertFalse(features.state()["needy"])

    def test_switched_on_once_installed(self):
        with self.pacman_says_missing([]):
            features.switch("needy", True)
        self.assertTrue(features.state()["needy"])


# Loads the live hyprland.lua with an `hl` that accepts any call, and prints what the features decide.
LUA_DRIVER = r"""
local function anything()
    return setmetatable({}, { __index = function() return anything() end, __call = function() return anything() end })
end
hl = anything()
rawset(hl, "config", function(options)
    if options.animations then print("animations " .. tostring(options.animations.enabled)) end
end)
rawset(hl, "gesture", function() print("gesture") end)
rawset(hl, "layer_rule", function(rule)
    if rule.name:find("blur") then print("blur " .. tostring(rule.blur)) end
end)
rawset(hl, "notification", { create = function(note) print("notification " .. note.text) end })
package.path = HYPR .. "/?.lua;" .. package.path
package.preload["theme"] = function() end
dofile(HYPR .. "/hyprland.lua")
"""


@unittest.skipUnless(shutil.which("lua"), "no lua")
class HyprlandFollowsFeaturesTest(unittest.TestCase):
    def setUp(self):
        self.sandbox = Sandbox()
        self.state = self.sandbox.home / ".config/hypr-rice/features.json"

    def tearDown(self):
        self.sandbox.cleanup()

    def config_lines(self):
        script = f"HYPR = {json.dumps(str(LIVE_HOME / '.config/hypr'))}\n" + LUA_DRIVER
        result = subprocess.run(["lua", "-"], input=script, env=self.sandbox.env(), capture_output=True, text=True,
                                timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.splitlines()

    def test_on_as_written(self):
        self.state.write_text(json.dumps({"animations": True, "gestures": True, "menu-blur": True}, indent=2))
        lines = self.config_lines()
        self.assertIn("animations true", lines)
        self.assertIn("gesture", lines)
        self.assertEqual({line for line in lines if line.startswith("blur")}, {"blur true"})

    def test_off_as_written(self):
        self.state.write_text('{"animations": false, "gestures": false, "menu-blur": false}')
        lines = self.config_lines()
        self.assertIn("animations false", lines)
        self.assertNotIn("gesture", lines)
        self.assertEqual({line for line in lines if line.startswith("blur")}, {"blur false"})

    def test_a_missing_state_is_reported(self):
        lines = self.config_lines()
        self.assertTrue(any(line.startswith("notification Нет features.json") for line in lines), lines)
        self.assertIn("animations false", lines)


if __name__ == "__main__":
    unittest.main()
