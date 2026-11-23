// The clipboard history (Alt+Shift+V): what was copied lately, newest first, filtered by what is typed. Enter
// copies the chosen entry back and closes, Delete removes it, «Очистить» wipes all after a second press.
import QtQuick
import Quickshell
import qs.common
import "../common/keys.js" as KeyName

OverlayPanel {
    id: menu

    property string query: ""
    property int current: 0
    property bool clearArmed: false

    readonly property alias history: history
    readonly property var results: history.entries.filter(
        entry => entry.label.toLowerCase().includes(query.toLowerCase()))
    readonly property string emptyText: !history.on ? "История выключена: Alt+F2 → Функции → \"История буфера обмена\""
                                      : query ? "Ничего не нашлось" : "История пуста"

    onResultsChanged: select(current)

    function select(index) {
        current = Math.max(0, Math.min(index, results.length - 1));
    }

    function activate(index) {
        const entry = results[index];
        if (entry) {
            history.copy(entry.id);
            close();
        }
    }

    function removeCurrent() {
        const entry = results[current];
        if (entry) {
            history.remove(entry.id);
        }
    }

    function clear() {
        if (clearArmed) {
            clearArmed = false;
            history.wipe();
        } else {
            clearArmed = true;
        }
    }

    ClipboardHistory { id: history }

    namespace: "clipboard"
    fullscreen: false
    implicitWidth: 680
    implicitHeight: 560
    fadeInMs: Theme.slideMs * 0.6
    fadeOutMs: 140

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius(22)
        color: Theme.alpha(Theme.bg, 0.93)
        border.width: Theme.border
        border.color: Theme.alpha(Theme.accent, 0.55)
        scale: menu.shown ? 1 : 0.96
        Behavior on scale { NumberAnimation { duration: Theme.slideMs * 0.8; easing.type: Easing.OutCubic } }
        clip: true

        Rectangle {
            id: field
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
            height: 52
            radius: Theme.radius(26)
            color: Theme.alpha(Theme.bg2, 0.95)
            border.color: Theme.alpha(Theme.accent, 0.45)

            HeaderTitle {
                anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
                size: 20
                markSize: 21
                fallbackGlyph: "\uf0ea"
            }
            Text {
                anchors { left: input.left; verticalCenter: parent.verticalCenter }
                visible: !input.text
                text: "Поиск в истории…"
                font.family: Theme.bodyFont; font.pixelSize: 18; font.italic: Theme.italicTitle
                color: Theme.muted
            }
            TextInput {
                id: input
                anchors { left: parent.left; leftMargin: 50; right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                focus: true
                font.family: Theme.bodyFont; font.pixelSize: 18
                color: Theme.fg
                selectionColor: Theme.alpha(Theme.accent, 0.4)
                clip: true
                onTextChanged: menu.query = text
                Keys.onPressed: event => {
                    const step = KeyName.listStep(event);
                    if (event.key === Qt.Key_Escape) {
                        menu.close();
                    } else if (step !== 0) {
                        menu.select(menu.current + step);
                    } else if (KeyName.isEnter(event)) {
                        menu.activate(menu.current);
                    } else if (event.key === Qt.Key_Delete && input.cursorPosition === input.text.length) {
                        // At the end of the text Delete has nothing to erase there, so it removes the entry.
                        menu.removeCurrent();
                    } else {
                        return;
                    }
                    event.accepted = true;
                }
            }
        }

        ListView {
            id: list
            anchors { left: parent.left; right: parent.right; top: field.bottom; bottom: footer.top; margins: 12 }
            clip: true
            spacing: 4
            model: menu.results
            currentIndex: menu.current
            highlightMoveDuration: 120
            boundsBehavior: Flickable.StopAtBounds

            highlight: Rectangle {
                width: list.width
                radius: Theme.radius(12)
                color: Theme.alpha(Theme.accent, 0.22)
                border.color: Theme.alpha(Theme.accent, 0.55)
            }

            delegate: Item {
                id: row
                required property var modelData
                required property int index
                width: list.width
                height: 44

                Text {
                    anchors { left: parent.left; right: parent.right; margins: 14; verticalCenter: parent.verticalCenter }
                    elide: Text.ElideRight
                    text: row.modelData.label
                    font.family: Theme.bodyFont; font.pixelSize: 15
                    color: Theme.fg
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: menu.select(row.index)
                    onClicked: menu.activate(row.index)
                }
            }

            Text {
                anchors.centerIn: parent
                width: list.width - 40
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                visible: list.count === 0
                text: menu.emptyText
                font.family: Theme.titleFont; font.pixelSize: Theme.titleSize(16); font.italic: Theme.italicTitle
                color: Theme.muted
            }
        }

        Item {
            id: footer
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 16 }
            height: 36
            visible: history.on

            Text {
                anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                text: "Enter скопировать · Delete удалить"
                font.family: Theme.bodyFont; font.pixelSize: 12
                color: Theme.muted
            }
            Chip {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: menu.clearArmed ? "Точно очистить?" : "Очистить"
                enabled: history.entries.length > 0
                onClicked: menu.clear()
            }
        }
    }
}
