import QtQuick
import qs.common
import "../common/url.js" as Url

// Cursor themes (installed ones with a few cursors drawn, missing ones to install) and the size.
Item {
    id: section
    required property ThemeEditStore themeEdit
    required property UserFiles userFiles

    SectionTitle {
        id: cursorTitle
        text: "Курсор"
    }
    Text {
        anchors { left: cursorTitle.right; leftMargin: 12; verticalCenter: cursorTitle.verticalCenter }
        text: themeEdit.editing && !themeEdit.edit.cursor ? "как в теме: " + themeEdit.themesCursor() : ""
        font.family: Theme.bodyFont; font.pixelSize: 13
        color: Theme.muted
    }
    Row {
        id: cursorFileRow
        anchors { left: cursorTitle.right; leftMargin: 220; verticalCenter: cursorTitle.verticalCenter }
        spacing: 12
        Chip { text: "Добавить из файла…"; enabled: !userFiles.working; onClicked: userFiles.pick("cursor") }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: 360
            elide: Text.ElideRight
            text: userFiles.pickFor === "cursor" ? userFiles.message : ""
            font.family: Theme.bodyFont; font.pixelSize: 13
            color: userFiles.failed ? Theme.crit : Theme.muted
        }
    }
    Row {
        id: cursorSizeRow
        anchors { right: parent.right; verticalCenter: cursorTitle.verticalCenter }
        spacing: 8
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Размер"
            font.family: Theme.bodyFont; font.pixelSize: 14
            color: Theme.fg
        }
        Repeater {
            model: themeEdit.cursorSizes
            Chip {
                required property int modelData
                text: modelData + " px"
                active: themeEdit.editing !== null && themeEdit.cursorSizeNow() === modelData
                onClicked: themeEdit.pickCursorSize(modelData)
            }
        }
    }
    ListView {
        id: cursorList
        anchors { left: parent.left; right: parent.right; top: cursorTitle.bottom; bottom: parent.bottom; topMargin: 14 }
        clip: true
        spacing: 4
        boundsBehavior: Flickable.StopAtBounds
        model: themeEdit.cursorThemes.installed.concat(themeEdit.cursorThemes.downloadable.filter(item => !item.installed))
        delegate: Rectangle {
            id: cursorRow
            required property var modelData
            readonly property bool installed: modelData.name !== undefined
            readonly property bool chosen: installed && themeEdit.cursorNow() === modelData.name
            width: ListView.view.width; height: 60
            radius: Theme.rounded ? 8 : 0
            color: chosen ? Theme.alpha(Theme.accent, 0.2) : (cursorHover.containsMouse ? Theme.alpha(Theme.accent, 0.08) : Theme.alpha(Theme.bg2, 0.9))
            border.color: chosen ? Theme.accent : "transparent"
            MouseArea {
                id: cursorHover
                anchors.fill: parent
                hoverEnabled: true
                enabled: cursorRow.installed
                onClicked: themeEdit.pickCursor(cursorRow.modelData.name)
            }
            Text {
                id: cursorName
                x: 14; anchors.verticalCenter: parent.verticalCenter
                width: 220
                elide: Text.ElideRight
                text: cursorRow.installed ? cursorRow.modelData.label : cursorRow.modelData.title
                font.family: Theme.bodyFont; font.pixelSize: 15
                color: Theme.fg
            }
            Row {
                visible: cursorRow.installed
                anchors { left: cursorName.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
                spacing: 14
                Repeater {
                    model: cursorRow.installed ? cursorRow.modelData.previews : []
                    Image {
                        required property string modelData
                        width: 40; height: 40
                        source: Url.fromPath(modelData)
                        asynchronous: true
                    }
                }
            }
            Text {
                visible: !cursorRow.installed
                anchors { left: cursorName.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
                text: (cursorRow.modelData.source === "aur" ? "из AUR" : "из репозитория") + " · не установлен"
                font.family: Theme.bodyFont; font.pixelSize: 13
                color: Theme.muted
            }
            Chip {
                visible: !cursorRow.installed
                anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                text: "Установить"
                enabled: !themeEdit.install.starting
                onClicked: themeEdit.askInstall(cursorRow.modelData, "Alt+F2 → Тема → Курсор")
            }
            Chip {
                visible: cursorRow.installed && !!cursorRow.modelData.removable
                anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                text: "Удалить"
                enabled: !userFiles.working
                onClicked: userFiles.removeCursor(cursorRow.modelData.name)
            }
        }
    }
    Text {
        visible: !themeEdit.cursorThemes.installed.length
        anchors { left: cursorList.left; top: cursorList.top }
        text: "читаю курсоры…"
        font.family: Theme.bodyFont; font.pixelSize: 13
        color: Theme.muted
    }
}
