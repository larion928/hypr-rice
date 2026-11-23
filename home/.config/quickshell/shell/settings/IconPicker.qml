import QtQuick
import qs.common

// The icon picker for themeEdit.iconFor: every icon of the font, searched by name. A click chooses, «Применить»
// sets it; «Отмена» or Esc leave the icon as it was.
Rectangle {
    id: picker
    required property ThemeEditStore themeEdit
    property string hovered: ""   // the name of the icon under the pointer
    readonly property var foundIcons: {
        const words = themeEdit.iconQuery.toLowerCase().split(/\s+/).filter(word => word);
        if (!words.length) {
            return themeEdit.allIcons;
        }
        return themeEdit.allIcons.filter(([, name]) => words.every(word => name.includes(word)));
    }

    color: Theme.bg
    onVisibleChanged: if (visible) iconSearch.text = themeEdit.iconQuery
    MouseArea { anchors.fill: parent }
    Row {
        id: pickerTop
        spacing: 12
        SectionTitle {
            anchors.verticalCenter: parent.verticalCenter
            text: "Значок: " + themeEdit.moduleName(themeEdit.iconFor)
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: (themeEdit.iconOf(themeEdit.iconFor) || "·") + "  →  "
                  + (themeEdit.iconChoice || themeEdit.ownIcon(themeEdit.iconFor) || "·")
            font.family: Theme.glyphFont; font.pixelSize: 24
            color: Theme.accent
        }
        Field {
            id: iconSearch
            anchors.verticalCenter: parent.verticalCenter
            width: 300
            placeholder: "поиск по-английски: volume, cpu, wifi…"
            onTextChanged: themeEdit.iconQuery = text
        }
    }
    Row {
        anchors { right: parent.right; verticalCenter: pickerTop.verticalCenter }
        spacing: 10
        Chip { text: "Как в теме"; active: themeEdit.iconChoice === ""; onClicked: themeEdit.iconChoice = "" }
        Chip { text: "Отмена"; onClicked: themeEdit.iconFor = "" }
        Chip { text: "Применить"; primary: true; onClicked: themeEdit.applyIcon() }
    }
    Text {
        id: pickerStatus
        anchors { left: parent.left; top: pickerTop.bottom; topMargin: 10 }
        text: !themeEdit.allIcons.length ? "загружаю значки шрифта…"
              : picker.foundIcons.length + " значков · нажми, чтобы выбрать, двойной щелчок сразу применяет"
                + (picker.hovered ? " · " + picker.hovered : "")
                + (["pulseaudio", "temperature", "backlight", "battery"].includes(themeEdit.iconFor)
                   ? " · у этого модуля значок меняется по уровню, свой будет один на все уровни" : "")
        font.family: Theme.bodyFont; font.pixelSize: 13
        color: Theme.muted
    }
    GridView {
        anchors { left: parent.left; right: parent.right; top: pickerStatus.bottom; bottom: parent.bottom; topMargin: 10 }
        clip: true
        cellWidth: 52; cellHeight: 52
        boundsBehavior: Flickable.StopAtBounds
        model: picker.foundIcons
        delegate: Rectangle {
            id: iconCell
            required property var modelData
            readonly property bool picked: themeEdit.iconChoice === modelData[0]
            width: 48; height: 48
            radius: 8
            color: picked ? Theme.alpha(Theme.accent, 0.3)
                   : (cellArea.containsMouse ? Theme.alpha(Theme.accent, 0.14) : Theme.alpha(Theme.bg2, 0.8))
            border.color: picked ? Theme.accent : "transparent"
            Text {
                anchors.centerIn: parent
                text: iconCell.modelData[0]
                font.family: Theme.glyphFont; font.pixelSize: 24
                color: iconCell.picked ? Theme.accent : Theme.fg
            }
            MouseArea {
                id: cellArea
                anchors.fill: parent
                hoverEnabled: true
                onEntered: picker.hovered = iconCell.modelData[1]
                onClicked: themeEdit.iconChoice = iconCell.modelData[0]
                onDoubleClicked: {
                    themeEdit.iconChoice = iconCell.modelData[0];
                    themeEdit.applyIcon();
                }
            }
        }
    }
}
