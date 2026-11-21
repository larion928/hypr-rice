"""rice mouse-test: the mouse's sensor angle, resolution (CPI) and polling rate, measured from the counts the
sensor sends, before Hyprland's acceleration and rotation touch them. The user moves the mouse along a ruler:
a straight hand line the sensor reports askew is the sensor's angle, which devices.lua's `rotation` undoes
(libinput turns the motion clockwise by that many whole degrees). The resolution needs a known distance;
the mouse's firmware sets it, so it is only reported.

Reading /dev/input needs the `input` group. Strokes are split by pauses, not by a button: a held button
would click whatever window the cursor reaches between strokes."""
import math
import os
import select
import statistics
import struct
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import devices_lua  # noqa: E402
import mice  # noqa: E402

EVENT = struct.Struct("llHHi")  # struct input_event: time (seconds, microseconds), type, code, value
EV_SYN = 0x00
EV_REL = 0x02
REL_X = 0x00
REL_Y = 0x01

PAUSE_SECONDS = 0.4  # no motion this long ends a stroke
MIN_STROKE_COUNTS = 1000  # shorter motion is the hand settling or the mouse lifted back, not a stroke
ANGLE_STROKES = 5
DISTANCE_STROKES = 3
DEFAULT_DISTANCE_MM = 100
MIN_CORRECTION_DEGREES = 1


@dataclass
class Stroke:
    points: list = field(default_factory=list)  # (x, y) summed counts after each report, y down as on screen
    times: list = field(default_factory=list)  # seconds of each report


class Reader:
    """The relative motion of one event node, report by report. Pauses are judged by the reports' own times:
    motion made while the user read the instructions arrives at once, yet stays apart from the stroke."""

    def __init__(self, node):
        self.fd = os.open(node, os.O_RDONLY | os.O_NONBLOCK)
        self.pending = b""  # the bytes of an event cut by the end of a read
        self.report = [0, 0]  # dx, dy of a report whose SYN_REPORT has not been read yet
        self.unused = []  # reports read past the end of the last stroke

    def motions(self, timeout):
        """(time, dx, dy) of each report within the timeout; [] when the mouse stayed still."""
        if not select.select([self.fd], [], [], timeout)[0]:
            return []
        self.pending += os.read(self.fd, EVENT.size * 256)
        whole = len(self.pending) - len(self.pending) % EVENT.size
        events, self.pending = self.pending[:whole], self.pending[whole:]
        found = []
        for seconds, microseconds, kind, code, value in EVENT.iter_unpack(events):
            if kind == EV_REL and code in (REL_X, REL_Y):
                self.report[code] += value  # REL_X and REL_Y are 0 and 1, the report's indices
            elif kind == EV_SYN and any(self.report):
                found.append((seconds + microseconds / 1e6, *self.report))
                self.report = [0, 0]
        return found

    def drain(self):
        """Forgets the motion made so far: the next stroke starts with what the mouse does from now on."""
        while self.motions(timeout=0):
            pass
        self.unused = []

    def stroke(self):
        """The next motion between two pauses that is long enough to be a stroke."""
        while True:
            stroke = self.motion_until_pause()
            if math.hypot(*stroke.points[-1]) >= MIN_STROKE_COUNTS:
                return stroke

    def motion_until_pause(self):
        stroke = Stroke()
        x, y = 0, 0
        while True:
            motions = self.unused or self.motions(timeout=PAUSE_SECONDS if stroke.times else None)
            self.unused = []
            if not motions:
                return stroke
            for index, (moment, dx, dy) in enumerate(motions):
                if stroke.times and moment - stroke.times[-1] > PAUSE_SECONDS:
                    self.unused = motions[index:]
                    return stroke
                x, y = x + dx, y + dy
                stroke.points.append((x, y))
                stroke.times.append(moment)


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


def rotation_for(sensor_angle):
    """The clockwise rotation that turns a line the sensor reports at this angle back to horizontal."""
    return round(-sensor_angle) % 360


def counts_per_inch(stroke, millimetres):
    return math.hypot(*stroke.points[-1]) / (millimetres / 25.4)


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
            if reader.motions(timeout=0.05):
                return pointer, reader


def measure_angle(reader):
    print(f"\nУгол датчика. Прижми мышь боком к линейке (или к краю книги), лежащей горизонтально, и веди вдоль "
          f"неё 15–20 см, затем остановись. Возвращай мышь, подняв её. Проходов: {ANGLE_STROKES}.")
    reader.drain()
    strokes, angles = [], []
    for number in range(1, ANGLE_STROKES + 1):
        stroke = reader.stroke()
        strokes.append(stroke)
        angles.append(line_angle(stroke.points))
        print(f"  проход {number}: {angles[-1]:+.1f}°, отклонение от прямой {wobble_percent(stroke.points):.1f}%")
    return strokes, statistics.fmean(angles), statistics.stdev(angles)


def measure_resolution(reader):
    millimetres = ask_distance()
    print(f"Поставь мышь на начало отметки, замри на секунду, веди ровно до конца и остановись. "
          f"Проходов: {DISTANCE_STROKES}.")
    reader.drain()
    strokes, values = [], []
    for number in range(1, DISTANCE_STROKES + 1):
        stroke = reader.stroke()
        strokes.append(stroke)
        values.append(counts_per_inch(stroke, millimetres))
        print(f"  проход {number}: {values[-1]:.0f} CPI")
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
    print(f"Проверяем {pointer.name}.")
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
