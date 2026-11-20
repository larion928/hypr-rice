#!/usr/bin/env bash
# Measures what feels slow in the live session, in milliseconds. Unlike run.sh it uses the real $HOME and
# the real Hyprland, so it is run by hand and only inside a Hyprland session.
#   tests/bench.sh [menus|theme|all]     (default: all)
#
# menus  Opens each menu BENCH_RUNS times (default 3) and times it from the launcher's start until the
#        panel's layer surface (the WlrLayershell.namespace in its shell.qml) shows up in `hyprctl layers`;
#        then closes it. "before quickshell" is the part of that spent in the launcher script itself
#        (theme-list.py, jq, hyprctl binds), read off its xtrace up to `exec quickshell`.
#        The launchers keep their usual side files (theme-list.json, help-binds.json in $XDG_RUNTIME_DIR).
# theme  Re-applies the current theme with `changetheme --keep-wallpaper`, so the screen flickers like a
#        theme switch, and shows where the time goes: per command of changetheme (from its xtrace), the
#        slowest imports of themegen, and per-step time of themegen.apply (cProfile).
#        Waybar and histuid are restarted and the wallpaper is kept; the config files get the same content.
set -uo pipefail

source "$HOME/.config/quickshell/panel.sh"  # panel_is_open, close_panel

BIN=$HOME/.local/bin
THEMEGEN_DIR=$HOME/.config/hypr/scripts
WORK=$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/bench.XXXXXX")
OPEN_PANEL=  # a panel this script opened and has not yet closed

cleanup() {
    [ -z "$OPEN_PANEL" ] || close_panel "$OPEN_PANEL"
    rm -rf "$WORK"
}
trap cleanup EXIT

# Microseconds since the epoch: bash has no sub-second clock but $EPOCHREALTIME, whose separator follows the locale.
now_us() {
    local now=$EPOCHREALTIME
    echo $(( ${now//[.,]/} ))
}

to_ms() { echo $(( ($1 + 500) / 1000 )); }

median() {
    local sorted
    mapfile -t sorted < <(printf '%s\n' "$@" | sort -n)
    echo "${sorted[${#sorted[@]} / 2]}"
}

maximum() { printf '%s\n' "$@" | sort -n | tail -n 1; }

# Calls the command until it succeeds; gives up after 10 s.
wait_until() {
    local deadline=$(( $(now_us) + 10000000 ))
    until "$@"; do
        [ "$(now_us)" -lt "$deadline" ] || return 1
        sleep 0.005
    done
}

layer_is_mapped() {
    hyprctl layers -j | jq -e --arg namespace "$1" 'any(.. | objects; .namespace? == $namespace)' >/dev/null
}

process_gone() { ! kill -0 "$1" 2>/dev/null; }

# --- menus ---

# One open-and-close of a menu. Sets BEFORE_QUICKSHELL_US and MAPPED_US (both from the launcher's start;
# BEFORE_QUICKSHELL_US is "-" when the trace has no `exec quickshell`). Fails when the window never showed up.
# Not run in a subshell, so the EXIT trap sees OPEN_PANEL.
open_and_close_once() {
    local script=$1 panel=$2 namespace=$3 trace=$WORK/trace
    local start mapped pid exec_line shown=1

    start=$(now_us)
    PS4='+${EPOCHREALTIME} ' bash -x "$BIN/$script" >/dev/null 2>"$trace" </dev/null &
    pid=$!
    OPEN_PANEL=$panel
    wait_until layer_is_mapped "$namespace" || { echo "$script: окно не появилось за 10 с" >&2; shown=0; }
    mapped=$(now_us)

    close_panel "$panel"
    wait_until process_gone "$pid" || { echo "$script: процесс не завершился за 10 с" >&2; kill "$pid"; }
    wait "$pid" 2>/dev/null
    OPEN_PANEL=

    BEFORE_QUICKSHELL_US=-
    exec_line=$(grep -m1 '^+[0-9.,]* exec quickshell' "$trace")
    if [ -n "$exec_line" ]; then
        exec_line=${exec_line%% *}
        exec_line=${exec_line#+}
        BEFORE_QUICKSHELL_US=$(( ${exec_line//[.,]/} - start ))
    fi
    MAPPED_US=$(( mapped - start ))
    [ "$shown" = 1 ]
}

# The panel's name is the one the launcher script toggles, its namespace the one its shell.qml sets.
bench_menu() {
    local script=$1 panel namespace
    local befores=() mappeds=()

    panel=$(sed -n 's/^if panel_is_open \([a-z]*\);.*/\1/p' "$BIN/$script")
    namespace=$(grep -m1 -o 'WlrLayershell.namespace: "[^"]*"' "$(panel_conf "$panel")/shell.qml" | cut -d'"' -f2)
    if [ -z "$panel" ] || [ -z "$namespace" ]; then
        echo "$script: не нашёл имя панели или namespace, пропускаю" >&2
        return
    fi
    if panel_is_open "$panel"; then
        echo "$script: панель уже открыта, закройте её и повторите" >&2
        return
    fi

    for _ in $(seq "${BENCH_RUNS:-3}"); do
        open_and_close_once "$script" "$panel" "$namespace" || continue
        befores+=("$BEFORE_QUICKSHELL_US")
        mappeds+=("$MAPPED_US")
    done
    if [ ${#mappeds[@]} -eq 0 ]; then
        printf '%-16s %-14s %s\n' "$script" "$namespace" "окно ни разу не появилось"
        return
    fi

    local before_median=-
    [ "${befores[0]}" = - ] || before_median=$(to_ms "$(median "${befores[@]}")")
    printf '%-16s %-14s %12s %14s %12s\n' "$script" "$namespace" "$before_median" \
        "$(to_ms "$(median "${mappeds[@]}")")" "$(to_ms "$(maximum "${mappeds[@]}")")"
}

bench_menus() {
    local script
    echo "Меню: ${BENCH_RUNS:-3} запусков каждого, мс до появления окна"
    printf '%-16s %-14s %12s %14s %12s\n' menu namespace "до quickshell" "до окна (med)" "до окна (max)"
    for script in launcher settings-panel theme-picker help-panel power-menu notif-panel network-panel games shots-gallery; do
        bench_menu "$script"
    done
}

# --- theme ---

# Prints the xtrace of a script as "<ms> <command>", the time being up to the next traced command of any level:
# bash traces `x=$(cmd)` only after cmd ran, so a command inside a substitution has to end the previous one.
# Commands inside a substitution are marked with one more "+". Commands under 10 ms are left out.
# The arguments are the trace file and the end of the run (microseconds).
print_command_costs() {
    local trace=$1 end_us=$2
    awk -v end_us="$end_us" '
        function flush(now) {
            if (previous != "" && (now - started) >= 10000) {
                printf "%6d  %s\n", (now - started + 500) / 1000, substr(previous, 1, 100)
            }
        }
        /^\++[0-9]+[.,][0-9]+ / {
            stamp = $1; sub(/^\++/, "", stamp); gsub(/[.,]/, "", stamp)
            flush(stamp)
            started = stamp
            previous = $0; sub(/^[^ ]+ /, "", previous)
            nesting = $1; sub(/[0-9.,]+$/, "", nesting)
            previous = nesting " " previous
        }
        END { flush(end_us) }
    ' "$trace"
}

time_changetheme() {
    local theme=$1 trace=$WORK/changetheme-trace start end
    start=$(now_us)
    PS4='+${EPOCHREALTIME} ' bash -x "$BIN/changetheme" "$theme" --keep-wallpaper >/dev/null 2>"$trace"
    end=$(now_us)

    echo "changetheme $theme --keep-wallpaper: команды дольше 10 мс, мс"
    print_command_costs "$trace" "$end"
    printf '%6d  всего (фоновые waybar-start и themegen offer не входят)\n' "$(to_ms $(( end - start )))"
}

slowest_imports() {
    echo "import themegen: 10 самых дорогих импортов, мс (собственное время, вместе с вложенными)"
    python3 -X importtime -c 'import sys; sys.path.insert(0, sys.argv[1]); import themegen' "$THEMEGEN_DIR" 2>&1 >/dev/null \
        | awk -F'|' '
            /^import time:/ && $2 ~ /[0-9]/ {
                self = $1; sub(/import time: */, "", self)
                name = $3; sub(/^ */, "", name)
                printf "%d %d %s\n", self, $2, name
            }' \
        | sort -rn | head -n 10 \
        | awk '{ printf "%8.1f %8.1f  %s\n", $1 / 1000, $2 / 1000, $3 }'
}

# What changetheme does in its step 2, once, under cProfile.
profile_apply() {
    local theme=$1 wallpaper
    wallpaper=$(cat "$HOME/.config/hypr/current-wallpaper" 2>/dev/null)

    echo "themegen.apply: шаги, мс (включая ожидание внешних программ)"
    python3 - "$THEMEGEN_DIR" "$theme" "$wallpaper" <<'PY'
import cProfile, pstats, sys
from pathlib import Path

themegen_dir, theme, wallpaper = sys.argv[1:4]
sys.path.insert(0, themegen_dir)
import themegen

profile = cProfile.Profile()
profile.runcall(themegen.apply, theme, wallpaper or None)

steps = []
for (path, _, function), (_, _, _, _, callers) in pstats.Stats(profile).stats.items():
    if "apptheme" not in Path(path).parts:
        continue
    for (caller_path, _, caller_function), (_, _, _, time_from_caller) in callers.items():
        if Path(caller_path).name == "themegen.py" and caller_function in ("apply", "run_each"):
            steps.append((time_from_caller, f"{Path(path).stem}.{function}"))

for seconds, step in sorted(steps, reverse=True):
    print(f"{seconds * 1000:8.1f}  {step}")
PY
}

bench_theme() {
    local theme
    theme=$(cat "$HOME/.config/hypr/current-theme")
    time_changetheme "$theme"
    echo
    slowest_imports
    echo
    profile_apply "$theme"
}

# --- main ---

if [ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    echo "Ошибка: bench.sh работает только внутри сессии Hyprland (нет HYPRLAND_INSTANCE_SIGNATURE)" >&2
    exit 1
fi

case "${1:-all}" in
    menus) bench_menus ;;
    theme) bench_theme ;;
    all) bench_menus; echo; bench_theme ;;
    *) echo "Использование: tests/bench.sh [menus|theme|all]" >&2; exit 1 ;;
esac
