pragma Singleton

// The palette following the theme's wallpaper clip: where the clip turns grey, so do the menus, notifications and
// the rest the shell draws, the bar and the window borders. The theme names its clip and the clip's colour, second
// by second, in ui.json "clipColour": {"clip": a file in the theme's folder, "track": a JSON list of 0..1 per second
// made by `themegen.py clip-colour <clip>`}. Only while that very clip plays: another wallpaper on the same theme
// keeps the full palette.
// The shell's own colours move smoothly (Theme.colourfulness); the bar and the borders in outsideSteps steps a full
// fade, since each step rewrites the bar's style (waybar rereads clip-colours.css, imported last by waybar-start)
// and sends Hyprland the borders.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

Singleton {
    id: clipColour

    // Seconds over which the palette moves to a new colourfulness: the clip's own fades take about as long.
    readonly property int fadeMs: 1200
    readonly property int outsideSteps: 8
    // The bar's colours named in every theme's wallust-colors.css; good, warn and crit keep theirs, as in the shell.
    readonly property var barColours: ["bg", "bg2", "fg", "muted", "accent", "accent2", "accent3"]

    readonly property var setup: Theme.ui.clipColour || null
    readonly property bool following: setup !== null && Wallpaper.connected && Wallpaper.path === Theme.dir + "/" + setup.clip
    readonly property var track: following ? Theme.parse(trackFile.text(), []) : []
    readonly property real target: track.length ? (track[Math.min(track.length - 1, Math.floor(Wallpaper.position))] ?? 1) : 1
    readonly property real outsideShare: Math.round(Theme.colourfulness * outsideSteps) / outsideSteps

    // Hyprland's borders as the theme set them ({active, inactive}: {colors, angle}), read when following starts.
    property var borders: null
    property bool bordersGrey: false

    onFollowingChanged: {
        Wallpaper.positionWatchers += following ? 1 : -1;
        if (following) {
            bordersReader.running = true;
        } else {
            stopOutside();
        }
    }
    Component.onCompleted: {
        if (following) {
            Wallpaper.positionWatchers += 1;
            bordersReader.running = true;
        }
        barFile.setText("");  // a shell that stopped mid-fade may have left the bar grey
    }
    onTargetChanged: {
        fade.to = target;
        fade.restart();
    }
    onOutsideShareChanged: {
        if (following) {
            paintOutside(outsideShare);
        }
    }

    function paintOutside(share) {
        barFile.setText(share >= 1 ? "" : barColours.filter(name => Theme.colors[name])
            .map(name => "@define-color " + name + " " + Theme.towardsGrey(Theme.colors[name], share) + ";\n").join(""));
        if (borders) {
            sendBorders(share);
        }
    }

    // Leaving the clip: the bar and the borders get the theme's colours back at once, without the fade, since a
    // theme change (its wallpaper goes first) reloads Hyprland right after and the old borders must not follow it.
    function stopOutside() {
        barFile.setText("");
        if (bordersGrey) {
            sendBorders(1);
        }
        borders = null;
    }

    function sendBorders(share) {
        const gradient = border => "{colors={" + border.colors.map(colour => '"' + Theme.towardsGrey(colour, share) + '"').join(",")
                                   + "},angle=" + border.angle + "}";
        Quickshell.execDetached(["hyprctl", "eval", "hl.config({general={col={active_border=" + gradient(borders.active)
                                 + ",inactive_border=" + gradient(borders.inactive) + "}}})"]);
        bordersGrey = share < 1;
    }

    // hyprctl's "ffe3a857 fff3e3c0 45deg" (AARRGGBB colours, then the angle) as {colors: ["#e3a857ff", ...], angle: 45}.
    function readGradient(gradient) {
        const parts = gradient.split(" ");
        return { colors: parts.slice(0, -1).map(colour => "#" + colour.slice(2) + colour.slice(0, 2)),
                 angle: parseInt(parts[parts.length - 1]) };
    }

    NumberAnimation {
        id: fade
        target: Theme
        property: "colourfulness"
        duration: clipColour.fadeMs
        easing.type: Easing.InOutQuad
    }

    FileView {
        id: trackFile
        path: clipColour.setup ? Theme.dir + "/" + clipColour.setup.track : ""
        blockLoading: true
    }

    FileView {
        id: barFile
        path: Quickshell.env("HOME") + "/.config/hypr-rice/waybar/clip-colours.css"
    }

    Process {
        id: bordersReader
        command: ["sh", "-c", "hyprctl -j getoption general:col.active_border; hyprctl -j getoption general:col.inactive_border"]
        stdout: StdioCollector {
            onStreamFinished: {
                const gradients = [];
                const pattern = /"gradient": *"([^"]+)"/g;
                for (let match = pattern.exec(this.text); match; match = pattern.exec(this.text)) {
                    gradients.push(match[1]);
                }
                if (gradients.length !== 2) {
                    return;  // no Hyprland to ask: the borders stay as they are
                }
                clipColour.borders = { active: clipColour.readGradient(gradients[0]), inactive: clipColour.readGradient(gradients[1]) };
                if (clipColour.following && clipColour.outsideShare < 1) {
                    clipColour.sendBorders(clipColour.outsideShare);
                }
            }
        }
    }
}
