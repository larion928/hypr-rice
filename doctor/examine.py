"""Runs the checks; one that breaks becomes a finding of its own instead of ending the run."""
from .checks import CHECKS
from .model import Finding, Section, Severity


def run_check(ctx, check):
    try:
        return check.detect(ctx)
    except Exception as error:  # a check that breaks on this machine must not hide the others
        return [Finding(key=f"check-broken:{check.__name__}", severity=Severity.WARNING,
                        text=f"проверка «{check.TITLE}» не выполнилась: {type(error).__name__}: {error}")]


def examine(ctx):
    return [Section(check.TITLE, check, run_check(ctx, check)) for check in CHECKS]


def all_findings(sections):
    return [finding for section in sections for finding in section.findings]
