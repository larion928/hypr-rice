import QtQuick
import qs.common
import "../common/url.js" as Url

// A moment of a GIF or a video picked with a slider, then kept as one of the theme's wallpapers.
Rectangle {
    id: picker
    required property UserFiles userFiles

    color: Theme.alpha(Theme.bg, 0.92)
    MouseArea { anchors.fill: parent }
    Column {
        anchors.centerIn: parent
        width: Math.min(parent.width - 60, 980)
        spacing: 14
        SectionTitle { text: "Кадр для обоев" }
        Text {
            width: parent.width
            elide: Text.ElideMiddle
            text: userFiles.frameSource
            font.family: Theme.font; font.pixelSize: 12
            color: Theme.muted
        }
        Rectangle {
            width: parent.width; height: width * 9 / 16
            radius: Theme.rounded ? 10 : 0
            color: Theme.bg2
            clip: true
            Image {
                anchors.fill: parent
                source: Url.fromPath(userFiles.framePreview)
                fillMode: Image.PreserveAspectFit
                cache: false
            }
        }
        Row {
            spacing: 14
            NumberSlider {
                anchors.verticalCenter: parent.verticalCenter
                width: 640
                from: 0; to: userFiles.frameEnd()
                step: userFiles.frameLength && userFiles.frameLength.kind === "gif" ? 1 : 0.1
                value: userFiles.frameAt
                onMoved: value => userFiles.showFrame(value)
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: userFiles.frameLabel()
                font.family: Theme.font; font.pixelSize: 14
                color: Theme.fg
            }
        }
        Row {
            spacing: 10
            Chip {
                text: "Взять этот кадр"
                primary: true
                enabled: userFiles.framePreview !== "" && userFiles.frameInput !== "" && !userFiles.working
                onClicked: userFiles.takeFrame()
            }
            Chip { text: "Отмена"; onClicked: userFiles.closeFrames() }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: userFiles.pickFor === "frames" ? userFiles.message : ""
                font.family: Theme.bodyFont; font.pixelSize: 13
                color: userFiles.failed ? Theme.crit : Theme.muted
            }
        }
    }
}
