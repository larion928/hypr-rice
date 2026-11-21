import QtQuick

// A button with a word on it (and an icon before it): "primary" is filled with the accent (red with "danger"),
// "active" marks the chosen one of a set, "danger" alone turns the word red. Faded out while disabled.
Rectangle {
    id: chip

    property string text
    property string glyph: ""
    property bool active
    property bool primary
    property bool danger

    signal clicked()

    width: content.implicitWidth + 26
    height: 34
    radius: Theme.rounded ? 9 : 0
    opacity: enabled ? 1 : 0.4
    readonly property string tone: danger ? Theme.crit : Theme.accent

    color: primary ? tone
           : active ? Theme.alpha(Theme.accent, 0.28)
           : area.containsMouse ? Theme.alpha(tone, 0.12) : Theme.alpha(Theme.bg2, 0.9)
    border.color: active || primary ? tone : Theme.alpha(danger ? Theme.crit : Theme.muted, 0.35)

    Row {
        id: content
        anchors.centerIn: parent
        spacing: 8
        Text {
            visible: chip.glyph !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: chip.glyph
            font.family: Theme.glyphFont
            font.pixelSize: 15
            color: textLabel.color
        }
        Text {
            id: textLabel
            visible: chip.text !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: chip.text
            font.family: Theme.bodyFont
            font.pixelSize: 14
            font.bold: chip.active || chip.primary
            color: chip.primary ? Theme.bg : chip.danger ? Theme.crit : chip.active ? Theme.accent : Theme.fg
        }
    }

    MouseArea { id: area; anchors.fill: parent; hoverEnabled: true; enabled: chip.enabled; onClicked: chip.clicked() }
}
