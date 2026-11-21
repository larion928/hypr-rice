import QtQuick
import qs.common
import "../common/url.js" as Url

// The wallpapers changetheme picks from: click one to switch it on or off.
// Wallpaper Engine's subscribed wallpapers: a video one is added to the theme with a click; scenes and
// web wallpapers are programs, shown but not added.
Rectangle {
    id: enginePicker
    required property UserFiles userFiles

    readonly property var kinds: ({ video: "видео", scene: "сцена · пока нельзя", web: "веб · пока нельзя",
                                    application: "программа · нельзя" })
    color: Theme.alpha(Theme.bg, 0.92)
    MouseArea { anchors.fill: parent }
    Row {
        id: engineHeader
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
        spacing: 14
        SectionTitle { text: "Wallpaper Engine" }
        Chip { anchors.verticalCenter: parent.verticalCenter; text: "Готово"; onClicked: userFiles.engineOpen = false }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 420
            elide: Text.ElideRight
            text: userFiles.pickFor === "engine" ? userFiles.message : ""
            font.family: Theme.bodyFont; font.pixelSize: 13
            color: userFiles.failed ? Theme.crit : Theme.muted
        }
    }
    Text {
        anchors { left: parent.left; right: parent.right; top: engineHeader.bottom; margins: 8; topMargin: 24 }
        visible: userFiles.engine !== null && !userFiles.engine.items.length
        wrapMode: Text.WordWrap
        text: !userFiles.engine ? "" : !userFiles.engine.installed
              ? "Wallpaper Engine не установлен в Steam. Он платный: купи и установи его, подпишись на обои в его Мастерской Steam, и Steam их скачает. Видеообои из подписок появятся здесь."
              : "Подписок нет: подпишись на обои в Мастерской Wallpaper Engine, Steam их скачает, и они появятся здесь."
        font.family: Theme.bodyFont; font.pixelSize: 15
        color: Theme.fg
    }
    GridView {
        anchors { left: parent.left; right: parent.right; top: engineHeader.bottom; bottom: parent.bottom; topMargin: 16 }
        clip: true
        cellWidth: 230; cellHeight: 200
        boundsBehavior: Flickable.StopAtBounds
        model: userFiles.engine ? userFiles.engine.items : []
        delegate: Item {
            id: engineItem
            required property var modelData
            readonly property bool added: userFiles.engineAdded.includes(modelData.id)
            width: 220; height: 190
            Rectangle {
                width: parent.width; height: 130
                radius: Theme.rounded ? 10 : 0
                clip: true
                color: Theme.bg2
                border.width: engineArea.containsMouse && engineItem.modelData.addable ? 2 : 0
                border.color: Theme.accent
                opacity: engineItem.modelData.addable ? 1 : 0.4
                Image {
                    anchors { fill: parent; margins: parent.border.width }
                    source: Url.fromPath(engineItem.modelData.preview)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
                MouseArea {
                    id: engineArea
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: engineItem.modelData.addable && !engineItem.added && !userFiles.working
                    onClicked: userFiles.addEngine(engineItem.modelData)
                }
            }
            Text {
                y: 136; width: parent.width
                elide: Text.ElideRight
                text: (engineItem.added ? "✓ " : "") + engineItem.modelData.title
                font.family: Theme.bodyFont; font.pixelSize: 14
                color: Theme.fg
            }
            Text {
                y: 158; width: parent.width
                elide: Text.ElideRight
                text: engineItem.added ? "добавлено в обои темы" : (enginePicker.kinds[engineItem.modelData.type] || engineItem.modelData.type)
                font.family: Theme.bodyFont; font.pixelSize: 12
                color: engineItem.modelData.addable ? Theme.accent : Theme.muted
            }
        }
    }
}
