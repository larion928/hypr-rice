import QtQuick

// A one-line text field with a placeholder. Esc hands the keyboard back to the menu (its FocusScope) and
// tells the owner, which may also clear the text or step back.
Rectangle {
    id: field

    property alias text: input.text
    property alias echoMode: input.echoMode
    property alias inputFocus: input.activeFocus
    property string placeholder

    signal accepted()
    signal escaped()

    function focusInput() {
        input.forceActiveFocus();
    }

    // Starts the field with what was typed while the menu had the keyboard.
    function type(typed) {
        input.text += typed;
        input.forceActiveFocus();
    }

    height: 34
    radius: Theme.rounded ? 9 : 0
    color: Theme.alpha(Theme.bg2, 0.9)
    border.color: input.activeFocus ? Theme.accent : Theme.alpha(Theme.muted, 0.35)

    TextInput {
        id: input
        anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
        verticalAlignment: TextInput.AlignVCenter
        font.family: Theme.bodyFont
        font.pixelSize: 14
        color: Theme.fg
        selectionColor: Theme.alpha(Theme.accent, 0.4)
        clip: true
        Keys.onEscapePressed: {
            input.focus = false;
            field.escaped();
        }
        onAccepted: field.accepted()
    }
    Text {
        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
        visible: !input.text && !input.activeFocus
        text: field.placeholder
        font: input.font
        color: Theme.muted
    }
    MouseArea { anchors.fill: parent; onClicked: input.forceActiveFocus() }
}
