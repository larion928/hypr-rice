# Sourced by the menu scripts in ~/.local/bin (launcher, settings-panel, theme-picker, ...). Every menu lives in
# one long-running Quickshell, ~/.config/quickshell/shell, started from hyprland.lua; a script only asks it over
# IPC to toggle, open or close a menu. When the shell is not running (it crashed), the script starts it first.

MENUS_SHELL="$HOME/.config/quickshell/shell"

menus_running() {
    quickshell list -p "$MENUS_SHELL" 2>/dev/null | grep -q "Process ID"
}

# Starts the shell and waits until it answers (at most 5 s). -n: two scripts starting it at once make one shell.
# gtk3: Qt takes GTK's icon theme, the one the rice sets per theme (as hyprland.lua starts it).
menus_start() {
    QT_QPA_PLATFORMTHEME=gtk3 quickshell -d -n -p "$MENUS_SHELL" >/dev/null 2>&1
    local tries
    for tries in $(seq 50); do
        quickshell ipc -p "$MENUS_SHELL" call menus isOpen launcher >/dev/null 2>&1 && return 0
        sleep 0.1
    done
    return 1
}

# menus_call <function> <menu> [argument]: toggle, open, close or isOpen; prints what the shell answers.
menus_call() {
    shell_call menus "$@"
}

# shell_call <target> <function> [argument...]: calls an IpcHandler of the shell (menus, player), starting the
# shell first when it is not running; prints what it answers.
shell_call() {
    quickshell ipc -p "$MENUS_SHELL" call "$@" 2>/dev/null && return 0
    if menus_running; then
        notify-send -u critical "Меню" "Оболочка меню не отвечает: quickshell log -p $MENUS_SHELL"
        return 1
    fi
    menus_start && quickshell ipc -p "$MENUS_SHELL" call "$@"
}
