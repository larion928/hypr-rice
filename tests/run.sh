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
