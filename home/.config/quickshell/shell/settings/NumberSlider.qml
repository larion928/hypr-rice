import QtQuick
import qs.common

// A number on a track; moved(value) on every drag, rounded to step.
Item {
    id: slider
    property real from: 0
    property real to: 10
    property real step: 1
    property real value: 0
    signal moved(real value)
    implicitHeight: 24
    readonly property real fraction: Math.max(0, Math.min(1, (value - from) / (to - from)))
    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width; height: 6; radius: 3
        color: Theme.alpha(Theme.bg2, 0.9)
        border.color: Theme.alpha(Theme.muted, 0.35)
    }
    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: slider.fraction * (parent.width - 18) + 9; height: 6; radius: 3
        color: Theme.accent
    }
    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        x: slider.fraction * (parent.width - 18)
        width: 18; height: 18; radius: 9
        color: Theme.accent
        border.color: Theme.bg
    }
    MouseArea {
        anchors.fill: parent
        preventStealing: true
        function set(x) {
            const share = Math.max(0, Math.min(1, (x - 9) / (width - 18)));
            const raw = slider.from + share * (slider.to - slider.from);
            slider.moved(Number((Math.round(raw / slider.step) * slider.step).toFixed(2)));
        }
        onPressed: mouse => set(mouse.x)
        onPositionChanged: mouse => { if (pressed) set(mouse.x); }
    }
}
