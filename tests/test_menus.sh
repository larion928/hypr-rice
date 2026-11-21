# Quickshell menus: what the offscreen behaviour tests in tests/qml cannot see.

# Every Nerd Font icon of the menus is written as a \u escape: an icon typed as the character
# itself is in the Private Use Area, which editors and tools drop without a trace (all 36 icons of
# the menus vanished that way once), leaving glyph: "" behind.
test_menu_icons_are_not_empty() {
    local shell="$REPO/home/.config/quickshell/shell" empty
    empty=$(grep -rnE '(glyph|keys|fallbackGlyph): ""|\? "" : ""' "$shell" --include='*.qml' --include='*.js' \
        | grep -v 'common/Chip.qml:.*property string glyph: ""')
    [ -z "$empty" ] || fail "пустые иконки:"$'\n'"$empty"
}

# An icon typed as the character itself still shows today, so the test above cannot see it; it turns
# into "" only when the next tool strips the Private Use Area, and nothing in that diff looks wrong.
test_menu_icons_are_escaped() {
    local shell="$REPO/home/.config/quickshell/shell" raw
    # Without a UTF-8 locale grep -P rejects these code points, and an empty result would pass.
    raw=$(LC_ALL=C.UTF-8 grep -rnP '[\x{E000}-\x{F8FF}\x{F0000}-\x{FFFFD}]' "$shell" --include='*.qml' --include='*.js')
    [ $? -le 1 ] || fail "grep не смог проверить иконки"
    [ -z "$raw" ] || fail "иконки не через \\u:"$'\n'"$raw"
}
