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
