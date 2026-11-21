import QtQuick

// An on/off switch; toggled() asks for the other state, the owner sets `checked`.
Rectangle {
    id: toggle

    property bool checked

    signal toggled()

    width: 46
    height: 26
    radius: 13
    color: checked ? Theme.alpha(Theme.accent, 0.85) : Theme.alpha(Theme.muted, 0.35)
    Behavior on color { ColorAnimation { duration: 150 } }

    Rectangle {
        width: 20
        height: 20
        radius: 10
        y: 3
        x: toggle.checked ? toggle.width - width - 3 : 3
        color: Theme.bg
        Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
    }

    MouseArea { anchors.fill: parent; onClicked: toggle.toggled() }
}
