import QtQuick
import QtQuick.Effects
import Quickshell.Widgets
import qs.common
import "../common/url.js" as Url

// One theme in its own colours and fonts: its wallpaper, its mark and name, its palette and the window border
// gradient. Cards appear one after another when the picker opens.
Item {
    id: card

    property var entry
    property int number
    property bool selected
    property bool compact

    signal hovered()
    signal picked()

    readonly property var c: entry.pal.colors
    readonly property real r: Math.min(entry.ui.radius ?? 12, 22)

    width: compact ? 300 : 320
    height: compact ? 332 : 372
    opacity: 0

    Component.onCompleted: appear.start()
    SequentialAnimation {
        id: appear
        PauseAnimation { duration: (card.number - 1) * 55 }
        ParallelAnimation {
            NumberAnimation { target: card; property: "opacity"; to: 1; duration: 260 }
            NumberAnimation { target: face; property: "y"; from: 46; to: 0; duration: 380; easing.type: Easing.OutCubic }
        }
    }

    Rectangle {
        id: face
        width: parent.width
        height: parent.height
        radius: card.r
        color: card.c.bg
        border.width: card.selected ? 2 : 1
        border.color: card.selected ? card.c.accent : Theme.alpha(card.c.muted, 0.4)
        scale: card.selected ? 1.06 : 0.97
        opacity: card.selected ? 1 : 0.62
        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
        Behavior on opacity { NumberAnimation { duration: 180 } }

        layer.enabled: card.selected
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: card.c.accent
            shadowBlur: 1
            shadowHorizontalOffset: 0; shadowVerticalOffset: 0
            blurMax: 40
        }

        ClippingRectangle {
            id: thumb
            x: 10; y: 10
            width: parent.width - 20
            height: width * 9 / 16
            radius: Math.max(0, card.r - 4)
            color: card.c.bg2
            Image {
                anchors.fill: parent
                source: Url.fromPath(card.entry.thumb)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }
        }

        Row {
            id: title
            anchors { left: parent.left; leftMargin: 16; top: thumb.bottom; topMargin: 16 }
            spacing: 10
            Image {
                visible: !!card.entry.ui.headerIcon
                source: card.entry.ui.headerIcon ? Url.fromPath(card.entry.dir + "/" + card.entry.ui.headerIcon) : ""
                width: 24; height: 24; sourceSize: Qt.size(48, 48)
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                visible: !card.entry.ui.headerIcon
                text: card.entry.ui.headerGlyph || "•"
                font.family: card.entry.pal.font; font.pixelSize: 22; font.bold: true
                color: card.c.accent
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: card.entry.ui.upperTitle ? card.entry.pal.label.toUpperCase() : card.entry.pal.label
                font.family: card.entry.pal.display; font.pixelSize: Math.round(26 * (card.entry.ui.titleScale ?? 1))
                font.italic: !!card.entry.ui.italicTitle
                color: card.c.fg
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Rectangle {
            visible: card.entry.current
            anchors { right: parent.right; rightMargin: 16; verticalCenter: title.verticalCenter }
            width: nowText.implicitWidth + 16; height: 22; radius: Math.min(card.r, 11)
            color: Theme.alpha(card.c.accent, 0.22)
            Text {
                id: nowText
                anchors.centerIn: parent
                text: "сейчас"
                font.family: card.entry.pal.font; font.pixelSize: 12
                color: card.c.accent
            }
        }

        Row {
            id: swatches
            anchors { left: parent.left; leftMargin: 16; top: title.bottom; topMargin: 16 }
            spacing: 6
            Repeater {
                model: ["bg2", "fg", "accent", "accent2", "accent3", "muted", "good", "warn", "crit"]
                Rectangle {
                    required property string modelData
                    width: 24; height: 24
                    radius: card.r > 4 ? 12 : 2
                    color: card.c[modelData]
                    border.color: Theme.alpha(card.c.fg, 0.15)
                }
            }
        }

        // What the window border gradient looks like in this theme.
        Rectangle {
            anchors { left: parent.left; right: parent.right; top: swatches.bottom; margins: 16; topMargin: 18 }
            height: 6
            radius: card.r > 4 ? 3 : 0
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: card.c.accent }
                GradientStop { position: 1; color: card.c.accent2 }
            }
        }

        Text {
            anchors { left: parent.left; leftMargin: 16; bottom: parent.bottom; bottomMargin: 14 }
            text: card.number + "  ·  " + card.entry.name
            font.family: card.entry.pal.font; font.pixelSize: 12
            color: card.c.muted
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onEntered: card.hovered()
        onClicked: card.picked()
    }
}
