"""--fix: choose the cures, ask for sudo once if a chosen one needs it, run each, then run its check again
and say what that check sees now. A cure counts as done only when its finding is gone."""
from .examine import run_check
from .model import CureFailed, CureKind


def curable(sections):
    return [(section, finding) for section in sections for finding in section.findings if finding.cure]


def choose_unattended(candidates, out):
    """--fix -y: the safe cures; the others are named, so nothing is skipped silently."""
    chosen = []
    for section, finding in candidates:
        if finding.cure.kind == CureKind.AUTO:
            chosen.append((section, finding))
        else:
            out(f"  пропущено (нужен ответ, запусти без -y): {finding.cure.description}")
    return chosen


def choose_interactively(candidates, ask):
    return [(section, finding) for section, finding in candidates
            if ask(f"{finding.text}\n    лечение: {finding.cure.description}. Выполнить? [y/N] ")]


def apply(ctx, chosen, out):
    if not chosen:
        out("  лечить нечего")
        return
    sudo_works = True
    if any(finding.cure.sudo for _, finding in chosen):
        out("  нужны права администратора (sudo):")
        sudo_works = ctx.runner.interactive(["sudo", "-v"]) == 0
    for number, (section, finding) in enumerate(chosen, 1):
        out(f"\n  [{number}/{len(chosen)}] {finding.cure.description}")
        if finding.cure.sudo and not sudo_works:
            out("    не выполнено: sudo не дал прав")
            continue
        out(f"    {verdict(ctx, section, finding)}")


def verdict(ctx, section, finding):
    try:
        finding.cure.action(ctx)
    except CureFailed as failure:
        return f"не помогло: {failure}"
    ctx.forget()
    remaining = next((left for left in run_check(ctx, section.check) if left.key == finding.key), None)
    if remaining is None:
        return "исправлено"
    detail = f" ({remaining.evidence[0]})" if remaining.evidence else ""
    return f"не помогло: проверка всё ещё видит «{remaining.text}»{detail}"
