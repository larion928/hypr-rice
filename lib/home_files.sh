# The rice's files in ~: home/ of the repo copied over, what it replaces backed up, files merged into
# the user's own, and the list of what was put there (for updates and uninstall).

# Files that are merged into the user's own instead of replacing them.
MERGED_JSON=(".config/Code - OSS/User/settings.json")
# The user's own version of each merged file from before the rice's first merge (or a PATH.absent mark
# when there was none): uninstall puts it back.
ORIGINALS="$HOME/.config/hypr-rice/originals"
# Every file copy_rice_files put in ~: an update removes those the new version no longer ships, and
# uninstall removes what it lists. Nothing else in ~ is ever removed this way.
MANIFEST="$HOME/.config/hypr-rice/installed-files"

copy_rice_files() {  # home/ of the rice into ~; MODE, DO_BACKUP and FOREIGN_CONFIGS from inspect_existing_desktop
    local files=() ours=() theirs=() kept=() f
    mapfile -d '' files < <(cd "$SRC/home" && find . -type f -print0 -o -type l -print0)
    files=("${files[@]#./}")
    # Decided before anything is copied: whether the user had a file of their own is read from ~.
    for f in "${files[@]}"; do
        if keep_theirs "$f"; then theirs+=("$f"); else ours+=("$f"); fi
    done
    [ "$DO_BACKUP" = 1 ] && back_up_replaced "${ours[@]}"
    # Merged files: ours on top of the user's own (Code-OSS keeps its other settings); a user's file
    # is never copied over, even when it cannot be merged.
    for f in "${MERGED_JSON[@]}"; do
        merge_user_file "$f"
        [ -f "$HOME/$f" ] && kept+=("$f")
    done
    copy_home_except "${theirs[@]}" "${kept[@]}"
    for f in "${MERGED_JSON[@]}"; do put_merged_file "$f"; done
    remove_stale_files
    write_manifest "${ours[@]}"
    if printf '%s\n' "${theirs[@]}" | grep -q '^\.config/fish/'; then info "fish: оставлен твой конфиг"; fi
    for f in "${ours[@]}"; do
        [ -f "$HOME/$f" ] && grep -Iq "__HOME__" "$HOME/$f" 2>/dev/null && fill_home -i "$HOME/$f"
    done
    chmod +x "$HOME"/.local/bin/* "$HOME"/.config/hypr-rice/waybar/scripts/* "$HOME"/.config/hypr/scripts/*.py \
             "$HOME"/.config/hypr/scripts/ru-date "$HOME"/.claude/statusline.sh 2>/dev/null || true
    load_apps
    remove_files_of_missing_programs
    install_manager_entry
    ok "${#files[@]} файлов"
    write_machine_files
    xdg-user-dirs-update 2>/dev/null || true
    mkdir -p "$HOME/Pictures/screenshots"
}

keep_theirs() {  # coexist mode: a path of ours that would overwrite the other desktop's config
    [ "$MODE" = coexist ] || return 1
    case "$1" in
        .config/fish/*) [ -e "$HOME/.config/fish/config.fish" ] ;;
        .config/Code\ -\ OSS/User/keybindings.json) [ -e "$HOME/$1" ] ;;
        *) return 1 ;;
    esac
}

is_merged() { printf '%s\n' "${MERGED_JSON[@]}" | grep -qxF "$1"; }

back_up_replaced() {  # back_up_replaced PATH...: what the rice replaces goes to $BACKUP
    local p f
    mkdir -p "$BACKUP"
    # Replace mode: foreign rice configs leave entirely. Coexist mode: only a foreign Hyprland
    # config does (two rices cannot share one Hyprland), everything else stays put.
    for p in "${FOREIGN_CONFIGS[@]}"; do
        case "$p" in
            "$HOME/.config/hypr") ;;  # handled below, the machine and user files stay
            *) [ "$MODE" = replace ] && mv "$p" "$BACKUP/" ;;
        esac
    done
    if [ -d "$HOME/.config/hypr" ]; then
        mkdir -p "$BACKUP/hypr"
        find "$HOME/.config/hypr" -mindepth 1 -maxdepth 1 \
            ! -name monitors.lua ! -name devices.lua ! -name binds-user.lua ! -name user.lua -exec mv -t "$BACKUP/hypr/" {} +
    fi
    for f in "$@"; do
        [ -e "$HOME/$f" ] || continue
        mkdir -p "$BACKUP/home/$(dirname "$f")"
        cp -a "$HOME/$f" "$BACKUP/home/$f"
        is_merged "$f" || rm -f "$HOME/$f"
    done
    ok "старое → $BACKUP"
}

copy_home_except() {  # copy_home_except PATH...: home/ of the rice into ~, but for these paths
    local excl=() path theme
    for path in "$@"; do excl+=(--exclude="./$path"); done
    # Themes the user removed (Alt+F2 → Тема) stay removed until they bring them back there.
    while IFS= read -r theme; do
        if [ -n "$theme" ]; then
            excl+=(--exclude="./.config/hypr/themes/$theme")
        fi
    done < <(cat "$HOME/.config/hypr-rice/removed-themes" 2>/dev/null)
    tar -C "$SRC/home" -cf - "${excl[@]}" . | tar -C "$HOME" -xf -
}

# Code - OSS writes settings.json as JSONC (comments, trailing commas), which jq refuses. Prints
# USER's settings with OURS on top, nested objects merged; fails, printing nothing, if USER does not
# parse. The comments do not survive: the file before is kept as PATH.rice-backup (put_merged_file).
merge_jsonc() {  # merge_jsonc USER OURS
    python3 - "$1" "$2" <<'PY'
import json, re, sys

STRING = r'"(?:\\.|[^"\\])*"'
COMMENT = re.compile(STRING + r'|//[^\n]*|/\*.*?\*/', re.S)
TRAILING_COMMA = re.compile(STRING + r'|,(?=\s*[}\]])')

def strip(text):
    keep_strings = lambda match: match.group(0) if match.group(0).startswith('"') else ""
    return TRAILING_COMMA.sub(keep_strings, COMMENT.sub(keep_strings, text))

def merge(base, top):
    for key, value in top.items():
        if isinstance(value, dict) and isinstance(base.get(key), dict):
            merge(base[key], value)
        else:
            base[key] = value
    return base

with open(sys.argv[1], encoding="utf-8") as user_file, open(sys.argv[2], encoding="utf-8") as ours_file:
    user = json.loads(strip(user_file.read()) or "{}")
    ours = json.loads(ours_file.read())
if not isinstance(user, dict):
    sys.exit(1)
print(json.dumps(merge(user, ours), indent=2, ensure_ascii=False))
PY
}

merge_user_file() {  # merge_user_file PATH: the merged ~/PATH ready as ~/PATH.rice-tmp
    local path=$1 user="$HOME/$1"
    if [ ! -e "$ORIGINALS/$path" ] && [ ! -e "$ORIGINALS/$path.absent" ]; then
        mkdir -p "$(dirname "$ORIGINALS/$path")"
        if [ -f "$user" ]; then cp -a "$user" "$ORIGINALS/$path"; else : > "$ORIGINALS/$path.absent"; fi
    fi
    [ -f "$user" ] || return 0
    if ! merge_jsonc "$user" "$SRC/home/$path" > "$user.rice-tmp" 2>/dev/null; then
        rm -f "$user.rice-tmp"
        warn "$path не разобран: оставлен как есть, настройки райса в него не добавлены"
    fi
}

put_merged_file() {  # put_merged_file PATH: ~/PATH.rice-tmp in place of ~/PATH, the old one kept when they differ
    local user="$HOME/$1"
    [ -f "$user.rice-tmp" ] || return 0
    if cmp -s "$user.rice-tmp" "$user"; then
        rm -f "$user.rice-tmp"
        return 0
    fi
    cp -a "$user" "$user.rice-backup"
    mv "$user.rice-tmp" "$user"
}

remove_stale_files() {  # what the previous version put in ~ and this one no longer ships
    local path
    [ -f "$MANIFEST" ] || return 0
    while IFS= read -r path; do
        if [ ! -e "$SRC/home/$path" ] && [ ! -L "$SRC/home/$path" ]; then
            rm -f "$HOME/$path"
        fi
    done < "$MANIFEST"
}

write_manifest() {  # write_manifest PATH...: the files of home/ that were copied to ~
    local f
    mkdir -p "$(dirname "$MANIFEST")"
    for f in "$@"; do
        is_merged "$f" || printf '%s\n' "$f"
    done > "$MANIFEST"
}

installed_rice_files() {  # the files of ~ the rice put there, relative to ~
    if [ -f "$MANIFEST" ]; then
        cat "$MANIFEST"
        return
    fi
    # Installs from before the list: what this version ships, the merged files aside.
    local f
    while IFS= read -r -d '' f; do
        f=${f#./}
        is_merged "$f" || printf '%s\n' "$f"
    done < <(cd "$SRC/home" && find . -type f -print0 -o -type l -print0)
}

restore_merged_files() {  # each merged file back to the user's own from before the rice
    local path saved
    for path in "${MERGED_JSON[@]}"; do
        saved="$ORIGINALS/$path"
        if [ -f "$saved" ]; then
            [ -f "$HOME/$path" ] && cp -a "$HOME/$path" "$HOME/$path.rice-backup"
            mkdir -p "$(dirname "$HOME/$path")"
            mv "$saved" "$HOME/$path"
            ok "$path: возвращён твой прежний (с райсом — $path.rice-backup)"
        elif [ -e "$saved.absent" ] && cmp -s "$HOME/$path" "$SRC/home/$path"; then
            rm -f "$HOME/$path"
        elif [ -e "$HOME/$path" ]; then
            info "$path оставлен: в нём твои настройки вместе с настройками райса"
        fi
        rm -f "$saved.absent"
    done
    find "$ORIGINALS" -depth -type d -empty -delete 2>/dev/null || true
}

install_manager_entry() {  # the manager itself in ~/.local/bin, and a launcher entry for it
    ln -sfn "$SRC/rice" "$HOME/.local/bin/rice"
    write_desktop_entry "$HOME/.local/share/applications/hypr-rice-manager.desktop" "Name=Менеджер райса" \
        "Comment=Программы, обновление и починка hypr-rice" "Exec=kitty -e rice" "Icon=preferences-desktop" \
        "Categories=Settings;"
}

write_machine_files() {  # this machine's monitors and input devices: written once, never overwritten
    if [ ! -f "$HOME/.config/hypr/monitors.lua" ]; then
        printf '%s\n' "-- Monitors of this machine (not part of hypr-rice). Every output at its preferred mode;" \
            "-- name outputs here for fixed layouts, see \`hyprctl monitors\`." \
            'hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })' \
            > "$HOME/.config/hypr/monitors.lua"
    fi
    if [ ! -f "$HOME/.config/hypr/devices.lua" ]; then
        printf '%s\n' "-- Per-device input settings. mouse-sens and rice mouse-test rewrite the lines below," \
            "-- keep each hl.device() call on a single line." > "$HOME/.config/hypr/devices.lua"
    fi
}
