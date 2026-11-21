# rice install, update, uninstall and report: the rice's files in ~, backups, install.sh.

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
    [ -f "$HOME/.config/quickshell/launch/common/Theme.qml" ] || fail "карточка запуска не видит общий Theme.qml через ссылку common"
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

# rice report writes every section even on a broken system: sddm stopped, no network, no Hyprland.
test_report_writes_every_section() {
    mkdir -p "$HOME/root/etc"
    echo "[core]" > "$HOME/root/etc/pacman.conf"
    strict_rice '
        systemctl() { return 3; }
        journalctl() { return 1; }
        curl() { return 7; }
        hyprctl() { return 1; }
        cmd_report' >/dev/null 2>&1 || fail "rice report завершился с ошибкой"
    local report="$HOME/rice-report.txt"
    grep -qx '== pacman.conf repos' "$report" && grep -qx '\[core\]' "$report" \
        || fail "отчёт оборвался: $(tail -n 3 "$report")"
    grep -q 'не запущен' "$report" || fail "не сказано, что Hyprland не запущен"
}

# Code - OSS keeps settings.json as JSONC: the rice's settings are merged into it all the same, the
# file before the merge is kept, one that does not parse is left alone, and uninstall puts back the
# user's own from before the rice.
test_code_settings_merged() {
    load_rice
    local settings="$HOME/.config/Code - OSS/User/settings.json"
    mkdir -p "$(dirname "$settings")" "$HOME/.config/hypr"
    echo installed > "$HOME/.config/hypr/.rice-installed"  # an update: nothing is backed up
    cat > "$settings" <<'EOF'
{
    // my font
    "editor.fontSize": 15, /* big */
    "my.url": "http://example.com//path",
    "files.autoSave": "off",
}
EOF
    cp "$settings" "$HOME/mine.json"
    inspect_existing_desktop >/dev/null
    copy_rice_files >/dev/null 2>&1
    jq -e '."editor.fontSize" == 15 and ."my.url" == "http://example.com//path"
           and ."files.autoSave" == "afterDelay" and ."git.autofetch" == true' "$settings" >/dev/null \
        || fail "настройки не слиты: $(cat "$settings")"
    cmp -s "$settings.rice-backup" "$HOME/mine.json" || fail "файл до слияния не сохранён"

    echo '{ broken' > "$settings"
    copy_rice_files >/dev/null 2>&1
    [ "$(cat "$settings")" = '{ broken' ] || fail "неразобранный файл перезаписан"

    cmd_uninstall >/dev/null 2>&1
    cmp -s "$settings" "$HOME/mine.json" || fail "после удаления не вернулся свой settings.json: $(cat "$settings")"
}

# Uninstall takes back what the rice set up outside ~ and what the programs' setup steps changed;
# files it did not write stay.
test_uninstall_tears_down_system() {
    load_rice
    mkdir -p "$(dirname "$SUDOERS_RULE")" "$(dirname "$THEME_ROOT")" "$SDDM_CONF_D" "$TMPFILES_D" \
        "$(dirname "$CACHE_TRIM_HOOK")" "$HOME/.claude" "$HOME/.config/hypr"
    local f ours=("$SUDOERS_RULE" "$THEME_ROOT" "$CACHE_TRIM" "$CACHE_TRIM_HOOK" "$SDDM_CONF_D/99-hypr-rice.conf"
                  "$TMPFILES_D/hypr-rice-power.conf" "$HOME/.config/hypr/games.lua")
    for f in "${ours[@]}"; do touch "$f"; done
    echo mine > "$TMPFILES_D/mine.conf"
    printf '[Autologin]\nSession=plasma\n' > "$SDDM_CONF_D/autologin.conf.rice-backup"
    printf '[Autologin]\nSession=hyprland.desktop\n' > "$SDDM_CONF_D/autologin.conf"
    printf '[options]\n\n[core]\nInclude = x\n\n[hypr-rice]\nSigLevel = Required DatabaseOptional\nServer = %s\n' \
        "$PKG_REPO_URL" > "$PACMAN_CONF"
    echo '{"model": "x", "statusLine": {"type": "command", "command": "~/.claude/statusline.sh"}}' \
        > "$HOME/.claude/settings.json"
    pacman-key() { echo "pacman-key $*" >> "$HOME/calls"; }
    systemctl() { echo "systemctl $*" >> "$HOME/calls"; }
    hyprctl() { :; }
    is_installed() { [ "$1" = zram-generator ]; }
    unhook_zram() { echo "unhook zram" >> "$HOME/calls"; }

    cmd_uninstall >/dev/null 2>&1
    for f in "${ours[@]}"; do [ ! -e "$f" ] || fail "остался $f"; done
    [ -e "$TMPFILES_D/mine.conf" ] || fail "удалён чужой файл"
    [ "$(cat "$SDDM_CONF_D/autologin.conf")" = "$(printf '[Autologin]\nSession=plasma')" ] \
        || fail "автовход не возвращён: $(cat "$SDDM_CONF_D/autologin.conf")"
    ! grep -q 'hypr-rice' "$PACMAN_CONF" && grep -qx '\[core\]' "$PACMAN_CONF" \
        || fail "pacman.conf: $(cat "$PACMAN_CONF")"
    grep -qx "pacman-key --delete $PKG_KEY_FPR" "$HOME/calls" || fail "ключ репозитория остался"
    grep -qx 'unhook zram' "$HOME/calls" || fail "шаг zram не отменён"
    grep -q 'disable --now cache-trim.timer' "$HOME/calls" || fail "cache-trim.timer остался включён"
    jq -e '.statusLine == null and .model == "x"' "$HOME/.claude/settings.json" >/dev/null \
        || fail "Claude Code: $(cat "$HOME/.claude/settings.json")"
}

# An update removes the files an earlier version installed and this one no longer ships; the user's
# own files next to them stay.
test_update_removes_stale_rice_files() {
    load_rice
    mkdir -p "$HOME/.config/hypr" "$HOME/.local/bin"
    echo installed > "$HOME/.config/hypr/.rice-installed"
    inspect_existing_desktop >/dev/null
    copy_rice_files >/dev/null 2>&1
    grep -qx '.config/hypr/hyprland.lua' "$MANIFEST" || fail "нет списка поставленных файлов"
    echo ".local/bin/renamed-script" >> "$MANIFEST"  # shipped by the previous version
    echo old > "$HOME/.local/bin/renamed-script"
    echo mine > "$HOME/.local/bin/my-script"
    copy_rice_files >/dev/null 2>&1
    [ ! -e "$HOME/.local/bin/renamed-script" ] || fail "остался файл прежней версии"
    [ -e "$HOME/.local/bin/my-script" ] || fail "удалён свой файл"
    ! grep -qx '.local/bin/renamed-script' "$MANIFEST" || fail "убранный файл остался в списке"
}

# The home folder may hold characters sed treats specially; USER may be unset.
test_home_and_user_anywhere() {
    export HOME="$HOME/a|b&c\\d"
    mkdir -p "$HOME"
    load_rice
    printf 'path=__HOME__/x\n' > "$HOME/file"
    fill_home -i "$HOME/file"
    [ "$(cat "$HOME/file")" = "path=$HOME/x" ] || fail "подставлено: $(cat "$HOME/file")"
    [ "$(env -u USER bash -c "source '$REPO/rice'; echo \"\$USER\"")" = "$(id -un)" ] || fail "без USER"
}

# Uninstall with a backup folder that turned out empty puts back nothing and does not fail.
test_uninstall_with_empty_backup() {
    mkdir -p "$HOME/.rice-backup-1" "$HOME/.config/hypr-rice"
    echo "backup=$HOME/.rice-backup-1" > "$HOME/.config/hypr-rice/install.conf"
    strict_rice cmd_uninstall >/dev/null 2>&1 || fail "удаление с пустым бэкапом завершилось с ошибкой"
}

# install.sh: a repeated install on another branch switches to it (the clone is single-branch), and a
# git repository of the user's own at RICE_SRC is refused, not reset.
test_install_sh_branches() {
    local bin="$HOME/bin" remote="$HOME/remote" branch
    mkdir -p "$bin"
    printf '#!/bin/sh\nexit 0\n' > "$bin/curl"
    cp "$bin/curl" "$bin/pacman"
    chmod +x "$bin"/*
    export GIT_CONFIG_GLOBAL="$HOME/gitconfig" GIT_CONFIG_NOSYSTEM=1 PATH="$bin:$PATH"
    git config --global user.name test
    git config --global user.email test@example.com
    git config --global protocol.file.allow always
    git config --global url."file://$remote".insteadOf https://github.com/larion928/hypr-rice.git
    git init -q -b main "$remote"
    for branch in main dev; do
        git -C "$remote" checkout -q -B "$branch"
        printf '#!/bin/sh\necho "rice from %s $*"\n' "$branch" > "$remote/rice"
        chmod +x "$remote/rice"
        git -C "$remote" add rice
        git -C "$remote" commit -q -m "$branch"
    done

    [ "$(RICE_SRC="$HOME/src" RICE_BRANCH=main bash "$REPO/install.sh" 2>&1 | tail -n1)" = "rice from main install" ] \
        || fail "первая установка не прошла"
    local out
    out=$(RICE_SRC="$HOME/src" RICE_BRANCH=dev bash "$REPO/install.sh" 2>&1 | tail -n1)
    [ "$out" = "rice from dev install" ] || fail "другая ветка: $out"
    [ "$(git -C "$HOME/src" rev-parse --abbrev-ref HEAD)" = dev ] || fail "rice update пойдёт не по той ветке"

    git init -q "$HOME/mine"
    echo committed > "$HOME/mine/file"
    git -C "$HOME/mine" add file
    git -C "$HOME/mine" commit -q -m mine
    echo changed > "$HOME/mine/file"
    RICE_SRC="$HOME/mine" bash "$REPO/install.sh" >/dev/null 2>&1 && fail "чужой репозиторий принят"
    [ "$(cat "$HOME/mine/file")" = changed ] || fail "чужой репозиторий сброшен"
}

# rice help lists every command of the header.
test_help_lists_every_command() {
    local cmd help
    help=$("$REPO/rice" help)
    for cmd in install apps remove update upgrade proton games repair report doctor features uninstall; do
        grep -q "^  rice $cmd " <<<"$help" || fail "в справке нет rice $cmd"
    done
}

# Side by side with another desktop whose login screen the user kept: the choice is remembered, and
# neither an update nor a repair turns that login screen off for SDDM.
test_coexist_keeps_other_login_screen() {
    load_rice
    local unit="$HOME/root/usr/lib/systemd/system/gdm.service"
    mkdir -p "$(dirname "$unit")" "$(dirname "$DISPLAY_MANAGER_UNIT")" "$HOME/.config/waybar" "$HOME/.config/hypr"
    touch "$unit"
    ln -s "$unit" "$DISPLAY_MANAGER_UNIT"
    echo foreign > "$HOME/.config/waybar/config"
    systemctl() { echo "systemctl $*" >> "$HOME/calls"; }
    RICE_MODE=coexist RICE_ASSUME=n
    inspect_existing_desktop >/dev/null 2>&1
    record_install
    grep -qx 'use_sddm=0' "$HOME/.config/hypr-rice/install.conf" \
        || fail "отказ от SDDM не записан: $(cat "$HOME/.config/hypr-rice/install.conf")"

    # A fresh rice, as `rice update` and `rice repair` start; their other steps are not this test's.
    unset RICE_MODE
    RICE_ASSUME=y MODE=replace USE_SDDM=1
    install_missing_packages() { :; }
    rerun_installed_hooks() { :; }
    apply_rice() { setup_sddm; record_install; }
    pac() { :; }
    aur_install() { :; }
    mark_rice_packages_explicit() { :; }
    pkg_repo_enabled() { :; }
    setup_system() { setup_sddm; }
    setup_maintenance() { :; }
    setup_features() { :; }
    apply_theme() { :; }
    cmd_apply_update >/dev/null 2>&1
    MODE=replace USE_SDDM=1
    cmd_repair >/dev/null 2>&1
    ! grep -q 'sddm' "$HOME/calls" 2>/dev/null || fail "экран входа gdm заменён: $(cat "$HOME/calls")"
    [ ! -e "$SDDM_CONF_D/99-hypr-rice.conf" ] || fail "записана тема SDDM"
    grep -qx 'use_sddm=0' "$HOME/.config/hypr-rice/install.conf" || fail "обновление забыло отказ от SDDM"
}

# Installs from before the choice was written down: the login screen they left in place is the answer.
test_coexist_choice_read_from_old_install() {
    load_rice
    local unit="$HOME/root/usr/lib/systemd/system/gdm.service"
    mkdir -p "$(dirname "$unit")" "$(dirname "$DISPLAY_MANAGER_UNIT")" "$HOME/.config/hypr-rice"
    echo mode=coexist > "$HOME/.config/hypr-rice/install.conf"
    load_install_mode
    [ "$MODE/$USE_SDDM" = coexist/1 ] || fail "без экрана входа: $MODE/$USE_SDDM"
    touch "$unit"
    ln -s "$unit" "$DISPLAY_MANAGER_UNIT"
    load_install_mode
    [ "$MODE/$USE_SDDM" = coexist/0 ] || fail "при gdm: $MODE/$USE_SDDM"
    echo mode=replace > "$HOME/.config/hypr-rice/install.conf"
    load_install_mode
    [ "$MODE/$USE_SDDM" = replace/1 ] || fail "замена: $MODE/$USE_SDDM"
}

# A machine without a display manager has no login screen to turn off.
test_sddm_without_display_manager() {
    load_rice
    systemctl() { echo "systemctl $*" >> "$HOME/calls"; }
    sudo_write() { :; }
    setup_sddm >/dev/null 2>&1
    ! grep -q 'disable' "$HOME/calls" || fail "выключался несуществующий экран входа: $(cat "$HOME/calls")"
}
