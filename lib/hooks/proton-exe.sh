# hook:proton-exe — opening a .exe runs it through Proton (umu, via ~/.local/bin/proton-run).

EXE_TYPES=(application/x-ms-dos-executable application/x-msdownload application/vnd.microsoft.portable-executable
           application/x-msi application/x-ms-shortcut application/x-bat)

# Thunar runs a .exe that has the execute bit (most archives unpack them so) as a program of its own
# instead of opening it with umu-run.desktop, and the kernel cannot run it ("Exec format error"). This
# rule makes the kernel hand every Windows program ("MZ" are its first two bytes) to proton-run, so
# such a .exe and ./game.exe in a terminal start through Proton too.
PROTON_BINFMT=/etc/binfmt.d/proton-run.conf
PROTON_BINFMT_RULE=/proc/sys/fs/binfmt_misc/proton-run

hook_proton_exe() {
    local d="$HOME/.local/share/applications" m
    write_desktop_entry "$d/umu-run.desktop" "Name=Proton (umu)" "Comment=Запустить Windows-программу через Proton" \
        "Exec=$HOME/.local/bin/proton-run %f" "Icon=wine" "NoDisplay=true" "MimeType=$(IFS=';'; echo "${EXE_TYPES[*]}");"
    for m in "${EXE_TYPES[@]}"; do
        xdg-mime default umu-run.desktop "$m" 2>/dev/null || true
    done
    update-desktop-database "$d" 2>/dev/null || true
    printf ':proton-run:M::MZ::%s:\n' "$HOME/.local/bin/proton-run" | sudo_write "$PROTON_BINFMT" || return 1
    sudo systemctl restart systemd-binfmt.service
}

unhook_proton_exe() {
    # Without this, .exe files would stay bound to a launcher whose umu-run is gone.
    local d="$HOME/.local/share/applications" list="$HOME/.config/mimeapps.list"
    rm -f "$d/umu-run.desktop"
    if [ -f "$list" ]; then
        sed -i -e 's/umu-run\.desktop;\?//g' -e '/=$/d' "$list"
    fi
    update-desktop-database "$d" 2>/dev/null || true
    sudo rm -f "$PROTON_BINFMT"
    if [ -e "$PROTON_BINFMT_RULE" ]; then
        echo -1 | sudo_write "$PROTON_BINFMT_RULE"
    fi
}
