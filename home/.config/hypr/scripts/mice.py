"""The pointing devices the kernel sees, read from /sys: which of them are real (not a virtual device such as
ydotoold's), which are mice plugged in by USB or Bluetooth (not a laptop's touchpad), and the name Hyprland
gives each one, which devices.lua lines are keyed by."""
from dataclasses import dataclass
from pathlib import Path

BUS_USB = 0x03
BUS_BLUETOOTH = 0x05
BUS_VIRTUAL = 0x06
REL_X = 0x00
ABS_X = 0x00
BTN_LEFT = 0x110


@dataclass(frozen=True)
class Pointer:
    name: str  # Hyprland's name of it: the kernel's lowercased, spaces as dashes
    node: Path  # /dev/input/eventN, whose events rice mouse-test reads
    external: bool  # plugged in by USB or Bluetooth
    relative: bool  # reports motion in sensor counts (a mouse), not positions (a touchpad, a tablet)


def pointers(root=Path("/")):
    """Every real pointing device, in event node order."""
    found = []
    for event in sorted((root / "sys/class/input").glob("event*"), key=lambda path: int(path.name[5:])):
        device = event / "device"
        bus = int(read(device / "id/bustype") or "0", 16)
        relative = has_bit(device / "capabilities/rel", REL_X)
        absolute = has_bit(device / "capabilities/abs", ABS_X)
        if bus == BUS_VIRTUAL or not has_bit(device / "capabilities/key", BTN_LEFT) or not (relative or absolute):
            continue
        found.append(Pointer(name=hyprland_name(read(device / "name")), node=Path("/dev/input") / event.name,
                             external=bus in (BUS_USB, BUS_BLUETOOTH), relative=relative))
    return found


def external_mice(root=Path("/")):
    return [pointer for pointer in pointers(root) if pointer.external and pointer.relative]


def hyprland_name(kernel_name):
    return kernel_name.strip().lower().replace(" ", "-")


def same_device(hyprland_listed, pointer_name):
    """Hyprland numbers a repeated name (name-1, name-2); the numbered one is still that device."""
    base, _, number = hyprland_listed.rpartition("-")
    return hyprland_listed == pointer_name or (number.isdigit() and base == pointer_name)


def read(path):
    try:
        return path.read_text().strip()
    except OSError:
        return ""


def has_bit(path, bit):
    """A capabilities file is a bitmask in hex words of 64 bits, the most significant word first."""
    words = read(path).split()
    mask = 0
    for word in words:
        mask = (mask << 64) | int(word, 16)
    return bool(mask >> bit & 1)
