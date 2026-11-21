import QtQuick
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import qs.common
import "../common/url.js" as Url

// One module as it looks on the bar; drag it. With showName (the set below the bar) its name is
// written next to it.
Rectangle {
    id: barModule
    required property ThemeEditStore themeEdit

    required property string modelData
    required property int index
    property var editor
    property string side
    property bool showName: false
    readonly property string pillModule: modelData
    readonly property bool lifted: editor.drag !== null && editor.drag.side === side && editor.drag.index === index && side !== ""
    readonly property string shows: themeEdit.moduleState(modelData)  // shown, sometimes or missing
    readonly property bool tray: modelData === "tray"
    width: moduleContent.implicitWidth + 22; height: 36
    radius: 8
    color: moduleArea.containsMouse ? Theme.alpha(Theme.accent, 0.18) : Theme.alpha(Theme.bg2, 0.9)
    border.color: shows === "missing" ? Theme.alpha(Theme.crit, 0.6) : Theme.alpha(Theme.muted, 0.3)
    opacity: lifted ? 0.25 : shows === "missing" ? 0.4 : shows === "sometimes" ? 0.6 : 1
    Row {
        id: moduleContent
        anchors.centerIn: parent
        spacing: 6
        // The tray's real icons; waybar draws nothing for an empty tray.
        Repeater {
            model: barModule.tray ? SystemTray.items : []
            IconImage {
                required property var modelData
                anchors.verticalCenter: parent.verticalCenter
                implicitSize: 16
                source: modelData.icon
            }
        }
        // The theme's battery icon, which its CSS puts in front of the percentage.
        Image {
            visible: barModule.modelData === "custom/battery" && themeEdit.editing !== null
            anchors.verticalCenter: parent.verticalCenter
            width: visible ? 16 : 0; height: 16
            sourceSize: Qt.size(32, 32)
            source: visible ? Url.fromPath(themeEdit.editing.dir + "/assets/battery-0.svg") : ""
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: (barModule.tray && SystemTray.items.values.length === 0 ? "трей пуст"
                   : barModule.tray ? "" : themeEdit.preview(barModule.modelData))
                  + (barModule.showName ? "  " + themeEdit.moduleName(barModule.modelData) : "")
            visible: text !== ""
            font.family: Theme.font; font.pixelSize: 15
            color: Theme.fg
        }
    }
    Text {
        visible: moduleArea.containsMouse && barModule.side !== "" && themeEdit.iconEditable(barModule.modelData)
        anchors { right: parent.right; top: parent.top; rightMargin: -5; topMargin: -7 }
        text: "\u{f03eb}"  // md-pencil
        font.family: Theme.glyphFont; font.pixelSize: 13
        color: Theme.accent
    }
    MouseArea {
        id: moduleArea
        anchors.fill: parent
        hoverEnabled: true
        preventStealing: true
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        onEntered: barModule.editor.hovered = barModule.modelData
        onExited: if (barModule.editor.hovered === barModule.modelData) barModule.editor.hovered = ""
        onPressed: mouse => barModule.editor.start(barModule.modelData, barModule.side, barModule.index,
                                                   mapToItem(barModule.editor, mouse.x, mouse.y))
        onPositionChanged: mouse => { if (pressed) barModule.editor.follow(mapToItem(barModule.editor, mouse.x, mouse.y)); }
        onReleased: barModule.editor.finish()
    }
}
