import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.common

// One notification: its app, time, summary and body (as plain text). A click expands it and marks it read; on hover it offers
// copying its text and deleting it.
Rectangle {
    id: card

    property var notification
    property string summary
    property string body
    readonly property bool read: !!notification.histui_dismissed_at
    readonly property bool critical: notification.urgency === 2
    property bool expanded: false

    signal opened()
    signal copyRequested()
    signal removeRequested()

    height: content.implicitHeight + 24
    radius: Theme.cardRadius
    color: hover.hovered ? Theme.alpha(Theme.bg2, 1) : Theme.alpha(Theme.bg2, read ? 0.55 : 0.85)
    border.width: 1
    border.color: critical ? Theme.alpha(Theme.crit, 0.8) : Theme.alpha(Theme.accent, read ? 0.12 : 0.35)
    opacity: 0

    Component.onCompleted: appear.start()
    NumberAnimation on opacity { id: appear; running: false; to: 1; duration: 220; easing.type: Easing.OutQuad }

    // Unread marker on the left edge.
    Rectangle {
        visible: !card.read
        x: 0; y: 10
        width: 3; height: card.height - 20; radius: 2
        color: card.critical ? Theme.crit : Theme.accent
    }

    HoverHandler { id: hover }
    TapHandler {
        onTapped: {
            card.expanded = !card.expanded;
            card.opened();
        }
    }

    Column {
        id: content
        x: 14; y: 12
        width: card.width - 28
        spacing: 4

        Item {
            width: parent.width
            height: 20
            Row {
                spacing: 8
                anchors.verticalCenter: parent.verticalCenter
                IconImage {
                    id: appIcon
                    implicitSize: 18
                    visible: source != ""
                    readonly property string name: (card.notification.extensions && card.notification.extensions.desktop_entry)
                                                   || String(card.notification.app_name || "").toLowerCase()
                    // true: return "" instead of a broken icon when the theme lacks it.
                    source: name ? Quickshell.iconPath(name, true) : ""
                }
                Text {
                    visible: !appIcon.visible
                    text: ""
                    font.family: Theme.glyphFont; font.pixelSize: 14
                    color: Theme.accent
                }
                Text {
                    text: card.notification.app_name || ""
                    font.family: Theme.bodyFont; font.pixelSize: 12
                    color: Theme.muted
                }
            }
            Row {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 2
                visible: hover.hovered
                IconButton { small: true; glyph: "\uf0c5"; onClicked: card.copyRequested() }
                IconButton { small: true; glyph: "\uf1f8"; danger: true; onClicked: card.removeRequested() }
            }
            Text {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                visible: !hover.hovered
                text: Qt.formatTime(new Date((card.notification.timestamp || 0) * 1000), "hh:mm")
                font.family: Theme.bodyFont; font.pixelSize: 12
                color: Theme.muted
            }
        }
        Text {
            width: parent.width
            text: card.summary
            visible: text.length > 0
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            maximumLineCount: card.expanded ? 6 : 2
            elide: Text.ElideRight
            font.family: Theme.titleFont; font.pixelSize: 15; font.bold: true
            color: card.critical ? Theme.crit : Theme.fg
        }
        Text {
            width: parent.width
            text: card.body
            visible: text.length > 0
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            maximumLineCount: card.expanded ? 40 : 3
            elide: Text.ElideRight
            font.family: Theme.bodyFont; font.pixelSize: 13
            color: Theme.alpha(Theme.fg, card.read ? 0.6 : 0.85)
        }
    }
}
