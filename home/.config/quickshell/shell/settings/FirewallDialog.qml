import QtQuick
import qs.common

// Switching on a feature whose ports ufw keeps closed (KDE Connect's 1714-1764): open them first, or switch it on
// as it is. Opening asks the administrator password in the rice's polkit window.
Rectangle {
    id: dialog
    required property FeaturesModel features
    readonly property var feature: features.firewall

    color: Theme.alpha(Theme.bg, 0.92)
    MouseArea { anchors.fill: parent }
    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 620); height: firewallColumn.implicitHeight + 48
        radius: Theme.radius(22)
        color: Theme.bg2
        border.color: Theme.accent
        Column {
            id: firewallColumn
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24 }
            spacing: 12
            SectionTitle {
                text: dialog.feature ? "Брандмауэр — «" + dialog.feature.name + "»" : ""
            }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: !dialog.feature ? ""
                      : "ufw не пропускает порты " + dialog.feature.closedPorts.join(", ")
                        + ": без них устройства в сети не найдут этот компьютер. Открыть их? Понадобится пароль "
                        + "администратора."
                font.family: Theme.bodyFont; font.pixelSize: 14
                color: Theme.fg
            }
            Row {
                visible: !dialog.features.openingPorts
                spacing: 10
                Chip { text: "Открыть порты"; primary: true; onClicked: dialog.features.openPorts() }
                Chip { text: "Включить без них"; onClicked: dialog.features.keepPortsClosed() }
                Chip { text: "Отмена"; onClicked: dialog.features.firewall = null }
            }
            Text {
                visible: dialog.features.openingPorts
                text: "Жду пароль администратора…"
                font.family: Theme.bodyFont; font.pixelSize: 14
                color: Theme.accent
            }
        }
    }
}
