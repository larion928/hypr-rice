"""Programs that crashed (left a core dump) in the last 24 hours, by program and signal. A crash already
reported by an earlier run is listed as info; what is new is a warning, with whether an update of the
package that owns the program is waiting."""
import signal
from collections import defaultdict
from datetime import datetime

from ..model import Finding, Severity
from .rice import COMPONENTS

TITLE = "Падения программ (24 ч)"
DAY_MICROSECONDS = 24 * 3600 * 1_000_000
RICE_PROGRAMS = {part.executable for part in COMPONENTS}


def detect(ctx):
    since = ctx.now.timestamp() * 1_000_000 - DAY_MICROSECONDS
    recent = [dump for dump in ctx.coredumps() if dump.get("time", 0) >= since]
    groups = defaultdict(list)
    for dump in recent:
        groups[(dump.get("exe") or "?", dump.get("sig", 0))].append(dump)
    seen = set(ctx.previous.crashes)
    findings = [crash_finding(ctx, exe, number, dumps, seen) for (exe, number), dumps in groups.items()]
    ctx.observed.crashes = sorted({crash_id(dump) for dump in recent} | seen)[-500:]
    return findings


def crash_id(dump):
    return f"{dump.get('time')}:{dump.get('pid')}"


def crash_finding(ctx, exe, number, dumps, seen):
    name = exe.rsplit("/", 1)[-1]
    times = ", ".join(datetime.fromtimestamp(dump["time"] / 1_000_000).strftime("%d.%m %H:%M") for dump in dumps)
    text = f"{name} упал {len(dumps)} раз(а) — {signal_name(number)}"
    if name in RICE_PROGRAMS:
        text += " (часть райса; работает ли он сейчас — в разделе «Райс»)"
    evidence = (f"когда: {times}", f"подробности: coredumpctl info {exe}")
    if all(crash_id(dump) in seen for dump in dumps):
        return Finding(key=f"crash:{exe}:{number}", severity=Severity.INFO, text=text + ", уже сообщалось",
                       evidence=evidence)
    newest = crash_id(dumps[-1])
    return Finding(key=f"crash:{exe}:{number}:{newest}", severity=Severity.WARNING, text=text,
                   evidence=evidence, hint=update_hint(ctx, exe))


def signal_name(number):
    try:
        return signal.Signals(number).name
    except ValueError:
        return f"сигнал {number}"


def update_hint(ctx, exe):
    owner = ctx.run(["pacman", "-Qqo", exe])
    if not owner.ok or not owner.lines:
        return "программа не из пакета pacman: обнови её тем же способом, каким ставил"
    package = owner.lines[0]
    updates = ctx.updates()
    if updates is None:
        return f"пакет {package}; есть ли обновление — проверить не удалось (нет сети?)"
    if package in updates:
        return f"для пакета {package} есть обновление до {updates[package]}: rice upgrade"
    return f"пакет {package} последней версии: если падения повторяются — это ошибка программы, " \
           f"сообщи её авторам (coredumpctl info {exe})"
