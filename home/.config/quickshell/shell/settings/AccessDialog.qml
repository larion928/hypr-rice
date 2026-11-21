import QtQuick
import qs.common

// Switching on a feature that needs what the system does not allow yet: ports ufw keeps closed (KDE Connect's
// 1714-1764), a group the user is not in (input, to read the keyboard). Allow it first, or switch the feature on
// as it is. Allowing asks the administrator password in the rice's polkit window.
Rectangle {
    id: dialog
    required property FeaturesModel features
    readonly property var feature: features.asking

    function reasons(feature) {
        const lines = [];
        if (feature.closedPorts.length) {
            lines.push("ufw не пропускает порты " + feature.closedPorts.join(", ")
                       + ": без них устройства в сети не найдут этот компьютер.");
        }
        if (feature.missingGroups.length) {
            lines.push("Нужна группа " + feature.missingGroups.join(", ") + ": с ней райс читает клавиатуру. "
                       + "Читать нажатия сможет и любая другая твоя программа. Заработает после повторного входа.");
        }
        return lines.join("\n\n");
    }

    color: Theme.alpha(Theme.bg, 0.92)
    MouseArea { anchors.fill: parent }
    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 620); height: accessColumn.implicitHeight + 48
        radius: Theme.radius(22)
        color: Theme.bg2
        border.color: Theme.accent
        Column {
            id: accessColumn
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24 }
            spacing: 12
            SectionTitle {
                text: dialog.feature ? "Разрешения — «" + dialog.feature.name + "»" : ""
            }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: dialog.feature ? dialog.reasons(dialog.feature) + "\n\nРазрешить? Понадобится пароль администратора." : ""
                font.family: Theme.bodyFont; font.pixelSize: 14
                color: Theme.fg
            }
            Row {
                visible: !dialog.features.granting
                spacing: 10
                Chip { text: "Разрешить"; primary: true; onClicked: dialog.features.grant() }
                Chip { text: "Включить без этого"; onClicked: dialog.features.switchOnWithout() }
                Chip { text: "Отмена"; onClicked: dialog.features.asking = null }
            }
            Text {
                visible: dialog.features.granting
                text: "Жду пароль администратора…"
                font.family: Theme.bodyFont; font.pixelSize: 14
                color: Theme.accent
            }
        }
    }
}
