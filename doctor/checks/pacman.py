"""Packages: how long since the last full upgrade, the keyring, a stale lock, orphans, config files waiting
for a merge, AUR updates, and with --full the files of installed packages that were damaged."""
import difflib
import os
import re
from datetime import datetime
from pathlib import Path

from ..context import RICE, as_root
from ..model import Cure, CureFailed, CureKind, Finding, Severity

TITLE = "Пакеты (pacman)"
UPGRADE_LINE = re.compile(r"^\[([^\]]+)\] \[PACMAN\] starting full system upgrade")
PACKAGE_MANAGERS = ("pacman", "yay", "paru")
DIFF_LINES = 8
# pacman -Qkk as a user: a changed mtime, owner or symlink is how the rice (Papirus folder colours) and
# archlinux-java legitimately leave files, and a file it may not read is not damage.
DAMAGE = re.compile(r"^warning: (\S+): (/\S.*) \((SHA256 checksum mismatch|Size mismatch|No such file or directory)\)$")


def detect(ctx):
    findings = [*upgrade_age(ctx), *pending_updates(ctx), *stale_lock(ctx), *orphans(ctx), *unmerged_configs(ctx),
                *aur_updates(ctx)]
    if ctx.full:
        findings += damaged_files(ctx)
    return findings


def run_interactive(argv, failure):
    def action(ctx):
        if ctx.runner.interactive(argv) != 0:
            raise CureFailed(failure)
    return action


def last_full_upgrade(ctx):
    log = ctx.path("/var/log/pacman.log")
    try:
        lines = log.read_text(errors="replace").splitlines()
    except OSError:
        return None
    for line in reversed(lines):
        match = UPGRADE_LINE.match(line)
        if match:
            return datetime.strptime(match.group(1), "%Y-%m-%dT%H:%M:%S%z")
    return None


def upgrade_age(ctx):
    upgraded = last_full_upgrade(ctx)
    cure = Cure("обновить систему (rice upgrade)", CureKind.ASK, run_interactive([str(RICE), "upgrade"],
                                                                                  "rice upgrade не прошёл"))
    if upgraded is None:
        return [Finding(key="pacman:never-upgraded", severity=Severity.WARNING,
                        text="в /var/log/pacman.log нет ни одного полного обновления", cure=cure)]
    days = (ctx.now - upgraded).days
    if days <= ctx.config.upgrade_days:
        return [Finding(key="pacman:upgraded", severity=Severity.INFO,
                        text=f"последнее полное обновление: {upgraded:%d.%m.%Y} ({days} дн. назад)")]
    return [Finding(key="pacman:old-upgrade", severity=Severity.WARNING,
                    text=f"система не обновлялась {days} дн. (с {upgraded:%d.%m.%Y})", cure=cure)]


def pending_updates(ctx):
    updates = ctx.updates()
    if updates is None:
        return [Finding(key="pacman:updates-unknown", severity=Severity.INFO,
                        text="не удалось проверить обновления (checkupdates: нет сети или pacman-contrib)")]
    findings = [Finding(key="pacman:updates", severity=Severity.INFO, text=f"доступно обновлений: {len(updates)}")]
    if "archlinux-keyring" in updates:
        findings.append(Finding(
            key="pacman:keyring", severity=Severity.WARNING,
            text=f"ключи Arch (archlinux-keyring) устарели, в репозитории {updates['archlinux-keyring']}: "
                 "с ними обновление может споткнуться о подписи",
            cure=Cure("обновить ключи первыми (sudo pacman -Sy archlinux-keyring), затем rice upgrade", CureKind.ASK,
                      run_interactive(["sudo", "pacman", "-Sy", "--needed", "archlinux-keyring"],
                                      "pacman не обновил archlinux-keyring"))))
    return findings


def stale_lock(ctx):
    lock = ctx.path("/var/lib/pacman/db.lck")
    if not lock.exists():
        return []
    if any(ctx.run(["pgrep", "-x", name]).ok for name in PACKAGE_MANAGERS):
        return [Finding(key="pacman:busy", severity=Severity.INFO, text="pacman сейчас работает (db.lck занят)")]
    return [Finding(key="pacman:stale-lock", severity=Severity.PROBLEM,
                    text="остался замок /var/lib/pacman/db.lck, хотя pacman не запущен: установка пакетов не пойдёт",
                    cure=Cure("удалить db.lck", CureKind.ASK, remove_lock_action(lock), sudo=True))]


def remove_lock_action(lock):
    def remove(ctx):
        result = ctx.run(as_root(["rm", "-f", str(lock)]))
        if not result.ok:
            raise CureFailed(result.err.strip() or "rm не удался")
    return remove


def orphans(ctx):
    names = ctx.run(["pacman", "-Qtdq"]).lines
    if not names:
        return []
    sizes = package_sizes(ctx, names)
    evidence = tuple(f"{name}  {sizes.get(name, '?')}" for name in names)
    return [Finding(key="pacman:orphans", severity=Severity.WARNING,
                    text=f"пакеты-сироты (поставлены как зависимости, больше никому не нужны): {len(names)}",
                    evidence=evidence,
                    cure=Cure(f"удалить сирот: sudo pacman -Rns ({len(names)} шт., pacman покажет список)",
                              CureKind.ASK, remove_orphans))]


def remove_orphans(ctx):
    names = ctx.run(["pacman", "-Qtdq"]).lines
    if names and ctx.runner.interactive(["sudo", "pacman", "-Rns", *names]) != 0:
        raise CureFailed("pacman -Rns не завершился успешно")


def package_sizes(ctx, names):
    sizes = {}
    name = ""
    for line in ctx.run(["pacman", "-Qi", *names]).lines:
        field, _, value = line.partition(":")
        if field.strip() == "Name":
            name = value.strip()
        elif field.strip() == "Installed Size":
            sizes[name] = value.strip()
    return sizes


def unmerged_configs(ctx):
    etc = ctx.path("/etc")
    found = []
    for folder, _, files in os.walk(etc, onerror=lambda error: None):
        found += [os.path.join(folder, name) for name in files if name.endswith((".pacnew", ".pacsave"))]
    if not found:
        return []
    shown = {path: "/" + os.path.relpath(path, ctx.root) for path in sorted(found)}
    evidence = [line for path, name in shown.items() for line in (name, *short_diff(path))]
    return [Finding(key="pacman:pacnew:" + ",".join(shown.values()), severity=Severity.WARNING,
                    text=f"файлы настроек ждут слияния (.pacnew/.pacsave): {len(found)}", evidence=tuple(evidence),
                    cure=Cure("слить через pacdiff (спросит про каждый файл)", CureKind.ASK,
                              run_interactive(["sudo", "pacdiff"], "pacdiff завершился с ошибкой")))]


def short_diff(path):
    """The first changed lines between the config in use and the one pacman left beside it."""
    current = re.sub(r"\.(pacnew|pacsave)$", "", path)
    try:
        ours = Path(current).read_text(errors="replace").splitlines()
        theirs = Path(path).read_text(errors="replace").splitlines()
    except OSError as error:
        return [f"  (diff не прочитать: {error.strerror})"]
    changed = [line for line in difflib.unified_diff(ours, theirs, "в работе", "из пакета", lineterm="", n=0)
               if not line.startswith("@@")]
    shown = [f"  {line}" for line in changed[:DIFF_LINES]]
    if len(changed) > DIFF_LINES:
        shown.append(f"  … ещё {len(changed) - DIFF_LINES} строк")
    return shown


def aur_updates(ctx):
    helper = next((name for name in ("yay", "paru") if ctx.has(name)), "")
    if not helper:
        return []
    result = ctx.run([helper, "-Qua"], timeout=90)
    if result.code not in (0, 1):
        return [Finding(key="pacman:aur-unknown", severity=Severity.INFO,
                        text=f"обновления AUR проверить не удалось ({helper} -Qua: код {result.code})")]
    if not result.lines:
        return []
    return [Finding(key="pacman:aur", severity=Severity.INFO, text=f"обновления AUR: {len(result.lines)}",
                    evidence=tuple(result.lines[:10]), hint="поставит rice upgrade")]


def damaged_files(ctx):
    result = ctx.run(["pacman", "-Qkk"], timeout=900)
    damaged = {}
    for line in result.err.splitlines():
        match = DAMAGE.match(line)
        if match:
            damaged.setdefault(match.group(1), []).append(f"{match.group(2)}: {match.group(3)}")
    if not damaged:
        return [Finding(key="pacman:files-ok", severity=Severity.INFO, text="файлы пакетов целы (pacman -Qkk)")]
    packages = sorted(damaged)
    evidence = tuple(f"{package}: {problem}" for package in packages for problem in damaged[package][:3])
    return [Finding(key="pacman:damaged:" + ",".join(packages), severity=Severity.PROBLEM,
                    text=f"повреждены файлы пакетов: {', '.join(packages)}", evidence=evidence,
                    cure=Cure("переустановить эти пакеты", CureKind.ASK,
                              run_interactive(["sudo", "pacman", "-S", *packages], "pacman -S не прошёл")))]
