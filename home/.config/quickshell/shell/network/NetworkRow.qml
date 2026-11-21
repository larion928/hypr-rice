import QtQuick
import qs.common
import "signal.js" as Signal

// A nearby network: signal, lock, name, tags; a click connects (a saved or open one) or opens the password
// field in place (a new secured one). On hover a saved one offers to be forgotten.
Rectangle {
    id: row

    required property NetworkManager net
    property var network
    readonly property bool saved: !!net.saved[network.ssid]
    readonly property bool open: net.expanded === network.ssid
    readonly property bool connecting: net.busy === network.ssid

    // The menu's keys again (Esc in the password field).
    signal done()

    width: parent ? parent.width : 0
    height: open ? 104 : 48
    radius: Theme.radius(18)
    color: rowHover.hovered || open ? Theme.alpha(Theme.bg2, 0.95) : Theme.alpha(Theme.bg2, 0.55)
    border.width: open ? 1 : 0
    border.color: Theme.alpha(Theme.accent, 0.5)
    Behavior on height { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
    clip: true

    // Hover of the whole row, buttons inside included: a MouseArea loses it to the forget button on top of it,
    // which then hides the button, which gives the hover back, in a loop.
    HoverHandler { id: rowHover }

    MouseArea {
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 48
        hoverEnabled: true
        onClicked: {
            if (row.network.secure && !row.saved) {
                const opening = !row.open;
                row.net.expanded = opening ? row.network.ssid : "";
                if (opening) {
                    password.focusInput();
                }
            } else {
                row.net.connect(row.network, "");
            }
        }
    }

    Text {
        id: icon
        x: 14; y: 12
        text: Signal.glyph(row.network.signal)
        font.family: Theme.glyphFont; font.pixelSize: 20
        color: row.saved ? Theme.accent : Theme.fg
    }
    Text {
        visible: row.network.secure
        anchors { left: icon.right; leftMargin: 2 }
        y: 20
        text: "\u{f033e}"
        font.family: Theme.glyphFont; font.pixelSize: 11
        color: Theme.muted
    }
    Text {
        anchors { left: icon.right; leftMargin: 16; right: tags.left; rightMargin: 8 }
        y: 14
        elide: Text.ElideRight
        text: row.network.ssid
        font.family: Theme.bodyFont; font.pixelSize: 14
        color: Theme.fg
    }
    Row {
        id: tags
        anchors { right: parent.right; rightMargin: 12 }
        y: 12
        spacing: 6
        Tag { visible: row.network.band5; text: "5G" }
        Tag { visible: row.saved && !row.connecting; text: "сохранена" }
        Tag { visible: row.connecting; text: "подключаю…"; tone: Theme.accent }
        IconButton {
            visible: row.saved && !row.connecting && rowHover.hovered
            glyph: "\u{f0a7a}"
            small: true
            onClicked: row.net.forget(row.network.ssid)
        }
    }

    // Password, asked in place for a new secured network.
    Field {
        id: password
        visible: row.open
        x: 14; y: 54
        width: row.width - 28 - connectButton.width - 10
        height: 36
        echoMode: TextInput.Password
        placeholder: "пароль"
        onAccepted: if (text.length >= 8) row.net.connect(row.network, text)
        onEscaped: {
            row.net.expanded = "";
            row.done();
        }
    }
    Chip {
        id: connectButton
        visible: row.open
        anchors { right: parent.right; rightMargin: 14 }
        y: 55
        text: "Подключить"
        enabled: password.text.length >= 8 && !row.connecting
        onClicked: row.net.connect(row.network, password.text)
    }

    // A small label on the row: the band, saved, connecting.
    component Tag: Rectangle {
        id: tag
        property string text
        property string tone: Theme.muted
        height: 22
        width: tagText.implicitWidth + 14
        radius: 11
        color: Theme.alpha(tone, 0.18)
        Text {
            id: tagText
            anchors.centerIn: parent
            text: tag.text
            font.family: Theme.bodyFont; font.pixelSize: 11
            color: tag.tone
        }
    }
}
