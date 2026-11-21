# rice: pacman with retries and fallback mirrors, the repos it adds, its own packages.

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

# A repository the rice adds is synced together with a system upgrade: Arch does not support
# installing from databases fresher than the system (a partial upgrade).
test_repos_synced_with_upgrade() {
    load_rice
    pac() { echo "pac $*" >> "$HOME/calls"; }
    curl() { return 0; }
    pacman-key() { return 0; }
    mkdir -p "$(dirname "$PACMAN_CONF")"
    printf '#[multilib]\n#Include = /etc/pacman.d/mirrorlist\n' > "$PACMAN_CONF"
    enable_multilib >/dev/null
    grep -qx '\[multilib\]' "$PACMAN_CONF" || fail "multilib не включён"
    setup_pkg_repo >/dev/null
    grep -qx '\[hypr-rice\]' "$PACMAN_CONF" || fail "репозиторий hypr-rice не подключён"
    [ "$(cat "$HOME/calls")" = "$(printf 'pac -Syu\npac -Syu')" ] || fail "синхронизация: $(cat "$HOME/calls")"
    ! grep -rnE '(pac|pacman) [^#]*-Sy( |$)' "$REPO/rice" "$REPO/lib" "$REPO/install.sh" || fail "синхронизация без обновления"
}
