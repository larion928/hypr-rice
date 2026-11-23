// Power menu (Alt+M, waybar power button): lock, logout, suspend, reboot, poweroff. Logout, reboot and
// poweroff need a second press. ui.json "powerStyle": "cards" (big themed buttons) or "terminal" (a shell-like
// list, hacker).
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.common
import "../common/keys.js" as KeyName

OverlayPanel {
    id: menu

    readonly property bool terminal: Theme.ui.powerStyle === "terminal"
    property int current: 0
    property string armed: ""

    readonly property var actions: [
        { id: "lock",     key: "L", label: "Блокировка",  glyph: "\uf023", cmd: "rice-lock", shell: "rice-lock" },
        { id: "logout",   key: "E", label: "Выход",       glyph: "\uf2f5", danger: true, cmd: "hyprctl dispatch 'hl.dsp.exit()'", shell: "hyprctl dispatch exit" },
        { id: "suspend",  key: "S", label: "Сон",         glyph: "\uf186", cmd: "rice-lock & sleep 1; systemctl suspend", shell: "systemctl suspend" },
        { id: "reboot",   key: "R", label: "Перезагрузка", glyph: "\uf2f9", danger: true, cmd: "systemctl reboot", shell: "systemctl reboot" },
        { id: "poweroff", key: "P", label: "Выключение",  glyph: "\uf011", danger: true, cmd: "systemctl poweroff", shell: "systemctl poweroff" },
    ]

    function select(index) {
        current = (index + actions.length) % actions.length;
        armed = "";
    }

    function activate(index) {
        const action = actions[index];
        current = index;
        if (action.danger && armed !== action.id) {
            armed = action.id;
            disarm.restart();
            return;
        }
        // Run after the overlay is gone so a lock screen or shutdown does not race with it.
        Quickshell.execDetached(["sh", "-c", "sleep 0.25; " + action.cmd]);
        close();
    }

    namespace: "power-menu"
    dim: 0.66

    onKeyPressed: event => {
        const byLetter = actions.findIndex(action => action.key === KeyName.of(event));
        const step = KeyName.step(event, 1);
        if (byLetter >= 0) {
            activate(byLetter);
        } else if (step !== 0) {
            select(current + step);
        } else if (KeyName.isEnter(event) || event.key === Qt.Key_Space) {
            activate(current);
        }
    }

    Timer { id: disarm; interval: 3500; onTriggered: menu.armed = "" }

    // For the "terminal" style prompt. $HOSTNAME is a shell variable, not in the environment, and
    // /etc/hostname may be missing; the kernel always knows.
    FileView { id: hostnameFile; path: "/proc/sys/kernel/hostname"; blockLoading: true }

    // ---------- cards ----------
    Column {
        visible: !menu.terminal
        anchors.centerIn: parent
        spacing: 40

        HeaderTitle {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "До встречи"
            size: 40
            markSize: 32
            spinning: true
            fallbackGlyph: "\uf011"
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 22
            Repeater {
                model: menu.actions
                Rectangle {
                    id: card
                    required property var modelData
                    required property int index
                    readonly property bool selected: menu.current === index
                    readonly property bool armed: menu.armed === modelData.id
                    readonly property string tone: modelData.danger ? Theme.crit : Theme.accent
                    width: 150; height: 170
                    radius: Theme.radius(26)
                    color: armed ? Theme.alpha(Theme.crit, 0.25) : Theme.alpha(Theme.bg2, selected ? 0.98 : 0.8)
                    border.width: selected ? 2 : 1
                    border.color: selected ? tone : Theme.alpha(Theme.muted, 0.35)
                    scale: selected ? 1.07 : 1
                    Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
                    layer.enabled: selected
                    layer.effect: MultiEffect {
                        shadowEnabled: true; shadowColor: card.tone
                        shadowBlur: 0.9; shadowHorizontalOffset: 0; shadowVerticalOffset: 0; blurMax: 32
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: 12
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: card.modelData.glyph
                            font.family: Theme.glyphFont; font.pixelSize: 44
                            color: card.selected ? card.tone : Theme.fg
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: card.armed ? "Точно?" : card.modelData.label
                            font.family: Theme.titleFont; font.pixelSize: 16; font.italic: Theme.italicTitle
                            color: card.armed ? Theme.crit : Theme.fg
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: card.armed ? "ещё раз" : card.modelData.key
                            font.family: Theme.bodyFont; font.pixelSize: 12
                            color: Theme.muted
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: if (menu.current !== card.index) menu.select(card.index)
                        onClicked: menu.activate(card.index)
                    }
                }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "буквы или ← →, Enter выбрать, Esc отмена"
            font.family: Theme.bodyFont; font.pixelSize: 14
            color: Theme.muted
        }
    }

    // ---------- terminal ----------
    Rectangle {
        visible: menu.terminal
        anchors.centerIn: parent
        width: 620; height: terminalLines.implicitHeight + 48
        color: Theme.alpha("#000000", 0.92)
        border.color: Theme.accent

        Column {
            id: terminalLines
            x: 26; y: 24
            spacing: 6
            Text {
                text: (Quickshell.env("USER") || "user") + "@" + (hostnameFile.text().trim() || "localhost") + ":~$ power --menu"
                font.family: Theme.bodyFont; font.pixelSize: 17
                color: Theme.accent
            }
            Item { width: 1; height: 8 }
            Repeater {
                model: menu.actions
                Rectangle {
                    id: line
                    required property var modelData
                    required property int index
                    readonly property bool selected: menu.current === index
                    readonly property bool armed: menu.armed === modelData.id
                    width: 568; height: 32
                    color: selected ? Theme.alpha(Theme.accent, 0.18) : "transparent"
                    Text {
                        anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                        text: (line.selected ? "> " : "  ") + "[" + line.modelData.key + "]  "
                              + (line.armed ? "confirm? press again" : line.modelData.shell)
                        font.family: Theme.bodyFont; font.pixelSize: 17
                        color: line.armed ? Theme.crit : line.selected ? Theme.accent2 : Theme.accent3
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: if (menu.current !== line.index) menu.select(line.index)
                        onClicked: menu.activate(line.index)
                    }
                }
            }
            Item { width: 1; height: 8 }
            Row {
                Text {
                    text: "$ "
                    font.family: Theme.bodyFont; font.pixelSize: 17
                    color: Theme.accent
                }
                Rectangle {
                    width: 10; height: 20
                    color: Theme.accent
                    SequentialAnimation on opacity {
                        loops: Animation.Infinite
                        NumberAnimation { to: 0; duration: 1 }
                        PauseAnimation { duration: 500 }
                        NumberAnimation { to: 1; duration: 1 }
                        PauseAnimation { duration: 500 }
                    }
                }
            }
        }
    }
}
