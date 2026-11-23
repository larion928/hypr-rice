# themegen: theme edits reaching kitty, waybar, icons, windows and GTK; the settings window; cursors.

# Edits made to a theme in the settings (fonts, colours, wallpapers) reach the theme loader, kitty
# and waybar; what was not edited stays the theme's own.
test_theme_edits_reach_the_programs() {
    local theme_dir="$HOME/.config/hypr/themes/claude"
    mkdir -p "$theme_dir" "$HOME/.config/hypr-rice" "$HOME/bin" "$HOME/Pictures"
    cp "$REPO/home/.config/hypr/themes/claude/"{palette.json,ui.json} "$theme_dir/"
    touch "$theme_dir/a.png" "$theme_dir/b.png" "$HOME/Pictures/mine.jpg"
    cat > "$HOME/.config/hypr-rice/theme-edits.json" <<EOF
{"themes": {"claude": {"fonts": {"font": "Test Mono", "body": "Test Sans", "display": ""},
                       "colors": {"accent": "#123456", "bg": "not a colour"},
                       "wallpapers": {"added": ["$HOME/Pictures/mine.jpg", "$HOME/gone.png"],
                                      "off": ["$theme_dir/a.png"]}}}}
EOF
    printf '#!/bin/sh\n' > "$HOME/bin/pkill" && chmod +x "$HOME/bin/pkill"
    PATH="$HOME/bin:$PATH" python3 - "$REPO/home/.config/hypr/scripts" "$HOME" <<'PY' || fail "генератор упал"
import sys
sys.path.insert(0, sys.argv[1])
from apptheme.apps import kitty
from apptheme.desktop import waybar
from apptheme.themes.theme import load
home = sys.argv[2]
theme = load("claude")
assert theme.font == "Test Mono", theme.font
assert theme.body_font == "Test Sans", theme.body_font
assert theme.display == "Source Serif 4", theme.display  # an empty choice keeps the theme's own
assert theme.colors["accent"] == "#123456", theme.colors["accent"]
assert theme.colors["bg"] == theme.own["colors"]["bg"], "a broken colour must be ignored"
walls = [str(p) for p in theme.wallpapers]
assert walls == [f"{home}/.config/hypr/themes/claude/b.png", f"{home}/Pictures/mine.jpg"], walls
kitty.apply(theme)
waybar.write_fonts(theme)
PY
    grep -qx "font_family Test Mono" "$HOME/.config/hypr-rice/kitty/theme.conf" || fail "kitty не получил шрифт"
    grep -qx "cursor #123456" "$HOME/.config/hypr-rice/kitty/theme.conf" || fail "kitty не получил цвет"
    grep -q '"Test Mono", "JetBrainsMono Nerd Font"' "$HOME/.config/hypr-rice/waybar/fonts.css" \
        || fail "waybar не получил шрифт"
}

# The waybar layout saved for every theme applies to all of them, a theme's own layout wins over
# it; a module only one theme defines is dropped elsewhere, and a bar at the bottom keeps its gap
# to the screen edge.
test_waybar_layout_edits() {
    local themes="$HOME/.config/hypr/themes"
    mkdir -p "$themes" "$HOME/.config/hypr-rice/waybar"
    cp -r "$REPO/home/.config/hypr/themes/"{claude,coffee} "$themes/"
    cp "$REPO/home/.config/hypr-rice/waybar/config.base.json" "$HOME/.config/hypr-rice/waybar/"
    cat > "$HOME/.config/hypr-rice/theme-edits.json" <<'EOF'
{"everywhere": {"waybar": {"modules-left": ["clock", "custom/claude"], "modules-right": ["tray"],
                           "position": "bottom"}},
 "themes": {"claude": {"waybar": {"modules-left": ["custom/claude"], "modules-right": ["clock"]}}}}
EOF
    python3 - "$REPO/home/.config/hypr/scripts" <<'PY' || fail "раскладка собрана не так"
import sys
sys.path.insert(0, sys.argv[1])
from apptheme.desktop import waybar
from apptheme.themes.theme import load
coffee = waybar.config_for(load("coffee"))
assert coffee["modules-left"] == ["clock"], coffee["modules-left"]   # custom/claude is claude's own
assert coffee["modules-right"] == ["tray"], coffee["modules-right"]
assert coffee["position"] == "bottom" and "margin-bottom" in coffee and "margin-top" not in coffee
claude = waybar.config_for(load("claude"))
assert claude["modules-left"] == ["custom/claude"], claude["modules-left"]
assert claude["modules-right"] == ["clock"], claude["modules-right"]
assert claude["position"] == "bottom", "the shared position stays where the theme sets none"
PY
}

# Without thermal_zone0 waybar's temperature module reads the CPU's own sensor, found by name; with
# the zone it is left alone.
test_waybar_finds_cpu_sensor() {
    local sys="$HOME/sys"
    mkdir -p "$sys/devices/pci/hwmon/hwmon3" "$sys/devices/acpi/hwmon/hwmon0" "$sys/class/hwmon" "$sys/class/thermal"
    echo acpitz > "$sys/devices/acpi/hwmon/hwmon0/name"
    echo k10temp > "$sys/devices/pci/hwmon/hwmon3/name"
    echo 62750 > "$sys/devices/pci/hwmon/hwmon3/temp1_input"
    ln -s "$sys/devices/acpi/hwmon/hwmon0" "$sys/class/hwmon/hwmon0"
    ln -s "$sys/devices/pci/hwmon/hwmon3" "$sys/class/hwmon/hwmon3"
    python3 - "$REPO/home/.config/hypr/scripts" "$sys" <<'PY' || fail "датчик найден не так"
import sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
from apptheme.desktop import waybar
root = Path(sys.argv[2])
waybar.HWMON = root / "class/hwmon"
waybar.THERMAL_ZONE = root / "class/thermal/thermal_zone0"
found = waybar.cpu_sensor()
assert found == {"hwmon-path-abs": str(root / "devices/pci/hwmon"), "input-filename": "temp1_input"}, found
waybar.THERMAL_ZONE.mkdir()
assert waybar.cpu_sensor() == {}, "with thermal_zone0 the module keeps its default"
PY
}

# An icon picked for a module replaces the glyph its format starts with, or what {icon} stood for;
# modules whose icon says something (the workspaces) keep theirs.
test_waybar_icon_edits() {
    local themes="$HOME/.config/hypr/themes"
    mkdir -p "$themes" "$HOME/.config/hypr-rice/waybar"
    cp -r "$REPO/home/.config/hypr/themes/coffee" "$themes/"
    cp "$REPO/home/.config/hypr-rice/waybar/config.base.json" "$HOME/.config/hypr-rice/waybar/"
    echo '{"themes": {"coffee": {"icons": {"cpu": "X", "pulseaudio": "V", "hyprland/workspaces": "W"}}}}' \
        > "$HOME/.config/hypr-rice/theme-edits.json"
    python3 - "$REPO/home/.config/hypr/scripts" <<'PY' || fail "значки заменены не так"
import sys
sys.path.insert(0, sys.argv[1])
from apptheme.desktop import waybar
from apptheme.themes.theme import load
config = waybar.config_for(load("coffee"))
assert config["cpu"]["format"] == "X {usage}%", config["cpu"]["format"]
assert config["pulseaudio"]["format"] == "V {volume}%", config["pulseaudio"]["format"]
assert config["hyprland/workspaces"]["format"] == "{icon}", "the workspaces' icon must stay"
assert "cpu" in waybar.layout(load("coffee"))["iconEditable"]
PY
}

# A theme can take another's battery drawing (in its own colours, with that drawing's animation), its
# own folder colour and icon theme; folders are recoloured only under a Papirus icon theme.
test_icon_edits() {
    local themes="$HOME/.config/hypr/themes"
    mkdir -p "$themes" "$HOME/.config/gtk-3.0" "$HOME/bin"
    cp -r "$REPO/home/.config/hypr/themes/"{coffee,night} "$themes/"
    printf '[Settings]\ngtk-icon-theme-name=Papirus-Dark\n' > "$HOME/.config/gtk-3.0/settings.ini"
    printf '#!/bin/sh\n' > "$HOME/bin/gsettings" && chmod +x "$HOME/bin/gsettings"
    mkdir -p "$HOME/.config/hypr-rice"
    echo '{"themes": {"coffee": {"battery": "night", "folders": "teal", "iconTheme": "breeze-dark"}}}' \
        > "$HOME/.config/hypr-rice/theme-edits.json"
    PATH="$HOME/bin:$PATH" python3 - "$REPO/home/.config/hypr/scripts" <<'PY' || fail "значки применены не так"
import sys
sys.path.insert(0, sys.argv[1])
from apptheme.desktop import battery
from apptheme.icons import icon_theme
from apptheme.themes.theme import load
coffee = load("coffee")
frames = battery.frames(coffee)
assert len(frames) == 7, len(frames)                                  # night's moon phases
assert coffee.colors["fg"] in frames[0], "drawn in coffee's colours"
assert coffee.ui.get("batteryAnim") == "pingpong", coffee.ui.get("batteryAnim")  # night's animation
battery.build([coffee])
own = (coffee.dir / "assets/own-battery.svg").read_text()
assert own == battery.drawing_of("coffee", coffee)[0] != frames[0], "the settings show coffee's own drawing"
assert len(list((coffee.dir / "assets").glob("battery-*.svg"))) == 7, "the bar counts only the frames"
assert coffee.ui["folders"] == "teal"
assert icon_theme.current(coffee) == "breeze-dark"
icon_theme.apply(coffee)
PY
    grep -qx "gtk-icon-theme-name=breeze-dark" "$HOME/.config/gtk-3.0/settings.ini" || fail "тема значков не записана"
    echo '{"themes": {}}' > "$HOME/.config/hypr-rice/theme-edits.json"
    PATH="$HOME/bin:$PATH" python3 - "$REPO/home/.config/hypr/scripts" <<'PY' || fail "тема значков не вернулась"
import sys
sys.path.insert(0, sys.argv[1])
from apptheme.icons import icon_theme
from apptheme.themes.theme import load
icon_theme.apply(load("coffee"))
PY
    grep -qx "gtk-icon-theme-name=Papirus-Dark" "$HOME/.config/gtk-3.0/settings.ini" || fail "без правки не вернулась тема значков райса"
}

# The settings window's bar fills a module's own format the way waybar does, and tells a script that
# printed nothing (shown only at times) from one that never answered.
test_bar_preview_formats() {
    python3 - "$REPO/home/.config/hypr/scripts" <<'PY' || fail "превью панели собрано не так"
import sys
sys.path.insert(0, sys.argv[1])
from apptheme.desktop import bar_preview as bar
assert bar.render("{icon} {volume}%", {"volume": 70}, ["low", "mid", "high"], 70) == "high 70%"
assert bar.render("{icon} {volume}%", {"volume": 10}, {"default": ["low", "mid", "high"]}, 10) == "low 10%"
assert bar.render(" {}", {"": "96"}) == "96"
assert bar.from_script("custom/updates", {"return-type": "json", "format": "{}"}, '{"text": "13"}') == bar.shown("13")
empty = bar.from_script("custom/updates", {"return-type": "json"}, "")
assert empty["state"] == "sometimes" and "обновлен" in empty["note"], empty
silent = bar.from_script("custom/x", {}, None)
assert silent["state"] == "sometimes" and "не ответил" in silent["note"], silent
# Hyprland 0.57 lists a special workspace without an "id".
bar.hyprctl = lambda what: [{"id": 2}, {"name": "special:magic"}, {"id": 1}] if what == "workspaces" else {"id": 2}
assert bar.read_workspaces({"format-icons": {"active": "*"}}) == bar.shown("1 *"), bar.read_workspaces({})
PY
}

# Window edits go to theme-edits.lua: only what was changed, the theme's animations rescaled for
# «быстрее»; the theme's own values are read from its hypr.lua.
test_window_edits() {
    local themes="$HOME/.config/hypr/themes"
    mkdir -p "$themes" "$HOME/.config/hypr-rice"
    cp -r "$REPO/home/.config/hypr/themes/coffee" "$themes/"
    echo '{"themes": {"coffee": {"windows": {"gaps_in": 2, "blur": false, "active_opacity": 0.9, "animations": "fast"}}}}' \
        > "$HOME/.config/hypr-rice/theme-edits.json"
    python3 - "$REPO/home/.config/hypr/scripts" <<'PY' || fail "правки окон записаны не так"
import sys
sys.path.insert(0, sys.argv[1])
from apptheme.desktop import windows
from apptheme.themes.theme import load
coffee = load("coffee")
own = windows.own(coffee)
assert (own["gaps_in"], own["gaps_out"], own["border_size"], own["rounding"]) == (5, 10, 3, 6), own
windows.apply(coffee)
lua = windows.EDITS_LUA.read_text()
assert "hl.config({ general = { gaps_in = 2 }, decoration = { active_opacity = 0.9, blur = { enabled = false } } })" in lua, lua
assert 'leaf = "windowsIn",   enabled = true, speed = 1.8' in lua, lua   # 3 × 0.6
assert "gaps_out" not in lua and "rounding" not in lua, "only what was changed"
PY
}

# Every member the settings window uses on its main objects (themeEdit.save, panelEditor.slots, ...) is
# defined; QML only notices a missing one when that line runs, e.g. on the first drag.
test_settings_members_defined() {
    python3 "$REPO/tests/qml_members.py" "$REPO/home/.config/quickshell/shell/settings" \
        || fail "в окне настроек используется неопределённое"
}

# themegen builds and applies every theme in a fake $HOME; tests/themegen_snapshot.sh records it all.
test_themegen_applies_every_theme() {
    "$REPO/tests/themegen_snapshot.sh" "$HOME/snapshot" >/dev/null || fail "themegen упал, вывод выше"
    local folder theme
    for folder in "$REPO"/home/.config/hypr/themes/*/; do
        theme=$(basename "$folder")
        [ -s "$HOME/snapshot/apply-$theme/.config/hypr-rice/kitty/theme.conf" ] || fail "$theme: нет темы kitty"
        ls "$HOME/snapshot/build/.config/hypr/themes/$theme/assets/battery-0.svg" >/dev/null 2>&1 \
            || fail "$theme: нет значка батареи"
    done
}

# Reloading GTK ends on the base theme gtk.css is written over, whatever theme the setting held:
# restoring the held one kept a wrong base (light Adwaita's grey dividers in Thunar) for good.
test_gtk_reload_lands_on_base_theme() {
    mkdir -p "$HOME/bin"
    printf '#!/bin/sh\n[ "$1" = get ] && { echo "'"'"'Adwaita-dark'"'"'"; exit 0; }\necho "$*" >> "%s/calls"\n' "$HOME" \
        > "$HOME/bin/gsettings"
    printf '#!/bin/sh\n:\n' > "$HOME/bin/systemctl"
    chmod +x "$HOME/bin/gsettings" "$HOME/bin/systemctl"
    PATH="$HOME/bin:$PATH" python3 - "$REPO/home/.config/hypr/scripts" "$HOME/calls" <<'PY' || fail "тема GTK не та"
import sys
sys.path.insert(0, sys.argv[1])
from apptheme.apps import gtk
gtk.reload()
last = open(sys.argv[2]).read().splitlines()[-1]
assert last == f"set org.gnome.desktop.interface gtk-theme {gtk.base_theme()}", last
PY
}

# A cursor theme from a file: an archive (refused when it reaches out of itself or carries no cursor),
# or an osu! skin; added ones can go again, the rice's WhiteCat cannot.
test_cursor_from_file() {
    mkdir -p "$HOME/pack/Neon/cursors" "$HOME/.config/hypr/scripts" "$HOME/skin"
    cp -r "$REPO/home/.config/hypr/scripts/." "$HOME/.config/hypr/scripts/"
    printf 'Xcur' > "$HOME/pack/Neon/cursors/left_ptr"
    printf '[Icon Theme]\nName=Neon\n' > "$HOME/pack/Neon/index.theme"
    tar -czf "$HOME/neon.tar.gz" -C "$HOME/pack" Neon
    python3 - "$HOME/.config/hypr/scripts" "$HOME" <<'PY' || fail "курсор из файла не так"
import sys, tarfile, zipfile
from pathlib import Path
from PIL import Image
sys.path.insert(0, sys.argv[1])
from apptheme.cursors import cursor_install
home = Path(sys.argv[2])
icons = home / ".local/share/icons"

assert cursor_install.install(home / "neon.tar.gz") == ["Neon"] and (icons / "Neon/cursors/left_ptr").exists()
try:
    cursor_install.install(home / "neon.tar.gz")
    raise AssertionError("курсор установлен поверх того же")
except ValueError:
    pass

with zipfile.ZipFile(home / "evil.zip", "w") as out:
    out.writestr("../evil/cursors/left_ptr", "x")
with zipfile.ZipFile(home / "empty.zip", "w") as out:
    out.writestr("Thing/readme.txt", "x")
for bad, reason in (("evil.zip", "за его пределы"), ("empty.zip", "нет темы курсора")):
    try:
        cursor_install.install(home / bad)
        raise AssertionError(f"{bad} принят")
    except ValueError as error:
        assert reason in str(error), error

Image.new("RGBA", (64, 64), (255, 255, 0, 255)).save(home / "skin/cursor@2x.png")
with zipfile.ZipFile(home / "My Skin.osk", "w") as out:
    out.write(home / "skin/cursor@2x.png", "cursor@2x.png")
assert cursor_install.install(home / "My Skin.osk") == ["My Skin"] and (icons / "My Skin/cursors/left_ptr").exists()

cursor_install.remove("Neon")
assert not (icons / "Neon").exists()
(icons / "WhiteCat/cursors").mkdir(parents=True)
try:
    cursor_install.remove("WhiteCat")
    raise AssertionError("удалён курсор райса")
except ValueError:
    pass
PY
}
