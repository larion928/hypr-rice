# rice games and rice proton.

# rice proton offers the downloaded Proton versions and Steam's own from every Steam library;
# a folder without the proton script is not a Proton.
test_proton_versions() {
    load_rice
    local steam="$HOME/.local/share/Steam" other="$HOME/games/SteamLibrary"
    mkdir -p "$steam/compatibilitytools.d/GE-Proton10-1" "$steam/compatibilitytools.d/broken" \
        "$steam/steamapps/common/Proton - Experimental" "$other/steamapps/common/Proton 9.0" \
        "$other/steamapps/common/Half-Life"
    touch "$steam/compatibilitytools.d/GE-Proton10-1/proton" "$steam/steamapps/common/Proton - Experimental/proton" \
        "$other/steamapps/common/Proton 9.0/proton"
    printf '"libraryfolders"\n{\n\t"0"\n\t{\n\t\t"path"\t\t"%s"\n\t}\n\t"1"\n\t{\n\t\t"path"\t\t"%s"\n\t}\n}\n' \
        "$steam" "$other" > "$steam/steamapps/libraryfolders.vdf"

    local expected="GE-Proton10-1=$steam/compatibilitytools.d/GE-Proton10-1
Proton - Experimental (Steam)=$steam/steamapps/common/Proton - Experimental
Proton 9.0 (Steam)=$other/steamapps/common/Proton 9.0"
    [ "$(proton_versions)" = "$expected" ] || fail "найдено: $(proton_versions)"
}

# rice games: what was picked is switched on, what was unpicked off, nothing else is touched.
test_games_tuning_menu() {
    load_rice
    for id in gamemode ntsync tearing zen; do
        eval "tuning_${id}_on() { echo on $id >> \"\$HOME/calls\"; touch \"\$HOME/is-$id\"; }"
        eval "tuning_${id}_off() { echo off $id >> \"\$HOME/calls\"; rm -f \"\$HOME/is-$id\"; }"
    done
    tuning_on() { [ -f "$HOME/is-$1" ]; }

    apply_game_tunings tearing gamemode >/dev/null
    apply_game_tunings gamemode >/dev/null
    [ "$(cat "$HOME/calls")" = "$(printf 'on gamemode\non tearing\noff tearing')" ] || fail "вызовы: $(cat "$HOME/calls")"
}

# Each game tuning on and off: its files, its packages, its refusals.
test_games_tunings() {
    load_rice
    GAMEMODE_MARK="$HOME/.config/hypr-rice/gamemode"
    GAMEMODE_INI="$HOME/.config/gamemode.ini"
    TEARING_LUA="$HOME/.config/hypr/games.lua"
    NTSYNC_LOAD="$HOME/etc/ntsync.conf"
    NTSYNC_RULE="$HOME/etc/60-ntsync.rules"
    mkdir -p "$HOME/etc"
    need_sudo() { :; }
    enable_multilib() { :; }
    pac() { echo "pac $*" >> "$HOME/calls"; }
    usermod() { echo "usermod $*" >> "$HOME/calls"; }
    hyprctl() { echo "hyprctl $*" >> "$HOME/calls"; }
    modprobe() { echo "modprobe $*" >> "$HOME/calls"; }
    udevadm() { :; }
    update_grub() { echo grub >> "$HOME/calls"; }
    amd_card() { echo 1; }

    tuning_tearing_on >/dev/null
    grep -q 'immediate = true' "$TEARING_LUA" && grep -q 'allow_tearing = true' "$TEARING_LUA" || fail "тиринг не записан"
    tuning_tearing_off >/dev/null
    [ ! -e "$TEARING_LUA" ] || fail "тиринг не убран"

    tuning_gamemode_on >/dev/null
    tuning_on gamemode || fail "GameMode не отмечен"
    grep -q 'pac -S --needed lib32-gamemode' "$HOME/calls" && grep -q "usermod -aG gamemode $USER" "$HOME/calls" \
        || fail "пакеты или группа: $(cat "$HOME/calls")"
    grep -q 'gpu_device=1' "$GAMEMODE_INI" || fail "нет настроек видеокарты AMD"
    tuning_gamemode_off >/dev/null
    [ ! -e "$GAMEMODE_INI" ] && ! tuning_on gamemode || fail "GameMode не выключен"
    echo "[general]" > "$GAMEMODE_INI"
    tuning_gamemode_on >/dev/null
    tuning_gamemode_off >/dev/null
    [ "$(cat "$GAMEMODE_INI")" = "[general]" ] || fail "чужой gamemode.ini перезаписан или удалён"

    tuning_ntsync_on >/dev/null
    [ "$(cat "$NTSYNC_LOAD")" = ntsync ] && grep -q uaccess "$NTSYNC_RULE" || fail "ntsync не настроен"
    tuning_ntsync_off >/dev/null
    [ ! -e "$NTSYNC_LOAD" ] && [ ! -e "$NTSYNC_RULE" ] && grep -q 'modprobe -r ntsync' "$HOME/calls" || fail "ntsync не убран"

    uname() { echo 7.2.14-zen1-1-zen; }
    tuning_zen_off >/dev/null 2>&1 && fail "удаляет загруженное ядро"
    true
}
