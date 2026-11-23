// Phone menu (waybar custom/phone, phone-panel): the KDE Connect phone the bar shows, its battery, what can be
// done with it, its pairing, and the other phones to switch to. Which phone is shown is Phones' choice
// (services/Phones.qml), shared with the bar.
import QtQuick
import QtQuick.Effects
import qs.common
import qs.services

OverlayPanel {
    id: menu

    readonly property var device: Phones.current
    readonly property bool usable: !!device && device.paired && device.reachable

    namespace: "phone-panel"
    dim: 0.25
    fadeInMs: 160
    fadeOutMs: 140

    // What the menu says instead of a phone, or "" when there is one to show.
    function emptyText() {
        if (!Phones.enabled) {
            return "KDE Connect выключен: Alt+F2 → Функции → Телефон.";
        }
        if (!Phones.running) {
            return "KDE Connect запускается…";
        }
        return device ? "" : "Телефон не найден. Откройте KDE Connect на телефоне в той же сети Wi-Fi.";
    }

    function statusText(phone) {
        if (!phone.reachable) {
            return "не на связи";
        }
        if (!phone.battery) {
            return "на связи";
        }
        return "на связи · " + phone.battery.charge + "%" + (phone.battery.charging ? ", заряжается" : "");
    }

    Rectangle {
        id: card
        anchors { top: parent.top; right: parent.right; topMargin: menu.shown ? 50 : 34; rightMargin: 14 }
        Behavior on anchors.topMargin { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        width: 400
        height: content.implicitHeight + 36
        radius: Theme.radius(18)
        color: Theme.alpha(Theme.bg, 0.96)
        border.width: Theme.border
        border.color: Theme.alpha(Theme.accent, Theme.ui.glow ? 0.9 : 0.4)
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Theme.ui.glow ? Theme.accent : "#000000"
            shadowBlur: 0.8; shadowVerticalOffset: Theme.ui.glow ? 0 : 8; blurMax: 32
        }
        MouseArea { anchors.fill: parent }   // clicks inside do not close

        Column {
            id: content
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 18 }
            spacing: 14

            Text {
                text: Theme.title("Телефон")
                font.family: Theme.titleFont; font.pixelSize: Theme.titleSize(24); font.bold: true; font.italic: Theme.italicTitle
                color: Theme.fg
            }

            Text {
                visible: text !== ""
                width: parent.width
                wrapMode: Text.WordWrap
                text: menu.emptyText()
                font.family: Theme.bodyFont; font.pixelSize: 13
                color: Theme.muted
            }

            Row {
                visible: !!menu.device
                width: parent.width
                spacing: 12
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Phones.phoneGlyph
                    font.family: Theme.glyphFont; font.pixelSize: 30
                    color: menu.usable ? Theme.accent : Theme.muted
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 42
                    spacing: 2
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: menu.device ? menu.device.name : ""
                        font.family: Theme.bodyFont; font.pixelSize: 16; font.bold: true
                        color: Theme.fg
                    }
                    Text {
                        text: menu.device ? menu.statusText(menu.device) : ""
                        font.family: Theme.bodyFont; font.pixelSize: 13
                        color: Theme.muted
                    }
                }
            }

            Flow {
                visible: menu.usable
                width: parent.width
                spacing: 8
                Chip { glyph: "\u{f0952}"; text: "Найти телефон"; onClicked: Phones.act("ring", menu.device) }
                Chip { glyph: "\u{f009e}"; text: "Пинг"; onClicked: Phones.act("ping", menu.device) }
                Chip { glyph: "\u{f022a}"; text: "Отправить файлы"; onClicked: Phones.actSlowly("share", menu.device) }
                Chip { glyph: "\u{f0192}"; text: "Отправить буфер"; onClicked: Phones.act("clipboard", menu.device) }
                Chip {
                    glyph: "\u{f0770}"; text: "Файлы телефона"
                    onClicked: { Phones.actSlowly("browse", menu.device); menu.close(); }
                }
            }

            PairingRow {
                visible: !!menu.device && !menu.device.paired && menu.device.reachable
                width: parent.width
                device: menu.device
            }

            Text {
                visible: Phones.message !== ""
                width: parent.width
                wrapMode: Text.WordWrap
                text: Phones.message
                font.family: Theme.bodyFont; font.pixelSize: 13
                color: Theme.crit
            }

            Column {
                visible: Phones.devices.length > 1
                width: parent.width
                spacing: 6
                SectionTitle { text: "Устройства" }
                Repeater {
                    model: Phones.devices
                    DeviceRow {
                        required property var modelData
                        width: parent.width
                        device: modelData
                        status: menu.statusText(modelData) + (modelData.paired ? "" : " · не сопряжён")
                        current: !!menu.device && modelData.id === menu.device.id
                        onPicked: Phones.pick(modelData)
                    }
                }
            }

            Chip {
                visible: !!menu.device && menu.device.paired
                text: "Разорвать сопряжение"
                danger: true
                onClicked: Phones.act("unpair", menu.device)
            }
        }
    }
}
