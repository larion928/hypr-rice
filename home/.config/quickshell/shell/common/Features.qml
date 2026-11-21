pragma Singleton

// The rice's features the user switched on or off (Alt+F2 → Функции): ~/.config/hypr-rice/features.json as
// ~/.config/hypr/scripts/features.py writes it, a flat {"id": true|false} of every feature. Watched, so a
// switch takes effect in whatever is open. A feature the file does not list is off.
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    readonly property string script: Quickshell.env("HOME") + "/.config/hypr/scripts/features.py"
    readonly property var state: parse(stateFile.text())

    function on(feature) {
        return state[feature] === true;
    }

    function parse(text) {
        try {
            return JSON.parse(text) || {};
        } catch (error) {
            return {};
        }
    }

    FileView {
        id: stateFile
        path: Quickshell.env("HOME") + "/.config/hypr-rice/features.json"
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
    }
}
