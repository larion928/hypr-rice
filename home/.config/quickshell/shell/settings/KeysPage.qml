import QtQuick
import qs.common

// Клавиши: the main modifier, the editable binds by group (in the help's order), programs' shortcuts, own binds
// and a form for a new one.
Item {
    id: page

    required property KeysModel keys
    readonly property var groupOrder: ["Приложения", "Окна", "Воркспейсы", "Скриншоты", "Оформление", "Система"]

    Row {
        id: modRow
        spacing: 10
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Главная клавиша:"
            font.family: Theme.bodyFont; font.pixelSize: 15
            color: Theme.fg
        }
        Chip { text: "Alt"; active: page.keys.mainMod === "ALT"; onClicked: page.keys.setMainMod("ALT") }
        Chip { text: "Super (Win)"; active: page.keys.mainMod === "SUPER"; onClicked: page.keys.setMainMod("SUPER") }
    }

    Flickable {
        anchors { left: parent.left; right: parent.right; top: modRow.bottom; topMargin: 18; bottom: buttons.top; bottomMargin: 12 }
        contentHeight: keyList.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: keyList
            width: parent.width
            spacing: 6

            Repeater {
                model: [...new Set(page.keys.binds.map(b => b.group))]
                    .sort((p, q) => (page.groupOrder.indexOf(p) + 1 || 99) - (page.groupOrder.indexOf(q) + 1 || 99))
                Column {
                    id: group
                    required property string modelData
                    width: keyList.width
                    spacing: 6
                    SectionTitle { text: group.modelData }
                    Repeater {
                        model: page.keys.binds.filter(b => b.group === group.modelData)
                        BindRow {
                            required property var modelData
                            keys: page.keys
                            width: group.width
                            title: modelData.text
                            combo: modelData.current
                            isDefault: modelData.current === modelData.default
                            capturing: page.keys.capturing === modelData.id
                            onEdit: page.keys.startCapture(modelData.id)
                            onToggle: page.keys.setCurrent(modelData.id, modelData.current ? "" : modelData.default)
                            onReset: page.keys.setCurrent(modelData.id, modelData.default)
                        }
                    }
                }
            }

            SectionTitle { text: "Сочетания программ" }
            Text {
                width: keyList.width
                wrapMode: Text.WordWrap
                text: page.keys.globalRows().length
                      ? "Программа сама выбрать клавишу не может (отсюда \"среда рабочего стола не разрешила\" в Discord): назначь её здесь. Подходят и кнопки мыши: колёсико, боковые."
                      : "Пока ни одна программа не просила сочетание. Discord просит его, когда в его настройках назначаешь клавишу рации; запусти программу и открой это окно снова."
                font.family: Theme.bodyFont; font.pixelSize: 13
                color: Theme.muted
            }
            Repeater {
                model: page.keys.globalRows()
                BindRow {
                    required property var modelData
                    keys: page.keys
                    width: keyList.width
                    title: modelData.description + "  ·  " + modelData.name.split(":")[0]
                    combo: modelData.keys
                    isDefault: true
                    emptyLabel: "не назначено"
                    capturing: page.keys.capturing === "global:" + modelData.name
                    onEdit: page.keys.startCapture("global:" + modelData.name)
                    onToggle: modelData.keys ? page.keys.setGlobal(modelData.name, "") : page.keys.startCapture("global:" + modelData.name)
                }
            }

            SectionTitle { text: "Свои сочетания" }
            Repeater {
                model: page.keys.custom
                BindRow {
                    required property var modelData
                    required property int index
                    keys: page.keys
                    width: keyList.width
                    title: (modelData.name || modelData.cmd) + "  ·  " + modelData.cmd
                    combo: modelData.keys
                    isDefault: true
                    removable: true
                    onRemove: page.keys.removeCustom(index)
                }
            }

            // New own bind: name, command, keys.
            Row {
                spacing: 10
                Field { id: nameField; width: 200; placeholder: "Название" }
                Field { id: commandField; width: 340; placeholder: "Команда, например: gimp" }
                Chip {
                    text: page.keys.capturing === "custom" ? "Нажми сочетание…"
                          : page.keys.customCombo ? page.keys.label(page.keys.customCombo) : "Сочетание"
                    active: page.keys.capturing === "custom"
                    onClicked: page.keys.startCapture("custom")
                }
                Chip {
                    text: "Добавить"
                    primary: true
                    enabled: page.keys.customCombo !== "" && commandField.text.trim() !== ""
                    onClicked: {
                        page.keys.addCustom(page.keys.customCombo, commandField.text.trim(), nameField.text.trim());
                        nameField.text = "";
                        commandField.text = "";
                    }
                }
            }
        }
    }

    Row {
        id: buttons
        anchors { right: parent.right; bottom: parent.bottom }
        spacing: 10
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: page.keys.conflict ? "Уже занято: " + page.keys.conflict : page.keys.status
            font.family: Theme.bodyFont; font.pixelSize: 14
            color: page.keys.conflict ? Theme.warn : Theme.accent2
        }
        Chip { visible: page.keys.pendingId !== ""; text: "Всё равно назначить"; onClicked: page.keys.assignAnyway() }
        Chip { text: "Сохранить"; primary: true; enabled: page.keys.dirty; onClicked: page.keys.save() }
    }
}
