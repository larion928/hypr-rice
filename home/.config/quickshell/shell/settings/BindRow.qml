import QtQuick
import qs.common

// One hotkey: what it does, its combo, and change / on-off / reset (or remove, for an own bind).
Rectangle {
    id: row

    required property KeysModel keys
    property string title
    property string combo
    property bool isDefault
    property bool capturing
    property bool removable
    property string emptyLabel   // what no key reads as; keys.label's "выключено" without it

    signal edit()
    signal toggle()
    signal reset()
    signal remove()

    height: 44
    radius: Theme.rounded ? 10 : 0
    color: capturing ? Theme.alpha(Theme.accent, 0.15) : Theme.alpha(Theme.bg2, 0.6)
    border.color: capturing ? Theme.accent : "transparent"

    Text {
        anchors { left: parent.left; leftMargin: 14; right: buttons.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
        text: row.title
        elide: Text.ElideRight
        font.family: Theme.bodyFont; font.pixelSize: 14
        color: row.combo ? Theme.fg : Theme.muted
    }
    Row {
        id: buttons
        anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
        spacing: 8
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(110, comboText.implicitWidth + 20); height: 28
            radius: Theme.rounded ? 7 : 0
            color: Theme.alpha(Theme.accent, row.combo ? 0.16 : 0.05)
            border.color: Theme.alpha(Theme.accent, row.isDefault ? 0.45 : 0.9)
            Text {
                id: comboText
                anchors.centerIn: parent
                text: row.capturing ? "…" : (!row.combo && row.emptyLabel ? row.emptyLabel : row.keys.label(row.combo))
                font.family: Theme.glyphFont; font.pixelSize: 13
                color: row.combo ? Theme.accent : Theme.muted
            }
        }
        Chip { visible: !row.removable; text: "Изменить"; onClicked: row.edit() }
        Chip { visible: !row.removable; text: row.combo ? "Выкл" : "Вкл"; onClicked: row.toggle() }
        Chip { visible: !row.removable && !row.isDefault; text: "Сброс"; onClicked: row.reset() }
        Chip { visible: row.removable; text: "Удалить"; onClicked: row.remove() }
    }
}
