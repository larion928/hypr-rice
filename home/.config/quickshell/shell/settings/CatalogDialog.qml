import QtQuick
import qs.common
import qs.services
import "../common/url.js" as Url

// The theme catalog over the theme list: its packs, each theme with a picture and what can be done with it here.
Rectangle {
    id: catalogDialog
    required property OwnThemes ownThemes

    readonly property var actions: ({
        "absent": "Поставить",
        "changed": "Обновить",
        "installed": "Удалить"
    })
    function act(theme) {
        if (theme.state === "installed") {
            ownThemes.removeNamed(theme.name);
        } else {
            ownThemes.installFromCatalog(theme.name);
        }
    }

    color: Theme.alpha(Theme.bg, 0.85)
    MouseArea { anchors.fill: parent }  // the page under it waits

    Rectangle {
        anchors { fill: parent; margins: 24 }
        radius: Theme.radius(14)
        color: Theme.bg2
        border.color: Theme.alpha(Theme.accent, 0.5)

        Column {
            id: top
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24 }
            spacing: 10
            SectionTitle { text: "Темы из каталога" }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: "Темы, которые автор райса прочитал и подписал. Тема скачивается с GitHub и ставится, только если сходится с подписью. Удалённую тему можно поставить снова."
                font.family: Theme.bodyFont; font.pixelSize: 14
                color: Theme.fg
            }
        }

        Flickable {
            anchors { left: parent.left; right: parent.right; top: top.bottom; bottom: bottom.top; margins: 24 }
            contentHeight: packColumn.implicitHeight
            clip: true
            Column {
                id: packColumn
                width: parent.width
                spacing: 22
                Repeater {
                    model: catalogDialog.ownThemes.packs
                    Column {
                        id: pack
                        required property var modelData
                        width: packColumn.width
                        spacing: 10
                        Row {
                            spacing: 14
                            SectionTitle { text: pack.modelData.label; font.pixelSize: Theme.titleSize(18) }
                            Chip {
                                visible: pack.modelData.themes.some(theme => theme.state === "absent")
                                text: "Поставить все"
                                enabled: !catalogDialog.ownThemes.busy
                                onClicked: catalogDialog.ownThemes.installFromCatalog(pack.modelData.id)
                            }
                        }
                        Text {
                            visible: text !== ""
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: pack.modelData.about
                            font.family: Theme.bodyFont; font.pixelSize: 13
                            color: Theme.muted
                        }
                        Flow {
                            width: parent.width
                            spacing: 16
                            Repeater {
                                model: pack.modelData.themes
                                ThemeOffer {}
                            }
                        }
                    }
                }
            }
        }

        Row {
            id: bottom
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 24 }
            spacing: 10
            Text {
                width: parent.width - closeChip.width - parent.spacing
                anchors.verticalCenter: parent.verticalCenter
                wrapMode: Text.WordWrap
                text: catalogDialog.ownThemes.busy || catalogDialog.ownThemes.error
                font.family: Theme.bodyFont; font.pixelSize: 13
                color: catalogDialog.ownThemes.error ? Theme.crit : Theme.muted
            }
            Chip {
                id: closeChip
                text: "Закрыть"
                enabled: !catalogDialog.ownThemes.busy
                onClicked: catalogDialog.ownThemes.dialog = ""
            }
        }
    }

    // One theme of a pack: its picture, its name, and the one thing to do with it.
    component ThemeOffer: Rectangle {
        id: offer
        required property var modelData
        readonly property bool current: ThemeList.themes.some(theme => theme.current && theme.name === modelData.name)
        width: 280; height: 214
        radius: Theme.radius(14)
        color: Theme.bg
        border.width: 1
        border.color: Theme.alpha(Theme.accent, 0.5)
        clip: true
        Image {
            x: 8; y: 8; width: parent.width - 16; height: 140
            source: Url.fromPath(offer.modelData.preview)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }
        Text {
            x: 18; y: 164
            width: parent.width - 36 - action.width
            elide: Text.ElideRight
            text: offer.modelData.label
            font.family: Theme.titleFont; font.pixelSize: Theme.titleSize(20)
            color: Theme.fg
        }
        Chip {
            id: action
            anchors { right: parent.right; rightMargin: 14; bottom: parent.bottom; bottomMargin: 16 }
            visible: offer.modelData.state in catalogDialog.actions && !offer.current
            primary: offer.modelData.state !== "installed"
            text: catalogDialog.actions[offer.modelData.state] || ""
            enabled: !catalogDialog.ownThemes.busy
            onClicked: catalogDialog.act(offer.modelData)
        }
        Text {
            visible: !action.visible
            anchors { right: parent.right; rightMargin: 14; bottom: parent.bottom; bottomMargin: 18 }
            text: offer.current ? "сейчас" : "имя занято"
            font.family: Theme.bodyFont; font.pixelSize: 13
            color: offer.current ? Theme.accent : Theme.muted
        }
    }
}
