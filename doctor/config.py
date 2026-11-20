"""~/.config/hypr-rice/doctor.conf: what this machine watches, ignores and tolerates. Its format is
described in default.conf, which is also what a missing file is created from."""
import configparser
import re
import shutil
from dataclasses import dataclass
from pathlib import Path

DEFAULT = Path(__file__).with_name("default.conf")


@dataclass(frozen=True)
class Config:
    watched_services: tuple
    ignored_sources: frozenset
    ignored_patterns: tuple
    spike: int
    disk_warning: int
    disk_problem: int
    upgrade_days: int
    cpu_temperature: int
    battery_health: int
    boot_service_seconds: float
    journal_keep: str

    def ignores(self, source, message):
        return source in self.ignored_sources or any(pattern.search(message) for pattern in self.ignored_patterns)


def load(path):
    """The user's file over the defaults; created from the defaults when there is none, so it can be found."""
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy(DEFAULT, path)
    parser = configparser.ConfigParser(interpolation=None)
    parser.read(DEFAULT, encoding="utf-8")
    parser.read(path, encoding="utf-8")
    services = parser["services"]
    journal = parser["journal"]
    limits = parser["thresholds"]
    return Config(
        watched_services=tuple(services.get("watch", "").split()),
        ignored_sources=frozenset(journal.get("ignore_sources", "").split()),
        ignored_patterns=tuple(re.compile(line.strip())
                               for line in journal.get("ignore_patterns", "").splitlines() if line.strip()),
        spike=journal.getint("spike"),
        disk_warning=limits.getint("disk_warning"),
        disk_problem=limits.getint("disk_problem"),
        upgrade_days=limits.getint("upgrade_days"),
        cpu_temperature=limits.getint("cpu_temperature"),
        battery_health=limits.getint("battery_health"),
        boot_service_seconds=limits.getfloat("boot_service_seconds"),
        journal_keep=limits.get("journal_keep"),
    )
