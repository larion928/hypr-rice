pragma Singleton

// The current theme as the menus draw it: palette.json and ui.json as themegen wrote them to ~/.config/hypr
// (the theme's own, with the user's edits in place), and the theme's folder for its pictures and sounds.
// All three are watched, so whatever is open redraws when changetheme switches the theme.
import QtQuick
import Quickshell
import Quickshell.Io
import "url.js" as Url

Singleton {
    id: theme

    readonly property string hypr: Quickshell.env("HOME") + "/.config/hypr"
    readonly property string name: currentFile.text().trim()
    readonly property string dir: name ? hypr + "/themes/" + name : ""

    readonly property var pal: parse(paletteFile.text(), { colors: {} })
    readonly property var ui: parse(uiFile.text(), {})

    // A theme without one of these colours gets the stand-in, so a menu never draws with an undefined colour.
    readonly property var colors: pal.colors || {}
    readonly property string bg: colors.bg || "#000000"
    readonly property string bg2: colors.bg2 || "#202020"
    readonly property string fg: colors.fg || "#ffffff"
    readonly property string muted: colors.muted || "#808080"
    readonly property string accent: colors.accent || "#ffffff"
    readonly property string accent2: colors.accent2 || accent
    readonly property string accent3: colors.accent3 || accent
    readonly property string good: colors.good || "#00c000"
    readonly property string warn: colors.warn || "#e0c000"
    readonly property string crit: colors.crit || "#ff0000"

    readonly property string font: pal.font || "monospace"
    readonly property string titleFont: ui.titleFont === "display" ? (pal.display || "serif") : font
    readonly property string bodyFont: !ui.bodyFont || ui.bodyFont === "font" ? font
                                       : ui.bodyFont === "display" ? (pal.display || "serif") : ui.bodyFont
    // The menus' icons are Nerd Font code points; the theme's main font may be any font the user picked, so the
    // icons keep the one the rice installs.
    readonly property string glyphFont: "JetBrainsMono Nerd Font"

    readonly property bool italicTitle: !!ui.italicTitle
    // A display font drawn larger than most at the same size (a wide pixel font) is scaled down by its theme.
    readonly property real titleScale: ui.titleScale ?? 1
    readonly property int border: ui.border ?? 1
    readonly property int slideMs: ui.slideMs ?? 260
    readonly property int cardRadius: ui.cardRadius ?? 10
    // A square theme (radius 4 or less) keeps small parts square too.
    readonly property bool rounded: radius(14) > 4

    // The theme's corner radius, capped for a part whose size cannot take more.
    function radius(max) {
        return Math.min(ui.radius ?? 14, max);
    }

    // A size given for titles, as the theme's title font needs it.
    function titleSize(px) {
        return Math.round(px * titleScale);
    }

    // A title as the theme writes titles: some themes in upper case.
    function title(text) {
        return ui.upperTitle ? String(text).toUpperCase() : text;
    }

    // colour ("#RRGGBB") at the given opacity (0..1), in Qt's "#AARRGGBB" form.
    function alpha(colour, opacity) {
        return "#" + ("0" + Math.round(opacity * 255).toString(16)).slice(-2) + String(colour || "#888888").slice(1);
    }

    function parse(text, fallback) {
        try {
            return JSON.parse(text);
        } catch (e) {
            return fallback;
        }
    }

    // A theme may bring its fonts (ui.json "fonts": files in its folder). fontconfig shows them to every other
    // program, but a running Qt reads the font list once, at start: the shell loads them itself.
    Instantiator {
        model: theme.ui.fonts || []
        delegate: FontLoader {
            required property string modelData
            source: Url.fromPath(theme.dir + "/" + modelData)
        }
    }

    FileView { id: currentFile; path: theme.hypr + "/current-theme"; blockLoading: true; watchChanges: true; onFileChanged: reload() }
    FileView { id: paletteFile; path: theme.hypr + "/palette.json"; blockLoading: true; watchChanges: true; onFileChanged: reload() }
    FileView { id: uiFile; path: theme.hypr + "/ui.json"; blockLoading: true; watchChanges: true; onFileChanged: reload() }
}
