// Notification history (waybar bell, launcher): histui's notifications grouped by day, searchable. History,
// deletion and Do Not Disturb are histui's (Histui.qml); the panel shows them and asks for changes.
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.common
import "../common/listmodel.js" as ListModelSync

OverlayPanel {
    id: menu

    property string query: ""
    property bool confirmClear: false
    readonly property alias items: store.items
    readonly property alias unread: store.unread

    readonly property var months: ["января", "февраля", "марта", "апреля", "мая", "июня", "июля",
                                   "августа", "сентября", "октября", "ноября", "декабря"]

    // Notification bodies may carry basic markup; shown as plain text. &amp; goes last, so "&amp;lt;" stays the
    // text "&lt;" instead of turning into "<".
    function plain(text) {
        return String(text || "").replace(/<[^>]*>/g, "").replace(/&lt;/g, "<").replace(/&gt;/g, ">")
            .replace(/&quot;/g, "\"").replace(/&amp;/g, "&").replace(/[‎‏‪-‮⁦-⁩]/g, "").trim();
    }

    function dayLabel(timestamp) {
        const date = new Date(timestamp * 1000);
        const now = new Date();
        const today = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime() / 1000;
        if (timestamp >= today) {
            return "Сегодня";
        }
        if (timestamp >= today - 86400) {
            return "Вчера";
        }
        return date.getDate() + " " + months[date.getMonth()]
               + (date.getFullYear() !== now.getFullYear() ? " " + date.getFullYear() : "");
    }

    // Flat list for the ListView: day headers between the notifications. Every row has the same roles (ListModel
    // wants that); `key` names the row across refreshes.
    readonly property var rows: {
        const q = query.trim().toLowerCase();
        const found = items.filter(n => !q || [n.app_name, n.summary, n.body].join(" ").toLowerCase().indexOf(q) !== -1)
                           .sort((x, y) => y.timestamp - x.timestamp);
        const out = [];
        let last = "";
        for (const n of found) {
            const day = dayLabel(n.timestamp);
            if (day !== last) {
                out.push({ key: "day:" + day, kind: "day", label: day, nid: "" });
                last = day;
            }
            out.push({ key: "n:" + n.histui_id, kind: "n", label: "", nid: n.histui_id });
        }
        return out;
    }

    // `rows` updated in place, so a refresh does not scroll the list to the top, collapse an open card or replay
    // the fade-in.
    ListModel { id: rowModel }
    onRowsChanged: ListModelSync.sync(rowModel, rows, "key")

    function clearAll() {
        if (!confirmClear) {
            confirmClear = true;
            confirmTimer.restart();
            return;
        }
        confirmClear = false;
        store.clearAll();
    }

    function copy(notification) {
        const text = [plain(notification.summary), plain(notification.body)].filter(s => s).join("\n");
        Quickshell.execDetached(["sh", "-c", 'printf "%s" "$1" | wl-copy', "sh", text]);
    }

    namespace: "notif-panel"
    fullscreen: false
    layer: WlrLayer.Top
    keyboard: WlrKeyboardFocus.OnDemand
    anchors { top: true; right: true; bottom: true }
    implicitWidth: 440
    margins { top: 6; right: 10; bottom: 10 }
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0
    fadeInMs: Theme.slideMs * 0.7
    fadeOutMs: Theme.slideMs * 0.8

    // Typing goes to the search.
    onKeyPressed: event => {
        if (event.text.trim()) {
            search.type(event.text);
        }
    }

    Histui { id: store }
    Timer { id: confirmTimer; interval: 3000; onTriggered: menu.confirmClear = false }

    Rectangle {
        id: sheet
        width: parent.width
        height: parent.height
        x: menu.shown ? 0 : width
        Behavior on x { NumberAnimation { duration: menu.shown ? Theme.slideMs : Theme.slideMs * 0.8; easing.type: menu.shown ? Easing.OutCubic : Easing.InCubic } }
        radius: Theme.ui.radius ?? 14
        color: Theme.alpha(Theme.bg, 0.94)
        border.width: Theme.border
        border.color: Theme.alpha(Theme.accent, 0.55)
        clip: true

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
                    HeaderTitle {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Theme.ui.title || "Уведомления"
                        size: 21
                        markSize: 21
                        spacing: 10
                    }
                    Rectangle {
                        visible: menu.unread > 0
                        anchors.verticalCenter: parent.verticalCenter
                        width: unreadText.implicitWidth + 14; height: 20; radius: 10
                        color: Theme.alpha(Theme.accent, 0.25)
                        Text {
                            id: unreadText
                            anchors.centerIn: parent
                            text: menu.unread
                            font.family: Theme.bodyFont; font.pixelSize: 12; font.bold: true
                            color: Theme.accent
                        }
                    }
                }

                Row {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    spacing: 4
                    IconButton { glyph: store.dnd ? "\uf1f6" : "\uf0f3"; active: store.dnd; onClicked: store.toggleDnd() }
                    IconButton { glyph: "\uf00c"; onClicked: store.readAll() }
                    IconButton { glyph: "\uf00d"; onClicked: menu.close() }
                }
            }

            Field {
                id: search
                width: parent.width
                height: 38
                placeholder: "\uf002  Поиск по уведомлениям"
                onTextChanged: menu.query = text
                onEscaped: {
                    if (text) {
                        text = "";
                    } else {
                        menu.close();
                    }
                }
            }
        }

        ListView {
            id: list
            anchors { left: parent.left; right: parent.right; top: head.bottom; bottom: foot.top; margins: 16; topMargin: 12 }
            clip: true
            spacing: 8
            model: rowModel
            boundsBehavior: Flickable.StopAtBounds

            delegate: Item {
                id: row
                required property string kind
                required property string label
                required property string nid
                readonly property var notification: store.byId[nid] || ({})
                width: list.width
                height: kind === "day" ? dayText.implicitHeight + 8 : card.height

                SectionTitle {
                    id: dayText
                    visible: row.kind === "day"
                    y: 4
                    text: row.label
                    font.pixelSize: 14
                }
                NotificationCard {
                    id: card
                    visible: row.kind !== "day"
                    width: parent.width
                    notification: row.notification
                    summary: menu.plain(row.notification.summary)
                    body: menu.plain(row.notification.body)
                    onOpened: if (!read) store.markRead(row.nid)
                    onCopyRequested: menu.copy(row.notification)
                    onRemoveRequested: store.remove(row.nid)
                }
            }

            Column {
                anchors.centerIn: parent
                visible: list.count === 0
                spacing: 8
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Theme.ui.headerGlyph || "\uf0f3"
                    font.family: Theme.titleFont; font.pixelSize: Theme.titleSize(40)
                    color: Theme.alpha(Theme.muted, 0.6)
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: menu.query ? "Ничего не найдено" : "Уведомлений нет"
                    font.family: Theme.titleFont; font.pixelSize: Theme.titleSize(16); font.italic: Theme.italicTitle
                    color: Theme.muted
                }
            }
        }

        Item {
            id: foot
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 16 }
            height: 36

            Text {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                text: menu.items.length + " в истории"
                font.family: Theme.bodyFont; font.pixelSize: 12
                color: Theme.muted
            }
            Chip {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: menu.confirmClear ? "Точно? Нажми ещё раз" : "Очистить всё"
                danger: true
                primary: menu.confirmClear
                onClicked: menu.clearAll()
            }
        }
    }
}
