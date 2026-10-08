// Volume / brightness OSD. Runs for the whole session (started from hyprland.lua) and reacts
// to changes rather than keys: PipeWire for the default sink, sysfs for the backlight.
// The look follows the current theme (ui.json "osdStyle": pill, ascii, neon, minimal, retro, wave) and
// is reloaded whenever ~/.config/hypr/current-theme changes.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pipewire

ShellRoot {
    id: root

    readonly property string hypr: Quickshell.env("HOME") + "/.config/hypr"
    property string themeName: ""
    property var pal: ({ colors: {} })
    property var ui: ({})
    readonly property var c: pal.colors || {}
    readonly property string style: ui.osdStyle || "pill"
    readonly property string titleFont: ui.titleFont === "display" ? (pal.display || "serif") : (pal.font || "monospace")
    readonly property string bodyFont: pal.font || "monospace"
    readonly property int r: Math.min(ui.radius ?? 14, 22)

    property string kind: "volume"   // what is being shown
    property real value: 0           // 0..1
    property bool muted: false
    property bool shown: false
    property bool ready: false       // ignore the initial values reported at startup

    function a(col, al) {
        return "#" + ("0" + Math.round(al * 255).toString(16)).slice(-2) + String(col || "#888888").slice(1);
    }

    function show(k, v, m) {
        if (!ready) return;
        kind = k;
        value = Math.max(0, Math.min(1, v));
        muted = m;
        shown = true;
        hideTimer.restart();
    }

    Timer { interval: 1500; running: true; onTriggered: root.ready = true }
    Timer { id: hideTimer; interval: 1400; onTriggered: root.shown = false }

    // ---------- theme ----------

    FileView {
        path: root.hypr + "/current-theme"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.loadTheme(text().trim())
    }
    // Parse in onLoaded: right after a path change text() still returns the previous file,
    // which made the OSD lag one theme behind.
    FileView {
        id: palFile
        path: root.themeName ? root.hypr + "/themes/" + root.themeName + "/palette.json" : ""
        onLoaded: { try { root.pal = JSON.parse(text()); } catch (e) {} }
    }
    FileView {
        id: uiFile
        path: root.themeName ? root.hypr + "/themes/" + root.themeName + "/ui.json" : ""
        onLoaded: { try { root.ui = JSON.parse(text()); } catch (e) { root.ui = {}; } }
    }

    function loadTheme(name) {
        if (name) themeName = name;
    }

    // ---------- sources ----------

    readonly property var sink: Pipewire.defaultAudioSink
    PwObjectTracker { objects: [root.sink] }
    Connections {
        target: root.sink ? root.sink.audio : null
        function onVolumeChanged() { root.show("volume", root.sink.audio.volume, root.sink.audio.muted); }
        function onMutedChanged() { root.show("volume", root.sink.audio.volume, root.sink.audio.muted); }
    }

    // Set by the autostart line in hyprland.lua (first device in /sys/class/backlight).
    readonly property string backlight: Quickshell.env("OSD_BACKLIGHT") || "/sys/class/backlight/amdgpu_bl1"
    property real maxBrightness: 1
    FileView {
        path: root.backlight + "/max_brightness"
        onLoaded: root.maxBrightness = Math.max(1, parseInt(text()))
    }
    FileView {
        path: root.backlight + "/brightness"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.show("brightness", parseInt(text()) / root.maxBrightness, false)
    }

    // ---------- view ----------

    readonly property string icon: kind === "brightness"
        ? (value > 0.66 ? "\u{f00e0}" : value > 0.33 ? "\u{f00df}" : "\u{f00de}")
        : (muted || value === 0 ? "\u{f075f}" : value > 0.66 ? "\u{f057e}" : value > 0.33 ? "\u{f0580}" : "\u{f057f}")
    readonly property string label: kind === "brightness" ? "Яркость" : muted ? "Без звука" : "Громкость"
    readonly property int pct: Math.round(value * 100)

    PanelWindow {
        id: win
        visible: root.shown || fade.running
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
            opacity: root.shown ? 1 : 0
            Behavior on opacity { NumberAnimation { id: fade; duration: root.shown ? 120 : 260 } }
            transform: Translate { y: root.shown ? 0 : 14; Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } } }

            // pill: rounded card, icon, bar, percent (claude, frieren, sakura)
            Rectangle {
                visible: root.style === "pill"
                anchors.fill: parent
                radius: Math.min(root.r, height / 2)
                color: root.a(root.c.bg, 0.92)
                border.color: root.a(root.c.accent, 0.5)
                Row {
                    anchors { fill: parent; leftMargin: 22; rightMargin: 22 }
                    spacing: 16
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.icon
                        font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 24
                        color: root.muted ? (root.c.muted || "grey") : (root.c.accent || "white")
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 120; height: 8; radius: 4
                        color: root.a(root.c.muted, 0.3)
                        Rectangle {
                            width: parent.width * root.value; height: parent.height; radius: 4
                            color: root.muted ? (root.c.muted || "grey") : (root.c.accent || "white")
                            Behavior on width { NumberAnimation { duration: 120 } }
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.pct
                        font.family: root.titleFont; font.pixelSize: 20; font.italic: !!root.ui.italicTitle
                        color: root.c.fg || "white"
                    }
                }
            }

            // ascii: terminal-style bar (hacker)
            Rectangle {
                visible: root.style === "ascii"
                anchors.fill: parent
                color: root.a("#000000", 0.9)
                border.color: root.c.accent || "green"
                Text {
                    anchors.centerIn: parent
                    readonly property int cells: 20
                    readonly property int full: Math.round(root.value * cells)
                    text: (root.kind === "brightness" ? "bri " : root.muted ? "mute" : "vol ")
                          + " [" + "#".repeat(full) + "-".repeat(cells - full) + "] "
                          + String(root.pct).padStart(3, " ") + "%"
                    font.family: root.bodyFont; font.pixelSize: 18
                    color: root.muted ? (root.c.muted || "grey") : (root.c.accent || "green")
                }
            }

            // neon: glowing segments with a hard edge (cyberpunk)
            Rectangle {
                visible: root.style === "neon"
                anchors.fill: parent
                color: root.a(root.c.bg, 0.92)
                border.width: 2
                border.color: root.c.accent || "magenta"
                Row {
                    anchors { fill: parent; leftMargin: 18; rightMargin: 18 }
                    spacing: 12
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.icon
                        font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 24
                        color: root.c.accent2 || "cyan"
                    }
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 3
                        Repeater {
                            model: 20
                            Rectangle {
                                required property int index
                                readonly property bool on: index < Math.round(root.value * 20)
                                width: 9; height: 22
                                color: on ? (index >= 16 ? (root.c.accent || "magenta") : (root.c.accent2 || "cyan"))
                                          : root.a(root.c.muted, 0.25)
                                opacity: root.muted && on ? 0.4 : 1
                            }
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: String(root.pct).padStart(3, " ")
                        font.family: root.bodyFont; font.pixelSize: 18; font.bold: true
                        color: root.c.accent || "magenta"
                    }
                }
            }

            // minimal: a thin line and a small number (night)
            Item {
                visible: root.style === "minimal"
                anchors.fill: parent
                Text {
                    anchors { horizontalCenter: parent.horizontalCenter; bottom: line.top; bottomMargin: 10 }
                    text: root.label.toLowerCase() + "  " + root.pct
                    font.family: root.bodyFont; font.pixelSize: 13
                    color: root.c.muted || "grey"
                }
                Rectangle {
                    id: line
                    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 18 }
                    width: 260; height: 2
                    color: root.a(root.c.muted, 0.35)
                    Rectangle {
                        width: parent.width * root.value; height: parent.height
                        color: root.muted ? (root.c.muted || "grey") : (root.c.fg || "white")
                        Behavior on width { NumberAnimation { duration: 120 } }
                    }
                }
            }

            // retro: a framed row of chunky blocks with a label tab, gruvbox-like (coffee)
            Rectangle {
                visible: root.style === "retro"
                anchors.fill: parent
                radius: 6
                color: root.a(root.c.bg, 0.95)
                border.width: 2
                border.color: root.c.accent3 || "brown"
                Row {
                    anchors { fill: parent; leftMargin: 14; rightMargin: 16 }
                    spacing: 12
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 44; height: 44; radius: 4
                        color: root.muted ? (root.c.muted || "grey") : (root.c.accent || "orange")
                        Text {
                            anchors.centerIn: parent
                            text: root.icon
                            font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 22
                            color: root.c.bg || "black"
                        }
                    }
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4
                        Repeater {
                            model: 10
                            Rectangle {
                                required property int index
                                readonly property bool on: index < Math.round(root.value * 10)
                                width: 14; height: 26; radius: 2
                                color: on ? (root.muted ? (root.c.muted || "grey") : (root.c.accent2 || "wheat"))
                                          : root.a(root.c.accent3, 0.25)
                            }
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: String(root.pct).padStart(3, " ") + "%"
                        font.family: root.titleFont; font.pixelSize: 18; font.bold: true
                        color: root.c.fg || "white"
                    }
                }
            }

            // wave: a rounded glass pill filled with water whose surface keeps moving (ocean)
            Rectangle {
                id: waveBox
                visible: root.style === "wave"
                anchors.fill: parent
                radius: height / 2
                color: root.a(root.c.bg, 0.9)
                border.width: 1.5
                border.color: root.a(root.c.accent, 0.6)
                property real phase: 0
                NumberAnimation on phase {
                    running: waveBox.visible && win.visible
                    from: 0; to: Math.PI * 2; duration: 1400; loops: Animation.Infinite
                }
                Canvas {
                    id: water
                    anchors { fill: parent; margins: 6 }
                    property real level: root.value
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
                        grad.addColorStop(0, root.a(root.c.accent3, 0.85));
                        grad.addColorStop(1, root.a(root.muted ? root.c.muted : root.c.accent, 0.85));
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
                        text: root.icon
                        font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 24
                        color: root.c.fg || "white"
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 120
                        text: root.label
                        font.family: root.titleFont; font.pixelSize: 17; font.bold: true
                        color: root.c.fg || "white"
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.pct
                        font.family: root.titleFont; font.pixelSize: 22; font.bold: true
                        color: root.c.fg || "white"
                    }
                }
            }
        }
    }
}
