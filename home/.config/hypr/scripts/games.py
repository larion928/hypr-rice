#!/usr/bin/env python3
"""The game library of the games window (Alt+G, ~/.config/quickshell/games): what it lists, adds and
starts. The library is the user's own file, ~/.config/hypr-rice/games.json, which rice updates
never touch; covers picked for games are copied to ~/.local/share/hypr-rice/game-covers. The code is
in gamelib/, this file is the command line: COMMANDS is the list of commands.

A game is one of:
  exe       a Windows program, started through Proton (proton-run, with its loading card)
  appimage  an AppImage, made executable and started as it is
  native    any other program file of this machine
  app       an installed program, by its .desktop entry (osu!, a game installed from the AUR, ...)
  steam     a game of the Steam library, started by Steam
"""
import sys
from pathlib import Path

from command_table import Command, printing_json, run
from gamelib import library, steam_games
from gamelib.launch import launch
from gamelib.listing import listing
from gamelib.pictures import find_pictures

ERRORS = (ValueError, OSError)  # OSError: a program or file that cannot be started or read


COMMANDS = {
    "list": Command(
        printing_json(listing), "", "the library as JSON, most recently played first", ERRORS),
    "steam": Command(
        printing_json(steam_games.installed), "",
        "the installed Steam games as JSON (Proton and runtimes left out)", ERRORS),
    "add-file": Command(
        printing_json(lambda path: library.add_file(Path(path))), "<path>",
        "adds a program file; prints the new game as JSON", ERRORS),
    "add-app": Command(
        printing_json(lambda desktop_id, name, icon: library.add(
            {"kind": "app", "target": desktop_id, "name": name, "icon": icon})),
        "<id> <name> <icon>", "adds an installed program by its .desktop id", ERRORS),
    "add-steam": Command(
        printing_json(lambda appid, name: library.add({"kind": "steam", "target": appid, "name": name})),
        "<appid> <name>", "adds a Steam game", ERRORS),
    "rename": Command(library.rename, "<id> <name>", "renames a game; a blank name keeps the old one", ERRORS),
    "cover": Command(
        lambda game_id, image: library.set_cover(game_id, Path(image)), "<id> <image>",
        "copies the image as the game's cover", ERRORS),
    "uncover": Command(
        library.uncover, "<id>", "the game without a cover: its icon, or its first letter", ERRORS),
    "find": Command(
        find_pictures, "",
        "looks for a picture for each game that has none yet (the window runs it)", ERRORS),
    "remove": Command(library.remove, "<id>", "removes the game from the library", ERRORS),
    "launch": Command(launch, "<id>", "starts the game and remembers when", ERRORS),
}


if __name__ == "__main__":
    sys.exit(run("games.py", COMMANDS, sys.argv[1:]))
