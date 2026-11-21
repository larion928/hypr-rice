# Themes of the user's own, and the rice's themes removed, restored and reset.

# A fake $HOME with themegen and the coffee theme, edited in the settings window in every way.
user_theme_home() {
    mkdir -p "$HOME/.config/hypr/themes" "$HOME/.config/hypr-rice/waybar" "$HOME/Pictures"
    cp -r "$REPO/home/.config/hypr/scripts" "$HOME/.config/hypr/"
    cp -r "$REPO/home/.config/hypr/themes/coffee" "$REPO/home/.config/hypr/themes/night" "$HOME/.config/hypr/themes/"
    cp "$REPO/home/.config/hypr-rice/waybar/config.base.json" "$HOME/.config/hypr-rice/waybar/"
    sed -i "s|__HOME__|$HOME|g" "$HOME"/.config/hypr/themes/*/style.css  # as rice installs them
    cp "$(ls "$HOME"/.config/hypr/themes/night/*.png | head -1)" "$HOME/Pictures/mine.png"
    local off
    off=$(ls "$HOME"/.config/hypr/themes/coffee/*.png | head -1)
    cat > "$HOME/.config/hypr-rice/theme-edits.json" <<JSON
{"themes": {"coffee": {"colors": {"accent": "#123456"}, "fonts": {"font": "Iosevka", "body": "Inter"},
  "wallpapers": {"off": ["$off"], "added": ["$HOME/Pictures/mine.png"]},
  "waybar": {"modules-left": ["clock"], "modules-center": [], "modules-right": ["memory"], "position": "bottom"},
  "icons": {"memory": "X"}, "windows": {"gaps_in": 3, "animations": "off"},
  "iconTheme": "breeze-dark", "folders": "teal", "battery": "night"}}}
JSON
    echo "$off" > "$HOME/off-wallpaper"
}

# A theme made from an edited one looks the same (its edits written into its own files), lives
# where updates do not reach, and goes out and comes back as an archive.
test_user_theme_from_edited_theme() {
    user_theme_home
    python3 - "$HOME/.config/hypr/scripts" "$HOME" <<'PY' || fail "своя тема собрана не так"
import dataclasses, json, sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
from apptheme.desktop import waybar, windows
from apptheme.themes import user_themes
from apptheme.themes.theme import all_names, load
home = Path(sys.argv[2])

name = user_themes.create("Моя тема", "coffee")
assert name == "moya-tema", name
link = home / ".config/hypr/themes" / name
assert link.is_symlink() and link.resolve() == home / ".config/hypr-rice/themes" / name, link
assert name in all_names()

made, source = load(name), load("coffee")
assert made.edits == {} and made.label == "Моя тема", (made.edits, made.label)
assert made.colors == source.colors and made.colors["accent"] == "#123456"
assert made.font == "Iosevka" and made.body_font == "Inter"
assert made.ui["iconTheme"] == "breeze-dark" and made.ui["folders"] == "teal"
assert (made.dir / "battery.py").read_text() == (home / ".config/hypr/themes/night/battery.py").read_text()
names = [path.name for path in made.wallpapers]
assert "mine.png" in names and Path((home / "off-wallpaper").read_text().strip()).name not in names, names
for key in ("modules-left", "modules-right", "position"):
    assert waybar.config_for(made)[key] == waybar.config_for(dataclasses.replace(source, shared={}))[key], key
assert "X" in json.dumps(waybar.config_for(made)["memory"]), waybar.config_for(made)["memory"]
assert windows.own(made)["gaps_in"] == 3, windows.own(made)
assert "animations = { enabled = false }" in (made.dir / "hypr.lua").read_text()

style = (made.dir / "style.css").read_text()
assert f"{home}/.config/hypr/themes/moya-tema/assets/battery-0.svg" in style and "themes/coffee/" not in style, \
    "копия ссылается на картинки исходной темы"

archive = home / "moya.zip"
user_themes.export(name, archive)
import zipfile
packed = zipfile.ZipFile(archive).read("moya-tema/style.css").decode()
assert str(home) not in packed and "__HOME__/.config/hypr/themes/moya-tema/" in packed, "в архиве путь этой машины"
again = user_themes.import_archive(archive)
assert again == "moya-tema-2" and load(again).colors == made.colors, again
style = (load(again).dir / "style.css").read_text()
assert f"{home}/.config/hypr/themes/moya-tema-2/assets/" in style and "__HOME__" not in style, "пути после импорта не те"

user_themes.promote(again)
promoted = home / ".config/hypr/themes" / again
assert promoted.is_dir() and not promoted.is_symlink() and not (home / ".config/hypr-rice/themes" / again).exists()

try:
    user_themes.delete("coffee")
    raise AssertionError("тема райса удалилась")
except ValueError:
    pass
user_themes.delete(name)
assert not link.exists() and not link.is_symlink() and name not in all_names()
PY
}

# An archive that is not one theme folder, or a folder without what changetheme needs, is refused.
test_user_theme_import_refuses_bad_archives() {
    user_theme_home
    python3 - "$HOME/.config/hypr/scripts" "$HOME" <<'PY' || fail "плохой архив принят"
import shutil, sys, zipfile
from pathlib import Path
sys.path.insert(0, sys.argv[1])
from apptheme.themes import user_themes
home = Path(sys.argv[2])
coffee = home / ".config/hypr/themes/coffee"

def archive(name, members):
    path = home / name
    with zipfile.ZipFile(path, "w") as out:
        for member, source in members:
            out.write(source, member)
    return path

def refused(path, reason):
    try:
        user_themes.import_archive(path)
    except ValueError as error:
        assert reason in str(error), (reason, error)
        return
    raise AssertionError(f"{path.name} принят")

refused(archive("escape.zip", [("../evil.txt", coffee / "palette.json")]), "за пределы")
refused(archive("two.zip", [("a/palette.json", coffee / "palette.json"), ("b/hypr.lua", coffee / "hypr.lua")]), "одна папка")
refused(archive("nolua.zip", [("t/palette.json", coffee / "palette.json"), ("t/style.css", coffee / "style.css")]), "hypr.lua")
assert not any((home / ".config/hypr-rice/themes").glob("*")), "отказанный архив оставил тему"
PY
}

# A rice theme with the name of a user theme (an update brought one) keeps its folder; the user's
# stays hidden, not overwritten.
test_user_theme_yields_to_rice_theme() {
    user_theme_home
    mkdir -p "$HOME/.config/hypr-rice/themes/coffee"
    echo '{}' > "$HOME/.config/hypr-rice/themes/coffee/palette.json"
    python3 - "$HOME/.config/hypr/scripts" <<'PY' 2>"$HOME/err" || fail "ссылка заменила тему райса"
import sys
sys.path.insert(0, sys.argv[1])
from apptheme.themes import user_themes
from apptheme.paths import THEMES
user_themes.link()
assert not (THEMES / "coffee").is_symlink() and (THEMES / "coffee/hypr.lua").exists()
PY
    grep -q 'скрыта' "$HOME/err" || fail "нет предупреждения о совпадении имён"
}

# A theme of the rice is removed (not the current one) and comes back from the rice's copy of its
# repository.
test_rice_theme_removed_and_restored() {
    user_theme_home
    mkdir -p "$HOME/.local/bin"
    ln -s "$REPO/rice" "$HOME/.local/bin/rice"
    echo night > "$HOME/.config/hypr/current-theme"
    python3 - "$HOME/.config/hypr/scripts" "$HOME" <<'PY' || fail "удаление или возврат темы райса не так"
import sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
import themegen
from apptheme.themes import removed_themes
from apptheme.themes.theme import all_names
home = Path(sys.argv[2])

try:
    themegen.delete_theme("night")
    raise AssertionError("удалилась включённая тема")
except ValueError:
    pass
themegen.delete_theme("coffee")
assert "coffee" not in all_names() and removed_themes.names() == ["coffee"]
assert removed_themes.listing() == [{"name": "coffee", "label": "Coffee"}], removed_themes.listing()
assert "coffee" in __import__("json").loads((home / ".config/hypr-rice/theme-edits.json").read_text())["themes"], \
    "правки удалённой темы пропали"
removed_themes.restore("coffee")
assert "coffee" in all_names() and removed_themes.names() == []
PY
}

# «К заводским»: a theme of the rice loses its edits, its added wallpapers and changes made by hand in
# its folder; it is the rice's again.
test_factory_reset() {
    user_theme_home
    mkdir -p "$HOME/.local/bin" "$HOME/.local/share/hypr-rice/wallpapers/coffee"
    ln -s "$REPO/rice" "$HOME/.local/bin/rice"
    touch "$HOME/.local/share/hypr-rice/wallpapers/coffee/added.png"
    echo "-- broken by hand" >> "$HOME/.config/hypr/themes/coffee/hypr.lua"
    touch "$HOME/.config/hypr/themes/coffee/stray.png"
    python3 - "$HOME/.config/hypr/scripts" "$HOME" <<'PY' || fail "тема не вернулась к заводской"
import json, sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
from apptheme.themes import factory_reset
from apptheme.themes.theme import load
home = Path(sys.argv[2])
factory_reset.reset("coffee")
coffee = home / ".config/hypr/themes/coffee"
assert load("coffee").edits == {}
assert not (home / ".local/share/hypr-rice/wallpapers/coffee").exists()
assert "broken by hand" not in (coffee / "hypr.lua").read_text() and not (coffee / "stray.png").exists()
assert load("night").name == "night"
PY
}
