import QtQuick
import qs.common

// Saturation and value in the square, hue in the bar below, and the hex code. value comes in;
// picked(hex) goes out on every change the user makes.
Column {
    id: cp
    property string value: "#000000"
    property real hue: 0
    property real saturation: 0
    property real brightness: 0
    signal picked(string hex)
    spacing: 12
    onValueChanged: load(value)
    Component.onCompleted: load(value)

    function load(hex) {
        const c = Qt.color(hex);
        if (c.hsvHue >= 0) cp.hue = c.hsvHue;
        cp.saturation = c.hsvSaturation;
        cp.brightness = c.hsvValue;
        hexField.text = hex;
    }
    function pick() {
        const hex = Qt.hsva(cp.hue, cp.saturation, cp.brightness, 1).toString();
        hexField.text = hex;
        cp.picked(hex);
    }

    Rectangle {
        id: square
        width: 320; height: 220
        radius: 6
        color: Qt.hsva(cp.hue, 1, 1, 1)
        Rectangle {
            anchors.fill: parent; radius: parent.radius
            gradient: Gradient { orientation: Gradient.Horizontal; GradientStop { position: 0; color: "white" } GradientStop { position: 1; color: "transparent" } }
        }
        Rectangle {
            anchors.fill: parent; radius: parent.radius
            gradient: Gradient { GradientStop { position: 0; color: "transparent" } GradientStop { position: 1; color: "black" } }
        }
        Rectangle {
            x: cp.saturation * parent.width - 8; y: (1 - cp.brightness) * parent.height - 8
            width: 16; height: 16; radius: 8
            color: "transparent"; border.color: "white"; border.width: 2
        }
        MouseArea {
            anchors.fill: parent
            function set(mouse) {
                cp.saturation = Math.max(0, Math.min(1, mouse.x / width));
                cp.brightness = Math.max(0, Math.min(1, 1 - mouse.y / height));
                cp.pick();
            }
            onPressed: mouse => set(mouse)
            onPositionChanged: mouse => set(mouse)
        }
    }
    Rectangle {
        width: square.width; height: 22
        radius: 6
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "#ff0000" }
            GradientStop { position: 0.17; color: "#ffff00" }
            GradientStop { position: 0.33; color: "#00ff00" }
            GradientStop { position: 0.5; color: "#00ffff" }
            GradientStop { position: 0.67; color: "#0000ff" }
            GradientStop { position: 0.83; color: "#ff00ff" }
            GradientStop { position: 1.0; color: "#ff0000" }
        }
        Rectangle {
            x: cp.hue * parent.width - 3; y: -3
            width: 6; height: parent.height + 6; radius: 3
            color: "white"; border.color: "black"
        }
        MouseArea {
            anchors.fill: parent
            function set(mouse) {
                cp.hue = Math.max(0, Math.min(0.999, mouse.x / width));
                cp.pick();
            }
            onPressed: mouse => set(mouse)
            onPositionChanged: mouse => set(mouse)
        }
    }
    Row {
        spacing: 10
        Rectangle { width: 34; height: 34; radius: 8; color: cp.value; border.color: Theme.alpha(Theme.fg, 0.4) }
        Field {
            id: hexField
            width: 140
            placeholder: "#rrggbb"
            onAccepted: {
                if (/^#[0-9a-fA-F]{6}$/.test(text)) cp.picked(text.toLowerCase());
            }
        }
    }
}
