// Cyberpunk: purple dim, glowing magenta frame with cyan corner brackets, neon labels.
// Capture: white flash, RGB-split glitch with shifting slices and a "CAPTURED" tag, then the
// region collapses like a CRT switching off.
import QtQuick
import QtQuick.Effects

Item {
    id: t
    property QtObject ctx
    readonly property var c: ctx ? ctx.pal.colors : ({})
    readonly property string mono: ctx ? ctx.pal.font : "monospace"
    readonly property color pink: c.accent || "#ff2e88"
    readonly property color cyan: c.accent2 || "#21e6ff"
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
        readonly property color shade: Qt.rgba(0.05, 0.01, 0.09, 0.62)
        Rectangle { visible: !t.hasRect; anchors.fill: parent; color: dim.shade }
        Rectangle { visible: t.hasRect; color: dim.shade; x: 0; y: 0; width: parent.width; height: t.r.y }
        Rectangle { visible: t.hasRect; color: dim.shade; x: 0; y: t.r.y + t.r.height; width: parent.width; height: parent.height - y }
        Rectangle { visible: t.hasRect; color: dim.shade; x: 0; y: t.r.y; width: t.r.x; height: t.r.height }
        Rectangle { visible: t.hasRect; color: dim.shade; x: t.r.x + t.r.width; y: t.r.y; width: parent.width - x; height: t.r.height }
    }

    Item {
        id: frame
        visible: t.hasRect && !t.capturing
        opacity: t.selected ? 1 : 0.6
        x: t.r.x; y: t.r.y; width: t.r.width; height: t.r.height

        Rectangle {
            anchors.fill: parent; anchors.margins: -2
            color: "transparent"
            border.width: 2
            border.color: t.pink
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: t.pink
                shadowBlur: 0.9
                shadowHorizontalOffset: 0; shadowVerticalOffset: 0
                blurMax: 24
            }
        }

        // Corner brackets: [horizontal-dir, vertical-dir] per corner.
        Repeater {
            model: [[0, 0], [1, 0], [0, 1], [1, 1]]
            Item {
                required property var modelData
                readonly property real len: 18
                x: modelData[0] ? frame.width + 6 - len : -6
                y: modelData[1] ? frame.height + 6 - len : -6
                width: len; height: len
                Rectangle { width: parent.len; height: 3; color: t.cyan; y: parent.modelData[1] ? parent.len - 3 : 0 }
                Rectangle { width: 3; height: parent.len; color: t.cyan; x: parent.modelData[0] ? parent.len - 3 : 0 }
            }
        }
    }

    Rectangle {
        visible: t.hasRect && !t.capturing
        readonly property bool below: t.r.y + t.r.height + height + 16 < t.height
        x: Math.max(4, Math.min(t.r.x + t.r.width - width, t.width - width - 4))
        y: below ? t.r.y + t.r.height + 12 : Math.max(4, t.r.y - height - 12)
        width: sizeText.implicitWidth + 20; height: sizeText.implicitHeight + 6
        color: t.pink
        Text {
            id: sizeText
            anchors.centerIn: parent
            text: "◢ " + Math.round(t.r.width * t.px) + "×" + Math.round(t.r.height * t.px) + " ◣"
            font.family: t.mono; font.pixelSize: 13; font.bold: true
            color: t.c.bg || "black"
        }
    }

    Rectangle {
        visible: !t.selected && !t.capturing && t.ctx && t.ctx.mode !== "full"
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom; anchors.bottomMargin: 44
        width: hintText.implicitWidth + 30; height: 34
        color: t.a(t.c.bg || "#0a0612", 0.92)
        border.color: t.cyan
        Text {
            id: hintText
            anchors.centerIn: parent
            text: "SELECT ▸ DRAG  //  CLICK = WINDOW  //  ENTER = SCREEN  //  ESC = ABORT"
            font.family: t.mono; font.pixelSize: 13; font.bold: true
            color: t.cyan
        }
    }

    // ---------- capture ----------

    readonly property rect src: Qt.rect(r.x * px, r.y * px, r.width * px, r.height * px)

    Item {
        id: glitch
        visible: false
        x: t.r.x; y: t.r.y; width: t.r.width; height: t.r.height
        transform: Scale { id: glitchScale; origin.x: glitch.width / 2; origin.y: glitch.height / 2 }

        Image {
            id: base
            anchors.fill: parent
            source: t.ctx ? t.ctx.frozen : ""
            sourceClipRect: t.src
            visible: false
        }
        MultiEffect {
            id: pinkCopy
            source: base; width: parent.width; height: parent.height
            colorization: 1; colorizationColor: t.pink
            opacity: 0.7
        }
        MultiEffect {
            id: cyanCopy
            source: base; width: parent.width; height: parent.height
            colorization: 1; colorizationColor: t.cyan
            opacity: 0.7
        }

        // Horizontal slices of the real image that jump sideways.
        Repeater {
            id: slices
            model: 9
            Item {
                required property int index
                readonly property real h: glitch.height / slices.count
                y: index * h; width: glitch.width; height: h
                clip: true
                Image {
                    y: -parent.y
                    width: glitch.width; height: glitch.height
                    source: t.ctx ? t.ctx.frozen : ""
                    sourceClipRect: t.src
                }
            }
        }

        Rectangle { id: flash; anchors.fill: parent; color: "white"; opacity: 0 }

        Item {
            id: tag
            x: (glitch.width - width) / 2
            y: (glitch.height - height) / 2
            width: tagText.implicitWidth; height: tagText.implicitHeight
            opacity: 0
            readonly property int size: Math.max(22, Math.min(64, glitch.width / 9))
            Text { x: -4; text: tagText.text; font: tagText.font; color: t.cyan; opacity: 0.8 }
            Text { x: 4; text: tagText.text; font: tagText.font; color: t.pink; opacity: 0.8 }
            Text {
                id: tagText
                text: "CAPTURED"
                font.family: t.mono; font.pixelSize: tag.size; font.bold: true; font.letterSpacing: 4
                color: "white"
            }
        }
    }

    Timer {
        id: jitter
        interval: 45; repeat: true
        onTriggered: {
            pinkCopy.x = -4 - Math.random() * 12; pinkCopy.y = (Math.random() - 0.5) * 6;
            cyanCopy.x = 4 + Math.random() * 12; cyanCopy.y = (Math.random() - 0.5) * 6;
            for (let i = 0; i < slices.count; i++) {
                const s = slices.itemAt(i);
                s.x = Math.random() < 0.4 ? (Math.random() - 0.5) * 60 : 0;
            }
            tag.x = (glitch.width - tag.width) / 2 + (Math.random() - 0.5) * 8;
        }
    }

    onCapturingChanged: if (capturing) captureAnim.start()

    SequentialAnimation {
        id: captureAnim
        ScriptAction { script: { glitch.visible = true; jitter.start(); } }
        ParallelAnimation {
            NumberAnimation { target: t.ctx; property: "frozenOpacity"; to: 0; duration: 250 }
            NumberAnimation { target: dim; property: "opacity"; to: 0.4; duration: 250 }
            SequentialAnimation {
                NumberAnimation { target: flash; property: "opacity"; to: 0.9; duration: 60 }
                NumberAnimation { target: flash; property: "opacity"; to: 0; duration: 160 }
            }
        }
        NumberAnimation { target: tag; property: "opacity"; to: 1; duration: 80 }
        PauseAnimation { duration: 650 }
        ScriptAction { script: { jitter.stop(); pinkCopy.x = 0; cyanCopy.x = 0; } }
        // CRT off: squash to a line, then to a dot.
        ParallelAnimation {
            NumberAnimation { target: glitchScale; property: "yScale"; to: 0.015; duration: 150; easing.type: Easing.InQuad }
            NumberAnimation { target: flash; property: "opacity"; to: 1; duration: 150 }
            NumberAnimation { target: dim; property: "opacity"; to: 0; duration: 250 }
        }
        NumberAnimation { target: glitchScale; property: "xScale"; to: 0; duration: 130; easing.type: Easing.InQuad }
        ScriptAction { script: t.ctx.finish() }
    }
}
