import QtQuick
import qs.common

// Installing a missing package (an icon or cursor theme, mpvpaper, what a feature needs): the password, then the
// installer's output.
Rectangle {
    id: dialog
    required property PackageInstall install

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
                text: install.item ? "Установка «" + install.item.title + "»" : ""
            }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: !install.item ? ""
                      : (install.item.source === "aur" ? "Из AUR: пакет соберётся на этой машине, это может занять пару минут. "
                         : install.item.source === "repo" ? "Из репозитория Arch. "
                         : "Из репозитория Arch, а если его там нет, из AUR (тогда пакет соберётся на этой машине, "
                           + "это может занять пару минут). ")
                        + "Нужен пароль администратора (sudo): он передаётся установщику напрямую и нигде не сохраняется."
                font.family: Theme.bodyFont; font.pixelSize: 14
                color: Theme.fg
            }
            Row {
                visible: install.phase === "ask"
                spacing: 10
                Field {
                    id: passwordField
                    width: 300
                    echoMode: TextInput.Password
                    placeholder: "пароль sudo"
                    onAccepted: if (text) { install.start(text); text = ""; }
                }
                Chip {
                    text: "Установить"
                    primary: true
                    enabled: passwordField.text !== ""
                    onClicked: { install.start(passwordField.text); passwordField.text = ""; }
                }
                Chip { text: "Отмена"; onClicked: install.item = null }
            }
            Rectangle {
                visible: install.phase === "running" || install.phase === "done" || install.phase === "failed"
                width: parent.width; height: 260
                radius: 8
                color: Theme.bg
                Text {
                    anchors { fill: parent; margins: 12 }
                    text: install.log.join("\n")
                    font.family: Theme.font; font.pixelSize: 12
                    color: Theme.muted
                    wrapMode: Text.WrapAnywhere
                    clip: true
                    verticalAlignment: Text.AlignBottom
                }
            }
            Text {
                visible: install.message !== ""
                text: install.message
                font.family: Theme.bodyFont; font.pixelSize: 14; font.bold: true
                color: install.phase === "done" ? Theme.good
                       : install.phase === "running" ? Theme.accent : Theme.crit
            }
            Text {
                visible: install.phase === "checking"
                text: "Проверяю пароль…"
                font.family: Theme.bodyFont; font.pixelSize: 14
                color: Theme.accent
            }
            Chip {
                visible: install.phase === "running"
                text: "Скрыть (установка продолжится)"
                onClicked: install.item = null
            }
            Chip {
                visible: install.phase === "done" || install.phase === "failed"
                text: "Закрыть"
                onClicked: install.item = null
            }
        }
    }
}
