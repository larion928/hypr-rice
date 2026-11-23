// Network panel (waybar network, launcher): Wi-Fi on/off, the current connection, nearby networks with the
// password asked in place, forgetting saved networks. Everything goes through nmcli (NetworkManager.qml).
import QtQuick
import QtQuick.Effects
import Quickshell
import qs.common
import "signal.js" as Signal

OverlayPanel {
    id: menu

    readonly property alias net: manager

    namespace: "network-panel"
    dim: 0.25
    fadeInMs: 160
    fadeOutMs: 140

    NetworkManager { id: manager }

    Rectangle {
        id: card
        anchors { top: parent.top; right: parent.right; topMargin: menu.shown ? 50 : 34; rightMargin: 14 }
        Behavior on anchors.topMargin { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        width: 410
        // Header and footer keep their size; the network list gets what is left and scrolls.
        height: Math.min(18 + top.implicitHeight + (manager.wifiOn ? 14 + list.implicitHeight : 0)
                         + (bottom.implicitHeight > 0 ? 14 + bottom.implicitHeight : 0) + 18,
                         parent.height - 80)
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
            id: top
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 18 }
            spacing: 14

            // Header: title, rescan, Wi-Fi switch.
            Item {
                width: parent.width; height: 34
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Theme.title("Сеть")
                    font.family: Theme.titleFont; font.pixelSize: 24; font.bold: true; font.italic: Theme.italicTitle
                    color: Theme.fg
                }
                Row {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    spacing: 10
                    IconButton { glyph: "\u{f0450}"; spinning: manager.scanning; onClicked: manager.rescan() }
                    Switch { checked: manager.wifiOn; onToggled: manager.setWifi(!manager.wifiOn) }
                }
            }

            // The current Wi-Fi connection.
            Rectangle {
                visible: !!manager.active
                width: parent.width; height: 64
                radius: Theme.radius(18)
                color: Theme.alpha(Theme.accent, 0.14)
                border.width: 1; border.color: Theme.alpha(Theme.accent, 0.5)
                Text {
                    id: activeIcon
                    anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                    text: Signal.glyph(manager.active ? manager.active.signal || 0 : 0)
                    font.family: Theme.glyphFont; font.pixelSize: 24
                    color: Theme.accent
                }
                Column {
                    anchors { left: activeIcon.right; leftMargin: 12; right: disconnectButton.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    spacing: 3
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: manager.active ? manager.active.ssid || "" : ""
                        font.family: Theme.bodyFont; font.pixelSize: 15; font.bold: true
                        color: Theme.fg
                    }
                    Text {
                        text: "подключено" + (manager.active && manager.active.ip ? " · " + manager.active.ip : "")
                        font.family: Theme.bodyFont; font.pixelSize: 12
                        color: Theme.muted
                    }
                }
                Chip {
                    id: disconnectButton
                    anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    text: "Отключить"
                    onClicked: manager.disconnect()
                }
            }

            // Ethernet, VPN tunnels and the like.
            Repeater {
                model: manager.others
                Row {
                    required property var modelData
                    readonly property bool cable: modelData.type === "ethernet"
                    readonly property bool tunnel: ["tun", "wireguard", "vpn"].includes(modelData.type)
                    spacing: 10
                    Text {
                        text: parent.cable ? "\u{f0200}" : "\u{f0582}"
                        font.family: Theme.glyphFont; font.pixelSize: 16
                        color: Theme.good
                    }
                    Text {
                        text: (parent.cable ? "Кабель: " : parent.tunnel ? "VPN: " : parent.modelData.type + ": ") + parent.modelData.name
                        font.family: Theme.bodyFont; font.pixelSize: 13
                        color: Theme.muted
                    }
                }
            }

            Text {
                visible: manager.wifiOn
                text: "Доступные сети" + (manager.networks.length ? "  ·  " + manager.networks.length : "")
                font.family: Theme.bodyFont; font.pixelSize: 12; font.capitalization: Font.AllUppercase
                font.letterSpacing: 1
                color: Theme.muted
            }
            Text {
                visible: !manager.wifiOn
                width: parent.width; wrapMode: Text.Wrap
                text: "Wi-Fi выключен. Включи переключателем сверху."
                font.family: Theme.bodyFont; font.pixelSize: 14
                color: Theme.muted
            }
        }

        Flickable {
            visible: manager.wifiOn
            anchors { left: parent.left; right: parent.right; top: top.bottom; bottom: bottom.top
                      leftMargin: 18; rightMargin: 18; topMargin: 14; bottomMargin: bottom.implicitHeight > 0 ? 14 : 0 }
            contentHeight: list.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: list
                width: parent.width
                spacing: 6
                Repeater {
                    model: manager.otherNetworks
                    NetworkRow {
                        required property var model
                        net: manager
                        network: model
                        onDone: menu.focusScene()
                    }
                }
            }
        }

        Column {
            id: bottom
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 18 }
            spacing: 10

            Text {
                visible: !!manager.message
                width: parent.width; wrapMode: Text.Wrap
                text: manager.message
                font.family: Theme.bodyFont; font.pixelSize: 13
                color: manager.messageIsError ? Theme.crit : Theme.accent2
            }
            Chip {
                visible: manager.hasEditor
                text: "Все настройки сети…"
                onClicked: {
                    Quickshell.execDetached(["nm-connection-editor"]);
                    menu.close();
                }
            }
        }
    }
}
