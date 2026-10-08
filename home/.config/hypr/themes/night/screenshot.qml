// Night: plain grey dim, thin light frame, small monospace label.
// Capture: a soft white flash over the region, then it gently shrinks and fades.
import QtQuick

Item {
    id: t
    property QtObject ctx
    readonly property var c: ctx ? ctx.pal.colors : ({})
    readonly property string mono: ctx ? ctx.pal.font : "monospace"
    readonly property bool capturing: ctx && ctx.phase === "capture"
    readonly property bool selected: ctx && ctx.sel.width > 0
    readonly property rect r: !ctx ? Qt.rect(0, 0, 0, 0) : selected ? ctx.sel : ctx.hover
    readonly property bool hasRect: r.width > 0
    readonly property real px: ctx ? ctx.scale : 1

    function a(col, al) {
        return "#" + ("0" + Math.round(al * 255).toString(16)).slice(-2) + String(col).slice(1);
    }

    Item {
        id: dim
        anchors.fill: parent
        readonly property color shade: Qt.rgba(0, 0, 0, 0.45)
        Rectangle { visible: !t.hasRect; anchors.fill: parent; color: dim.shade }
        Rectangle { visible: t.hasRect; color: dim.shade; x: 0; y: 0; width: parent.width; height: t.r.y }
        Rectangle { visible: t.hasRect; color: dim.shade; x: 0; y: t.r.y + t.r.height; width: parent.width; height: parent.height - y }
        Rectangle { visible: t.hasRect; color: dim.shade; x: 0; y: t.r.y; width: t.r.x; height: t.r.height }
        Rectangle { visible: t.hasRect; color: dim.shade; x: t.r.x + t.r.width; y: t.r.y; width: parent.width - x; height: t.r.height }
    }

    Rectangle {
        visible: t.hasRect && !t.capturing
        x: t.r.x - 1; y: t.r.y - 1; width: t.r.width + 2; height: t.r.height + 2
        color: "transparent"
        border.width: 1
        border.color: t.a(t.c.fg || "#c9cace", t.selected ? 0.9 : 0.45)
    }

    Text {
        visible: t.hasRect && !t.capturing
        readonly property bool below: t.r.y + t.r.height + height + 10 < t.height
        x: Math.max(6, Math.min(t.r.x + t.r.width - width, t.width - width - 6))
        y: below ? t.r.y + t.r.height + 6 : Math.max(6, t.r.y - height - 6)
        text: Math.round(t.r.width * t.px) + " × " + Math.round(t.r.height * t.px)
        font.family: t.mono; font.pixelSize: 12
        color: t.c.muted || "#7c8088"
    }

    Text {
        visible: !t.selected && !t.capturing && t.ctx && t.ctx.mode !== "full"
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom; anchors.bottomMargin: 40
        text: "область — тянуть  ·  окно — клик  ·  экран — enter  ·  esc"
        font.family: t.mono; font.pixelSize: 12
        color: t.c.muted || "#7c8088"
    }

    Item {
        id: shot
        visible: false
        x: t.r.x; y: t.r.y; width: t.r.width; height: t.r.height
        Image {
            anchors.fill: parent
            source: t.ctx ? t.ctx.frozen : ""
            sourceClipRect: Qt.rect(t.r.x * t.px, t.r.y * t.px, t.r.width * t.px, t.r.height * t.px)
        }
        Rectangle { id: flash; anchors.fill: parent; color: "white"; opacity: 0 }
    }

    onCapturingChanged: if (capturing) captureAnim.start()

    SequentialAnimation {
        id: captureAnim
        ScriptAction { script: shot.visible = true }
        ParallelAnimation {
            NumberAnimation { target: t.ctx; property: "frozenOpacity"; to: 0; duration: 300 }
            SequentialAnimation {
                NumberAnimation { target: flash; property: "opacity"; to: 0.55; duration: 80 }
                NumberAnimation { target: flash; property: "opacity"; to: 0; duration: 260 }
            }
        }
        ParallelAnimation {
            NumberAnimation { target: shot; property: "scale"; to: 0.96; duration: 380; easing.type: Easing.OutQuad }
            NumberAnimation { target: shot; property: "opacity"; to: 0; duration: 380 }
            NumberAnimation { target: dim; property: "opacity"; to: 0; duration: 380 }
        }
        ScriptAction { script: t.ctx.finish() }
    }
}
