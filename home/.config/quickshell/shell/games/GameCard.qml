import QtQuick
import Quickshell.Widgets
import qs.common
import "../common/url.js" as Url

// A game: its cover (or its program's icon, or its first letter), its name and how it starts.
Item {
    id: card

    property var game
    property bool chosen
    property string kindName
    property string iconSource

    signal hovered()
    signal launched()
    signal edited()

    width: 196
    height: 330

    // Hover from a handler: it stays on over the edit button too, which a MouseArea would lose.
    HoverHandler {
        id: hover
        onHoveredChanged: if (hovered) card.hovered()
    }

    Rectangle {
        id: coverBox
        x: 8; y: 8; width: 180; height: 270
        radius: Theme.radius(12)
        color: Theme.bg2
        clip: true
        border.width: card.chosen || hover.hovered ? 2 : 0
        border.color: Theme.accent
        opacity: card.game.present ? 1 : 0.45
        scale: hover.hovered ? 1.03 : 1
        Behavior on scale { NumberAnimation { duration: 120 } }

        Image {
            id: coverImage
            anchors.fill: parent
            anchors.margins: parent.border.width
            visible: card.game.cover !== ""
            source: Url.fromPath(card.game.cover)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }
        IconImage {
            id: iconImage
            anchors.centerIn: parent
            visible: !coverImage.visible && source != ""
            implicitSize: 96
            source: card.iconSource
        }
        Text {
            anchors.centerIn: parent
            visible: !coverImage.visible && !iconImage.visible
            text: card.game.name.charAt(0).toUpperCase()
            font.family: Theme.titleFont; font.pixelSize: 96
            color: Theme.accent
        }
        Rectangle {
            anchors { left: parent.left; bottom: parent.bottom; margins: 8 }
            width: kindText.implicitWidth + 12; height: 22
            radius: 6
            color: Theme.alpha(Theme.bg, 0.85)
            Text {
                id: kindText
                anchors.centerIn: parent
                text: card.game.present ? card.kindName : "нет на месте"
                font.family: Theme.bodyFont; font.pixelSize: 12
                color: card.game.present ? Theme.muted : Theme.crit
            }
        }
        IconButton {
            anchors { right: parent.right; top: parent.top; margins: 8 }
            visible: hover.hovered
            filled: true
            glyph: "\u{f03eb}"
            onClicked: card.edited()
        }
    }
    Text {
        anchors { left: coverBox.left; right: coverBox.right; top: coverBox.bottom; topMargin: 8 }
        text: card.game.name
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignHCenter
        font.family: Theme.bodyFont; font.pixelSize: 15
        color: card.chosen ? Theme.accent : Theme.fg
    }
    MouseArea {
        anchors.fill: coverBox
        z: -1
        onClicked: card.launched()
    }
}
