"""The animated wallpaper pauses only while fullscreen windows hide it: the Hyprland config decides from its
events (driven here through a stand-in `hl` under plain Lua), wallpaper-pause tells mpv through its control
socket (a stand-in socket here), and wallpaper gives mpvpaper that socket."""
import json
import shutil
import socket
import subprocess
import threading
import unittest

from rice_sandbox import LIVE_BIN, LIVE_HOME, Sandbox

SOCKET_NAME = "hypr-rice-wallpaper.sock"

# Loads the live hyprland.lua with an `hl` that accepts any call, then fires the events the test lists.
# Each monitor is {regular workspace's fullscreen mode, special workspace's mode or nil}; a window of
# mode 2 is "w<monitor>". Prints every command the config ran.
LUA_DRIVER = r"""
local function anything()
    return setmetatable({}, { __index = function() return anything() end, __call = function() return anything() end })
end
local handlers = {}
local monitors = {}
hl = anything()
rawset(hl, "on", function(event, callback)
    handlers[event] = handlers[event] or {}
    table.insert(handlers[event], callback)
end)
rawset(hl, "exec_cmd", function(command) print(command) end)
rawset(hl, "get_monitors", function() return monitors end)

local function workspace(mode, owner)
    if mode == nil then
        return nil
    end
    local window = mode > 0 and { address = owner } or nil
    return { fullscreen_mode = mode, has_fullscreen = mode > 0, fullscreen_window = window }
end
local function show(layout)
    monitors = {}
    for index, pair in ipairs(layout) do
        local owner = "w" .. index
        table.insert(monitors, { active_workspace = workspace(pair[1], owner),
                                 active_special_workspace = workspace(pair[2], owner) })
    end
end
local function fire(event, argument)
    for _, callback in ipairs(handlers[event] or {}) do
        callback(argument)
    end
end

package.path = HYPR .. "/?.lua;" .. package.path
-- theme.lua is this machine's link to the current theme: the repo's copy has none, and the events
-- under test do not depend on it.
package.preload["theme"] = function() end
dofile(HYPR .. "/hyprland.lua")
for _, step in ipairs(STEPS) do
    show(step[2])
    print("-- " .. step[1])
    fire(step[1], step[3])
end
"""


def lua_table(value):
    if value is None:
        return "nil"
    if isinstance(value, str):
        return json.dumps(value)
    if isinstance(value, (list, tuple)):
        return "{" + ", ".join(lua_table(item) for item in value) + "}"
    if isinstance(value, dict):
        return "{" + ", ".join(f"{key} = {lua_table(item)}" for key, item in value.items()) + "}"
    return str(value)


@unittest.skipUnless(shutil.which("lua"), "no lua")
class FullscreenEventsTest(unittest.TestCase):
    def setUp(self):
        self.sandbox = Sandbox()
        (self.sandbox.home / ".config/hypr-rice/features.json").write_text('{"wallpaper-pause": true}')

    def tearDown(self):
        self.sandbox.cleanup()

    def commands_after(self, steps):
        """steps: (event, monitors, event argument); returns {event: the pause commands it ran}."""
        script = (f"HYPR = {json.dumps(str(LIVE_HOME / '.config/hypr'))}\n"
                  f"STEPS = {lua_table([list(step) for step in steps])}\n" + LUA_DRIVER)
        result = subprocess.run(["lua", "-"], input=script, env=self.sandbox.env(), capture_output=True, text=True,
                                timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        commands, event = {}, None
        for line in result.stdout.splitlines():
            if line.startswith("-- "):
                event = f"{len(commands)} {line[3:]}"
                commands[event] = []
            elif event and "wallpaper-pause" in line:
                commands[event].append(line.split()[-1])
        return list(commands.values())

    def test_switched_off_it_never_pauses(self):
        (self.sandbox.home / ".config/hypr-rice/features.json").write_text('{"wallpaper-pause": false}')
        self.assertEqual(self.commands_after([("window.fullscreen", [(2, None)], None)]), [["no"]])

    def test_fullscreen_on_a_hidden_workspace_keeps_it_playing(self):
        # A fullscreen window on workspace 10 while workspace 2 is shown: the monitor shows no fullscreen.
        self.assertEqual(self.commands_after([("window.fullscreen", [(0, None)], None)]), [["no"]])

    def test_fullscreen_on_the_shown_workspace_pauses_and_leaving_it_plays(self):
        self.assertEqual(self.commands_after([
            ("workspace.active", [(0, None)], None),
            ("window.fullscreen", [(2, None)], None),
            ("window.active", [(2, None)], None),
            ("window.fullscreen", [(0, None)], None),
        ]), [["no"], ["yes"], [], ["no"]])

    def test_a_maximized_window_does_not_pause_it(self):
        self.assertEqual(self.commands_after([("window.fullscreen", [(1, None)], None)]), [["no"]])

    def test_a_fullscreen_window_in_the_shown_special_workspace_pauses_it(self):
        self.assertEqual(self.commands_after([("workspace.special_active", [(0, 2)], None)]), [["yes"]])

    def test_closing_the_fullscreen_window_plays_it_although_the_workspace_still_counts_it(self):
        self.assertEqual(self.commands_after([
            ("window.fullscreen", [(2, None)], None),
            ("window.close", [(2, None)], {"address": "w1"}),
        ]), [["yes"], ["no"]])

    def test_with_two_monitors_it_pauses_only_when_both_are_covered(self):
        self.assertEqual(self.commands_after([
            ("window.fullscreen", [(2, None), (0, None)], None),
            ("workspace.active", [(2, None), (2, None)], None),
            ("monitor.removed", [(2, None)], None),
        ]), [["no"], ["yes"], []])

    def test_a_restarted_player_gets_the_state_again(self):
        self.assertEqual(self.commands_after([
            ("window.fullscreen", [(2, None)], None),
            ("layer.opened", [(2, None)], {"namespace": "awww-daemon"}),
            ("layer.opened", [(2, None)], {"namespace": "mpvpaper"}),
        ]), [["yes"], [], ["yes"]])


class FakeMpv:
    """A listening control socket that answers every command line as mpv does and keeps what it got."""

    def __init__(self, path):
        self.received = []
        self.server = socket.socket(socket.AF_UNIX)
        self.server.bind(str(path))
        self.server.listen()
        self.thread = threading.Thread(target=self.serve, daemon=True)
        self.thread.start()

    def serve(self):
        while True:
            try:
                connection, _ = self.server.accept()
            except OSError:  # closed by the test
                return
            with connection, connection.makefile("rw") as stream:
                for line in stream:
                    self.received.append(json.loads(line))
                    stream.write('{"data":null,"request_id":0,"error":"success"}\n')
                    stream.flush()

    def close(self):
        self.server.close()


class WallpaperPauseTest(unittest.TestCase):
    def setUp(self):
        self.sandbox = Sandbox()
        self.socket = self.sandbox.runtime / SOCKET_NAME

    def tearDown(self):
        self.sandbox.cleanup()

    def test_it_sets_mpv_pause(self):
        player = FakeMpv(self.socket)
        try:
            paused = self.sandbox.run([LIVE_BIN / "wallpaper-pause", "yes"], timeout=10)
            played = self.sandbox.run([LIVE_BIN / "wallpaper-pause", "no"], timeout=10)
        finally:
            player.close()
        self.assertEqual(paused.returncode, 0, paused.stderr)
        self.assertEqual(played.returncode, 0, played.stderr)
        self.assertEqual([command["command"] for command in player.received],
                         [["set_property", "pause", True], ["set_property", "pause", False]])

    def test_without_an_animated_wallpaper_there_is_nothing_to_do(self):
        result = self.sandbox.run([LIVE_BIN / "wallpaper-pause", "yes"], timeout=10)
        self.assertEqual((result.returncode, result.stderr), (0, ""))

    def test_a_player_that_is_gone_is_nothing_to_do(self):
        stale = socket.socket(socket.AF_UNIX)
        stale.bind(str(self.socket))
        stale.close()
        result = self.sandbox.run([LIVE_BIN / "wallpaper-pause", "no"], timeout=10)
        self.assertEqual((result.returncode, result.stderr), (0, ""))

    def test_anything_but_yes_or_no_is_a_usage_error(self):
        result = self.sandbox.run([LIVE_BIN / "wallpaper-pause", "maybe"], timeout=10)
        self.assertEqual(result.returncode, 1)
        self.assertIn("usage", result.stderr)


class WallpaperPlayerTest(unittest.TestCase):
    def setUp(self):
        self.sandbox = Sandbox()

    def tearDown(self):
        self.sandbox.cleanup()

    @unittest.skipUnless(shutil.which("ffmpeg"), "no ffmpeg")
    def test_the_player_gets_the_control_socket_and_no_pause_for_hidden_fullscreen(self):
        clip = self.sandbox.home / "clip.mp4"
        made = self.sandbox.run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i", "testsrc2=s=320x180:r=10:d=1",
                                 "-c:v", "libx264", "-pix_fmt", "yuv420p", clip])
        self.assertEqual(made.returncode, 0, made.stderr)
        self.sandbox.stub("player")
        result = self.sandbox.run([LIVE_BIN / "wallpaper", clip], WALLPAPER_PLAYER=str(self.sandbox.stubs / "player"))
        self.assertEqual(result.returncode, 0, result.stderr)
        started = [call for call in self.sandbox.recorded() if call.startswith("player ")]
        self.assertEqual(len(started), 1, self.sandbox.recorded())
        self.assertIn(f"input-ipc-server={self.sandbox.runtime / SOCKET_NAME}", started[0])
        self.assertNotIn(" -a ", started[0])
        self.assertIn(" -p ", started[0])


if __name__ == "__main__":
    unittest.main()
