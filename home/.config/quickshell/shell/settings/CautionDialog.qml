import QtQuick
import qs.common

// Switching on a feature that may get in the way when it goes wrong (the input features type keys themselves, an
// experimental one is still being tried out): its warning, and how to switch it off again even when the keyboard
// is what it broke.
Rectangle {
    id: dialog
    required property FeaturesModel features
    readonly property var feature: features.cautioning

    color: Theme.alpha(Theme.bg, 0.92)
    MouseArea { anchors.fill: parent }
    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 620); height: cautionColumn.implicitHeight + 48
        radius: Theme.radius(22)
        color: Theme.bg2
        border.color: Theme.warn
        Column {
            id: cautionColumn
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24 }
            spacing: 12
            SectionTitle {
                text: dialog.feature ? "Включить «" + dialog.feature.name + "»?" : ""
            }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: dialog.feature ? dialog.feature.caution : ""
                font.family: Theme.bodyFont; font.pixelSize: 14
                color: Theme.fg
            }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: dialog.feature ? "Выключить: здесь, в Функциях (мышью: шестерёнка на панели), или в терминале "
                                       + "rice features off " + dialog.feature.id : ""
                font.family: Theme.bodyFont; font.pixelSize: 13
                color: Theme.muted
            }
            Row {
                spacing: 10
                Chip { text: "Включить"; primary: true; onClicked: dialog.features.acceptCaution() }
                Chip { text: "Отмена"; onClicked: dialog.features.cautioning = null }
            }
        }
    }
}
