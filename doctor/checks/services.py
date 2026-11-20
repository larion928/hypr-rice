"""Units that failed, restart in a loop, are enabled but do not run, or are watched in doctor.conf."""
from ..context import as_root, journal_of_unit, systemctl
from ..model import Cure, CureFailed, CureKind, Finding, Severity

TITLE = "Службы"
SCOPES = ("system", "user")
# The doctor's own unit: reporting it would make every next run report the last one.
OWN_UNITS = {"rice-doctor.service", "rice-doctor.timer"}
STATE_PROPERTIES = ("Id", "LoadState", "Type", "ActiveState", "SubState", "Result", "TriggeredBy", "BusName",
                    "ConditionResult")


def detect(ctx):
    findings = []
    for scope in SCOPES:
        findings += failed_units(ctx, scope)
        findings += restart_loops(ctx, scope)
        findings += enabled_not_running(ctx, scope)
    findings += watched_units(ctx)
    return findings


def scope_label(scope):
    return "пользовательский юнит" if scope == "user" else "юнит"


def units_in_state(ctx, scope, state):
    result = ctx.run(systemctl(scope, "list-units", "--all", f"--state={state}", "--plain", "--no-legend"))
    return [line.split()[0] for line in result.lines if line.split()[0] not in OWN_UNITS]


def unit_journal(ctx, scope, unit):
    return tuple(ctx.run(journal_of_unit(scope, unit)).lines)


def failed_units(ctx, scope):
    return [Finding(key=f"failed:{scope}:{unit}", severity=Severity.PROBLEM,
                    text=f"{scope_label(scope)} {unit} упал (failed)",
                    evidence=unit_journal(ctx, scope, unit),
                    cure=Cure(f"сбросить и перезапустить {unit}", CureKind.ASK, restart_action(scope, unit),
                              sudo=scope == "system"))
            for unit in units_in_state(ctx, scope, "failed")]


def restart_loops(ctx, scope):
    """A unit systemd keeps restarting: it never reaches failed, so a failed-only check misses it."""
    return [Finding(key=f"loop:{scope}:{unit}", severity=Severity.PROBLEM,
                    text=f"{scope_label(scope)} {unit} падает и перезапускается по кругу",
                    evidence=unit_journal(ctx, scope, unit),
                    hint=f"причина — в строках выше; остановить: systemctl{' --user' if scope == 'user' else ''}"
                         f" disable --now {unit}")
            for unit in units_in_state(ctx, scope, "auto-restart")]


def enabled_not_running(ctx, scope):
    listed = ctx.run(systemctl(scope, "list-unit-files", "--state=enabled", "--type=service", "--plain",
                               "--no-legend"))
    units = [line.split()[0] for line in listed.lines
             if "@." not in line.split()[0] and line.split()[0] not in OWN_UNITS]
    findings = []
    for unit in unit_properties(ctx, scope, units):
        if unit.get("ActiveState") == "failed" or is_running_or_fine(unit):  # failed ones: failed_units
            continue
        name = unit["Id"]
        findings.append(Finding(
            key=f"inactive:{scope}:{name}", severity=Severity.WARNING,
            text=f"{name} в автозапуске, но не работает (состояние {unit['ActiveState']}, итог {unit['Result']})",
            evidence=unit_journal(ctx, scope, name),
            cure=Cure(f"запустить {name}", CureKind.ASK, start_action(scope, name), sudo=scope == "system")))
    return findings


def unit_properties(ctx, scope, units):
    """One dict of STATE_PROPERTIES per unit, from a single systemctl show."""
    if not units:
        return []
    shown = ctx.run(systemctl(scope, "show", "-p", ",".join(STATE_PROPERTIES), *units))
    blocks = []
    for block in shown.out.strip().split("\n\n"):
        pairs = (line.split("=", 1) for line in block.splitlines() if "=" in line)
        blocks.append({name: value for name, value in pairs})
    return [block for block in blocks if "Id" in block]


def is_running_or_fine(unit):
    """Not running is the normal state of an enabled service that ran once and finished, that a socket,
    path, timer or D-Bus starts on demand, or whose start condition does not hold on this machine."""
    if unit.get("ActiveState") in ("active", "reloading", "activating"):
        return True
    finished_well = unit.get("Result") == "success"
    if unit.get("Type") == "oneshot" and finished_well:
        return True
    if unit.get("TriggeredBy") or unit.get("ConditionResult") == "no":
        return True
    return bool(unit.get("BusName")) and finished_well


def watched_units(ctx):
    findings = []
    for entry in ctx.config.watched_services:
        scope, unit = ("user", entry[len("user:"):]) if entry.startswith("user:") else ("system", entry)
        state = unit_properties(ctx, scope, [unit])
        if not state or state[0].get("LoadState") == "not-found":
            findings.append(Finding(
                key=f"watched-missing:{entry}", severity=Severity.WARNING,
                text=f"в doctor.conf отслеживается {unit}, но такого юнита на машине нет",
                hint="убери его из [services] watch в ~/.config/hypr-rice/doctor.conf"))
        elif state[0].get("ActiveState") != "active":
            findings.append(Finding(
                key=f"watched:{entry}", severity=Severity.PROBLEM,
                text=f"{unit} из doctor.conf не работает (состояние {state[0].get('ActiveState')})",
                evidence=unit_journal(ctx, scope, unit),
                cure=Cure(f"запустить {unit}", CureKind.ASK, start_action(scope, unit), sudo=scope == "system")))
    return findings


def with_sudo(scope, argv):
    return as_root(argv) if scope == "system" else argv


def restart_action(scope, unit):
    def restart(ctx):
        ctx.run(with_sudo(scope, systemctl(scope, "reset-failed", unit)))
        result = ctx.run(with_sudo(scope, systemctl(scope, "restart", unit)), timeout=120)
        if not result.ok:
            raise CureFailed(result.err.strip() or f"systemctl restart вернул {result.code}")
    return restart


def start_action(scope, unit):
    def start(ctx):
        result = ctx.run(with_sudo(scope, systemctl(scope, "start", unit)), timeout=120)
        if not result.ok:
            raise CureFailed(result.err.strip() or f"systemctl start вернул {result.code}")
    return start
