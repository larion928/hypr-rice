// Cheat sheet, toggled by ~/.local/bin/help-panel (Alt+F1, waybar "?").
// Hotkeys are read from `hyprctl binds -j` ($HELP_BINDS): a bind shows up when keybind.lua gives
// it a description "group | text [| keys label]". The bar, terminal and Code - OSS sections
// below are static because Hyprland does not know about them.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    readonly property string themeDir: Quickshell.env("HELP_THEME_DIR")
    property var pal: ({ colors: {} })
    property var ui: ({})
    property var sections: []
    property bool closing: false
    readonly property var c: pal.colors || {}
    readonly property string titleFont: ui.titleFont === "display" ? (pal.display || "serif") : (pal.font || "monospace")
    readonly property string bodyFont: !ui.bodyFont || ui.bodyFont === "font" ? (pal.font || "monospace")
                                       : ui.bodyFont === "display" ? (pal.display || "serif") : ui.bodyFont
    readonly property int r: Math.min(ui.radius ?? 14, 22)

    FileView { id: palFile; path: root.themeDir + "/palette.json"; blockLoading: true }
    FileView { id: uiFile; path: root.themeDir + "/ui.json"; blockLoading: true }
    FileView { id: bindsFile; path: Quickshell.env("HELP_BINDS"); blockLoading: true }

    Component.onCompleted: {
        try { pal = JSON.parse(palFile.text()); } catch (e) {}
        try { ui = JSON.parse(uiFile.text()); } catch (e) {}
        let binds = [];
        try { binds = JSON.parse(bindsFile.text()); } catch (e) {}
        sections = buildSections(binds);
    }

    function a(col, al) {
        return "#" + ("0" + Math.round(al * 255).toString(16)).slice(-2) + String(col || "#888888").slice(1);
    }

    readonly property var keyNames: ({
        "Return": "Enter", "Print": "PrtSc", "Tab": "Tab", "left": "←", "right": "→", "up": "↑", "down": "↓",
        "mouse:272": "ЛКМ", "mouse:273": "ПКМ", "space": "Space"
    })

    function keyLabel(b) {
        const mods = [];
        if (b.modmask & 64) mods.push("Super");
        if (b.modmask & 4) mods.push("Ctrl");
        if (b.modmask & 8) mods.push("Alt");
        if (b.modmask & 1) mods.push("Shift");
        mods.push(keyNames[b.key] || (b.key.length === 1 ? b.key.toUpperCase() : b.key));
        return mods.join("+");
    }

    readonly property var order: ["Приложения", "Окна", "Воркспейсы", "Скриншоты", "Оформление", "Звук и яркость", "Система"]

    function buildSections(binds) {
        const groups = {};
        for (const b of binds) {
            if (!b.has_description || !b.description) continue;
            const parts = b.description.split("|").map(s => s.trim());
            if (parts.length < 2) continue;
            (groups[parts[0]] = groups[parts[0]] || []).push({ keys: parts[2] || keyLabel(b), text: parts[1] });
        }
        const out = order.filter(g => groups[g]).map(g => ({ title: g, rows: groups[g] }));
        for (const g in groups)
            if (order.indexOf(g) === -1) out.push({ title: g, rows: groups[g] });

        out.push({ title: "Панель сверху", rows: [
            { keys: "\u{f03d8}", text: "Выбор темы" },
            { keys: "", text: "Эта справка" },
            { keys: "", text: "Уведомления (ПКМ — старый TUI)" },
            { keys: "", text: "Блокировка, сон, выход, выключение" },
            { keys: "us / ru", text: "Раскладка — Super+Space" },
            { keys: "✳ %", text: "Лимиты Claude (тема claude), клик — claude.ai" },
        ]});
        out.push({ title: "В терминале", rows: [
            { keys: "changetheme <тема>", text: "Сменить тему без окна выбора" },
            { keys: "themegen.py build", text: "Пересобрать темы Code, drift, neoHtop, Telegram" },
            { keys: "shot / shot full", text: "Скриншот из скрипта" },
            { keys: "mouse-sens", text: "Чувствительность мыши" },
            { keys: "portal-restart", text: "Перезапуск трансляции экрана" },
            { keys: "drift", text: "Скринсейвер в терминале" },
        ]});
        out.push({ title: "Code - OSS (git)", rows: [
            { keys: "Ctrl+Shift+G", text: "Изменения и коммит" },
            { keys: "Ctrl+Alt+G", text: "Граф веток" },
            { keys: "Ctrl+Alt+B / N", text: "Переключить / создать ветку" },
            { keys: "Ctrl+Alt+M", text: "Слить ветку" },
            { keys: "Ctrl+Alt+C", text: "Коммит" },
            { keys: "Ctrl+Alt+P", text: "Забрать изменения (pull)" },
        ]});
        return out;
    }

    function close() {
        if (closing) return;
        closing = true;
        outAnim.start();
    }

    IpcHandler {
        target: "help"
        function close(): void { root.close(); }
    }

    PanelWindow {
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "help-panel"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        Item {
            id: scene
            anchors.fill: parent
            opacity: 0
            focus: true
            Keys.onPressed: e => { if (e.key === Qt.Key_Escape || e.key === Qt.Key_F1 || e.key === Qt.Key_Q) root.close(); }
            Component.onCompleted: inAnim.start()
            NumberAnimation { id: inAnim; target: scene; property: "opacity"; to: 1; duration: 200 }
            SequentialAnimation {
                id: outAnim
                NumberAnimation { target: scene; property: "opacity"; to: 0; duration: 160 }
                ScriptAction { script: Qt.quit() }
            }

            Rectangle { anchors.fill: parent; color: root.a(root.c.bg, 0.7) }
            MouseArea { anchors.fill: parent; onClicked: root.close() }

            Rectangle {
                id: sheet
                anchors.centerIn: parent
                width: Math.min(parent.width - 80, 1560)
                height: Math.min(parent.height - 80, 960)
                radius: root.r
                color: root.a(root.c.bg, 0.95)
                border.width: root.ui.border ?? 1
                border.color: root.a(root.c.accent, 0.5)
                MouseArea { anchors.fill: parent }   // clicks inside do not close

                Row {
                    id: header
                    x: 32; y: 26
                    spacing: 14
                    Image {
                        visible: !!root.ui.headerIcon
                        source: root.ui.headerIcon ? "file://" + root.themeDir + "/" + root.ui.headerIcon : ""
                        width: 30; height: 30; sourceSize: Qt.size(60, 60)
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        visible: !root.ui.headerIcon
                        text: root.ui.headerGlyph || "?"
                        font.family: root.titleFont; font.pixelSize: 26; font.bold: true
                        color: root.c.accent || "white"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: root.ui.upperTitle ? "КАК ТУТ ВСЁ УСТРОЕНО" : "Как тут всё устроено"
                        font.family: root.titleFont; font.pixelSize: 32; font.italic: !!root.ui.italicTitle
                        color: root.c.fg || "white"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                Text {
                    anchors { right: parent.right; rightMargin: 32; verticalCenter: header.verticalCenter }
                    text: "Alt — главная клавиша · Esc — закрыть"
                    font.family: root.bodyFont; font.pixelSize: 14
                    color: root.c.muted || "grey"
                }

                Flickable {
                    anchors { left: parent.left; right: parent.right; top: header.bottom; bottom: parent.bottom; margins: 24; topMargin: 22 }
                    contentHeight: flow.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Flow {
                        id: flow
                        width: parent.width
                        spacing: 18

                        Repeater {
                            model: root.sections
                            Rectangle {
                                id: card
                                required property var modelData
                                required property int index
                                width: (flow.width - flow.spacing * 2) / 3
                                height: col.implicitHeight + 32
                                radius: Math.min(root.r, 16)
                                color: root.a(root.c.bg2, 0.85)
                                border.color: root.a(root.c.muted, 0.25)
                                opacity: 0
                                Component.onCompleted: appear.start()
                                SequentialAnimation {
                                    id: appear
                                    PauseAnimation { duration: card.index * 40 }
                                    NumberAnimation { target: card; property: "opacity"; to: 1; duration: 220 }
                                }

                                Column {
                                    id: col
                                    x: 18; y: 16
                                    width: card.width - 36
                                    spacing: 9
                                    Text {
                                        text: root.ui.upperTitle ? card.modelData.title.toUpperCase() : card.modelData.title
                                        font.family: root.titleFont; font.pixelSize: 17; font.bold: true; font.italic: !!root.ui.italicTitle
                                        color: root.c.accent2 || root.c.accent || "white"
                                    }
                                    Repeater {
                                        model: card.modelData.rows
                                        Item {
                                            required property var modelData
                                            width: col.width
                                            height: Math.max(chip.height, label.implicitHeight)
                                            Rectangle {
                                                id: chip
                                                width: Math.min(chipText.implicitWidth + 16, col.width * 0.48)
                                                height: 26
                                                radius: root.r > 4 ? 7 : 0
                                                color: root.a(root.c.accent, 0.16)
                                                border.color: root.a(root.c.accent, 0.45)
                                                Text {
                                                    id: chipText
                                                    anchors.centerIn: parent
                                                    width: Math.min(implicitWidth, col.width * 0.48 - 16)
                                                    elide: Text.ElideRight
                                                    text: parent.parent.modelData.keys
                                                    font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 13
                                                    color: root.c.accent || "white"
                                                }
                                            }
                                            Text {
                                                id: label
                                                anchors { left: parent.left; leftMargin: col.width * 0.5; right: parent.right; verticalCenter: chip.verticalCenter }
                                                text: parent.modelData.text
                                                wrapMode: Text.Wrap
                                                font.family: root.bodyFont; font.pixelSize: 14
                                                color: root.c.fg || "white"
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
