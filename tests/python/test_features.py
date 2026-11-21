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

    def test_switching_drive_notifications_restarts_the_automounter_only(self):
        self.assertTrue(features.BY_ID["automount"].default)
        self.assertFalse(features.BY_ID["automount-notify"].default)
        self.assertEqual(self.features("on", "automount-notify").returncode, 0)
        self.assertEqual(self.features("is", "automount-notify").returncode, 0)
        self.assertEqual([call for call in self.sandbox.recorded() if call.startswith("systemctl")],
                         ["systemctl --user try-restart rice-udiskie.service"])

    def test_the_automounter_starts_with_notifications_only_when_they_are_on(self):
        self.sandbox.stub("udiskie")
        automount = LIVE_HOME / ".local/bin/rice-automount"
        self.assertEqual(self.sandbox.run([automount], WAYLAND_DISPLAY="wayland-test").returncode, 0)
        self.features("on", "automount-notify")
        self.assertEqual(self.sandbox.run([automount], WAYLAND_DISPLAY="wayland-test").returncode, 0)
        self.assertEqual([call for call in self.sandbox.recorded() if call.startswith("udiskie")],
                         ["udiskie --no-notify", "udiskie --notify"])

    def test_the_automounter_fails_without_a_wayland_display_so_the_service_retries(self):
        self.sandbox.stub("udiskie")
        self.assertEqual(self.sandbox.run([LIVE_HOME / ".local/bin/rice-automount"]).returncode, 1)
        self.assertFalse([call for call in self.sandbox.recorded() if call.startswith("udiskie")])

    def test_write_never_restarts_the_automounter(self):
        self.assertEqual(self.features("write").returncode, 0)
        self.assertNotIn("systemctl --user try-restart rice-udiskie.service", self.sandbox.recorded())

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
        self.assertEqual(set(listed[0]), {"id", "group", "name", "about", "on", "needs", "missing", "experimental",
                                             "closedPorts"})


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


class FirewallPortsTest(unittest.TestCase):
    """closed_ports reads ufw's own files: ufw.conf for whether it is on, user.rules for what it lets in."""
    RULE = "### tuple ### allow {} 1714:1764 0.0.0.0/0 any 0.0.0.0/0 in\n"

    def setUp(self):
        self.sandbox = Sandbox()
        self.config = self.sandbox.home / "ufw.conf"
        self.rules = self.sandbox.home / "user.rules"
        self.config.write_text("ENABLED=yes\n")
        self.rules.write_text("")
        for name, path in (("UFW_CONFIG", self.config), ("UFW_RULES", self.rules)):
            patcher = mock.patch.object(features, name, path)
            patcher.start()
            self.addCleanup(patcher.stop)
        self.item = features.Feature("phone", "g", "Телефон", "", ports=("1714:1764/tcp", "1714:1764/udp"))

    def tearDown(self):
        self.sandbox.cleanup()

    def test_ports_without_a_rule_are_closed(self):
        self.rules.write_text(self.RULE.format("tcp"))
        self.assertEqual(features.closed_ports(self.item), ["1714:1764/udp"])

    def test_a_rule_for_any_protocol_opens_both(self):
        self.rules.write_text(self.RULE.format("any"))
        self.assertEqual(features.closed_ports(self.item), [])

    def test_nothing_is_closed_while_ufw_is_off(self):
        self.config.write_text("ENABLED=no\n")
        self.assertEqual(features.closed_ports(self.item), [])

    def test_opening_asks_one_password_for_the_closed_ports(self):
        self.rules.write_text(self.RULE.format("tcp"))
        with mock.patch.object(features, "BY_ID", {"phone": self.item}), \
                mock.patch.object(features.subprocess, "run",
                                  return_value=subprocess.CompletedProcess([], 0, "", "")) as run:
            features.open_ports("phone")
        command = run.call_args.args[0]
        self.assertEqual(command[0], "pkexec")
        self.assertEqual(command[-1:], ["1714:1764/udp"])

    def test_a_cancelled_password_is_an_error(self):
        with mock.patch.object(features, "BY_ID", {"phone": self.item}), \
                mock.patch.object(features.subprocess, "run",
                                  return_value=subprocess.CompletedProcess([], 126, "", "")):
            with self.assertRaises(OSError):
                features.open_ports("phone")


# Loads the live hyprland.lua with an `hl` that accepts any call, and prints what the features decide.
LUA_DRIVER = r"""
local function anything()
    return setmetatable({}, { __index = function() return anything() end, __call = function() return anything() end })
end
hl = anything()
rawset(hl, "config", function(options)
    if options.animations then print("animations " .. tostring(options.animations.enabled)) end
    if options.general then print("layout " .. options.general.layout) end
end)
rawset(hl, "gesture", function(spec) print("gesture " .. spec.fingers .. " " .. spec.action) end)
rawset(hl, "dsp", setmetatable({ layout = function(message) print("layoutmsg " .. message) end },
                               { __index = function() return anything() end }))
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
        self.assertIn("gesture 3 workspace", lines)
        self.assertEqual({line for line in lines if line.startswith("blur")}, {"blur true"})
        self.assertNotIn("layout scrolling", lines)
        self.assertIn("layoutmsg togglesplit", lines)

    def test_off_as_written(self):
        self.state.write_text('{"animations": false, "gestures": false, "menu-blur": false}')
        lines = self.config_lines()
        self.assertIn("animations false", lines)
        self.assertFalse(any(line.startswith("gesture") for line in lines), lines)
        self.assertEqual({line for line in lines if line.startswith("blur")}, {"blur false"})

    def test_scrolling_takes_the_layout_the_keys_and_three_fingers(self):
        self.state.write_text('{"gestures": true, "scrolling": true}')
        lines = self.config_lines()
        self.assertIn("layout scrolling", lines)
        self.assertEqual([line for line in lines if line.startswith("gesture")],
                         ["gesture 3 scroll_move", "gesture 4 workspace"])
        self.assertEqual([line for line in lines if line.startswith("layoutmsg")],
                         ["layoutmsg colresize +conf", "layoutmsg fit visible"])

    def test_a_missing_state_is_reported(self):
        lines = self.config_lines()
        self.assertTrue(any(line.startswith("notification Нет features.json") for line in lines), lines)
        self.assertIn("animations false", lines)


if __name__ == "__main__":
    unittest.main()
