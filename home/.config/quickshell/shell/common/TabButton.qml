import QtQuick

// One tab of a row of tabs; "active" is the one shown.
Rectangle {
    id: tab

    property string text
    property bool active

    signal clicked()

    width: label.implicitWidth + 30
    height: 36
    radius: Theme.rounded ? 18 : 0
    color: active ? Theme.alpha(Theme.accent, 0.25) : area.containsMouse ? Theme.alpha(Theme.accent, 0.1) : "transparent"
    border.color: active ? Theme.accent : Theme.alpha(Theme.muted, 0.3)

    Text {
        id: label
        anchors.centerIn: parent
        text: tab.text
        font.family: Theme.bodyFont
        font.pixelSize: 15
        font.bold: tab.active
        color: tab.active ? Theme.accent : Theme.fg
    }

    MouseArea { id: area; anchors.fill: parent; hoverEnabled: true; onClicked: tab.clicked() }
}
