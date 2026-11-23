import QtQuick
import qs.common

// A panel module in the layout editor: its icon, and its name when asked for or when it has no icon.
Row {
    id: moduleLabel
    required property ThemeEditStore themeEdit
    required property string module
    property bool showName: false
    readonly property string icon: themeEdit.iconOf(module)
    spacing: 7

    Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: moduleLabel.icon !== ""
        text: moduleLabel.icon
        font.family: Theme.glyphFont; font.pixelSize: 17
        color: Theme.fg
    }
    Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: moduleLabel.showName || moduleLabel.icon === ""
        text: moduleLabel.themeEdit.moduleName(moduleLabel.module)
        font.family: Theme.bodyFont; font.pixelSize: 14
        color: Theme.fg
    }
}
