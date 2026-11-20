# Sourced by the panel scripts in ~/.local/bin (launcher, help-panel, settings-panel, ...).
# A panel is the Quickshell config ~/.config/quickshell/NAME: it reads the current theme's folder
# from $RICE_THEME_DIR and closes on `quickshell ipc call panel close`.
# The toggle needs no lock file: anything a panel starts (changetheme -> waybar, apps from the
# launcher) would inherit the lock's file descriptor and hold it forever.

panel_conf() { echo "$HOME/.config/quickshell/$1"; }

panel_is_open() {
    quickshell list -p "$(panel_conf "$1")" 2>/dev/null | grep -q "Process ID"
}

close_panel() {
    local conf
    conf=$(panel_conf "$1")
    quickshell ipc -p "$conf" call panel close >/dev/null 2>&1 || quickshell kill -p "$conf" >/dev/null 2>&1
}

# Replaces the calling script with the panel. The panel opens on the monitor that has focus now
# ($RICE_MONITOR): Quickshell would put it on its first screen, and Hyprland's own idea of the
# focused monitor reaches a panel only after its window is made.
open_panel() {
    local theme
    theme=$(cat "$HOME/.config/hypr/current-theme" 2>/dev/null || echo claude)
    export RICE_THEME_DIR="$HOME/.config/hypr/themes/$theme"
    RICE_MONITOR=$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name')
    export RICE_MONITOR
    exec quickshell -n -p "$(panel_conf "$1")"
}
