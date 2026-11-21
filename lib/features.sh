# rice features: the rice's features switched on and off (the same list as Alt+F2 → Функции). The registry and
# its state are ~/.config/hypr/scripts/features.py and ~/.config/hypr-rice/features.json.

FEATURES_PY="$HOME/.config/hypr/scripts/features.py"

cmd_features() {  # cmd_features [on|off ID]: the list, or one feature switched
    if [ $# -eq 0 ]; then
        python3 "$FEATURES_PY" show
    else
        python3 "$FEATURES_PY" "$@"
    fi
}

# Every install, update and repair: features a new version brought get their defaults, the user's choices
# stay, and the session follows them (the daily check's timer among them).
setup_features() {
    python3 "$FEATURES_PY" write || warn "функции райса не записаны (python3 $FEATURES_PY write)"
    ok "функции: rice features, или Alt+F2 → Функции"
}
