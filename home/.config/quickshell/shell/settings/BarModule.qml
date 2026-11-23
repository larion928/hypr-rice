import QtQuick
import qs.common

// One module on the bar or in the set below it, as its icon (with its name in the set); drag it.
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
    width: moduleContent.implicitWidth + 22; height: 36
    radius: 8
    color: moduleArea.containsMouse ? Theme.alpha(Theme.accent, 0.18) : Theme.alpha(Theme.bg2, 0.9)
    border.color: shows === "missing" ? Theme.alpha(Theme.crit, 0.6) : Theme.alpha(Theme.muted, 0.3)
    opacity: lifted ? 0.25 : shows === "missing" ? 0.4 : shows === "sometimes" ? 0.6 : 1
    ModuleLabel {
        id: moduleContent
        anchors.centerIn: parent
        themeEdit: barModule.themeEdit
        module: barModule.modelData
        showName: barModule.showName
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
