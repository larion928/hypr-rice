# hook:zram — swap in compressed RAM, set up the same on any machine (sizes are shares of its RAM).

ZRAM_CONF=/etc/systemd/zram-generator.conf
ZRAM_SYSCTL=/etc/sysctl.d/99-hypr-rice-zram.conf

hook_zram() {
    if ! rice_owns "$ZRAM_CONF"; then
        info "zram: свой $ZRAM_CONF оставлен как есть"
        return 0
    fi
    # zram-generator works the size out on each machine: half of its RAM, at most 8 GiB.
    printf '%s\n' "$RICE_MARK (rice → программы → zram). Half of the RAM, at most 8 GiB, zstd-compressed." \
        "[zram0]" "zram-size = min(ram / 2, 8192)" "compression-algorithm = zstd" "swap-priority = 100" \
        | sudo_write "$ZRAM_CONF" || return 1
    # The usual tuning for swap on zram (ArchWiki): swap early and in single pages, it is in RAM anyway.
    printf '%s\n' "$RICE_MARK (rice → программы → zram)." "vm.swappiness = 180" "vm.watermark_boost_factor = 0" \
        "vm.watermark_scale_factor = 125" "vm.page-cluster = 0" | sudo_write "$ZRAM_SYSCTL" || return 1
    sudo sysctl -q --system || return 1
    sudo systemctl daemon-reload || return 1
    # A zram swap already in use is not rebuilt now: taking it off needs that much free RAM.
    if swapon --show=NAME --noheadings | grep -q zram0; then
        ok "zram настроен: новый размер — после перезагрузки"
    else
        sudo systemctl start systemd-zram-setup@zram0.service && ok "zram включён: половина памяти, не больше 8 ГиБ"
    fi
}

unhook_zram() {
    if rice_owns "$ZRAM_CONF"; then sudo rm -f "$ZRAM_CONF"; fi
    if rice_owns "$ZRAM_SYSCTL"; then sudo rm -f "$ZRAM_SYSCTL"; fi
    info "zram выключится после перезагрузки"
}
