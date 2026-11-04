#!/usr/bin/env bash
# themegen_snapshot.sh OUT — run themegen.py in a fake $HOME (build, then apply for every theme)
# and copy everything it produced after each step to OUT/<step>/, with the commands it ran in
# OUT/<step>/commands. Two snapshots taken from the same themes must be identical, which is how a
# rewrite of themegen is checked: tests/themegen_snapshot.sh before; (rewrite); ... after;
# diff -r before after.
# The programs it themes are faked as installed (Firefox, Zen, Obsidian, Vesktop, Code - OSS,
# drift, Chromium, neoHtop); sudo, gsettings, systemctl, pkill, hyprctl and pgrep only record their calls.
# SRC_HOME (default: the repo's home/) is where themegen.py and the themes are taken from.
set -euo pipefail

REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
SRC_HOME=${SRC_HOME:-$REPO/home}
OUT=$(mkdir -p "$1" && cd "$1" && pwd)
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
FAKE_HOME=$SANDBOX/home
STUBS=$SANDBOX/bin
CALLS=$SANDBOX/calls

copy_inputs() {
    mkdir -p "$FAKE_HOME/.config/hypr" "$FAKE_HOME/.config/hypr-rice/waybar"
    cp -r "$SRC_HOME/.config/hypr/scripts" "$SRC_HOME/.config/hypr/themes" "$FAKE_HOME/.config/hypr/"
    find "$FAKE_HOME/.config/hypr" -name __pycache__ -prune -exec rm -rf {} +
    cp "$SRC_HOME/.config/hypr-rice/waybar/config.base.json" "$FAKE_HOME/.config/hypr-rice/waybar/"
    echo '{"clock": {"format": "{:%H:%M}"}}' > "$FAKE_HOME/.config/hypr-rice/waybar/config.local.json"
}

fake_installed_programs() {
    local h=$FAKE_HOME
    mkdir -p "$h/.mozilla/firefox/test.default" "$h/.zen/test.default" "$h/vault/.obsidian" \
        "$h/.config/obsidian" "$h/.config/vesktop/settings" "$h/.config/Code - OSS/User" \
        "$h/.config/drift" "$h/.config/chromium/Default" "$h/neohtop/src/lib/definitions"
    touch "$h/.mozilla/firefox/test.default/prefs.js" "$h/.zen/test.default/prefs.js"
    echo 'user_pref("browser.startup.page", 3);' > "$h/.mozilla/firefox/test.default/user.js"
    echo "{\"vaults\": {\"v\": {\"path\": \"$h/vault\"}}}" > "$h/.config/obsidian/obsidian.json"
    echo '{}' > "$h/vault/.obsidian/appearance.json"
    echo '{"enabledThemes": []}' > "$h/.config/vesktop/settings/settings.json"
    echo '{"editor.fontSize": 14}' > "$h/.config/Code - OSS/User/settings.json"
    printf '[engine]\nspeed = 1\n' > "$h/.config/drift/config.toml"
    echo '{"browser": {}}' > "$h/.config/chromium/Default/Preferences"
}

# Each stub records "name args" and succeeds; pgrep reports nothing running.
make_stubs() {
    mkdir -p "$STUBS"
    local name
    for name in sudo gsettings systemctl pkill hyprctl code-oss chromium AyuGram Telegram; do
        printf '#!/bin/sh\necho "%s $*" >> "%s"\n' "$name" "$CALLS" > "$STUBS/$name"
    done
    printf '#!/bin/sh\necho "pgrep $*" >> "%s"\nexit 1\n' "$CALLS" > "$STUBS/pgrep"
    chmod +x "$STUBS"/*
}

themegen() {
    HOME=$FAKE_HOME PATH="$STUBS:/usr/bin" python3 "$FAKE_HOME/.config/hypr/scripts/themegen.py" "$@"
}

# Everything under the fake home except the inputs. Zips (the Code - OSS extension, Telegram
# themes) are unpacked, since they carry the time they were made; a symlink becomes a file naming
# its target, which only exists inside the sandbox.
save_step() {
    local step=$OUT/$1 archive link target
    sleep 0.3  # commands themegen starts in the background
    mkdir -p "$step"
    (cd "$FAKE_HOME" && tar -cf - --exclude=./.config/hypr/scripts --exclude='*.pyc' --exclude=__pycache__ \
        --no-wildcards-match-slash --exclude='./.config/hypr/themes/*/[!a]*' .) | tar -C "$step" -xf -
    find "$step" \( -name '*.vsix' -o -name '*.tdesktop-theme' \) | while read -r archive; do
        mkdir "$archive.unpacked"
        (cd "$archive.unpacked" && python3 -m zipfile -e "$archive" .)
        rm "$archive"
    done
    find "$step" -type l | while read -r link; do
        target=$(readlink "$link")
        rm "$link"
        echo "symlink -> $target" > "$link"
    done
    sort "$CALLS" > "$step/commands" 2>/dev/null || touch "$step/commands"
    rm -f "$CALLS"
}

# The sandbox path and the time-based version numbers taken out, so snapshots from
# different runs and minutes compare equal.
normalize() {
    grep -rlF "$SANDBOX" "$OUT" | xargs -r sed -i "s|$SANDBOX|SANDBOX|g"
    grep -rlE '1\.0\.[0-9]{6,}' "$OUT" | xargs -r sed -i -E 's/1\.0\.[0-9]{6,}/1.0.N/g'
    find "$OUT" -path '*hypr-themes/chromium/manifest.json' \
        -exec sed -i -E 's/"version": "1\.[0-9]+\.[0-9]+"/"version": "N"/' {} +
    find "$OUT" -depth -name '*1.0.[0-9]*' | while read -r p; do
        mv "$p" "$(dirname "$p")/$(basename "$p" | sed -E 's/1\.0\.[0-9]{6,}/1.0.N/')"
    done
}

copy_inputs
fake_installed_programs
make_stubs
themegen build > "$OUT/build.stdout"
save_step build
for theme_dir in "$FAKE_HOME"/.config/hypr/themes/*/; do
    theme=$(basename "$theme_dir")
    wallpaper=$(find "$theme_dir" -maxdepth 1 -type f \( -name '*.jpg' -o -name '*.png' -o -name '*.webp' \) | sort | head -n1)
    themegen apply "$theme" --wallpaper "$wallpaper"
    save_step "apply-$theme"
done
normalize
echo "снимок: $OUT ($(find "$OUT" -type f | wc -l) файлов)"
