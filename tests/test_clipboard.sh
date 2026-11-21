# ~/.local/bin/clipboard-store: what wl-paste --watch runs on every copy for the clipboard history.

# A fake cliphist: the entries are files in ~/clip named by id, and the database file grows by every stored entry
# and shrinks back to their sum only on compact, as a real one keeps freed pages until then.
fake_cliphist() {
    mkdir -p "$HOME/bin"
    cat > "$HOME/bin/cliphist" <<'EOF'
#!/bin/sh
echo "cliphist $*" >> "$CALLS"
dir=$HOME/clip db=$HOME/.cache/cliphist/db
mkdir -p "$dir" "${db%/*}"
touch "$db"
while [ "${1#-}" != "$1" ]; do shift 2; done
case $1 in
    store)
        id=$(($(ls "$dir" | sort -n | tail -n1) + 1))
        cat > "$dir/$id"
        truncate -s $(($(stat -c %s "$db") + $(stat -c %s "$dir/$id"))) "$db" ;;
    list) ls "$dir" | sort -nr | while read -r id; do printf '%s\tentry %s\n' "$id" "$id"; done ;;
    decode) cat "$dir/$2" ;;
    delete) while IFS="$(printf '\t')" read -r id _; do rm "$dir/$id"; done ;;
    compact) truncate -s "$(cat "$dir"/* /dev/null | wc -c)" "$db" ;;
esac
EOF
    chmod +x "$HOME/bin/cliphist"
    export CALLS="$HOME/calls" PATH="$HOME/bin:$PATH" CLIPBOARD_LIMIT_BYTES=1000
}

# Stores $1 bytes as one copy.
copy_bytes() {
    head -c "$1" /dev/zero | "$REPO/home/.local/bin/clipboard-store"
}

kept() {
    ls "$HOME/clip" | sort -n | tr '\n' ' '
}

test_clipboard_store_keeps_100_entries_without_a_size_limit_for_one() {
    fake_cliphist
    copy_bytes 10
    grep -qx "cliphist -max-items 100 -max-store-size 0 store" "$CALLS" || fail "не те флаги: $(cat "$CALLS")"
    ! grep -q "decode\|compact" "$CALLS" || fail "под пределом база не должна читаться: $(cat "$CALLS")"
}

# Past the limit the oldest entries go until the rest fits, and the database is compacted; the newest one stays
# even when it alone is over the limit.
test_clipboard_store_drops_the_oldest_past_the_limit() {
    fake_cliphist
    copy_bytes 400
    copy_bytes 400
    copy_bytes 400
    [ "$(kept)" = "2 3 " ] || fail "после 1200 из 1000 байт остались: $(kept)"
    [ "$(stat -c %s "$HOME/.cache/cliphist/db")" -eq 800 ] || fail "база не сжата: $(stat -c %s "$HOME/.cache/cliphist/db")"
    copy_bytes 1500
    [ "$(kept)" = "4 " ] || fail "после записи больше предела остались: $(kept)"
}
