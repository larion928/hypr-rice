// Mr. Robot: black dim with faint scanlines, red viewfinder corners that glitch now and then,
// "hello, friend." hint. Capture: the selected picture tears into shifted slices with a red and
// cyan split, an fsociety terminal log types itself out, then everything cuts off with a flicker.
import QtQuick
import QtQuick.Effects

Item {
    id: t
    property QtObject ctx
    readonly property var c: ctx ? ctx.pal.colors : ({})
    readonly property string mono: ctx ? ctx.pal.font : "monospace"
    readonly property color red: c.accent || "#e8191c"
    readonly property color white: c.accent2 || "#f5f5f5"
    readonly property bool capturing: ctx && ctx.phase === "capture"
    readonly property bool selected: ctx && ctx.sel.width > 0
    readonly property rect r: !ctx ? Qt.rect(0, 0, 0, 0) : selected ? ctx.sel : ctx.hover
    readonly property bool hasRect: r.width > 0
    readonly property real px: ctx ? ctx.scale : 1

    function a(col, al) {
        return "#" + ("0" + Math.round(al * 255).toString(16)).slice(-2) + String(col).slice(1);
    }

    // ---------- selection ----------

    Item {
        id: dim
        anchors.fill: parent
        readonly property color shade: Qt.rgba(0, 0, 0, 0.66)
        Rectangle { visible: !t.hasRect; anchors.fill: parent; color: dim.shade }
        Rectangle { visible: t.hasRect; color: dim.shade; x: 0; y: 0; width: parent.width; height: t.r.y }
        Rectangle { visible: t.hasRect; color: dim.shade; x: 0; y: t.r.y + t.r.height; width: parent.width; height: parent.height - y }
        Rectangle { visible: t.hasRect; color: dim.shade; x: 0; y: t.r.y; width: t.r.x; height: t.r.height }
        Rectangle { visible: t.hasRect; color: dim.shade; x: t.r.x + t.r.width; y: t.r.y; width: parent.width - x; height: t.r.height }

        Canvas {
            anchors.fill: parent
            onPaint: {
                const g = getContext("2d");
                g.fillStyle = t.a(t.white, 0.03);
                for (let y = 0; y < height; y += 3)
                    g.fillRect(0, y, width, 1);
            }
        }
    }

    Item {
        id: crosshair
        visible: !t.capturing && t.ctx && t.ctx.mouse.x >= 0 && !t.selected
        Rectangle { x: 0; y: t.ctx ? t.ctx.mouse.y : 0; width: t.width; height: 1; color: t.a(t.white, 0.25) }
        Rectangle { x: t.ctx ? t.ctx.mouse.x : 0; y: 0; width: 1; height: t.height; color: t.a(t.white, 0.25) }
        Rectangle {
            x: (t.ctx ? t.ctx.mouse.x : 0) - 3; y: (t.ctx ? t.ctx.mouse.y : 0) - 3
            width: 7; height: 7
            color: t.red
        }
        Text {
            x: (t.ctx ? t.ctx.mouse.x : 0) + 12; y: (t.ctx ? t.ctx.mouse.y : 0) + 8
            text: t.ctx ? Math.round(t.ctx.mouse.x * t.px) + " " + Math.round(t.ctx.mouse.y * t.px) : ""
            font.family: t.mono; font.pixelSize: 12
            color: t.white
        }
    }

    // Viewfinder: a thin white frame with red corners; every few seconds it jumps sideways for a
    // moment, split into red and white, like a bad video signal.
    Item {
        id: frame
        visible: t.hasRect && !t.capturing
        property real jitter: 0
        x: t.r.x + jitter; y: t.r.y; width: t.r.width; height: t.r.height
        opacity: t.selected ? 1 : 0.7
        readonly property real arm: Math.min(28, width / 3, height / 3)

        Rectangle { anchors.fill: parent; color: "transparent"; border.color: t.a(t.white, 0.5); border.width: 1 }
        Rectangle {
            visible: frame.jitter !== 0
            x: -frame.jitter * 2; width: parent.width; height: parent.height
            color: "transparent"; border.color: t.a(t.red, 0.8); border.width: 1
        }
        Repeater {
            model: [[0, 0, 1, 1], [1, 0, -1, 1], [0, 1, 1, -1], [1, 1, -1, -1]]
            Item {
                required property var modelData
                x: modelData[0] * frame.width; y: modelData[1] * frame.height
                Rectangle {
                    x: modelData[2] > 0 ? -2 : -frame.arm + 2; y: modelData[3] > 0 ? -2 : -1
                    width: frame.arm; height: 3; color: t.red
                }
                Rectangle {
                    x: modelData[2] > 0 ? -2 : -1; y: modelData[3] > 0 ? -2 : -frame.arm + 2
                    width: 3; height: frame.arm; color: t.red
                }
            }
        }
        SequentialAnimation {
            running: frame.visible
            loops: Animation.Infinite
            PauseAnimation { duration: 2200 }
            PropertyAction { target: frame; property: "jitter"; value: 6 }
            PauseAnimation { duration: 60 }
            PropertyAction { target: frame; property: "jitter"; value: -4 }
            PauseAnimation { duration: 50 }
            PropertyAction { target: frame; property: "jitter"; value: 0 }
        }
    }

    Rectangle {
        visible: t.hasRect && !t.capturing
        readonly property bool below: t.r.y + t.r.height + height + 10 < t.height
        x: Math.max(4, Math.min(t.r.x, t.width - width - 4))
        y: below ? t.r.y + t.r.height + 8 : Math.max(4, t.r.y - height - 8)
        width: label.implicitWidth + 16; height: label.implicitHeight + 8
        color: "black"
        Text {
            id: label
            anchors.centerIn: parent
            textFormat: Text.StyledText
            text: "<font color='" + t.red + "'>f</font>" + Math.round(t.r.width * t.px) + "×" + Math.round(t.r.height * t.px)
                  + "  <font color='" + t.a(t.white, 0.55) + "'>@ " + Math.round(t.r.x * t.px) + "," + Math.round(t.r.y * t.px) + "</font>"
            font.family: t.mono; font.pixelSize: 13
            color: t.white
        }
    }

    Rectangle {
        visible: !t.selected && !t.capturing && t.ctx && t.ctx.mode !== "full"
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom; anchors.bottomMargin: 44
        width: hintText.implicitWidth + 32; height: 34
        color: "black"
        Rectangle { width: 3; height: parent.height; color: t.red }
        Text {
            id: hintText
            anchors.centerIn: parent
            textFormat: Text.StyledText
            text: "<font color='" + t.red + "'>hello, friend.</font>   drag: область · click: окно · enter: экран · esc: выйти"
            font.family: t.mono; font.pixelSize: 13
            color: t.white
        }
    }

    // ---------- capture ----------

    // The selected picture cut into horizontal slices; each slice is the frozen screen seen through
    // a window over its own rows, shifted sideways at random while the tear lasts.
    Item {
        id: tear
        visible: false
        x: t.r.x; y: t.r.y; width: t.r.width; height: t.r.height
        clip: true
        readonly property int slices: Math.max(6, Math.min(18, Math.floor(height / 40)))

        Repeater {
            id: sliceRepeater
            model: tear.visible ? tear.slices : 0
            Item {
                id: slice
                required property int index
                property real shift: 0
                y: index * tear.height / tear.slices
                width: tear.width; height: Math.ceil(tear.height / tear.slices)
                clip: true
                Image {
                    x: -t.r.x + slice.shift; y: -t.r.y - slice.y
                    width: t.width; height: t.height
                    source: t.ctx ? t.ctx.frozen : ""
                    cache: false
                }
            }
        }
        // Red and cyan ghosts of the picture: the channel split of a broken signal.
        Repeater {
            model: tear.visible ? [[t.red, -6], ["#00e5ff", 6]] : []
            MultiEffect {
                required property var modelData
                x: modelData[1]; width: tear.width; height: tear.height
                source: ghostSource
                colorization: 1
                colorizationColor: modelData[0]
                opacity: 0.35
            }
        }
        Item {
            id: ghostSource
            visible: false
            width: tear.width; height: tear.height
            layer.enabled: tear.visible
            Image {
                x: -t.r.x; y: -t.r.y
                width: t.width; height: t.height
                source: t.ctx ? t.ctx.frozen : ""
                cache: false
            }
        }
        Timer {
            interval: 45; repeat: true; running: tear.visible
            onTriggered: {
                for (let i = 0; i < sliceRepeater.count; i++) {
                    const s = sliceRepeater.itemAt(i);
                    if (s) s.shift = Math.random() < 0.45 ? (Math.random() - 0.5) * Math.min(80, tear.width / 6) : 0;
                }
            }
        }
    }

    Rectangle {
        id: term
        visible: false
        opacity: 0
        readonly property string fullText:
            "root@fsociety:~# ./shot\n"
            + "[+] " + Math.round(t.r.width * t.px) + "x" + Math.round(t.r.height * t.px) + " captured\n"
            + "[+] saved " + (t.ctx ? t.ctx.outFile.split("/").pop() : "") + "\n"
            + "[+] copied to clipboard\n"
            + "[!] we are fsociety_"
        property int shown: 0
        x: Math.max(16, Math.min(t.r.x + 16, t.width - width - 16))
        y: Math.max(16, Math.min(t.r.y + t.r.height - height - 16, t.height - height - 16))
        width: termText.implicitWidth + 30; height: termText.implicitHeight + 22
        color: t.a("#000000", 0.9)
        Rectangle { width: 3; height: parent.height; color: t.red }
        Text {
            id: termText
            x: 16; y: 11
            text: term.fullText.slice(0, term.shown)
            font.family: t.mono; font.pixelSize: 14
            color: t.white
        }
        NumberAnimation on shown { id: typing; running: false; from: 0; to: term.fullText.length; duration: 700 }
    }

    onCapturingChanged: if (capturing) captureAnim.start()

    SequentialAnimation {
        id: captureAnim
        ScriptAction { script: tear.visible = true }
        PauseAnimation { duration: 420 }
        ScriptAction { script: { tear.visible = false; term.visible = true; } }
        ParallelAnimation {
            NumberAnimation { target: t.ctx; property: "frozenOpacity"; to: 0.25; duration: 300 }
            NumberAnimation { target: term; property: "opacity"; to: 1; duration: 100 }
            ScriptAction { script: typing.start() }
        }
        PauseAnimation { duration: 1150 }
        // Signal lost.
        NumberAnimation { target: t; property: "opacity"; to: 0.15; duration: 40 }
        NumberAnimation { target: t; property: "opacity"; to: 0.85; duration: 40 }
        NumberAnimation { target: t; property: "opacity"; to: 0.05; duration: 50 }
        ParallelAnimation {
            NumberAnimation { target: t; property: "opacity"; to: 0; duration: 60 }
            NumberAnimation { target: t.ctx; property: "frozenOpacity"; to: 0; duration: 60 }
        }
        ScriptAction { script: t.ctx.finish() }
    }
}
