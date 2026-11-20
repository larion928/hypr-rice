"""The rice's own session parts: the notification daemon, the bar, the OSD, the wallpaper daemon, the
screen-capture portal, Hyprland's config and the theme link. Restarting a part is safe (it is what
logging in does), so those cures run with --fix -y too."""
import time
from dataclasses import dataclass
from typing import Callable

from ..model import Cure, CureFailed, CureKind, Finding, Severity

TITLE = "Райс"
WAIT_STEPS = 8
WAIT_STEP_SECONDS = 0.5


def detect(ctx):
    if not (ctx.home / ".config/hypr/.rice-installed").exists():
        return [Finding(key="rice:not-installed", severity=Severity.INFO, text="райс не установлен — пропускаю")]
    if not ctx.hyprland_running():
        return [Finding(key="rice:no-hyprland", severity=Severity.INFO,
                        text="Hyprland не запущен — части райса не проверялись")]
    return [*components(ctx), *config_errors(ctx), *theme_link(ctx)]


def wait_until(condition):
    for _ in range(WAIT_STEPS):
        if condition():
            return True
        time.sleep(WAIT_STEP_SECONDS)
    return False


@dataclass(frozen=True)
class Component:
    key: str
    label: str
    executable: str       # its program's name, as a core dump names it
    is_running: Callable  # is_running(context) -> bool
    start: Callable       # start(context); raises CureFailed


def components(ctx):
    return [Finding(key=f"rice:{part.key}", severity=Severity.PROBLEM, text=f"не работает: {part.label}",
                    cure=Cure(f"запустить: {part.label}", CureKind.AUTO, start_action(part)))
            for part in COMPONENTS if not part.is_running(ctx)]


def start_action(part):
    def start(ctx):
        part.start(ctx)
        if not wait_until(lambda: part.is_running(ctx)):
            raise CureFailed(f"{part.label}: запущен(а), но сразу завершился(ась)")
    return start


def run_or_fail(ctx, argv, failure, timeout=60):
    result = ctx.run(argv, timeout=timeout)
    if not result.ok:
        raise CureFailed(result.err.strip()[-300:] or failure)


def spawn_or_fail(ctx, argv):
    if not ctx.runner.spawn(argv):
        raise CureFailed(f"нет программы {argv[0]}")


def process_running(name):
    return lambda ctx: ctx.run(["pgrep", "-u", str(ctx.uid), "-x", name]).ok


def histuid_owns_notifications(ctx):
    status = ctx.run(["busctl", "--user", "status", "org.freedesktop.Notifications"])
    return "Comm=histuid" in status.lines


def start_histuid(ctx):
    run_or_fail(ctx, ["systemctl", "--user", "restart", "histuid.service"], "histuid.service не перезапустился")


def start_waybar(ctx):
    run_or_fail(ctx, [str(ctx.home / ".local/bin/waybar-start")],
                "waybar запущен, но панель не показалась (подробности: ~/.cache/waybar-start.log)", timeout=90)


# The OSD's quickshell config, and the command hyprland.lua starts it with at login (it has no script of
# its own). Asked through quickshell's own instance list, not by a process's command line.
OSD_CONFIG = ".config/quickshell/osd"
OSD_COMMAND = f"OSD_BACKLIGHT=$(ls -d /sys/class/backlight/* 2>/dev/null | head -n1) quickshell -d -p ~/{OSD_CONFIG}"


def osd_running(ctx):
    listed = ctx.run(["quickshell", "list", "--path", str(ctx.home / OSD_CONFIG)])
    return listed.ok and listed.out.startswith("Instance ")


def start_osd(ctx):
    spawn_or_fail(ctx, ["sh", "-c", OSD_COMMAND])


def start_awww(ctx):
    spawn_or_fail(ctx, ["awww-daemon"])
    wallpaper = ctx.home / ".config/hypr/current-wallpaper"
    awww_running = process_running("awww-daemon")
    if wallpaper.exists() and wait_until(lambda: awww_running(ctx)):
        # A fresh daemon shows nothing until it is told what to show.
        ctx.run([str(ctx.home / ".local/bin/wallpaper"), wallpaper.read_text().strip()], timeout=60)


def portal_running(ctx):
    return ctx.run(["systemctl", "--user", "is-active", "xdg-desktop-portal-hyprland.service"]).ok


def start_portal(ctx):
    run_or_fail(ctx, [str(ctx.home / ".local/bin/portal-restart")], "portal-restart не сработал")


# Every part of the rice that must be running in a Hyprland session, and how the rice itself starts it.
COMPONENTS = (
    Component("notifications", "уведомления (histuid на шине org.freedesktop.Notifications)", "histuid",
              histuid_owns_notifications, start_histuid),
    Component("waybar", "панель waybar", "waybar", process_running("waybar"), start_waybar),
    Component("osd", "OSD громкости и яркости (quickshell)", "quickshell", osd_running, start_osd),
    Component("awww", "демон обоев awww-daemon", "awww-daemon", process_running("awww-daemon"), start_awww),
    Component("portal", "портал xdg-desktop-portal-hyprland (запись и показ экрана)", "xdg-desktop-portal-hyprland",
              portal_running, start_portal),
)


def config_errors(ctx):
    errors = ctx.run(["hyprctl", "configerrors"]).lines
    if not errors:
        return []
    return [Finding(key="rice:configerrors", severity=Severity.PROBLEM, text="в конфиге Hyprland ошибки",
                    evidence=tuple(errors[:10]), hint="исправь указанные строки; проверить: hyprctl configerrors")]


def theme_link(ctx):
    hypr = ctx.home / ".config/hypr"
    current_file = hypr / "current-theme"
    current = current_file.read_text().strip() if current_file.exists() else ""
    if not current or not (hypr / "themes" / current).is_dir():
        return [Finding(key="rice:theme-missing", severity=Severity.PROBLEM,
                        text=f"текущая тема «{current}» не найдена в ~/.config/hypr/themes",
                        hint="выбери тему: Alt+Shift+T или changetheme claude")]
    link = hypr / "theme.lua"
    expected = hypr / "themes" / current / "hypr.lua"
    if link.exists() and link.resolve() == expected.resolve():
        return []
    return [Finding(key="rice:theme-link", severity=Severity.PROBLEM,
                    text=f"~/.config/hypr/theme.lua не указывает на тему {current}",
                    evidence=(f"сейчас: {link.resolve() if link.is_symlink() else 'нет ссылки'}",),
                    cure=Cure(f"применить тему {current} заново (changetheme)", CureKind.AUTO,
                              reapply_theme(current)))]


def reapply_theme(theme):
    def reapply(ctx):
        result = ctx.run([str(ctx.home / ".local/bin/changetheme"), theme], timeout=180)
        if not result.ok:
            raise CureFailed(result.err.strip()[-300:] or "changetheme не сработал")
    return reapply
