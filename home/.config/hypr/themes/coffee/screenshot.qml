// Coffee: warm dark-roast dim, a square caramel frame with corner brackets, mono labels.
// Capture: the shot turns into an instant photo that develops from dark sepia to full colour,
// tilts a little and slides out at the bottom like a photo leaving the camera.
import QtQuick
import QtQuick.Effects

Item {
    id: t
    property QtObject ctx
    readonly property var c: ctx ? ctx.pal.colors : ({})
    readonly property string mono: ctx ? ctx.pal.display : "monospace"
    readonly property color caramel: c.accent || "#d8a657"
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
        readonly property color shade: Qt.rgba(0.1, 0.07, 0.04, 0.6)
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
            anchors.fill: parent; anchors.margins: -1
            radius: 3
            color: "transparent"
            border.width: 1
            border.color: t.a(t.caramel, 0.6)
        }

        // Viewfinder brackets.
        Repeater {
            model: [[0, 0], [1, 0], [0, 1], [1, 1]]
            Item {
                required property var modelData
                readonly property int sx: modelData[0] ? -1 : 1
                readonly property int sy: modelData[1] ? -1 : 1
                x: modelData[0] ? frame.width : 0
                y: modelData[1] ? frame.height : 0
                Rectangle { x: parent.sx > 0 ? -4 : -18; y: parent.sy > 0 ? -4 : 1; width: 22; height: 3; color: t.caramel }
                Rectangle { x: parent.sx > 0 ? -4 : 1; y: parent.sy > 0 ? -4 : -18; width: 3; height: 22; color: t.caramel }
            }
        }
    }

    Rectangle {
        visible: t.hasRect && !t.capturing
        readonly property bool below: t.r.y + t.r.height + height + 16 < t.height
        x: Math.max(8, Math.min(t.r.x + (t.r.width - width) / 2, t.width - width - 8))
        y: below ? t.r.y + t.r.height + 12 : Math.max(8, t.r.y + 12)
        width: sizeText.implicitWidth + 20; height: sizeText.implicitHeight + 8
        radius: 4
        color: t.caramel
        Text {
            id: sizeText
            anchors.centerIn: parent
            text: Math.round(t.r.width * t.px) + "×" + Math.round(t.r.height * t.px)
            font.family: t.mono; font.pixelSize: 14; font.bold: true
            color: t.c.bg || "black"
        }
    }

    Rectangle {
        visible: !t.selected && !t.capturing && t.ctx && t.ctx.mode !== "full"
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom; anchors.bottomMargin: 48
        width: hintText.implicitWidth + 36; height: 38; radius: 6
        color: t.a(t.c.bg || "#1d1612", 0.94)
        border.color: t.a(t.caramel, 0.6)
        Text {
            id: hintText
            anchors.centerIn: parent
            text: "☕ выделите область · клик — окно · enter — весь экран · esc — отмена"
            font.family: t.mono; font.pixelSize: 14
            color: t.c.fg || "white"
        }
    }

    // ---------- capture ----------

    // The photo: picture fitted into at most 460×340, cream border with a wide bottom strip.
    readonly property real fit: Math.min(1, 460 / Math.max(1, r.width), 340 / Math.max(1, r.height))
    readonly property real picW: r.width * fit
    readonly property real picH: r.height * fit

    Rectangle {
        id: photo
        visible: false
        width: t.picW + 28; height: t.picH + 76
        color: t.c.fg || "#ebdbb2"
        radius: 3
        transformOrigin: Item.Center
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true; shadowColor: "#000000"; shadowOpacity: 0.6
            shadowBlur: 0.7; shadowVerticalOffset: 8; blurMax: 24
        }

        property real develop: 0  // 0 = dark sepia, 1 = developed

        Image {
            id: pic
            x: 14; y: 14; width: t.picW; height: t.picH
            source: t.ctx ? t.ctx.frozen : ""
            sourceClipRect: Qt.rect(t.r.x * t.px, t.r.y * t.px, t.r.width * t.px, t.r.height * t.px)
            smooth: true
            visible: false
        }
        MultiEffect {
            anchors.fill: pic
            source: pic
            saturation: -1 + photo.develop
            brightness: -0.55 * (1 - photo.develop)
            colorization: 0.6 * (1 - photo.develop)
            colorizationColor: t.c.accent3 || "#a9643c"
        }
        Text {
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 18 }
            text: "сохранено · " + Qt.formatTime(new Date(), "HH:mm")
            font.family: t.mono; font.pixelSize: 17
            color: t.c.bg2 || "#2a201a"
            opacity: photo.develop
        }
    }

    onCapturingChanged: if (capturing) captureAnim.start()

    SequentialAnimation {
        id: captureAnim
        ScriptAction {
            script: {
                // Start exactly over the selection so the picture seems to lift off the screen.
                photo.scale = 1 / t.fit;
                photo.x = t.r.x + t.r.width / 2 - photo.width / 2;
                photo.y = t.r.y + t.r.height / 2 - photo.height / 2;
                photo.visible = true;
            }
        }
        ParallelAnimation {
            NumberAnimation { target: t.ctx; property: "frozenOpacity"; to: 0; duration: 300 }
            NumberAnimation { target: dim; property: "opacity"; to: 0.6; duration: 300 }
            NumberAnimation { target: photo; property: "scale"; to: 1; duration: 520; easing.type: Easing.OutCubic }
            NumberAnimation { target: photo; property: "x"; to: (t.width - photo.width) / 2; duration: 520; easing.type: Easing.OutCubic }
            NumberAnimation { target: photo; property: "y"; to: (t.height - photo.height) / 2; duration: 520; easing.type: Easing.OutCubic }
            NumberAnimation { target: photo; property: "rotation"; to: -4; duration: 520; easing.type: Easing.OutBack }
        }
        NumberAnimation { target: photo; property: "develop"; to: 1; duration: 1000; easing.type: Easing.InOutSine }
        PauseAnimation { duration: 350 }
        ParallelAnimation {
            NumberAnimation { target: photo; property: "y"; to: t.height + 40; duration: 520; easing.type: Easing.InCubic }
            NumberAnimation { target: photo; property: "rotation"; to: 6; duration: 520 }
            NumberAnimation { target: dim; property: "opacity"; to: 0; duration: 520 }
        }
        ScriptAction { script: t.ctx.finish() }
    }
}
