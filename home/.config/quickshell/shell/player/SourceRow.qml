import QtQuick
import Quickshell.Services.Mpris
import qs.common
import qs.services

// One player in the card's source list: its program and track; a click makes it the active one.
Rectangle {
    id: row

    property MprisPlayer player
    property bool current

    signal picked()

    height: 40
    radius: Theme.radius(12)
    color: current ? Theme.alpha(Theme.accent, 0.14)
           : area.containsMouse ? Theme.alpha(Theme.fg, 0.06) : "transparent"
    border.width: current ? 1 : 0
    border.color: Theme.alpha(Theme.accent, 0.5)

    Text {
        id: stateGlyph
        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
        text: row.player && row.player.isPlaying ? Players.musicGlyph : Players.pauseGlyph
        font.family: Theme.glyphFont; font.pixelSize: 15
        color: row.current ? Theme.accent : Theme.muted
    }

    Text {
        anchors { left: stateGlyph.right; leftMargin: 10; right: parent.right; rightMargin: 12 }
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideRight
        text: row.player ? row.player.identity + (row.player.trackTitle ? " · " + row.player.trackTitle : "") : ""
        font.family: Theme.bodyFont; font.pixelSize: 13
        color: Theme.fg
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: row.picked()
    }
}
