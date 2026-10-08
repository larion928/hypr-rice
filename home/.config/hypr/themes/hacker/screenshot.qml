// Hacker: black dim with scanlines, crosshair, marching-ants frame, terminal-style labels.
// Capture: a green scanline sweeps the region, digital rain falls through it, a terminal log
// types itself out, then everything cuts off with a flicker.
import QtQuick
import QtQuick.Shapes

Item {
    id: t
    property QtObject ctx
    readonly property var c: ctx ? ctx.pal.colors : ({})
    readonly property string mono: ctx ? ctx.pal.font : "monospace"
    readonly property color green: c.accent || "#2bd94a"
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
        readonly property color shade: Qt.rgba(0, 0.02, 0, 0.62)
        Rectangle { visible: !t.hasRect; anchors.fill: parent; color: dim.shade }
        Rectangle { visible: t.hasRect; color: dim.shade; x: 0; y: 0; width: parent.width; height: t.r.y }
        Rectangle { visible: t.hasRect; color: dim.shade; x: 0; y: t.r.y + t.r.height; width: parent.width; height: parent.height - y }
        Rectangle { visible: t.hasRect; color: dim.shade; x: 0; y: t.r.y; width: t.r.x; height: t.r.height }
        Rectangle { visible: t.hasRect; color: dim.shade; x: t.r.x + t.r.width; y: t.r.y; width: parent.width - x; height: t.r.height }

        Canvas {
            anchors.fill: parent
            onPaint: {
                const g = getContext("2d");
                g.fillStyle = t.a(t.green, 0.05);
                for (let y = 0; y < height; y += 3)
                    g.fillRect(0, y, width, 1);
            }
        }
    }

    Item {
        id: crosshair
        visible: !t.capturing && t.ctx && t.ctx.mouse.x >= 0 && !t.selected
        Rectangle { x: 0; y: t.ctx ? t.ctx.mouse.y : 0; width: t.width; height: 1; color: t.a(t.green, 0.45) }
        Rectangle { x: t.ctx ? t.ctx.mouse.x : 0; y: 0; width: 1; height: t.height; color: t.a(t.green, 0.45) }
        Text {
            x: (t.ctx ? t.ctx.mouse.x : 0) + 10; y: (t.ctx ? t.ctx.mouse.y : 0) + 8
            text: t.ctx ? Math.round(t.ctx.mouse.x * t.px) + "," + Math.round(t.ctx.mouse.y * t.px) : ""
            font.family: t.mono; font.pixelSize: 12
            color: t.green
        }
    }

    Shape {
        id: frame
        visible: t.hasRect && !t.capturing
        opacity: t.selected ? 1 : 0.6
        ShapePath {
            id: ants
            strokeColor: t.green
            strokeWidth: 1.5
            fillColor: "transparent"
            strokeStyle: ShapePath.DashLine
            dashPattern: [4, 3]
            startX: t.r.x; startY: t.r.y
            PathLine { x: t.r.x + t.r.width; y: t.r.y }
            PathLine { x: t.r.x + t.r.width; y: t.r.y + t.r.height }
            PathLine { x: t.r.x; y: t.r.y + t.r.height }
            PathLine { x: t.r.x; y: t.r.y }
        }
        Timer {
            interval: 60; repeat: true; running: frame.visible
            onTriggered: ants.dashOffset = (ants.dashOffset + 1) % 7
        }
    }

    Rectangle {
        visible: t.hasRect && !t.capturing
        readonly property bool below: t.r.y + t.r.height + height + 10 < t.height
        x: Math.max(4, Math.min(t.r.x, t.width - width - 4))
        y: below ? t.r.y + t.r.height + 6 : Math.max(4, t.r.y - height - 6)
        width: label.implicitWidth + 14; height: label.implicitHeight + 6
        color: "black"
        border.color: t.green
        Text {
            id: label
            anchors.centerIn: parent
            text: "[x:" + Math.round(t.r.x * t.px) + " y:" + Math.round(t.r.y * t.px) + "] "
                  + Math.round(t.r.width * t.px) + "x" + Math.round(t.r.height * t.px)
            font.family: t.mono; font.pixelSize: 13
            color: t.green
        }
    }

    Rectangle {
        visible: !t.selected && !t.capturing && t.ctx && t.ctx.mode !== "full"
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom; anchors.bottomMargin: 44
        width: hintText.implicitWidth + 28; height: 32
        color: "black"
        border.color: t.a(t.green, 0.6)
        Text {
            id: hintText
            anchors.centerIn: parent
            text: "$ shot --select   drag: region | click: window | enter: screen | esc: abort"
            font.family: t.mono; font.pixelSize: 13
            color: t.green
        }
    }

    // ---------- capture ----------

    readonly property string glyphs: "ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄ0123456789ABCDEF<>/{}#$"

    function randomColumn(n) {
        let s = "";
        for (let i = 0; i < n; i++)
            s += glyphs[Math.floor(Math.random() * glyphs.length)] + (i < n - 1 ? "\n" : "");
        return s;
    }

    Item {
        id: fx
        visible: false
        x: t.r.x; y: t.r.y; width: t.r.width; height: t.r.height
        clip: true

        Rectangle { anchors.fill: parent; color: t.a(t.green, 0.1) }

        Repeater {
            id: rain
            model: fx.visible ? Math.max(4, Math.min(90, Math.floor(fx.width / 16))) : 0
            Text {
                id: col
                required property int index
                readonly property int rows: Math.max(6, Math.floor(fx.height / 18))
                x: index * (fx.width / rain.count) + Math.random() * 6
                text: t.randomColumn(Math.ceil(rows * (0.3 + Math.random() * 0.5)))
                font.family: t.mono; font.pixelSize: 15
                lineHeight: 1.1
                color: t.green
                opacity: 0.35 + Math.random() * 0.6
                NumberAnimation on y {
                    from: -col.implicitHeight - Math.random() * fx.height * 0.6
                    to: fx.height + 20
                    duration: 650 + Math.random() * 500
                    easing.type: Easing.InQuad
                }
            }
        }

        Rectangle {
            id: scan
            width: parent.width; height: 3
            y: -10
            color: t.c.accent2 || "#57f57a"
            Rectangle {
                anchors.bottom: parent.top
                width: parent.width; height: 40
                gradient: Gradient {
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 1; color: t.a(t.green, 0.35) }
                }
            }
        }
    }

    Rectangle {
        id: term
        visible: false
        opacity: 0
        readonly property string fullText:
            "$ shot --save\n"
            + "> captured " + Math.round(t.r.width * t.px) + "x" + Math.round(t.r.height * t.px) + "\n"
            + "> wrote " + (t.ctx ? t.ctx.outFile.split("/").pop() : "") + "\n"
            + "> copied to clipboard\n> done_"
        property int shown: 0
        x: Math.max(16, Math.min(t.r.x + 16, t.width - width - 16))
        y: Math.max(16, Math.min(t.r.y + t.r.height - height - 16, t.height - height - 16))
        width: termText.implicitWidth + 28; height: termText.implicitHeight + 20
        color: t.a("#000000", 0.88)
        border.color: t.green
        Text {
            id: termText
            x: 14; y: 10
            text: term.fullText.slice(0, term.shown)
            font.family: t.mono; font.pixelSize: 14
            color: t.green
        }
        NumberAnimation on shown { id: typing; running: false; from: 0; to: term.fullText.length; duration: 650 }
    }

    onCapturingChanged: if (capturing) captureAnim.start()

    SequentialAnimation {
        id: captureAnim
        ScriptAction { script: { fx.visible = true; term.visible = true; } }
        ParallelAnimation {
            NumberAnimation { target: scan; property: "y"; from: -10; to: fx.height + 10; duration: 480; easing.type: Easing.InOutSine }
            NumberAnimation { target: t.ctx; property: "frozenOpacity"; to: 0.25; duration: 480 }
            SequentialAnimation {
                PauseAnimation { duration: 200 }
                NumberAnimation { target: term; property: "opacity"; to: 1; duration: 120 }
                ScriptAction { script: typing.start() }
            }
        }
        PauseAnimation { duration: 1100 }
        // Hard flicker out.
        NumberAnimation { target: t; property: "opacity"; to: 0.2; duration: 40 }
        NumberAnimation { target: t; property: "opacity"; to: 0.9; duration: 40 }
        NumberAnimation { target: t; property: "opacity"; to: 0.05; duration: 50 }
        NumberAnimation { target: t; property: "opacity"; to: 0.6; duration: 40 }
        ParallelAnimation {
            NumberAnimation { target: t; property: "opacity"; to: 0; duration: 60 }
            NumberAnimation { target: t.ctx; property: "frozenOpacity"; to: 0; duration: 60 }
        }
        ScriptAction { script: t.ctx.finish() }
    }
}
