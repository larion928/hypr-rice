# hook:syncthing — Syncthing runs as the user's own service, from the next login on and right now.

hook_syncthing() {
    systemctl --user enable --now syncthing.service >/dev/null 2>&1 || return 1
    ok "Syncthing запущен: настройка — http://127.0.0.1:8384"
}

unhook_syncthing() {
    systemctl --user disable --now syncthing.service >/dev/null 2>&1 || true
}
