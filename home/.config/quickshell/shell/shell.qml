// The rice's menus, on-screen displays and polkit agent (the administrator password window, polkit/) in one
// long-running Quickshell (started from hyprland.lua; the menu scripts in ~/.local/bin start it when it is not
// running). Each menu is loaded when it opens and unloaded when it
// closes; the scripts open and close them over IPC:
//   quickshell ipc -p ~/.config/quickshell/shell call menus toggle <menu> [argument]
// open, close and isOpen work the same way. Menus: launcher, settings, themes, help, power, notif, network, games,
// shots, shot, clipboard. Colours and fonts follow the current theme as it changes (common/Theme.qml).
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Polkit
import qs.osd
import qs.launcher
import qs.settings
import qs.themes
import qs.help
import qs.power
import qs.notif
import qs.network
import qs.games
import qs.shots
import qs.shot
import qs.clipboard
import qs.polkit

ShellRoot {
    id: shell

    readonly property var slots: ({ launcher: launcherSlot, settings: settingsSlot, themes: themesSlot, help: helpSlot,
                                    power: powerSlot, notif: notifSlot, network: networkSlot, games: gamesSlot,
                                    shots: shotsSlot, shot: shotSlot, clipboard: clipboardSlot })

    function slot(name) {
        const found = slots[name];
        if (!found) {
            console.warn("menus: no menu", name);
        }
        return found;
    }

    // The open menu's window, or null.
    function menu(name) {
        const found = slots[name];
        return found && found.item ? found.item : null;
    }

    Osd {}

    MenuSlot { id: launcherSlot; Launcher { argument: launcherSlot.argument } }
    MenuSlot { id: settingsSlot; Settings { argument: settingsSlot.argument } }
    MenuSlot { id: themesSlot; ThemePicker { argument: themesSlot.argument } }
    MenuSlot { id: helpSlot; Help { argument: helpSlot.argument } }
    MenuSlot { id: powerSlot; Power { argument: powerSlot.argument } }
    MenuSlot { id: notifSlot; Notifications { argument: notifSlot.argument } }
    MenuSlot { id: networkSlot; Network { argument: networkSlot.argument } }
    MenuSlot { id: gamesSlot; Games { argument: gamesSlot.argument } }
    MenuSlot { id: shotsSlot; Shots { argument: shotsSlot.argument } }
    MenuSlot { id: shotSlot; Screenshot { argument: shotSlot.argument } }
    MenuSlot { id: clipboardSlot; Clipboard {} }

    // The session's polkit agent: an app asking for an administrator's rights gets the password window.
    PolkitAgent { id: polkitAgent }
    LazyLoader {
        active: polkitAgent.flow !== null
        PolkitDialog { flow: polkitAgent.flow }
    }

    IpcHandler {
        target: "menus"

        function toggle(name: string, argument: string): void {
            shell.slot(name)?.toggle(argument);
        }
        function open(name: string, argument: string): void {
            shell.slot(name)?.open(argument);
        }
        function close(name: string): void {
            shell.slot(name)?.close();
        }
        function isOpen(name: string): bool {
            return !!shell.slot(name)?.active;
        }
    }
}
