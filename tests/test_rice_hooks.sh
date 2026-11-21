# rice: the programs' setup steps (lib/hooks/): what each changes and takes back.

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

# zram: the size is a formula zram-generator works out on each machine (half the RAM, at most 8 GiB);
# a zram swap in use is not rebuilt; the user's own config is left alone; only the rice's files go.
test_zram_hook() {
    load_rice
    mkdir -p "$HOME/etc"
    ZRAM_CONF="$HOME/etc/zram-generator.conf"
    ZRAM_SYSCTL="$HOME/etc/99-hypr-rice-zram.conf"
    sysctl() { :; }
    systemctl() { echo "systemctl $*" >> "$HOME/calls"; }
    swapon() { cat "$HOME/swaps" 2>/dev/null; }

    hook_zram >/dev/null
    grep -qx 'zram-size = min(ram / 2, 8192)' "$ZRAM_CONF" || fail "размер zram не формулой: $(cat "$ZRAM_CONF")"
    grep -qx 'vm.swappiness = 180' "$ZRAM_SYSCTL" || fail "нет настроек ядра"
    grep -q 'start systemd-zram-setup@zram0' "$HOME/calls" || fail "zram не включён"

    : > "$HOME/calls"
    echo /dev/zram0 > "$HOME/swaps"
    hook_zram >/dev/null
    ! grep -q 'start systemd-zram-setup' "$HOME/calls" || fail "работающий zram пересоздан на лету"

    unhook_zram >/dev/null
    [ ! -e "$ZRAM_CONF" ] && [ ! -e "$ZRAM_SYSCTL" ] || fail "файлы райса не убраны"
    printf '[zram0]\nzram-size = ram\n' > "$ZRAM_CONF"
    hook_zram >/dev/null
    unhook_zram >/dev/null
    [ "$(cat "$ZRAM_CONF")" = "$(printf '[zram0]\nzram-size = ram')" ] || fail "свой конфиг zram перезаписан или удалён"
}

# earlyoom: its arguments as systemd hands them over compile (a real earlyoom, dry run); the user's own
# changed file is left alone.
test_earlyoom_hook() {
    load_rice
    mkdir -p "$HOME/etc"
    EARLYOOM_CONF="$HOME/etc/earlyoom"
    systemctl() { :; }
    pacman() { echo "$EARLYOOM_CONF ${PACMAN_STATE:-}"; }

    hook_earlyoom >/dev/null
    grep -q "^$RICE_MARK" "$EARLYOOM_CONF" || fail "конфиг earlyoom не записан"
    if command -v earlyoom >/dev/null; then
        python3 - "$EARLYOOM_CONF" > "$HOME/args" <<'PY'
import shlex, sys
line = next(l for l in open(sys.argv[1]) if l.startswith("EARLYOOM_ARGS="))
print("\n".join(shlex.split(shlex.split(line.split("=", 1)[1])[0])))
PY
        mapfile -t args < "$HOME/args"
        timeout 1 earlyoom --dryrun "${args[@]}" > "$HOME/out" 2>&1
        [ $? -eq 124 ] || fail "earlyoom не принял аргументы: $(tail -3 "$HOME/out")"
    fi

    echo 'EARLYOOM_ARGS="-m 3"' > "$EARLYOOM_CONF"
    PACMAN_STATE="[modified]" hook_earlyoom >/dev/null
    [ "$(cat "$EARLYOOM_CONF")" = 'EARLYOOM_ARGS="-m 3"' ] || fail "свой конфиг earlyoom перезаписан"
}

# A fake Igareck AntiDPI release VERSION in $HOME/release: the archive, its SHA-256 list and an
# installer that only notes how it was called and leaves an installation behind.
fake_antidpi_release() {
    local version=$1 name="Igareck_AntiDPI_CLI_v$1_Linux_x64"
    mkdir -p "$HOME/build/$name/app" "$HOME/release"
    cat > "$HOME/build/$name/app/install.py" <<PY
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
prefix = Path(args[args.index("--prefix") + 1])
with open(os.environ["HOME"] + "/installer-calls", "a") as log:
    log.write(" ".join(args) + (" tty" if sys.stdin.isatty() else " no-tty") + "\n")
prefix.mkdir(parents=True)
(prefix / "installation.json").write_text(json.dumps({"version": "$version"}))
(prefix / "remove_installation.py").write_text(
    "import os, shutil, sys\n"
    "open(os.environ['HOME'] + '/installer-calls', 'a').write('remove ' + ' '.join(sys.argv[1:]) + '\\\\n')\n"
    "shutil.rmtree(os.path.dirname(os.path.abspath(__file__)))\n")
PY
    tar -czf "$HOME/release/$name.tar.gz" -C "$HOME/build" "$name"
    (cd "$HOME/release" && sha256sum "$name.tar.gz" > "SHA256SUMS_Linux_v$version.txt")
}

# Igareck AntiDPI from the rice: installed without questions, the version pinned in rice and the archive
# checked against the SHA-256 pinned with it (the release's own list would vouch for a replaced release);
# the same version not again, a new one in place of the old; installed only while its folder is there;
# removing it leaves the packages it needed.
test_antidpi_hook() {
    load_rice
    systemctl() { return 1; }
    curl() {
        local out="" url="${*: -1}"
        while [ $# -gt 1 ]; do [ "$1" = -o ] && out=$2; shift; done
        cp "$HOME/release/$(basename "$url")" "$out"
    }
    pin() {  # pin VERSION: the rice pins that fake release
        ANTIDPI_VERSION=$1
        ANTIDPI_SHA256=$(sha256sum < "$HOME/release/Igareck_AntiDPI_CLI_v$1_Linux_x64.tar.gz" | cut -d' ' -f1)
    }
    fake_antidpi_release 1.1
    pin 1.1

    hook_antidpi >/dev/null || fail "не поставилось"
    grep -qx -- "install --prefix $ANTIDPI_PREFIX --engine compatible --shortcuts no --global-command yes --skip-deps --no-launch no-tty" \
        "$HOME/installer-calls" || fail "установщик вызван не так: $(cat "$HOME/installer-calls")"
    [ -f "$ANTIDPI_DESKTOP" ] || fail "нет пункта в лаунчере"

    hook_antidpi >/dev/null
    [ "$(grep -c '^install' "$HOME/installer-calls")" = 1 ] || fail "та же версия поставлена ещё раз"

    fake_antidpi_release 1.2
    pin 1.2
    hook_antidpi >/dev/null || fail "новая версия не встала"
    grep -qx 'remove --purge --yes' "$HOME/installer-calls" && [ "$(antidpi_installed)" = 1.2 ] \
        || fail "старая версия не заменена: $(cat "$HOME/installer-calls")"

    fake_antidpi_release 1.3
    ANTIDPI_VERSION=1.3  # the release's own list matches, the rice's pinned checksum (of 1.2) does not
    hook_antidpi >/dev/null 2>&1 && fail "поставлено с несовпавшей суммой"
    [ "$(antidpi_installed)" = 1.2 ] || fail "после отказа сломана прежняя установка"

    is_installed() { return 0; }  # every package it needs is there
    APP_SRC[antidpi]="dep:base-devel dep:curl path:$ANTIDPI_PREFIX hook:antidpi"
    app_packages_installed antidpi || fail "установленный не считается установленным"
    unhook_antidpi >/dev/null
    ! app_packages_installed antidpi || fail "без папки считается установленным"
    pacman() { [ "$1" = -Qq ] && return 0; echo "pacman $*" >> "$HOME/calls"; }
    remove_apps antidpi >/dev/null 2>&1
    ! grep -q 'base-devel\|curl' "$HOME/calls" 2>/dev/null || fail "удаление программы снесло её зависимости"
}

# A setup step that fails midway stops there and is reported (hook || warn ignores set -e inside it).
test_failed_step_stops() {
    load_rice
    ZRAM_CONF="$HOME/missing/zram-generator.conf"  # its folder is not there: tee fails
    NTSYNC_LOAD="$HOME/missing/ntsync.conf"
    sysctl() { echo sysctl >> "$HOME/calls"; }
    systemctl() { echo "systemctl $*" >> "$HOME/calls"; }
    udevadm() { echo udevadm >> "$HOME/calls"; }
    modprobe() { echo modprobe >> "$HOME/calls"; }
    swapon() { :; }
    run_hook zram >/dev/null 2>&1
    apply_game_tunings ntsync >/dev/null 2>&1
    [ ! -e "$HOME/calls" ] || fail "после неудачного шага выполнились следующие: $(cat "$HOME/calls")"
    printf '%s\n' "${WARNINGS[@]}" | grep -q 'не отработал шаг zram' || fail "о zram не предупреждено"
    printf '%s\n' "${WARNINGS[@]}" | grep -q 'не включилось: NTSync' || fail "о NTSync не предупреждено"
}

# Syncthing runs as the user's own service while it is installed.
test_syncthing_hook() {
    load_rice
    systemctl() { echo "systemctl $*" >> "$HOME/calls"; }
    run_hook syncthing >/dev/null
    run_unhook syncthing
    [ "$(cat "$HOME/calls")" = "$(printf 'systemctl --user enable --now syncthing.service\nsystemctl --user disable --now syncthing.service')" ] \
        || fail "вызовы: $(cat "$HOME/calls")"
}
