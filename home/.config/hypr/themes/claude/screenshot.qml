// Claude: warm dim, terracotta rounded frame, serif labels.
// Capture: the spark blooms in the middle of the region, the shot shrinks into a card
// in the bottom-right corner with "Saved", then slides away.
import QtQuick
import Quickshell.Widgets

Item {
    id: t
    property QtObject ctx
    readonly property var c: ctx ? ctx.pal.colors : ({})
    readonly property string serif: ctx ? ctx.pal.display : "serif"
    readonly property bool capturing: ctx && ctx.phase === "capture"
    readonly property bool selected: ctx && ctx.sel.width > 0
    readonly property rect r: !ctx ? Qt.rect(0, 0, 0, 0) : selected ? ctx.sel : ctx.hover
    readonly property bool hasRect: r.width > 0
    readonly property real px: ctx ? ctx.scale : 1

    // "#rrggbb" + alpha -> "#aarrggbb", which QML colors accept.
    function a(col, al) {
        return "#" + ("0" + Math.round(al * 255).toString(16)).slice(-2) + String(col).slice(1);
    }

    // ---------- selection ----------

    Item {
        id: dim
        anchors.fill: parent
        readonly property color shade: Qt.rgba(0.07, 0.06, 0.05, 0.58)
        Rectangle { visible: !t.hasRect; anchors.fill: parent; color: dim.shade }
        Rectangle { visible: t.hasRect; color: dim.shade; x: 0; y: 0; width: parent.width; height: t.r.y }
        Rectangle { visible: t.hasRect; color: dim.shade; x: 0; y: t.r.y + t.r.height; width: parent.width; height: parent.height - y }
        Rectangle { visible: t.hasRect; color: dim.shade; x: 0; y: t.r.y; width: t.r.x; height: t.r.height }
        Rectangle { visible: t.hasRect; color: dim.shade; x: t.r.x + t.r.width; y: t.r.y; width: parent.width - x; height: t.r.height }
    }

    Rectangle {
        id: frame
        visible: t.hasRect && !t.capturing
        x: t.r.x - 2; y: t.r.y - 2; width: t.r.width + 4; height: t.r.height + 4
        radius: 8
        color: "transparent"
        border.width: 2
        border.color: t.c.accent || "#d97757"
        opacity: t.selected ? 1 : 0.55
    }

    Rectangle {
        id: sizeLabel
        visible: t.hasRect && !t.capturing
        readonly property bool below: t.r.y + t.r.height + height + 14 < t.height
        x: Math.max(8, Math.min(t.r.x + (t.r.width - width) / 2, t.width - width - 8))
        y: below ? t.r.y + t.r.height + 10 : Math.max(8, t.r.y + 10)
        width: sizeText.implicitWidth + 24; height: sizeText.implicitHeight + 10
        radius: height / 2
        color: t.a(t.c.bg2 || "#2a2927", 0.92)
        border.color: t.a(t.c.accent || "#d97757", 0.5)
        Text {
            id: sizeText
            anchors.centerIn: parent
            text: Math.round(t.r.width * t.px) + " × " + Math.round(t.r.height * t.px)
            font.family: t.serif; font.pixelSize: 15
            color: t.c.fg || "white"
        }
    }

    Rectangle {
        id: hint
        visible: !t.selected && !t.capturing && t.ctx && t.ctx.mode !== "full"
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom; anchors.bottomMargin: 48
        width: hintRow.implicitWidth + 36; height: 40; radius: 20
        color: t.a(t.c.bg || "#1f1e1d", 0.9)
        border.color: t.a(t.c.accent || "#d97757", 0.35)
        Row {
            id: hintRow
            anchors.centerIn: parent
            spacing: 10
            Image { source: t.ctx ? "file://" + t.ctx.themeDir + "/assets/spark.svg" : ""; width: 16; height: 16; sourceSize: Qt.size(32, 32); anchors.verticalCenter: parent.verticalCenter }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Выделите область  ·  клик — окно  ·  Enter — весь экран  ·  Esc — отмена"
                font.family: t.serif; font.pixelSize: 14
                color: t.c.fg || "white"
            }
        }
    }

    // ---------- capture ----------

    readonly property real cardW: Math.min(340, Math.max(160, r.width * 0.45))
    readonly property real cardH: Math.min(cardW * r.height / Math.max(1, r.width), 260)

    ClippingRectangle {
        id: card
        visible: false
        radius: 14
        color: t.c.bg2 || "#2a2927"
        border.width: 2
        border.color: t.c.accent || "#d97757"
        Image {
            anchors.fill: parent
            source: t.ctx ? t.ctx.frozen : ""
            sourceClipRect: t.ctx ? Qt.rect(t.r.x * t.ctx.scale, t.r.y * t.ctx.scale,
                                            t.r.width * t.ctx.scale, t.r.height * t.ctx.scale)
                                  : Qt.rect(0, 0, 0, 0)
            fillMode: Image.PreserveAspectCrop
            smooth: true
        }
    }

    Image {
        id: spark
        visible: false
        source: t.ctx ? "file://" + t.ctx.themeDir + "/assets/spark.svg" : ""
        width: 120; height: 120
        sourceSize: Qt.size(240, 240)
        x: t.r.x + (t.r.width - width) / 2
        y: t.r.y + (t.r.height - height) / 2
        scale: 0; opacity: 0
    }

    Column {
        id: saved
        visible: false
        opacity: 0
        spacing: 2
        x: card.x - width - 18
        y: card.y + card.height - height
        Text {
            anchors.right: parent.right
            text: "Сохранено"
            font.family: t.serif; font.pixelSize: 26; font.italic: true
            color: t.c.accent || "#d97757"
        }
        Text {
            anchors.right: parent.right
            text: "в буфере и в ~/Pictures/screenshots"
            font.family: t.serif; font.pixelSize: 13
            color: t.c.muted || "#8a857b"
        }
    }

    onCapturingChanged: if (capturing) captureAnim.start()

    SequentialAnimation {
        id: captureAnim
        ScriptAction {
            script: {
                card.x = t.r.x; card.y = t.r.y; card.width = t.r.width; card.height = t.r.height;
                card.radius = 8;
                card.visible = true; spark.visible = true; saved.visible = true;
            }
        }
        ParallelAnimation {
            NumberAnimation { target: spark; property: "scale"; from: 0.2; to: 1.15; duration: 420; easing.type: Easing.OutBack }
            NumberAnimation { target: spark; property: "opacity"; from: 0; to: 1; duration: 200 }
            NumberAnimation { target: spark; property: "rotation"; from: -90; to: 90; duration: 900; easing.type: Easing.OutCubic }
            NumberAnimation { target: t.ctx; property: "frozenOpacity"; to: 0; duration: 500; easing.type: Easing.InOutQuad }
            NumberAnimation { target: dim; property: "opacity"; to: 0; duration: 500 }
        }
        ParallelAnimation {
            NumberAnimation { target: card; property: "x"; to: t.width - t.cardW - 36; duration: 560; easing.type: Easing.OutCubic }
            NumberAnimation { target: card; property: "y"; to: t.height - t.cardH - 36; duration: 560; easing.type: Easing.OutCubic }
            NumberAnimation { target: card; property: "width"; to: t.cardW; duration: 560; easing.type: Easing.OutCubic }
            NumberAnimation { target: card; property: "height"; to: t.cardH; duration: 560; easing.type: Easing.OutCubic }
            NumberAnimation { target: card; property: "radius"; to: 14; duration: 560 }
            NumberAnimation { target: spark; property: "opacity"; to: 0; duration: 380; easing.type: Easing.InQuad }
            NumberAnimation { target: spark; property: "scale"; to: 0.4; duration: 380; easing.type: Easing.InQuad }
            SequentialAnimation {
                PauseAnimation { duration: 280 }
                NumberAnimation { target: saved; property: "opacity"; to: 1; duration: 260 }
            }
        }
        PauseAnimation { duration: 900 }
        ParallelAnimation {
            NumberAnimation { target: card; property: "x"; to: t.width + 20; duration: 380; easing.type: Easing.InCubic }
            NumberAnimation { target: saved; property: "opacity"; to: 0; duration: 240 }
        }
        ScriptAction { script: t.ctx.finish() }
    }
}
