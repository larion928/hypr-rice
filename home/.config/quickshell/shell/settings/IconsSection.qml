import QtQuick
import qs.common
import "../common/url.js" as Url
import qs.services

// The icon theme of GTK programs (installed ones with samples, missing ones to install) on the left,
// the battery drawing (any theme's, in this theme's colours) on the right.
Item {
    id: section
    required property ThemeEditStore themeEdit

    SectionTitle {
        id: iconThemeTitle
        text: "Тема значков"
    }
    Text {
        anchors { left: iconThemeTitle.right; leftMargin: 12; verticalCenter: iconThemeTitle.verticalCenter }
        text: themeEdit.editing && !themeEdit.edit.iconTheme ? "как в теме: " + themeEdit.themesIconTheme() : ""
        font.family: Theme.bodyFont; font.pixelSize: 13
        color: Theme.muted
    }
    ListView {
        id: iconThemeList
        anchors { left: parent.left; top: iconThemeTitle.bottom; bottom: parent.bottom; topMargin: 10 }
        width: parent.width * 0.58
        clip: true
        spacing: 4
        boundsBehavior: Flickable.StopAtBounds
        model: themeEdit.iconThemes.installed.concat(themeEdit.iconThemes.downloadable.filter(item => !item.installed))
        delegate: Rectangle {
            id: themeRow
            required property var modelData
            readonly property bool installed: modelData.name !== undefined
            readonly property bool chosen: installed && themeEdit.iconThemeNow() === modelData.name
            width: ListView.view.width; height: 52
            radius: Theme.rounded ? 8 : 0
            color: chosen ? Theme.alpha(Theme.accent, 0.2) : (rowHover.containsMouse ? Theme.alpha(Theme.accent, 0.08) : Theme.alpha(Theme.bg2, 0.9))
            border.color: chosen ? Theme.accent : "transparent"
            MouseArea {
                id: rowHover
                anchors.fill: parent
                hoverEnabled: true
                enabled: themeRow.installed
                onClicked: themeEdit.pickIconTheme(themeRow.modelData.name)
            }
            Text {
                id: themeName
                x: 14; anchors.verticalCenter: parent.verticalCenter
                width: 190
                elide: Text.ElideRight
                text: themeRow.installed ? themeRow.modelData.label : themeRow.modelData.title
                font.family: Theme.bodyFont; font.pixelSize: 15
                color: Theme.fg
            }
            Row {
                visible: themeRow.installed
                anchors { left: themeName.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
                spacing: 8
                Repeater {
                    model: themeRow.installed ? themeRow.modelData.previews : []
                    Image {
                        required property string modelData
                        width: 28; height: 28
                        sourceSize: Qt.size(56, 56)
                        source: Url.fromPath(modelData)
                        asynchronous: true
                    }
                }
            }
            Text {
                visible: !themeRow.installed
                anchors { left: themeName.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
                text: themeRow.installed ? "" : (themeRow.modelData.source === "aur" ? "из AUR" : "из репозитория") + " · не установлена"
                font.family: Theme.bodyFont; font.pixelSize: 13
                color: Theme.muted
            }
            Chip {
                visible: !themeRow.installed
                anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                text: "Установить"
                enabled: !themeEdit.installStarting
                onClicked: themeEdit.askInstall(themeRow.modelData)
            }
        }
    }
    Text {
        visible: !themeEdit.iconThemes.installed.length
        anchors { left: iconThemeList.left; top: iconThemeList.top }
        text: "читаю темы значков…"
        font.family: Theme.bodyFont; font.pixelSize: 13
        color: Theme.muted
    }

    SectionTitle {
        id: batteryTitle
        anchors { left: iconThemeList.right; leftMargin: 28 }
        text: "Рисунок батареи"
    }
    Text {
        id: batteryNote
        anchors { left: batteryTitle.left; top: batteryTitle.bottom; topMargin: 4 }
        text: "у любой темы, в цветах этой; анимация — та, что у рисунка"
        font.family: Theme.bodyFont; font.pixelSize: 13
        color: Theme.muted
    }
    Flow {
        anchors { left: batteryTitle.left; right: parent.right; top: batteryNote.bottom; topMargin: 12 }
        spacing: 10
        Repeater {
            model: ThemeList.themes
            Rectangle {
                id: batteryCell
                required property var modelData
                readonly property bool chosen: themeEdit.editing !== null
                    && (themeEdit.edit.battery || themeEdit.editing.name) === modelData.name
                width: 96; height: 92
                radius: Theme.rounded ? 10 : 0
                color: chosen ? Theme.alpha(Theme.accent, 0.2) : (batteryArea.containsMouse ? Theme.alpha(Theme.accent, 0.08) : Theme.alpha(Theme.bg2, 0.9))
                border.color: chosen ? Theme.accent : "transparent"
                Image {
                    anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 12 }
                    width: 40; height: 40
                    sourceSize: Qt.size(80, 80)
                    source: Url.fromPath(batteryCell.modelData.dir + "/assets/battery-0.svg")
                }
                Text {
                    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 10 }
                    text: batteryCell.modelData.pal.label
                    font.family: Theme.bodyFont; font.pixelSize: 12
                    color: Theme.fg
                }
                MouseArea {
                    id: batteryArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: themeEdit.pickBattery(batteryCell.modelData.name)
                }
            }
        }
    }
}
