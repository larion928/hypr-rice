// The current theme as the panels use it: palette.json and ui.json as themegen wrote them to
// ~/.config/hypr (the theme's own, with the fonts the user picked for it in place), and the fonts they
// name. Every panel folder reaches this one through its symlink "common", because Quickshell refuses
// imports from outside a config's folder.
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: theme

    // The theme's folder, for its pictures and sounds. Panels opened by panel.sh get it in
    // $RICE_THEME_DIR; the OSD runs all session and points it at whichever theme is current.
    property string dir: Quickshell.env("RICE_THEME_DIR")
    readonly property string generated: Quickshell.env("HOME") + "/.config/hypr"
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

    // Watched: the OSD stays open while the theme or its fonts change.
    FileView { id: palFile; path: theme.generated + "/palette.json"; blockLoading: true; watchChanges: true; onFileChanged: reload() }
    FileView { id: uiFile; path: theme.generated + "/ui.json"; blockLoading: true; watchChanges: true; onFileChanged: reload() }
}
