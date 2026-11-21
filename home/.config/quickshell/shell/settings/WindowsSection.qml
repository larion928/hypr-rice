import QtQuick
import qs.common
import "../common/url.js" as Url

// Hyprland's windows: sliders on the left, two windows drawn with those values on the right.
Item {
    id: section
    required property ThemeEditStore themeEdit

    Column {
        id: windowControls
        width: 700
        spacing: 10
        Repeater {
            model: themeEdit.windowSettings
            Item {
                id: settingRow
                required property var modelData
                readonly property string key: modelData[0]
                readonly property bool percent: modelData[5] === "%"
                readonly property bool edited: themeEdit.editing !== null && settingRow.key in themeEdit.edit.windows
                width: windowControls.width; height: 34
                function shown(value) {
                    return settingRow.percent ? Math.round(value * 100) + "%" : value + (settingRow.modelData[5] ? " " + settingRow.modelData[5] : "");
                }
                Text {
                    width: 250; anchors.verticalCenter: parent.verticalCenter
                    text: settingRow.modelData[1]
                    font.family: Theme.bodyFont; font.pixelSize: 14
                    color: Theme.fg
                }
                NumberSlider {
                    id: rowSlider
                    x: 255; width: 200; anchors.verticalCenter: parent.verticalCenter
                    from: settingRow.modelData[2]; to: settingRow.modelData[3]; step: settingRow.modelData[4]
                    value: themeEdit.editing ? themeEdit.windowValue(settingRow.key) : 0
                    onMoved: value => themeEdit.setWindow(settingRow.key, value)
                }
                Text {
                    x: 470; anchors.verticalCenter: parent.verticalCenter
                    text: themeEdit.editing ? settingRow.shown(themeEdit.windowValue(settingRow.key)) : ""
                    font.family: Theme.font; font.pixelSize: 14
                    color: settingRow.edited ? Theme.accent : Theme.fg
                }
                Text {
                    x: 535; anchors.verticalCenter: parent.verticalCenter
                    text: settingRow.edited ? "↺ тема: " + settingRow.shown(themeEdit.editing.windows[settingRow.key]) : ""
                    font.family: Theme.bodyFont; font.pixelSize: 12
                    color: Theme.muted
                    MouseArea { anchors.fill: parent; onClicked: themeEdit.setWindow(settingRow.key, themeEdit.editing.windows[settingRow.key]) }
                }
            }
        }
        Row {
            spacing: 8
            Text {
                width: 250; anchors.verticalCenter: parent.verticalCenter
                text: "Размытие под окнами"
                font.family: Theme.bodyFont; font.pixelSize: 14
                color: Theme.fg
            }
            Chip { text: "Вкл"; active: themeEdit.editing !== null && !!themeEdit.windowValue("blur"); onClicked: themeEdit.setWindow("blur", true) }
            Chip { text: "Выкл"; active: themeEdit.editing !== null && !themeEdit.windowValue("blur"); onClicked: themeEdit.setWindow("blur", false) }
        }
        Row {
            spacing: 8
            Text {
                width: 250; anchors.verticalCenter: parent.verticalCenter
                text: "Анимации"
                font.family: Theme.bodyFont; font.pixelSize: 14
                color: Theme.fg
            }
            Repeater {
                model: [["", "Как в теме"], ["fast", "Быстрее"], ["slow", "Медленнее"], ["off", "Выключить"]]
                Chip {
                    required property var modelData
                    text: modelData[1]
                    active: themeEdit.editing !== null && (themeEdit.edit.windows.animations || "") === modelData[0]
                    onClicked: themeEdit.setAnimations(modelData[0])
                }
            }
        }
    }

    // Two windows over the theme's wallpaper, at the real gaps, border and rounding.
    Rectangle {
        id: windowsPreview
        anchors { left: windowControls.right; right: parent.right; top: parent.top; leftMargin: 28 }
        height: 320
        radius: 8
        clip: true
        color: Theme.bg2
        Image {
            anchors.fill: parent
            source: themeEdit.editing ? Url.fromPath(themeEdit.editing.thumb) : ""
            fillMode: Image.PreserveAspectCrop
        }
        Repeater {
            model: 2
            Rectangle {
                required property int index
                readonly property real outer: themeEdit.editing ? themeEdit.windowValue("gaps_out") : 0
                readonly property real inner: themeEdit.editing ? themeEdit.windowValue("gaps_in") : 0
                readonly property real half: (windowsPreview.width - 2 * outer - 2 * inner) / 2
                x: outer + index * (half + 2 * inner); y: outer + 26
                width: half; height: windowsPreview.height - 2 * outer - 26
                radius: themeEdit.editing ? themeEdit.windowValue("rounding") : 0
                color: Theme.alpha(Theme.bg, themeEdit.editing ? themeEdit.windowValue(index === 0 ? "active_opacity" : "inactive_opacity") : 1)
                border.width: themeEdit.editing ? themeEdit.windowValue("border_size") : 0
                border.color: index === 0 ? Theme.accent : Theme.alpha(Theme.muted, 0.67)
                Text {
                    anchors.centerIn: parent
                    text: index === 0 ? "активное окно" : "окно"
                    font.family: Theme.bodyFont; font.pixelSize: 13
                    color: Theme.fg
                }
            }
        }
        Rectangle {
            x: 8; y: 4; width: parent.width - 16; height: 18; radius: 5
            color: Theme.alpha(Theme.bg, 0.85)
            Text {
                anchors.centerIn: parent
                text: "панель"
                font.family: Theme.bodyFont; font.pixelSize: 10
                color: Theme.muted
            }
        }
    }
    Text {
        anchors { left: windowsPreview.left; right: windowsPreview.right; top: windowsPreview.bottom; topMargin: 10 }
        wrapMode: Text.WordWrap
        text: "Образец в настоящих пикселях. Размытие и анимации видны только на экране: сохрани, тема применится заново."
        font.family: Theme.bodyFont; font.pixelSize: 12
        color: Theme.muted
    }
}
