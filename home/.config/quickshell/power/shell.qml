// Power menu, toggled by ~/.local/bin/power-menu (waybar power button).
// ui.json "powerStyle": "cards" (big themed buttons) or "terminal" (a shell-like list, hacker).
// Logout, reboot and poweroff need a second press.
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    readonly property string themeDir: Quickshell.env("POWER_THEME_DIR")
    property var pal: ({ colors: {} })
    property var ui: ({})
    readonly property var c: pal.colors || {}
    readonly property string titleFont: ui.titleFont === "display" ? (pal.display || "serif") : (pal.font || "monospace")
    readonly property string bodyFont: pal.font || "monospace"
    readonly property int r: Math.min(ui.radius ?? 14, 26)
    readonly property bool terminal: ui.powerStyle === "terminal"

    property int current: 0
    property string armed: ""
    property bool closing: false

    FileView { id: palFile; path: root.themeDir + "/palette.json"; blockLoading: true }
    FileView { id: uiFile; path: root.themeDir + "/ui.json"; blockLoading: true }
    Component.onCompleted: {
        try { pal = JSON.parse(palFile.text()); } catch (e) {}
        try { ui = JSON.parse(uiFile.text()); } catch (e) {}
    }

    function a(col, al) {
        return "#" + ("0" + Math.round(al * 255).toString(16)).slice(-2) + String(col || "#888888").slice(1);
    }

    readonly property var actions: [
        { id: "lock",     key: "L", label: "Блокировка",  glyph: "", cmd: "hyprlock", shell: "hyprlock" },
        { id: "logout",   key: "E", label: "Выход",       glyph: "", danger: true, cmd: "hyprctl dispatch 'hl.dsp.exit()'", shell: "hyprctl dispatch exit" },
        { id: "suspend",  key: "S", label: "Сон",         glyph: "", cmd: "hyprlock & sleep 1; systemctl suspend", shell: "systemctl suspend" },
        { id: "reboot",   key: "R", label: "Перезагрузка", glyph: "", danger: true, cmd: "systemctl reboot", shell: "systemctl reboot" },
        { id: "poweroff", key: "P", label: "Выключение",  glyph: "", danger: true, cmd: "systemctl poweroff", shell: "systemctl poweroff" },
    ]

    function activate(i) {
        const act = actions[i];
        if (!act) return;
        current = i;
        if (act.danger && armed !== act.id) {
            armed = act.id;
            disarm.restart();
            return;
        }
        // Run after the overlay is gone so a lock screen or shutdown does not race with it.
        Quickshell.execDetached(["sh", "-c", "sleep 0.25; " + act.cmd]);
        close();
    }

    function close() {
        if (closing) return;
        closing = true;
        outAnim.start();
    }

    Timer { id: disarm; interval: 3500; onTriggered: root.armed = "" }

    IpcHandler {
        target: "power"
        function close(): void { root.close(); }
    }

    PanelWindow {
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "power-menu"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        Item {
            id: scene
            anchors.fill: parent
            opacity: 0
            focus: true
            Component.onCompleted: inAnim.start()
            NumberAnimation { id: inAnim; target: scene; property: "opacity"; to: 1; duration: 180 }
            SequentialAnimation {
                id: outAnim
                NumberAnimation { target: scene; property: "opacity"; to: 0; duration: 180 }
                ScriptAction { script: Qt.quit() }
            }

            Keys.onPressed: e => {
                if (e.key === Qt.Key_Escape) root.close();
                else if (e.key === Qt.Key_Left || e.key === Qt.Key_Up || e.key === Qt.Key_H || e.key === Qt.Key_K || e.key === Qt.Key_Backtab) {
                    root.current = (root.current + root.actions.length - 1) % root.actions.length; root.armed = "";
                } else if (e.key === Qt.Key_Right || e.key === Qt.Key_Down || e.key === Qt.Key_J || e.key === Qt.Key_Tab) {
                    root.current = (root.current + 1) % root.actions.length; root.armed = "";
                } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) {
                    root.activate(root.current);
                } else {
                    const i = root.actions.findIndex(x => x.key === e.text.toUpperCase());
                    if (i >= 0) root.activate(i);
                }
            }

            Rectangle { anchors.fill: parent; color: root.a(root.c.bg, 0.66) }
            MouseArea { anchors.fill: parent; onClicked: root.close() }

            // ---------- cards ----------
            Column {
                visible: !root.terminal
                anchors.centerIn: parent
                spacing: 40

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 14
                    Image {
                        id: headIcon
                        visible: !!root.ui.headerIcon
                        source: root.ui.headerIcon ? "file://" + root.themeDir + "/" + root.ui.headerIcon : ""
                        width: 34; height: 34; sourceSize: Qt.size(68, 68)
                        anchors.verticalCenter: parent.verticalCenter
                        RotationAnimation on rotation { from: 0; to: 360; duration: 12000; loops: Animation.Infinite }
                    }
                    Text {
                        visible: !root.ui.headerIcon
                        text: root.ui.headerGlyph || ""
                        font.family: root.titleFont; font.pixelSize: 30; font.bold: true
                        color: root.c.accent || "white"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: root.ui.upperTitle ? "ДО ВСТРЕЧИ" : "До встречи"
                        font.family: root.titleFont; font.pixelSize: 40; font.italic: !!root.ui.italicTitle
                        color: root.c.fg || "white"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 22
                    Repeater {
                        model: root.actions
                        Rectangle {
                            id: btn
                            required property var modelData
                            required property int index
                            readonly property bool sel: root.current === index
                            readonly property bool armed: root.armed === modelData.id
                            readonly property color tone: modelData.danger ? (root.c.crit || "red") : (root.c.accent || "white")
                            width: 150; height: 170
                            radius: root.r
                            color: armed ? root.a(root.c.crit, 0.25) : sel ? root.a(root.c.bg2, 0.98) : root.a(root.c.bg2, 0.8)
                            border.width: sel ? 2 : 1
                            border.color: sel ? btn.tone : root.a(root.c.muted, 0.35)
                            scale: sel ? 1.07 : 1
                            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
                            layer.enabled: sel
                            layer.effect: MultiEffect {
                                shadowEnabled: true; shadowColor: btn.tone
                                shadowBlur: 0.9; shadowHorizontalOffset: 0; shadowVerticalOffset: 0; blurMax: 32
                            }

                            Column {
                                anchors.centerIn: parent
                                spacing: 12
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: btn.modelData.glyph
                                    font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 44
                                    color: btn.sel ? btn.tone : (root.c.fg || "white")
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: btn.armed ? "Точно?" : btn.modelData.label
                                    font.family: root.titleFont; font.pixelSize: 16; font.italic: !!root.ui.italicTitle
                                    color: btn.armed ? (root.c.crit || "red") : (root.c.fg || "white")
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: btn.armed ? "ещё раз" : btn.modelData.key
                                    font.family: root.bodyFont; font.pixelSize: 12
                                    color: root.c.muted || "grey"
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onEntered: if (root.current !== btn.index) { root.current = btn.index; root.armed = ""; }
                                onClicked: root.activate(btn.index)
                            }
                        }
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "буквы или ← →, Enter — выбрать, Esc — отмена"
                    font.family: root.bodyFont; font.pixelSize: 14
                    color: root.c.muted || "grey"
                }
            }

            // ---------- terminal ----------
            Rectangle {
                visible: root.terminal
                anchors.centerIn: parent
                width: 620; height: termCol.implicitHeight + 48
                color: root.a("#000000", 0.92)
                border.color: root.c.accent || "green"

                Column {
                    id: termCol
                    x: 26; y: 24
                    spacing: 6
                    Text {
                        text: (Quickshell.env("USER") || "user") + "@" + (Quickshell.env("HOSTNAME") || "archlinux") + ":~$ power --menu"
                        font.family: root.bodyFont; font.pixelSize: 17
                        color: root.c.accent || "green"
                    }
                    Item { width: 1; height: 8 }
                    Repeater {
                        model: root.actions
                        Rectangle {
                            id: line
                            required property var modelData
                            required property int index
                            readonly property bool sel: root.current === index
                            readonly property bool armed: root.armed === modelData.id
                            width: 568; height: 32
                            color: sel ? root.a(root.c.accent, 0.18) : "transparent"
                            Text {
                                anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                                text: (line.sel ? "> " : "  ") + "[" + line.modelData.key + "]  "
                                      + (line.armed ? "confirm? press again" : line.modelData.shell)
                                font.family: root.bodyFont; font.pixelSize: 17
                                color: line.armed ? (root.c.crit || "red") : line.sel ? (root.c.accent2 || "lime") : (root.c.accent3 || "green")
                            }
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onEntered: if (root.current !== line.index) { root.current = line.index; root.armed = ""; }
                                onClicked: root.activate(line.index)
                            }
                        }
                    }
                    Item { width: 1; height: 8 }
                    Row {
                        spacing: 0
                        Text {
                            text: "$ "
                            font.family: root.bodyFont; font.pixelSize: 17
                            color: root.c.accent || "green"
                        }
                        Rectangle {
                            width: 10; height: 20
                            color: root.c.accent || "green"
                            SequentialAnimation on opacity {
                                loops: Animation.Infinite
                                NumberAnimation { to: 0; duration: 1; }
                                PauseAnimation { duration: 500 }
                                NumberAnimation { to: 1; duration: 1; }
                                PauseAnimation { duration: 500 }
                            }
                        }
                    }
                }
            }
        }
    }
}
