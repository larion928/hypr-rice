// Volume / brightness OSD. Reacts to changes rather than keys: PipeWire for the default sink, sysfs for the first
// backlight. The look follows the current theme (ui.json "osdStyle": pill, ascii, neon, minimal, retro, wave).
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import qs.common

Scope {
    id: osd

    readonly property string style: Theme.ui.osdStyle || "pill"
    readonly property int r: Theme.radius(22)

    property string kind: "volume"   // what is being shown
    property real value: 0           // 0..1
    property bool muted: false
    property bool shown: false
    property bool ready: false       // ignore the initial values reported at startup

    function show(newKind, newValue, newMuted) {
        if (!ready) {
            return;
        }
        kind = newKind;
        value = Math.max(0, Math.min(1, newValue));
        muted = newMuted;
        shown = true;
        hideTimer.restart();
    }

    Timer { interval: 1500; running: true; onTriggered: osd.ready = true }
    Timer { id: hideTimer; interval: 1400; onTriggered: osd.shown = false }

    // ---------- sources ----------

    readonly property var sink: Pipewire.defaultAudioSink
    PwObjectTracker { objects: [osd.sink] }
    Connections {
        target: osd.sink ? osd.sink.audio : null
        function onVolumeChanged() { osd.show("volume", osd.sink.audio.volume, osd.sink.audio.muted); }
        function onMutedChanged() { osd.show("volume", osd.sink.audio.volume, osd.sink.audio.muted); }
    }

    // The first device in /sys/class/backlight; "" on a machine without one.
    property string backlight: ""
    Process {
        command: ["sh", "-c", "ls -d /sys/class/backlight/* 2>/dev/null | head -n1"]
        running: true
        stdout: StdioCollector { onStreamFinished: osd.backlight = this.text.trim() }
    }
    property real maxBrightness: 1
    FileView {
        path: osd.backlight ? osd.backlight + "/max_brightness" : ""
        onLoaded: osd.maxBrightness = Math.max(1, parseInt(text()))
    }
    FileView {
        path: osd.backlight ? osd.backlight + "/brightness" : ""
        watchChanges: true
        onFileChanged: reload()
        onLoaded: osd.show("brightness", parseInt(text()) / osd.maxBrightness, false)
    }

    // ---------- view ----------

    readonly property string icon: kind === "brightness"
        ? (value > 0.66 ? "\u{f00e0}" : value > 0.33 ? "\u{f00df}" : "\u{f00de}")
        : (muted || value === 0 ? "\u{f075f}" : value > 0.66 ? "\u{f057e}" : value > 0.33 ? "\u{f0580}" : "\u{f057f}")
    readonly property string label: kind === "brightness" ? "Яркость" : muted ? "Без звука" : "Громкость"
    readonly property int pct: Math.round(value * 100)
    readonly property string levelColour: muted ? Theme.muted : Theme.accent

    PanelWindow {
        id: win
        // Shown on whichever monitor has focus now.
        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? null
        visible: osd.shown || fade.running
        anchors.bottom: true
        margins.bottom: 90
        implicitWidth: 360
        implicitHeight: 72
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "osd"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        mask: Region {}

        Item {
            id: body
            anchors.fill: parent
            opacity: osd.shown ? 1 : 0
            Behavior on opacity { NumberAnimation { id: fade; duration: osd.shown ? 120 : 260 } }
            transform: Translate { y: osd.shown ? 0 : 14; Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } } }

            // pill: rounded card, icon, bar, percent (claude, frieren, sakura)
            Rectangle {
                visible: osd.style === "pill"
                anchors.fill: parent
                radius: Math.min(osd.r, height / 2)
                color: Theme.alpha(Theme.bg, 0.92)
                border.color: Theme.alpha(Theme.accent, 0.5)
                Row {
                    anchors { fill: parent; leftMargin: 22; rightMargin: 22 }
                    spacing: 16
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: osd.icon
                        font.family: Theme.glyphFont; font.pixelSize: 24
                        color: osd.levelColour
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 120; height: 8; radius: 4
                        color: Theme.alpha(Theme.muted, 0.3)
                        Rectangle {
                            width: parent.width * osd.value; height: parent.height; radius: 4
                            color: osd.levelColour
                            Behavior on width { NumberAnimation { duration: 120 } }
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: osd.pct
                        font.family: Theme.titleFont; font.pixelSize: 20; font.italic: Theme.italicTitle
                        color: Theme.fg
                    }
                }
            }

            // ascii: terminal-style bar (hacker)
            Rectangle {
                visible: osd.style === "ascii"
                anchors.fill: parent
                color: Theme.alpha("#000000", 0.9)
                border.color: Theme.accent
                Text {
                    anchors.centerIn: parent
                    readonly property int cells: 20
                    readonly property int full: Math.round(osd.value * cells)
                    text: (osd.kind === "brightness" ? "bri " : osd.muted ? "mute" : "vol ")
                          + " [" + "#".repeat(full) + "-".repeat(cells - full) + "] "
                          + String(osd.pct).padStart(3, " ") + "%"
                    font.family: Theme.bodyFont; font.pixelSize: 18
                    color: osd.levelColour
                }
            }

            // neon: glowing segments with a hard edge (cyberpunk)
            Rectangle {
                visible: osd.style === "neon"
                anchors.fill: parent
                color: Theme.alpha(Theme.bg, 0.92)
                border.width: 2
                border.color: Theme.accent
                Row {
                    anchors { fill: parent; leftMargin: 18; rightMargin: 18 }
                    spacing: 12
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: osd.icon
                        font.family: Theme.glyphFont; font.pixelSize: 24
                        color: Theme.accent2
                    }
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 3
                        Repeater {
                            model: 20
                            Rectangle {
                                required property int index
                                readonly property bool on: index < Math.round(osd.value * 20)
                                width: 9; height: 22
                                color: on ? (index >= 16 ? Theme.accent : Theme.accent2) : Theme.alpha(Theme.muted, 0.25)
                                opacity: osd.muted && on ? 0.4 : 1
                            }
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: String(osd.pct).padStart(3, " ")
                        font.family: Theme.bodyFont; font.pixelSize: 18; font.bold: true
                        color: Theme.accent
                    }
                }
            }

            // minimal: a thin line and a small number (night)
            Item {
                visible: osd.style === "minimal"
                anchors.fill: parent
                Text {
                    anchors { horizontalCenter: parent.horizontalCenter; bottom: line.top; bottomMargin: 10 }
                    text: osd.label.toLowerCase() + "  " + osd.pct
                    font.family: Theme.bodyFont; font.pixelSize: 13
                    color: Theme.muted
                }
                Rectangle {
                    id: line
                    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 18 }
                    width: 260; height: 2
                    color: Theme.alpha(Theme.muted, 0.35)
                    Rectangle {
                        width: parent.width * osd.value; height: parent.height
                        color: osd.muted ? Theme.muted : Theme.fg
                        Behavior on width { NumberAnimation { duration: 120 } }
                    }
                }
            }

            // retro: a framed row of chunky blocks with a label tab, gruvbox-like (coffee)
            Rectangle {
                visible: osd.style === "retro"
                anchors.fill: parent
                radius: 6
                color: Theme.alpha(Theme.bg, 0.95)
                border.width: 2
                border.color: Theme.accent3
                Row {
                    anchors { fill: parent; leftMargin: 14; rightMargin: 16 }
                    spacing: 12
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 44; height: 44; radius: 4
                        color: osd.levelColour
                        Text {
                            anchors.centerIn: parent
                            text: osd.icon
                            font.family: Theme.glyphFont; font.pixelSize: 22
                            color: Theme.bg
                        }
                    }
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4
                        Repeater {
                            model: 10
                            Rectangle {
                                required property int index
                                readonly property bool on: index < Math.round(osd.value * 10)
                                width: 14; height: 26; radius: 2
                                color: on ? (osd.muted ? Theme.muted : Theme.accent2) : Theme.alpha(Theme.accent3, 0.25)
                            }
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: String(osd.pct).padStart(3, " ") + "%"
                        font.family: Theme.titleFont; font.pixelSize: 18; font.bold: true
                        color: Theme.fg
                    }
                }
            }

            // wave: a rounded glass pill filled with water whose surface keeps moving (ocean)
            Rectangle {
                id: waveBox
                visible: osd.style === "wave"
                anchors.fill: parent
                radius: height / 2
                color: Theme.alpha(Theme.bg, 0.9)
                border.width: 1.5
                border.color: Theme.alpha(Theme.accent, 0.6)
                property real phase: 0
                NumberAnimation on phase {
                    running: waveBox.visible && win.visible
                    from: 0; to: Math.PI * 2; duration: 1400; loops: Animation.Infinite
                }
                Canvas {
                    anchors { fill: parent; margins: 6 }
                    property real level: osd.value
                    property real ph: waveBox.phase
                    Behavior on level { NumberAnimation { duration: 160 } }
                    onLevelChanged: requestPaint()
                    onPhChanged: requestPaint()
                    onPaint: {
                        const g = getContext("2d");
                        g.reset();
                        const r = height / 2;
                        // Clip to the pill shape.
                        g.beginPath();
                        g.moveTo(r, 0); g.lineTo(width - r, 0);
                        g.arc(width - r, r, r, -Math.PI / 2, Math.PI / 2);
                        g.lineTo(r, height);
                        g.arc(r, r, r, Math.PI / 2, Math.PI * 1.5);
                        g.closePath();
                        g.clip();
                        // Water fills from the left; its right edge is the wavy surface.
                        const edge = width * level;
                        const grad = g.createLinearGradient(0, 0, width, 0);
                        grad.addColorStop(0, Theme.alpha(Theme.accent3, 0.85));
                        grad.addColorStop(1, Theme.alpha(osd.levelColour, 0.85));
                        g.fillStyle = grad;
                        g.beginPath();
                        g.moveTo(0, 0);
                        for (let y = 0; y <= height; y += 3)
                            g.lineTo(edge + (level > 0.01 && level < 0.99 ? Math.sin(y / 7 + ph) * 5 : 0), y);
                        g.lineTo(0, height);
                        g.closePath();
                        g.fill();
                    }
                }
                Row {
                    anchors { fill: parent; leftMargin: 24; rightMargin: 24 }
                    spacing: 12
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: osd.icon
                        font.family: Theme.glyphFont; font.pixelSize: 24
                        color: Theme.fg
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 120
                        text: osd.label
                        font.family: Theme.titleFont; font.pixelSize: 17; font.bold: true
                        color: Theme.fg
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: osd.pct
                        font.family: Theme.titleFont; font.pixelSize: 22; font.bold: true
                        color: Theme.fg
                    }
                }
            }
        }
    }
}
