pragma Singleton

// The shell's palette following the theme's wallpaper clip: where the clip turns grey, so do the menus,
// notifications and the rest the shell draws. The theme names its clip and the clip's colour, second by second,
// in ui.json "clipColour": {"clip": a file in the theme's folder, "track": a JSON list of 0..1 per second made by
// `themegen.py clip-colour <clip>`}. Only while that very clip plays: another wallpaper on the same theme keeps the
// full palette.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

Singleton {
    id: clipColour

    // Seconds over which the palette moves to a new colourfulness: the clip's own fades take about as long.
    readonly property int fadeMs: 1200

    readonly property var setup: Theme.ui.clipColour || null
    readonly property bool following: setup !== null && Wallpaper.connected && Wallpaper.path === Theme.dir + "/" + setup.clip
    readonly property var track: following ? Theme.parse(trackFile.text(), []) : []
    readonly property real target: track.length ? (track[Math.min(track.length - 1, Math.floor(Wallpaper.position))] ?? 1) : 1

    onFollowingChanged: Wallpaper.positionWatchers += following ? 1 : -1
    Component.onCompleted: {
        if (following) {
            Wallpaper.positionWatchers += 1;
        }
    }
    onTargetChanged: {
        fade.to = target;
        fade.restart();
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
}
