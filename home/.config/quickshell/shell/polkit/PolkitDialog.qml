// The password window of the session's polkit agent (shell.qml). An app asks the system for something only an
// administrator may do (mount the computer's own disk, pkexec, a system network connection); polkit asks this
// session's agent, and the window shows what is asked and takes the password, which goes to polkit's helper and is
// not kept here. Closing the window without a password (Esc, a click outside, «Отмена») refuses the request.
// The admin whose password is asked is polkit's first choice: Identity has no members to name it by in QML.
import QtQuick
import Quickshell.Services.Polkit
import qs.common

OverlayPanel {
    id: dialog

    // Turns null a moment before the window goes away, hence the ?. below.
    required property AuthFlow flow

    function submit() {
        if (!password.text || !flow?.isResponseRequired) {
            return;
        }
        flow.submit(password.text);
        password.text = "";
    }

    namespace: "polkit-dialog"
    onClosingChanged: {
        if (closing && flow && !flow.isCompleted) {
            flow.cancelAuthenticationRequest();
        }
    }
    Component.onCompleted: password.focusInput()

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 560); height: column.implicitHeight + 48
        radius: Theme.radius(22)
        color: Theme.bg2
        border.color: Theme.accent
        // A click on the card is not a click outside, which would refuse.
        MouseArea { anchors.fill: parent }

        Column {
            id: column
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24 }
            spacing: 12

            SectionTitle { text: "Нужен пароль администратора" }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: dialog.flow?.message ?? ""
                font.family: Theme.bodyFont; font.pixelSize: 15
                color: Theme.fg
            }
            Text {
                width: parent.width
                wrapMode: Text.WrapAnywhere
                text: dialog.flow?.actionId ?? ""
                font.family: Theme.font; font.pixelSize: 12
                color: Theme.muted
            }
            Row {
                spacing: 10
                Field {
                    id: password
                    width: 300
                    echoMode: dialog.flow?.responseVisible ? TextInput.Normal : TextInput.Password
                    placeholder: dialog.flow?.inputPrompt.trim() || "пароль"
                    onAccepted: dialog.submit()
                    onEscaped: dialog.close()
                }
                Chip {
                    text: "Подтвердить"
                    primary: true
                    enabled: password.text !== "" && !!dialog.flow?.isResponseRequired
                    onClicked: dialog.submit()
                }
                Chip { text: "Отмена"; onClicked: dialog.close() }
            }
            Text {
                visible: text !== ""
                width: parent.width
                wrapMode: Text.WordWrap
                text: dialog.flow?.supplementaryMessage || (dialog.flow?.failed ? "Пароль не подошёл" : "")
                font.family: Theme.bodyFont; font.pixelSize: 14; font.bold: true
                color: dialog.flow?.supplementaryIsError || dialog.flow?.failed ? Theme.crit : Theme.muted
            }
        }
    }
}
