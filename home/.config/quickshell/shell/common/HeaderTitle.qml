import QtQuick
import "url.js" as Url

// A menu's title with the theme's mark in front: its picture (ui.json headerIcon), else its glyph
// (headerGlyph). A menu with a mark of its own gives a Nerd Font icon instead.
Row {
    id: header

    property string text
    property int size: 28
    property int markSize: size - 2
    property string icon: ""
    property string fallbackGlyph: "•"
    property bool spinning: false

    readonly property bool themePicture: !icon && !!Theme.ui.headerIcon

    spacing: 14

    Image {
        visible: header.themePicture
        anchors.verticalCenter: parent.verticalCenter
        width: header.markSize
        height: header.markSize
        sourceSize: Qt.size(header.markSize * 2, header.markSize * 2)
        source: header.themePicture ? Url.fromPath(Theme.dir + "/" + Theme.ui.headerIcon) : ""
        RotationAnimation on rotation {
            running: header.spinning
            from: 0
            to: 360
            duration: 12000
            loops: Animation.Infinite
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
    Text {
        visible: header.text !== ""
        anchors.verticalCenter: parent.verticalCenter
        text: Theme.title(header.text)
        font.family: Theme.titleFont
        font.pixelSize: header.size
        font.italic: Theme.italicTitle
        color: Theme.fg
    }
}
