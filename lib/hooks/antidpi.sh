# hook:antidpi — Igareck AntiDPI: anti-DPI strategies on zapret2, made for Debian/Ubuntu.
# Its own installer runs without questions (answers as flags, no terminal on stdin): it then needs
# no apt, only the Arch packages apps.txt installs before this step. Its installer runs as root, so
# the version is pinned here, with the archive's SHA-256: a checksum list from the same release would
# vouch for nothing if the release itself were replaced. A new version comes with a rice update
# (which reruns this step); the same version is not installed again.
ANTIDPI_REPO=https://github.com/igareck/anti-dpi-for-russia
ANTIDPI_VERSION=1.1
ANTIDPI_SHA256=bd581b6ca6c43b86dee4dcdd8d912519e04e6ffe077f3abecfa137649ebdae48
ANTIDPI_PREFIX=/opt/igareck-antidpi
ANTIDPI_DESKTOP="$HOME/.local/share/applications/hypr-rice-antidpi.desktop"

antidpi_installed() {  # the version in its installation.json, or nothing
    sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$ANTIDPI_PREFIX/installation.json" 2>/dev/null | head -n1
}

hook_antidpi() {
    local version=$ANTIDPI_VERSION installed work name
    installed=$(antidpi_installed)
    if [ "$installed" = "$version" ]; then
        ok "Igareck AntiDPI $version уже стоит"
        return 0
    fi
    work=$(mktemp -d)
    name="Igareck_AntiDPI_CLI_v${version}_Linux_x64.tar.gz"
    if ! download_verified "$ANTIDPI_REPO/releases/download/v$version/$name" "$ANTIDPI_SHA256" "$work/$name"; then
        rm -rf "$work"
        return 1
    fi
    if ! tar -xzf "$work/$name" -C "$work"; then
        warn "AntiDPI $version: архив не распаковался"
        rm -rf "$work"
        return 1
    fi
    # A new version replaces the old one whole: its installer takes only an empty folder.
    if [ -n "$installed" ] && ! sudo python3 "$ANTIDPI_PREFIX/remove_installation.py" --purge --yes </dev/null >/dev/null; then
        warn "AntiDPI $installed не удалился, $version не ставлю"
        rm -rf "$work"
        return 1
    fi
    if ! sudo python3 "$work/${name%.tar.gz}/app/install.py" install --prefix "$ANTIDPI_PREFIX" --engine compatible \
            --shortcuts no --global-command yes --skip-deps --no-launch </dev/null; then
        warn "AntiDPI $version не установился (лог — в выводе выше и в /var/log/igareck-zapret2)"
        rm -rf "$work"
        return 1
    fi
    rm -rf "$work"
    write_desktop_entry "$ANTIDPI_DESKTOP" "Name=Igareck AntiDPI" "Comment=Обход DPI: стратегии на zapret2" \
        "Exec=kitty -e igareck-antidpi" "Icon=network-vpn" "Categories=Network;"
    ok "Igareck AntiDPI $version: запуск — igareck-antidpi или лаунчер (Alt+R)"
    # Two zapret engines on the same traffic get in each other's way.
    if systemctl is-active --quiet zapret2.service 2>/dev/null; then
        warn "работает служба zapret2: перед стратегиями AntiDPI останови её — sudo systemctl disable --now zapret2"
    fi
}

unhook_antidpi() {
    if [ -f "$ANTIDPI_PREFIX/remove_installation.py" ]; then
        sudo python3 "$ANTIDPI_PREFIX/remove_installation.py" --purge --yes </dev/null >/dev/null
    fi
    rm -f "$ANTIDPI_DESKTOP"
}
