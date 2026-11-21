# rice: the program catalog (packages/apps.txt): installed or not, picking, installing, removing.

# The program menu offers to install only what is not installed, and to remove only what is.
test_catalog_choices() {
    load_rice
    APP_IDS=(firefox zen)
    declare -gA APP_GROUP=([firefox]=Браузеры [zen]=Браузеры) APP_NAME=([firefox]=Firefox [zen]="Zen Browser")
    declare -gA APP_SRC=([firefox]="firefox browser" [zen]="aur:zen-browser-bin browser")
    pacman() { [ "$1" = -Qq ] && echo zen-browser-bin; }
    [ "$(catalog_choices install)" = "Браузеры · Firefox=firefox" ] || fail "к установке предложено: $(catalog_choices install)"
    [ "$(catalog_choices remove)" = "Браузеры · Zen Browser=zen" ] || fail "к удалению предложено: $(catalog_choices remove)"
}

# An app counts as installed only with its files too; its packages alone are checked separately
# (an update keeps the files of a program that is installed).
test_app_installed_needs_files() {
    load_rice
    pacman() { [ "$1" = -Qq ] && printf '%s\n' demo-pkg demo-aur; }
    APP_SRC[demo]="demo-pkg aur:demo-aur file:.local/bin/demo"
    app_packages_installed demo || fail "пакеты стоят, но app_packages_installed говорит нет"
    app_installed demo && fail "файла нет, но app_installed говорит да"
    mkdir -p "$HOME/.local/bin"
    touch "$HOME/.local/bin/demo"
    app_installed demo || fail "всё на месте, но app_installed говорит нет"
}

# A prebuilt file from the GitHub release goes in only when its checksum is the one the signed
# repo lists; curl is faked to serve $HOME/served.
test_release_file_is_checked() {
    load_rice
    SRC=$HOME/src
    mkdir -p "$SRC/packages"
    echo genuine > "$HOME/genuine"
    echo "$(sha256sum < "$HOME/genuine" | cut -d' ' -f1)  .local/bin/tool" > "$SRC/packages/release.sha256"
    curl() {
        local out
        while [ $# -gt 0 ]; do [ "$1" = -o ] && out=$2; shift; done
        cp "$HOME/served" "$out"
    }

    echo forged > "$HOME/served"
    install_release_file .local/bin/tool 2>/dev/null && fail "подменённый файл принят"
    [ ! -e "$HOME/.local/bin/tool" ] || fail "подменённый файл остался на месте"

    cp "$HOME/genuine" "$HOME/served"
    install_release_file .local/bin/tool >/dev/null || fail "настоящий файл не принят"
    cmp -s "$HOME/.local/bin/tool" "$HOME/genuine" || fail "поставлен не тот файл"
    [ -x "$HOME/.local/bin/tool" ] || fail "файл не исполняемый"
}

# RICE_APPS takes ids with or without spaces after the commas; an unknown id is a warning, not a crash.
test_rice_apps_checked() {
    load_rice
    load_apps
    RICE_APPS="steam, no-such-app,lutris" pick_apps install >/dev/null 2>&1
    [ "${PICKED[*]}" = "steam lutris" ] || fail "выбрано: ${PICKED[*]}"
    printf '%s\n' "${WARNINGS[@]}" | grep -q no-such-app || fail "о неизвестной программе не предупреждено"
}

# A program's own package is installed as such, its helpers as dependencies; removing it takes its own
# package and only those helpers that became orphans: one the user installed on purpose stays.
test_program_helpers_kept_for_user() {
    load_rice
    APP_IDS=(archiver)
    APP_SRC[archiver]="file-roller 7zip unrar"
    APP_NAME[archiver]="Архиватор"
    pac() { echo "pac $*" >> "$HOME/calls"; }
    aur_install() { :; }
    install_apps archiver >/dev/null 2>&1
    grep -qx 'pac -S --needed file-roller' "$HOME/calls" && grep -qx 'pac -S --needed --asdeps 7zip unrar' "$HOME/calls" \
        || fail "установка: $(cat "$HOME/calls")"

    : > "$HOME/calls"
    pacman() {
        case "$1" in
            -Qq) return 0 ;;          # all three are installed
            -Qdtq) echo unrar ;;       # unrar came in with the program; 7zip the user installed themselves
            *) echo "pacman $*" >> "$HOME/calls" ;;
        esac
    }
    remove_apps archiver >/dev/null 2>&1
    [ "$(cat "$HOME/calls")" = "$(printf 'pacman -Rs --noconfirm file-roller\npacman -Rs --noconfirm unrar')" ] \
        || fail "удаление: $(cat "$HOME/calls")"
}

# A helper from the AUR comes in as a dependency too, so it goes with the program (ProtonPlus with
# Proton); one the user had already installed stays theirs.
test_aur_helpers_installed_as_deps() {
    load_rice
    APP_IDS=(proton)
    APP_SRC[proton]="umu-launcher aur:protonplus aur:mine"
    APP_NAME[proton]="Proton"
    local installed="$HOME/installed"
    echo mine > "$installed"
    pac() { :; }
    enable_multilib() { :; }
    aur_install() { printf '%s\n' "$@" >> "$installed"; echo "aur $*" >> "$HOME/calls"; }
    pacman() {
        case "$1" in
            -Qq) shift; grep -xF -f <(printf '%s\n' "$@") "$installed" ;;
            *) echo "pacman $*" >> "$HOME/calls" ;;
        esac
    }
    install_apps proton >/dev/null 2>&1
    grep -qx 'pacman -D --asdeps protonplus' "$HOME/calls" || fail "ProtonPlus не отмечен зависимостью: $(cat "$HOME/calls")"
}

# The catalog itself, read the way rice reads it: every AppImage reaches the installer with its checksum.
test_catalog_appimages_keep_checksum() {
    load_rice
    load_apps
    local id found=0
    for id in "${APP_IDS[@]}"; do
        [[ ${APP_SRC[$id]} == *appimage:* ]] || continue
        found=1
        [[ ${APP_SRC[$id]} =~ \#sha256=[0-9a-f]{64}$ ]] || fail "$id: контрольная сумма потерялась: ${APP_SRC[$id]}"
    done
    [ "$found" = 1 ] || fail "в каталоге не нашлось ни одного AppImage"
}

# An AppImage is pinned with its checksum in apps.txt: without one it is not downloaded, a file that
# does not match is not kept.
test_appimage_checked() {
    load_rice
    echo genuine > "$HOME/genuine"
    local sum
    sum=$(sha256sum < "$HOME/genuine" | cut -d' ' -f1)
    curl() {
        local out
        while [ $# -gt 0 ]; do [ "$1" = -o ] && out=$2; shift; done
        echo "curl" >> "$HOME/calls"
        cp "$HOME/served" "$out"
    }
    APP_NAME[game]=Game
    APP_SRC[game]="appimage:https://example.com/v1/game.AppImage"
    cp "$HOME/genuine" "$HOME/served"
    install_apps game >/dev/null 2>&1
    [ ! -e "$HOME/calls" ] && [ ! -e "$HOME/Applications/game.AppImage" ] || fail "скачан без контрольной суммы"

    APP_SRC[game]="appimage:https://example.com/v1/game.AppImage#sha256=$sum"
    echo forged > "$HOME/served"
    install_apps game >/dev/null 2>&1
    [ ! -e "$HOME/Applications/game.AppImage" ] || fail "подменённый файл принят"
    cp "$HOME/genuine" "$HOME/served"
    install_apps game >/dev/null 2>&1
    cmp -s "$HOME/Applications/game.AppImage" "$HOME/genuine" && [ -x "$HOME/Applications/game.AppImage" ] \
        || fail "настоящий файл не поставлен"
}
