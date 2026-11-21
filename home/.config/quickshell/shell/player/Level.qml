import QtQuick
import qs.common

// A horizontal level from 0 to 1 the user clicks or drags: the track's position, a player's volume. While the
// mouse is held it shows where the mouse is and sends dragged(); on release it sends released(). The owner
// applies either and sets value back.
Item {
    id: level

    property real value
    readonly property real shownValue: area.pressed ? fractionAt(area.mouseX) : Math.max(0, Math.min(1, value))

    signal dragged(real fraction)
    signal released(real fraction)

    function fractionAt(x) {
        return Math.max(0, Math.min(1, x / width));
    }

    implicitHeight: 16

    Rectangle {
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
        height: 4
        radius: 2
        color: Theme.alpha(Theme.fg, 0.15)
    }

    Rectangle {
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
        width: level.width * level.shownValue
        height: 4
        radius: 2
        color: Theme.accent
    }

    Rectangle {
        x: level.width * level.shownValue - width / 2
        anchors.verticalCenter: parent.verticalCenter
        width: 12; height: 12; radius: 6
        color: Theme.accent
        visible: area.containsMouse || area.pressed
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPositionChanged: if (pressed) level.dragged(level.fractionAt(mouseX))
        onPressed: level.dragged(level.fractionAt(mouseX))
        onReleased: level.released(level.fractionAt(mouseX))
    }
}
