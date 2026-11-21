# When something is wrong: rice repair puts the rice's packages, settings and features back, rice report writes
# what a helper needs to know; rice doctor (python, doctor/) checks and cures.

cmd_repair() {
    need_sudo
    step "Починка"
    local base=() aur=()
    mapfile -t base < <(list "$SRC/packages/base.txt")
    mapfile -t aur < <(list "$SRC/packages/aur.txt")
    pac -S --needed "${base[@]}" >/dev/null || warn "не все основные пакеты встали"
    pkg_repo_enabled || setup_pkg_repo
    aur_install "${aur[@]}" || true
    mark_rice_packages_explicit
    load_install_mode
    setup_system
    setup_maintenance
    setup_features
    apply_theme "$(current_theme)"
    finish
}

cmd_report() {
    local out="$HOME/rice-report.txt"
    # Every section is written whatever fails before it: a broken system is what the report is for,
    # and under set -e the first missing file or stopped service would end it there.
    (
        set +e
        echo "hypr-rice report $(date '+%F %T')"
        echo "rice: $(cat "$MARKER" 2>/dev/null || echo 'не установлен')  src: $(git -C "$SRC" log -1 --format='%h %s' 2>/dev/null)"
        echo "os: $(. /etc/os-release; echo "$PRETTY_NAME")  kernel: $(uname -r)"
        echo "gpu: $(for v in /sys/class/drm/card*/device/vendor; do cat "$v"; done 2>/dev/null | sort -u | tr '\n' ' ')"
        echo
        echo "== display manager"
        readlink -f /etc/systemd/system/display-manager.service 2>&1
        systemctl is-enabled sddm 2>&1; systemctl is-active sddm 2>&1
        cat /etc/sddm.conf.d/*.conf 2>/dev/null
        echo
        echo "== sddm log"
        journalctl -b -u sddm --no-pager 2>/dev/null | tail -n 40
        echo
        echo "== sessions"
        ls /usr/share/wayland-sessions /usr/share/xsessions 2>/dev/null
        echo
        echo "== missing rice packages"
        local p
        for p in $(list "$SRC/packages/base.txt") $(list "$SRC/packages/aur.txt"); do
            pacman -Qq "$p" >/dev/null 2>&1 || echo "  $p"
        done
        echo
        echo "== network"
        for u in https://github.com https://aur.archlinux.org "$PKG_REPO_URL/hypr-rice.db" https://geo.mirror.pkgbuild.com; do
            printf '  %-70s %s\n' "$u" "$(curl -fsSIL -o /dev/null -w '%{http_code}' --max-time 10 "$u" 2>&1 || echo FAIL)"
        done
        echo
        echo "== hyprland"
        hyprctl version 2>/dev/null | head -n 2 || echo "  не запущен"  # pipefail: the pipe fails when hyprctl does
        hyprctl configerrors 2>/dev/null
        echo
        echo "== user services"
        systemctl --user --no-pager --failed 2>/dev/null | head -n 20
        echo
        echo "== pacman.conf repos"
        grep -E '^\[' "$PACMAN_CONF"
    ) > "$out" 2>&1 || true
    ok "отчёт: $out (пришли его тому, кто помогает)"
}

cmd_mouse_test() {  # the user moves the mouse along a ruler and answers questions: a terminal is needed
    have_tty || die "rice mouse-test нужен терминал"
    exec python3 "$HOME/.config/hypr/scripts/mouse_test.py"
}

cmd_doctor() {  # the doctor is python, in the repo next to lib/ (doctor/)
    PYTHONPATH="$SRC${PYTHONPATH:+:$PYTHONPATH}" exec python3 -m doctor "$@"
}
