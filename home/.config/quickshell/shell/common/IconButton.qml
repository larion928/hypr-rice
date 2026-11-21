import QtQuick

// A round button with a Nerd Font icon. "filled" gives it a background of its own, for one drawn over a
// picture; "active" marks a switched-on state, "danger" a destructive action, "spinning" work in progress.
Rectangle {
    id: button

    property string glyph
    property bool small
    property bool filled
    property bool active
    property bool danger
    property bool spinning

    signal clicked()

    readonly property string tone: danger ? Theme.crit : Theme.accent

    width: small ? 26 : 32
    height: width
    radius: width / 2
    color: active ? Theme.alpha(Theme.accent, 0.3)
           : area.containsMouse ? Theme.alpha(tone, filled ? 0.85 : 0.22)
           : filled ? Theme.alpha(Theme.bg, 0.85) : "transparent"

    Text {
        anchors.centerIn: parent
        text: button.glyph
        font.family: Theme.glyphFont
        font.pixelSize: button.small ? 13 : 16
        color: area.containsMouse && button.filled ? Theme.bg
               : area.containsMouse || button.active ? button.tone : Theme.fg
        RotationAnimation on rotation {
            running: button.spinning
            from: 0
            to: 360
            duration: 900
            loops: Animation.Infinite
        }
    }

    MouseArea { id: area; anchors.fill: parent; hoverEnabled: true; onClicked: button.clicked() }
}
