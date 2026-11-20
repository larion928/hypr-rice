"""Clock, network, sound and swap: what the whole session quietly depends on."""
from ..context import as_root
from ..model import Cure, CureFailed, CureKind, Finding, Severity

TITLE = "Система"
PROBE_HOST = "archlinux.org"
AUDIO_UNITS = ("pipewire.service", "wireplumber.service")


def detect(ctx):
    return [*clock(ctx), *network(ctx), *audio(ctx), *swap(ctx)]


def clock(ctx):
    shown = dict(line.split("=", 1) for line in ctx.run(["timedatectl", "show"]).lines if "=" in line)
    if not shown:
        return [Finding(key="system:clock-unknown", severity=Severity.INFO, text="состояние часов не прочитано")]
    if shown.get("NTP") != "yes":
        return [Finding(key="system:ntp-off", severity=Severity.WARNING,
                        text="синхронизация времени по сети выключена: часы уйдут, а с ними TLS и подписи пакетов",
                        cure=Cure("включить синхронизацию (timedatectl set-ntp true)", CureKind.ASK, enable_ntp,
                                  sudo=True))]
    if shown.get("NTPSynchronized") != "yes":
        return [Finding(key="system:ntp-unsynced", severity=Severity.WARNING,
                        text="синхронизация времени включена, но часы ещё не сверены",
                        hint="так бывает первые минуты после загрузки или без сети; проверить: timedatectl")]
    return []


def enable_ntp(ctx):
    result = ctx.run(as_root(["timedatectl", "set-ntp", "true"]))
    if not result.ok:
        raise CureFailed(result.err.strip() or "timedatectl set-ntp не сработал")


def network(ctx):
    resolved = ctx.run(["getent", "ahosts", PROBE_HOST], timeout=15)
    if not resolved.ok:
        return [Finding(key="system:dns", severity=Severity.PROBLEM,
                        text=f"имя {PROBE_HOST} не разрешается: нет сети или не работает DNS",
                        evidence=tuple(ctx.run(["resolvectl", "status"]).lines[:6]),
                        hint="проверь подключение (nmcli device status); "
                             "если сеть есть — DNS в настройках подключения")]
    answered = ctx.run(["curl", "-sSI", "-o", "/dev/null", "--max-time", "10", f"https://{PROBE_HOST}"], timeout=20)
    if not answered.ok:
        return [Finding(key="system:https", severity=Severity.PROBLEM,
                        text=f"DNS работает, но https://{PROBE_HOST} не отвечает",
                        evidence=(answered.err.strip(),),
                        hint="сайт может быть недоступен из твоей сети (блокировка, прокси) — проверь другой сайт")]
    return []


def audio(ctx):
    findings = []
    for unit in AUDIO_UNITS:
        if ctx.run(["systemctl", "--user", "is-active", unit]).ok:
            continue
        findings.append(Finding(key=f"system:audio:{unit}", severity=Severity.PROBLEM,
                                text=f"{unit} не работает: звука не будет",
                                cure=Cure(f"перезапустить {unit}", CureKind.ASK, restart_user_unit(unit))))
    return findings


def restart_user_unit(unit):
    def restart(ctx):
        result = ctx.run(["systemctl", "--user", "restart", unit])
        if not result.ok:
            raise CureFailed(result.err.strip() or f"systemctl --user restart {unit} не сработал")
    return restart


def swap(ctx):
    try:
        areas = ctx.path("/proc/swaps").read_text().splitlines()[1:]
    except OSError:
        return []
    if any(line.strip() for line in areas):
        return []
    return [Finding(key="system:no-swap", severity=Severity.WARNING,
                    text="нет ни swap, ни zram: при нехватке памяти система зависнет, а не закроет программу",
                    hint="поставь zram через rice apps (раздел «Система»)")]
