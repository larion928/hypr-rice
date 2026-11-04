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

# The rice's own packages that are installed get marked as explicitly installed, so removing some
# program (pacman -Rs) or its orphans never takes them along.
test_rice_packages_marked_explicit() {
    load_rice
    pacman() {
        echo "pacman $*" >> "$HOME/calls"
        if [ "$1" = -Qq ]; then
            shift
            local name
            for name in "$@"; do
                case "$name" in grim|python-pillow) echo "$name" ;; esac
            done
            return 1  # some of the asked are not installed
        fi
    }
    mark_rice_packages_explicit
    grep -qx "pacman -D --asexplicit python-pillow grim" "$HOME/calls" \
        || fail "пакеты райса не отмечены: $(grep -- -D "$HOME/calls" || echo нет вызова)"
}

# The program menu offers to install only what is not installed, and to remove only what is.
test_catalog_choices() {
    load_rice
    APP_IDS=(firefox zen)
    declare -gA APP_GROUP=([firefox]=Браузеры [zen]=Браузеры) APP_NAME=([firefox]=Firefox [zen]="Zen Browser")
    declare -gA APP_SRC=([firefox]="firefox browser" [zen]="aur:zen-browser-bin browser")
    pacman() { [ "$1" = -Qq ] && echo zen-browser-bin; }
    [ "$(catalog_choices install)" = "Браузеры · Firefox=firefox" ] || fail "к установке предложено: $(catalog_choices install)"
    [ "$(catalog_choices remove)" = "Браузеры · Zen Browser=zen" ] || fail "к удалению предложено: $(catalog_choices remove)"
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
    pacman() { [ "$1" = -Qq ] && printf '%s\n' demo-pkg demo-aur; }
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
    grep -q "^yay -S .*--sudo $HOME/run/rice-sudo\.[^ ]*/sudo --mflags --config .*makepkg.conf aur-pkg$" "$calls" || fail "yay вызван без обёртки sudo: $(grep yay "$calls")"
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

# Window edits go to theme-edits.lua: only what was changed, the theme's animations rescaled for
# «быстрее»; the theme's own values are read from its hypr.lua.
test_window_edits() {
    local themes="$HOME/.config/hypr/themes"
    mkdir -p "$themes" "$HOME/.config/hypr-rice"
    cp -r "$REPO/home/.config/hypr/themes/coffee" "$themes/"
    echo '{"themes": {"coffee": {"windows": {"gaps_in": 2, "blur": false, "active_opacity": 0.9, "animations": "fast"}}}}' \
        > "$HOME/.config/hypr-rice/theme-edits.json"
    python3 - "$REPO/home/.config/hypr/scripts" <<'PY' || fail "правки окон записаны не так"
import sys
sys.path.insert(0, sys.argv[1])
from apptheme import windows
from apptheme.theme import load
coffee = load("coffee")
own = windows.own(coffee)
assert (own["gaps_in"], own["gaps_out"], own["border_size"], own["rounding"]) == (5, 10, 3, 6), own
windows.apply(coffee)
lua = windows.EDITS_LUA.read_text()
assert "hl.config({ general = { gaps_in = 2 }, decoration = { active_opacity = 0.9, blur = { enabled = false } } })" in lua, lua
assert 'leaf = "windowsIn",   enabled = true, speed = 1.8' in lua, lua   # 3 × 0.6
assert "gaps_out" not in lua and "rounding" not in lua, "only what was changed"
PY
}

# Every member the settings window uses on its main objects (themeEdit.save, panelEditor.slots, ...) is
# defined; QML only notices a missing one when that line runs, e.g. on the first drag.
test_settings_members_defined() {
    python3 "$REPO/tests/qml_members.py" "$REPO/home/.config/quickshell/settings/shell.qml" \
        panelEditor themeEdit keys mon ownThemes userFiles || fail "в окне настроек используется неопределённое"
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

# The Proton step hands .exe files to proton-run twice: by type (opening a file) and in the kernel
# (a .exe with the execute bit, which Thunar runs as a program); removing Proton takes both away.
test_proton_exe_hook() {
    load_rice
    PROTON_BINFMT="$HOME/binfmt.d/proton-run.conf"
    PROTON_BINFMT_RULE="$HOME/binfmt_misc/proton-run"
    mkdir -p "$HOME/binfmt.d" "$HOME/binfmt_misc"
    systemctl() { echo "systemctl $*" >> "$HOME/calls"; }
    xdg-mime() { echo "xdg-mime $*" >> "$HOME/calls"; }
    update-desktop-database() { :; }

    hook_proton_exe
    [ "$(cat "$PROTON_BINFMT")" = ":proton-run:M::MZ::$HOME/.local/bin/proton-run:" ] \
        || fail "неверное правило binfmt: $(cat "$PROTON_BINFMT")"
    grep -qx 'systemctl restart systemd-binfmt.service' "$HOME/calls" || fail "правило не загружено в ядро"
    grep -qx 'xdg-mime default umu-run.desktop application/x-msdownload' "$HOME/calls" \
        || fail ".exe не привязан к umu-run.desktop"

    echo ':proton-run enabled' > "$PROTON_BINFMT_RULE"
    unhook_proton_exe
    [ ! -e "$PROTON_BINFMT" ] || fail "правило binfmt осталось после удаления Proton"
    [ "$(cat "$PROTON_BINFMT_RULE")" = -1 ] || fail "правило не снято в ядре"
    [ ! -e "$HOME/.local/share/applications/umu-run.desktop" ] || fail "umu-run.desktop остался"
}

# rice update runs the setup steps of installed programs again, and only theirs.
test_update_reruns_installed_hooks() {
    load_rice
    APP_IDS=(kept gone)
    APP_SRC[kept]="hook:first-step"
    APP_SRC[gone]="hook:second-step"
    app_installed() { [ "$1" = kept ]; }
    hook_first_step() { echo first >> "$HOME/ran"; }
    hook_second_step() { echo second >> "$HOME/ran"; }

    rerun_installed_hooks
    [ "$(cat "$HOME/ran")" = first ] || fail "выполнились шаги: $(cat "$HOME/ran" 2>/dev/null)"
}

# Reloading GTK ends on the base theme gtk.css is written over, whatever theme the setting held:
# restoring the held one kept a wrong base (light Adwaita's grey dividers in Thunar) for good.
test_gtk_reload_lands_on_base_theme() {
    mkdir -p "$HOME/bin"
    printf '#!/bin/sh\n[ "$1" = get ] && { echo "'"'"'Adwaita-dark'"'"'"; exit 0; }\necho "$*" >> "%s/calls"\n' "$HOME" \
        > "$HOME/bin/gsettings"
    printf '#!/bin/sh\n:\n' > "$HOME/bin/systemctl"
    chmod +x "$HOME/bin/gsettings" "$HOME/bin/systemctl"
    PATH="$HOME/bin:$PATH" python3 - "$REPO/home/.config/hypr/scripts" "$HOME/calls" <<'PY' || fail "тема GTK не та"
import sys
sys.path.insert(0, sys.argv[1])
from apptheme import gtk
gtk.reload()
last = open(sys.argv[2]).read().splitlines()[-1]
assert last == f"set org.gnome.desktop.interface gtk-theme {gtk.base_theme()}", last
PY
}

# rice proton offers the downloaded Proton versions and Steam's own from every Steam library;
# a folder without the proton script is not a Proton.
test_proton_versions() {
    load_rice
    local steam="$HOME/.local/share/Steam" other="$HOME/games/SteamLibrary"
    mkdir -p "$steam/compatibilitytools.d/GE-Proton10-1" "$steam/compatibilitytools.d/broken" \
        "$steam/steamapps/common/Proton - Experimental" "$other/steamapps/common/Proton 9.0" \
        "$other/steamapps/common/Half-Life"
    touch "$steam/compatibilitytools.d/GE-Proton10-1/proton" "$steam/steamapps/common/Proton - Experimental/proton" \
        "$other/steamapps/common/Proton 9.0/proton"
    printf '"libraryfolders"\n{\n\t"0"\n\t{\n\t\t"path"\t\t"%s"\n\t}\n\t"1"\n\t{\n\t\t"path"\t\t"%s"\n\t}\n}\n' \
        "$steam" "$other" > "$steam/steamapps/libraryfolders.vdf"

    local expected="GE-Proton10-1=$steam/compatibilitytools.d/GE-Proton10-1
Proton - Experimental (Steam)=$steam/steamapps/common/Proton - Experimental
Proton 9.0 (Steam)=$other/steamapps/common/Proton 9.0"
    [ "$(proton_versions)" = "$expected" ] || fail "найдено: $(proton_versions)"
}

# A fake umu for proton-run: a package on PYTHONPATH whose main() records PROTONPATH, prints the
# lines in $HOME/umu-output and exits with the status in $HOME/umu-status (0 without the file).
fake_umu() {
    mkdir -p "$HOME/pylib/umu" "$HOME/bin"
    : > "$HOME/pylib/umu/__init__.py"
    cat > "$HOME/pylib/umu/__main__.py" <<'PY'
import os, sys
from pathlib import Path
home = Path(os.environ["HOME"])
def main():
    (home / "protonpath").write_text(os.environ.get("PROTONPATH", ""))
    output = home / "umu-output"
    if output.exists():
        print(output.read_text(), file=sys.stderr, end="")
    status = home / "umu-status"
    return int(status.read_text()) if status.exists() else 0
PY
    for name in quickshell hyprctl; do printf '#!/bin/sh\n:\n' > "$HOME/bin/$name"; done
    printf '#!/bin/sh\necho "$*" >> "%s/notified"\n' "$HOME" > "$HOME/bin/notify-send"
    chmod +x "$HOME/bin"/*
}

proton_run() { PATH="$HOME/bin:$PATH" PYTHONPATH="$HOME/pylib" XDG_RUNTIME_DIR="$HOME" "$REPO/home/.local/bin/proton-run" "$@"; }

# proton-run hands umu the Proton picked in rice proton: a path (Steam's Proton too), or a folder
# name in compatibilitytools.d as older rice wrote it.
test_proton_run_uses_picked_proton() {
    fake_umu
    local steam="$HOME/.local/share/Steam" conf="$HOME/.config/hypr-rice/proton.conf"
    mkdir -p "$HOME/.config/hypr-rice" "$steam/compatibilitytools.d/GE-Proton10-1" \
        "$steam/steamapps/common/Proton - Experimental"

    echo "proton=$steam/steamapps/common/Proton - Experimental" > "$conf"
    proton_run game.exe || fail "proton-run завершился с ошибкой"
    [ "$(cat "$HOME/protonpath")" = "$steam/steamapps/common/Proton - Experimental" ] \
        || fail "по пути: $(cat "$HOME/protonpath")"

    echo "proton=GE-Proton10-1" > "$conf"
    proton_run game.exe
    [ "$(cat "$HOME/protonpath")" = "$steam/compatibilitytools.d/GE-Proton10-1" ] \
        || fail "по имени: $(cat "$HOME/protonpath")"
}

# umu's output goes to the program's log; a start that fails says so (status, notification).
test_proton_run_reports_failed_start() {
    fake_umu
    printf 'INFO: umu-launcher version 1.4.4\nERROR: something broke\n' > "$HOME/umu-output"
    echo 3 > "$HOME/umu-status"
    proton_run game.exe
    [ $? -eq 3 ] || fail "код выхода не передан"
    grep -q 'something broke' "$HOME/.cache/hypr-rice/proton/game.log" || fail "вывод umu не попал в лог"
    grep -q 'game.exe не запустился' "$HOME/notified" || fail "нет уведомления о сбое"
    [ -z "$(ls "$HOME/proton-run")" ] || fail "файл состояния карточки остался"
}

# The card's percent and stage follow umu's output; a download fills its span by the bytes written.
test_proton_run_progress() {
    python3 - "$REPO/home/.local/bin/proton-run" "$HOME" <<'PY' || fail "прогресс считается не так"
import importlib.machinery, importlib.util, json, sys
from pathlib import Path
loader = importlib.machinery.SourceFileLoader("proton_run", sys.argv[1])
spec = importlib.util.spec_from_loader("proton_run", loader)
proton_run = importlib.util.module_from_spec(spec)
loader.exec_module(proton_run)
home = Path(sys.argv[2])
state_file = home / "state.json"
progress = proton_run.Progress(state_file, "game.exe")
def state():
    return json.loads(state_file.read_text())

progress.line("INFO: umu-launcher version 1.4.4")
assert state()["percent"] == 2 and state()["stage"] == "Запускаю umu", state()
progress.line("INFO: Downloading steamrt4 (4.0.1), please wait...")
part = home / "SteamLinuxRuntime_4.tar.xz.parts"
part.write_bytes(b"x" * 1000)
progress.line(f"@@download 2000 {part}")
progress.tick()
assert state()["percent"] == 25, state()  # half of the span from 5 to 45
assert state()["detail"].startswith("0 из 0 МБ"), state()
progress.line("INFO: Running 'Proton - Experimental' using runtime 'steamrt4'")
assert state()["percent"] == 85 and state()["detail"] == "", state()
progress.line("INFO: umu-launcher version 1.4.4")  # an earlier stage again: no step back
assert state()["percent"] == 85, state()
progress.line("fsync: up and running.")
assert state()["stage"] == "Wine запущен, жду окно программы", state()
progress.finish("Запущено")
assert state()["status"] == "done" and state()["percent"] == 100, state()
PY
}

# A fake $HOME with themegen and the coffee theme, edited in the settings window in every way.
user_theme_home() {
    mkdir -p "$HOME/.config/hypr/themes" "$HOME/.config/hypr-rice/waybar" "$HOME/Pictures"
    cp -r "$REPO/home/.config/hypr/scripts" "$HOME/.config/hypr/"
    cp -r "$REPO/home/.config/hypr/themes/coffee" "$REPO/home/.config/hypr/themes/night" "$HOME/.config/hypr/themes/"
    cp "$REPO/home/.config/hypr-rice/waybar/config.base.json" "$HOME/.config/hypr-rice/waybar/"
    sed -i "s|__HOME__|$HOME|g" "$HOME"/.config/hypr/themes/*/style.css  # as rice installs them
    cp "$(ls "$HOME"/.config/hypr/themes/night/*.png | head -1)" "$HOME/Pictures/mine.png"
    local off
    off=$(ls "$HOME"/.config/hypr/themes/coffee/*.png | head -1)
    cat > "$HOME/.config/hypr-rice/theme-edits.json" <<JSON
{"themes": {"coffee": {"colors": {"accent": "#123456"}, "fonts": {"font": "Iosevka", "body": "Inter"},
  "wallpapers": {"off": ["$off"], "added": ["$HOME/Pictures/mine.png"]},
  "waybar": {"modules-left": ["clock"], "modules-center": [], "modules-right": ["memory"], "position": "bottom"},
  "icons": {"memory": "X"}, "windows": {"gaps_in": 3, "animations": "off"},
  "iconTheme": "breeze-dark", "folders": "teal", "battery": "night"}}}
JSON
    echo "$off" > "$HOME/off-wallpaper"
}

# A theme made from an edited one looks the same (its edits written into its own files), lives
# where updates do not reach, and goes out and comes back as an archive.
test_user_theme_from_edited_theme() {
    user_theme_home
    python3 - "$HOME/.config/hypr/scripts" "$HOME" <<'PY' || fail "своя тема собрана не так"
import dataclasses, json, sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
from apptheme import user_themes, waybar, windows
from apptheme.theme import all_names, load
home = Path(sys.argv[2])

name = user_themes.create("Моя тема", "coffee")
assert name == "moya-tema", name
link = home / ".config/hypr/themes" / name
assert link.is_symlink() and link.resolve() == home / ".config/hypr-rice/themes" / name, link
assert name in all_names()

made, source = load(name), load("coffee")
assert made.edits == {} and made.label == "Моя тема", (made.edits, made.label)
assert made.colors == source.colors and made.colors["accent"] == "#123456"
assert made.font == "Iosevka" and made.body_font == "Inter"
assert made.ui["iconTheme"] == "breeze-dark" and made.ui["folders"] == "teal"
assert (made.dir / "battery.py").read_text() == (home / ".config/hypr/themes/night/battery.py").read_text()
names = [path.name for path in made.wallpapers]
assert "mine.png" in names and Path((home / "off-wallpaper").read_text().strip()).name not in names, names
for key in ("modules-left", "modules-right", "position"):
    assert waybar.config_for(made)[key] == waybar.config_for(dataclasses.replace(source, shared={}))[key], key
assert "X" in json.dumps(waybar.config_for(made)["memory"]), waybar.config_for(made)["memory"]
assert windows.own(made)["gaps_in"] == 3, windows.own(made)
assert "animations = { enabled = false }" in (made.dir / "hypr.lua").read_text()

style = (made.dir / "style.css").read_text()
assert f"{home}/.config/hypr/themes/moya-tema/assets/battery-0.svg" in style and "themes/coffee/" not in style, \
    "копия ссылается на картинки исходной темы"

archive = home / "moya.zip"
user_themes.export(name, archive)
import zipfile
packed = zipfile.ZipFile(archive).read("moya-tema/style.css").decode()
assert str(home) not in packed and "__HOME__/.config/hypr/themes/moya-tema/" in packed, "в архиве путь этой машины"
again = user_themes.import_archive(archive)
assert again == "moya-tema-2" and load(again).colors == made.colors, again
style = (load(again).dir / "style.css").read_text()
assert f"{home}/.config/hypr/themes/moya-tema-2/assets/" in style and "__HOME__" not in style, "пути после импорта не те"

user_themes.promote(again)
promoted = home / ".config/hypr/themes" / again
assert promoted.is_dir() and not promoted.is_symlink() and not (home / ".config/hypr-rice/themes" / again).exists()

try:
    user_themes.delete("coffee")
    raise AssertionError("тема райса удалилась")
except ValueError:
    pass
user_themes.delete(name)
assert not link.exists() and not link.is_symlink() and name not in all_names()
PY
}

# An archive that is not one theme folder, or a folder without what changetheme needs, is refused.
test_user_theme_import_refuses_bad_archives() {
    user_theme_home
    python3 - "$HOME/.config/hypr/scripts" "$HOME" <<'PY' || fail "плохой архив принят"
import shutil, sys, zipfile
from pathlib import Path
sys.path.insert(0, sys.argv[1])
from apptheme import user_themes
home = Path(sys.argv[2])
coffee = home / ".config/hypr/themes/coffee"

def archive(name, members):
    path = home / name
    with zipfile.ZipFile(path, "w") as out:
        for member, source in members:
            out.write(source, member)
    return path

def refused(path, reason):
    try:
        user_themes.import_archive(path)
    except ValueError as error:
        assert reason in str(error), (reason, error)
        return
    raise AssertionError(f"{path.name} принят")

refused(archive("escape.zip", [("../evil.txt", coffee / "palette.json")]), "за пределы")
refused(archive("two.zip", [("a/palette.json", coffee / "palette.json"), ("b/hypr.lua", coffee / "hypr.lua")]), "одна папка")
refused(archive("nolua.zip", [("t/palette.json", coffee / "palette.json"), ("t/style.css", coffee / "style.css")]), "hypr.lua")
assert not any((home / ".config/hypr-rice/themes").glob("*")), "отказанный архив оставил тему"
PY
}

# A rice theme with the name of a user theme (an update brought one) keeps its folder; the user's
# stays hidden, not overwritten.
test_user_theme_yields_to_rice_theme() {
    user_theme_home
    mkdir -p "$HOME/.config/hypr-rice/themes/coffee"
    echo '{}' > "$HOME/.config/hypr-rice/themes/coffee/palette.json"
    python3 - "$HOME/.config/hypr/scripts" <<'PY' 2>"$HOME/err" || fail "ссылка заменила тему райса"
import sys
sys.path.insert(0, sys.argv[1])
from apptheme import user_themes
from apptheme.paths import THEMES
user_themes.link()
assert not (THEMES / "coffee").is_symlink() and (THEMES / "coffee/hypr.lua").exists()
PY
    grep -q 'скрыта' "$HOME/err" || fail "нет предупреждения о совпадении имён"
}

# A theme of the rice the user removed does not come back with an update; the others do.
test_update_keeps_removed_theme_away() {
    load_rice
    mkdir -p "$HOME/.config/hypr" "$HOME/.config/hypr-rice"
    echo installed > "$HOME/.config/hypr/.rice-installed"
    echo coffee > "$HOME/.config/hypr-rice/removed-themes"
    inspect_existing_desktop >/dev/null
    copy_rice_files >/dev/null

    [ ! -e "$HOME/.config/hypr/themes/coffee" ] || fail "удалённая тема вернулась с обновлением"
    [ -f "$HOME/.config/hypr/themes/night/palette.json" ] || fail "остальные темы не скопированы"
}

# A theme of the rice is removed (not the current one) and comes back from the rice's copy of its
# repository.
test_rice_theme_removed_and_restored() {
    user_theme_home
    mkdir -p "$HOME/.local/bin"
    ln -s "$REPO/rice" "$HOME/.local/bin/rice"
    echo night > "$HOME/.config/hypr/current-theme"
    python3 - "$HOME/.config/hypr/scripts" "$HOME" <<'PY' || fail "удаление или возврат темы райса не так"
import sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
import themegen
from apptheme import removed_themes
from apptheme.theme import all_names
home = Path(sys.argv[2])

try:
    themegen.delete_theme("night")
    raise AssertionError("удалилась включённая тема")
except ValueError:
    pass
themegen.delete_theme("coffee")
assert "coffee" not in all_names() and removed_themes.names() == ["coffee"]
assert removed_themes.listing() == [{"name": "coffee", "label": "Coffee"}], removed_themes.listing()
assert "coffee" in __import__("json").loads((home / ".config/hypr-rice/theme-edits.json").read_text())["themes"], \
    "правки удалённой темы пропали"
removed_themes.restore("coffee")
assert "coffee" in all_names() and removed_themes.names() == []
PY
}

# «К заводским»: a theme of the rice loses its edits, its added wallpapers and changes made by hand in
# its folder; it is the rice's again.
test_factory_reset() {
    user_theme_home
    mkdir -p "$HOME/.local/bin" "$HOME/.local/share/hypr-rice/wallpapers/coffee"
    ln -s "$REPO/rice" "$HOME/.local/bin/rice"
    touch "$HOME/.local/share/hypr-rice/wallpapers/coffee/added.png"
    echo "-- broken by hand" >> "$HOME/.config/hypr/themes/coffee/hypr.lua"
    touch "$HOME/.config/hypr/themes/coffee/stray.png"
    python3 - "$HOME/.config/hypr/scripts" "$HOME" <<'PY' || fail "тема не вернулась к заводской"
import json, sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
from apptheme import factory_reset
from apptheme.theme import load
home = Path(sys.argv[2])
factory_reset.reset("coffee")
coffee = home / ".config/hypr/themes/coffee"
assert load("coffee").edits == {}
assert not (home / ".local/share/hypr-rice/wallpapers/coffee").exists()
assert "broken by hand" not in (coffee / "hypr.lua").read_text() and not (coffee / "stray.png").exists()
assert load("night").name == "night"
PY
}

# The games window's library: a program file's kind from its name and first bytes, Steam games without
# Steam's own tools, each game started by the right command.
test_games_library() {
    mkdir -p "$HOME/bin" "$HOME/.local/bin" "$HOME/games" "$HOME/.local/share/Steam/steamapps"
    printf 'MZ\x90\x00' > "$HOME/games/Some_Game.exe"
    printf 'MZ\x90\x00' > "$HOME/games/no-suffix-windows"
    printf '\x7fELF' > "$HOME/games/Tool.AppImage"
    printf '#!/bin/sh\n' > "$HOME/games/native-game"
    chmod +x "$HOME/games/native-game"
    echo text > "$HOME/games/readme.txt"
    printf '"AppState"\n{\n\t"appid"\t\t"%s"\n\t"name"\t\t"%s"\n}\n' 1 "Proton Experimental" \
        > "$HOME/.local/share/Steam/steamapps/appmanifest_1.acf"
    printf '"AppState"\n{\n\t"appid"\t\t"%s"\n\t"name"\t\t"%s"\n}\n' 881100 "Noita" \
        > "$HOME/.local/share/Steam/steamapps/appmanifest_881100.acf"
    printf '#!/bin/sh\necho "$0 $*" >> "%s/started"\n' "$HOME" > "$HOME/.local/bin/proton-run"
    printf '#!/bin/sh\necho "steam $*" >> "%s/started"\n' "$HOME" > "$HOME/bin/steam"
    chmod +x "$HOME/.local/bin/proton-run" "$HOME/bin/steam"
    PATH="$HOME/bin:$PATH" python3 - "$REPO/home/.config/hypr/scripts" "$HOME" <<'PY' || fail "библиотека игр не так"
import sys, time
from pathlib import Path
sys.path.insert(0, sys.argv[1])
import games
home = Path(sys.argv[2])
kinds = {name: games.add_file(home / "games" / name)["kind"]
         for name in ("Some_Game.exe", "no-suffix-windows", "Tool.AppImage", "native-game")}
assert kinds == {"Some_Game.exe": "exe", "no-suffix-windows": "exe", "Tool.AppImage": "appimage", "native-game": "native"}, kinds
try:
    games.add_file(home / "games/readme.txt")
    raise AssertionError("текстовый файл принят за игру")
except ValueError:
    pass
again = games.add_file(home / "games/Some_Game.exe")
assert len(games.games()) == 4 and again["name"] == "Some Game", (len(games.games()), again)

assert [g["name"] for g in games.steam_games()] == ["Noita"], games.steam_games()
noita = games.add({"kind": "steam", "target": "881100", "name": "Noita"})

games.launch(again["id"])
games.launch(noita["id"])
# Both start detached, so they may finish in either order and take a while on a busy machine.
started_file = home / "started"
for _ in range(50):
    if started_file.exists() and len(started_file.read_text().splitlines()) == 2:
        break
    time.sleep(0.1)
started = sorted(started_file.read_text().splitlines())
assert started == sorted([f"{home}/.local/bin/proton-run {home}/games/Some_Game.exe", "steam steam://rungameid/881100"]), started
assert games.listing()[0]["id"] in (again["id"], noita["id"]) and games.game(noita["id"])["played"] > 0

(home / "games/native-game").unlink()
native = next(g for g in games.listing() if g["kind"] == "native")
assert not native["present"]
try:
    games.launch(native["id"])
    raise AssertionError("запущена игра, которой нет")
except ValueError:
    pass
games.remove(native["id"])
assert all(g["kind"] != "native" for g in games.games())
PY
}

# A game without a cover gets one found for it: the store's cover of a game of the very same name
# (a similar name is another game), else an icon from the game's folder; looked for only once.
test_games_find_pictures() {
    mkdir -p "$HOME/games/Pinball" "$HOME/store"
    printf 'MZ' > "$HOME/games/Pinball/pinball.exe"
    printf 'PNG' > "$HOME/games/Pinball/icon.png"
    printf '\xff\xd8 a jpeg' > "$HOME/store/cover.jpg"
    echo '{"items": [{"id": 1, "name": "Balatro"}, {"id": 2, "name": "McOsu"}]}' > "$HOME/store/search.json"
    python3 - "$REPO/home/.config/hypr/scripts" "$HOME" <<'PY' || fail "картинки для игр найдены не так"
import sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
import games
home = Path(sys.argv[2])
games.STORE_SEARCH = f"file://{home}/store/search.json?{{}}"
games.STORE_COVERS = (f"file://{home}/store/missing-{{}}.jpg", f"file://{home}/store/cover.jpg?{{}}")
pinball = games.add_file(home / "games/Pinball/pinball.exe")
balatro = games.add({"kind": "app", "target": "Balatro", "name": "Balatro", "icon": "balatro"})
osu = games.add({"kind": "app", "target": "osu", "name": "osu!", "icon": "osu"})
games.find_pictures()
assert games.game(pinball["id"]).get("icon") == str(home / "games/Pinball/icon.png"), games.game(pinball["id"])
assert Path(games.game(balatro["id"])["cover"]).read_bytes().startswith(b"\xff\xd8"), games.game(balatro["id"])
assert not games.game(osu["id"]).get("cover"), "osu! получила обложку чужой игры (McOsu)"
assert all(entry.get("looked") for entry in games.games())

(home / "store/search.json").write_text('{"items": [{"id": 3, "name": "osu!"}]}')
games.find_pictures()
assert not games.game(osu["id"]).get("cover"), "поиск повторился для уже просмотренной игры"
games.uncover(balatro["id"])
assert games.game(balatro["id"])["cover"] == "" and not list((home / ".local/share/hypr-rice/game-covers").glob(balatro["id"] + ".*"))
PY
}

# rice games: what was picked is switched on, what was unpicked off, nothing else is touched.
test_games_tuning_menu() {
    load_rice
    for id in gamemode ntsync tearing zen; do
        eval "tuning_${id}_on() { echo on $id >> \"\$HOME/calls\"; touch \"\$HOME/is-$id\"; }"
        eval "tuning_${id}_off() { echo off $id >> \"\$HOME/calls\"; rm -f \"\$HOME/is-$id\"; }"
    done
    tuning_on() { [ -f "$HOME/is-$1" ]; }

    apply_game_tunings tearing gamemode >/dev/null
    apply_game_tunings gamemode >/dev/null
    [ "$(cat "$HOME/calls")" = "$(printf 'on gamemode\non tearing\noff tearing')" ] || fail "вызовы: $(cat "$HOME/calls")"
}

# Each game tuning on and off: its files, its packages, its refusals.
test_games_tunings() {
    load_rice
    GAMEMODE_MARK="$HOME/.config/hypr-rice/gamemode"
    GAMEMODE_INI="$HOME/.config/gamemode.ini"
    TEARING_LUA="$HOME/.config/hypr/games.lua"
    NTSYNC_LOAD="$HOME/etc/ntsync.conf"
    NTSYNC_RULE="$HOME/etc/60-ntsync.rules"
    mkdir -p "$HOME/etc"
    need_sudo() { :; }
    enable_multilib() { :; }
    pac() { echo "pac $*" >> "$HOME/calls"; }
    usermod() { echo "usermod $*" >> "$HOME/calls"; }
    hyprctl() { echo "hyprctl $*" >> "$HOME/calls"; }
    modprobe() { echo "modprobe $*" >> "$HOME/calls"; }
    udevadm() { :; }
    update_grub() { echo grub >> "$HOME/calls"; }
    amd_card() { echo 1; }

    tuning_tearing_on >/dev/null
    grep -q 'immediate = true' "$TEARING_LUA" && grep -q 'allow_tearing = true' "$TEARING_LUA" || fail "тиринг не записан"
    tuning_tearing_off >/dev/null
    [ ! -e "$TEARING_LUA" ] || fail "тиринг не убран"

    tuning_gamemode_on >/dev/null
    tuning_on gamemode || fail "GameMode не отмечен"
    grep -q 'pac -S --needed lib32-gamemode' "$HOME/calls" && grep -q "usermod -aG gamemode $USER" "$HOME/calls" \
        || fail "пакеты или группа: $(cat "$HOME/calls")"
    grep -q 'gpu_device=1' "$GAMEMODE_INI" || fail "нет настроек видеокарты AMD"
    tuning_gamemode_off >/dev/null
    [ ! -e "$GAMEMODE_INI" ] && ! tuning_on gamemode || fail "GameMode не выключен"
    echo "[general]" > "$GAMEMODE_INI"
    tuning_gamemode_on >/dev/null
    tuning_gamemode_off >/dev/null
    [ "$(cat "$GAMEMODE_INI")" = "[general]" ] || fail "чужой gamemode.ini перезаписан или удалён"

    tuning_ntsync_on >/dev/null
    [ "$(cat "$NTSYNC_LOAD")" = ntsync ] && grep -q uaccess "$NTSYNC_RULE" || fail "ntsync не настроен"
    tuning_ntsync_off >/dev/null
    [ ! -e "$NTSYNC_LOAD" ] && [ ! -e "$NTSYNC_RULE" ] && grep -q 'modprobe -r ntsync' "$HOME/calls" || fail "ntsync не убран"

    uname() { echo 7.2.14-zen1-1-zen; }
    tuning_zen_off >/dev/null 2>&1 && fail "удаляет загруженное ядро"
    true
}

# proton-run starts the game under gamemoderun when GameMode is on.
test_proton_run_gamemode() {
    fake_umu
    printf '#!/bin/sh\necho gamemoderun >> "%s/wrapped"\nexec "$@"\n' "$HOME" > "$HOME/bin/gamemoderun"
    chmod +x "$HOME/bin/gamemoderun"
    proton_run game.exe
    [ ! -e "$HOME/wrapped" ] || fail "gamemoderun без включённого GameMode"
    mkdir -p "$HOME/.config/hypr-rice"
    touch "$HOME/.config/hypr-rice/gamemode"
    proton_run game.exe
    [ "$(cat "$HOME/wrapped")" = gamemoderun ] || fail "игра запущена не через gamemoderun"
}

# With GameMode on, games run under gamemoderun, the Steam client never: under it Steam's browser part
# does not start (error 0x3018).
test_games_gamemode_not_for_steam() {
    mkdir -p "$HOME/bin" "$HOME/.config/hypr-rice"
    printf '#!/bin/sh\n' > "$HOME/bin/gamemoderun"
    chmod +x "$HOME/bin/gamemoderun"
    touch "$HOME/.config/hypr-rice/gamemode"
    PATH="$HOME/bin:$PATH" python3 - "$REPO/home/.config/hypr/scripts" <<'PY' || fail "gamemoderun не там"
import sys
sys.path.insert(0, sys.argv[1])
import games
assert games.command_for({"kind": "app", "target": "steam"}) == ["gtk-launch", "steam"]
assert games.command_for({"kind": "app", "target": "osu"}) == ["gamemoderun", "gtk-launch", "osu"]
assert games.command_for({"kind": "steam", "target": "881100"}) == ["steam", "steam://rungameid/881100"]
PY
}

# An animated GIF is a wallpaper like any other; what cannot play it (lock and login screens,
# browsers) gets its first frame from .stills/, which a copy of the theme leaves out.
test_gif_wallpaper() {
    user_theme_home
    python3 - "$HOME/.config/hypr/scripts" "$HOME" <<'PY' || fail "GIF-обои не так"
import sys
from pathlib import Path
from PIL import Image
sys.path.insert(0, sys.argv[1])
from apptheme import bake, wallpaper_still
from apptheme.theme import load
home = Path(sys.argv[2])
coffee = home / ".config/hypr/themes/coffee"
frames = [Image.new("RGB", (8, 8), color) for color in ((200, 0, 0), (0, 0, 200))]
frames[0].save(coffee / "zz-animated.gif", save_all=True, append_images=frames[1:], duration=100, loop=0)

assert coffee / "zz-animated.gif" in load("coffee").own_wallpapers
still = Path(wallpaper_still.still(coffee / "zz-animated.gif"))
assert still == coffee / ".stills/zz-animated.png", still
assert Image.open(still).convert("RGB").getpixel((0, 0)) == (200, 0, 0), "кадр не первый"
plain = next(p for p in load("coffee").own_wallpapers if p.suffix == ".png")
assert wallpaper_still.still(plain) == str(plain)

bake.copy_theme(coffee, home / "copy")
assert (home / "copy/zz-animated.gif").exists() and not (home / "copy/.stills").exists()
PY
}

# A cursor theme from a file: an archive (refused when it reaches out of itself or carries no cursor),
# or an osu! skin; added ones can go again, the rice's WhiteCat cannot.
test_cursor_from_file() {
    mkdir -p "$HOME/pack/Neon/cursors" "$HOME/.config/hypr/scripts" "$HOME/skin"
    cp -r "$REPO/home/.config/hypr/scripts/." "$HOME/.config/hypr/scripts/"
    printf 'Xcur' > "$HOME/pack/Neon/cursors/left_ptr"
    printf '[Icon Theme]\nName=Neon\n' > "$HOME/pack/Neon/index.theme"
    tar -czf "$HOME/neon.tar.gz" -C "$HOME/pack" Neon
    python3 - "$HOME/.config/hypr/scripts" "$HOME" <<'PY' || fail "курсор из файла не так"
import sys, tarfile, zipfile
from pathlib import Path
from PIL import Image
sys.path.insert(0, sys.argv[1])
from apptheme import cursor_install
home = Path(sys.argv[2])
icons = home / ".local/share/icons"

assert cursor_install.install(home / "neon.tar.gz") == ["Neon"] and (icons / "Neon/cursors/left_ptr").exists()
try:
    cursor_install.install(home / "neon.tar.gz")
    raise AssertionError("курсор установлен поверх того же")
except ValueError:
    pass

with zipfile.ZipFile(home / "evil.zip", "w") as out:
    out.writestr("../evil/cursors/left_ptr", "x")
with zipfile.ZipFile(home / "empty.zip", "w") as out:
    out.writestr("Thing/readme.txt", "x")
for bad, reason in (("evil.zip", "за его пределы"), ("empty.zip", "нет темы курсора")):
    try:
        cursor_install.install(home / bad)
        raise AssertionError(f"{bad} принят")
    except ValueError as error:
        assert reason in str(error), error

Image.new("RGBA", (64, 64), (255, 255, 0, 255)).save(home / "skin/cursor@2x.png")
with zipfile.ZipFile(home / "My Skin.osk", "w") as out:
    out.write(home / "skin/cursor@2x.png", "cursor@2x.png")
assert cursor_install.install(home / "My Skin.osk") == ["My Skin"] and (icons / "My Skin/cursors/left_ptr").exists()

cursor_install.remove("Neon")
assert not (icons / "Neon").exists()
(icons / "WhiteCat/cursors").mkdir(parents=True)
try:
    cursor_install.remove("WhiteCat")
    raise AssertionError("удалён курсор райса")
except ValueError:
    pass
PY
}

# A wallpaper from a moment of a GIF (by frame) or a video (by second, when ffmpeg is there).
test_wallpaper_frames() {
    python3 - "$REPO/home/.config/hypr/scripts" "$HOME" <<'PY' || fail "кадр вынут не так"
import shutil, subprocess, sys
from pathlib import Path
from PIL import Image
sys.path.insert(0, sys.argv[1])
from apptheme import frames
home = Path(sys.argv[2])
pictures = [Image.new("RGB", (40, 20), color) for color in ((200, 0, 0), (0, 200, 0), (0, 0, 200))]
pictures[0].save(home / "a.gif", save_all=True, append_images=pictures[1:], duration=100)
assert frames.length(home / "a.gif") == {"kind": "gif", "frames": 3}
frames.frame(home / "a.gif", 1, home / "frame.png")
assert Image.open(home / "frame.png").convert("RGB").getpixel((5, 5))[1] > 150, "не второй кадр"
frames.frame(home / "a.gif", 2, home / "small.png", 20)
assert Image.open(home / "small.png").size == (20, 10)
if shutil.which("ffmpeg"):
    subprocess.run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i", "color=c=blue:s=64x36:d=2", str(home / "v.mp4")], check=True)
    assert 1.5 < frames.length(home / "v.mp4")["seconds"] < 2.5
    frames.frame(home / "v.mp4", 1.0, home / "v.png")
    assert Image.open(home / "v.png").size == (64, 36)
try:
    frames.length(home / "frame.png")
    raise AssertionError("кадр из картинки")
except ValueError:
    pass
PY
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
