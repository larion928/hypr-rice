// Theme switcher, toggled by ~/.local/bin/theme-picker (Alt+Shift+T, waybar palette button).
// The script writes $PICKER_DATA: every theme's palette.json + ui.json and a wallpaper thumbnail.
// Each card is drawn in its own theme's colours and fonts; Enter runs changetheme.
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

ShellRoot {
    id: root

    property var themes: []
    property int index: 0
    property bool closing: false
    readonly property var cur: themes.find(t => t.current) || themes[0] || ({ pal: { colors: {} }, ui: {} })
    // Up to five cards fit in one row; more go into a 4-column grid with smaller cards.
    readonly property int columns: themes.length > 5 ? 4 : Math.max(1, themes.length)
    readonly property bool compact: themes.length > 5

    FileView { id: dataFile; path: Quickshell.env("PICKER_DATA"); blockLoading: true }

    Component.onCompleted: {
        try { themes = JSON.parse(dataFile.text()); } catch (e) { console.warn("picker data:", e); }
        const i = themes.findIndex(t => t.current);
        index = i >= 0 ? i : 0;
    }

    function a(col, al) {
        return "#" + ("0" + Math.round(al * 255).toString(16)).slice(-2) + String(col || "#888888").slice(1);
    }

    function move(d) {
        if (themes.length) index = (index + d + themes.length) % themes.length;
    }

    function apply() {
        if (closing || !themes.length) return;
        const t = themes[index];
        closing = true;
        if (!t.current)
            Quickshell.execDetached(["changetheme", t.name]);
        closeAnim.start();
    }

    function close() {
        if (closing) return;
        closing = true;
        closeAnim.start();
    }

    IpcHandler {
        target: "picker"
        function close(): void { root.close(); }
    }

    PanelWindow {
        id: win
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "theme-picker"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        Item {
            id: scene
            anchors.fill: parent
            opacity: 0
            focus: true

            Component.onCompleted: openAnim.start()
            NumberAnimation { id: openAnim; target: scene; property: "opacity"; to: 1; duration: 180 }
            SequentialAnimation {
                id: closeAnim
                PauseAnimation { duration: 120 }
                NumberAnimation { target: scene; property: "opacity"; to: 0; duration: 220 }
                ScriptAction { script: Qt.quit() }
            }

            Keys.onPressed: e => {
                if (e.key === Qt.Key_Escape) root.close();
                else if (e.key === Qt.Key_Left || e.key === Qt.Key_Backtab || e.key === Qt.Key_H) root.move(-1);
                else if (e.key === Qt.Key_Right || e.key === Qt.Key_Tab || e.key === Qt.Key_L) root.move(1);
                else if (e.key === Qt.Key_Up || e.key === Qt.Key_K) root.move(-root.columns);
                else if (e.key === Qt.Key_Down || e.key === Qt.Key_J) root.move(root.columns);
                else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) root.apply();
                else if (e.key >= Qt.Key_1 && e.key <= Qt.Key_9 && e.key - Qt.Key_1 < root.themes.length) {
                    root.index = e.key - Qt.Key_1;
                    root.apply();
                }
            }

            Rectangle {
                anchors.fill: parent
                color: root.a(root.cur.pal.colors.bg, 0.62)
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root.close()
                onWheel: w => root.move(w.angleDelta.y > 0 || w.angleDelta.x > 0 ? -1 : 1)
            }

            Text {
                anchors { horizontalCenter: parent.horizontalCenter; bottom: cards.top; bottomMargin: 60 }
                text: "Тема оформления"
                font.family: root.cur.pal.display || "serif"
                font.pixelSize: 40
                color: root.cur.pal.colors.fg || "white"
            }

            Grid {
                id: cards
                anchors.centerIn: parent
                columns: root.columns
                spacing: 28

                Repeater {
                    model: root.themes

                    Item {
                        id: cardRoot
                        required property var modelData
                        required property int index
                        readonly property var t: modelData
                        readonly property var c: t.pal.colors
                        readonly property bool selected: root.index === index
                        readonly property real r: Math.min(t.ui.radius ?? 12, 22)
                        width: root.compact ? 300 : 320
                        height: root.compact ? 332 : 372
                        opacity: 0

                        Component.onCompleted: appear.start()
                        SequentialAnimation {
                            id: appear
                            PauseAnimation { duration: cardRoot.index * 55 }
                            ParallelAnimation {
                                NumberAnimation { target: cardRoot; property: "opacity"; to: 1; duration: 260 }
                                NumberAnimation { target: card; property: "y"; from: 46; to: 0; duration: 380; easing.type: Easing.OutCubic }
                            }
                        }

                        Rectangle {
                            id: card
                            width: parent.width
                            height: parent.height
                            radius: cardRoot.r
                            color: cardRoot.c.bg
                            border.width: cardRoot.selected ? 2 : 1
                            border.color: cardRoot.selected ? cardRoot.c.accent : root.a(cardRoot.c.muted, 0.4)
                            scale: cardRoot.selected ? 1.06 : 0.97
                            opacity: cardRoot.selected ? 1 : 0.62
                            Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
                            Behavior on opacity { NumberAnimation { duration: 180 } }

                            layer.enabled: cardRoot.selected
                            layer.effect: MultiEffect {
                                shadowEnabled: true
                                shadowColor: cardRoot.c.accent
                                shadowBlur: 1
                                shadowHorizontalOffset: 0; shadowVerticalOffset: 0
                                blurMax: 40
                            }

                            ClippingRectangle {
                                id: thumb
                                x: 10; y: 10
                                width: parent.width - 20
                                height: width * 9 / 16
                                radius: Math.max(0, cardRoot.r - 4)
                                color: cardRoot.c.bg2
                                Image {
                                    anchors.fill: parent
                                    source: cardRoot.t.thumb ? "file://" + cardRoot.t.thumb : ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                }
                            }

                            Row {
                                id: title
                                anchors { left: parent.left; leftMargin: 16; top: thumb.bottom; topMargin: 16 }
                                spacing: 10
                                Image {
                                    visible: !!cardRoot.t.ui.headerIcon
                                    source: cardRoot.t.ui.headerIcon ? "file://" + cardRoot.t.dir + "/" + cardRoot.t.ui.headerIcon : ""
                                    width: 24; height: 24; sourceSize: Qt.size(48, 48)
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    visible: !cardRoot.t.ui.headerIcon
                                    text: cardRoot.t.ui.headerGlyph || "•"
                                    font.family: cardRoot.t.pal.font; font.pixelSize: 22; font.bold: true
                                    color: cardRoot.c.accent
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    text: cardRoot.t.ui.upperTitle ? cardRoot.t.pal.label.toUpperCase() : cardRoot.t.pal.label
                                    font.family: cardRoot.t.pal.display; font.pixelSize: 26
                                    font.italic: !!cardRoot.t.ui.italicTitle
                                    color: cardRoot.c.fg
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            Rectangle {
                                visible: cardRoot.t.current
                                anchors { right: parent.right; rightMargin: 16; verticalCenter: title.verticalCenter }
                                width: curText.implicitWidth + 16; height: 22; radius: Math.min(cardRoot.r, 11)
                                color: root.a(cardRoot.c.accent, 0.22)
                                Text {
                                    id: curText
                                    anchors.centerIn: parent
                                    text: "сейчас"
                                    font.family: cardRoot.t.pal.font; font.pixelSize: 12
                                    color: cardRoot.c.accent
                                }
                            }

                            Row {
                                id: swatches
                                anchors { left: parent.left; leftMargin: 16; top: title.bottom; topMargin: 16 }
                                spacing: 6
                                Repeater {
                                    model: ["bg2", "fg", "accent", "accent2", "accent3", "muted", "good", "warn", "crit"]
                                    Rectangle {
                                        required property string modelData
                                        width: 24; height: 24
                                        radius: cardRoot.r > 4 ? 12 : 2
                                        color: cardRoot.c[modelData]
                                        border.color: root.a(cardRoot.c.fg, 0.15)
                                    }
                                }
                            }

                            // What the window border gradient looks like in this theme.
                            Rectangle {
                                anchors { left: parent.left; right: parent.right; top: swatches.bottom; margins: 16; topMargin: 18 }
                                height: 6
                                radius: cardRoot.r > 4 ? 3 : 0
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0; color: cardRoot.c.accent }
                                    GradientStop { position: 1; color: cardRoot.c.accent2 }
                                }
                            }

                            Text {
                                anchors { left: parent.left; leftMargin: 16; bottom: parent.bottom; bottomMargin: 14 }
                                text: (cardRoot.index + 1) + "  ·  " + cardRoot.t.name
                                font.family: cardRoot.t.pal.font; font.pixelSize: 12
                                color: cardRoot.c.muted
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: root.index = cardRoot.index
                            onClicked: { root.index = cardRoot.index; root.apply(); }
                        }
                    }
                }
            }

            Text {
                anchors { horizontalCenter: parent.horizontalCenter; top: cards.bottom; topMargin: 56 }
                text: (root.compact ? "←  →  ↑  ↓" : "←  →") + "  выбрать      Enter  применить      1–"
                      + Math.min(9, root.themes.length) + "  сразу      Esc  закрыть"
                font.family: root.cur.pal.font || "monospace"
                font.pixelSize: 15
                color: root.cur.pal.colors.muted || "grey"
            }
        }
    }
}
