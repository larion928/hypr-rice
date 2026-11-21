# hook:earlyoom — when memory runs out, browser tabs go first and the desktop and games are spared.

EARLYOOM_CONF=/etc/default/earlyoom

hook_earlyoom() {
    # The package's own file is replaced; one the user changed (pacman: [modified]) and not ours stays.
    if ! rice_owns "$EARLYOOM_CONF" && pacman -Qii earlyoom 2>/dev/null | grep -q "$EARLYOOM_CONF \[modified\]"; then
        info "earlyoom: свой $EARLYOOM_CONF оставлен как есть"
    else
        # Thresholds are earlyoom's own shares (10% of RAM and of swap). What it should spare (the
        # desktop, Steam, games, Windows ones through Proton too) and what to close first (browser tabs).
        # systemd splits $EARLYOOM_ARGS at spaces: no space inside a pattern ("Web.Content", not "Web Content").
        printf '%s\n' "$RICE_MARK (rice → программы → earlyoom)." \
            "EARLYOOM_ARGS=\"-r 3600 -n --avoid '(^|/)(init|systemd.*|Xwayland|Hyprland|sshd|pipewire.*|wireplumber|waybar|quickshell|qs|steam|steamwebhelper|gamescope|.*\\.exe|RimWorld.*)\$' --prefer '(^|/)(chrome|chromium|firefox|zen|Web.Content|Isolated.Web.Co)\$'\"" \
            | sudo_write "$EARLYOOM_CONF" || return 1
    fi
    sudo systemctl enable earlyoom.service >/dev/null 2>&1 || return 1
    sudo systemctl restart earlyoom.service && ok "earlyoom: при нехватке памяти первыми закрывает вкладки браузера"
}

unhook_earlyoom() {
    sudo systemctl disable --now earlyoom.service >/dev/null 2>&1 || true
}
