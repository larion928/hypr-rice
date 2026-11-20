"""rice doctor [--fix [-y]] [--full] [--notify]"""
import argparse
import configparser
import re
import sys
from pathlib import Path

from . import config as config_file
from . import fixing, notify, report
from . import state as state_file
from .context import Context
from .examine import all_findings, examine
from .model import Severity
from .runner import Runner

CONF = ".config/hypr-rice/doctor.conf"
STATE = ".local/state/hypr-rice/doctor.json"


def parse(argv):
    parser = argparse.ArgumentParser(
        prog="rice doctor", description="Проверка системы и райса: что сломано, почему и что с этим сделать.",
        add_help=False)
    parser.add_argument("-h", "--help", action="help", help="эта справка")
    parser.add_argument("--fix", action="store_true", help="после отчёта предложить лечение, спрашивая про каждое")
    parser.add_argument("-y", "--yes", action="store_true", help="с --fix: выполнить безопасное лечение без вопросов")
    parser.add_argument("--full", action="store_true", help="и медленные проверки: файлы пакетов, SMART дисков")
    parser.add_argument("--notify", action="store_true",
                        help="для таймера: уведомление, только если есть проблема или что-то новое")
    options = parser.parse_args(argv)
    if options.yes and not options.fix:
        parser.error("-y имеет смысл только вместе с --fix")
    if options.notify and options.fix:
        parser.error("--notify (фон) и --fix (вопросы) вместе не сочетаются")
    return options


def load_config(home, out):
    path = home / CONF
    try:
        return config_file.load(path)
    except (configparser.Error, ValueError, re.error) as error:
        out(f"{path}: ошибка в настройках ({error}), беру настройки по умолчанию")
        return config_file.load(config_file.DEFAULT)


def main(argv=None, runner=None, home=None, root=Path("/"), out=print):
    """runner, home and root are the real ones unless a test passes its own."""
    options = parse(sys.argv[1:] if argv is None else argv)
    home = home or Path.home()
    if options.notify:
        return notify_mode(options, runner, home, root, out)
    ctx = make_context(options, runner, home, root, out)
    sections = examine(ctx)
    out(report.render(sections, report.Painter(sys.stdout.isatty())))
    if options.fix:
        fix(ctx, sections, options.yes, out)
    save_state(ctx, sections, home)
    return 0


def make_context(options, runner, home, root, out):
    return Context(runner=runner or Runner(), config=load_config(home, out),
                   previous=state_file.load(home / STATE), home=home, root=root, full=options.full)


def fix(ctx, sections, unattended, out):
    out("\n● Лечение")
    candidates = fixing.curable(sections)
    if not unattended and not has_terminal():
        out("  для вопросов нужен терминал; безопасное лечение без вопросов: rice doctor --fix -y")
        return
    if unattended:
        chosen = fixing.choose_unattended(candidates, out)
    else:
        chosen = fixing.choose_interactively(candidates, ask_on_terminal)
    fixing.apply(ctx, chosen, out)
    out("\nПроверить снова: rice doctor")


def has_terminal():
    try:
        open("/dev/tty").close()
        return True
    except OSError:
        return False


def ask_on_terminal(question):
    try:
        with open("/dev/tty", "r+") as terminal:
            terminal.write(f"\n  {question}")
            terminal.flush()
            return terminal.readline().strip().lower().startswith(("y", "д"))
    except OSError:
        return False


def save_state(ctx, sections, home):
    ctx.observed.last_run = ctx.now.isoformat(timespec="seconds")
    ctx.observed.findings = sorted({finding.key for finding in all_findings(sections)
                                    if finding.severity != Severity.INFO})
    state_file.save(home / STATE, ctx.observed)


def notify_mode(options, runner, home, root, out):
    """Never fails: an exit status other than 0 would leave the doctor's own unit failed, and the next run
    would find that. What went wrong is printed to the unit's journal instead."""
    try:
        ctx = make_context(options, runner, home, root, out)
        sections = examine(ctx)
        findings = all_findings(sections)
        previous_keys = set(ctx.previous.findings)
        save_state(ctx, sections, home)
        if notify.worth_notifying(findings, previous_keys):
            title, body = notify.summary(findings, previous_keys)
            urgent = any(finding.severity == Severity.PROBLEM for finding in findings)
            if not notify.send(ctx, title, body, urgent):
                # Not shown, so not seen: the next run should still count all of it as new.
                state_file.save(home / STATE, ctx.previous)
                out("уведомление не показано (нет демона уведомлений?)")
    except Exception as error:
        out(f"rice doctor --notify: {type(error).__name__}: {error}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
