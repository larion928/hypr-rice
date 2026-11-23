import QtQuick
import qs.common
import qs.services
import "../common/url.js" as Url

// Тема: on the left what adds or brings back themes (a file, the catalog, the removed ones) and the tabs of the list
// (8 themes to a tab); on the right what can be done with the theme selected below. A theme's own settings
// (ThemeEditor), the dialogs of OwnThemes and the catalog open over the list.
Item {
    id: page

    required property ThemeEditStore themeEdit
    required property OwnThemes ownThemes
    required property UserFiles userFiles
    readonly property var chosen: ownThemes.chosen()

    signal switched()

    Row {
        id: tools
        spacing: 10
        Chip { text: "Из файла…"; onClicked: page.ownThemes.ask("import", null) }
        Chip { text: "Каталог…"; onClicked: page.ownThemes.openCatalog() }
        Chip {
            visible: page.ownThemes.removed.length > 0
            text: "Вернуть удалённые (" + page.ownThemes.removed.length + ")"
            onClicked: page.ownThemes.ask("restore", null)
        }
        Item { visible: page.ownThemes.pages > 1; width: 12; height: 1 }
        Repeater {
            model: page.ownThemes.pages > 1 ? page.ownThemes.pages : 0
            TabButton {
                required property int index
                text: String(index + 1)
                active: page.ownThemes.themePage === index
                onClicked: page.ownThemes.themePage = index
            }
        }
    }
    Row {
        anchors { right: parent.right; verticalCenter: tools.verticalCenter }
        visible: page.chosen !== null
        spacing: 10
        SectionTitle {
            anchors.verticalCenter: parent.verticalCenter
            text: page.chosen ? "\"" + page.chosen.pal.label + "\"" : ""
            font.pixelSize: Theme.titleSize(16)
            font.bold: false
        }
        Chip { text: "Изменить"; primary: true; onClicked: page.themeEdit.open(page.chosen) }
        Chip { text: "Добавить на её основе"; onClicked: page.ownThemes.ask("new", page.chosen) }
        Chip { text: "Экспорт…"; onClicked: page.ownThemes.ask("export", page.chosen) }
        Chip { text: "К заводским"; onClicked: page.ownThemes.ask("factory", page.chosen) }
        Chip { visible: page.chosen !== null && !page.chosen.current; text: "Удалить"; onClicked: page.ownThemes.ask("delete", page.chosen) }
    }
    Flow {
        anchors { left: parent.left; right: parent.right; top: tools.bottom; bottom: parent.bottom; topMargin: 16 }
        spacing: 16
        Repeater {
            model: ThemeList.themes.slice(page.ownThemes.themePage * page.ownThemes.perPage,
                                          (page.ownThemes.themePage + 1) * page.ownThemes.perPage)
            Rectangle {
                id: card
                required property var modelData
                readonly property var colors: modelData.pal.colors
                readonly property bool chosen: page.chosen !== null && page.chosen.name === modelData.name
                width: 280; height: 230
                radius: Theme.radius(14)
                color: colors.bg
                border.width: chosen ? 3 : area.containsMouse || modelData.current ? 2 : 1
                border.color: colors.accent
                clip: true
                Image {
                    x: 8; y: 8; width: parent.width - 16; height: 140
                    source: Url.fromPath(card.modelData.thumb)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
                Column {
                    x: 18; y: 160
                    spacing: 10
                    Text {
                        text: card.modelData.pal.label
                        font.family: Theme.titleFont; font.pixelSize: Theme.titleSize(22)
                        color: card.colors.fg
                    }
                    Row {
                        spacing: 6
                        Repeater {
                            model: [card.colors.accent, card.colors.accent2, card.colors.fg]
                            Rectangle { required property string modelData; width: 22; height: 22; radius: 11; color: modelData }
                        }
                    }
                }
                Text {
                    visible: card.modelData.current || card.modelData.user
                    anchors { right: parent.right; rightMargin: 14; bottom: parent.bottom; bottomMargin: 16 }
                    text: card.modelData.current ? "сейчас" : card.modelData.catalog ? "каталог" : "своя"
                    font.family: Theme.bodyFont; font.pixelSize: 13
                    color: card.modelData.current ? card.colors.accent : card.colors.muted
                }
                MouseArea {
                    id: area
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: page.ownThemes.selected = card.modelData.name
                    onDoubleClicked: page.themeEdit.open(card.modelData)
                }
            }
        }
    }

    ThemeEditor {
        anchors.fill: parent
        visible: page.themeEdit.editing !== null
        themeEdit: page.themeEdit
        userFiles: page.userFiles
        ownThemes: page.ownThemes
        onSwitched: page.switched()
    }
    OwnThemeDialog {
        anchors.fill: parent
        visible: page.ownThemes.dialog !== "" && page.ownThemes.dialog !== "catalog"
        themeEdit: page.themeEdit
        ownThemes: page.ownThemes
    }
    CatalogDialog {
        anchors.fill: parent
        visible: page.ownThemes.dialog === "catalog"
        ownThemes: page.ownThemes
    }
}
