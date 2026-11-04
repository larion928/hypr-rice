#!/usr/bin/env bash
# Tests for the rice manager and the waybar battery module. Every test gets an empty fake $HOME,
# so nothing on this machine is read or changed; pacman and sudo are replaced by stubs.
#   tests/run.sh           run all tests
#   tests/run.sh NAME...   run the named tests
set -uo pipefail

REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
FAILED=()

fail() { echo "      $*"; exit 1; }  # ends the test: each one runs in its own subshell

# Runs one test function in a subshell with HOME pointing at a fresh directory.
run_test() {
    local name=$1 sandbox
    sandbox=$(mktemp -d)
    if (export HOME="$sandbox/home"; mkdir -p "$HOME"; cd "$sandbox" && "$name") >"$sandbox/out" 2>&1; then
        echo "ok    $name"
    else
        echo "FAIL  $name"
        sed 's/^/      /' "$sandbox/out" | tail -n 20
        FAILED+=("$name")
    fi
    rm -rf "$sandbox"
}

# The rice manager's functions, with every system command it may reach stubbed out.
load_rice() {
    # shellcheck source=../rice
    source "$REPO/rice"
    set +e
    SRC=$REPO
    sudo() { "$@"; }
    pacman() { return 1; }
    flatpak() { return 1; }
    xdg-user-dirs-update() { :; }
    export RICE_ASSUME=y RICE_MODE=replace
}

rice_backups() { find "$HOME" -maxdepth 1 -name '.rice-backup-*'; }

# A first install over a foreign rice (replace mode) moves the foreign configs into one backup.
test_first_install_backs_up_foreign_rice() {
    load_rice
    mkdir -p "$HOME/.config/waybar"
    echo foreign > "$HOME/.config/waybar/config"
    inspect_existing_desktop >/dev/null
    copy_rice_files >/dev/null

    [ "$(rice_backups | wc -l)" -eq 1 ] || fail "ожидался один бэкап, есть: $(rice_backups)"
    [ "$(cat "$(rice_backups)/waybar/config")" = foreign ] || fail "чужой waybar не попал в бэкап"
    [ -f "$HOME/.config/hypr/hyprland.lua" ] || fail "файлы райса не скопированы"
    [ -f "$HOME/.config/quickshell/help/common/Theme.qml" ] || fail "панели не видят общий Theme.qml через ссылку common"
}

# Reinstalling or updating an installed rice leaves the user's own directories alone and makes
# no backup: kitty and waybar outside ~/.config/hypr-rice belong to other desktops.
test_reinstall_keeps_user_dirs() {
    load_rice
    mkdir -p "$HOME/.config/hypr" "$HOME/.config/kitty" "$HOME/.config/quickshell/mine"
    echo installed > "$HOME/.config/hypr/.rice-installed"
    echo mine > "$HOME/.config/kitty/kitty.conf"
    echo mine > "$HOME/.config/quickshell/mine/shell.qml"
    echo mine > "$HOME/.config/hypr/monitors.lua"
    inspect_existing_desktop >/dev/null
    copy_rice_files >/dev/null

    [ -z "$(rice_backups)" ] || fail "при переустановке появился бэкап: $(rice_backups)"
    [ "$(cat "$HOME/.config/kitty/kitty.conf")" = mine ] || fail "пропал свой kitty.conf"
    [ "$(cat "$HOME/.config/quickshell/mine/shell.qml")" = mine ] || fail "пропал свой файл в quickshell"
    [ "$(cat "$HOME/.config/hypr/monitors.lua")" = mine ] || fail "перезаписан monitors.lua"
}

# Uninstall puts back what was there before the rice, never a backup of the rice itself.
test_uninstall_restores_pre_rice_backup() {
    load_rice
    mkdir -p "$HOME/.config/waybar"
    echo foreign > "$HOME/.config/waybar/config"
    inspect_existing_desktop >/dev/null
    copy_rice_files >/dev/null
    record_install
    # Older rice versions backed up the rice itself on every update.
    local old="$HOME/.rice-backup-29990101-000000"
    mkdir -p "$old/hypr"
    echo installed > "$old/hypr/.rice-installed"
    echo rice > "$old/hypr/hyprland.lua"
    cmd_uninstall >/dev/null

    [ "$(cat "$HOME/.config/waybar/config" 2>/dev/null)" = foreign ] || fail "чужой waybar не вернулся"
    [ ! -e "$HOME/.config/hypr/hyprland.lua" ] || fail "после удаления остался или вернулся hyprland.lua райса"
    [ ! -e "$HOME/.local/bin/changetheme" ] || fail "после удаления остался changetheme"
}

# Uninstall of an install that never needed a backup only removes the rice's files.
test_uninstall_without_backup() {
    load_rice
    inspect_existing_desktop >/dev/null
    copy_rice_files >/dev/null
    record_install
    cmd_uninstall >/dev/null

    [ ! -e "$HOME/.config/hypr/hyprland.lua" ] || fail "остался hyprland.lua"
    [ ! -e "$HOME/.local/bin/rice" ] || fail "остался rice"
    [ -z "$(find "$HOME/.config/quickshell" -type l 2>/dev/null)" ] || fail "остались ссылки common в панелях"
}

# A fake pacman whose runs print the given lines to stderr and fail, one argument per run;
# "ok" makes that run succeed. Runs are counted in $HOME/pacman-runs.
fake_pacman() {
    printf '%s\n' "$@" > "$HOME/pacman-script"
    pacman() {
        local run line
        run=$(( $(cat "$HOME/pacman-runs" 2>/dev/null || echo 0) + 1 ))
        echo "$run" > "$HOME/pacman-runs"
        line=$(sed -n "${run}p" "$HOME/pacman-script")
        [ "$line" = ok ] && return 0
        echo "$line" >&2
        return 1
    }
    sleep() { :; }
    MIRRORLIST="$HOME/mirrorlist"
    PACMAN_CONF="$HOME/pacman.conf"
    echo "Server = https://mirror.example/\$repo/os/\$arch" > "$MIRRORLIST"
    echo "Include = /etc/pacman.d/mirrorlist" > "$PACMAN_CONF"
    cp "$MIRRORLIST" "$HOME/mirrorlist.orig"
}

# pac returns as soon as pacman does, with rice's sudo keeper running in the background: waiting on
# $! once waited on that keeper for ever, after a finished system upgrade.
test_pac_returns_with_background_job() {
    load_rice
    # Real programs, not shell functions: bash points $! elsewhere for those.
    unset -f sudo pacman
    mkdir -p "$HOME/bin"
    printf '#!/bin/sh\nexec "$@"\n' > "$HOME/bin/sudo"
    printf '#!/bin/sh\necho "warning: something" >&2\nexit 0\n' > "$HOME/bin/pacman"
    chmod +x "$HOME/bin/sudo" "$HOME/bin/pacman"
    PATH="$HOME/bin:$PATH"
    ( sleep 30 ) &
    local keeper=$! started=$SECONDS
    pac -Syu >/dev/null 2>&1 || fail "pac сообщил об ошибке"
    kill "$keeper" 2>/dev/null
    [ $((SECONDS - started)) -lt 5 ] || fail "pac ждал фоновый процесс $((SECONDS - started)) с"
}

# A package that does not exist is not a network problem: one try, mirrors untouched.
test_pac_gives_up_on_non_network_error() {
    load_rice
    fake_pacman "error: target not found: no-such-package" ok
    pac -S no-such-package >/dev/null 2>&1 && fail "pac сообщил об успехе"

    [ "$(cat "$HOME/pacman-runs")" -eq 1 ] || fail "попыток: $(cat "$HOME/pacman-runs"), ожидалась одна"
    cmp -s "$MIRRORLIST" "$HOME/mirrorlist.orig" || fail "список зеркал изменён"
}

# A stalled download is retried, and from the second failure the fallback mirrors go first.
test_pac_retries_network_error() {
    load_rice
    fake_pacman "error: failed retrieving file 'x.pkg.tar.zst' from mirror : Operation too slow" \
                "error: failed retrieving file 'x.pkg.tar.zst' from mirror : Operation too slow" ok
    pac -S x >/dev/null 2>&1 || fail "pac не дошёл до успешной попытки"

    [ "$(cat "$HOME/pacman-runs")" -eq 3 ] || fail "попыток: $(cat "$HOME/pacman-runs"), ожидалось три"
    grep -q 'yandex' "$MIRRORLIST" || fail "запасные зеркала не подключены"
}

# An app counts as installed only with its files too; its packages alone are checked separately
# (an update keeps the files of a program that is installed).
test_app_installed_needs_files() {
    load_rice
    pacman() { return 0; }
    APP_SRC[demo]="demo-pkg aur:demo-aur file:.local/bin/demo"
    app_packages_installed demo || fail "пакеты стоят, но app_packages_installed говорит нет"
    app_installed demo && fail "файла нет, но app_installed говорит да"
    mkdir -p "$HOME/.local/bin"
    touch "$HOME/.local/bin/demo"
    app_installed demo || fail "всё на месте, но app_installed говорит нет"
}

battery() { POWER_SUPPLY_DIR="$HOME/power_supply" python3 "$REPO/home/.config/hypr-rice/waybar/scripts/battery"; }

supply() {  # supply NAME TYPE [FILE=VALUE...]
    local dir="$HOME/power_supply/$1" pair
    mkdir -p "$dir"
    echo "$2" > "$dir/type"
    shift 2
    for pair in "$@"; do echo "${pair#*=}" > "$dir/${pair%%=*}"; done
}

# A desktop has no battery: the module stays hidden instead of showing a red 0%.
test_battery_hidden_without_battery() {
    supply AC Mains online=1
    [ "$(battery | jq -r .text)" = "" ] || fail "модуль виден без батареи: $(battery)"
}

# Batteries and chargers are found by type, whatever the laptop calls them.
test_battery_any_names() {
    supply BAT1 Battery capacity=57 status=Discharging
    supply AC Mains online=1
    local out
    out=$(battery)
    [ "$(jq -r .text <<<"$out")" = "57%" ] || fail "не тот заряд: $out"
    jq -e '.class | index("plugged")' <<<"$out" >/dev/null || fail "зарядка не найдена: $out"
}

# A wireless mouse reports its battery too (scope Device); it is not the laptop's.
test_battery_ignores_mouse() {
    supply hidpp_battery_0 Battery capacity=90 status=Discharging scope=Device
    [ "$(battery | jq -r .text)" = "" ] || fail "батарея мышки принята за батарею ноутбука: $(battery)"
}

# A prebuilt file from the GitHub release goes in only when its checksum is the one the signed
# repo lists; curl is faked to serve $HOME/served.
test_release_file_is_checked() {
    load_rice
    SRC=$HOME/src
    mkdir -p "$SRC/packages"
    echo genuine > "$HOME/genuine"
    echo "$(sha256sum < "$HOME/genuine" | cut -d' ' -f1)  .local/bin/tool" > "$SRC/packages/release.sha256"
    curl() {
        local out
        while [ $# -gt 0 ]; do [ "$1" = -o ] && out=$2; shift; done
        cp "$HOME/served" "$out"
    }

    echo forged > "$HOME/served"
    install_release_file .local/bin/tool 2>/dev/null && fail "подменённый файл принят"
    [ ! -e "$HOME/.local/bin/tool" ] || fail "подменённый файл остался на месте"

    cp "$HOME/genuine" "$HOME/served"
    install_release_file .local/bin/tool >/dev/null || fail "настоящий файл не принят"
    cmp -s "$HOME/.local/bin/tool" "$HOME/genuine" || fail "поставлен не тот файл"
    [ -x "$HOME/.local/bin/tool" ] || fail "файл не исполняемый"
}

# Edits made to a theme in the settings (fonts, colours, wallpapers) reach the theme loader, kitty
# and waybar; what was not edited stays the theme's own.
test_theme_edits_reach_the_programs() {
    local theme_dir="$HOME/.config/hypr/themes/claude"
    mkdir -p "$theme_dir" "$HOME/.config/hypr-rice" "$HOME/bin" "$HOME/Pictures"
    cp "$REPO/home/.config/hypr/themes/claude/"{palette.json,ui.json} "$theme_dir/"
    touch "$theme_dir/a.png" "$theme_dir/b.png" "$HOME/Pictures/mine.jpg"
    cat > "$HOME/.config/hypr-rice/theme-edits.json" <<EOF
{"themes": {"claude": {"fonts": {"font": "Test Mono", "body": "Test Sans", "display": ""},
                       "colors": {"accent": "#123456", "bg": "not a colour"},
                       "wallpapers": {"added": ["$HOME/Pictures/mine.jpg", "$HOME/gone.png"],
                                      "off": ["$theme_dir/a.png"]}}}}
EOF
    printf '#!/bin/sh\n' > "$HOME/bin/pkill" && chmod +x "$HOME/bin/pkill"
    PATH="$HOME/bin:$PATH" python3 - "$REPO/home/.config/hypr/scripts" "$HOME" <<'PY' || fail "генератор упал"
import sys
sys.path.insert(0, sys.argv[1])
from apptheme import kitty, waybar
from apptheme.theme import load
home = sys.argv[2]
theme = load("claude")
assert theme.font == "Test Mono", theme.font
assert theme.body_font == "Test Sans", theme.body_font
assert theme.display == "Source Serif 4", theme.display  # an empty choice keeps the theme's own
assert theme.colors["accent"] == "#123456", theme.colors["accent"]
assert theme.colors["bg"] == theme.own["colors"]["bg"], "a broken colour must be ignored"
walls = [str(p) for p in theme.wallpapers]
assert walls == [f"{home}/.config/hypr/themes/claude/b.png", f"{home}/Pictures/mine.jpg"], walls
kitty.apply(theme)
waybar.write_fonts(theme)
PY
    grep -qx "font_family Test Mono" "$HOME/.config/hypr-rice/kitty/theme.conf" || fail "kitty не получил шрифт"
    grep -qx "cursor #123456" "$HOME/.config/hypr-rice/kitty/theme.conf" || fail "kitty не получил цвет"
    grep -q '"Test Mono", "JetBrainsMono Nerd Font"' "$HOME/.config/hypr-rice/waybar/fonts.css" \
        || fail "waybar не получил шрифт"
}

# The waybar layout saved for every theme applies to all of them, a theme's own layout wins over
# it; a module only one theme defines is dropped elsewhere, and a bar at the bottom keeps its gap
# to the screen edge.
test_waybar_layout_edits() {
    local themes="$HOME/.config/hypr/themes"
    mkdir -p "$themes" "$HOME/.config/hypr-rice/waybar"
    cp -r "$REPO/home/.config/hypr/themes/"{claude,coffee} "$themes/"
    cp "$REPO/home/.config/hypr-rice/waybar/config.base.json" "$HOME/.config/hypr-rice/waybar/"
    cat > "$HOME/.config/hypr-rice/theme-edits.json" <<'EOF'
{"everywhere": {"waybar": {"modules-left": ["clock", "custom/claude"], "modules-right": ["tray"],
                           "position": "bottom"}},
 "themes": {"claude": {"waybar": {"modules-left": ["custom/claude"], "modules-right": ["clock"]}}}}
EOF
    python3 - "$REPO/home/.config/hypr/scripts" <<'PY' || fail "раскладка собрана не так"
import sys
sys.path.insert(0, sys.argv[1])
from apptheme import waybar
from apptheme.theme import load
coffee = waybar.config_for(load("coffee"))
assert coffee["modules-left"] == ["clock"], coffee["modules-left"]   # custom/claude is claude's own
assert coffee["modules-right"] == ["tray"], coffee["modules-right"]
assert coffee["position"] == "bottom" and "margin-bottom" in coffee and "margin-top" not in coffee
claude = waybar.config_for(load("claude"))
assert claude["modules-left"] == ["custom/claude"], claude["modules-left"]
assert claude["modules-right"] == ["clock"], claude["modules-right"]
assert claude["position"] == "bottom", "the shared position stays where the theme sets none"
PY
}

# Without thermal_zone0 waybar's temperature module reads the CPU's own sensor, found by name; with
# the zone it is left alone.
test_waybar_finds_cpu_sensor() {
    local sys="$HOME/sys"
    mkdir -p "$sys/devices/pci/hwmon/hwmon3" "$sys/devices/acpi/hwmon/hwmon0" "$sys/class/hwmon" "$sys/class/thermal"
    echo acpitz > "$sys/devices/acpi/hwmon/hwmon0/name"
    echo k10temp > "$sys/devices/pci/hwmon/hwmon3/name"
    echo 62750 > "$sys/devices/pci/hwmon/hwmon3/temp1_input"
    ln -s "$sys/devices/acpi/hwmon/hwmon0" "$sys/class/hwmon/hwmon0"
    ln -s "$sys/devices/pci/hwmon/hwmon3" "$sys/class/hwmon/hwmon3"
    python3 - "$REPO/home/.config/hypr/scripts" "$sys" <<'PY' || fail "датчик найден не так"
import sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
from apptheme import waybar
root = Path(sys.argv[2])
waybar.HWMON = root / "class/hwmon"
waybar.THERMAL_ZONE = root / "class/thermal/thermal_zone0"
found = waybar.cpu_sensor()
assert found == {"hwmon-path-abs": str(root / "devices/pci/hwmon"), "input-filename": "temp1_input"}, found
waybar.THERMAL_ZONE.mkdir()
assert waybar.cpu_sensor() == {}, "with thermal_zone0 the module keeps its default"
PY
}

# An icon picked for a module replaces the glyph its format starts with, or what {icon} stood for;
# modules whose icon says something (the workspaces) keep theirs.
test_waybar_icon_edits() {
    local themes="$HOME/.config/hypr/themes"
    mkdir -p "$themes" "$HOME/.config/hypr-rice/waybar"
    cp -r "$REPO/home/.config/hypr/themes/coffee" "$themes/"
    cp "$REPO/home/.config/hypr-rice/waybar/config.base.json" "$HOME/.config/hypr-rice/waybar/"
    echo '{"themes": {"coffee": {"icons": {"cpu": "X", "pulseaudio": "V", "hyprland/workspaces": "W"}}}}' \
        > "$HOME/.config/hypr-rice/theme-edits.json"
    python3 - "$REPO/home/.config/hypr/scripts" <<'PY' || fail "значки заменены не так"
import sys
sys.path.insert(0, sys.argv[1])
from apptheme import waybar
from apptheme.theme import load
config = waybar.config_for(load("coffee"))
assert config["cpu"]["format"] == "X {usage}%", config["cpu"]["format"]
assert config["pulseaudio"]["format"] == "V {volume}%", config["pulseaudio"]["format"]
assert config["hyprland/workspaces"]["format"] == "{icon}", "the workspaces' icon must stay"
assert "cpu" in waybar.layout(load("coffee"))["iconEditable"]
PY
}

# A theme can take another's battery drawing (in its own colours, with that drawing's animation), its
# own folder colour and icon theme; folders are recoloured only under a Papirus icon theme.
test_icon_edits() {
    local themes="$HOME/.config/hypr/themes"
    mkdir -p "$themes" "$HOME/.config/gtk-3.0" "$HOME/bin"
    cp -r "$REPO/home/.config/hypr/themes/"{coffee,night} "$themes/"
    printf '[Settings]\ngtk-icon-theme-name=Papirus-Dark\n' > "$HOME/.config/gtk-3.0/settings.ini"
    printf '#!/bin/sh\n' > "$HOME/bin/gsettings" && chmod +x "$HOME/bin/gsettings"
    mkdir -p "$HOME/.config/hypr-rice"
    echo '{"themes": {"coffee": {"battery": "night", "folders": "teal", "iconTheme": "breeze-dark"}}}' \
        > "$HOME/.config/hypr-rice/theme-edits.json"
    PATH="$HOME/bin:$PATH" python3 - "$REPO/home/.config/hypr/scripts" <<'PY' || fail "значки применены не так"
import sys
sys.path.insert(0, sys.argv[1])
from apptheme import battery, icon_theme
from apptheme.theme import load
coffee = load("coffee")
frames = battery.frames(coffee)
assert len(frames) == 7, len(frames)                                  # night's moon phases
assert coffee.colors["fg"] in frames[0], "drawn in coffee's colours"
assert coffee.ui.get("batteryAnim") == "pingpong", coffee.ui.get("batteryAnim")  # night's animation
assert coffee.ui["folders"] == "teal"
assert icon_theme.current(coffee) == "breeze-dark"
icon_theme.apply(coffee)
PY
    grep -qx "gtk-icon-theme-name=breeze-dark" "$HOME/.config/gtk-3.0/settings.ini" || fail "тема значков не записана"
    echo '{"themes": {}}' > "$HOME/.config/hypr-rice/theme-edits.json"
    PATH="$HOME/bin:$PATH" python3 - "$REPO/home/.config/hypr/scripts" <<'PY' || fail "тема значков не вернулась"
import sys
sys.path.insert(0, sys.argv[1])
from apptheme import icon_theme
from apptheme.theme import load
icon_theme.apply(load("coffee"))
PY
    grep -qx "gtk-icon-theme-name=Papirus-Dark" "$HOME/.config/gtk-3.0/settings.ini" || fail "без правки не вернулась тема значков райса"
}

# The settings window's bar fills a module's own format the way waybar does, and tells a script that
# printed nothing (shown only at times) from one that never answered.
test_bar_preview_formats() {
    python3 - "$REPO/home/.config/hypr/scripts" <<'PY' || fail "превью панели собрано не так"
import sys
sys.path.insert(0, sys.argv[1])
from apptheme import bar_preview as bar
assert bar.render("{icon} {volume}%", {"volume": 70}, ["low", "mid", "high"], 70) == "high 70%"
assert bar.render("{icon} {volume}%", {"volume": 10}, {"default": ["low", "mid", "high"]}, 10) == "low 10%"
assert bar.render(" {}", {"": "96"}) == "96"
assert bar.from_script("custom/updates", {"return-type": "json", "format": "{}"}, '{"text": "13"}') == bar.shown("13")
empty = bar.from_script("custom/updates", {"return-type": "json"}, "")
assert empty["state"] == "sometimes" and "обновлен" in empty["note"], empty
silent = bar.from_script("custom/x", {}, None)
assert silent["state"] == "sometimes" and "не ответил" in silent["note"], silent
PY
}

# rice-install-package takes the sudo password on stdin: a wrong one ends with status 2, a right one
# starts the install in the background (repo package through pacman, AUR one through yay with the sudo
# wrapper), whose log ends with "@@done 0"; the password is in no command's arguments, and nothing of
# it is left behind once the install is over.
test_install_package_password() {
    local bin="$HOME/bin" calls="$HOME/calls"
    mkdir -p "$bin" "$HOME/run"
    cat > "$bin/sudo" <<'EOF'
#!/bin/sh
# The fake sudo: -S reads the password from stdin; only "right" passes.
echo "sudo $*" >> "$CALLS"
[ "$1" = -S ] || exit 1
IFS= read -r given
[ "$given" = right ] || exit 1
shift 3  # -S -p ""
[ "$1" = -v ] && exit 0
"$@"
EOF
    printf '#!/bin/sh\necho "pacman $*" >> "$CALLS"\ncase "$1" in -Si) [ "$2" = repo-pkg ] ;; -Q) exit 0 ;; esac\n' > "$bin/pacman"
    printf '#!/bin/sh\necho "yay $*" >> "$CALLS"\n' > "$bin/yay"
    printf '#!/bin/sh\necho "notify-send $*" >> "$CALLS"\n' > "$bin/notify-send"
    chmod +x "$bin"/*
    export CALLS="$calls" XDG_RUNTIME_DIR="$HOME/run" PATH="$bin:$PATH"
    local tool="$REPO/home/.local/bin/rice-install-package" status
    echo wrong | "$tool" repo-pkg >/dev/null; status=$?
    [ "$status" -eq 2 ] || fail "неверный пароль дал код $status"
    [ -z "$(ls -A "$HOME/run")" ] || fail "после неверного пароля остались файлы: $(ls "$HOME/run")"

    echo right | "$tool" repo-pkg >/dev/null || fail "установка из репозитория не запустилась"
    install_finished repo-pkg
    grep -q "^sudo -S -p  pacman -S --needed --noconfirm repo-pkg$" "$calls" || fail "pacman вызван не через sudo -S: $(cat "$calls")"
    echo right | "$tool" aur-pkg >/dev/null || fail "установка из AUR не запустилась"
    install_finished aur-pkg
    grep -q "^yay -S .*--sudo $HOME/run/rice-sudo\.[^ ]*/sudo aur-pkg$" "$calls" || fail "yay вызван без обёртки sudo: $(grep yay "$calls")"
    grep -q "^notify-send .*Установлено: aur-pkg" "$calls" || fail "нет уведомления об установке"
    ! grep -q "right\|wrong" "$calls" || fail "пароль попал в аргументы команд"
    [ -z "$(ls -d "$HOME"/run/rice-sudo.* 2>/dev/null)" ] || fail "остались файлы с паролем"
}

# Waits up to 5 s for the background install of $1 to write its last line.
install_finished() {
    local log="$HOME/run/rice-install-$1.log" tries
    for tries in $(seq 50); do
        grep -q "^@@done 0$" "$log" 2>/dev/null && return 0
        sleep 0.1
    done
    fail "фоновая установка $1 не закончилась: $(cat "$log" 2>/dev/null)"
}

# Every member the settings window uses on its main objects (themeEdit.save, panelEditor.slots, ...) is
# defined; QML only notices a missing one when that line runs, e.g. on the first drag.
test_settings_members_defined() {
    python3 "$REPO/tests/qml_members.py" "$REPO/home/.config/quickshell/settings/shell.qml" \
        panelEditor themeEdit keys mon || fail "в окне настроек используется неопределённое"
}

# themegen builds and applies every theme in a fake $HOME; tests/themegen_snapshot.sh records it all.
test_themegen_applies_every_theme() {
    "$REPO/tests/themegen_snapshot.sh" "$HOME/snapshot" >/dev/null || fail "themegen упал, вывод выше"
    local folder theme
    for folder in "$REPO"/home/.config/hypr/themes/*/; do
        theme=$(basename "$folder")
        [ -s "$HOME/snapshot/apply-$theme/.config/hypr-rice/kitty/theme.conf" ] || fail "$theme: нет темы kitty"
        ls "$HOME/snapshot/build/.config/hypr/themes/$theme/assets/battery-0.svg" >/dev/null 2>&1 \
            || fail "$theme: нет значка батареи"
    done
}

tests=("$@")
[ ${#tests[@]} -gt 0 ] || mapfile -t tests < <(declare -F | awk '{print $3}' | grep '^test_')
for name in "${tests[@]}"; do
    run_test "$name"
done
if [ ${#FAILED[@]} -gt 0 ]; then
    echo "не прошли: ${FAILED[*]}"
    exit 1
fi
echo "все тесты прошли (${#tests[@]})"
