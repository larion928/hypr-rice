import QtQuick
import qs.common
import qs.services

// The animated wallpaper as a sound source in the player card (services/Wallpaper.qml): its sound switched on
// or off (the feature wallpaper-sound), why it is quiet while switched on, and its volume.
Rectangle {
    height: 44
    radius: Theme.radius(12)
    color: Wallpaper.audible ? Theme.alpha(Theme.accent, 0.14) : "transparent"
    border.width: 1
    border.color: Theme.alpha(Theme.accent, Wallpaper.audible ? 0.5 : 0.2)

    IconButton {
        id: soundButton
        anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
        glyph: Wallpaper.soundOn ? "\u{f057e}" : "\u{f0581}"
        active: Wallpaper.soundOn
        onClicked: Wallpaper.switchSound()
    }

    Column {
        anchors { left: soundButton.right; leftMargin: 8; right: volumeButtons.left; rightMargin: 8 }
        anchors.verticalCenter: parent.verticalCenter
        Text {
            text: "Обои"
            font.family: Theme.bodyFont; font.pixelSize: 13
            color: Theme.fg
        }
        Text {
            width: parent.width
            elide: Text.ElideRight
            text: Wallpaper.status
            font.family: Theme.bodyFont; font.pixelSize: 11
            color: Theme.muted
        }
    }

    Row {
        id: volumeButtons
        visible: Wallpaper.soundOn
        anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
        IconButton {
            glyph: "\u{f0374}"
            onClicked: Wallpaper.setVolume(Wallpaper.volume - Wallpaper.volumeStep)
        }
        IconButton {
            glyph: "\u{f0415}"
            onClicked: Wallpaper.setVolume(Wallpaper.volume + Wallpaper.volumeStep)
        }
    }
}
