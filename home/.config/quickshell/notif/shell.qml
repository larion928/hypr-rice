// Notification history panel, toggled by ~/.local/bin/notif-panel (waybar bell).
// Data and actions go through the histui CLI; the look comes from the current theme's
// palette.json plus ui.json (title, glyph, radii, fonts, slide speed).
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import "common"
import "common/color.js" as Color

ShellRoot {
    id: root

    Theme { id: theme }

    property var items: []
    property string query: ""
    property bool dnd: false
    property bool closing: false
    property bool confirmClear: false

    Component.onCompleted: {
        refresh();
    }

    // Notification bodies may carry basic markup; show them as plain text.
    function plain(s) {
        return String(s || "").replace(/<[^>]*>/g, "").replace(/&amp;/g, "&").replace(/&lt;/g, "<")
            .replace(/&gt;/g, ">").replace(/&quot;/g, "\"").replace(/[\u200e\u200f\u202a-\u202e\u2066-\u2069]/g, "").trim();
    }

    readonly property var months: ["января", "февраля", "марта", "апреля", "мая", "июня", "июля",
                                   "августа", "сентября", "октября", "ноября", "декабря"]

    function dayLabel(ts) {
        const d = new Date(ts * 1000), now = new Date();
        const start = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime() / 1000;
        if (ts >= start) return "Сегодня";
        if (ts >= start - 86400) return "Вчера";
        return d.getDate() + " " + months[d.getMonth()] + (d.getFullYear() !== now.getFullYear() ? " " + d.getFullYear() : "");
    }

    function timeLabel(ts) {
        const d = new Date(ts * 1000);
        return ("0" + d.getHours()).slice(-2) + ":" + ("0" + d.getMinutes()).slice(-2);
    }

    // Flat list for the ListView: day headers interleaved with notifications.
    readonly property var rows: {
        const q = query.trim().toLowerCase();
        const list = items.filter(n => !q || [n.app_name, n.summary, n.body].join(" ").toLowerCase().indexOf(q) !== -1)
                          .sort((x, y) => y.timestamp - x.timestamp);
        const out = [];
        let last = "";
        for (const n of list) {
            const day = dayLabel(n.timestamp);
            if (day !== last) {
                out.push({ kind: "day", label: day });
                last = day;
            }
            out.push({ kind: "n", n: n });
        }
        return out;
    }
    readonly property int unread: items.filter(n => !n.histui_dismissed_at).length

    Process {
        id: listProc
        command: ["histui", "get", "--format", "json", "--limit", "300"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.items = JSON.parse(text) || []; } catch (e) { console.warn("histui:", e); }
            }
        }
    }
    Process {
        id: dndProc
        command: ["histui", "dnd", "status"]
        stdout: StdioCollector { onStreamFinished: root.dnd = /enabled/.test(text) && !/disabled/.test(text) }
    }
    // Actions run one at a time; the list is refreshed after each.
    Process {
        id: actProc
        onExited: root.refresh()
    }

    function refresh() {
        if (!listProc.running) listProc.running = true;
        if (!dndProc.running) dndProc.running = true;
    }

    function act(cmd) {
        if (actProc.running) return;
        actProc.command = cmd;
        actProc.running = true;
    }

    function remove(id) {
        items = items.filter(n => n.histui_id !== id);
        act(["histui", "set", id, "--delete"]);
    }

    function markRead(id) {
        act(["histui", "set", id, "--dismiss"]);
    }

    function readAll() {
        act(["sh", "-c", "histui get --format ids | histui set --stdin --dismiss"]);
    }

    function clearAll() {
        if (!confirmClear) {
            confirmClear = true;
            confirmTimer.restart();
            return;
        }
        confirmClear = false;
        items = [];
        act(["histui", "prune", "--keep", "0"]);
    }

    function copy(text) {
        Quickshell.execDetached(["sh", "-c", 'printf "%s" "$1" | wl-copy', "sh", text]);
    }

    function close() {
        if (closing) return;
        closing = true;
        slideOut.start();
    }

    Timer { id: confirmTimer; interval: 3000; onTriggered: root.confirmClear = false }
    Timer { interval: 4000; running: !root.closing; repeat: true; onTriggered: root.refresh() }

    IpcHandler {
        target: "panel"
        function close(): void { root.close(); }
    }

    PanelWindow {
        id: panel
        anchors { top: true; right: true; bottom: true }
        implicitWidth: 440
        margins { top: 6; right: 10; bottom: 10 }
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: 0
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "notif-panel"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

        // Clicking anywhere outside the panel closes it.
        HyprlandFocusGrab {
            active: !root.closing
            windows: [panel]
            onCleared: root.close()
        }

        Rectangle {
            id: sheet
            width: parent.width
            height: parent.height
            x: width
            opacity: 0
            radius: theme.ui.radius ?? 14
            color: Color.withAlpha(theme.c.bg, 0.94)
            border.width: theme.ui.border ?? 1
            border.color: Color.withAlpha(theme.c.accent, 0.55)
            clip: true
            focus: true
            Keys.onEscapePressed: root.close()

            Component.onCompleted: slideIn.start()

            ParallelAnimation {
                id: slideIn
                NumberAnimation { target: sheet; property: "x"; from: sheet.width; to: 0; duration: theme.ui.slideMs ?? 260; easing.type: Easing.OutCubic }
                NumberAnimation { target: sheet; property: "opacity"; from: 0; to: 1; duration: (theme.ui.slideMs ?? 260) * 0.7 }
            }
            SequentialAnimation {
                id: slideOut
                ParallelAnimation {
                    NumberAnimation { target: sheet; property: "x"; to: sheet.width; duration: (theme.ui.slideMs ?? 260) * 0.8; easing.type: Easing.InCubic }
                    NumberAnimation { target: sheet; property: "opacity"; to: 0; duration: (theme.ui.slideMs ?? 260) * 0.8 }
                }
                ScriptAction { script: Qt.quit() }
            }

            Column {
                id: head
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
                spacing: 12

                Item {
                    width: parent.width
                    height: 32

                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 10
                        Image {
                            visible: !!theme.ui.headerIcon
                            source: theme.ui.headerIcon ? "file://" + theme.dir + "/" + theme.ui.headerIcon : ""
                            width: 22; height: 22; sourceSize: Qt.size(44, 44)
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            visible: !theme.ui.headerIcon
                            text: theme.ui.headerGlyph || "•"
                            font.family: theme.titleFont; font.pixelSize: 20; font.bold: true
                            color: theme.c.accent || "white"
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: theme.ui.upperTitle ? String(theme.ui.title || "").toUpperCase() : (theme.ui.title || "Уведомления")
                            font.family: theme.titleFont; font.pixelSize: 21; font.italic: !!theme.ui.italicTitle
                            color: theme.c.fg || "white"
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Rectangle {
                            visible: root.unread > 0
                            anchors.verticalCenter: parent.verticalCenter
                            width: unreadText.implicitWidth + 14; height: 20; radius: 10
                            color: Color.withAlpha(theme.c.accent, 0.25)
                            Text {
                                id: unreadText
                                anchors.centerIn: parent
                                text: root.unread
                                font.family: theme.bodyFont; font.pixelSize: 12; font.bold: true
                                color: theme.c.accent || "white"
                            }
                        }
                    }

                    Row {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        spacing: 4
                        IconButton {
                            glyph: root.dnd ? "" : ""
                            tip: root.dnd ? "«Не беспокоить» включено" : "Не беспокоить"
                            active: root.dnd
                            onClicked: { root.dnd = !root.dnd; root.act(["histui", "dnd", "toggle"]); }
                        }
                        IconButton { glyph: ""; tip: "Отметить всё прочитанным"; onClicked: root.readAll() }
                        IconButton { glyph: ""; tip: "Закрыть (Esc)"; onClicked: root.close() }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 38
                    radius: Math.min(theme.ui.cardRadius ?? 10, 19)
                    color: Color.withAlpha(theme.c.bg2, 0.9)
                    border.color: search.activeFocus ? (theme.c.accent || "white") : Color.withAlpha(theme.c.muted, 0.35)
                    Text {
                        anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                        visible: !search.text
                        text: "  Поиск по уведомлениям"
                        font.family: theme.bodyFont; font.pixelSize: 14
                        color: theme.c.muted || "grey"
                    }
                    TextInput {
                        id: search
                        anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                        verticalAlignment: TextInput.AlignVCenter
                        font.family: theme.bodyFont; font.pixelSize: 14
                        color: theme.c.fg || "white"
                        selectionColor: Color.withAlpha(theme.c.accent, 0.4)
                        clip: true
                        onTextChanged: root.query = text
                        Keys.onEscapePressed: text ? text = "" : root.close()
                    }
                }
            }

            ListView {
                id: list
                anchors { left: parent.left; right: parent.right; top: head.bottom; bottom: foot.top; margins: 16; topMargin: 12 }
                clip: true
                spacing: 8
                model: root.rows
                boundsBehavior: Flickable.StopAtBounds

                delegate: Item {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool isDay: modelData.kind === "day"
                    readonly property var n: modelData.n || ({})
                    width: list.width
                    height: isDay ? dayText.implicitHeight + 8 : card.height

                    Text {
                        id: dayText
                        visible: row.isDay
                        y: 4
                        text: row.modelData.label || ""
                        font.family: theme.titleFont; font.pixelSize: 14; font.bold: true; font.italic: !!theme.ui.italicTitle
                        color: theme.c.accent2 || theme.c.accent || "white"
                    }

                    Rectangle {
                        id: card
                        visible: !row.isDay
                        width: parent.width
                        height: visible ? content.implicitHeight + 24 : 0
                        radius: theme.ui.cardRadius ?? 10
                        readonly property bool read: !!row.n.histui_dismissed_at
                        readonly property bool critical: row.n.urgency === 2
                        property bool expanded: false
                        color: hover.hovered ? Color.withAlpha(theme.c.bg2, 1) : Color.withAlpha(theme.c.bg2, read ? 0.55 : 0.85)
                        border.width: 1
                        border.color: critical ? Color.withAlpha(theme.c.crit, 0.8) : Color.withAlpha(theme.c.accent, read ? 0.12 : 0.35)
                        opacity: 0

                        Component.onCompleted: if (visible) appear.start()
                        NumberAnimation on opacity { id: appear; running: false; to: 1; duration: 220; easing.type: Easing.OutQuad }

                        // Unread marker on the left edge.
                        Rectangle {
                            visible: !card.read
                            x: 0; y: 10
                            width: 3; height: card.height - 20; radius: 2
                            color: card.critical ? (theme.c.crit || "red") : (theme.c.accent || "white")
                        }

                        HoverHandler { id: hover }
                        TapHandler {
                            onTapped: {
                                card.expanded = !card.expanded;
                                if (!card.read) root.markRead(row.n.histui_id);
                            }
                        }

                        Column {
                            id: content
                            x: 14; y: 12
                            width: card.width - 28
                            spacing: 4

                            Item {
                                width: parent.width
                                height: 20
                                Row {
                                    spacing: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    IconImage {
                                        id: appIcon
                                        implicitSize: 18
                                        visible: source != ""
                                        readonly property string name: (row.n.extensions && row.n.extensions.desktop_entry)
                                                                       || String(row.n.app_name || "").toLowerCase()
                                        // true: return "" instead of a broken icon when the theme lacks it.
                                        source: name ? Quickshell.iconPath(name, true) : ""
                                    }
                                    Text {
                                        visible: !appIcon.visible
                                        text: "\uf0f3"
                                        font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 14
                                        color: theme.c.accent || "white"
                                    }
                                    Text {
                                        text: row.n.app_name || ""
                                        font.family: theme.bodyFont; font.pixelSize: 12
                                        color: theme.c.muted || "grey"
                                    }
                                }
                                Row {
                                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                    spacing: 2
                                    visible: hover.hovered
                                    IconButton { small: true; glyph: ""; tip: "Копировать текст"; onClicked: root.copy([root.plain(row.n.summary), root.plain(row.n.body)].filter(s => s).join("\n")) }
                                    IconButton { small: true; glyph: ""; tip: "Удалить"; danger: true; onClicked: root.remove(row.n.histui_id) }
                                }
                                Text {
                                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                    visible: !hover.hovered
                                    text: root.timeLabel(row.n.timestamp || 0)
                                    font.family: theme.bodyFont; font.pixelSize: 12
                                    color: theme.c.muted || "grey"
                                }
                            }
                            Text {
                                width: parent.width
                                text: root.plain(row.n.summary)
                                visible: text.length > 0
                                textFormat: Text.PlainText
                                wrapMode: Text.Wrap
                                maximumLineCount: card.expanded ? 6 : 2
                                elide: Text.ElideRight
                                font.family: theme.titleFont; font.pixelSize: 15; font.bold: true
                                color: card.critical ? (theme.c.crit || "white") : (theme.c.fg || "white")
                            }
                            Text {
                                width: parent.width
                                text: root.plain(row.n.body)
                                visible: text.length > 0
                                textFormat: Text.PlainText
                                wrapMode: Text.Wrap
                                maximumLineCount: card.expanded ? 40 : 3
                                elide: Text.ElideRight
                                font.family: theme.bodyFont; font.pixelSize: 13
                                color: Color.withAlpha(theme.c.fg, card.read ? 0.6 : 0.85)
                            }
                        }
                    }
                }

                Column {
                    anchors.centerIn: parent
                    visible: list.count === 0
                    spacing: 8
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: theme.ui.headerGlyph || ""
                        font.family: theme.titleFont; font.pixelSize: 40
                        color: Color.withAlpha(theme.c.muted, 0.6)
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.query ? "Ничего не найдено" : "Уведомлений нет"
                        font.family: theme.titleFont; font.pixelSize: 16; font.italic: !!theme.ui.italicTitle
                        color: theme.c.muted || "grey"
                    }
                }
            }

            Item {
                id: foot
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 16 }
                height: 36

                Text {
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    text: root.items.length + " в истории"
                    font.family: theme.bodyFont; font.pixelSize: 12
                    color: theme.c.muted || "grey"
                }

                Rectangle {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    width: clearText.implicitWidth + 24; height: 32
                    radius: Math.min(theme.ui.cardRadius ?? 10, 16)
                    color: root.confirmClear ? Color.withAlpha(theme.c.crit, 0.85) : clearHover.hovered ? Color.withAlpha(theme.c.crit, 0.25) : "transparent"
                    border.color: Color.withAlpha(theme.c.crit, 0.6)
                    HoverHandler { id: clearHover }
                    TapHandler { onTapped: root.clearAll() }
                    Text {
                        id: clearText
                        anchors.centerIn: parent
                        text: root.confirmClear ? "Точно? Нажми ещё раз" : "Очистить всё"
                        font.family: theme.bodyFont; font.pixelSize: 13
                        color: root.confirmClear ? (theme.c.bg || "black") : (theme.c.crit || "red")
                    }
                }
            }
        }
    }

    component IconButton: Rectangle {
        id: btn
        property string glyph
        property string tip
        property bool active: false
        property bool danger: false
        property bool small: false
        signal clicked()
        width: small ? 24 : 32; height: width
        radius: Math.min(theme.ui.cardRadius ?? 8, width / 2)
        color: active ? Color.withAlpha(theme.c.accent, 0.3) : btnHover.hovered ? Color.withAlpha(danger ? theme.c.crit : theme.c.accent, 0.2) : "transparent"
        HoverHandler { id: btnHover }
        TapHandler { onTapped: btn.clicked() }
        Text {
            anchors.centerIn: parent
            text: btn.glyph
            font.family: "JetBrainsMono Nerd Font"; font.pixelSize: btn.small ? 12 : 15
            color: btn.danger && btnHover.hovered ? (theme.c.crit || "red") : btn.active ? (theme.c.accent || "white") : (theme.c.fg || "white")
        }
    }
}
