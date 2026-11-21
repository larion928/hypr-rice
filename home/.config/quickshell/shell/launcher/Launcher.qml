// App launcher (Alt+R). Apps come from DesktopEntries, the rice's own entries from commands.js; launches are
// counted in ~/.local/state/launcher/usage.json so frequent ones rank higher (search.js).
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.common
import qs.services
import "../common/keys.js" as KeyName
import "commands.js" as Commands
import "search.js" as Search

OverlayPanel {
    id: menu

    readonly property string usagePath: Quickshell.env("HOME") + "/.local/state/launcher/usage.json"
    readonly property var usage: {
        try {
            return JSON.parse(usageFile.text()) || {};
        } catch (e) {
            return {};
        }
    }
    property string query: ""
    property int current: 0
    property string armed: ""   // id of a dangerous command waiting for a second Enter

    readonly property var commands: Commands.all(ThemeList.themes, Quickshell.env("HOME"))
    readonly property var apps: DesktopEntries.applications.values
        .filter(e => !e.noDisplay)
        .map(e => ({ id: "app:" + e.id, name: e.name, desc: e.genericName || e.comment || "", icon: e.icon,
                     keys: [e.genericName, e.comment, (e.keywords || []).join(" "), (e.categories || []).join(" ")].join(" "),
                     entry: e }))
    readonly property var results: Search.results(apps.concat(commands), query, usage)

    onResultsChanged: select(0)

    function select(index) {
        current = Math.max(0, Math.min(index, results.length - 1));
        armed = "";
    }

    function activate(index) {
        const it = results[index];
        if (!it) {
            return;
        }
        if (it.danger && armed !== it.id) {
            armed = it.id;
            return;
        }
        const counted = Object.assign({}, usage);
        counted[it.id] = (counted[it.id] || 0) + 1;
        Quickshell.execDetached(["sh", "-c", 'mkdir -p "$(dirname "$1")" && printf "%s" "$2" > "$1"', "sh",
                                 usagePath, JSON.stringify(counted)]);
        if (it.entry) {
            it.entry.execute();
        } else {
            Quickshell.execDetached(it.run);
        }
        close();
    }

    // Down/Tab/Ctrl+J and Up/Shift+Tab/Ctrl+K move; plain letters, and Left/Right, belong to the text.
    function moveKey(event) {
        const name = KeyName.of(event);
        const control = event.modifiers & Qt.ControlModifier;
        if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab || (control && name === "J")) {
            return 1;
        }
        if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab || (control && name === "K")) {
            return -1;
        }
        return 0;
    }

    FileView { id: usageFile; path: menu.usagePath; blockLoading: true }

    namespace: "launcher"
    fullscreen: false
    implicitWidth: 680
    implicitHeight: 560
    fadeInMs: Theme.slideMs * 0.6
    fadeOutMs: 140

    Rectangle {
        id: box
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
                fallbackGlyph: "\uf002"
            }
            Text {
                anchors { left: input.left; verticalCenter: parent.verticalCenter }
                visible: !input.text
                text: "Приложение или команда…"
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
                    const step = menu.moveKey(event);
                    if (event.key === Qt.Key_Escape) {
                        menu.close();
                    } else if (step !== 0) {
                        menu.select(menu.current + step);
                    } else if (KeyName.isEnter(event)) {
                        menu.activate(menu.current);
                    } else {
                        return;
                    }
                    event.accepted = true;
                }
            }
        }

        SectionTitle {
            id: sectionLabel
            anchors { left: parent.left; leftMargin: 24; top: field.bottom; topMargin: 14 }
            text: menu.query ? "Результаты" : "Часто запускаемые"
            font.pixelSize: 13
        }

        ListView {
            id: list
            anchors { left: parent.left; right: parent.right; top: sectionLabel.bottom; bottom: parent.bottom; margins: 12; topMargin: 8 }
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
                readonly property bool armed: menu.armed === modelData.id
                width: list.width
                height: 54

                Row {
                    anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                    spacing: 14

                    Item {
                        width: 32; height: 32
                        anchors.verticalCenter: parent.verticalCenter
                        IconImage {
                            id: appIcon
                            // Sized from the start: a source set while the size is still 0 is
                            // rendered at the SVG's own size, which can be huge.
                            implicitSize: 32
                            visible: source != ""
                            source: row.modelData.icon ? Quickshell.iconPath(row.modelData.icon, true) : ""
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: !appIcon.visible
                            text: row.modelData.glyph || "\uf2d0"
                            font.family: Theme.glyphFont; font.pixelSize: 20
                            color: row.modelData.danger ? Theme.crit : Theme.accent
                        }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text {
                            text: row.modelData.name
                            font.family: Theme.titleFont; font.pixelSize: 16
                            color: row.modelData.danger ? Theme.crit : Theme.fg
                        }
                        Text {
                            visible: text.length > 0
                            width: list.width - 140
                            elide: Text.ElideRight
                            text: row.armed ? "Нажми Enter ещё раз, чтобы подтвердить" : row.modelData.desc
                            font.family: Theme.bodyFont; font.pixelSize: 12
                            color: row.armed ? Theme.warn : Theme.muted
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: if (menu.current !== row.index) menu.select(row.index)
                    onClicked: menu.activate(row.index)
                }
            }

            Text {
                anchors.centerIn: parent
                visible: list.count === 0
                text: "Ничего не нашлось"
                font.family: Theme.titleFont; font.pixelSize: 16; font.italic: Theme.italicTitle
                color: Theme.muted
            }
        }
    }
}
