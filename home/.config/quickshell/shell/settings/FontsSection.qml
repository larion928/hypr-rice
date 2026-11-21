import QtQuick
import qs.common

// The three fonts on the left; on the right the installed fonts, each in its own face.
Item {
    id: section
    required property ThemeEditStore themeEdit

    Column {
        id: slotColumn
        anchors { left: parent.left; top: parent.top }
        width: 400
        spacing: 12
        Repeater {
            model: themeEdit.fontSlots
            Rectangle {
                id: slotRow
                required property var modelData
                readonly property string key: modelData[0]
                readonly property bool active: themeEdit.fontSlot === key
                width: slotColumn.width; height: 92
                radius: Theme.rounded ? 10 : 0
                color: active ? Theme.alpha(Theme.accent, 0.16) : Theme.alpha(Theme.bg2, 0.9)
                border.color: active ? Theme.accent : Theme.alpha(Theme.muted, 0.3)
                Column {
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 16 }
                    spacing: 4
                    Text {
                        text: slotRow.modelData[1] + " · " + slotRow.modelData[2]
                        font.family: Theme.bodyFont; font.pixelSize: 13
                        color: Theme.muted
                    }
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: themeEdit.editing ? themeEdit.font(slotRow.key) : ""
                        font.family: text; font.pixelSize: 22
                        color: Theme.fg
                    }
                    Text {
                        readonly property bool own: !themeEdit.editing || !themeEdit.edit.fonts[slotRow.key]
                        text: own ? "как в теме" : "свой выбор"
                        font.family: Theme.bodyFont; font.pixelSize: 12
                        color: own ? Theme.muted : Theme.accent
                    }
                }
                MouseArea { anchors.fill: parent; onClicked: themeEdit.fontSlot = slotRow.key }
            }
        }
        Chip {
            text: "Как в теме"
            enabled: themeEdit.editing !== null && !!themeEdit.edit.fonts[themeEdit.fontSlot]
            onClicked: themeEdit.chooseFont("")
        }
    }

    Field {
        id: fontSearch
        anchors { left: slotColumn.right; right: parent.right; top: parent.top; leftMargin: 24 }
        placeholder: "Поиск шрифта"
        onTextChanged: themeEdit.fontQuery = text
    }
    ListView {
        anchors { left: fontSearch.left; right: parent.right; top: fontSearch.bottom; bottom: parent.bottom; topMargin: 10 }
        clip: true
        spacing: 2
        boundsBehavior: Flickable.StopAtBounds
        model: themeEdit.matchingFonts
        delegate: Rectangle {
            id: fontRow
            required property string modelData
            readonly property bool picked: themeEdit.editing !== null && themeEdit.font(themeEdit.fontSlot) === modelData
            width: ListView.view.width; height: 44
            radius: Theme.rounded ? 8 : 0
            color: picked ? Theme.alpha(Theme.accent, 0.22)
                   : (rowArea.containsMouse ? Theme.alpha(Theme.accent, 0.1) : "transparent")
            Text {
                anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                text: fontRow.modelData
                font.family: Theme.bodyFont; font.pixelSize: 14
                color: Theme.fg
            }
            Text {
                anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                text: "Аа Бб Вв 0123"
                font.family: fontRow.modelData; font.pixelSize: 18
                color: fontRow.picked ? Theme.accent : Theme.muted
            }
            MouseArea { id: rowArea; anchors.fill: parent; hoverEnabled: true; onClicked: themeEdit.chooseFont(fontRow.modelData) }
        }
    }
}
