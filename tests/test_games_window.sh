# The games window's library (gamelib): kinds, Steam games, covers, launching.

# The games window's library: a program file's kind from its name and first bytes, Steam games without
# Steam's own tools, each game started by the right command.
test_games_library() {
    mkdir -p "$HOME/bin" "$HOME/.local/bin" "$HOME/games" "$HOME/.local/share/Steam/steamapps"
    printf 'MZ\x90\x00' > "$HOME/games/Some_Game.exe"
    printf 'MZ\x90\x00' > "$HOME/games/no-suffix-windows"
    printf '\x7fELF' > "$HOME/games/Tool.AppImage"
    printf '#!/bin/sh\n' > "$HOME/games/native-game"
    chmod +x "$HOME/games/native-game"
    echo text > "$HOME/games/readme.txt"
    printf '"AppState"\n{\n\t"appid"\t\t"%s"\n\t"name"\t\t"%s"\n}\n' 1 "Proton Experimental" \
        > "$HOME/.local/share/Steam/steamapps/appmanifest_1.acf"
    printf '"AppState"\n{\n\t"appid"\t\t"%s"\n\t"name"\t\t"%s"\n}\n' 881100 "Noita" \
        > "$HOME/.local/share/Steam/steamapps/appmanifest_881100.acf"
    printf '#!/bin/sh\necho "$0 $*" >> "%s/started"\n' "$HOME" > "$HOME/.local/bin/proton-run"
    printf '#!/bin/sh\necho "steam $*" >> "%s/started"\n' "$HOME" > "$HOME/bin/steam"
    chmod +x "$HOME/.local/bin/proton-run" "$HOME/bin/steam"
    PATH="$HOME/bin:$PATH" python3 - "$REPO/home/.config/hypr/scripts" "$HOME" <<'PY' || fail "библиотека игр не так"
import sys, time
from pathlib import Path
sys.path.insert(0, sys.argv[1])
from gamelib import launch, library, listing, pictures, steam_games
home = Path(sys.argv[2])
kinds = {name: library.add_file(home / "games" / name)["kind"]
         for name in ("Some_Game.exe", "no-suffix-windows", "Tool.AppImage", "native-game")}
assert kinds == {"Some_Game.exe": "exe", "no-suffix-windows": "exe", "Tool.AppImage": "appimage", "native-game": "native"}, kinds
try:
    library.add_file(home / "games/readme.txt")
    raise AssertionError("текстовый файл принят за игру")
except ValueError:
    pass
again = library.add_file(home / "games/Some_Game.exe")
assert len(library.games()) == 4 and again["name"] == "Some Game", (len(library.games()), again)

assert [g["name"] for g in steam_games.installed()] == ["Noita"], steam_games.installed()
noita = library.add({"kind": "steam", "target": "881100", "name": "Noita"})

launch.launch(again["id"])
launch.launch(noita["id"])
# Both start detached, so they may finish in either order and take a while on a busy machine.
started_file = home / "started"
for _ in range(50):
    if started_file.exists() and len(started_file.read_text().splitlines()) == 2:
        break
    time.sleep(0.1)
started = sorted(started_file.read_text().splitlines())
assert started == sorted([f"{home}/.local/bin/proton-run {home}/games/Some_Game.exe", "steam steam://rungameid/881100"]), started
assert listing.listing()[0]["id"] in (again["id"], noita["id"]) and library.game(noita["id"])["played"] > 0

(home / "games/native-game").unlink()
native = next(g for g in listing.listing() if g["kind"] == "native")
assert not native["present"]
try:
    launch.launch(native["id"])
    raise AssertionError("запущена игра, которой нет")
except ValueError:
    pass
library.remove(native["id"])
assert all(g["kind"] != "native" for g in library.games())
PY
}

# A game without a cover gets one found for it: the store's cover of a game of the very same name
# (a similar name is another game), else an icon from the game's folder; looked for only once.
test_games_find_pictures() {
    mkdir -p "$HOME/games/Pinball" "$HOME/store"
    printf 'MZ' > "$HOME/games/Pinball/pinball.exe"
    printf 'PNG' > "$HOME/games/Pinball/icon.png"
    printf '\xff\xd8 a jpeg' > "$HOME/store/cover.jpg"
    echo '{"items": [{"id": 1, "name": "Balatro"}, {"id": 2, "name": "McOsu"}]}' > "$HOME/store/search.json"
    python3 - "$REPO/home/.config/hypr/scripts" "$HOME" <<'PY' || fail "картинки для игр найдены не так"
import sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
import urllib.error
import urllib.request
from gamelib import launch, library, listing, pictures, steam_games
home = Path(sys.argv[2])
pictures.STORE_SEARCH = f"file://{home}/store/search.json?{{}}"
pictures.STORE_COVERS = (f"file://{home}/store/missing-{{}}.jpg", f"file://{home}/store/cover.jpg?{{}}")
# The store answers 404 for a cover size it has not; file:// would say "no connection" instead.
real_urlopen = urllib.request.urlopen
def store_urlopen(url, timeout=None):
    if "missing-" in url:
        raise urllib.error.HTTPError(url, 404, "Not Found", None, None)
    return real_urlopen(url, timeout=timeout)
urllib.request.urlopen = store_urlopen
pinball = library.add_file(home / "games/Pinball/pinball.exe")
balatro = library.add({"kind": "app", "target": "Balatro", "name": "Balatro", "icon": "balatro"})
osu = library.add({"kind": "app", "target": "osu", "name": "osu!", "icon": "osu"})
pictures.find_pictures()
assert library.game(pinball["id"]).get("icon") == str(home / "games/Pinball/icon.png"), library.game(pinball["id"])
assert Path(library.game(balatro["id"])["cover"]).read_bytes().startswith(b"\xff\xd8"), library.game(balatro["id"])
assert not library.game(osu["id"]).get("cover"), "osu! получила обложку чужой игры (McOsu)"
assert all(entry.get("looked") for entry in library.games())

(home / "store/search.json").write_text('{"items": [{"id": 3, "name": "osu!"}]}')
pictures.find_pictures()
assert not library.game(osu["id"]).get("cover"), "поиск повторился для уже просмотренной игры"
library.uncover(balatro["id"])
assert library.game(balatro["id"])["cover"] == "" and not list((home / ".local/share/hypr-rice/game-covers").glob(balatro["id"] + ".*"))

# Offline: the game's own icon is found all the same, and the game is left unlooked so the store is
# asked again next time.
(home / "games/Solitaire").mkdir()
(home / "games/Solitaire/solitaire.exe").write_bytes(b"MZ")
(home / "games/Solitaire/icon.png").write_bytes(b"PNG")
solitaire = library.add_file(home / "games/Solitaire/solitaire.exe")
def offline(url, timeout=None):
    raise urllib.error.URLError("no network")
urllib.request.urlopen = offline
pictures.find_pictures()
offline_game = library.game(solitaire["id"])
assert offline_game.get("icon") == str(home / "games/Solitaire/icon.png"), offline_game
assert not offline_game.get("looked"), "без сети игра помечена просмотренной"
PY
}

# With GameMode on, games run under gamemoderun, the Steam client never: under it Steam's browser part
# does not start (error 0x3018).
test_games_gamemode_not_for_steam() {
    mkdir -p "$HOME/bin" "$HOME/.config/hypr-rice"
    printf '#!/bin/sh\n' > "$HOME/bin/gamemoderun"
    chmod +x "$HOME/bin/gamemoderun"
    touch "$HOME/.config/hypr-rice/gamemode"
    PATH="$HOME/bin:$PATH" python3 - "$REPO/home/.config/hypr/scripts" <<'PY' || fail "gamemoderun не там"
import sys
sys.path.insert(0, sys.argv[1])
from gamelib import launch, library, listing, pictures, steam_games
assert launch.command_for({"kind": "app", "target": "steam"}) == ["gtk-launch", "steam"]
assert launch.command_for({"kind": "app", "target": "osu"}) == ["gamemoderun", "gtk-launch", "osu"]
assert launch.command_for({"kind": "steam", "target": "881100"}) == ["steam", "steam://rungameid/881100"]
PY
}
