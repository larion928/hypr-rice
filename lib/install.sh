# rice install: the questions first, then packages, programs, the rice's files and system settings.

STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP="$HOME/.rice-backup-$STAMP"

# What inspect_existing_desktop decided, read by the steps after it (copy_rice_files, setup_sddm,
# record_install, finish). An update and a repair read MODE and USE_SDDM back (load_install_mode).
MODE=replace        # replace | coexist: what happens to another desktop's configs
DO_BACKUP=0         # 1 on a first install over another desktop: what the rice replaces goes to $BACKUP
USE_SDDM=1          # 0: coexist mode keeps the other desktop's login screen
FOREIGN_CONFIGS=()  # the other desktop's config folders in ~/.config

# Config folders of other desktops and rices.
RICE_DIRS=(hypr waybar quickshell kitty rofi wofi dunst mako swaync eww ags hyprpanel wlogout
           fuzzel walker histui swaylock alacritty foot)

cmd_install() {
    local theme="${RICE_THEME:-$(current_theme)}"
    need_sudo
    load_apps

    step "Вопросы (дальше всё пойдёт само)"
    inspect_existing_desktop
    pick_apps install

    step "Пакеты из официальных репозиториев"
    local base=()
    mapfile -t base < <(list "$SRC/packages/base.txt")
    # pipewire-pulse replaces PulseAudio; --noconfirm would answer "no" to removing it and abort.
    if pacman -Qq pulseaudio >/dev/null 2>&1; then
        local pa=()
        mapfile -t pa < <(pacman -Qq | grep -E '^pulseaudio(-|$)')
        sudo pacman -Rdd --noconfirm "${pa[@]}" >/dev/null
        info "PulseAudio заменён на PipeWire"
    fi
    pac -Syu --needed "${base[@]}" || die "не удалось поставить основные пакеты (интернет или зеркала)"
    ok "${#base[@]} пакетов"

    step "Пакеты AUR"
    setup_pkg_repo
    local aur=()
    mapfile -t aur < <(list "$SRC/packages/aur.txt")
    aur_install "${aur[@]}" || true
    mark_rice_packages_explicit
    ok "готово"

    if [ ${#PICKED[@]} -gt 0 ]; then
        step "Выбранные программы"
        install_apps "${PICKED[@]}"
    fi

    apply_rice "$theme"
    finish
    info "Перезагрузись и выбери сеанс Hyprland на экране входа."
    info "Alt+F1 — справка по хоткеям, Alt+R — лаунчер, Alt+Enter — терминал, rice — менеджер райса."
    # Never reboot on RICE_ASSUME alone: an unattended run should leave that to the caller.
    if [ -z "${RICE_ASSUME:-}" ] && ask "Перезагрузить сейчас?" n; then
        sudo systemctl reboot
    fi
}

# Decides what happens to the configs already in ~ (sets MODE, DO_BACKUP, USE_SDDM, FOREIGN_CONFIGS).
# Only a first install backs anything up: later runs replace the rice's own files, and the user's
# other configs (kitty, waybar of another desktop) are none of their business.
inspect_existing_desktop() {
    local d p
    FOREIGN_CONFIGS=()
    MODE=${RICE_MODE:-}
    DO_BACKUP=0
    USE_SDDM=1
    if [ -f "$MARKER" ]; then
        info "hypr-rice уже установлен ($(cat "$MARKER")). Файлы райса обновятся, остальное не тронется."
        ask "Продолжить?" y || die "отменено"
        load_install_mode
        MODE=${RICE_MODE:-$MODE}
        return
    fi
    for d in "${RICE_DIRS[@]}"; do
        p="$HOME/.config/$d"
        [ -e "$p" ] && [ -n "$(ls -A "$p" 2>/dev/null)" ] && FOREIGN_CONFIGS+=("$p")
    done
    if [ ${#FOREIGN_CONFIGS[@]} -eq 0 ]; then
        ok "система чистая"
        MODE=${MODE:-replace}
        return
    fi
    info "Найден уже настроенный рабочий стол:"
    printf '      %s\n' "${FOREIGN_CONFIGS[@]}"
    [ -n "$MODE" ] || MODE=$(choose_mode)
    case "$MODE" in
        replace) info "Старый райс уйдёт в бэкап $BACKUP, вместо него встанет hypr-rice." ;;
        coexist)
            info "hypr-rice встанет рядом: настройки другого окружения не трогаются,"
            info "выбор между ними — на экране входа."
            [ -d "$HOME/.config/hypr" ] && info "Только чужой конфиг Hyprland уйдёт в бэкап: два райса в одном Hyprland не уживаются."
            coexist_dm_question ;;
        *) die "отменено, ничего не изменено" ;;
    esac
    DO_BACKUP=1
}

install_setting() {  # install_setting KEY: a value from install.conf, empty when unset
    sed -n "s/^$1=//p" "$HOME/.config/hypr-rice/install.conf" 2>/dev/null || true
}

# MODE and USE_SDDM as the first install decided them: a reinstall, an update and a repair must leave
# alone the other desktop's login screen the user chose to keep.
load_install_mode() {
    MODE=$(install_setting mode)
    MODE=${MODE:-replace}
    USE_SDDM=$(install_setting use_sddm)
    [ -n "$USE_SDDM" ] && return
    # Installs from before use_sddm was written: side by side, a login screen left in place was the answer.
    USE_SDDM=1
    if [ "$MODE" = coexist ]; then
        case "$(display_manager)" in
            ""|sddm) ;;
            *) USE_SDDM=0 ;;
        esac
    fi
}

# Remembers the install: the version, the mode and the login screen choice, and the backup that
# uninstall puts back.
record_install() {
    local backup
    backup=$(install_setting backup)
    [ "$DO_BACKUP" = 1 ] && backup=$BACKUP
    echo "$(git -C "$SRC" log -1 --format='%h %cs' 2>/dev/null || echo local) $STAMP" > "$MARKER"
    mkdir -p "$HOME/.config/hypr-rice"
    printf '%s\n' "mode=$MODE" "use_sddm=$USE_SDDM" ${backup:+"backup=$backup"} > "$HOME/.config/hypr-rice/install.conf"
    [ -f "$TRUST" ] || install -m644 "$SRC/system/allowed_signers" "$TRUST"
}

choose_mode() {  # replace | coexist | cancel
    if [ -n "${RICE_ASSUME:-}" ]; then
        [[ $RICE_ASSUME =~ ^[Yy] ]] && echo replace || echo cancel
        return
    fi
    choose_one "Что сделать со старым райсом?" \
        "Заменить: старый уйдёт в бэкап=replace" \
        "Поставить рядом: выбор окружения на экране входа=coexist" \
        "Отмена=cancel" || echo cancel
}

coexist_dm_question() {
    local cur
    cur=$(display_manager)
    if [ -n "$cur" ] && [ "$cur" != sddm ]; then
        ask "Сейчас экран входа — $cur. Поставить вместо него SDDM hypr-rice (с темой райса)?" n \
            || USE_SDDM=0
    fi
}

# The part of an install that a rice update repeats: files, system settings, app themes.
apply_rice() {
    local theme=$1
    step "Файлы райса"
    copy_rice_files
    update_release_files

    step "Системные настройки"
    setup_system
    setup_maintenance

    step "Приложения"
    setup_apps_config

    step "Тема"
    apply_theme "$theme"
    record_install
}
