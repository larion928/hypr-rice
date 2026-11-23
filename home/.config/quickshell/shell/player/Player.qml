// Player card (waybar custom/player, player-panel): the active MPRIS player's cover, track and controls, and
// the other players to switch to. Which player is active is Players' choice (services/Players.qml), shared
// with the media keys and the bar. A control the player does not support is not shown.
// The animated wallpaper's sound, when its clip has one, is switched and set at the bottom.
import QtQuick
import QtQuick.Effects
import Quickshell.Services.Mpris
import qs.common
import qs.services

OverlayPanel {
    id: menu

    readonly property MprisPlayer player: Players.active

    namespace: "player-panel"
    dim: 0.25
    fadeInMs: 160
    fadeOutMs: 140

    function clock(seconds) {
        const whole = Math.max(0, Math.floor(seconds));
        return Math.floor(whole / 60) + ":" + String(whole % 60).padStart(2, "0");
    }

    function nextLoopState(state) {
        if (state === MprisLoopState.None) {
            return MprisLoopState.Playlist;
        }
        return state === MprisLoopState.Playlist ? MprisLoopState.Track : MprisLoopState.None;
    }

    // MPRIS does not signal the position as it moves: ask for it while the track plays.
    Timer {
        running: menu.shown && !!menu.player && menu.player.isPlaying
        interval: 1000
        repeat: true
        onTriggered: menu.player.positionChanged()
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
                text: Theme.title("Плеер")
                font.family: Theme.titleFont; font.pixelSize: Theme.titleSize(24); font.bold: true; font.italic: Theme.italicTitle
                color: Theme.fg
            }

            Text {
                visible: !menu.player
                width: parent.width
                wrapMode: Text.WordWrap
                text: "Ничего не играет. Здесь появится плеер, браузер или другая программа, когда она начнёт играть."
                font.family: Theme.bodyFont; font.pixelSize: 13
                color: Theme.muted
            }

            NowPlaying {
                visible: !!menu.player
                width: parent.width
                player: menu.player
            }

            Column {
                visible: !!menu.player
                width: parent.width
                spacing: 2
                Level {
                    visible: !!menu.player && menu.player.positionSupported && menu.player.lengthSupported
                             && menu.player.length > 0
                    width: parent.width
                    value: menu.player && menu.player.length > 0 ? menu.player.position / menu.player.length : 0
                    enabled: !!menu.player && menu.player.canSeek
                    onReleased: fraction => menu.player.position = fraction * menu.player.length
                }
                Item {
                    visible: !!menu.player && menu.player.lengthSupported && menu.player.length > 0
                    width: parent.width; height: 16
                    Text {
                        text: menu.player ? menu.clock(menu.player.position) : ""
                        font.family: Theme.bodyFont; font.pixelSize: 11; color: Theme.muted
                    }
                    Text {
                        anchors.right: parent.right
                        text: menu.player ? menu.clock(menu.player.length) : ""
                        font.family: Theme.bodyFont; font.pixelSize: 11; color: Theme.muted
                    }
                }
            }

            Row {
                visible: !!menu.player
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 14
                IconButton {
                    visible: !!menu.player && menu.player.shuffleSupported
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: menu.player && menu.player.shuffle ? "\u{f049d}" : "\u{f049e}"
                    active: !!menu.player && menu.player.shuffle
                    onClicked: menu.player.shuffle = !menu.player.shuffle
                }
                IconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: "\u{f04ae}"
                    opacity: menu.player && menu.player.canGoPrevious ? 1 : 0.35
                    onClicked: if (menu.player.canGoPrevious) menu.player.previous()
                }
                IconButton {
                    width: 44
                    filled: true
                    glyph: menu.player && menu.player.isPlaying ? "\u{f03e4}" : "\u{f040a}"
                    opacity: menu.player && menu.player.canTogglePlaying ? 1 : 0.35
                    onClicked: if (menu.player.canTogglePlaying) menu.player.togglePlaying()
                }
                IconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: "\u{f04ad}"
                    opacity: menu.player && menu.player.canGoNext ? 1 : 0.35
                    onClicked: if (menu.player.canGoNext) menu.player.next()
                }
                IconButton {
                    visible: !!menu.player && menu.player.loopSupported
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: !menu.player || menu.player.loopState === MprisLoopState.None ? "\u{f0457}"
                           : menu.player.loopState === MprisLoopState.Track ? "\u{f0458}" : "\u{f0456}"
                    active: !!menu.player && menu.player.loopState !== MprisLoopState.None
                    onClicked: menu.player.loopState = menu.nextLoopState(menu.player.loopState)
                }
            }

            Row {
                visible: !!menu.player && menu.player.volumeSupported
                width: parent.width
                spacing: 10
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u{f057e}"
                    font.family: Theme.glyphFont; font.pixelSize: 16; color: Theme.muted
                }
                Level {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 26
                    value: menu.player ? menu.player.volume : 0
                    onDragged: fraction => menu.player.volume = fraction
                }
            }

            Column {
                visible: Players.all.length > 1
                width: parent.width
                spacing: 6
                SectionTitle { text: "Источники" }
                Repeater {
                    model: Players.all
                    SourceRow {
                        required property MprisPlayer modelData
                        width: parent.width
                        player: modelData
                        current: modelData === menu.player
                        onPicked: Players.pick(modelData)
                    }
                }
            }

            Column {
                visible: Wallpaper.connected && Wallpaper.hasSound
                width: parent.width
                spacing: 6
                SectionTitle { text: "Звук обоев" }
                WallpaperRow { width: parent.width }
            }
        }
    }
}
