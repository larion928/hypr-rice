// Theme switcher (Alt+Shift+T, waybar palette button, launcher). Each card is drawn in its own theme's colours
// and fonts; Enter runs changetheme. Eight themes to a tab; the tab follows the selected theme.
import QtQuick
import Quickshell
import qs.common
import qs.services
import "../common/keys.js" as KeyName

OverlayPanel {
    id: menu

    readonly property var themes: ThemeList.themes
    property int index: Math.max(0, themes.findIndex(t => t.current))  // the selected theme, in the whole list
    // The current theme's look for the picker itself, so it matches what is on screen.
    readonly property var cur: themes.find(t => t.current) || themes[0] || ({ pal: { colors: {} }, ui: {} })
    readonly property int perPage: 8
    readonly property int pages: Math.max(1, Math.ceil(themes.length / perPage))
    readonly property int page: Math.floor(index / perPage)
    readonly property var shown: themes.slice(page * perPage, (page + 1) * perPage)
    // Up to five cards fit in one row; more go into a 4-column grid with smaller cards.
    readonly property int columns: shown.length > 5 ? 4 : Math.max(1, shown.length)
    readonly property bool compact: shown.length > 5

    function move(step) {
        if (themes.length) {
            index = (index + step + themes.length) % themes.length;
        }
    }

    // The same place on another tab, or its last theme when that tab is shorter.
    function turnPage(step) {
        const next = (page + step + pages) % pages;
        index = Math.min(next * perPage + index % perPage, themes.length - 1);
    }

    function apply() {
        if (closing || !themes.length) {
            return;
        }
        const picked = themes[index];
        if (!picked.current) {
            Quickshell.execDetached(["changetheme", picked.name]);
        }
        close();
    }

    namespace: "theme-picker"
    dim: 0.62
    lingerMs: 120
    fadeOutMs: 220
    Component.onCompleted: ThemeList.refresh()

    onKeyPressed: event => {
        const step = KeyName.step(event, columns);
        const digit = event.key - Qt.Key_1;
        if (step !== 0) {
            move(step);
        } else if (event.key === Qt.Key_PageUp) {
            turnPage(-1);
        } else if (event.key === Qt.Key_PageDown) {
            turnPage(1);
        } else if (KeyName.isEnter(event) || event.key === Qt.Key_Space) {
            apply();
        } else if (digit >= 0 && digit < Math.min(8, shown.length)) {
            index = page * perPage + digit;
            apply();
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: menu.close()
        onWheel: wheel => menu.move(wheel.angleDelta.y > 0 || wheel.angleDelta.x > 0 ? -1 : 1)
    }

    Text {
        anchors { horizontalCenter: parent.horizontalCenter; bottom: cards.top; bottomMargin: 60 }
        text: "Тема оформления"
        font.family: menu.cur.pal.display || "serif"
        font.pixelSize: Math.round(40 * (menu.cur.ui.titleScale ?? 1))
        color: Theme.fg
    }

    // The tabs: one dot each, the current one long.
    Row {
        visible: menu.pages > 1
        anchors { horizontalCenter: parent.horizontalCenter; bottom: cards.top; bottomMargin: 26 }
        spacing: 10
        Repeater {
            model: menu.pages
            Rectangle {
                required property int index
                width: index === menu.page ? 34 : 12; height: 12
                radius: 6
                color: index === menu.page ? Theme.accent : Theme.alpha(Theme.muted, 0.6)
                Behavior on width { NumberAnimation { duration: 180 } }
                MouseArea { anchors.fill: parent; onClicked: menu.turnPage(parent.index - menu.page) }
            }
        }
    }

    Grid {
        id: cards
        anchors.centerIn: parent
        columns: menu.columns
        spacing: 28

        Repeater {
            model: menu.shown
            ThemeCard {
                required property var modelData
                required property int index  // on this tab
                readonly property int place: menu.page * menu.perPage + index  // in the whole list
                entry: modelData
                number: index + 1
                selected: menu.index === place
                compact: menu.compact
                onHovered: menu.index = place
                onPicked: {
                    menu.index = place;
                    menu.apply();
                }
            }
        }
    }

    Text {
        anchors { horizontalCenter: parent.horizontalCenter; top: cards.bottom; topMargin: 56 }
        text: (menu.compact ? "←  →  ↑  ↓" : "←  →") + "  выбрать      Enter  применить      1–"
              + menu.shown.length + "  сразу" + (menu.pages > 1 ? "      PgUp  PgDn  вкладки" : "")
              + "      Esc  закрыть"
        font.family: menu.cur.pal.font || "monospace"
        font.pixelSize: 15
        color: Theme.muted
    }
}
