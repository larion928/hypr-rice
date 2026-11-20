"""Battery wear and CPU temperature, read from /sys. Nothing to cure here, only to know."""
from ..model import Finding, Severity

TITLE = "Батарея и температура"
CPU_SENSORS = ("k10temp", "coretemp", "zenpower", "cpu_thermal")


def detect(ctx):
    return [*batteries(ctx), *cpu_temperature(ctx)]


def read_number(path):
    try:
        return int(path.read_text().strip())
    except (OSError, ValueError):
        return 0


def batteries(ctx):
    findings = []
    for supply in sorted(ctx.path("/sys/class/power_supply").glob("*")):
        if not (supply / "type").exists() or (supply / "type").read_text().strip() != "Battery":
            continue
        # Drivers report energy (µWh) or charge (µAh); either ratio is the wear.
        full = read_number(supply / "energy_full") or read_number(supply / "charge_full")
        design = read_number(supply / "energy_full_design") or read_number(supply / "charge_full_design")
        if not full or not design:
            continue
        health = round(100 * full / design)
        cycles = read_number(supply / "cycle_count")
        text = f"батарея {supply.name}: {health}% от заводской ёмкости" + (f", циклов: {cycles}" if cycles else "")
        if health >= ctx.config.battery_health:
            findings.append(Finding(key=f"laptop:battery:{supply.name}", severity=Severity.INFO, text=text))
        else:
            findings.append(Finding(key=f"laptop:battery-worn:{supply.name}", severity=Severity.WARNING,
                                    text=text + " — изношена", hint="держится заметно меньше нового; замена батареи"))
    return findings


def cpu_temperature(ctx):
    for hwmon in sorted(ctx.path("/sys/class/hwmon").glob("hwmon*")):
        name = hwmon / "name"
        if not name.exists() or name.read_text().strip() not in CPU_SENSORS:
            continue
        celsius = read_number(hwmon / "temp1_input") / 1000
        if celsius <= ctx.config.cpu_temperature:
            return [Finding(key="laptop:cpu", severity=Severity.INFO, text=f"процессор: {celsius:.0f} °C")]
        return [Finding(key="laptop:cpu-hot", severity=Severity.WARNING,
                        text=f"процессор горячий: {celsius:.0f} °C (порог {ctx.config.cpu_temperature})",
                        hint="посмотри, кто грузит процессор (htop), и не забита ли пылью система охлаждения")]
    return []
