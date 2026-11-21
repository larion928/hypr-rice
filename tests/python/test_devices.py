"""devices_lua.py, the devices.lua reader and writer, and mice.py, the pointing devices read from /sys."""
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

from rice_sandbox import LIVE_SCRIPTS

sys.path.insert(0, str(LIVE_SCRIPTS))
import devices_lua  # noqa: E402  (the live scripts folder goes on the path first)
import mice  # noqa: E402


class DevicesLuaTest(unittest.TestCase):
    def setUp(self):
        self.folder = Path(tempfile.mkdtemp(prefix="devices-lua-"))
        self.path = self.folder / "devices.lua"

    def tearDown(self):
        shutil.rmtree(self.folder)

    def test_reads_every_setting_of_every_line_and_skips_comments(self):
        self.path.write_text('-- a comment\n'
                             'hl.device({ name = "vxe-r1se+-mouse", sensitivity = -0.45, rotation = 357 })\n'
                             'hl.device({ name = "pad", natural_scroll = true })\n')
        self.assertEqual(devices_lua.read(self.path), {"vxe-r1se+-mouse": {"sensitivity": -0.45, "rotation": 357},
                                                       "pad": {"natural_scroll": True}})

    def test_saving_one_setting_keeps_the_others_and_the_other_lines(self):
        self.path.write_text('-- keep me\n'
                             'hl.device({ name = "mouse", sensitivity = -0.45, rotation = 357 })\n'
                             'hl.device({ name = "other", sensitivity = 0.20 })\n')
        devices_lua.save("mouse", {"sensitivity": -0.3}, self.path)
        self.assertEqual(self.path.read_text(),
                         '-- keep me\n'
                         'hl.device({ name = "mouse", sensitivity = -0.30, rotation = 357 })\n'
                         'hl.device({ name = "other", sensitivity = 0.20 })\n')

    def test_a_device_without_a_line_gets_one_at_the_end(self):
        self.path.write_text("-- header\n")
        devices_lua.save("new mouse", {"rotation": 4}, self.path)
        self.assertEqual(self.path.read_text(), '-- header\nhl.device({ name = "new mouse", rotation = 4 })\n')

    def test_saving_creates_a_missing_file(self):
        devices_lua.save("mouse", {"sensitivity": 0.0}, self.path)
        self.assertEqual(devices_lua.read(self.path), {"mouse": {"sensitivity": 0.0}})


class MiceTest(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix="mice-"))

    def tearDown(self):
        shutil.rmtree(self.root)

    def device(self, event, name, bus, rel="0", abs_="0", key="0"):
        folder = self.root / "sys/class/input" / event / "device"
        (folder / "id").mkdir(parents=True)
        (folder / "capabilities").mkdir()
        (folder / "name").write_text(name + "\n")
        (folder / "id/bustype").write_text(f"{bus:04x}\n")
        for capability, mask in (("rel", rel), ("abs", abs_), ("key", key)):
            (folder / "capabilities" / capability).write_text(mask + "\n")

    def test_only_real_pointers_count_and_only_usb_or_bluetooth_mice_are_external_mice(self):
        buttons = "1f0000 0 0 0 0"  # BTN_LEFT..BTN_EXTRA: bits 0x110-0x114, in the fifth word from the end
        self.device("event6", "CX Wireless mouse -1k dongle Mouse", mice.BUS_USB, rel="1943", key=buttons)
        self.device("event8", "CX Wireless mouse -1k dongle Consumer Control", mice.BUS_USB, rel="1040", key="1")
        self.device("event10", "SYNA0001:00 06CB:CE2D Touchpad", 0x18, abs_="660800011000003", key=buttons)
        self.device("event12", "BT Mouse", mice.BUS_BLUETOOTH, rel="3", key=buttons)
        self.device("event20", "ydotoold virtual device", mice.BUS_VIRTUAL, rel="3", key=buttons)

        self.assertEqual([pointer.name for pointer in mice.pointers(self.root)],
                         ["cx-wireless-mouse--1k-dongle-mouse", "syna0001:00-06cb:ce2d-touchpad", "bt-mouse"])
        self.assertEqual([(pointer.name, str(pointer.node)) for pointer in mice.external_mice(self.root)],
                         [("cx-wireless-mouse--1k-dongle-mouse", "/dev/input/event6"),
                          ("bt-mouse", "/dev/input/event12")])

    def test_hyprland_numbered_name_is_the_same_device(self):
        self.assertTrue(mice.same_device("mouse-1", "mouse"))
        self.assertTrue(mice.same_device("mouse", "mouse"))
        self.assertFalse(mice.same_device("mouse-pad", "mouse"))


if __name__ == "__main__":
    unittest.main()
