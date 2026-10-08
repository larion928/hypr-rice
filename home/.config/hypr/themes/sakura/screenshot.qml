// Sakura: plum dim, a soft pink rounded frame with blossoms turning at the corners, serif italics.
// Capture: the shot dissolves into cherry petals that tumble down with the wind.
import QtQuick
import QtQuick.Effects
import QtQuick.Particles

Item {
    id: t
    property QtObject ctx
    readonly property var c: ctx ? ctx.pal.colors : ({})
    readonly property string serif: ctx ? ctx.pal.display : "serif"
    readonly property color pink: c.accent || "#f4a7c0"
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
        readonly property color shade: Qt.rgba(0.11, 0.06, 0.09, 0.55)
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
            radius: 14
            color: "transparent"
            border.width: 2
            border.color: t.pink
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true; shadowColor: t.pink
                shadowBlur: 0.6; shadowHorizontalOffset: 0; shadowVerticalOffset: 0
                blurMax: 16
            }
        }

        Repeater {
            model: [[0, 0], [1, 0], [0, 1], [1, 1]]
            Text {
                required property var modelData
                required property int index
                text: "✿"
                font.pixelSize: 18
                color: index % 2 ? (t.c.accent2 || "#ffd1df") : t.pink
                x: (modelData[0] ? frame.width : 0) - width / 2
                y: (modelData[1] ? frame.height : 0) - height / 2
                RotationAnimation on rotation {
                    loops: Animation.Infinite
                    from: index * 45; to: index * 45 + 360; duration: 9000
                }
            }
        }
    }

    Rectangle {
        visible: t.hasRect && !t.capturing
        readonly property bool below: t.r.y + t.r.height + height + 16 < t.height
        x: Math.max(8, Math.min(t.r.x + (t.r.width - width) / 2, t.width - width - 8))
        y: below ? t.r.y + t.r.height + 12 : Math.max(8, t.r.y + 12)
        width: sizeText.implicitWidth + 28; height: sizeText.implicitHeight + 8
        radius: height / 2
        color: t.a(t.c.bg2 || "#281c22", 0.9)
        border.color: t.a(t.pink, 0.5)
        Text {
            id: sizeText
            anchors.centerIn: parent
            text: Math.round(t.r.width * t.px) + " × " + Math.round(t.r.height * t.px)
            font.family: t.serif; font.pixelSize: 18; font.italic: true
            color: t.c.fg || "white"
        }
    }

    Rectangle {
        visible: !t.selected && !t.capturing && t.ctx && t.ctx.mode !== "full"
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom; anchors.bottomMargin: 48
        width: hintText.implicitWidth + 44; height: 42; radius: 21
        color: t.a(t.c.bg || "#1c1418", 0.9)
        border.color: t.a(t.pink, 0.4)
        Text {
            id: hintText
            anchors.centerIn: parent
            text: "✿  Выделите область  ·  клик — окно  ·  Enter — весь экран  ·  Esc — отмена  ✿"
            font.family: t.serif; font.pixelSize: 17; font.italic: true
            color: t.c.fg || "white"
        }
    }

    // ---------- capture ----------

    Image {
        id: shotImage
        visible: false
        x: t.r.x; y: t.r.y; width: t.r.width; height: t.r.height
        source: t.ctx ? t.ctx.frozen : ""
        sourceClipRect: Qt.rect(t.r.x * t.px, t.r.y * t.px, t.r.width * t.px, t.r.height * t.px)
    }

    ParticleSystem { id: petals }
    ImageParticle {
        system: petals
        source: t.ctx ? "file://" + t.ctx.themeDir + "/assets/petal.svg" : ""
        color: t.pink
        colorVariation: 0.08
        alpha: 0.95
        rotationVariation: 180
        rotationVelocity: 90
        rotationVelocityVariation: 160
        entryEffect: ImageParticle.Scale
    }
    Emitter {
        id: emitter
        system: petals
        x: t.r.x; y: t.r.y; width: t.r.width; height: t.r.height
        enabled: false
        lifeSpan: 1700; lifeSpanVariation: 400
        size: 18; sizeVariation: 8; endSize: 10
        velocity: AngleDirection { angle: 70; angleVariation: 40; magnitude: 90; magnitudeVariation: 60 }
        // Gravity plus a breeze to the right.
        acceleration: PointDirection { x: 60; y: 160; xVariation: 40; yVariation: 30 }
    }

    Text {
        id: savedText
        visible: false
        opacity: 0
        text: "✿  сохранено  ✿"
        x: t.r.x + (t.r.width - width) / 2
        y: Math.min(t.r.y + t.r.height / 2 - height / 2, t.height - height - 24)
        font.family: t.serif; font.pixelSize: 34; font.italic: true
        color: t.c.accent2 || "white"
        style: Text.Outline; styleColor: t.a(t.c.bg || "#1c1418", 0.6)
    }

    onCapturingChanged: if (capturing) captureAnim.start()

    SequentialAnimation {
        id: captureAnim
        ScriptAction { script: { shotImage.visible = true; savedText.visible = true; } }
        ParallelAnimation {
            NumberAnimation { target: t.ctx; property: "frozenOpacity"; to: 0; duration: 350 }
            NumberAnimation { target: dim; property: "opacity"; to: 0.5; duration: 350 }
        }
        ScriptAction { script: emitter.burst(Math.max(80, Math.min(600, Math.round(t.r.width * t.r.height / 1800)))) }
        ParallelAnimation {
            NumberAnimation { target: shotImage; property: "opacity"; to: 0; duration: 600; easing.type: Easing.InQuad }
            NumberAnimation { target: shotImage; property: "scale"; to: 0.94; duration: 600 }
            SequentialAnimation {
                PauseAnimation { duration: 250 }
                NumberAnimation { target: savedText; property: "opacity"; to: 1; duration: 400 }
            }
        }
        PauseAnimation { duration: 700 }
        ParallelAnimation {
            NumberAnimation { target: dim; property: "opacity"; to: 0; duration: 450 }
            NumberAnimation { target: savedText; property: "opacity"; to: 0; duration: 450 }
        }
        PauseAnimation { duration: 300 }
        ScriptAction { script: t.ctx.finish() }
    }
}
