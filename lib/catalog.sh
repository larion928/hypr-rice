# The program catalog (packages/apps.txt): what is installed, picking, installing and removing programs.
# Its header lists the kinds of sources a program has; each kind is handled below.

APP_IDS=()
declare -gA APP_GROUP APP_NAME APP_SRC  # -g: global even when tests source this file from a function
load_apps() {
    local id group name src
    APP_IDS=()
    while IFS='|' read -r id group name src; do
        id=$(trim "$id")
        APP_IDS+=("$id")
        APP_GROUP[$id]=$(trim "$group")
        APP_NAME[$id]=$(trim "$name")
        APP_SRC[$id]=$(trim "$src")
    done < <(list "$SRC/packages/apps.txt")
}

app_sources() {  # app_sources ID KIND: the values of ID's sources of KIND (repo: the bare package names)
    local tok kind
    for tok in ${APP_SRC[$1]}; do
        case "$tok" in
            browser) kind=browser ;;
            *:*) kind=${tok%%:*} ;;
            *) kind=repo ;;
        esac
        if [ "$kind" = "$2" ]; then echo "${tok#"$kind:"}"; fi
    done
}

# The packages of app ID from the repos and the AUR ("aur:" kept), in catalog order: the first one is
# the program itself, the ones after it are its helpers.
app_packages() {
    local tok
    for tok in ${APP_SRC[$1]}; do
        case "$tok" in
            browser) ;;
            aur:*) echo "$tok" ;;
            *:*) ;;
            *) echo "$tok" ;;
        esac
    done
}

# Installed packages and Flatpak apps, read once and kept until something is installed or removed:
# asking pacman package by package took seconds for the whole catalog.
declare -gA INSTALLED=()
INSTALLED_READ=0
is_installed() {  # is_installed PACKAGE, or flatpak:ID
    if [ "$INSTALLED_READ" = 0 ]; then
        INSTALLED=()
        local name
        while read -r name; do INSTALLED[$name]=1; done < <(pacman -Qq 2>/dev/null)
        while read -r name; do INSTALLED[flatpak:$name]=1; done < <(flatpak list --app --columns=application 2>/dev/null)
        INSTALLED_READ=1
    fi
    [ -n "${INSTALLED[$1]:-}" ]
}
forget_installed() { INSTALLED_READ=0; }

# Every package of app ID is installed (pacman, AUR, Flatpak, AppImage); its files are not checked.
# This and app_installed run for the whole catalog on every menu, so they read APP_SRC in place
# instead of through app_sources, which costs a subshell per call.
app_packages_installed() {
    local tok
    for tok in ${APP_SRC[$1]}; do
        case "$tok" in
            file:*|release:*|hook:*|browser) ;;
            appimage:*) [ -x "$HOME/Applications/$1.AppImage" ] || return 1 ;;
            flatpak:*) is_installed "$tok" || return 1 ;;
            path:*) [ -e "${tok#path:}" ] || return 1 ;;
            dep:*) is_installed "${tok#dep:}" || return 1 ;;
            *) is_installed "${tok#aur:}" || return 1 ;;
        esac
    done
}

# App ID is fully present: its packages and the files the rice copies for it.
app_installed() {
    app_packages_installed "$1" || return 1
    local tok
    for tok in ${APP_SRC[$1]}; do
        [[ $tok == file:* || $tok == release:* ]] || continue
        [ -e "$HOME/${tok#*:}" ] || return 1
    done
}

# ---------- picking ----------

# The programs picked in this run (pick_apps). install_apps and remove_apps get them as arguments;
# copy_rice_files keeps the files of a picked program even before its packages are in.
PICKED=()
picked() { local id; for id in "${PICKED[@]}"; do [ "$id" = "$1" ] && return 0; done; return 1; }

# The catalog lines pick_apps offers ("group · name=id"): to install, what is not installed yet; to
# remove, what is.
catalog_choices() {
    local mode=$1 id
    for id in "${APP_IDS[@]}"; do
        if app_installed "$id"; then
            [ "$mode" = remove ] || continue
        elif [ "$mode" = remove ]; then
            continue
        fi
        echo "${APP_GROUP[$id]} · ${APP_NAME[$id]}=$id"
    done
}

# pick_apps MODE: sets PICKED. "install": only what is not installed yet is offered (RICE_APPS
# answers instead); "remove": only installed programs are offered.
pick_apps() {
    local mode=${1:-install} id opts=()
    PICKED=()
    if [ "$mode" = install ] && [ -n "${RICE_APPS:-}" ]; then
        case "$RICE_APPS" in
            all) PICKED=("${APP_IDS[@]}") ;;
            none) ;;
            *) IFS=', ' read -r -a PICKED <<<"$RICE_APPS" ;;  # "steam,lutris" and "steam, lutris" alike
        esac
        info "программы (RICE_APPS): ${PICKED[*]:-нет}"
    else
        have_tty || { info "нет терминала, программы не выбираю"; return; }
        mapfile -t opts < <(catalog_choices "$mode")
        if [ ${#opts[@]} -eq 0 ]; then
            if [ "$mode" = remove ]; then info "из каталога ничего не установлено"; else info "всё из каталога уже установлено"; fi
            return
        fi
        local header="Какие программы поставить?"
        [ "$mode" = remove ] && header="Какие программы удалить?"
        mapfile -t PICKED < <(choose_many "$header" "" "${opts[@]}" || true)
    fi
    local clean=()
    for id in "${PICKED[@]}"; do
        [ -n "$id" ] || continue
        if [ -n "${APP_NAME[$id]:-}" ]; then
            clean+=("$id")
        else
            warn "нет такой программы в каталоге: $id (список — packages/apps.txt)"
        fi
    done
    PICKED=("${clean[@]}")
    if [ ${#PICKED[@]} -gt 0 ]; then
        ok "выбрано: $(app_names "${PICKED[@]}")"
    else
        ok "ничего не выбрано"
    fi
}

app_names() {  # app_names ID...: their names shown, comma-separated
    local id
    for id in "$@"; do printf '%s, ' "${APP_NAME[$id]}"; done | sed 's/, $//'
}

# ---------- installing ----------

install_apps() {  # install_apps ID...
    local id pkg packages=() repo_pk=() helper_pk=() aur_pk=() aur_helper_pk=() flat=() hooks=() browsers=() path source appimages=0
    [ $# -gt 0 ] || return 0
    for id in "$@"; do
        mapfile -t packages < <(app_packages "$id")
        for pkg in "${packages[@]}"; do
            if [ "$pkg" = "${packages[0]}" ]; then
                if [[ $pkg == aur:* ]]; then aur_pk+=("${pkg#aur:}"); else repo_pk+=("$pkg"); fi
            elif [[ $pkg == aur:* ]]; then
                aur_helper_pk+=("${pkg#aur:}")
            else
                helper_pk+=("$pkg")
            fi
        done
        mapfile -t -O "${#repo_pk[@]}" repo_pk < <(app_sources "$id" dep)
        mapfile -t -O "${#flat[@]}" flat < <(app_sources "$id" flatpak)
        mapfile -t -O "${#hooks[@]}" hooks < <(app_sources "$id" hook)
        [ -z "$(app_sources "$id" browser)" ] || browsers+=("$id")
        [ -z "$(app_sources "$id" appimage)" ] || appimages=1
        # A rice file that only ships with this program (put back if it was dropped).
        for path in $(app_sources "$id" file); do
            [ -e "$HOME/$path" ] || install -Dm755 "$SRC/home/$path" "$HOME/$path"
        done
        for path in $(app_sources "$id" release); do install_release_file "$path" || true; done
    done
    # Vulkan for 32-bit games: Steam's lib32-vulkan-driver has several providers and
    # --noconfirm would just take the first one, which is wrong for most GPUs.
    if printf '%s\n' "$@" | grep -qx steam; then mapfile -t -O "${#repo_pk[@]}" repo_pk < <(gpu_vulkan); fi
    [ ${#flat[@]} -eq 0 ] || repo_pk+=(flatpak)
    [ "$appimages" = 0 ] || repo_pk+=(fuse2)
    if printf '%s\n' "${repo_pk[@]}" "${helper_pk[@]}" | grep -qE '^(steam|umu-launcher|lib32-.*)$'; then enable_multilib; fi

    [ ${#repo_pk[@]} -eq 0 ] || pac -S --needed "${repo_pk[@]}" || warn "часть программ из репозиториев не встала"
    # Helpers come in as dependencies, so they go with the program; one the user installed on their
    # own is skipped by --needed and stays theirs.
    [ ${#helper_pk[@]} -eq 0 ] || pac -S --needed --asdeps "${helper_pk[@]}" || warn "часть дополнительных пакетов не встала"
    [ ${#aur_pk[@]} -eq 0 ] || aur_install "${aur_pk[@]}" || true
    [ ${#aur_helper_pk[@]} -eq 0 ] || aur_install_as_deps "${aur_helper_pk[@]}"
    if [ ${#flat[@]} -gt 0 ]; then
        flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo \
            && flatpak install --user -y --noninteractive flathub "${flat[@]}" >/dev/null \
            || warn "flatpak: не встало ${flat[*]}"
    fi
    for id in "$@"; do
        for source in $(app_sources "$id" appimage); do install_appimage "$id" "$source" || true; done
    done
    for pkg in "${hooks[@]}"; do run_hook "$pkg"; done
    set_default_browser "${browsers[@]}"
    forget_installed
    ok "программ: $#"
}

gpu_vulkan() {  # the Vulkan driver packages, 64- and 32-bit, of every GPU in the machine
    local v
    for v in /sys/class/drm/card*/device/vendor; do
        case "$(cat "$v" 2>/dev/null)" in
            0x1002) echo "vulkan-radeon lib32-vulkan-radeon" ;;
            0x8086) echo "vulkan-intel lib32-vulkan-intel" ;;
            0x10de) echo "nvidia-utils lib32-nvidia-utils" ;;
            0x1af4) echo "vulkan-virtio lib32-vulkan-virtio" ;;
        esac
    done | tr ' ' '\n' | sort -u
}

install_appimage() {  # install_appimage ID SOURCE; SOURCE is "URL#sha256=HEX": a pinned version
    local id=$1 url=${2%%#*} want=${2##*#sha256=} dest="$HOME/Applications/$1.AppImage"
    if [ "$want" = "$2" ]; then
        warn "${APP_NAME[$id]}: в packages/apps.txt нет контрольной суммы (#sha256=), не ставлю"
        return 1
    fi
    download_verified "$url" "$want" "$dest" || return 1
    chmod +x "$dest"
    write_desktop_entry "$HOME/.local/share/applications/hypr-rice-$id.desktop" \
        "Name=${APP_NAME[$id]}" "Exec=$dest" "Icon=applications-games" "Categories=Game;"
    ok "${APP_NAME[$id]} → ~/Applications/$id.AppImage"
}

set_default_browser() {  # set_default_browser ID...: the first one, when no default is set (Alt+B opens it)
    [ $# -gt 0 ] || return 0
    [ -z "$(xdg-settings get default-web-browser 2>/dev/null)" ] || return 0
    local file
    file=$(app_desktop_file "$1" || true)
    [ -n "$file" ] && xdg-settings set default-web-browser "$file" 2>/dev/null && ok "браузер по умолчанию: ${APP_NAME[$1]}"
    return 0
}

app_desktop_file() {  # first .desktop file an installed app ships
    local tok f
    for tok in ${APP_SRC[$1]}; do
        case "$tok" in
            flatpak:*) f="${tok#flatpak:}.desktop"; [ -e "/var/lib/flatpak/exports/share/applications/$f" ] \
                           || [ -e "$HOME/.local/share/flatpak/exports/share/applications/$f" ] && { echo "$f"; return; } ;;
            hook:*|browser|file:*|release:*|appimage:*|path:*|dep:*) ;;
            *) f=$(pacman -Qlq "${tok#aur:}" 2>/dev/null | grep -m1 '/usr/share/applications/.*\.desktop$') \
                   && { basename "$f"; return; } ;;
        esac
    done
}

# Called as `hook || warn`, a hook runs with set -e ignored (bash's rule for anything left of ||):
# each of its steps that may fail ends it with `|| return 1` explicitly, or a failure midway
# would go unnoticed and the steps after it would run anyway. The same holds for tuning_*_on/off.
# The hooks are in lib/hooks/, one file each with its unhook.
run_hook() { "hook_${1//-/_}" || warn "не отработал шаг $1"; }
run_unhook() {  # the undo of a setup step, for the steps that have one
    local undo="unhook_${1//-/_}"
    if declare -F "$undo" >/dev/null; then "$undo"; fi
}

# An update may change what a program's setup step does, so it runs again for what is installed.
rerun_installed_hooks() {
    local id hook
    for id in "${APP_IDS[@]}"; do
        app_installed "$id" || continue
        for hook in $(app_sources "$id" hook); do run_hook "$hook"; done
    done
}

# Files that belong to programs that are not installed (neoHtop, ...) leave ~ after a copy of the rice.
remove_files_of_missing_programs() {
    local id path
    for id in "${APP_IDS[@]}"; do
        if picked "$id" || app_packages_installed "$id"; then
            continue
        fi
        for path in $(app_sources "$id" file); do rm -f "$HOME/$path"; done
    done
}

# ---------- prebuilt files of the GitHub release ----------

# Prebuilt files of the rice too big for git (neoHtop with the rice's themes built in) are assets of
# the GitHub release "files", named <file>-<first 12 characters of its sha256>; sync.sh uploads them.
# Their checksums are in packages/release.sha256 in the signed repo, so a file changed on GitHub
# is refused.
RELEASE_URL="https://github.com/larion928/hypr-rice/releases/download/files"

release_sha256() {  # release_sha256 PATH: the checksum the repo expects for ~/PATH
    awk -v path="$1" '$2 == path {print $1}' "$SRC/packages/release.sha256"
}

install_release_file() {  # install_release_file PATH: puts the expected file at ~/PATH
    local path=$1 want dest="$HOME/$1"
    want=$(release_sha256 "$path")
    [ -n "$want" ] || { warn "$path: нет контрольной суммы в packages/release.sha256"; return 1; }
    if [ -f "$dest" ] && [ "$(file_sha256 "$dest")" = "$want" ]; then
        return 0
    fi
    download_verified "$RELEASE_URL/$(basename "$path")-${want:0:12}" "$want" "$dest" || return 1
    chmod 755 "$dest"
}

# After an update, installed programs get their prebuilt files of the new version.
update_release_files() {
    local id path
    for id in "${APP_IDS[@]}"; do
        for path in $(app_sources "$id" release); do
            [ -e "$HOME/$path" ] || continue
            install_release_file "$path" || true
        done
    done
}

# ---------- removing ----------

remove_apps() {  # remove_apps ID...: packages, flatpaks, AppImages, files and setup steps
    local id pkg packages=() own=() helpers=() flat=() path hook
    for id in "$@"; do
        mapfile -t packages < <(app_packages "$id")
        for pkg in "${packages[@]}"; do
            pkg=${pkg#aur:}
            if [ "$pkg" != "${packages[0]#aur:}" ]; then
                helpers+=("$pkg")
            elif pacman -Qq "$pkg" >/dev/null 2>&1; then
                own+=("$pkg")
            fi
        done
        mapfile -t -O "${#flat[@]}" flat < <(app_sources "$id" flatpak)
        if [ -n "$(app_sources "$id" appimage)" ]; then
            rm -f "$HOME/Applications/$id.AppImage" "$HOME/.local/share/applications/hypr-rice-$id.desktop"
        fi
        for path in $(app_sources "$id" file) $(app_sources "$id" release); do rm -f "$HOME/$path"; done
        for hook in $(app_sources "$id" hook); do run_unhook "$hook"; done
    done
    # The program's own package, with its dependencies nothing else needs.
    [ ${#own[@]} -eq 0 ] || sudo pacman -Rs --noconfirm "${own[@]}" || warn "часть пакетов не удалилась (их требуют другие)"
    # Its helpers only once they are orphans: installed as dependencies and needed by nothing now.
    # One the user installed on purpose is explicit, never an orphan, and stays.
    local orphans=()
    mapfile -t orphans < <(printf '%s\n' "${helpers[@]}" | grep -xF -f <(pacman -Qdtq 2>/dev/null) || true)
    [ ${#orphans[@]} -eq 0 ] || sudo pacman -Rs --noconfirm "${orphans[@]}" || warn "часть дополнительных пакетов не удалилась"
    [ ${#flat[@]} -eq 0 ] || flatpak uninstall --user -y --noninteractive "${flat[@]}" >/dev/null || true
    forget_installed
    ok "удалено: $#"
}

# ---------- commands ----------

cmd_apps() {
    need_sudo
    load_apps
    step "Программы"
    pick_apps install
    # Ticked but already present = nothing to do; only what is missing gets installed.
    local id todo=()
    for id in "${PICKED[@]}"; do app_installed "$id" || todo+=("$id"); done
    [ ${#todo[@]} -gt 0 ] || { ok "всё отмеченное уже установлено"; return; }
    pkg_repo_enabled || setup_pkg_repo
    install_apps "${todo[@]}"
    # Themes for apps that just appeared (Code-OSS, AyuGram, ...).
    python3 "$HOME/.config/hypr/scripts/themegen.py" build >/dev/null 2>&1 || true
    finish
}

cmd_remove() {
    need_sudo
    load_apps
    step "Удаление программ"
    pick_apps remove
    [ ${#PICKED[@]} -gt 0 ] || return 0
    ask "Удалить: $(app_names "${PICKED[@]}")?" n || return 0
    remove_apps "${PICKED[@]}"
    finish
}
