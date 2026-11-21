import QtQuick
import qs.common
import "../common/url.js" as Url

Item {
    id: section
    required property ThemeEditStore themeEdit
    required property UserFiles userFiles

    Row {
        id: wallpaperActions
        spacing: 10
        Chip { text: "Добавить обои"; onClicked: themeEdit.pickWallpaper() }
        Chip { text: "Кадр из GIF или видео…"; enabled: !userFiles.working; onClicked: userFiles.pick("frames") }
        Chip { text: "Из Wallpaper Engine…"; enabled: !userFiles.working; onClicked: userFiles.openEngine() }
        Text {
            readonly property bool news: userFiles.pickFor === "frames" && userFiles.message !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: news ? userFiles.message
                       : "Нажми на картинку, чтобы включить или выключить её; при смене темы обои выбираются случайно из включённых."
            font.family: Theme.bodyFont; font.pixelSize: 13
            color: news && userFiles.failed ? Theme.crit : Theme.muted
        }
    }
    GridView {
        anchors { left: parent.left; right: parent.right; top: wallpaperActions.bottom; bottom: parent.bottom; topMargin: 16 }
        clip: true
        cellWidth: 260; cellHeight: 196
        boundsBehavior: Flickable.StopAtBounds
        model: themeEdit.editing ? themeEdit.wallpapers() : []
        delegate: Item {
            id: wallTile
            required property var modelData
            width: 248; height: 184
            Rectangle {
                anchors { left: parent.left; right: parent.right; top: parent.top }
                height: 140
                radius: Theme.rounded ? 10 : 0
                clip: true
                color: Theme.bg2
                border.width: 2
                border.color: wallTile.modelData.on ? Theme.accent : Theme.alpha(Theme.muted, 0.3)
                Image {
                    anchors { fill: parent; margins: 2 }
                    source: Url.fromPath(wallTile.modelData.thumb)
                    sourceSize.width: 480
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    opacity: wallTile.modelData.on ? 1 : 0.3
                }
                // A GIF or a video plays on the desktop (a new one shows its picture once the theme is saved).
                Rectangle {
                    visible: /\.(gif|mp4|webm|mkv|mov|avi|m4v)$/i.test(wallTile.modelData.path)
                    anchors { left: parent.left; top: parent.top; margins: 8 }
                    width: animatedText.implicitWidth + 14; height: 22
                    radius: 6
                    color: Theme.alpha(Theme.bg, 0.85)
                    Text {
                        id: animatedText
                        anchors.centerIn: parent
                        text: "\u{f040a} анимация"
                        font.family: Theme.bodyFont; font.pixelSize: 12
                        color: Theme.accent
                    }
                }
                Text {
                    visible: !wallTile.modelData.on
                    anchors.centerIn: parent
                    text: "выключены"
                    font.family: Theme.bodyFont; font.pixelSize: 15; font.bold: true
                    color: Theme.fg
                }
                MouseArea { anchors.fill: parent; onClicked: themeEdit.toggleWallpaper(wallTile.modelData.path) }
            }
            Row {
                anchors { left: parent.left; bottom: parent.bottom }
                spacing: 6
                Chip {
                    visible: themeEdit.editing !== null && themeEdit.editing.current && wallTile.modelData.on
                    text: "Поставить сейчас"
                    onClicked: themeEdit.showWallpaper(wallTile.modelData.path)
                }
                Chip {
                    visible: wallTile.modelData.added
                    text: "Убрать"
                    onClicked: themeEdit.removeWallpaper(wallTile.modelData.path)
                }
            }
        }
    }
}
