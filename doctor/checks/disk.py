"""How full each real file system is. A full one gets the list of what can be freed on it, each with its
size and its own cure; --full adds the drives' SMART health."""
import json
import os
import re
import shutil
from dataclasses import dataclass
from pathlib import Path

from ..context import as_root
from ..model import Cure, CureFailed, CureKind, Finding, Severity

TITLE = "Диск"
SKIPPED_TYPES = ("tmpfs", "devtmpfs", "efivarfs", "squashfs", "overlay", "ramfs")
SMALLEST_WORTH_LISTING = 20 * 1024 ** 2
BIGGEST_CACHE_DIRS = 5
PACCACHE_SAVED = re.compile(r"disk space saved: ([\d.]+ ?\S+)\)")
JOURNAL_SIZE = re.compile(r"take up ([\d.]+[KMGT]?B?)")


@dataclass(frozen=True)
class Mount:
    target: str
    size: int
    available: int
    percent: int


def detect(ctx):
    findings = []
    for mount in mounts(ctx):
        findings += mount_findings(ctx, mount)
    if ctx.full:
        findings += smart_health(ctx)
    return findings


def mounts(ctx):
    result = ctx.run(["df", "-B1", "--output=fstype,size,avail,pcent,target"])
    found = []
    for line in result.lines[1:]:
        fstype, size, available, percent, target = line.split(maxsplit=4)
        if fstype in SKIPPED_TYPES or fstype.startswith("fuse."):
            continue
        found.append(Mount(target, int(size), int(available), int(percent.rstrip("%"))))
    return found


def human(size):
    for unit in ("Б", "КиБ", "МиБ", "ГиБ"):
        if size < 1024:
            return f"{size:.0f} {unit}" if unit == "Б" else f"{size:.1f} {unit}"
        size /= 1024
    return f"{size:.1f} ТиБ"


def mount_findings(ctx, mount):
    text = f"{mount.target}: занято {mount.percent}%, свободно {human(mount.available)}"
    if mount.percent < ctx.config.disk_warning:
        return [Finding(key=f"disk:ok:{mount.target}", severity=Severity.INFO, text=text)]
    severity = Severity.PROBLEM if mount.percent >= ctx.config.disk_problem else Severity.WARNING
    freeable = [item for item in freeable_items(ctx) if on_mount(ctx, item.path, mount.target)]
    hint = "что можно освободить — ниже" if freeable else "ничего из известного райсу освободить здесь нельзя: " \
                                                          "посмотри, что занимает место (filelight, ncdu)"
    return [Finding(key=f"disk:full:{mount.target}", severity=severity, text=text, hint=hint),
            *(item.finding() for item in freeable)]


def on_mount(ctx, path, target):
    """path lies on the file system mounted at target (not on one mounted deeper)."""
    try:
        return os.stat(path).st_dev == os.stat(ctx.path(target)).st_dev
    except OSError:
        return False


@dataclass(frozen=True)
class Freeable:
    name: str
    path: Path
    size: str  # as shown: some sizes come from the tools that free them, already formatted
    cure: Cure

    def finding(self):
        return Finding(key=f"disk:free:{self.path}:{self.size}", severity=Severity.INFO,
                       text=f"можно освободить: {self.name} — {self.size}", cure=self.cure)


def freeable_items(ctx):
    return ctx.memo("freeable", lambda: [*package_cache(ctx), *aur_clones(ctx), *journal(ctx), *coredumps(ctx),
                                         *trash(ctx), *flatpak_unused(ctx), *biggest_cache_dirs(ctx)])


def folder_size(path):
    total = 0
    for folder, _, files in os.walk(path, onerror=lambda error: None):
        for name in files:
            try:
                total += os.lstat(os.path.join(folder, name)).st_size
            except OSError:
                pass
    return total


def emptying_action(path):
    """Removes what is inside path, keeping path itself."""
    def empty(ctx):
        for child in list(Path(path).iterdir()):
            if child.is_dir() and not child.is_symlink():
                shutil.rmtree(child, ignore_errors=True)
            else:
                child.unlink(missing_ok=True)
        if any(Path(path).iterdir()):
            raise CureFailed(f"в {path} остались файлы, которые не удалось удалить")
    return empty


def root_command_action(argv, failure):
    def run(ctx):
        result = ctx.run(as_root(argv), timeout=300)
        if not result.ok:
            raise CureFailed(result.err.strip() or failure)
    return run


def sized_folder(path, name, cure):
    size = folder_size(path) if path.is_dir() else 0
    if size < SMALLEST_WORTH_LISTING:
        return []
    return [Freeable(name, path, human(size), cure)]


def package_cache(ctx):
    """paccache's dry runs: all but the last 3 versions, and every version of uninstalled packages."""
    if not ctx.has("paccache"):
        return []
    saved = [PACCACHE_SAVED.search(ctx.run(["paccache", "-d", *args]).out) for args in ([], ["-u", "-k0"])]
    sizes = [match.group(1) for match in saved if match]
    if not sizes:
        return []
    cure = Cure("почистить кэш pacman (paccache -r и -ruk0)", CureKind.ASK, clean_package_cache, sudo=True)
    return [Freeable("старые версии пакетов в кэше pacman", ctx.path("/var/cache/pacman/pkg"), " + ".join(sizes),
                     cure)]


def clean_package_cache(ctx):
    for args in (["-r"], ["-ruk0"]):
        result = ctx.run(as_root(["paccache", *args]), timeout=300)
        if not result.ok:
            raise CureFailed(result.err.strip() or "paccache не сработал")


def aur_clones(ctx):
    items = []
    for relative in (".cache/yay", ".cache/paru/clone"):
        path = ctx.home / relative
        items += sized_folder(path, f"сборки AUR в ~/{relative}",
                              Cure(f"очистить ~/{relative}", CureKind.ASK, emptying_action(path)))
    return items


def journal(ctx):
    match = JOURNAL_SIZE.search(ctx.run(["journalctl", "--disk-usage"]).out)
    if not match:
        return []
    keep = ctx.config.journal_keep
    cure = Cure(f"ужать журнал до {keep}", CureKind.ASK,
                root_command_action(["journalctl", f"--vacuum-size={keep}"], "journalctl --vacuum-size не сработал"),
                sudo=True)
    return [Freeable("системный журнал", ctx.path("/var/log/journal"), match.group(1), cure)]


def coredumps(ctx):
    path = ctx.path("/var/lib/systemd/coredump")
    cure = Cure("удалить дампы падений", CureKind.ASK,
                root_command_action(["find", str(path), "-type", "f", "-delete"], "дампы не удалились"), sudo=True)
    return sized_folder(path, "дампы падений программ", cure)


def trash(ctx):
    files = ctx.home / ".local/share/Trash/files"
    return sized_folder(files, "корзина", Cure("очистить корзину", CureKind.ASK, empty_trash))


def empty_trash(ctx):
    for part in ("files", "info"):
        if (ctx.home / ".local/share/Trash" / part).is_dir():
            emptying_action(ctx.home / ".local/share/Trash" / part)(ctx)


def flatpak_unused(ctx):
    """Runtimes no installed app needs any more. flatpak lists them before asking to remove them; "n" keeps them."""
    if not ctx.has("flatpak"):
        return []
    listed = ctx.runner.run(["flatpak", "uninstall", "--unused", "--user"], stdin_text="n\n")
    names = re.findall(r"^\s*\d+\.\s+(\S+)", listed.out, re.MULTILINE)
    if not names:
        return []
    cure = Cure("удалить неиспользуемые среды flatpak", CureKind.ASK, remove_flatpak_unused)
    return [Freeable(f"неиспользуемые среды flatpak ({', '.join(names)})", ctx.home / ".local/share/flatpak",
                     f"{len(names)} шт.", cure)]


def remove_flatpak_unused(ctx):
    result = ctx.run(["flatpak", "uninstall", "--unused", "--user", "-y", "--noninteractive"], timeout=300)
    if not result.ok:
        raise CureFailed(result.err.strip() or "flatpak не удалил среды")


def biggest_cache_dirs(ctx):
    cache = ctx.home / ".cache"
    if not cache.is_dir():
        return []
    # The AUR clones are listed on their own above.
    sizes = [(folder_size(child), child) for child in cache.iterdir()
             if child.is_dir() and not child.is_symlink() and child.name not in ("yay", "paru")]
    biggest = sorted(sizes, reverse=True)[:BIGGEST_CACHE_DIRS]
    return [Freeable(f"кэш ~/.cache/{path.name}", path, human(size),
                     Cure(f"очистить ~/.cache/{path.name}", CureKind.ASK, emptying_action(path)))
            for size, path in biggest if size >= SMALLEST_WORTH_LISTING]


def smart_health(ctx):
    if not ctx.has("smartctl"):
        return [Finding(key="disk:no-smartctl", severity=Severity.INFO, text="здоровье дисков (SMART) не проверено",
                        hint="поставь smartmontools: sudo pacman -S smartmontools")]
    disks = [line.split()[0] for line in ctx.run(["lsblk", "-dno", "NAME,TYPE"]).lines if line.split()[-1] == "disk"]
    return [disk_health(ctx, f"/dev/{name}") for name in disks]


def disk_health(ctx, device):
    result = ctx.run(["smartctl", "-H", "-j", device])
    try:
        report = json.loads(result.out)
    except ValueError:
        report = {}
    passed = report.get("smart_status", {}).get("passed")
    if passed is None:
        return Finding(key=f"disk:smart-unknown:{device}", severity=Severity.INFO,
                       text=f"{device}: SMART не прочитан без прав root", hint=f"sudo smartctl -H {device}")
    if passed:
        return Finding(key=f"disk:smart-ok:{device}", severity=Severity.INFO, text=f"{device}: SMART в порядке")
    return Finding(key=f"disk:smart-failed:{device}", severity=Severity.PROBLEM,
                   text=f"{device}: SMART сообщает о неисправности диска — скопируй важные данные",
                   evidence=(f"sudo smartctl -a {device}",))
