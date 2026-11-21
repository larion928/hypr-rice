pragma Singleton

// Every theme with its palette, ui, edits, wallpapers and thumbnail (theme-list.py), for the theme picker, the
// launcher's theme commands and the settings window. Read when the shell starts and again whenever one of them
// opens or a theme is added or removed (refreshed() then); until a refresh is in, the menu shows the last list.
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: list

    property var themes: []
    // The last answer as text: an identical one leaves `themes` alone, so open menus keep their cards as they are.
    property string themesJson: ""

    signal refreshed()

    function refresh() {
        reader.running = true;
    }

    // The list changed here (a theme's edits saved): shown at once, and the next read replaces it whatever it says.
    function replace(changed) {
        themes = changed;
        themesJson = "";
    }

    Component.onCompleted: refresh()

    Process {
        id: reader
        command: ["python3", Quickshell.shellDir + "/services/theme-list.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (this.text !== list.themesJson) {
                    try {
                        list.themes = JSON.parse(this.text);
                        list.themesJson = this.text;
                    } catch (e) {
                        console.warn("theme-list.py:", e);
                    }
                }
                list.refreshed();
            }
        }
    }
}
