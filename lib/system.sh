# The rice outside ~: SDDM, the root helper and its sudoers rule, services, GTK settings, upkeep timers,
# app settings; and their teardown for uninstall.

SDDM_CONF=/etc/sddm.conf
SDDM_CONF_D=/etc/sddm.conf.d
DISPLAY_MANAGER_UNIT=/etc/systemd/system/display-manager.service

display_manager() {  # the login screen enabled now (sddm, gdm, ...), whichever it is; empty when none is
    # readlink -f of a missing link prints the link's own path, which is no login screen.
    [ -e "$DISPLAY_MANAGER_UNIT" ] || return 0
    basename "$(readlink -f "$DISPLAY_MANAGER_UNIT")" .service
}

setup_sddm() {
    local cur
    if [ "$MODE" = coexist ] && [ "$USE_SDDM" = 0 ]; then
        info "экран входа оставлен свой; Hyprland появится в его списке сеансов"
        return 0
    fi
    cur=$(display_manager)
    if [ -n "$cur" ] && [ "$cur" != sddm ]; then
        sudo systemctl disable "$cur.service" >/dev/null 2>&1 || true
        info "выключен экран входа $cur"
    fi
    sudo systemctl enable --force sddm.service >/dev/null 2>&1 || warn "не включился sddm"

    sudo rm -f "$SDDM_CONF_D/10-theme.conf"
    sudo install -Dm644 "$SRC/system/sddm-theme.conf" "$SDDM_CONF_D/99-hypr-rice.conf"
    # /etc/sddm.conf is read after sddm.conf.d and would override our theme.
    if [ -f "$SDDM_CONF" ] && grep -qE '^\s*Current\s*=' "$SDDM_CONF"; then
        sudo cp -n "$SDDM_CONF" "$SDDM_CONF.rice-backup"
        sudo sed -i -E 's/^(\s*Current\s*=)/# hypr-rice: \1/' "$SDDM_CONF"
        info "тема из $SDDM_CONF отключена (копия: sddm.conf.rice-backup)"
    fi
    # Autologin straight into another desktop would skip the login screen entirely.
    local f s
    for f in "$SDDM_CONF" "$SDDM_CONF_D"/*.conf; do
        [ -f "$f" ] || continue
        s=$(sed -n -E 's/^\s*Session\s*=\s*(.*)$/\1/p' "$f" | head -n1)
        [ -n "$s" ] || continue
        case "$s" in hyprland*) continue ;; esac
        if ask "Настроен автовход в «${s%.desktop}» ($f). Переключить автовход на Hyprland?" y; then
            sudo cp -n "$f" "$f.rice-backup"
            sudo sed -i -E 's/^(\s*Session\s*=\s*).*/\1hyprland.desktop/' "$f"
        fi
    done
    # Preselect Hyprland on the login screen (SDDM remembers the last session per machine);
    # side by side with another desktop the last choice is left alone.
    if [ "$MODE" = coexist ]; then
        ok "SDDM: тема sugar-candy, сеанс выбирается на экране входа"
        return 0
    fi
    local state=/var/lib/sddm/state.conf
    sudo mkdir -p /var/lib/sddm
    printf '%s\n' "[Last]" "Session=/usr/share/wayland-sessions/hyprland.desktop" "User=$USER" \
        | sudo_write "$state"
    sudo chown sddm:sddm "$state" 2>/dev/null || true
    ok "SDDM: тема sugar-candy, по умолчанию Hyprland"
}

# What setup_system puts outside ~; teardown_system takes it away again.
THEME_ROOT=/usr/local/bin/hypr-theme-root
SUDOERS_RULE=/etc/sudoers.d/hypr-theme
TMPFILES_D=/etc/tmpfiles.d

setup_system() {
    fill_home "$SRC/system/hypr-theme-root" | sudo_write "$THEME_ROOT"
    sudo chmod 755 "$THEME_ROOT"
    local tmp
    tmp=$(mktemp)
    echo "$USER ALL=(root) NOPASSWD: $THEME_ROOT" > "$tmp"
    if sudo visudo -cqf "$tmp"; then
        sudo install -m 440 -o root -g root "$tmp" "$SUDOERS_RULE"
        ok "hypr-theme-root (цвет папок, экран входа, тема браузеров)"
    else
        warn "правило sudoers не прошло проверку, смена цвета папок и SDDM работать не будет"
    fi
    rm -f "$tmp"

    setup_sddm

    if ls /sys/bus/platform/drivers/ideapad_acpi/*/fn_lock >/dev/null 2>&1; then
        sudo install -Dm644 "$SRC/system/fn-lock.conf" "$TMPFILES_D/fn-lock.conf"
        sudo systemd-tmpfiles --create "$TMPFILES_D/fn-lock.conf" 2>/dev/null || true
        ok "Lenovo IdeaPad: Fn Lock включён"
    fi
    local s u
    for s in NetworkManager bluetooth; do
        sudo systemctl enable "$s.service" >/dev/null 2>&1 || warn "не включился $s"
    done
    systemctl --user daemon-reload 2>/dev/null || true
    # histuid and portal-restart are started by Hyprland itself (another desktop on the same
    # account has its own notification daemon); older installs enabled them globally.
    systemctl --user disable histuid.service portal-restart.timer >/dev/null 2>&1 || true
    for u in pipewire.socket pipewire-pulse.socket wireplumber.service; do
        systemctl --user enable "$u" >/dev/null 2>&1 || warn "не включился $u (включи после входа: systemctl --user enable $u)"
    done
    ok "сервисы"

    # GTK, icons, cursor. settings.ini covers GTK apps; gsettings covers portals and libadwaita.
    local gtk=Graphite-Dark
    [ -d /usr/share/themes/Graphite-Dark ] || gtk=Adwaita-dark
    set_interface gtk-theme "$gtk"
    set_interface icon-theme Papirus-Dark
    set_interface cursor-theme WhiteCat
    set_interface cursor-size 24
    set_interface color-scheme prefer-dark
    sed -i "s/^gtk-theme-name=.*/gtk-theme-name=$gtk/" "$HOME/.config/gtk-3.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini" 2>/dev/null || true
    ok "GTK: $gtk, Papirus-Dark, курсор WhiteCat"
}

set_interface() {  # set_interface KEY VALUE: a GNOME interface setting (portals and libadwaita read them)
    dbus-run-session gsettings set org.gnome.desktop.interface "$@" 2>/dev/null \
        || gsettings set org.gnome.desktop.interface "$@" 2>/dev/null || true
}

CACHE_TRIM=/usr/local/bin/rice-cache-trim
CACHE_TRIM_HOOK=/etc/pacman.d/hooks/rice-cache-trim.hook

setup_maintenance() {  # package caches kept under 200 MB, weekly TRIM for SSDs, the daily rice doctor
    sudo install -m755 "$SRC/system/rice-cache-trim" "$CACHE_TRIM"
    sudo install -Dm644 "$SRC/system/rice-cache-trim.hook" "$CACHE_TRIM_HOOK"
    systemctl --user enable cache-trim.timer >/dev/null 2>&1 || warn "не включился cache-trim.timer"
    systemctl --user enable rice-doctor.timer >/dev/null 2>&1 || warn "не включился rice-doctor.timer"
    sudo systemctl enable fstrim.timer >/dev/null 2>&1 || warn "не включился fstrim.timer"
    ok "кэш пакетов не больше 200 МБ, TRIM для SSD раз в неделю, проверка системы раз в день"
}

# The mirror of setup_system, setup_maintenance and setup_pkg_repo, for uninstall. SDDM itself, its
# theme package and fstrim stay: the machine needs some login screen, and TRIM does no harm.
teardown_system() {
    local f conf
    sudo rm -f "$SUDOERS_RULE" "$THEME_ROOT" "$CACHE_TRIM" "$CACHE_TRIM_HOOK" "$SDDM_CONF_D/99-hypr-rice.conf" \
        "$TMPFILES_D/hypr-rice-power.conf" "$TMPFILES_D/hypr-rice-battery.conf"
    systemctl --user disable --now cache-trim.timer rice-doctor.timer >/dev/null 2>&1 || true
    if cmp -s "$TMPFILES_D/fn-lock.conf" "$SRC/system/fn-lock.conf"; then sudo rm -f "$TMPFILES_D/fn-lock.conf"; fi
    # hypr-theme-root writes this one when no theme was set at all.
    if cmp -s "$SDDM_CONF_D/10-theme.conf" "$SRC/system/sddm-theme.conf"; then sudo rm -f "$SDDM_CONF_D/10-theme.conf"; fi
    # SDDM files the rice changed (theme, autologin), and the mirror list it put fallback mirrors in.
    for f in "$SDDM_CONF.rice-backup" "$SDDM_CONF_D"/*.rice-backup "$MIRRORLIST.rice-backup"; do
        [ -f "$f" ] || continue
        sudo mv "$f" "${f%.rice-backup}"
    done
    if pkg_repo_enabled; then
        conf=$(awk '/^\[/ { skip = ($0 == "[hypr-rice]") } !skip' "$PACMAN_CONF")
        printf '%s\n' "$conf" | sudo_write "$PACMAN_CONF"
        sudo pacman-key --delete "$PKG_KEY_FPR" >/dev/null 2>&1 || true
        info "репозиторий hypr-rice отключён; поставленные из него пакеты остались"
    fi
    ok "системные файлы райса убраны (SDDM остался экраном входа, с обычной темой)"
}

setup_apps_config() {
    if command -v code-oss >/dev/null; then
        local ext
        for ext in mhutchie.git-graph MS-CEINTL.vscode-language-pack-ru; do
            code-oss --install-extension "$ext" --force >/dev/null 2>&1 || warn "Code-OSS: не встало $ext"
        done
        ok "Code-OSS: Git Graph, русский язык"
    fi
    mkdir -p "$HOME/.claude"
    local cfg="$HOME/.claude/settings.json"
    if [ -f "$cfg" ]; then
        jq '.statusLine = {type: "command", command: "~/.claude/statusline.sh"}' "$cfg" > "$cfg.tmp" && mv "$cfg.tmp" "$cfg"
    else
        echo '{ "statusLine": { "type": "command", "command": "~/.claude/statusline.sh" } }' | jq . > "$cfg"
    fi
    python3 "$HOME/.config/hypr/scripts/themegen.py" build >/dev/null 2>&1 \
        || warn "themegen build завершился с ошибкой (python3 ~/.config/hypr/scripts/themegen.py build)"
    ok "темы приложений"
}

apply_theme() {
    local theme=$1
    dbus-run-session "$HOME/.local/bin/changetheme" --offline "$theme" >/dev/null 2>&1 \
        || "$HOME/.local/bin/changetheme" --offline "$theme" >/dev/null 2>&1 \
        || warn "changetheme --offline $theme не отработал, после входа выполни: changetheme $theme"
    ok "тема $theme (менять: Alt+Shift+T или changetheme <тема>)"
}

unset_claude_statusline() {  # setup_apps_config pointed Claude Code's status line at the rice's script
    local cfg="$HOME/.claude/settings.json"
    [ -f "$cfg" ] || return 0
    jq -e '.statusLine.command == "~/.claude/statusline.sh"' "$cfg" >/dev/null 2>&1 || return 0
    jq 'del(.statusLine)' "$cfg" > "$cfg.tmp" && mv "$cfg.tmp" "$cfg"
}

current_theme() {  # the theme in use, claude when none is set yet
    cat "$HOME/.config/hypr/current-theme" 2>/dev/null || echo claude
}
