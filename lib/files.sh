# Writing files: system files as root, launcher entries, checked downloads, the rice's own marks.

sudo_write() {  # sudo_write FILE: stdin into FILE, as root
    sudo tee "$1" >/dev/null
}

sudo_append() {  # sudo_append FILE: stdin at the end of FILE, as root
    sudo tee -a "$1" >/dev/null
}

write_desktop_entry() {  # write_desktop_entry FILE KEY=VALUE...: a launcher entry (Alt+R lists it)
    local file=$1
    shift
    mkdir -p "$(dirname "$file")"
    printf '%s\n' "[Desktop Entry]" "Type=Application" "Terminal=false" "$@" > "$file"
}

file_sha256() { sha256sum < "$1" | cut -d' ' -f1; }

# A pinned file: kept only when its SHA-256 is the one the signed repo names, so a file replaced on
# the server is refused. The download goes to DEST.part first: DEST is never a half or a forged file.
download_verified() {  # download_verified URL SHA256 DEST
    local url=$1 want=$2 dest=$3 part="$3.part"
    mkdir -p "$(dirname "$dest")"
    if ! curl -fL --progress-bar -o "$part" "$url"; then
        rm -f "$part"
        warn "$(basename "$dest") не скачался"
        return 1
    fi
    if [ "$(file_sha256 "$part")" != "$want" ]; then
        rm -f "$part"
        warn "$(basename "$dest"): скачанный файл не совпал с контрольной суммой и не установлен"
        return 1
    fi
    mv "$part" "$dest"
}

# __HOME__ in a file of the rice becomes the home folder; escaped for sed, it may hold | & or \.
fill_home() {  # fill_home [SED OPTION...] FILE
    local home
    home=$(printf '%s' "$HOME" | sed 's/[\\|&]/\\&/g')
    sed -e "s|__HOME__|$home|g" "$@"
}

# Files the rice wrote outside its own folders start with RICE_MARK; one without it is the user's own
# and stays as it is.
RICE_MARK="# hypr-rice"
rice_owns() {  # rice_owns FILE: absent, or written by the rice
    [ ! -e "$1" ] || head -n1 "$1" | grep -q "^$RICE_MARK"
}
