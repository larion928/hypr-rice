import QtQuick
import qs.common
import "../common/url.js" as Url

// The ten palette colours on the left, the picker for the chosen one on the right, and a strip
// drawn in the edited colours to see them together.
Item {
    id: section
    required property ThemeEditStore themeEdit

    Column {
        id: colorColumn
        anchors { left: parent.left; top: parent.top }
        width: 400
        spacing: 6
        Repeater {
            model: themeEdit.colorNames
            Rectangle {
                id: colorRow
                required property var modelData
                readonly property string key: modelData[0]
                readonly property bool active: themeEdit.colorKey === key
                width: colorColumn.width; height: 44
                radius: Theme.rounded ? 8 : 0
                color: active ? Theme.alpha(Theme.accent, 0.16) : (colorRowArea.containsMouse ? Theme.alpha(Theme.accent, 0.08) : "transparent")
                border.color: active ? Theme.accent : "transparent"
                Rectangle {
                    id: swatch
                    anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                    width: 28; height: 28; radius: 6
                    color: themeEdit.editing ? themeEdit.color(colorRow.key) : "transparent"
                    border.color: Theme.alpha(Theme.fg, 0.4)
                }
                Text {
                    anchors { left: swatch.right; leftMargin: 12; verticalCenter: parent.verticalCenter }
                    text: colorRow.modelData[1]
                    font.family: Theme.bodyFont; font.pixelSize: 15
                    color: Theme.fg
                }
                Text {
                    anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    readonly property bool own: !themeEdit.editing || !themeEdit.edit.colors[colorRow.key]
                    text: (themeEdit.editing ? themeEdit.color(colorRow.key) : "") + (own ? "" : "  · свой")
                    font.family: Theme.font; font.pixelSize: 13
                    color: own ? Theme.muted : Theme.accent
                }
                MouseArea { id: colorRowArea; anchors.fill: parent; hoverEnabled: true; onClicked: themeEdit.colorKey = colorRow.key }
            }
        }
    }

    ColorPicker {
        id: picker
        anchors { left: colorColumn.right; top: parent.top; leftMargin: 28 }
        value: themeEdit.editing ? themeEdit.color(themeEdit.colorKey) : "#000000"
        onPicked: hex => themeEdit.chooseColor(hex)
    }
    Chip {
        anchors { left: picker.left; top: picker.bottom; topMargin: 12 }
        text: "Как в теме"
        enabled: themeEdit.editing !== null && !!themeEdit.edit.colors[themeEdit.colorKey]
        onClicked: themeEdit.ownColor()
    }

    // Folder colour (Papirus only: papirus-folders recolours its folder icons).
    Text {
        id: folderTitle
        anchors { left: picker.left; top: picker.bottom; topMargin: 64 }
        text: themeEdit.iconThemeNow().startsWith("Papirus")
              ? "Цвет папок" + (themeEdit.editing && !themeEdit.edit.folders ? "  · как в теме: " + (themeEdit.editing.own.folders || "стандартный") : "")
              : "Цвет папок меняется только у тем значков Papirus (тема значков выбирается в разделе \"Значки\")"
        font.family: Theme.bodyFont; font.pixelSize: 14; font.bold: true
        color: Theme.fg
    }
    Flow {
        visible: themeEdit.iconThemeNow().startsWith("Papirus")
        anchors { left: picker.left; right: parent.right; top: folderTitle.bottom; topMargin: 8 }
        spacing: 4
        Repeater {
            model: themeEdit.folderColors
            Rectangle {
                id: folderCell
                required property string modelData
                readonly property bool chosen: themeEdit.editing !== null
                    && (themeEdit.edit.folders || themeEdit.editing.own.folders) === modelData
                width: 44; height: 44
                radius: 8
                color: chosen ? Theme.alpha(Theme.accent, 0.25) : (folderArea.containsMouse ? Theme.alpha(Theme.accent, 0.1) : "transparent")
                border.color: chosen ? Theme.accent : "transparent"
                Image {
                    anchors.centerIn: parent
                    width: 32; height: 32
                    sourceSize: Qt.size(64, 64)
                    source: Url.fromPath("/usr/share/icons/Papirus/48x48/places/folder-" + folderCell.modelData + ".svg")
                }
                MouseArea {
                    id: folderArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: themeEdit.chooseFolders(folderCell.modelData)
                }
            }
        }
    }

    // A little bar in the edited colours.
    Rectangle {
        anchors { left: picker.left; right: parent.right; bottom: parent.bottom }
        height: 64
        radius: Theme.rounded ? 12 : 0
        readonly property var c: {
            const colors = {};
            if (themeEdit.editing)
                for (const [key] of themeEdit.colorNames) colors[key] = themeEdit.color(key);
            return colors;
        }
        color: c.bg || "black"
        border.color: c.accent || "white"
        Row {
            anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter }
            spacing: 14
            Rectangle { width: 30; height: 30; radius: 15; color: parent.parent.c.accent || "white"; anchors.verticalCenter: parent.verticalCenter }
            Text { text: "Текст"; color: parent.parent.c.fg || "white"; font.family: Theme.bodyFont; font.pixelSize: 16; anchors.verticalCenter: parent.verticalCenter }
            Text { text: "приглушённый"; color: parent.parent.c.muted || "grey"; font.family: Theme.bodyFont; font.pixelSize: 16; anchors.verticalCenter: parent.verticalCenter }
            Rectangle {
                width: 120; height: 34; radius: 8; color: parent.parent.c.bg2 || "black"
                anchors.verticalCenter: parent.verticalCenter
                Text { anchors.centerIn: parent; text: "кнопка"; color: parent.parent.parent.c.accent2 || "white"; font.family: Theme.bodyFont; font.pixelSize: 15 }
            }
            Text { text: "ок"; color: parent.parent.c.good || "green"; font.family: Theme.bodyFont; font.pixelSize: 16; anchors.verticalCenter: parent.verticalCenter }
            Text { text: "внимание"; color: parent.parent.c.warn || "yellow"; font.family: Theme.bodyFont; font.pixelSize: 16; anchors.verticalCenter: parent.verticalCenter }
            Text { text: "ошибка"; color: parent.parent.c.crit || "red"; font.family: Theme.bodyFont; font.pixelSize: 16; anchors.verticalCenter: parent.verticalCenter }
        }
    }
}
