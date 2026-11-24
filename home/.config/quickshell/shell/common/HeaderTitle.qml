import QtQuick
import "url.js" as Url

// A menu's title with the theme's mark in front: its picture (ui.json headerIcon, a still or an animated one),
// else its glyph (headerGlyph). A menu with a mark of its own gives a Nerd Font icon instead.
Row {
    id: header

    property string text
    property int size: 28
    property int markSize: size - 2
    property string icon: ""
    property string fallbackGlyph: "•"
    property bool spinning: false

    readonly property bool themePicture: !icon && !!Theme.ui.headerIcon
    readonly property string picture: themePicture ? Url.fromPath(Theme.dir + "/" + Theme.ui.headerIcon) : ""
    // An animated picture (GIF, WebP) plays once as the menu opens, then rests on its first frame.
    readonly property bool animated: /\.(gif|webp)$/i.test(Theme.ui.headerIcon || "")

    spacing: 14

    Item {
        visible: header.themePicture
        anchors.verticalCenter: parent.verticalCenter
        width: header.markSize
        height: header.markSize
        RotationAnimation on rotation {
            running: header.spinning
            from: 0
            to: 360
            duration: 12000
            loops: Animation.Infinite
        }
        Image {
            visible: !header.animated
            anchors.fill: parent
            sourceSize: Qt.size(header.markSize * 2, header.markSize * 2)
            source: header.animated ? "" : header.picture
        }
        AnimatedImage {
            visible: header.animated
            anchors.fill: parent
            source: header.animated ? header.picture : ""
            onCurrentFrameChanged: {
                if (frameCount > 1 && currentFrame === frameCount - 1) {
                    playing = false;
                    currentFrame = 0;
                }
            }
        }
    }
    Text {
        visible: !header.themePicture
        anchors.verticalCenter: parent.verticalCenter
        text: header.icon || Theme.ui.headerGlyph || header.fallbackGlyph
        font.family: header.icon ? Theme.glyphFont : Theme.titleFont
        font.pixelSize: header.markSize
        font.bold: !header.icon
        color: Theme.accent
    }
    Item {
        visible: header.text !== ""
        anchors.verticalCenter: parent.verticalCenter
        width: title.implicitWidth
        height: title.implicitHeight

        // ui.json headerFringe: a faint red copy 2 px to the left and a cyan one to the right, the colour fringe
        // round the letters of a lit screen. At 1 px the antialiased letter edge covered it.
        Repeater {
            model: Theme.ui.headerFringe ? [{ colour: "#ff3030", shift: -2 }, { colour: "#30e0ff", shift: 2 }] : []
            Text {
                required property var modelData
                x: modelData.shift
                text: title.text
                font: title.font
                color: modelData.colour
                opacity: 0.5
            }
        }
        Text {
            id: title
            text: Theme.title(header.text)
            font.family: Theme.titleFont
            font.pixelSize: header.size
            font.italic: Theme.italicTitle
            color: Theme.fg
        }
    }
}
