"""Each check of rice doctor on a fake machine: the command output it reads is stubbed, its files are under
a temporary folder."""
import json
import os
import unittest
from datetime import timedelta
from unittest import mock

from doctor_fakes import NOW, Machine, keys

from doctor.checks import boot, crashes, disk, kernel, laptop, pacman, rice, services, system
from doctor.model import CureFailed, Severity
from doctor.state import State

MICROSECONDS = 1_000_000


def setUpModule():
    for name in ("DBUS_SESSION_BUS_ADDRESS", "XDG_RUNTIME_DIR", "HYPRLAND_INSTANCE_SIGNATURE", "WAYLAND_DISPLAY"):
        os.environ.pop(name, None)


class CheckTest(unittest.TestCase):
    def setUp(self):
        self.machine = Machine()
        self.runner = self.machine.runner

    def tearDown(self):
        self.machine.cleanup()


class ServicesTest(CheckTest):
    def test_failed_unit_with_its_journal_as_evidence(self):
        self.runner.on("systemctl list-units --all --state=failed", "cups.service loaded failed failed CUPS\n")
        self.runner.on("journalctl --unit cups.service", "cups: config broken\n")
        found = services.detect(self.machine.context())
        self.assertEqual(keys(found), ["failed:system:cups.service"])
        self.assertEqual(found[0].evidence, ("cups: config broken",))
        self.assertTrue(found[0].cure.sudo)

    def test_restart_loop_is_a_problem(self):
        self.runner.on("systemctl --user list-units --all --state=auto-restart",
                       "crucix.service loaded activating auto-restart Crucix\n")
        found = services.detect(self.machine.context())
        self.assertEqual(keys(found), ["loop:user:crucix.service"])
        self.assertIsNone(found[0].cure)

    def test_failed_unit_is_not_reported_twice(self):
        self.runner.on("systemctl list-units --all --state=failed", "a.service loaded failed failed A\n")
        self.runner.on("systemctl list-unit-files --state=enabled", "a.service enabled disabled\n")
        self.runner.on("systemctl show", "Id=a.service\nType=simple\nActiveState=failed\nResult=exit-code\n")
        self.assertEqual(keys(services.detect(self.machine.context())), ["failed:system:a.service"])

    def test_cure_failure_carries_systemctls_reason(self):
        self.runner.on("sudo -n systemctl restart", code=1, err="Job failed\n")
        with self.assertRaisesRegex(CureFailed, "Job failed"):
            services.restart_action("system", "a.service")(self.machine.context())


class KernelTest(CheckTest):
    def test_running_kernel_without_modules_needs_a_reboot(self):
        ctx = self.machine.context()
        self.assertEqual(kernel.detect(ctx), [])
        ctx.kernel_release = "6.1-new"
        self.assertEqual(keys(kernel.detect(ctx)), ["kernel:modules"])


class CrashesTest(CheckTest):
    def dumps(self, *entries):
        self.runner.on("coredumpctl", json.dumps([{"time": int(when.timestamp() * MICROSECONDS), "pid": pid,
                                                   "sig": 11, "exe": exe} for when, pid, exe in entries]))

    def test_grouped_by_program_and_signal_new_then_known(self):
        hour = timedelta(hours=1)
        portal = "/usr/lib/xdg-desktop-portal-hyprland"
        self.dumps((NOW - 2 * hour, 1, portal), (NOW - hour, 2, portal), (NOW - 30 * hour, 3, portal))
        self.runner.on("pacman -Qqo", "xdg-desktop-portal-hyprland\n")
        self.runner.on("checkupdates", "xdg-desktop-portal-hyprland 1.0-1 -> 1.1-1\n")
        ctx = self.machine.context()
        found = crashes.detect(ctx)
        self.assertEqual(len(found), 1)
        self.assertIn("упал 2 раз", found[0].text)
        self.assertIn("часть райса", found[0].text)
        self.assertIn("обновление до 1.1-1", found[0].hint)
        self.assertEqual(found[0].severity, Severity.WARNING)
        again = crashes.detect(self.machine.context(previous=ctx.observed))
        self.assertEqual(again[0].severity, Severity.INFO)

    def test_no_dumps_no_findings(self):
        self.runner.on("coredumpctl", code=1, err="No coredumps found.")
        self.assertEqual(crashes.detect(self.machine.context()), [])


class PacmanTest(CheckTest):
    def setUp(self):
        super().setUp()
        self.runner.on("checkupdates", code=2)

    def test_old_upgrade_offers_rice_upgrade(self):
        self.machine.write("/var/log/pacman.log", "[2026-10-01T10:00:00+0300] [PACMAN] starting full system upgrade\n"
                                                  "[2026-10-02T10:00:00+0300] [ALPM] upgraded x\n")
        found = pacman.upgrade_age(self.machine.context())
        self.assertEqual(keys(found), ["pacman:old-upgrade"])
        self.assertIn("rice upgrade", found[0].cure.description)

    def test_recent_upgrade_is_info(self):
        self.machine.write("/var/log/pacman.log", "[2026-11-20T10:00:00+0300] [PACMAN] starting full system upgrade\n")
        self.assertEqual(pacman.upgrade_age(self.machine.context())[0].severity, Severity.INFO)

    def test_old_keyring_goes_first(self):
        self.runner.on("checkupdates", "archlinux-keyring 20260101-1 -> 20260909-1\nmesa 1 -> 2\n")
        found = pacman.pending_updates(self.machine.context())
        self.assertEqual(keys(found), ["pacman:updates", "pacman:keyring"])

    def test_stale_lock_only_when_no_package_manager_runs(self):
        self.machine.write("/var/lib/pacman/db.lck", "")
        self.runner.on("pgrep", code=1)
        self.assertEqual(keys(pacman.stale_lock(self.machine.context())), ["pacman:stale-lock"])
        self.runner.on("pgrep -x yay")
        self.assertEqual(keys(pacman.stale_lock(self.machine.context())), ["pacman:busy"])

    def test_orphans_with_sizes(self):
        self.runner.on("pacman -Qtdq", "vala\ninkscape\n")
        self.runner.on("pacman -Qi", "Name            : vala\nInstalled Size  : 14.59 MiB\n\n"
                                     "Name            : inkscape\nInstalled Size  : 190.34 MiB\n")
        found = pacman.orphans(self.machine.context())
        self.assertEqual(found[0].evidence, ("vala  14.59 MiB", "inkscape  190.34 MiB"))

    def test_pacnew_with_a_short_diff(self):
        self.machine.write("/etc/tpm/profile.json", "type: TPM2_ALG_ECC\n")
        self.machine.write("/etc/tpm/profile.json.pacnew", "type: ecc\n")
        found = pacman.unmerged_configs(self.machine.context())
        self.assertEqual(found[0].key, "pacman:pacnew:/etc/tpm/profile.json.pacnew")
        self.assertIn("  -type: TPM2_ALG_ECC", found[0].evidence)
        self.assertIn("  +type: ecc", found[0].evidence)

    def test_full_finds_damaged_files_but_not_legitimate_changes(self):
        self.runner.on("pacman -Qkk", err="warning: papirus-icon-theme: /usr/share/icons/x (Symlink path mismatch)\n"
                                          "warning: glibc: /usr/lib/libc.so.6 (SHA256 checksum mismatch)\n"
                                          "warning: cups: /etc/cups/x (Permission denied)\n", code=1)
        found = pacman.damaged_files(self.machine.context(full=True))
        self.assertEqual(keys(found), ["pacman:damaged:glibc"])

    def test_aur_updates_only_with_a_helper(self):
        self.assertEqual(pacman.aur_updates(self.machine.context()), [])
        helper = self.machine.folder / "bin/yay"
        helper.parent.mkdir()
        helper.write_text("")
        helper.chmod(0o755)
        self.runner.on("yay -Qua", "foo 1 -> 2\n")
        found = pacman.aur_updates(self.machine.context(env={"PATH": str(helper.parent)}))
        self.assertEqual(found[0].text, "обновления AUR: 1")


class DiskTest(CheckTest):
    def df(self, percent):
        self.runner.on("df", f"Type Size Avail Use% Mounted\next4 1000 100 {percent}% /\n"
                             "fuse.portal 0 0 0% /run/user/1000/doc\n")

    def test_healthy_mount_is_info(self):
        self.df(50)
        self.assertEqual([finding.severity for finding in disk.detect(self.machine.context())], [Severity.INFO])

    def test_full_mount_lists_what_can_be_freed_with_sizes(self):
        self.df(95)
        big = self.machine.home / ".cache/yay/pkg/big"
        big.parent.mkdir(parents=True)
        big.write_bytes(b"\0" * (disk.SMALLEST_WORTH_LISTING + 1))
        self.runner.on("journalctl --disk-usage", "Archived and active journals take up 1.2G in the file system.\n")
        with mock.patch.object(disk, "on_mount", return_value=True):
            found = disk.detect(self.machine.context())
        self.assertEqual(found[0].severity, Severity.PROBLEM)
        freeable = [finding.text for finding in found[1:]]
        self.assertIn("можно освободить: сборки AUR в ~/.cache/yay — 20.0 МиБ", freeable)
        self.assertIn("можно освободить: системный журнал — 1.2G", freeable)

    def test_emptying_cure_keeps_the_folder(self):
        folder = self.machine.home / ".cache/thing"
        (folder / "sub").mkdir(parents=True)
        (folder / "file").write_text("x")
        disk.emptying_action(folder)(self.machine.context())
        self.assertEqual(list(folder.iterdir()), [])

    def test_smart_hint_without_smartctl(self):
        found = disk.smart_health(self.machine.context(full=True))
        self.assertIn("smartmontools", found[0].hint)


class RiceTest(CheckTest):
    def setUp(self):
        super().setUp()
        self.machine.write_home(".config/hypr/.rice-installed", "")
        self.env = {"PATH": "", "HYPRLAND_INSTANCE_SIGNATURE": "test"}

    def all_running(self):
        self.runner.on("busctl --user status", "PID=1\nComm=histuid\n")
        self.runner.on("pgrep").on("systemctl --user is-active")
        self.runner.on("quickshell list", "Instance abc:\n  Process ID: 1\n")
        themes = self.machine.home / ".config/hypr/themes/coffee"
        themes.mkdir(parents=True)
        (themes / "hypr.lua").write_text("")
        self.machine.write_home(".config/hypr/current-theme", "coffee\n")
        (self.machine.home / ".config/hypr/theme.lua").symlink_to(themes / "hypr.lua")

    def test_skipped_without_hyprland(self):
        self.assertEqual(keys(rice.detect(self.machine.context())), ["rice:no-hyprland"])

    def test_everything_running(self):
        self.all_running()
        self.assertEqual(rice.detect(self.machine.context(env=self.env)), [])

    def test_stopped_parts_are_problems_with_safe_cures(self):
        self.all_running()
        self.runner.on("pgrep -u 1000 -x waybar", code=1)
        self.runner.on("busctl --user status", "PID=2\nComm=mako\n")
        self.runner.on("quickshell list", "No running instances for x\n")
        found = rice.detect(self.machine.context(env=self.env))
        self.assertEqual(keys(found), ["rice:notifications", "rice:waybar", "rice:osd"])
        self.assertTrue(all(finding.cure.kind.value == "auto" for finding in found))

    def test_start_cure_fails_when_the_part_does_not_come_up(self):
        self.runner.on("quickshell list", "No running instances for x\n")
        osd = next(part for part in rice.COMPONENTS if part.key == "osd")
        with mock.patch.object(rice, "WAIT_STEP_SECONDS", 0), self.assertRaises(CureFailed):
            rice.start_action(osd)(self.machine.context(env=self.env))
        self.assertEqual(self.runner.spawned[0][:2], ["sh", "-c"])

    def test_config_errors_and_a_stale_theme_link(self):
        self.all_running()
        self.runner.on("hyprctl configerrors", "hyprland.lua:12: unknown option\n")
        self.machine.write_home(".config/hypr/current-theme", "night\n")
        (self.machine.home / ".config/hypr/themes/night").mkdir()
        found = rice.detect(self.machine.context(env=self.env))
        self.assertEqual(keys(found), ["rice:configerrors", "rice:theme-link"])
        self.assertIn("changetheme", found[1].cure.description)


class SystemTest(CheckTest):
    def test_dns_failure(self):
        self.runner.on("getent", code=2)
        self.assertEqual(keys(system.network(self.machine.context())), ["system:dns"])

    def test_https_failure_after_dns(self):
        self.runner.on("getent", "1.2.3.4 STREAM archlinux.org\n")
        self.runner.on("curl", code=28, err="curl: (28) timed out")
        self.assertEqual(keys(system.network(self.machine.context())), ["system:https"])

    def test_clock(self):
        self.runner.on("timedatectl show", "NTP=no\nNTPSynchronized=no\n")
        self.assertEqual(keys(system.clock(self.machine.context())), ["system:ntp-off"])

    def test_audio_units_with_restart_cure(self):
        self.runner.on("systemctl --user is-active pipewire.service")
        self.runner.on("systemctl --user is-active wireplumber.service", code=3)
        found = system.audio(self.machine.context())
        self.assertEqual(keys(found), ["system:audio:wireplumber.service"])

    def test_no_swap(self):
        self.machine.write("/proc/swaps", "Filename Type Size Used Priority\n")
        self.assertEqual(keys(system.swap(self.machine.context())), ["system:no-swap"])


class LaptopTest(CheckTest):
    def battery(self, full, design):
        for name, value in (("type", "Battery"), ("energy_full", full), ("energy_full_design", design),
                            ("cycle_count", "788")):
            self.machine.write(f"/sys/class/power_supply/BAT0/{name}", f"{value}\n")
        self.machine.write("/sys/class/power_supply/ADP0/type", "Mains\n")

    def test_battery_wear(self):
        self.battery(27230000, 35000000)
        found = laptop.batteries(self.machine.context())
        self.assertEqual(found[0].text, "батарея BAT0: 78% от заводской ёмкости, циклов: 788")
        self.assertEqual(found[0].severity, Severity.INFO)
        self.battery(20000000, 35000000)
        self.assertEqual(laptop.batteries(self.machine.context())[0].severity, Severity.WARNING)

    def test_hot_cpu(self):
        self.machine.write("/sys/class/hwmon/hwmon0/name", "amdgpu\n")
        self.machine.write("/sys/class/hwmon/hwmon4/name", "k10temp\n")
        self.machine.write("/sys/class/hwmon/hwmon4/temp1_input", "95000\n")
        self.assertEqual(keys(laptop.cpu_temperature(self.machine.context())), ["laptop:cpu-hot"])


class BootTest(CheckTest):
    def test_slow_services_only(self):
        self.runner.on("systemd-analyze blame", "1min 2.5s slow.service\n12.003s other.service\n"
                                                "9.9s fast.service\n15.1s dev-tpm0.device\n345ms tiny.service\n")
        found = boot.detect(self.machine.context())
        self.assertEqual(found[0].evidence, ("1min 2.5s  slow.service", "12.003s  other.service"))


class StateTest(CheckTest):
    def test_unreadable_state_is_a_first_run(self):
        from doctor import state
        path = self.machine.write_home("state.json", "{broken")
        self.assertEqual(state.load(path), State())


if __name__ == "__main__":
    unittest.main()
