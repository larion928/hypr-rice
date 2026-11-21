import QtQuick
import qs.common

// One card of the cheat sheet: its title, then a row per entry with the keys in a chip and what they do.
Rectangle {
    id: card

    property var section
    property int appearDelay

    height: rows.implicitHeight + 32
    radius: Theme.radius(16)
    color: Theme.alpha(Theme.bg2, 0.85)
    border.color: Theme.alpha(Theme.muted, 0.25)
    opacity: 0
    Component.onCompleted: appear.start()
    SequentialAnimation {
        id: appear
        PauseAnimation { duration: card.appearDelay }
        NumberAnimation { target: card; property: "opacity"; to: 1; duration: 220 }
    }

    Column {
        id: rows
        x: 18; y: 16
        width: card.width - 36
        spacing: 9
        SectionTitle { text: Theme.title(card.section.title) }
        Repeater {
            model: card.section.rows
            Item {
                id: row
                required property var modelData
                width: rows.width
                height: Math.max(chip.height, label.implicitHeight)
                Rectangle {
                    id: chip
                    width: Math.min(keysText.implicitWidth + 16, rows.width * 0.48)
                    height: 26
                    radius: Theme.rounded ? 7 : 0
                    color: Theme.alpha(Theme.accent, 0.16)
                    border.color: Theme.alpha(Theme.accent, 0.45)
                    Text {
                        id: keysText
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, rows.width * 0.48 - 16)
                        elide: Text.ElideRight
                        text: row.modelData.keys
                        font.family: Theme.glyphFont; font.pixelSize: 13
                        color: Theme.accent
                    }
                }
                Text {
                    id: label
                    anchors { left: parent.left; leftMargin: rows.width * 0.5; right: parent.right; verticalCenter: chip.verticalCenter }
                    text: row.modelData.text
                    wrapMode: Text.Wrap
                    font.family: Theme.bodyFont; font.pixelSize: 14
                    color: Theme.fg
                }
            }
        }
    }
}
