# rice update (the rice's new version from GitHub, signed by its author) and rice upgrade (the system).

# Installs from before signed updates have no TRUST yet; it is written at the end of their next install.
# install.sh has its own copy: it checks the download before running anything from it, this file included.
signed_by_author() {  # signed_by_author REV
    [ -f "$TRUST" ] || return 0
    git -C "$SRC" -c gpg.format=ssh -c gpg.ssh.allowedSignersFile="$TRUST" verify-commit "$1" >/dev/null 2>&1
}

cmd_update() {
    # Updates follow the branch the rice was installed from.
    local branch="${RICE_BRANCH:-$(git -C "$SRC" rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)}"
    step "Обновляю hypr-rice"
    # An explicit refspec: the clone is single-branch, and RICE_BRANCH may name another branch.
    git -C "$SRC" fetch -q --depth 1 origin "+refs/heads/$branch:refs/remotes/origin/$branch" \
        || die "не удалось скачать обновление с GitHub"
    signed_by_author "origin/$branch" || die "новая версия на GitHub не подписана ключом автора, обновление не применено.
    Если автор сменил ключ и сам об этом сказал: rm $TRUST и снова rice update."
    local before after
    before=$(git -C "$SRC" rev-parse --short HEAD)
    # As a branch of that name, so the next update follows it too (branch is read from HEAD).
    git -C "$SRC" checkout -q -f -B "$branch" "origin/$branch"
    after=$(git -C "$SRC" rev-parse --short HEAD)
    if [ "$before" = "$after" ] && [ -z "${RICE_FORCE:-}" ]; then
        ok "уже последняя версия ($after)"
        return
    fi
    ok "$before → $after"
    git -C "$SRC" log --format='      %s' "$before..$after" 2>/dev/null | head -n 15 || true
    # The new rice script may differ from the running one; let it apply the update.
    exec "$SRC/rice" apply-update
}

# What an update needs: the packages the new version added, its files, its settings. The system
# itself is not upgraded here, that is `rice upgrade`.
cmd_apply_update() {
    need_sudo
    load_apps
    load_install_mode

    step "Новые пакеты райса"
    install_missing_packages
    apply_rice "$(current_theme)"
    rerun_installed_hooks
    finish
}

install_missing_packages() {
    local packages=() missing=() aur=()
    mapfile -t packages < <(list "$SRC/packages/base.txt")
    mapfile -t missing < <(pacman -T "${packages[@]}" 2>/dev/null || true)
    mapfile -t aur < <(list "$SRC/packages/aur.txt")
    # Without -y: syncing the databases without upgrading would leave a partial upgrade.
    if [ ${#missing[@]} -gt 0 ] && ! pac -S --needed "${missing[@]}"; then
        warn "не встали новые пакеты: ${missing[*]}. Поставятся с обновлением системы: rice upgrade"
    elif aur_install "${aur[@]}"; then
        ok "все пакеты райса на месте"
    fi
    forget_installed
    mark_rice_packages_explicit
}

cmd_upgrade() {
    need_sudo
    step "Обновление системы"
    pkg_repo_enabled || setup_pkg_repo
    pac -Syu || die "pacman -Syu не прошёл"
    ok "официальные репозитории и hypr-rice"
    # AUR packages that are not in the hypr-rice repo: -Qm lists only packages no enabled repo has,
    # and the hypr-rice repo is one of them, so its packages were upgraded by -Syu above.
    local foreign=()
    mapfile -t foreign < <(pacman -Qqm)
    if [ ${#foreign[@]} -gt 0 ] && aur_reachable && command -v yay >/dev/null; then
        yay -Sua --noconfirm --answerdiff None --answerclean None || warn "часть AUR-пакетов не обновилась"
    elif [ ${#foreign[@]} -gt 0 ]; then
        info "AUR недоступен; пакеты не из репозитория hypr-rice не обновлены: ${foreign[*]}"
    fi
    command -v flatpak >/dev/null && flatpak update --user -y --noninteractive >/dev/null 2>&1 || true
    finish
}
