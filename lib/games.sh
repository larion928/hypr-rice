# rice games (game optimisations, each on or off) and rice proton (the Proton that runs .exe files).

# What is on is read from the system itself, not from a list of its own that could drift from it.
GAMEMODE_MARK="$HOME/.config/hypr-rice/gamemode"  # proton-run and the games window start games through gamemoderun
GAMEMODE_INI="$HOME/.config/gamemode.ini"
TEARING_LUA="$HOME/.config/hypr/games.lua"        # hyprland.lua loads it
NTSYNC_LOAD=/etc/modules-load.d/ntsync.conf
NTSYNC_RULE=/etc/udev/rules.d/60-ntsync.rules
GAME_TUNINGS=("GameMode во время игр=gamemode" "NTSync для Proton (опыт)=ntsync"
              "Тиринг в полноэкранных играх=tearing" "Ядро linux-zen=zen")

tuning_on() {  # tuning_on gamemode|ntsync|tearing|zen
    case "$1" in
        gamemode) [ -f "$GAMEMODE_MARK" ] ;;
        ntsync) [ -f "$NTSYNC_LOAD" ] ;;
        tearing) [ -f "$TEARING_LUA" ] ;;
        zen) pacman -Q linux-zen >/dev/null 2>&1 ;;
    esac
}

cmd_games() {
    local label out on=() chosen=()
    step "Игры: оптимизация"
    info "GameMode — на время игры: приоритет процессора и диска, режим «производительность», высокие частоты"
    info "    видеокарты AMD; после игры всё как было. Ноутбук греется сильнее."
    info "NTSync — модуль ядра для Proton. Опыт: где-то быстрее, где-то медленнее fsync, сравни на своих играх."
    info "Тиринг — полноэкранные игры без ожидания кадра: меньше задержка ввода, но видны разрывы кадра."
    info "linux-zen — второе ядро (выбор в меню GRUB), прирост на ноутбуках не доказан, ~150 МБ."
    for label in "${GAME_TUNINGS[@]}"; do
        if tuning_on "${label##*=}"; then on+=("${label%=*}"); fi
    done
    have_tty || die "нужен терминал: rice games спрашивает, что включить"
    out=$(choose_many "Что включить?" "$(IFS=,; echo "${on[*]}")" \
        "${GAME_TUNINGS[@]}") || return 0
    mapfile -t chosen <<<"$out"
    apply_game_tunings "${chosen[@]}"
}

apply_game_tunings() {  # apply_game_tunings ID...: those on, the others off; only what changes is touched
    local label id
    for label in "${GAME_TUNINGS[@]}"; do
        id=${label##*=}
        if printf '%s\n' "$@" | grep -qx "$id"; then
            tuning_on "$id" || "tuning_${id}_on" || warn "не включилось: ${label%=*}"
        elif tuning_on "$id"; then
            "tuning_${id}_off" || warn "не выключилось: ${label%=*}"
        fi
    done
}

tuning_gamemode_on() {
    need_sudo
    pac -S --needed gamemode || return 1
    enable_multilib || return 1
    pac -S --needed lib32-gamemode || warn "32-битная часть gamemode не встала: старые 32-битные игры пойдут без него"
    # The group lets gamemode raise priorities and switch CPU and GPU clocks without a password.
    sudo usermod -aG gamemode "$USER" || return 1
    write_gamemode_ini || return 1
    mkdir -p "$(dirname "$GAMEMODE_MARK")" || return 1
    touch "$GAMEMODE_MARK" || return 1
    ok "GameMode включён; права группы gamemode заработают после нового входа в систему"
    info "игры Steam: в свойствах игры, параметры запуска — gamemoderun %command%"
}

tuning_gamemode_off() {
    rm -f "$GAMEMODE_MARK"
    if rice_owns "$GAMEMODE_INI"; then rm -f "$GAMEMODE_INI"; fi
    ok "GameMode выключен (пакет остался)"
}

# gamemode's own settings, unless the user keeps a gamemode.ini of their own.
write_gamemode_ini() {
    if ! rice_owns "$GAMEMODE_INI"; then
        info "свой $GAMEMODE_INI оставлен как есть"
        return
    fi
    local card
    {
        echo "$RICE_MARK (rice → Игры: оптимизация); rice removes it when GameMode is switched off."
        printf '[general]\nrenice=10\nioprio=0\ninhibit_screensaver=1\n'
        # The GPU part only for an AMD card: amd_performance_level is all gamemode does for it.
        if card=$(amd_card); then
            printf '\n[gpu]\napply_gpu_optimisations=accept-responsibility\ngpu_device=%s\namd_performance_level=high\n' "$card"
        fi
    } > "$GAMEMODE_INI"
}

amd_card() {  # the number N of the first /sys/class/drm/cardN run by amdgpu
    local card
    for card in /sys/class/drm/card[0-9]*; do
        if [ "$(basename "$(readlink -f "$card/device/driver")")" = amdgpu ]; then
            echo "${card##*card}"
            return 0
        fi
    done
    return 1
}

tuning_ntsync_on() {
    need_sudo
    echo ntsync | sudo_write "$NTSYNC_LOAD" || return 1
    # The device is root's only otherwise; uaccess gives it to whoever sits at the machine.
    echo 'KERNEL=="ntsync", TAG+="uaccess"' | sudo_write "$NTSYNC_RULE" || return 1
    sudo udevadm control --reload || return 1
    sudo modprobe ntsync || { warn "модуль ntsync не загрузился (в этом ядре его нет?)"; return 1; }
    ok "NTSync включён: Proton через proton-run берёт его сам (PROTON_USE_NTSYNC)"
}

tuning_ntsync_off() {
    need_sudo
    sudo rm -f "$NTSYNC_LOAD" "$NTSYNC_RULE" || return 1
    sudo udevadm control --reload || return 1
    sudo modprobe -r ntsync 2>/dev/null || info "ntsync сейчас занят игрой: выгрузится после перезагрузки"
    ok "NTSync выключен"
}

tuning_tearing_on() {
    mkdir -p "$(dirname "$TEARING_LUA")" || return 1
    cat > "$TEARING_LUA" <<'LUA' || return 1
-- Тиринг в полноэкранных играх (rice → Игры: оптимизация); rice writes and removes this file.
-- Hyprland shows such a game's frame at once instead of waiting for the screen: less input lag, with
-- tearing. Games run on XWayland (Proton, Steam, Wine) or are osu!; browsers and video players are
-- native Wayland windows and keep whole frames.
hl.config({ general = { allow_tearing = true } })

hl.window_rule({
    name  = "games-tearing",
    match = { fullscreen = true, xwayland = true },

    immediate = true,
})

hl.window_rule({
    name  = "games-tearing-osu",
    match = { fullscreen = true, class = "^osu!$" },

    immediate = true,
})
LUA
    hyprctl reload >/dev/null 2>&1 || true
    ok "тиринг в полноэкранных играх включён"
}

tuning_tearing_off() {
    rm -f "$TEARING_LUA"
    hyprctl reload >/dev/null 2>&1 || true
    ok "тиринг выключен"
}

tuning_zen_on() {
    need_sudo
    local free_mb
    free_mb=$(df --output=avail -m / | tail -n1)
    [ "$free_mb" -ge 1000 ] || { warn "на / свободно ${free_mb} МБ, для ядра нужно ~1000"; return 1; }
    pac -S --needed linux-zen || return 1
    update_grub
    ok "linux-zen поставлен; linux остался. Какое ядро грузится сейчас: uname -r; другое — в меню GRUB (Advanced options)"
}

tuning_zen_off() {
    case "$(uname -r)" in
        *zen*) warn "сейчас загружено linux-zen: перезагрузись в linux, потом выключай"; return 1 ;;
    esac
    need_sudo
    sudo pacman -Rns --noconfirm linux-zen || return 1
    update_grub
    ok "linux-zen удалён"
}

update_grub() {
    if [ -f /boot/grub/grub.cfg ] && command -v grub-mkconfig >/dev/null; then
        sudo grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1 || warn "grub-mkconfig не отработал: меню загрузки не обновлено"
    else
        warn "загрузчик не GRUB: меню загрузки обнови сам"
    fi
}

STEAM_DIR="$HOME/.local/share/Steam"

proton_versions() {  # "name=path" for every Proton here: downloaded (ProtonPlus, umu), then Steam's own
    local dir library
    for dir in "$STEAM_DIR/compatibilitytools.d"/*/; do
        if [ -f "$dir/proton" ]; then
            echo "$(basename "$dir")=${dir%/}"
        fi
    done
    # Steam keeps its own Proton versions next to the games, in each of its library folders.
    while IFS= read -r library; do
        for dir in "$library/steamapps/common"/Proton*/; do
            if [ -f "$dir/proton" ]; then
                echo "$(basename "$dir") (Steam)=${dir%/}"
            fi
        done
    done < <(sed -n 's/^\s*"path"\s*"\(.*\)"\s*$/\1/p' "$STEAM_DIR/steamapps/libraryfolders.vdf" 2>/dev/null)
}

cmd_proton() {  # which Proton runs .exe files (proton-run reads ~/.config/hypr-rice/proton.conf)
    local conf="$HOME/.config/hypr-rice/proton.conf"
    local current choice found=()
    local options=("Автоматически: последняя UMU-Proton=auto")
    mapfile -t found < <(proton_versions)
    options+=("${found[@]}")
    step "Proton для .exe"
    current=$(sed -n 's/^proton=//p' "$conf" 2>/dev/null || true)
    if [ -n "$current" ]; then
        info "сейчас: $(basename "$current")"
    else
        info "сейчас: автоматически (последняя UMU-Proton)"
    fi
    [ ${#options[@]} -gt 1 ] || info "других версий нет; поставь их в ProtonPlus (раздел Steam), они появятся здесь"
    have_tty || die "нужен терминал: rice proton спрашивает, какую версию взять"
    choice=$(choose_one "Какой Proton запускает .exe?" "${options[@]}") || return 0
    mkdir -p "$(dirname "$conf")"
    if [ "$choice" = auto ]; then
        rm -f "$conf"
        ok "автоматически: последняя UMU-Proton"
    else
        echo "proton=$choice" > "$conf"
        ok "$(basename "$choice")"
    fi
}
