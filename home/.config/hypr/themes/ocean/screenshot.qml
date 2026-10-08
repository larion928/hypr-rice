// Ocean: deep-blue dim, a glowing rounded frame with a slow wave along its bottom edge.
// Capture: a turquoise wave rises through the region and washes the shot away, bubbles float up.
import QtQuick
import QtQuick.Effects
import QtQuick.Particles

Item {
    id: t
    property QtObject ctx
    readonly property var c: ctx ? ctx.pal.colors : ({})
    readonly property string rounded: ctx ? ctx.pal.display : "sans-serif"
    readonly property color glow: c.accent || "#5ee6e0"
    readonly property color jelly: c.accent2 || "#c77dff"
    readonly property bool capturing: ctx && ctx.phase === "capture"
    readonly property bool selected: ctx && ctx.sel.width > 0
    readonly property rect r: !ctx ? Qt.rect(0, 0, 0, 0) : selected ? ctx.sel : ctx.hover
    readonly property bool hasRect: r.width > 0
    readonly property real px: ctx ? ctx.scale : 1

    function a(col, al) {
        return "#" + ("0" + Math.round(al * 255).toString(16)).slice(-2) + String(col).slice(1);
    }

    // Shared clock for every wave on screen.
    property real phase: 0
    NumberAnimation on phase { from: 0; to: Math.PI * 2; duration: 1600; loops: Animation.Infinite }

    // ---------- selection ----------

    Item {
        id: dim
        anchors.fill: parent
        readonly property color shade: Qt.rgba(0.01, 0.03, 0.1, 0.58)
        Rectangle { visible: !t.hasRect; anchors.fill: parent; color: dim.shade }
        Rectangle { visible: t.hasRect; color: dim.shade; x: 0; y: 0; width: parent.width; height: t.r.y }
        Rectangle { visible: t.hasRect; color: dim.shade; x: 0; y: t.r.y + t.r.height; width: parent.width; height: parent.height - y }
        Rectangle { visible: t.hasRect; color: dim.shade; x: 0; y: t.r.y; width: t.r.x; height: t.r.height }
        Rectangle { visible: t.hasRect; color: dim.shade; x: t.r.x + t.r.width; y: t.r.y; width: parent.width - x; height: t.r.height }
    }

    Rectangle {
        id: frame
        visible: t.hasRect && !t.capturing
        opacity: t.selected ? 1 : 0.6
        x: t.r.x - 2; y: t.r.y - 2; width: t.r.width + 4; height: t.r.height + 4
        radius: 16
        color: "transparent"
        border.width: 2
        border.color: t.glow
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true; shadowColor: t.glow
            shadowBlur: 1; shadowHorizontalOffset: 0; shadowVerticalOffset: 0
            blurMax: 24
        }
    }

    // A thin wave hugging the bottom of the selection.
    Canvas {
        id: edgeWave
        visible: frame.visible
        opacity: frame.opacity
        x: t.r.x + 10; y: t.r.y + t.r.height - 14; width: Math.max(0, t.r.width - 20); height: 12
        property real ph: t.phase
        onPhChanged: requestPaint()
        onPaint: {
            const g = getContext("2d");
            g.reset();
            g.strokeStyle = String(t.jelly);
            g.lineWidth = 1.5;
            g.globalAlpha = 0.7;
            g.beginPath();
            for (let x = 0; x <= width; x += 4) {
                const y = height / 2 + Math.sin(x / 22 + ph) * 3.5;
                x === 0 ? g.moveTo(x, y) : g.lineTo(x, y);
            }
            g.stroke();
        }
    }

    Rectangle {
        visible: t.hasRect && !t.capturing
        readonly property bool below: t.r.y + t.r.height + height + 16 < t.height
        x: Math.max(8, Math.min(t.r.x + (t.r.width - width) / 2, t.width - width - 8))
        y: below ? t.r.y + t.r.height + 12 : Math.max(8, t.r.y + 12)
        width: sizeText.implicitWidth + 28; height: sizeText.implicitHeight + 10
        radius: height / 2
        color: t.a(t.c.bg2 || "#0b1433", 0.9)
        border.color: t.a(t.glow, 0.5)
        Text {
            id: sizeText
            anchors.centerIn: parent
            text: Math.round(t.r.width * t.px) + " × " + Math.round(t.r.height * t.px)
            font.family: t.rounded; font.pixelSize: 15; font.bold: true
            color: t.glow
        }
    }

    Rectangle {
        visible: !t.selected && !t.capturing && t.ctx && t.ctx.mode !== "full"
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom; anchors.bottomMargin: 48
        width: hintText.implicitWidth + 44; height: 42; radius: 21
        color: t.a(t.c.bg || "#050a1f", 0.9)
        border.color: t.a(t.glow, 0.4)
        Text {
            id: hintText
            anchors.centerIn: parent
            text: "≋  Выделите область  ·  клик — окно  ·  Enter — весь экран  ·  Esc — отмена  ≋"
            font.family: t.rounded; font.pixelSize: 15
            color: t.c.fg || "white"
        }
    }

    // ---------- capture ----------

    Item {
        id: washed
        visible: false
        x: t.r.x; y: t.r.y; width: t.r.width; height: t.r.height
        clip: true

        Image {
            id: shotImage
            anchors.fill: parent
            source: t.ctx ? t.ctx.frozen : ""
            sourceClipRect: Qt.rect(t.r.x * t.px, t.r.y * t.px, t.r.width * t.px, t.r.height * t.px)
        }

        // level: 0 = water below the region, 1 = covers it completely.
        Canvas {
            id: water
            anchors.fill: parent
            property real level: 0
            property real ph: t.phase
            onLevelChanged: requestPaint()
            onPhChanged: requestPaint()
            onPaint: {
                const g = getContext("2d");
                g.reset();
                const amp = Math.min(18, height * 0.06);
                const top = height + amp - level * (height + amp * 2);
                const grad = g.createLinearGradient(0, top, 0, height);
                grad.addColorStop(0, t.a(t.glow, 0.95));
                grad.addColorStop(1, t.a(t.c.accent3 || "#3a4da7", 0.95));
                g.fillStyle = grad;
                g.beginPath();
                g.moveTo(0, height);
                for (let x = 0; x <= width + 8; x += 8)
                    g.lineTo(x, top + Math.sin(x / 40 + ph * 2) * amp + Math.sin(x / 17 - ph) * amp * 0.35);
                g.lineTo(width, height);
                g.closePath();
                g.fill();
            }
        }
    }

    ParticleSystem { id: bubbles }
    ImageParticle {
        system: bubbles
        source: t.ctx ? "file://" + t.ctx.themeDir + "/assets/bubble.svg" : ""
        color: t.glow
        colorVariation: 0.1
        alpha: 0.9
        entryEffect: ImageParticle.Scale
    }
    Emitter {
        id: emitter
        system: bubbles
        x: t.r.x; y: t.r.y + t.r.height * 0.3; width: t.r.width; height: t.r.height * 0.7
        enabled: false
        lifeSpan: 1500; lifeSpanVariation: 500
        size: 14; sizeVariation: 10; endSize: 22
        velocity: AngleDirection { angle: 270; angleVariation: 15; magnitude: 120; magnitudeVariation: 60 }
        acceleration: PointDirection { y: -60; xVariation: 30 }
    }

    Text {
        id: savedText
        visible: false
        opacity: 0
        text: "≋  сохранено  ≋"
        x: t.r.x + (t.r.width - width) / 2
        y: Math.min(t.r.y + t.r.height / 2 - height / 2, t.height - height - 24)
        font.family: t.rounded; font.pixelSize: 30; font.bold: true
        color: t.c.fg || "white"
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true; shadowColor: t.glow
            shadowBlur: 0.8; shadowHorizontalOffset: 0; shadowVerticalOffset: 0; blurMax: 20
        }
    }

    onCapturingChanged: if (capturing) captureAnim.start()

    SequentialAnimation {
        id: captureAnim
        ScriptAction { script: { washed.visible = true; savedText.visible = true; } }
        ParallelAnimation {
            NumberAnimation { target: t.ctx; property: "frozenOpacity"; to: 0; duration: 350 }
            NumberAnimation { target: dim; property: "opacity"; to: 0.55; duration: 350 }
            NumberAnimation { target: water; property: "level"; to: 1; duration: 750; easing.type: Easing.InOutSine }
            SequentialAnimation {
                PauseAnimation { duration: 250 }
                ScriptAction { script: emitter.burst(Math.max(40, Math.min(260, Math.round(t.r.width * t.r.height / 4000)))) }
            }
        }
        ParallelAnimation {
            NumberAnimation { target: washed; property: "opacity"; to: 0; duration: 500 }
            NumberAnimation { target: savedText; property: "opacity"; to: 1; duration: 400 }
        }
        PauseAnimation { duration: 700 }
        ParallelAnimation {
            NumberAnimation { target: dim; property: "opacity"; to: 0; duration: 450 }
            NumberAnimation { target: savedText; property: "opacity"; to: 0; duration: 450 }
        }
        PauseAnimation { duration: 200 }
        ScriptAction { script: t.ctx.finish() }
    }
}
