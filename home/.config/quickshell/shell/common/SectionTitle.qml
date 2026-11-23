import QtQuick

// A heading inside a menu, in the theme's title style.
Text {
    font.family: Theme.titleFont
    font.pixelSize: Theme.titleSize(17)
    font.bold: true
    font.italic: Theme.italicTitle
    color: Theme.accent2
}
