"""Services that slowed this boot down, from systemd-analyze blame."""
import re

from ..model import Finding, Severity

TITLE = "Загрузка"
DURATION_PART = re.compile(r"([\d.]+)(min|ms|s|us|µs|h)")
SECONDS_IN = {"h": 3600, "min": 60, "s": 1, "ms": 0.001, "us": 0.000001, "µs": 0.000001}


def detect(ctx):
    blame = ctx.run(["systemd-analyze", "blame", "--no-pager"])
    slow = []
    for line in blame.lines:
        duration, _, unit = line.strip().rpartition(" ")
        if unit.endswith(".service") and seconds(duration) >= ctx.config.boot_service_seconds:
            slow.append(f"{duration.strip()}  {unit}")
    if not slow:
        return []
    return [Finding(key="boot:slow:" + ",".join(entry.split()[-1] for entry in slow), severity=Severity.INFO,
                    text=f"службы, грузившиеся дольше {ctx.config.boot_service_seconds:g} с: {len(slow)}",
                    evidence=tuple(slow),
                    hint="ненужную можно выключить: sudo systemctl disable <служба>; "
                         "что кого ждёт: systemd-analyze critical-chain")]


def seconds(duration):
    """systemd's "1min 2.345s" or "345ms" in seconds."""
    return sum(float(number) * SECONDS_IN[unit] for number, unit in DURATION_PART.findall(duration))
