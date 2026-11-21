# ~/.local/bin/clipboard-store: what wl-paste --watch runs on every copy for the clipboard history.

# A fake cliphist 0.7.0: the entries are files in ~/clip named by id; it refuses the flags and subcommands 0.7.0
# does not have (as the real one does), skips a sensitive copy without reading it, drops an earlier copy of the
# same bytes and keeps the last -max-items.
fake_cliphist() {
    mkdir -p "$HOME/bin"
    cat > "$HOME/bin/cliphist" <<'EOF'
#!/bin/bash
echo "cliphist $*" >> "$CALLS"
dir=$HOME/clip max=750
mkdir -p "$dir"
while [ "${1#-}" != "$1" ]; do
    case $1 in
        -max-items) max=$2 ;;
        -max-dedupe-search|-min-store-length|-preview-width|-db-path|-config-path) ;;
        *) echo "flag provided but not defined: $1" >&2; exit 2 ;;
    esac
    shift 2
done
case $1 in
    store)
        [ "${CLIPBOARD_STATE:-}" = sensitive ] && exit 0
        id=$(($(ls "$dir" | sort -n | tail -n1) + 1))
        cat > "$dir/new"
        for entry in "$dir"/*; do
            [ "$entry" != "$dir/new" ] && cmp -s "$entry" "$dir/new" && rm "$entry"
        done
        mv "$dir/new" "$dir/$id"
        ls "$dir" | sort -nr | tail -n +$((max + 1)) | while read -r gone; do rm "$dir/$gone"; done ;;
    list) ls "$dir" | sort -nr | while read -r id; do printf '%s\tentry %s\n' "$id" "$id"; done ;;
    decode) cat "$dir/$2" ;;
    delete) while IFS=$'\t' read -r id _; do rm "$dir/$id"; done ;;
    wipe|delete-query|version) ;;
    *) echo "usage: cliphist <store|list|decode|delete|delete-query|wipe|version>" >&2; exit 1 ;;
esac
EOF
    chmod +x "$HOME/bin/cliphist"
    export CALLS="$HOME/calls" PATH="$HOME/bin:$PATH" XDG_CACHE_HOME="$HOME/.cache" CLIPBOARD_LIMIT_BYTES=1000
}

# Stores $1 bytes of $2 (default: zeros, each copy different from the last by its length) as one copy.
copy_bytes() {
    head -c "$1" "${2:-/dev/zero}" | "$REPO/home/.local/bin/clipboard-store" || fail "clipboard-store: код $?"
}

kept() {
    ls "$HOME/clip" | sort -n | tr '\n' ' '
}

sizes() {
    sort -n "$HOME/.cache/hypr-rice/clipboard-sizes" | tr '\n' ' '
}

test_clipboard_store_keeps_100_entries_and_their_sizes() {
    fake_cliphist
    copy_bytes 10
    grep -qx "cliphist -max-items 100 store" "$CALLS" || fail "не те флаги: $(cat "$CALLS")"
    [ "$(kept)" = "1 " ] || fail "запись не сохранилась: $(kept)"
    [ "$(sizes)" = "1 10 " ] || fail "размер не записан: $(sizes)"
    ! grep -q "decode" "$CALLS" || fail "под пределом записи не должны читаться: $(cat "$CALLS")"
}

# A sensitive copy and a copy the history already has leave no size of their own; an entry deleted from the
# menu leaves the sizes too.
test_clipboard_store_sizes_follow_the_history() {
    fake_cliphist
    copy_bytes 10
    CLIPBOARD_STATE=sensitive copy_bytes 20
    copy_bytes 10
    [ "$(kept)" = "2 " ] || fail "после секретной копии и повтора остались: $(kept)"
    [ "$(sizes)" = "2 10 " ] || fail "размеры: $(sizes)"
    copy_bytes 30
    printf '2\tentry 2\n' | cliphist delete
    copy_bytes 40
    [ "$(sizes)" = "3 30 4 40 " ] || fail "после удаления из меню размеры: $(sizes)"
}

# Past the limit the oldest entries go until the rest fits; the newest one stays even when it alone is over.
test_clipboard_store_drops_the_oldest_past_the_limit() {
    fake_cliphist
    copy_bytes 400
    copy_bytes 401
    copy_bytes 402
    [ "$(kept)" = "2 3 " ] || fail "после 1203 из 1000 байт остались: $(kept)"
    copy_bytes 1500
    [ "$(kept)" = "4 " ] || fail "после записи больше предела остались: $(kept)"
    [ "$(sizes)" = "4 1500 " ] || fail "размеры: $(sizes)"
}

# Entries stored before the sizes were kept are measured once.
test_clipboard_store_measures_entries_it_has_no_size_for() {
    fake_cliphist
    mkdir -p "$HOME/clip"
    head -c 700 /dev/zero > "$HOME/clip/1"
    copy_bytes 500
    [ "$(kept)" = "2 " ] || fail "старая запись без размера не учтена: $(kept)"
}
