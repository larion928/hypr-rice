// The animated wallpaper's card (waybar custom/wallpaper, wallpaper-panel): the clip's cover, title and artist
// from the theme's ui.json "wallpaperCard" ({ "cover": a path in the theme's folder, "title", "artist" }), its
// sound switch and volume, and how far the clip has played. The sound is services/Wallpaper.qml's.
// The cover may be shown as the theme's LED screen: "leds": { "tile": a picture of LED cells in the theme's
// folder, dark between the LEDs and transparent where they shine, "pitch": a cell's size in px }.
import QtQuick
import QtQuick.Effects
import qs.common
import qs.services

OverlayPanel {
    id: menu

    readonly property var track: Theme.ui.wallpaperCard || {}
    readonly property bool playing: Wallpaper.connected

    namespace: "wallpaper-card"
    dim: 0.25
    fadeInMs: 160
    fadeOutMs: 140

    Component.onCompleted: Wallpaper.positionWatchers += 1
    Component.onDestruction: Wallpaper.positionWatchers -= 1

    Rectangle {
        id: card
        anchors { top: parent.top; right: parent.right; topMargin: menu.shown ? 50 : 34; rightMargin: 14 }
        Behavior on anchors.topMargin { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        width: 420
        height: 236
        radius: Theme.radius(18)
        color: Theme.bg2
        border.width: Theme.border
        border.color: Theme.alpha(Theme.accent, Theme.ui.glow ? 0.9 : 0.4)
        clip: true
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Theme.ui.glow ? Theme.accent : "#000000"
            shadowBlur: 0.8; shadowVerticalOffset: Theme.ui.glow ? 0 : 8; blurMax: 32
        }
        MouseArea { anchors.fill: parent }   // clicks inside do not close

        // The cover one pixel per LED, under the cells.
        Item {
            id: ledScreen
            readonly property int pitch: menu.track.leds ? menu.track.leds.pitch : 0
            visible: pitch > 0 && cover.visible
            width: pitch > 0 ? Math.ceil(card.width / pitch) * pitch : 0
            height: pitch > 0 ? Math.ceil(card.height / pitch) * pitch : 0
            Image {
                anchors.fill: parent
                source: ledScreen.visible ? cover.source : ""
                sourceSize: Qt.size(ledScreen.width / ledScreen.pitch, ledScreen.height / ledScreen.pitch)
                smooth: false
                asynchronous: true
            }
            Image {
                anchors.fill: parent
                source: ledScreen.visible ? "file://" + Theme.dir + "/" + menu.track.leds.tile : ""
                fillMode: Image.Tile
            }
        }

        // Over the LEDs, faintly: their glow.
        Image {
            id: cover
            anchors.fill: parent
            visible: status === Image.Ready
            opacity: ledScreen.pitch > 0 ? 0.22 : 1
            source: menu.track.cover && Theme.dir ? "file://" + Theme.dir + "/" + menu.track.cover : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }

        // Darker towards the bottom: the title and the controls stay readable over any cover.
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: Theme.alpha(Theme.bg, 0.15) }
                GradientStop { position: 1.0; color: Theme.alpha(Theme.bg, 0.75) }
            }
        }

        Column {
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 18 }
            spacing: 4
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: menu.track.title || "Обои"
                font.family: Theme.titleFont; font.pixelSize: 26; font.italic: Theme.italicTitle
                color: Theme.fg
            }
            Text {
                width: parent.width
                visible: text !== ""
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: menu.track.artist || ""
                font.family: Theme.bodyFont; font.pixelSize: 15; font.bold: true
                color: Theme.fg
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: !menu.playing ? "Сейчас обои не анимированные"
                      : !Wallpaper.hasSound ? "У этих обоев нет звука" : Wallpaper.status
                font.family: Theme.bodyFont; font.pixelSize: 12
                color: Theme.muted
            }
        }

        Rectangle {
            id: band
            visible: menu.playing && Wallpaper.hasSound
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 64
            color: Theme.alpha(Theme.bg, 0.55)

            Row {
                anchors.centerIn: parent
                spacing: 22
                IconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: "\u{f0374}"
                    opacity: Wallpaper.soundOn ? 1 : 0.35
                    onClicked: Wallpaper.setVolume(Wallpaper.volume - Wallpaper.volumeStep)
                }
                IconButton {
                    width: 46
                    filled: true
                    active: Wallpaper.soundOn
                    glyph: Wallpaper.soundOn ? "\u{f057e}" : "\u{f0581}"
                    onClicked: Wallpaper.switchSound()
                }
                IconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: "\u{f0415}"
                    opacity: Wallpaper.soundOn ? 1 : 0.35
                    onClicked: Wallpaper.setVolume(Wallpaper.volume + Wallpaper.volumeStep)
                }
            }
        }

        // How far the clip has played, along the bottom edge.
        Rectangle {
            visible: menu.playing && Wallpaper.duration > 0
            anchors { left: parent.left; bottom: parent.bottom }
            height: 3
            width: parent.width * Math.min(1, Wallpaper.position / Math.max(1, Wallpaper.duration))
            color: Theme.accent
            Behavior on width { NumberAnimation { duration: 500 } }
        }
    }
}
