// The current theme as the panels use it: the theme folder's palette.json and ui.json and the
// fonts they name. Every panel folder reaches this one through its symlink "common", because
// Quickshell refuses imports from outside a config's folder.
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: theme

    // Panels opened by panel.sh get the folder in $RICE_THEME_DIR; the OSD runs all session and
    // points it at whichever theme is current.
    property string dir: Quickshell.env("RICE_THEME_DIR")
    readonly property var pal: parse(palFile.text(), { colors: {} })
    readonly property var ui: parse(uiFile.text(), {})
    readonly property var c: pal.colors || {}
    readonly property string font: pal.font || "monospace"
    readonly property string titleFont: ui.titleFont === "display" ? (pal.display || "serif") : font
    readonly property string bodyFont: !ui.bodyFont || ui.bodyFont === "font" ? font
                                       : ui.bodyFont === "display" ? (pal.display || "serif") : ui.bodyFont

    function parse(text, fallback) {
        try { return JSON.parse(text); } catch (e) { return fallback; }
    }

    FileView { id: palFile; path: theme.dir ? theme.dir + "/palette.json" : ""; blockLoading: true }
    FileView { id: uiFile; path: theme.dir ? theme.dir + "/ui.json" : ""; blockLoading: true }
}
