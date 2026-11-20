"""Errors in this boot's journal, grouped by the program that logged them. Read as JSON, so neither the
locale nor the date format matters. A source seen in earlier runs is news only when it spikes."""
import json
import re
from collections import Counter, defaultdict

from ..model import Cure, CureFailed, CureKind, Finding, Severity

TITLE = "Журнал (текущая загрузка)"
SAMPLES = 2
FIRMWARE = re.compile(r"Direct firmware load for (\S+) failed")
NO_SPACE = re.compile(r"No space left on device", re.IGNORECASE)
UNIT_PREFIX = re.compile(r"^([\w@.-]+\.(?:service|socket|timer|mount|scope)): ")
# systemd's own words about a unit; the unit itself is in the services section.
UNIT_FAILURE = re.compile(r"Failed to start |Main process exited|Failed with result")


def detect(ctx):
    entries = read_entries(ctx)
    if entries is None:
        return [Finding(key="journal:unreadable", severity=Severity.WARNING, text="журнал не читается",
                        hint="journalctl -p err -b вернул ошибку")]
    boot_id = ctx.path("/proc/sys/kernel/random/boot_id").read_text().strip()
    counts, samples = group(ctx, entries)
    findings = [firmware_finding(ctx, firmware) for firmware in firmware_failures(entries)]
    if any(NO_SPACE.search(message) for _, message in entries):
        findings.append(Finding(key="journal:no-space", severity=Severity.PROBLEM,
                                text="в журнале есть «No space left on device»: диск переполнялся",
                                hint="что занимает место и что можно освободить — в разделе «Диск»"))
    findings += source_findings(ctx, boot_id, counts, samples)
    remember(ctx, boot_id, counts)
    return findings


def read_entries(ctx):
    """(source, message) of every entry of priority err and worse in this boot, or None on failure."""
    result = ctx.run(["journalctl", "-p", "err", "-b", "-o", "json", "--no-pager", "-q", "--output-fields",
                      "SYSLOG_IDENTIFIER,_COMM,MESSAGE,_SYSTEMD_UNIT,_SYSTEMD_USER_UNIT"], timeout=60)
    if not result.ok:
        return None
    entries = []
    for line in result.lines:
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        entries.append((source_of(entry), text_of(entry.get("MESSAGE"))))
    return entries


def source_of(entry):
    """The program's name. systemd logs a process that died before exec as "(name)", by itself useless:
    that one is named by its unit, from the entry's fields or from the "unit: " its message starts with."""
    name = entry.get("SYSLOG_IDENTIFIER") or entry.get("_COMM") or "?"
    if not name.startswith("("):
        return name
    unit = entry.get("_SYSTEMD_USER_UNIT") or entry.get("_SYSTEMD_UNIT")
    prefix = UNIT_PREFIX.match(text_of(entry.get("MESSAGE")))
    return unit or (prefix.group(1) if prefix else name)


def text_of(message):
    """journalctl gives a message that is not valid UTF-8 as a list of bytes."""
    if isinstance(message, list):
        return bytes(message).decode("utf-8", "replace")
    return message or ""


def group(ctx, entries):
    counts = Counter()
    samples = defaultdict(list)
    for source, message in entries:
        if ctx.config.ignores(source, message) or UNIT_FAILURE.search(message):
            continue
        counts[source] += 1
        if message not in samples[source] and len(samples[source]) < SAMPLES:
            samples[source].append(message)
    return counts, samples


def source_findings(ctx, boot_id, counts, samples):
    """New sources and spikes are warnings; a known source at its usual rate is listed as info."""
    previous = ctx.previous
    counted_before = previous.journal_counts if previous.boot_id == boot_id else {}
    findings = []
    for source, count in counts.most_common():
        added = count - counted_before.get(source, 0)
        evidence = tuple(sample[:200] for sample in samples[source])
        if source not in previous.journal_sources:
            findings.append(Finding(key=f"journal:new:{source}", severity=Severity.WARNING,
                                    text=f"новый источник ошибок: {source} — {count} за эту загрузку",
                                    evidence=evidence))
        elif added >= ctx.config.spike:
            findings.append(Finding(key=f"journal:spike:{source}:{boot_id}:{count}", severity=Severity.WARNING,
                                    text=f"всплеск ошибок: {source} — +{added} с прошлой проверки "
                                         f"({count} за загрузку)",
                                    evidence=evidence))
        else:
            findings.append(Finding(key=f"journal:known:{source}", severity=Severity.INFO,
                                    text=f"{source}: {count} за загрузку, источник уже известен", evidence=evidence))
    return findings


def remember(ctx, boot_id, counts):
    ctx.observed.boot_id = boot_id
    ctx.observed.journal_counts = dict(counts)
    ctx.observed.journal_sources = sorted(set(ctx.previous.journal_sources) | set(counts))


def firmware_failures(entries):
    return sorted({match.group(1) for _, message in entries for match in FIRMWARE.finditer(message)})


def firmware_finding(ctx, firmware):
    """Which package ships the missing firmware, when pacman's file database can tell."""
    key = f"journal:firmware:{firmware}"
    text = f"ядру не хватило прошивки {firmware}"
    if not list(ctx.path("/var/lib/pacman/sync").glob("*.files")):
        return Finding(key=key, severity=Severity.WARNING, text=text,
                       hint="чей это файл, скажет pacman -F после sudo pacman -Fy (база файлов пакетов)")
    package = firmware_package(ctx, firmware)
    if not package:
        return Finding(key=key, severity=Severity.WARNING, text=text,
                       hint="ни один пакет из репозиториев её не содержит: обычно это не мешает работе устройства")
    if ctx.run(["pacman", "-Q", package]).ok:
        return Finding(key=f"{key}:installed", severity=Severity.INFO,
                       text=f"{text}; пакет {package} уже стоит — подхватится после перезагрузки")
    return Finding(key=key, severity=Severity.WARNING, text=f"{text}; она есть в пакете {package}",
                   cure=Cure(f"установить {package}", CureKind.ASK, install_action(package), sudo=True))


def firmware_package(ctx, firmware):
    for suffix in ("", ".zst", ".xz"):
        found = ctx.run(["pacman", "-Fq", f"usr/lib/firmware/{firmware}{suffix}"])
        if found.ok and found.lines:
            return found.lines[0].split("/")[-1]
    return ""


def install_action(package):
    def install(ctx):
        if ctx.runner.interactive(["sudo", "pacman", "-S", "--needed", package]) != 0:
            raise CureFailed(f"pacman не установил {package}")
    return install
