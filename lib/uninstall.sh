# rice uninstall: the rice's files and system settings go, the backup of what was there before comes back.

cmd_uninstall() {
    local backup
    backup=$(pre_rice_backup)
    step "Удаление hypr-rice"
    if [ -n "$backup" ]; then
        info "будет возвращён бэкап: $backup"
    else
        info "бэкапа прежних настроек нет: файлы райса просто удалятся"
    fi
    ask "Удалить hypr-rice?" n || return 0
    need_sudo
    load_apps
    undo_program_steps
    # Before the files go: the user units it disables are among them.
    teardown_system

    local f
    while IFS= read -r f; do rm -f "$HOME/$f"; done < <(installed_rice_files)
    while read -r _ f; do rm -f "$HOME/$f"; done < "$SRC/packages/release.sha256"
    restore_merged_files
    unset_claude_statusline
    cd "$HOME"
    rm -f "$MARKER" "$HOME/.local/bin/rice" "$HOME/.local/share/applications/hypr-rice-manager.desktop" \
          "$HOME/.config/hypr-rice/install.conf" "$MANIFEST"
    if [ -n "$backup" ]; then
        # Foreign configs were moved as whole directories, ours file by file under home/.
        for f in "$backup"/*; do
            [ -e "$f" ] || continue  # an empty backup: the pattern stays as it is
            case "$(basename "$f")" in
                home) (cd "$backup/home" && tar -cf - .) | tar -C "$HOME" -xf - ;;
                hypr) mkdir -p "$HOME/.config/hypr" && cp -a "$f/." "$HOME/.config/hypr/" ;;
                *) [ -e "$HOME/.config/$(basename "$f")" ] || mv "$f" "$HOME/.config/" ;;
            esac
        done
        ok "возвращено из $backup"
    fi
    info "Пакеты остались; удалить их: sudo pacman -Rs <пакеты>"
}

# The backup taken when the rice was first installed, or nothing if it replaced no other configs.
# Installs from before install.conf kept it get the oldest backup that is not one of the rice
# itself (older versions also backed the rice up on every update; those have the install marker).
pre_rice_backup() {
    local backup
    backup=$(install_setting backup)
    if [ -n "$backup" ]; then
        [ -d "$backup" ] && echo "$backup"
        return 0
    fi
    while IFS= read -r backup; do
        [ -e "$backup/hypr/.rice-installed" ] || { echo "$backup"; return 0; }
    done < <(find "$HOME" -maxdepth 1 -name '.rice-backup-*' | sort)
}

# The setup steps of installed programs and the game optimisations change the system (zram, earlyoom,
# the .exe rule in the kernel, AntiDPI, NTSync); without the rice nothing would manage them.
undo_program_steps() {
    local id tok
    for id in "${APP_IDS[@]}"; do
        app_packages_installed "$id" || continue
        for tok in ${APP_SRC[$id]}; do
            [[ $tok == hook:* ]] || continue
            run_unhook "${tok#hook:}" || warn "не отменился шаг ${tok#hook:}"
        done
    done
    # linux-zen stays: it may be the kernel running now.
    for id in gamemode ntsync tearing; do
        if tuning_on "$id"; then "tuning_${id}_off" || warn "не выключилось: $id"; fi
    done
}
