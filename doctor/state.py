"""~/.local/state/hypr-rice/doctor.json: what the last run saw, so a run can tell what is new since then.
  last_run         when it ran (ISO time)
  findings         keys of its problems and warnings: a notification is sent only for keys not among them
  boot_id          the boot its journal counts are from
  journal_counts   error entries per journal source in that boot, at that run
  journal_sources  every journal source that ever logged an error: a known one is no longer news
  crashes          ids of the core dumps already reported"""
import json
from dataclasses import dataclass, field


@dataclass
class State:
    last_run: str = ""
    findings: list = field(default_factory=list)
    boot_id: str = ""
    journal_counts: dict = field(default_factory=dict)
    journal_sources: list = field(default_factory=list)
    crashes: list = field(default_factory=list)


def load(path):
    """The last run's state; an empty one for the first run, or when the file is unreadable."""
    try:
        saved = json.loads(path.read_text())
        return State(**{name: saved[name] for name in State.__dataclass_fields__ if name in saved})
    except (OSError, ValueError, TypeError):
        return State()


def save(path, state):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(state.__dict__, ensure_ascii=False, indent=1))
    temporary.replace(path)
