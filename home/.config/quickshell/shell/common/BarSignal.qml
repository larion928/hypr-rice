import QtQuick
import Quickshell.Io

// Makes waybar run a custom module's exec again: the module's "signal" in waybar/config.base.json. Changes that
// come together (a track change sets several properties at once) go out as one signal.
Item {
    id: bar

    required property int number

    function refresh() {
        batch.restart();
    }

    Timer {
        id: batch
        interval: 150
        onTriggered: sender.running = true
    }

    Process {
        id: sender
        command: ["pkill", "-RTMIN+" + bar.number, "-x", "waybar"]
    }
}
