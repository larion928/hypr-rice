import QtQuick
import qs.common

// One game: its name, its cover, or out of the list.
Rectangle {
    id: dialog

    required property var library   // the games window
    readonly property var game: library.editing

    function saveName() {
        library.run(["rename", game.id, nameField.text]);
        library.dialog = "";
    }

    color: Theme.alpha(Theme.bg, 0.85)
    onVisibleChanged: if (visible && game) nameField.text = game.name
    MouseArea { anchors.fill: parent; onClicked: dialog.library.dialog = "" }

    Rectangle {
        anchors.centerIn: parent
        width: 700; height: fields.implicitHeight + 44
        radius: Theme.radius(22)
        color: Theme.bg2
        border.color: Theme.alpha(Theme.accent, 0.5)
        MouseArea { anchors.fill: parent }
        Column {
            id: fields
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 22 }
            spacing: 14
            SectionTitle {
                text: "Игра"
                font.pixelSize: Theme.titleSize(20)
                font.bold: false
            }
            Text {
                width: parent.width
                elide: Text.ElideMiddle
                text: dialog.game ? dialog.library.kindNames[dialog.game.kind] + " · " + dialog.game.target : ""
                font.family: Theme.font; font.pixelSize: 12
                color: Theme.muted
            }
            Field {
                id: nameField
                width: parent.width
                placeholder: "название"
                onAccepted: dialog.saveName()
                onEscaped: dialog.library.back()
            }
            Row {
                spacing: 10
                Chip { text: "Сохранить название"; primary: true; onClicked: dialog.saveName() }
                Chip { text: "Обложка…"; onClicked: dialog.library.pickFile("cover") }
                Chip {
                    visible: dialog.game !== null && dialog.game.cover !== ""
                    text: "Убрать обложку"
                    onClicked: {
                        dialog.library.run(["uncover", dialog.game.id]);
                        dialog.library.dialog = "";
                    }
                }
                Chip {
                    text: "Убрать из списка"
                    onClicked: {
                        dialog.library.run(["remove", dialog.game.id]);
                        dialog.library.dialog = "";
                    }
                }
            }
        }
    }
}
