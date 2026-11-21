// Cheat sheet (Alt+F1, waybar "?"). Hotkeys are read from `hyprctl binds -j` when it opens: a bind shows up when
// keybind.lua gives it a description "group | text [| keys label]". The other cards are in manual.js.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common
import "../common/keys.js" as KeyName
import "manual.js" as Manual

OverlayPanel {
    id: menu

    property var sections: []
    // keybind.lua writes the main modifier (changeable in the settings window) here.
    property string mainModLabel: "Alt"

    readonly property var groupOrder: ["Приложения", "Окна", "Воркспейсы", "Скриншоты", "Оформление", "Звук и яркость", "Система"]
    readonly property var keyNames: ({
        "Return": "Enter", "Print": "PrtSc", "Tab": "Tab", "left": "←", "right": "→", "up": "↑", "down": "↓",
        "mouse:272": "ЛКМ", "mouse:273": "ПКМ", "space": "Space"
    })

    function keyLabel(bind) {
        const mods = [];
        if (bind.modmask & 64) mods.push("Super");
        if (bind.modmask & 4) mods.push("Ctrl");
        if (bind.modmask & 8) mods.push("Alt");
        if (bind.modmask & 1) mods.push("Shift");
        mods.push(keyNames[bind.key] || (bind.key.length === 1 ? bind.key.toUpperCase() : bind.key));
        return mods.join("+");
    }

    // The described binds by group, the known groups first in their order, then Manual's cards.
    function buildSections(binds) {
        const groups = {};
        for (const bind of binds) {
            const parts = (bind.has_description && bind.description || "").split("|").map(s => s.trim());
            if (parts.length < 2) {
                continue;
            }
            (groups[parts[0]] = groups[parts[0]] || []).push({ keys: parts[2] || keyLabel(bind), text: parts[1] });
        }
        const known = groupOrder.filter(group => groups[group]);
        const others = Object.keys(groups).filter(group => !groupOrder.includes(group));
        return known.concat(others).map(group => ({ title: group, rows: groups[group] })).concat(Manual.sections);
    }

    namespace: "help-panel"
    fadeInMs: 200

    onKeyPressed: event => {
        if (event.key === Qt.Key_F1 || KeyName.of(event) === "Q") {
            close();
        }
    }

    Process {
        command: ["hyprctl", "binds", "-j"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    menu.sections = menu.buildSections(JSON.parse(this.text));
                } catch (e) {
                    menu.sections = menu.buildSections([]);
                }
            }
        }
    }
    FileView {
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/hypr-binds-registry.json"
        onLoaded: {
            const names = { SUPER: "Super", CTRL: "Ctrl" };
            try {
                menu.mainModLabel = names[JSON.parse(text()).mainMod] || "Alt";
            } catch (e) {}
        }
    }

    Rectangle {
        id: sheet
        anchors.centerIn: parent
        width: Math.min(parent.width - 80, 1560)
        height: Math.min(parent.height - 80, 960)
        radius: Theme.radius(22)
        color: Theme.alpha(Theme.bg, 0.95)
        border.width: Theme.border
        border.color: Theme.alpha(Theme.accent, 0.5)
        MouseArea { anchors.fill: parent }   // clicks inside do not close

        HeaderTitle {
            id: header
            x: 32; y: 26
            text: "Как тут всё устроено"
            size: 32
            fallbackGlyph: "?"
        }
        Text {
            anchors { right: parent.right; rightMargin: 32; verticalCenter: header.verticalCenter }
            text: menu.mainModLabel + " — главная клавиша · Esc — закрыть"
            font.family: Theme.bodyFont; font.pixelSize: 14
            color: Theme.muted
        }

        Flickable {
            anchors { left: parent.left; right: parent.right; top: header.bottom; bottom: parent.bottom; margins: 24; topMargin: 22 }
            contentHeight: cards.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Flow {
                id: cards
                width: parent.width
                spacing: 18

                Repeater {
                    model: menu.sections
                    HelpCard {
                        required property var modelData
                        required property int index
                        width: (cards.width - cards.spacing * 2) / 3
                        section: modelData
                        appearDelay: index * 40
                    }
                }
            }
        }
    }
}
