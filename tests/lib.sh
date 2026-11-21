# What every test file uses: the sandbox each test runs in, and the rice's functions with the system stubbed out.

fail() { echo "      $*"; exit 1; }  # ends the test: each one runs in its own subshell

# Runs one test function in a subshell with HOME pointing at a fresh directory.
run_test() {
    local name=$1 sandbox
    sandbox=$(mktemp -d)
    # Cut off from the live session too: a stub that is missing (or a child that outlives the test and its
    # stubs) would otherwise reach the real D-Bus session, Hyprland and the runtime dir's sockets and locks.
    mkdir -m 700 "$sandbox/run"
    if (export HOME="$sandbox/home" XDG_RUNTIME_DIR="$sandbox/run" DBUS_SESSION_BUS_ADDRESS=disabled:
        unset HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY DISPLAY
        mkdir -p "$HOME"; cd "$sandbox" && "$name") >"$sandbox/out" 2>&1; then
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
    # The files rice keeps outside ~ go under $HOME/root, and sudo refuses the real system folders:
    # sudo is only a pass-through here, a test that reached /etc would change this machine.
    local root="$HOME/root"
    PACMAN_CONF="$root/etc/pacman.conf"
    MIRRORLIST="$root/etc/pacman.d/mirrorlist"
    SDDM_CONF="$root/etc/sddm.conf"
    SDDM_CONF_D="$root/etc/sddm.conf.d"
    THEME_ROOT="$root/usr/local/bin/hypr-theme-root"
    SUDOERS_RULE="$root/etc/sudoers.d/hypr-theme"
    TMPFILES_D="$root/etc/tmpfiles.d"
    CACHE_TRIM="$root/usr/local/bin/rice-cache-trim"
    CACHE_TRIM_HOOK="$root/etc/pacman.d/hooks/rice-cache-trim.hook"
    ZRAM_CONF="$root/etc/systemd/zram-generator.conf"
    ZRAM_SYSCTL="$root/etc/sysctl.d/99-hypr-rice-zram.conf"
    EARLYOOM_CONF="$root/etc/default/earlyoom"
    PROTON_BINFMT="$root/etc/binfmt.d/proton-run.conf"
    PROTON_BINFMT_RULE="$root/proc/sys/fs/binfmt_misc/proton-run"
    NTSYNC_LOAD="$root/etc/modules-load.d/ntsync.conf"
    NTSYNC_RULE="$root/etc/udev/rules.d/60-ntsync.rules"
    ANTIDPI_PREFIX="$root/opt/igareck-antidpi"
    sudo() {
        local arg
        for arg in "$@"; do
            case "$arg" in
                /etc/*|/usr/*|/var/*|/opt/*|/boot/*|/proc/*|/sys/*)
                    echo "тест дошёл до системного файла: sudo $*" >&2
                    return 1 ;;
            esac
        done
        "$@"
    }
    need_sudo() { :; }
    systemctl() { :; }
    pacman() { return 1; }
    flatpak() { return 1; }
    xdg-user-dirs-update() { :; }
    export RICE_ASSUME=y RICE_MODE=replace
}

# Runs CODE after load_rice in a bash of its own, with set -e in force as when rice runs: the tests
# themselves run inside `if`, where bash ignores set -e, even in a subshell that sets it again.
strict_rice() {  # strict_rice CODE
    REPO=$REPO bash -c "$(declare -f load_rice); load_rice; set -e; $1"
}
