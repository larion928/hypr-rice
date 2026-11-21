"""rice mouse-test: the mouse's sensor angle, resolution (CPI) and polling rate, measured from the counts the
sensor sends, before Hyprland's acceleration and rotation touch them. The user moves the mouse along a ruler:
a straight hand line the sensor reports askew is the sensor's angle, which devices.lua's `rotation` undoes
(libinput turns the motion clockwise by that many whole degrees). The resolution needs a known distance;
the mouse's firmware sets it, so it is only reported.

Reading /dev/input needs the `input` group. A stroke is the motion made with the left button held: the mouse
is grabbed for the test, so neither the cursor nor the clicks reach Hyprland, and the motion back between
strokes, made with the button up, is not measured."""
import fcntl
import math
import os
import select
import statistics
import struct
import subprocess
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import devices_lua  # noqa: E402
import mice  # noqa: E402

EVENT = struct.Struct("llHHi")  # struct input_event: time (seconds, microseconds), type, code, value
EV_SYN = 0x00
EV_KEY = 0x01
EV_REL = 0x02
REL_X = 0x00
REL_Y = 0x01
BTN_LEFT = 0x110
BUTTON_UP = 0  # the values of a BTN_LEFT event
BUTTON_DOWN = 1
BUTTON_UNCHANGED = -1  # a report without a BTN_LEFT event
EVIOCGRAB = 0x40044590  # _IOW('E', 0x90, int)

ANGLE_STROKES = 5
# A stroke further from horizontal than this goes more up-down than sideways: the mouse was led away from the
# user, not across, and its angle is the wrong axis, not the sensor's.
MAX_STROKE_DEGREES = 45
DISTANCE_STROKES = 3
DEFAULT_DISTANCE_MM = 100
MIN_CORRECTION_DEGREES = 1


@dataclass(frozen=True)
class Report:
    time: float  # seconds
    dx: int
    dy: int
    button: int  # BUTTON_DOWN, BUTTON_UP or BUTTON_UNCHANGED


@dataclass
class Stroke:
    points: list = field(default_factory=list)  # (x, y) summed counts after each report, y down as on screen
    times: list = field(default_factory=list)  # seconds of each report


class Reader:
    """The motion of one event node made while its left button is held, report by report."""

    def __init__(self, node):
        self.fd = os.open(node, os.O_RDONLY | os.O_NONBLOCK)
        self.pending = b""  # the bytes of an event cut by the end of a read
        self.report = [0, 0]  # dx, dy of a report whose SYN_REPORT has not been read yet
        self.button = BUTTON_UNCHANGED  # the same report's BTN_LEFT
        self.unused = []  # reports read past the end of the last stroke

    def grab(self):
        """Keeps the mouse's motion and clicks from Hyprland. The kernel drops the grab when the process ends,
        a crash included."""
        try:
            fcntl.ioctl(self.fd, EVIOCGRAB, 1)
        except OSError as error:
            raise SystemExit(f"мышь занята другой программой ({error.strerror})") from None

    def reports(self, timeout):
        """The reports read within the timeout; [] when the mouse stayed still."""
        if not select.select([self.fd], [], [], timeout)[0]:
            return []
        self.pending += os.read(self.fd, EVENT.size * 256)
        whole = len(self.pending) - len(self.pending) % EVENT.size
        events, self.pending = self.pending[:whole], self.pending[whole:]
        found = []
        for seconds, microseconds, kind, code, value in EVENT.iter_unpack(events):
            if kind == EV_REL and code in (REL_X, REL_Y):
                self.report[code] += value  # REL_X and REL_Y are 0 and 1, the report's indices
            elif kind == EV_KEY and code == BTN_LEFT:
                self.button = value
            elif kind == EV_SYN:
                found.append(Report(seconds + microseconds / 1e6, *self.report, self.button))
                self.report, self.button = [0, 0], BUTTON_UNCHANGED
        return found

    def drain(self):
        """Forgets the reports read so far: the next stroke starts with a press made from now on."""
        while self.reports(timeout=0):
            pass
        self.unused = []

    def stroke(self, show):
        """The motion from the next press of the left button to its release; show(stroke) is called as it
        grows. A click, or a motion back to where it began, measures nothing and is skipped."""
        while True:
            stroke = self.held_motion(show)
            if stroke.points and any(stroke.points[-1]):
                return stroke

    def held_motion(self, show):
        stroke = Stroke()
        x, y = 0, 0
        held = False
        while True:
            reports = self.unused or self.reports(timeout=None)
            self.unused = []
            for index, report in enumerate(reports):
                if report.button == BUTTON_DOWN:
                    held = True
                if held and (report.dx or report.dy):
                    x, y = x + report.dx, y + report.dy
                    stroke.points.append((x, y))
                    stroke.times.append(report.time)
                if held and report.button == BUTTON_UP:
                    self.unused = reports[index + 1:]
                    return stroke
            if stroke.points:
                show(stroke)


class LiveLine:
    """One terminal line rewritten as a stroke grows. A mouse sends up to 1000 reports a second, so the line is
    redrawn at most every REFRESH_SECONDS."""
    REFRESH_SECONDS = 0.1

    def __init__(self, prefix, describe):
        self.prefix = prefix
        self.describe = describe  # stroke -> text shown while it grows
        self.shown_at = 0.0

    def show(self, stroke):
        now = time.monotonic()
        if now - self.shown_at >= self.REFRESH_SECONDS:
            self.shown_at = now
            print(f"\r\033[K{self.prefix}{self.describe(stroke)}", end="", flush=True)

    def finish(self, text):
        print(f"\r\033[K{self.prefix}{text}")


def line_angle(points):
    """The angle of the line through the points in degrees, (-90, 90], clockwise on screen: the principal axis
    of their spread, so the start and end wobble of a hand stroke weigh no more than its middle."""
    mean_x = statistics.fmean(x for x, _ in points)
    mean_y = statistics.fmean(y for _, y in points)
    spread_xx = sum((x - mean_x) ** 2 for x, _ in points)
    spread_yy = sum((y - mean_y) ** 2 for _, y in points)
    spread_xy = sum((x - mean_x) * (y - mean_y) for x, y in points)
    angle = math.degrees(math.atan2(2 * spread_xy, spread_xx - spread_yy)) / 2
    return angle if angle > -90 else angle + 180


def wobble_percent(points):
    """How far the stroke strays from its line: the RMS distance to it, in percent of the stroke's length."""
    angle = math.radians(line_angle(points))
    mean_x = statistics.fmean(x for x, _ in points)
    mean_y = statistics.fmean(y for _, y in points)
    across = [(y - mean_y) * math.cos(angle) - (x - mean_x) * math.sin(angle) for x, y in points]
    length = math.hypot(*points[-1])
    return 100 * math.sqrt(statistics.fmean(distance ** 2 for distance in across)) / length


def stroke_length(stroke):
    """Counts from the stroke's start to its end."""
    return math.hypot(*stroke.points[-1])


def length_progress(stroke):
    return f"{stroke_length(stroke):.0f} отсчётов"


def angle_progress(stroke):
    return f"{length_progress(stroke)}, {line_angle(stroke.points):+.1f}°"


def rotation_for(sensor_angle):
    """The clockwise rotation that turns a line the sensor reports at this angle back to horizontal."""
    return round(-sensor_angle) % 360


def counts_per_inch(stroke, millimetres):
    return stroke_length(stroke) / (millimetres / 25.4)


def polling_rate(strokes):
    """Reports per second while the mouse moves: the median gap between reports, pauses being outside strokes."""
    gaps = [later - earlier for stroke in strokes for earlier, later in zip(stroke.times, stroke.times[1:])]
    return 1 / statistics.median(gaps)


def pick_mouse(found):
    """The mouse the user moves first among the USB and Bluetooth ones."""
    readers = {}
    for pointer in found:
        try:
            readers[pointer] = Reader(pointer.node)
        except PermissionError:
            continue
    if not readers:
        raise SystemExit("нет доступа к /dev/input: нужна группа input — sudo gpasswd -a $USER input, затем "
                         "перелогиниться.\nУчти: в этой группе любая твоя программа сможет читать нажатия клавиш.")
    print("Пошевели мышью, которую проверяем.")
    while True:
        for pointer, reader in readers.items():
            if reader.reports(timeout=0.05):
                return pointer, reader


def measure_angle(reader):
    print(f"\nУгол датчика. Положи линейку (или книгу) поперёк стола, слева направо, и прижми к ней мышь боком. "
          f"Зажми левую кнопку, веди мышь вбок вдоль линейки 15–20 см и отпусти; назад веди с отпущенной "
          f"кнопкой. Проходов: {ANGLE_STROKES}.")
    reader.drain()
    strokes, angles = [], []
    while len(strokes) < ANGLE_STROKES:
        live = LiveLine(f"  проход {len(strokes) + 1}: ", angle_progress)
        stroke = reader.stroke(live.show)
        angle = line_angle(stroke.points)
        if abs(angle) > MAX_STROKE_DEGREES:
            live.finish(f"{angle:+.1f}° — мышь шла от себя, а не вбок; не засчитан, веди слева направо")
            continue
        strokes.append(stroke)
        angles.append(angle)
        live.finish(f"{angle:+.1f}°, отклонение от прямой {wobble_percent(stroke.points):.1f}%")
    return strokes, statistics.fmean(angles), statistics.stdev(angles)


def measure_resolution(reader):
    millimetres = ask_distance()
    print(f"Поставь мышь на начало отметки, зажми левую кнопку, веди ровно до конца и отпусти. "
          f"Проходов: {DISTANCE_STROKES}.")
    reader.drain()
    strokes, values = [], []
    for number in range(1, DISTANCE_STROKES + 1):
        live = LiveLine(f"  проход {number}: ", length_progress)
        stroke = reader.stroke(live.show)
        strokes.append(stroke)
        values.append(counts_per_inch(stroke, millimetres))
        live.finish(f"{values[-1]:.0f} CPI")
    return strokes, statistics.fmean(values)


def ask_distance():
    while True:
        answer = input(f"\nРазрешение. Сколько миллиметров отмеришь на линейке? (Enter — {DEFAULT_DISTANCE_MM}) ")
        if not answer.strip():
            return DEFAULT_DISTANCE_MM
        try:
            millimetres = float(answer.replace(",", "."))
        except ValueError:
            millimetres = 0
        if millimetres > 0:
            return millimetres
        print("  нужно число миллиметров больше нуля")


def offer_rotation(name, sensor_angle, spread):
    settings = devices_lua.read(devices_lua.PATH).get(name, {})
    current = settings.get("rotation", 0)
    significant = abs(sensor_angle) >= MIN_CORRECTION_DEGREES and abs(sensor_angle) > spread
    proposed = rotation_for(sensor_angle) if significant else 0
    print(f"\nДатчик повёрнут на {sensor_angle:+.1f}° (разброс проходов ±{spread:.1f}°); "
          f"сейчас rotation = {current}.")
    if proposed == current:
        print("Менять нечего.")
        return
    if input(f"Поставить rotation = {proposed} для {name}? [y/N] ").strip().lower() not in ("y", "д"):
        return
    devices_lua.save(name, {"rotation": proposed}, devices_lua.PATH)
    applied = subprocess.run(["hyprctl", "eval", devices_lua.device_line(name, settings | {"rotation": proposed})],
                             capture_output=True, text=True).returncode == 0
    print(f"Записано в {devices_lua.PATH}" + ("" if applied else "; применится при следующем входе в Hyprland"))


def main():
    found = mice.external_mice()
    if not found:
        raise SystemExit("мышь по USB или Bluetooth не найдена")
    pointer, reader = pick_mouse(found)
    reader.grab()
    print(f"Проверяем {pointer.name}. До конца проверки она не двигает курсор и не кликает; выход — Ctrl+C.")
    angle_strokes, sensor_angle, spread = measure_angle(reader)
    distance_strokes, resolution = measure_resolution(reader)
    print(f"\nРазрешение: {resolution:.0f} CPI (его задаёт прошивка мыши, система не меняет).")
    print(f"Частота опроса: {polling_rate(angle_strokes + distance_strokes):.0f} Гц.")
    offer_rotation(pointer.name, sensor_angle, spread)


if __name__ == "__main__":
    try:
        main()
    except (KeyboardInterrupt, EOFError):
        print()
