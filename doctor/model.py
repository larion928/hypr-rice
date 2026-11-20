"""What a check reports: findings, and the cures some of them carry."""
from dataclasses import dataclass, field
from enum import Enum
from typing import Callable, Optional


class Severity(Enum):
    PROBLEM = "problem"
    WARNING = "warning"
    INFO = "info"


class CureKind(Enum):
    AUTO = "auto"  # safe to run unasked: `rice doctor --fix -y` runs it
    ASK = "ask"    # runs only after a yes to its question


class CureFailed(Exception):
    """A cure's action could not do its job; the message says why, in Russian."""


@dataclass(frozen=True)
class Cure:
    description: str
    kind: CureKind
    action: Callable  # action(context); raises CureFailed
    sudo: bool = False


@dataclass(frozen=True)
class Finding:
    """key names the condition across runs: the same problem found again has the same key, so a cure is
    judged by whether its key is gone, and a notification is sent only for keys the last run lacked."""
    key: str
    severity: Severity
    text: str
    evidence: tuple = ()
    cure: Optional[Cure] = None
    hint: str = ""


@dataclass
class Section:
    title: str
    check: object  # the module whose detect() produced the findings, run again after a cure
    findings: list = field(default_factory=list)
