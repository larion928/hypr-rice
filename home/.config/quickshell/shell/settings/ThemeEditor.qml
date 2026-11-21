import QtQuick
import qs.common

// One theme's settings (themeEdit.editing): a header with saving and switching, the section tabs and the section
// itself, and the pickers and the install dialog over it.
Rectangle {
    id: editor
    required property ThemeEditStore themeEdit
    required property UserFiles userFiles
    required property OwnThemes ownThemes

    // «Включить тему»: the theme goes on and the window closes.
    signal switched()

    color: Theme.bg
    MouseArea { anchors.fill: parent }

    Row {
        id: editHeader
        anchors { left: parent.left; top: parent.top }
        spacing: 14
        Chip { text: "← Темы"; onClicked: themeEdit.editing = null }
        SectionTitle {
            anchors.verticalCenter: parent.verticalCenter
            text: themeEdit.editing ? "Тема «" + themeEdit.editing.pal.label + "»" : ""
        }
    }
    Row {
        anchors { right: parent.right; top: parent.top }
        spacing: 10
        Chip { text: "Копия…"; enabled: themeEdit.editing !== null; onClicked: ownThemes.ask("new", themeEdit.editing) }
        Chip { text: "Экспорт…"; enabled: themeEdit.editing !== null; onClicked: ownThemes.ask("export", themeEdit.editing) }
        Chip {
            visible: themeEdit.editing !== null && !themeEdit.editing.current
            text: "Удалить"
            onClicked: ownThemes.ask("delete", themeEdit.editing)
        }
        Chip { text: "Сбросить раздел"; enabled: themeEdit.editing !== null && themeEdit.sectionEdited(); onClicked: themeEdit.resetSection() }
        Chip { text: "К заводским"; enabled: themeEdit.editing !== null; onClicked: ownThemes.ask("factory", themeEdit.editing) }
        Chip { visible: themeEdit.editing !== null && !themeEdit.editing.current; text: "Включить тему"; onClicked: { themeEdit.switchTo(); editor.switched(); } }
        Chip { text: "Сохранить"; primary: true; enabled: themeEdit.dirty; onClicked: themeEdit.save() }
    }
    Row {
        id: sectionTabs
        anchors { left: parent.left; top: editHeader.bottom; topMargin: 16 }
        spacing: 8
        Repeater {
            model: themeEdit.sections
            TabButton {
                required property var modelData
                text: modelData[1]
                active: themeEdit.section === modelData[0]
                onClicked: themeEdit.section = modelData[0]
            }
        }
    }
    Text {
        anchors { right: parent.right; verticalCenter: sectionTabs.verticalCenter }
        text: !themeEdit.editing ? "" : themeEdit.editing.current ? "Тема включена: изменения применятся при сохранении"
                                                                   : "Изменения применятся, когда включишь эту тему"
        font.family: Theme.bodyFont; font.pixelSize: 13
        color: Theme.muted
    }

    Item {
        anchors { left: parent.left; right: parent.right; top: sectionTabs.bottom; bottom: parent.bottom; topMargin: 20 }
        FontsSection { themeEdit: editor.themeEdit; anchors.fill: parent; visible: themeEdit.section === "fonts" }
        ColorsSection { themeEdit: editor.themeEdit; anchors.fill: parent; visible: themeEdit.section === "colors" }
        WallpapersSection { themeEdit: editor.themeEdit; userFiles: editor.userFiles; anchors.fill: parent; visible: themeEdit.section === "wallpapers" }
        PanelSection { themeEdit: editor.themeEdit; anchors.fill: parent; visible: themeEdit.section === "waybar" }
        IconsSection { themeEdit: editor.themeEdit; anchors.fill: parent; visible: themeEdit.section === "icons" }
        WindowsSection { themeEdit: editor.themeEdit; anchors.fill: parent; visible: themeEdit.section === "windows" }
        CursorSection { themeEdit: editor.themeEdit; userFiles: editor.userFiles; anchors.fill: parent; visible: themeEdit.section === "cursor" }
        FramePicker { userFiles: editor.userFiles; anchors.fill: parent; z: 20; visible: userFiles.frameSource !== "" }
        EnginePicker { userFiles: editor.userFiles; anchors.fill: parent; z: 20; visible: userFiles.engineOpen }
        InstallDialog { themeEdit: editor.themeEdit; anchors.fill: parent; z: 30; visible: themeEdit.installing !== null }
    }
}
