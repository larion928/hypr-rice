"""Starting a game: Proton for a Windows program, Steam for a Steam game, the program itself otherwise."""
import shutil
import subprocess
import time
from pathlib import Path

from .library import HOME, change, game
from .listing import present

# Switched on in rice → Игры: оптимизация: games run under gamemoderun. A Windows game gets it from
# proton-run, a Steam game only from its launch options in Steam (Steam starts it, not this script).
GAMEMODE_MARK = HOME / ".config/hypr-rice/gamemode"
# The Steam client added as a program is a launcher, not a game: under gamemoderun every one of its
# helpers loads gamemode's library too, and its browser part (steamwebhelper, in Steam's own container)
# then does not start: error 0x3018. Its games get GameMode from their launch options in Steam.
NOT_UNDER_GAMEMODE = ("steam", "com.valvesoftware.Steam")


def command_for(entry):
    target = entry["target"]
    if entry["kind"] == "exe":
        return [str(HOME / ".local/bin/proton-run"), target]
    if entry["kind"] == "steam":
        return ["steam", f"steam://rungameid/{target}"]
    if entry["kind"] == "app":
        prefix = [] if target in NOT_UNDER_GAMEMODE else gamemode()
        return [*prefix, "gtk-launch", target]
    Path(target).chmod(Path(target).stat().st_mode | 0o111)
    return [*gamemode(), target]


def gamemode():
    return ["gamemoderun"] if GAMEMODE_MARK.exists() and shutil.which("gamemoderun") else []


def launch(game_id):
    entry = game(game_id)
    if not present(entry):
        raise ValueError(f"«{entry['name']}» больше нет на месте: {entry['target']}")
    folder = Path(entry["target"]).parent if entry["kind"] in ("exe", "appimage", "native") else HOME
    subprocess.Popen(command_for(entry), cwd=folder, start_new_session=True,
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    change(game_id, played=int(time.time()))
