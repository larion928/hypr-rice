import QtQuick
import qs.common

// Installing an icon or cursor theme: the password, then the installer's output.
Rectangle {
    id: dialog
    required property ThemeEditStore themeEdit

    color: Theme.alpha(Theme.bg, 0.92)
    MouseArea { anchors.fill: parent }
    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 720); height: installColumn.implicitHeight + 48
        radius: Theme.radius(22)
        color: Theme.bg2
        border.color: Theme.accent
        Column {
            id: installColumn
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24 }
            spacing: 12
            SectionTitle {
                text: themeEdit.installing ? "Установка «" + themeEdit.installing.title + "»" : ""
            }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: !themeEdit.installing ? ""
                      : (themeEdit.installing.source === "aur" ? "Из AUR: пакет соберётся на этой машине, это может занять пару минут. "
                                                               : "Из репозитория Arch. ")
                        + "Нужен пароль администратора (sudo): он передаётся установщику напрямую и нигде не сохраняется."
                font.family: Theme.bodyFont; font.pixelSize: 14
                color: Theme.fg
            }
            Row {
                visible: themeEdit.installState === "ask"
                spacing: 10
                Field {
                    id: passwordField
                    width: 300
                    echoMode: TextInput.Password
                    placeholder: "пароль sudo"
                    onAccepted: if (text) { themeEdit.startInstall(text); text = ""; }
                }
                Chip {
                    text: "Установить"
                    primary: true
                    enabled: passwordField.text !== ""
                    onClicked: { themeEdit.startInstall(passwordField.text); passwordField.text = ""; }
                }
                Chip { text: "Отмена"; onClicked: themeEdit.installing = null }
            }
            Rectangle {
                visible: themeEdit.installState === "running" || themeEdit.installState === "done" || themeEdit.installState === "failed"
                width: parent.width; height: 260
                radius: 8
                color: Theme.bg
                Text {
                    anchors { fill: parent; margins: 12 }
                    text: themeEdit.installLog.join("\n")
                    font.family: Theme.font; font.pixelSize: 12
                    color: Theme.muted
                    wrapMode: Text.WrapAnywhere
                    clip: true
                    verticalAlignment: Text.AlignBottom
                }
            }
            Text {
                visible: themeEdit.installMessage !== ""
                text: themeEdit.installMessage
                font.family: Theme.bodyFont; font.pixelSize: 14; font.bold: true
                color: themeEdit.installState === "done" ? Theme.good
                       : themeEdit.installState === "running" ? Theme.accent : Theme.crit
            }
            Text {
                visible: themeEdit.installState === "checking"
                text: "Проверяю пароль…"
                font.family: Theme.bodyFont; font.pixelSize: 14
                color: Theme.accent
            }
            Chip {
                visible: themeEdit.installState === "running"
                text: "Скрыть (установка продолжится)"
                onClicked: themeEdit.installing = null
            }
            Chip {
                visible: themeEdit.installState === "done" || themeEdit.installState === "failed"
                text: "Закрыть"
                onClicked: themeEdit.installing = null
            }
        }
    }
}
