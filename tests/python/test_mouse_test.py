"""mouse_test.py (rice mouse-test): the angle, resolution and polling rate counted from a mouse's reports, the
strokes split by the reports' times, the rotation offered and saved. No real device or Hyprland is touched:
events go through a FIFO, hyprctl and the answers are stand-ins."""
import math
import os
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from rice_sandbox import LIVE_SCRIPTS

sys.path.insert(0, str(LIVE_SCRIPTS))
import devices_lua  # noqa: E402  (the live scripts folder goes on the path first)
import mouse_test  # noqa: E402

REPORT_SECONDS = 0.001


def line(degrees, count=200, step=10):
    """Summed counts of a straight stroke at this clockwise angle."""
    radians = math.radians(degrees)
    return [(round(n * step * math.cos(radians)), round(n * step * math.sin(radians))) for n in range(1, count + 1)]


def reports(start, moves):
    """input_event bytes: each (dx, dy) as REL_X, REL_Y and a SYN_REPORT, one report per millisecond."""
    data = b""
    for index, (dx, dy) in enumerate(moves):
        moment = start + index * REPORT_SECONDS
        seconds, microseconds = int(moment), round(moment % 1 * 1e6)
        for kind, code, value in ((mouse_test.EV_REL, mouse_test.REL_X, dx),
                                  (mouse_test.EV_REL, mouse_test.REL_Y, dy), (mouse_test.EV_SYN, 0, 0)):
            data += mouse_test.EVENT.pack(seconds, microseconds, kind, code, value)
    return data


class CountingTest(unittest.TestCase):
    def test_angle_of_a_stroke_either_way_along_the_line(self):
        self.assertAlmostEqual(mouse_test.line_angle(line(5)), 5, places=0)
        self.assertAlmostEqual(mouse_test.line_angle(line(-3)), -3, places=0)
        self.assertAlmostEqual(mouse_test.line_angle(line(183)), 3, places=0)

    def test_rotation_turns_the_reported_line_back_clockwise(self):
        self.assertEqual(mouse_test.rotation_for(5.2), 355)
        self.assertEqual(mouse_test.rotation_for(-3.4), 3)
        self.assertEqual(mouse_test.rotation_for(0.2), 0)

    def test_a_straight_stroke_does_not_wobble(self):
        self.assertLess(mouse_test.wobble_percent(line(4)), 0.1)

    def test_counts_per_inch_and_polling_rate(self):
        stroke = mouse_test.Stroke(points=[(0, 0), (3150, 0)], times=[0.0, 0.001])
        self.assertAlmostEqual(mouse_test.counts_per_inch(stroke, 100), 800, places=0)
        strokes = [mouse_test.Stroke(times=[n * REPORT_SECONDS for n in range(50)])]
        self.assertAlmostEqual(mouse_test.polling_rate(strokes), 1000, places=0)


class ReaderTest(unittest.TestCase):
    def setUp(self):
        self.folder = Path(tempfile.mkdtemp(prefix="mouse-test-"))
        fifo = self.folder / "event"
        os.mkfifo(fifo)
        self.reader = mouse_test.Reader(fifo)
        self.writer = os.open(fifo, os.O_WRONLY)

    def tearDown(self):
        os.close(self.writer)
        shutil.rmtree(self.folder)

    def test_strokes_are_split_by_the_reports_times_and_short_motion_is_skipped(self):
        settling = [(1, 0)] * 50
        stroke = [(10, 1)] * 150
        os.write(self.writer, reports(100.0, settling) + reports(101.0, stroke) + reports(102.0, stroke))
        first = self.reader.stroke()
        second = self.reader.stroke()
        self.assertEqual(first.points[-1], (1500, 150))
        self.assertEqual(second.points[-1], (1500, 150))
        self.assertEqual(second.times[0], 102.0)

    def test_drain_forgets_the_motion_made_before(self):
        os.write(self.writer, reports(100.0, [(10, 0)] * 150))
        self.reader.drain()
        os.write(self.writer, reports(200.0, [(0, 10)] * 150))
        self.assertEqual(self.reader.stroke().points[-1], (0, 1500))


class OfferRotationTest(unittest.TestCase):
    def setUp(self):
        self.folder = Path(tempfile.mkdtemp(prefix="mouse-test-"))
        self.path = self.folder / "devices.lua"
        self.path.write_text('hl.device({ name = "mouse", sensitivity = -0.45 })\n')
        patches = (mock.patch.object(devices_lua, "PATH", self.path),
                   mock.patch.object(mouse_test.subprocess, "run", return_value=mock.Mock(returncode=0)),
                   mock.patch("builtins.print"))
        for patch in patches:
            patch.start()
            self.addCleanup(patch.stop)
        self.hyprctl = mouse_test.subprocess.run

    def tearDown(self):
        shutil.rmtree(self.folder)

    def offer(self, angle, spread, answer="y"):
        with mock.patch("builtins.input", return_value=answer):
            mouse_test.offer_rotation("mouse", angle, spread)

    def test_a_clear_angle_is_saved_with_the_other_settings_and_applied(self):
        self.offer(4.6, 0.8)
        self.assertEqual(devices_lua.read(self.path), {"mouse": {"sensitivity": -0.45, "rotation": 355}})
        self.assertEqual(self.hyprctl.call_args.args[0],
                         ["hyprctl", "eval", 'hl.device({ name = "mouse", sensitivity = -0.45, rotation = 355 })'])

    def test_an_angle_within_the_strokes_spread_is_no_reason_to_rotate(self):
        self.offer(1.5, 2.0)
        self.assertEqual(devices_lua.read(self.path), {"mouse": {"sensitivity": -0.45}})
        self.hyprctl.assert_not_called()

    def test_a_no_keeps_the_file(self):
        self.offer(4.6, 0.8, answer="n")
        self.assertEqual(devices_lua.read(self.path), {"mouse": {"sensitivity": -0.45}})


if __name__ == "__main__":
    unittest.main()
