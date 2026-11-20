"""--notify, for the daily timer: a notification only when there is a problem or something the last run
did not see; its action «Открыть отчёт» opens the full report in a terminal. histuid shows the
"open" action as a button and invokes "default" on a click (middle button by default) on the body."""
from .context import RICE
from .model import Severity
from .runner import TIMED_OUT

# notify-send --wait returns when the notification is closed or acted on. The daemon keeps an unanswered
# one in its history, so the doctor stops waiting after an hour rather than keep its unit running.
WAIT_SECONDS = 3600
SHOWN_IN_BODY = 3


def worth_notifying(findings, previous_keys):
    return any(finding.severity == Severity.PROBLEM
               or (finding.severity == Severity.WARNING and finding.key not in previous_keys)
               for finding in findings)


def summary(findings, previous_keys):
    problems = [finding for finding in findings if finding.severity == Severity.PROBLEM]
    news = [finding for finding in findings
            if finding.severity == Severity.WARNING and finding.key not in previous_keys]
    title = f"Проверка системы: проблем {len(problems)}, нового {len(news)}"
    shown = [finding.text for finding in (problems + news)[:SHOWN_IN_BODY]]
    rest = len(problems) + len(news) - len(shown)
    return title, "\n".join(shown + ([f"…и ещё {rest}"] if rest > 0 else []))


def send(ctx, title, body, urgent):
    """Shows the notification and opens the report if asked to; False when it could not be shown."""
    result = ctx.run(["notify-send", "-a", "rice doctor", "-u", "critical" if urgent else "normal",
                      "-A", "default=Открыть отчёт", "-A", "open=Открыть отчёт", "--wait", title, body],
                     timeout=WAIT_SECONDS)
    if result.out.strip() in ("default", "open"):
        # --hold: the window stays after the report is printed, until the user closes it.
        ctx.runner.interactive(["kitty", "--hold", "-e", str(RICE), "doctor"])
    return result.ok or result.code == TIMED_OUT
