import QtQuick
import qs.common

// The waybar layout as a bar to drag modules around on: within the bar to move them, off the bar to
// take them away, from the set below onto it to add them. Saved for this theme with «Сохранить»
// above, or for every theme with the button here.
Item {
    id: panelEditor
    required property ThemeEditStore themeEdit

    property var drag: null      // the module being dragged: {module, side, index}; side "" from the set below
    property var target: null    // where letting go puts it: {side, index, x}; null off the bar, which takes it away
    property var pressedAt: null  // where the drag began: a release close to it is a click, which picks an icon
    property string hovered: ""
    readonly property var sideNames: ({ "modules-left": "слева", "modules-center": "по центру",
                                        "modules-right": "справа" })

    function row(side) {
        return side === "modules-left" ? leftRow : side === "modules-center" ? centerRow : rightRow;
    }
    function pills(side) {
        const list = [];
        for (const child of panelEditor.row(side).children)
            if (child.pillModule !== undefined) list.push(child);
        return list;
    }
    // Every place a module can go, in the bar's coordinates: each gap of each group, a group's two
    // ends, and the bar's middle while the centre group is empty. A drop takes the nearest one.
    function slots() {
        const list = [];
        for (const [side] of themeEdit.sides) {
            const pills = panelEditor.pills(side);
            if (!pills.length) {
                const x = side === "modules-left" ? 16 : side === "modules-right" ? mockBar.width - 16 : mockBar.gapMiddle;
                list.push({ side: side, index: 0, x: x });
                continue;
            }
            const row = panelEditor.row(side);
            for (let i = 0; i <= pills.length; i++) {
                const edge = i < pills.length ? pills[i].x - 3 : pills[i - 1].x + pills[i - 1].width + 3;
                list.push({ side: side, index: i, x: row.mapToItem(mockBar, edge, 0).x });
            }
        }
        return list;
    }
    function start(module, side, index, point) {
        panelEditor.drag = { module: module, side: side, index: index };
        panelEditor.pressedAt = point;
        panelEditor.follow(point);
    }
    // point is in panelEditor's coordinates.
    function follow(point) {
        if (panelEditor.pressedAt && Math.hypot(point.x - panelEditor.pressedAt.x, point.y - panelEditor.pressedAt.y) > 6)
            panelEditor.pressedAt = null;
        ghost.x = point.x - ghost.width / 2;
        ghost.y = point.y - ghost.height / 2;
        const onBar = mockBar.mapFromItem(panelEditor, point.x, point.y);
        if (onBar.y < -30 || onBar.y > mockBar.height + 30) {
            panelEditor.target = null;
            return;
        }
        let nearest = null;
        for (const slot of panelEditor.slots())
            if (!nearest || Math.abs(slot.x - onBar.x) < Math.abs(nearest.x - onBar.x)) nearest = slot;
        panelEditor.target = nearest;
    }
    function finish() {
        const drag = panelEditor.drag;
        const target = panelEditor.target;
        const click = panelEditor.pressedAt !== null;
        panelEditor.drag = null;
        panelEditor.target = null;
        panelEditor.pressedAt = null;
        if (click) {
            if (drag && drag.side && themeEdit.iconEditable(drag.module)) themeEdit.openIconPicker(drag.module);
            return;
        }
        if (!drag || (!drag.side && !target)) return;
        const layout = themeEdit.panelCopy();
        if (drag.side) layout[drag.side].splice(drag.index, 1);
        if (target) {
            let index = target.index;
            if (drag.side === target.side && drag.index < index) index--;  // it was taken out above
            layout[target.side] = (layout[target.side] || []);
            layout[target.side].splice(index, 0, drag.module);
        }
        // After this release handler: the dragged module's own delegate goes away with the change,
        // and an item replaced while it still holds the mouse grab can stay drawn where it was.
        Qt.callLater(() => themeEdit.change("waybar", layout));
    }

    Row {
        id: panelTop
        spacing: 10
        TabButton { text: "Раскладка"; active: themeEdit.panelView === "layout"; onClicked: themeEdit.panelView = "layout" }
        TabButton { text: "Значки модулей"; active: themeEdit.panelView === "icons"; onClicked: themeEdit.panelView = "icons" }
        Item { width: 16; height: 1 }
        Chip { text: "Сверху"; active: themeEdit.editing !== null && themeEdit.panel().position !== "bottom"; onClicked: themeEdit.setPosition("top") }
        Chip { text: "Снизу"; active: themeEdit.editing !== null && themeEdit.panel().position === "bottom"; onClicked: themeEdit.setPosition("bottom") }
        Item { width: 16; height: 1 }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: !themeEdit.editing ? ""
                  : themeEdit.edit.waybar ? "своя раскладка у этой темы"
                  : themeEdit.everywhere.waybar ? "общая раскладка для всех тем" : "как в теме"
            font.family: Theme.bodyFont; font.pixelSize: 13
            color: Theme.accent
        }
    }
    Row {
        anchors { right: parent.right; verticalCenter: panelTop.verticalCenter }
        spacing: 10
        Chip {
            visible: themeEdit.editing !== null && !!themeEdit.everywhere.waybar
            text: "Убрать общую раскладку"
            onClicked: themeEdit.dropSharedPanel()
        }
        Chip { text: "Сохранить для всех тем"; onClicked: themeEdit.savePanelEverywhere() }
    }
    Text {
        id: panelHint
        anchors { left: parent.left; top: panelTop.bottom; topMargin: 14 }
        text: "Перетаскивай модули: по панели — переставить, с панели вниз — убрать, из набора снизу на панель — добавить. "
              + "Значки меняются во вкладке «Значки модулей» или нажатием на модуль."
              + (themeEdit.liveReading ? "   · обновляю данные панели…" : "")
        font.family: Theme.bodyFont; font.pixelSize: 13
        color: Theme.muted
    }

    Rectangle {
        id: mockBar
        anchors { left: parent.left; right: parent.right; top: panelHint.bottom; topMargin: 22 }
        height: 54
        radius: Math.min(Theme.ui.radius ?? 12, 16)
        color: Theme.alpha(Theme.bg, 0.95)
        border.width: panelEditor.target ? 2 : 1
        border.color: panelEditor.target ? Theme.accent : Theme.alpha(Theme.accent, 0.4)

        // The free stretch between the left and right groups. An empty centre group is shown and dropped
        // on there: at the bar's middle a long group on either side would cover it.
        readonly property real gapStart: leftRow.x + leftRow.width
        readonly property real gapEnd: rightRow.x
        readonly property real gapMiddle: (gapStart + gapEnd) / 2
        readonly property real gapWidth: gapEnd - gapStart

        // The empty centre group, as a place to drop on while dragging.
        Rectangle {
            visible: panelEditor.drag !== null && (themeEdit.panel()["modules-center"] || []).length === 0
            x: mockBar.gapMiddle - width / 2
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, Math.min(110, mockBar.gapWidth - 12)); height: parent.height - 14
            clip: true
            radius: 8
            color: Theme.alpha(Theme.accent, 0.08)
            border.color: Theme.alpha(Theme.accent, 0.4)
            Text {
                anchors.centerIn: parent
                text: "центр"
                font.family: Theme.bodyFont; font.pixelSize: 12
                color: Theme.muted
            }
        }
        Row {
            id: leftRow
            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
            spacing: 6
            Repeater {
                model: themeEdit.editing ? (themeEdit.panel()["modules-left"] || []) : []
                BarModule { editor: panelEditor; themeEdit: panelEditor.themeEdit; side: "modules-left" }
            }
        }
        Row {
            id: centerRow
            anchors.centerIn: parent
            spacing: 6
            Repeater {
                model: themeEdit.editing ? (themeEdit.panel()["modules-center"] || []) : []
                BarModule { editor: panelEditor; themeEdit: panelEditor.themeEdit; side: "modules-center" }
            }
        }
        Row {
            id: rightRow
            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
            spacing: 6
            Repeater {
                model: themeEdit.editing ? (themeEdit.panel()["modules-right"] || []) : []
                BarModule { editor: panelEditor; themeEdit: panelEditor.themeEdit; side: "modules-right" }
            }
        }
        Rectangle {
            id: dropMarker
            visible: panelEditor.target !== null
            x: panelEditor.target ? panelEditor.target.x - 1 : 0; y: 6
            width: 3; height: parent.height - 12; radius: 1
            color: Theme.accent
            Text {
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.top; bottomMargin: 10 }
                text: panelEditor.target ? panelEditor.sideNames[panelEditor.target.side] : ""
                font.family: Theme.bodyFont; font.pixelSize: 12; font.bold: true
                color: Theme.accent
            }
        }
    }
    Text {
        id: hoveredName
        anchors { left: parent.left; top: mockBar.bottom; topMargin: 30 }
        text: panelEditor.drag ? (panelEditor.target ? "Отпусти — встанет " + panelEditor.sideNames[panelEditor.target.side]
                                                      : panelEditor.drag.side ? "Отпусти здесь, чтобы убрать с панели" : "Тащи на панель")
              : panelEditor.hovered ? themeEdit.moduleName(panelEditor.hovered)
                                      + (themeEdit.moduleNote(panelEditor.hovered) ? " — " + themeEdit.moduleNote(panelEditor.hovered) : "")
                                      + (themeEdit.iconEditable(panelEditor.hovered) ? " · нажми — сменить значок, тащи — переставить"
                                                                                     : " · тащи — переставить; значок не меняется")
              : " "
        font.family: Theme.bodyFont; font.pixelSize: 14
        color: panelEditor.drag && panelEditor.drag.side && !panelEditor.target ? Theme.crit : Theme.fg
    }

    Text {
        id: setTitle
        anchors { left: parent.left; top: hoveredName.bottom; topMargin: 22 }
        text: "Можно добавить"
        font.family: Theme.bodyFont; font.pixelSize: 14; font.bold: true
        color: Theme.fg
    }
    Flow {
        anchors { left: parent.left; right: parent.right; top: setTitle.bottom; topMargin: 10 }
        spacing: 8
        Repeater {
            model: themeEdit.editing ? themeEdit.editing.waybar.available.filter(module => !themeEdit.onPanel(module)) : []
            BarModule { editor: panelEditor; themeEdit: panelEditor.themeEdit; side: ""; showName: true }
        }
    }

    // The modules on the bar with their icons, one «Сменить» each.
    Rectangle {
        visible: themeEdit.panelView === "icons"
        anchors { left: parent.left; right: parent.right; top: panelTop.bottom; bottom: parent.bottom; topMargin: 14 }
        z: 15
        color: Theme.bg
        MouseArea { anchors.fill: parent }
        ListView {
            anchors.fill: parent
            clip: true
            spacing: 4
            boundsBehavior: Flickable.StopAtBounds
            model: themeEdit.editing ? themeEdit.sides.reduce((all, [side]) => all.concat(themeEdit.panel()[side] || []), []) : []
            delegate: Rectangle {
                id: iconRow
                required property string modelData
                readonly property bool editable: themeEdit.iconEditable(modelData)
                width: ListView.view.width; height: 50
                radius: Theme.rounded ? 8 : 0
                color: Theme.alpha(Theme.bg2, 0.9)
                Text {
                    id: rowIcon
                    x: 16; anchors.verticalCenter: parent.verticalCenter
                    width: 36
                    text: themeEdit.iconOf(iconRow.modelData) || "·"
                    font.family: Theme.glyphFont; font.pixelSize: 22
                    color: Theme.fg
                }
                Text {
                    anchors { left: rowIcon.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
                    text: themeEdit.moduleName(iconRow.modelData)
                          + (themeEdit.edit.icons && themeEdit.edit.icons[iconRow.modelData] ? "  · свой значок" : "")
                          + (iconRow.editable ? "" : "  · значок не меняется: он показывает состояние или его рисует скрипт")
                    font.family: Theme.bodyFont; font.pixelSize: 15
                    color: iconRow.editable ? Theme.fg : Theme.muted
                }
                Chip {
                    visible: iconRow.editable
                    anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    text: "Сменить"
                    onClicked: themeEdit.openIconPicker(iconRow.modelData)
                }
            }
        }
    }

    IconPicker {
        anchors.fill: parent
        z: 20
        visible: panelEditor.themeEdit.iconFor !== ""
        themeEdit: panelEditor.themeEdit
    }

    // What follows the pointer while dragging.
    Rectangle {
        id: ghost
        visible: panelEditor.drag !== null
        z: 10
        width: ghostText.implicitWidth + 24; height: 38
        radius: 8
        color: Theme.alpha(Theme.bg2, 0.95)
        border.color: Theme.accent
        Text {
            id: ghostText
            anchors.centerIn: parent
            text: panelEditor.drag ? (themeEdit.preview(panelEditor.drag.module) || themeEdit.moduleName(panelEditor.drag.module)) : ""
            font.family: Theme.font; font.pixelSize: 16
            color: Theme.fg
        }
    }
}
