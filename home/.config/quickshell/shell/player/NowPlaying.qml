import QtQuick
import Quickshell.Services.Mpris
import qs.common
import qs.services

// The player card's track: the cover (a note when the player gives none), the title, the artist and which
// program plays it.
Item {
    id: track

    property MprisPlayer player

    implicitHeight: cover.height

    Rectangle {
        id: cover
        width: 96; height: 96
        radius: Theme.radius(12)
        color: Theme.alpha(Theme.accent, 0.14)
        clip: true

        Text {
            anchors.centerIn: parent
            visible: art.status !== Image.Ready
            text: Players.musicGlyph
            font.family: Theme.glyphFont; font.pixelSize: 40
            color: Theme.accent
        }

        Image {
            id: art
            anchors.fill: parent
            source: track.player ? track.player.trackArtUrl : ""
            sourceSize: Qt.size(192, 192)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }
    }

    Column {
        anchors { left: cover.right; leftMargin: 14; right: parent.right; verticalCenter: parent.verticalCenter }
        spacing: 4

        Text {
            width: parent.width
            maximumLineCount: 2
            wrapMode: Text.Wrap
            elide: Text.ElideRight
            text: track.player && track.player.trackTitle ? track.player.trackTitle : "Без названия"
            font.family: Theme.bodyFont; font.pixelSize: 16; font.bold: true
            color: Theme.fg
        }
        Text {
            visible: text !== ""
            width: parent.width
            elide: Text.ElideRight
            text: track.player ? track.player.trackArtist : ""
            font.family: Theme.bodyFont; font.pixelSize: 13
            color: Theme.fg
        }
        Text {
            width: parent.width
            elide: Text.ElideRight
            text: track.player ? track.player.identity : ""
            font.family: Theme.bodyFont; font.pixelSize: 11
            color: Theme.muted
        }
    }
}
