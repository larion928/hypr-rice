// Frieren: deep blue dim, soft glowing frame, twinkling ✦ at the corners, serif italics.
// Capture: a magic circle unfolds around the region, the shot brightens and dissolves
// into drifting blue sparks.
import QtQuick
import QtQuick.Effects
import QtQuick.Particles

Item {
    id: t
    property QtObject ctx
    readonly property var c: ctx ? ctx.pal.colors : ({})
    readonly property string serif: ctx ? ctx.pal.display : "serif"
    readonly property color glow: c.accent2 || "#b3c6e6"
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
        readonly property color shade: Qt.rgba(0.03, 0.05, 0.12, 0.52)
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
            radius: 12
            color: "transparent"
            border.width: 1.5
            border.color: t.glow
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true; shadowColor: t.c.accent || "#8fb0d9"
                shadowBlur: 0.8; shadowHorizontalOffset: 0; shadowVerticalOffset: 0
                blurMax: 20
            }
        }

        Repeater {
            model: [[0, 0], [1, 0], [0, 1], [1, 1]]
            Text {
                required property var modelData
                required property int index
                text: "✦"
                font.pixelSize: 16
                color: t.glow
                x: (modelData[0] ? frame.width : 0) - width / 2
                y: (modelData[1] ? frame.height : 0) - height / 2
                SequentialAnimation on opacity {
                    loops: Animation.Infinite
                    PauseAnimation { duration: index * 230 }
                    NumberAnimation { from: 0.25; to: 1; duration: 700; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 1; to: 0.25; duration: 700; easing.type: Easing.InOutSine }
                }
            }
        }
    }

    Rectangle {
        visible: t.hasRect && !t.capturing
        readonly property bool below: t.r.y + t.r.height + height + 16 < t.height
        x: Math.max(8, Math.min(t.r.x + (t.r.width - width) / 2, t.width - width - 8))
        y: below ? t.r.y + t.r.height + 12 : Math.max(8, t.r.y + 12)
        width: sizeText.implicitWidth + 26; height: sizeText.implicitHeight + 8
        radius: height / 2
        color: t.a(t.c.bg2 || "#171a24", 0.88)
        border.color: t.a(t.glow, 0.45)
        Text {
            id: sizeText
            anchors.centerIn: parent
            text: Math.round(t.r.width * t.px) + " × " + Math.round(t.r.height * t.px)
            font.family: t.serif; font.pixelSize: 15; font.italic: true
            color: t.c.fg || "white"
        }
    }

    Rectangle {
        visible: !t.selected && !t.capturing && t.ctx && t.ctx.mode !== "full"
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom; anchors.bottomMargin: 48
        width: hintText.implicitWidth + 40; height: 40; radius: 20
        color: t.a(t.c.bg || "#0d0f16", 0.88)
        border.color: t.a(t.glow, 0.35)
        Text {
            id: hintText
            anchors.centerIn: parent
            text: "✦  Выделите область  ·  клик — окно  ·  Enter — весь экран  ·  Esc — отмена  ✦"
            font.family: t.serif; font.pixelSize: 14; font.italic: true
            color: t.c.fg || "white"
        }
    }

    // ---------- capture ----------

    readonly property real circleSize: Math.min(Math.max(r.width, r.height) * 1.15, Math.min(width, height) * 0.95)

    Canvas {
        id: circle
        visible: false
        width: t.circleSize; height: t.circleSize
        x: t.r.x + t.r.width / 2 - width / 2
        y: t.r.y + t.r.height / 2 - height / 2
        opacity: 0; scale: 0.5
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true; shadowColor: t.c.accent || "#8fb0d9"
            shadowBlur: 1; shadowHorizontalOffset: 0; shadowVerticalOffset: 0; blurMax: 32
        }
        onPaint: {
            const g = getContext("2d");
            const cx = width / 2, cy = height / 2, R = width / 2 - 4;
            g.reset();
            g.strokeStyle = String(t.glow);
            g.fillStyle = String(t.glow);
            g.lineWidth = 1.6;
            const ring = rad => { g.beginPath(); g.arc(cx, cy, rad, 0, Math.PI * 2); g.stroke(); };
            ring(R); ring(R * 0.93); ring(R * 0.62);
            // Rune ticks between the outer rings.
            for (let i = 0; i < 48; i++) {
                const a = i / 48 * Math.PI * 2, l = i % 4 === 0 ? 0.05 : 0.025;
                g.beginPath();
                g.moveTo(cx + Math.cos(a) * R * 0.93, cy + Math.sin(a) * R * 0.93);
                g.lineTo(cx + Math.cos(a) * R * (0.93 - l), cy + Math.sin(a) * R * (0.93 - l));
                g.stroke();
            }
            // Hexagram.
            for (const off of [-Math.PI / 2, Math.PI / 2]) {
                g.beginPath();
                for (let i = 0; i <= 3; i++) {
                    const a = off + i * Math.PI * 2 / 3;
                    const x = cx + Math.cos(a) * R * 0.88, y = cy + Math.sin(a) * R * 0.88;
                    i === 0 ? g.moveTo(x, y) : g.lineTo(x, y);
                }
                g.stroke();
            }
            for (let i = 0; i < 6; i++) {
                const a = -Math.PI / 2 + i * Math.PI / 3;
                g.beginPath();
                g.arc(cx + Math.cos(a) * R * 0.88, cy + Math.sin(a) * R * 0.88, R * 0.04, 0, Math.PI * 2);
                g.fill();
            }
        }
    }

    Item {
        id: shotImage
        visible: false
        x: t.r.x; y: t.r.y; width: t.r.width; height: t.r.height
        property real bright: 0
        Image {
            id: shotSrc
            anchors.fill: parent
            source: t.ctx ? t.ctx.frozen : ""
            sourceClipRect: Qt.rect(t.r.x * t.px, t.r.y * t.px, t.r.width * t.px, t.r.height * t.px)
            visible: false
        }
        MultiEffect {
            anchors.fill: parent
            source: shotSrc
            brightness: shotImage.bright
            blurEnabled: true; blur: shotImage.bright; blurMax: 24
            colorization: shotImage.bright * 0.5; colorizationColor: t.glow
        }
    }

    ParticleSystem { id: sparks }
    ImageParticle {
        system: sparks
        source: "qrc:///particleresources/glowdot.png"
        color: t.glow
        colorVariation: 0.15
        alpha: 0.9
        entryEffect: ImageParticle.Fade
    }
    Emitter {
        id: emitter
        system: sparks
        x: t.r.x; y: t.r.y; width: t.r.width; height: t.r.height
        enabled: false
        lifeSpan: 1200; lifeSpanVariation: 400
        size: 10; sizeVariation: 6; endSize: 2
        velocity: AngleDirection { angle: 270; angleVariation: 35; magnitude: 70; magnitudeVariation: 50 }
        acceleration: PointDirection { y: -40; xVariation: 20 }
    }

    Text {
        id: savedText
        visible: false
        opacity: 0
        text: "✦  сохранено  ✦"
        x: t.r.x + (t.r.width - width) / 2
        y: Math.min(t.r.y + t.r.height + 16, t.height - height - 24)
        font.family: t.serif; font.pixelSize: 24; font.italic: true
        color: t.c.fg || "white"
    }

    onCapturingChanged: if (capturing) captureAnim.start()

    SequentialAnimation {
        id: captureAnim
        ScriptAction {
            script: {
                circle.requestPaint();
                circle.visible = true; shotImage.visible = true; savedText.visible = true;
            }
        }
        ParallelAnimation {
            NumberAnimation { target: t.ctx; property: "frozenOpacity"; to: 0; duration: 400 }
            NumberAnimation { target: dim; property: "opacity"; to: 0.55; duration: 400 }
            NumberAnimation { target: circle; property: "opacity"; to: 0.95; duration: 300 }
            NumberAnimation { target: circle; property: "scale"; to: 1; duration: 650; easing.type: Easing.OutCubic }
            NumberAnimation { target: circle; property: "rotation"; from: 0; to: 140; duration: 1700; easing.type: Easing.OutSine }
            NumberAnimation { target: shotImage; property: "bright"; to: 0.55; duration: 600; easing.type: Easing.InQuad }
            SequentialAnimation {
                PauseAnimation { duration: 450 }
                ScriptAction { script: emitter.burst(Math.max(150, Math.min(900, Math.round(t.r.width * t.r.height / 900)))) }
                ParallelAnimation {
                    NumberAnimation { target: shotImage; property: "opacity"; to: 0; duration: 550 }
                    NumberAnimation { target: savedText; property: "opacity"; to: 1; duration: 400 }
                }
            }
        }
        ParallelAnimation {
            NumberAnimation { target: circle; property: "opacity"; to: 0; duration: 450 }
            NumberAnimation { target: dim; property: "opacity"; to: 0; duration: 450 }
            NumberAnimation { target: savedText; property: "opacity"; to: 0; duration: 450 }
        }
        PauseAnimation { duration: 250 }
        ScriptAction { script: t.ctx.finish() }
    }
}
