import QtQuick
import qs.common

// What ownThemes asks: a new theme's name, a file to add or to save to, whether to delete.
Rectangle {
    id: ownDialog
    required property ThemeEditStore themeEdit
    required property OwnThemes ownThemes

    readonly property string label: ownThemes.subject ? ownThemes.subject.pal.label : ""
    // A copy and an export take the saved edits only.
    readonly property string unsaved: themeEdit.dirty && ownThemes.subject && themeEdit.editing
                                      && ownThemes.subject.name === themeEdit.editing.name
                                      ? " Несохранённые изменения туда не попадут: сначала сохрани." : ""
    readonly property var texts: ({
        "new": ["Новая тема", "Копия темы \"" + label + "\" со всеми её правками из этого окна. Дальше настраивай её здесь же; обновления райса её не трогают." + unsaved, "Создать"],
        "import": ["Тема из файла", "Архив .zip, сохранённый кнопкой \"Экспорт…\". В теме есть и программы (hypr.lua, battery.py, screenshot.qml): добавляй темы только от тех, кому доверяешь.", "Выбрать файл…"],
        "export": ["Экспорт темы", "Тема \"" + label + "\" со всеми правками в одном архиве .zip. Друг добавит её кнопкой \"Из файла…\" в списке тем." + unsaved, "Сохранить как…"],
        "delete": ["Удалить тему", ownThemes.subject && ownThemes.subject.catalog
                   ? "Тема \"" + label + "\" и её правки удалятся. Поставить её снова можно из каталога (кнопка \"Каталог…\" над списком тем)."
                   : ownThemes.subject && ownThemes.subject.user
                   ? "Тема \"" + label + "\" и её правки удалятся насовсем."
                   : "Тема \"" + label + "\" уйдёт из списка, обновления райса её не вернут. Вернуть её можно кнопкой \"Вернуть удалённые\" над списком тем, вместе с твоими правками.", "Удалить"],
        "factory": ["Вернуть к заводским", ownThemes.subject && ownThemes.subject.catalog
                    ? "Тема \"" + label + "\" скачается из каталога заново: уберутся все правки из этого окна, добавленные обои и правки руками в её папке."
                    : ownThemes.subject && ownThemes.subject.user
                    ? "У своей темы нет заводского вида: уберутся все правки из этого окна, тема станет такой, какой её создали."
                    : "Тема \"" + label + "\" станет такой, как в райсе: уберутся все правки из этого окна и добавленные обои, файлы темы возьмутся заново из копии райса (так уйдут и правки руками в её папке). Общая раскладка панели для всех тем останется: её убирает кнопка в разделе \"Панель\".", "Вернуть"],
        "restore": ["Вернуть удалённые темы", "Темы райса, которые ты удалил: нажми на тему, и она вернётся из копии райса на этом компьютере вместе с твоими правками.", ""]
    })
    readonly property var wording: texts[ownThemes.dialog] || ["", "", ""]
    function act() {
        if (ownThemes.dialog === "new") ownThemes.create(nameField.text);
        else if (ownThemes.dialog === "delete") ownThemes.remove();
        else if (ownThemes.dialog === "factory") ownThemes.factory();
        else ownThemes.pickFile(ownThemes.dialog);
    }
    onVisibleChanged: {
        if (!visible || ownThemes.dialog !== "new") return;
        nameField.text = "";
        nameField.focusInput();
    }
    color: Theme.alpha(Theme.bg, 0.85)
    MouseArea { anchors.fill: parent }  // the page under it waits

    Rectangle {
        anchors.centerIn: parent
        width: 560; height: dialogColumn.implicitHeight + 48
        radius: Theme.radius(14)
        color: Theme.bg2
        border.color: Theme.alpha(Theme.accent, 0.5)
        Column {
            id: dialogColumn
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24 }
            spacing: 14
            SectionTitle { text: ownDialog.wording[0] }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: ownDialog.wording[1]
                font.family: Theme.bodyFont; font.pixelSize: 14
                color: Theme.fg
            }
            Flow {
                visible: ownThemes.dialog === "restore"
                width: parent.width
                spacing: 8
                Repeater {
                    model: ownThemes.removed
                    Chip {
                        required property var modelData
                        text: modelData.label
                        enabled: !ownThemes.busy
                        onClicked: ownThemes.restore(modelData.name)
                    }
                }
            }
            Field {
                id: nameField
                visible: ownThemes.dialog === "new"
                width: parent.width
                placeholder: "Название, например \"Моя тема\""
                onAccepted: ownDialog.act()
            }
            Text {
                visible: text !== ""
                width: parent.width
                wrapMode: Text.WordWrap
                text: ownThemes.busy || ownThemes.error || ownThemes.done
                font.family: Theme.bodyFont; font.pixelSize: 13
                color: ownThemes.error ? Theme.crit : Theme.muted
            }
            Row {
                anchors.right: parent.right
                spacing: 10
                Chip { text: ownThemes.done ? "Закрыть" : "Отмена"; enabled: !ownThemes.busy; onClicked: ownThemes.dialog = "" }
                Chip {
                    visible: !ownThemes.done && ownDialog.wording[2] !== ""
                    primary: true
                    enabled: !ownThemes.busy && (ownThemes.dialog !== "new" || nameField.text.trim() !== "")
                    text: ownDialog.wording[2]
                    onClicked: ownDialog.act()
                }
            }
        }
    }
}
