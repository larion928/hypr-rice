"""The report as text: one block per check, then the totals."""
from .model import CureKind, Severity

COLORS = {"problem": "\033[31m", "warning": "\033[33m", "info": "\033[36m", "ok": "\033[32m", "bold": "\033[1m",
          "dim": "\033[2m", "reset": "\033[0m"}
MARKS = {Severity.PROBLEM: ("✗", "problem"), Severity.WARNING: ("⚠", "warning"), Severity.INFO: ("·", "info")}


class Painter:
    def __init__(self, enabled):
        self.enabled = enabled

    def __call__(self, color, text):
        return f"{COLORS[color]}{text}{COLORS['reset']}" if self.enabled else text


def render(sections, paint):
    lines = []
    for section in sections:
        lines += ["", paint("bold", f"● {section.title}")]
        if not any(finding.severity != Severity.INFO for finding in section.findings):
            lines.append(f"  {paint('ok', '✓')} в порядке")
        for finding in section.findings:
            lines += finding_lines(finding, paint)
    lines += ["", *totals(sections, paint)]
    return "\n".join(lines)


def finding_lines(finding, paint):
    mark, color = MARKS[finding.severity]
    lines = [f"  {paint(color, mark)} {finding.text}"]
    lines += [paint("dim", f"      {line}") for line in finding.evidence]
    if finding.cure:
        how = "rice doctor --fix -y" if finding.cure.kind == CureKind.AUTO else "rice doctor --fix"
        lines.append(f"      → лечение: {finding.cure.description} ({how})")
    if finding.hint:
        lines.append(f"      → {finding.hint}")
    return lines


def count(sections, severity):
    return sum(finding.severity == severity for section in sections for finding in section.findings)


def totals(sections, paint):
    problems = count(sections, Severity.PROBLEM)
    warnings = count(sections, Severity.WARNING)
    if not problems and not warnings:
        return [paint("ok", "Итог: всё в порядке.")]
    lines = [f"Итог: проблем {paint('problem', str(problems))}, предупреждений {paint('warning', str(warnings))}."]
    curable = sum(finding.cure is not None for section in sections for finding in section.findings)
    if curable:
        lines.append(f"Лечение есть для {curable}: rice doctor --fix")
    return lines
