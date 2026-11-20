"""rice doctor as a whole: each defect of the old sysdoc script it replaces has a test here that the old
design fails (numbered as in the review of sysdoc), plus the report, --fix and --notify flows."""
import io
import json
import os
import unittest
from pathlib import Path
from unittest import mock

from doctor_fakes import Machine, keys

from doctor import __main__ as doctor_main
from doctor import fixing, notify
from doctor.checks import journal, services
from doctor.examine import examine, run_check
from doctor.model import Cure, CureFailed, CureKind, Finding, Section, Severity
from doctor.runner import Runner
from doctor.state import State

REPO = Path(__file__).resolve().parents[2]
SESSION_VARIABLES = ("DBUS_SESSION_BUS_ADDRESS", "XDG_RUNTIME_DIR", "HYPRLAND_INSTANCE_SIGNATURE", "WAYLAND_DISPLAY",
                     "DISPLAY")


def setUpModule():
    # The doctor reads os.environ when no test env is given: it must not see the live session.
    for name in SESSION_VARIABLES:
        os.environ.pop(name, None)


def journal_line(identifier, message, unit=None):
    entry = {"SYSLOG_IDENTIFIER": identifier, "MESSAGE": message}
    if unit:
        entry["_SYSTEMD_UNIT"] = unit
    return json.dumps(entry, ensure_ascii=False)


class DoctorTest(unittest.TestCase):
    def setUp(self):
        self.machine = Machine()
        self.runner = self.machine.runner

    def tearDown(self):
        self.machine.cleanup()

    def run_main(self, *argv):
        printed = []
        code = doctor_main.main(list(argv), runner=self.runner, home=self.machine.home, root=self.machine.root,
                                out=printed.append)
        return code, "\n".join(printed)


class Defect1ExitStatusTest(DoctorTest):
    """sysdoc exited 1 on any problem, so its own unit failed and every next run reported it."""

    def test_notify_exits_zero_with_problems(self):
        self.runner.on("systemctl list-units --all --state=failed", "cups.service loaded failed failed CUPS\n")
        self.assertEqual(self.run_main("--notify")[0], 0)

    def test_notify_exits_zero_when_everything_breaks(self):
        with mock.patch.object(doctor_main, "examine", side_effect=RuntimeError("сломалось")):
            code, printed = self.run_main("--notify")
        self.assertEqual(code, 0)
        self.assertIn("сломалось", printed)

    def test_a_broken_check_is_a_finding_not_a_crash(self):
        with mock.patch.object(services, "detect", side_effect=KeyError("Id")):
            found = run_check(self.machine.context(), services)
        self.assertEqual(keys(found), ["check-broken:doctor.checks.services"])

    def test_own_unit_is_never_reported(self):
        self.runner.on("systemctl --user list-units --all --state=failed",
                       "rice-doctor.service loaded failed failed check\n")
        self.runner.on("systemctl --user list-unit-files", "rice-doctor.service enabled disabled\n")
        self.assertEqual(services.detect(self.machine.context()), [])

    def test_unit_cannot_end_failed(self):
        unit = (REPO / "home/.config/systemd/user/rice-doctor.service").read_text()
        self.assertIn("ExecStart=-%h/.local/bin/rice doctor --notify", unit)
        self.assertIn("TimeoutStartSec=infinity", unit)


class Defect2WatchedServicesTest(DoctorTest):
    """sysdoc watched a hardcoded zapret2.service that did not exist: a permanent error everywhere."""

    def test_default_config_watches_nothing(self):
        self.assertEqual(self.machine.context().config.watched_services, ())

    def test_missing_watched_unit_is_a_warning_pointing_to_the_config(self):
        self.runner.on("systemctl show", "Id=zapret2.service\nLoadState=not-found\nActiveState=inactive\n")
        found = services.watched_units(self.machine.context(conf="[services]\nwatch = zapret2.service\n"))
        self.assertEqual(found[0].severity, Severity.WARNING)
        self.assertIn("doctor.conf", found[0].hint)

    def test_stopped_watched_unit_is_a_problem_with_a_start_cure(self):
        self.runner.on("systemctl --user show", "Id=sync.service\nLoadState=loaded\nActiveState=inactive\n")
        found = services.watched_units(self.machine.context(conf="[services]\nwatch = user:sync.service\n"))
        self.assertEqual((found[0].severity, found[0].cure.sudo), (Severity.PROBLEM, False))


class Defect3JournalLocaleTest(DoctorTest):
    """sysdoc matched English short dates; under the Russian locale ("ноя 21 00:02:35") it counted nothing."""

    def test_entries_are_counted_from_json_whatever_the_locale(self):
        lines = [journal_line("kernel", "ноя 21 00:02:35 ошибка"), journal_line("kernel", "вторая"),
                 journal_line("wpa_supplicant", "nl80211: not supported")]
        self.runner.on("journalctl -p err -b -o json", "\n".join(lines))
        found = journal.detect(self.machine.context())
        self.assertIn("kernel — 2 за эту загрузку", found[0].text)
        self.assertEqual(len(found), 2)

    def test_parsed_commands_run_in_the_c_locale(self):
        runner = Runner(env={"LANG": "ru_RU.UTF-8", "PATH": "/usr/bin"})
        self.assertEqual(runner.parsed_env["LC_ALL"], "C.UTF-8")

    def test_a_dead_before_exec_process_is_named_by_its_unit(self):
        self.runner.on("journalctl -p err -b -o json", "\n".join([
            journal_line("(node)", "crucix.service: Changing to the requested working directory failed"),
            journal_line("(node)", "x", unit="crucix.service")]))
        found = journal.detect(self.machine.context())
        self.assertEqual(keys(found), ["journal:new:crucix.service"])

    def test_undecodable_message_does_not_break_the_check(self):
        self.runner.on("journalctl -p err -b -o json", json.dumps({"_COMM": "app", "MESSAGE": [104, 105, 255]}))
        self.assertIn("hi", journal.detect(self.machine.context())[0].evidence[0])


class Defect4OneshotTest(DoctorTest):
    """sysdoc flagged enabled-but-inactive oneshot units that ran and exited fine (NetworkManager-wait-online)."""

    def enabled(self, show):
        self.runner.on("systemctl list-unit-files --state=enabled", "unit.service enabled disabled\n")
        self.runner.on("systemctl show", show)
        return services.enabled_not_running(self.machine.context(), "system")

    def test_oneshot_that_finished_is_fine(self):
        self.assertEqual(self.enabled("Id=unit.service\nType=oneshot\nActiveState=inactive\nResult=success\n"), [])

    def test_started_on_demand_is_fine(self):
        self.assertEqual(self.enabled("Id=unit.service\nType=simple\nActiveState=inactive\nResult=success\n"
                                      "TriggeredBy=unit.socket\n"), [])
        self.assertEqual(self.enabled("Id=unit.service\nType=dbus\nActiveState=inactive\nResult=success\n"
                                      "BusName=org.example\n"), [])
        self.assertEqual(self.enabled("Id=unit.service\nType=simple\nActiveState=inactive\nResult=success\n"
                                      "ConditionResult=no\n"), [])

    def test_daemon_that_stopped_is_reported(self):
        found = self.enabled("Id=unit.service\nType=simple\nActiveState=inactive\nResult=exit-code\n")
        self.assertEqual(keys(found), ["inactive:system:unit.service"])


class Defect5BaselineTest(DoctorTest):
    """sysdoc printed a raw error count: thousands of known kernel lines looked like a new problem each day."""

    def journal_run(self, previous, counts, conf=""):
        lines = [journal_line(source, f"{source} {n}") for source, count in counts.items() for n in range(count)]
        self.runner.on("journalctl -p err -b -o json", "\n".join(lines))
        ctx = self.machine.context(previous=previous, conf=conf)
        return ctx, journal.detect(ctx)

    def test_a_known_source_at_its_usual_rate_is_info(self):
        ctx, _ = self.journal_run(State(), {"kernel": 5})
        _, found = self.journal_run(ctx.observed, {"kernel": 7})
        self.assertEqual([finding.severity for finding in found], [Severity.INFO])

    def test_a_spike_is_a_warning(self):
        ctx, _ = self.journal_run(State(), {"app": 5})
        _, found = self.journal_run(ctx.observed, {"app": 60})
        self.assertEqual(found[0].severity, Severity.WARNING)
        self.assertIn("+55", found[0].text)

    def test_ignored_sources_and_patterns_are_not_counted(self):
        conf = "[journal]\nignore_sources = kernel\nignore_patterns =\n  ^noise\n"
        self.runner.on("journalctl -p err -b -o json", "\n".join([
            journal_line("kernel", "x"), journal_line("app", "noise here"), journal_line("app", "real")]))
        found = journal.detect(self.machine.context(conf=conf))
        self.assertEqual(keys(found), ["journal:new:app"])
        self.assertIn("1 за эту загрузку", found[0].text)

    def test_notification_only_for_what_is_new(self):
        warning = Finding(key="pacman:orphans", severity=Severity.WARNING, text="сироты")
        self.assertTrue(notify.worth_notifying([warning], set()))
        self.assertFalse(notify.worth_notifying([warning], {"pacman:orphans"}))
        problem = Finding(key="failed:system:a", severity=Severity.PROBLEM, text="упал")
        self.assertTrue(notify.worth_notifying([problem], {"failed:system:a"}))


class Defect6NotificationTest(DoctorTest):
    """sysdoc's notification had no way to open the report."""

    def problem(self):
        self.runner.on("systemctl list-units --all --state=failed", "cups.service loaded failed failed CUPS\n")

    def test_notification_offers_the_report_and_opens_it(self):
        self.problem()
        self.runner.on("notify-send", "open\n")
        self.assertEqual(self.run_main("--notify")[0], 0)
        sent = self.runner.called("notify-send")[0]
        self.assertIn("--wait", sent)
        self.assertIn("open=Открыть отчёт", sent)
        self.assertIn("default=Открыть отчёт", sent)
        self.assertEqual(self.runner.interactive_calls[0][:4], ["kitty", "--hold", "-e", str(REPO / "rice")])
        self.assertEqual(self.runner.interactive_calls[0][4], "doctor")

    def test_dismissed_notification_opens_nothing(self):
        self.problem()
        self.runner.on("notify-send", "")
        self.run_main("--notify")
        self.assertEqual(self.runner.interactive_calls, [])

    def test_nothing_new_no_notification(self):
        self.machine.healthy()
        self.runner.on("notify-send", "")
        self.runner.on("journalctl -p err -b -o json", journal_line("kernel", "x"))
        self.run_main("--notify")
        self.run_main("--notify")
        self.assertEqual(len(self.runner.called("notify-send")), 1)

    def test_unshown_notification_keeps_the_news_new(self):
        self.machine.healthy()
        self.runner.on("journalctl -p err -b -o json", journal_line("kernel", "x"))
        self.runner.on("notify-send", "", code=1, err="no daemon")
        self.run_main("--notify")
        self.runner.on("notify-send", "")
        self.run_main("--notify")
        self.assertEqual(len(self.runner.called("notify-send")), 2)


class Defect7VerifiedCureTest(DoctorTest):
    """sysdoc ran each fix as a string through bash -c and called it done on exit status 0."""

    def failed_unit_section(self, stays_failed):
        listings = iter(["cups.service loaded failed failed CUPS\n",
                         "cups.service loaded failed failed CUPS\n" if stays_failed else ""])
        self.runner.on("systemctl list-units --all --state=failed", lambda: next(listings))
        self.runner.on("sudo -n systemctl", "")
        ctx = self.machine.context()
        return ctx, Section(services.TITLE, services, services.detect(ctx))

    def cure_output(self, stays_failed):
        ctx, section = self.failed_unit_section(stays_failed)
        printed = []
        fixing.apply(ctx, fixing.choose_interactively(fixing.curable([section]), lambda question: True),
                     printed.append)
        return "\n".join(printed)

    def test_cure_that_did_not_help_is_reported_as_such(self):
        self.assertIn("не помогло: проверка всё ещё видит", self.cure_output(stays_failed=True))

    def test_cure_is_judged_by_the_check_run_again(self):
        printed = self.cure_output(stays_failed=False)
        self.assertIn("исправлено", printed)
        self.assertTrue(self.runner.called("sudo -n systemctl restart cups.service"))

    def test_failing_cure_says_why(self):
        def broken(ctx):
            raise CureFailed("нет сети")
        finding = Finding(key="k", severity=Severity.PROBLEM, text="t", cure=Cure("d", CureKind.ASK, broken))
        printed = []
        fixing.apply(self.machine.context(), [(Section("s", services, [finding]), finding)], printed.append)
        self.assertIn("не помогло: нет сети", "\n".join(printed))

    def test_sudo_is_asked_once_and_only_when_needed(self):
        def cure(sudo):
            return Cure("d", CureKind.AUTO, lambda ctx: None, sudo=sudo)
        user_only = [(Section("s", services, []), Finding(key="a", severity=Severity.WARNING, text="a",
                                                         cure=cure(False)))]
        fixing.apply(self.machine.context(), user_only, lambda line: None)
        self.assertEqual(self.runner.interactive_calls, [])
        both = [(Section("s", services, []), Finding(key=key, severity=Severity.WARNING, text=key, cure=cure(True)))
                for key in ("a", "b")]
        fixing.apply(self.machine.context(), both, lambda line: None)
        self.assertEqual(self.runner.interactive_calls, [["sudo", "-v"]])

    def test_yes_runs_only_safe_cures(self):
        safe = Finding(key="a", severity=Severity.WARNING, text="a", cure=Cure("safe", CureKind.AUTO, None))
        asked = Finding(key="b", severity=Severity.WARNING, text="b", cure=Cure("asked", CureKind.ASK, None))
        section = Section("s", services, [safe, asked])
        printed = []
        chosen = fixing.choose_unattended(fixing.curable([section]), printed.append)
        self.assertEqual([finding.key for _, finding in chosen], ["a"])
        self.assertIn("asked", printed[0])


class ReportTest(DoctorTest):
    def test_report_runs_every_check_and_saves_state(self):
        code, printed = self.run_main()
        self.assertEqual(code, 0)
        for title in ("Службы", "Ядро", "Журнал", "Падения", "Пакеты", "Диск", "Райс", "Система", "Загрузка"):
            self.assertIn(title, printed)
        saved = json.loads((self.machine.home / ".local/state/hypr-rice/doctor.json").read_text())
        self.assertIn("last_run", saved)
        self.assertTrue((self.machine.home / ".config/hypr-rice/doctor.conf").exists())

    def test_broken_config_falls_back_to_defaults(self):
        self.machine.write_home(".config/hypr-rice/doctor.conf", "[thresholds]\ndisk_warning = много\n")
        code, printed = self.run_main()
        self.assertEqual(code, 0)
        self.assertIn("ошибка в настройках", printed)

    def test_bad_option_combinations_are_refused(self):
        for argv in (["-y"], ["--notify", "--fix"]):
            with self.assertRaises(SystemExit), mock.patch("sys.stderr", io.StringIO()):
                doctor_main.parse(argv)

    def test_examine_returns_a_section_per_check(self):
        self.assertEqual(len(examine(self.machine.context())), 10)


if __name__ == "__main__":
    unittest.main()
