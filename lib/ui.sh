# Talking to the user: output, questions, menus, sudo; and reading the rice's list files.

if [ -t 1 ]; then
    B=$'\e[1m'; RED=$'\e[31m'; GRN=$'\e[32m'; YEL=$'\e[33m'; CYN=$'\e[36m'; R=$'\e[0m'
else
    B=; RED=; GRN=; YEL=; CYN=; R=
fi
step() { printf '\n%s==>%s %s%s%s\n' "$CYN" "$R" "$B" "$*" "$R"; }
info() { printf '    %s\n' "$*"; }
ok()   { printf '    %s✓%s %s\n' "$GRN" "$R" "$*"; }
warn() { printf '    %s!%s %s\n' "$YEL" "$R" "$*" >&2; WARNINGS+=("$*"); }
die()  { printf '\n%sОшибка:%s %s\n' "$RED" "$R" "$*" >&2; exit 1; }
WARNINGS=()  # every warn of this run, repeated by finish

finish() {  # the end of a command that changed things: what went wrong on the way
    step "Готово"
    [ "$DO_BACKUP" = 1 ] && info "Старые файлы: $BACKUP"
    if [ ${#WARNINGS[@]} -gt 0 ]; then
        printf '    %sПредупреждения:%s\n' "$YEL" "$R"
        printf '      - %s\n' "${WARNINGS[@]}"
        info "Если что-то не так: rice report — и пришли файл ~/rice-report.txt"
    fi
}

# curl | bash: stdin is the script itself, so questions are read from the terminal.
have_tty() { { : </dev/tty; } 2>/dev/null; }
ask() {  # ask "question" default(y|n) -> returns 0 for yes
    local q=$1 def=${2:-n} a hint
    [ "$def" = y ] && hint="[Y/n]" || hint="[y/N]"
    if [ -n "${RICE_ASSUME:-}" ]; then
        info "$q $hint ${RICE_ASSUME} (RICE_ASSUME)"
        [[ $RICE_ASSUME =~ ^[Yy] ]]
        return
    fi
    if ! have_tty; then
        [ "$def" = y ]
        return
    fi
    read -r -p "    $q $hint " a </dev/tty || a=""
    a=${a:-$def}
    [[ $a =~ ^[YyДд] ]]
}

need_sudo() {
    [ "$(id -u)" -ne 0 ] || die "запускай от обычного пользователя, не от root (sudo спросят сам)"
    if ! sudo -n true 2>/dev/null; then
        info "Нужны права администратора, введи пароль sudo:"
        if have_tty; then sudo -v </dev/tty; else sudo -v; fi || die "sudo не сработал"
    fi
    # Keep the sudo timestamp fresh for the whole (long) run.
    if [ -z "${SUDO_KEEPER:-}" ]; then
        ( while kill -0 $$ 2>/dev/null; do sudo -n true 2>/dev/null; sleep 50; done ) &
        SUDO_KEEPER=$!
        trap 'kill $SUDO_KEEPER 2>/dev/null || true' EXIT
    fi
}

# A comment starts a line or follows a space: a "#" inside an entry (appimage:URL#sha256=…) is the entry's.
list() {  # entries of a list file, without comments
    grep -v '^[[:space:]]*#' "$1" | sed 's/[[:space:]]\+#.*//' | grep -v '^[[:space:]]*$'
}
trim() { local v=$1; v=${v#"${v%%[![:space:]]*}"}; printf '%s' "${v%"${v##*[![:space:]]}"}"; }

# ---------- menus: gum when it can be had, numbered lists otherwise ----------

# Pinned and checksummed: gum 2.x toggles only with "x", 0.17 also with space. The checksum is the
# x86_64 build's; on other machines, and wherever GitHub is unreachable, menus are numbered lists.
GUM_VERSION=0.17.0
GUM_SHA256=69ee169bd6387331928864e94d47ed01ef649fbfe875baed1bbf27b5377a6fdb
GUM=""
GUM_MISSING=0  # gum could not be had: not tried again in this run
fetch_gum() {
    [ -n "$GUM" ] && return 0
    [ "$GUM_MISSING" = 0 ] || return 1
    local dir="$CACHE/gum-$GUM_VERSION" tgz
    if [ "$(uname -m)" != x86_64 ]; then
        info "меню gum есть только для x86_64, выбор — номерами" >&2
        GUM_MISSING=1
        return 1
    fi
    if [ ! -x "$dir/gum" ]; then
        mkdir -p "$dir"
        tgz="$dir/gum.tgz"
        if ! curl -fsSL --max-time 60 -o "$tgz" \
                "https://github.com/charmbracelet/gum/releases/download/v$GUM_VERSION/gum_${GUM_VERSION}_Linux_x86_64.tar.gz" \
            || ! echo "$GUM_SHA256  $tgz" | sha256sum -c --quiet - >/dev/null 2>&1 \
            || ! tar -xzf "$tgz" -C "$dir" --strip-components=1; then
            rm -rf "$dir"
            info "меню gum не скачалось с GitHub, выбор — номерами" >&2
            GUM_MISSING=1
            return 1
        fi
    fi
    GUM="$dir/gum"
}
GUM_STYLE=(--header.foreground "#d97757" --cursor.foreground "#e8a383" --selected.foreground "#8fa876")

# Menus. Options are "label=value"; the chosen values are printed, one per line. With gum the list
# is navigated with arrows; without it (see fetch_gum) it is numbered and answered with numbers.
# Both draw on the terminal, so the caller's $(...) captures only the values.
choose_one() {  # choose_one HEADER OPTION...: fails when nothing was chosen
    local header=$1 n
    shift
    have_tty || return 1
    if fetch_gum; then
        "$GUM" choose --height "$(gum_height $#)" --header "$header" --cursor "› " "${GUM_STYLE[@]}" \
            --label-delimiter="=" "$@" </dev/tty
        return
    fi
    numbered_list "$header" "" "$@"
    read -r -p "    Номер, Enter — отмена: " n </dev/tty || return 1
    option_value "$n" "$@"
}

choose_many() {  # choose_many HEADER SELECTED OPTION...; SELECTED: labels ticked from the start, comma-separated
    local header=$1 selected=$2 nums n
    shift 2
    have_tty || return 1
    if fetch_gum; then
        "$GUM" choose --no-limit --height "$(gum_height $#)" --label-delimiter="=" \
            --header "$header  пробел — отметить · enter — готово" \
            --selected "$selected" --cursor "› " --cursor-prefix "[ ] " --selected-prefix "[✓] " \
            --unselected-prefix "[ ] " "${GUM_STYLE[@]}" "$@" </dev/tty
        return
    fi
    numbered_list "$header" "$selected" "$@"
    read -r -p "    Номера через пробел (0 — ничего), Enter — оставить отмеченное: " nums </dev/tty || return 1
    if [ -z "$nums" ]; then
        local option
        for option in "$@"; do
            [[ ",$selected," == *",${option%=*},"* ]] && echo "${option##*=}"
        done
        return 0
    fi
    for n in $nums; do option_value "$n" "$@" || true; done
}

gum_height() { local rows=$(($1 + 2)); echo $((rows < 22 ? rows : 22)); }

numbered_list() {  # numbered_list HEADER SELECTED OPTION...: the fallback menu, on the terminal
    local header=$1 selected=$2 i=1 option mark=""
    shift 2
    printf '    %s\n' "$header" >&2
    for option in "$@"; do
        if [ -n "$selected" ]; then
            mark="[ ] "
            [[ ",$selected," == *",${option%=*},"* ]] && mark="[✓] "
        fi
        printf '      %2d) %s%s\n' "$i" "$mark" "${option%=*}" >&2
        i=$((i + 1))
    done
}

option_value() {  # option_value N OPTION...: the value of option number N
    local n=$1
    shift
    if ! [[ $n =~ ^[0-9]+$ ]] || [ "$n" -lt 1 ] || [ "$n" -gt $# ]; then
        return 1
    fi
    local option=${!n}
    echo "${option##*=}"
}
