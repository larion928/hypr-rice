import QtQuick
import qs.common

// Функции: the rice's features by group, each with what it does and a switch; one that needs packages not
// installed yet offers to install them first.
Item {
    id: page

    required property FeaturesModel features

    Flickable {
        anchors { left: parent.left; right: parent.right; top: parent.top; bottom: messageText.top; bottomMargin: 12 }
        contentHeight: featureList.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: featureList
            width: parent.width
            spacing: 6

            Repeater {
                model: page.features.groups
                Column {
                    id: group
                    required property string modelData
                    width: featureList.width
                    spacing: 6
                    SectionTitle { text: group.modelData }
                    Repeater {
                        model: page.features.list.filter(feature => feature.group === group.modelData)
                        Rectangle {
                            id: row
                            required property var modelData
                            width: group.width
                            height: texts.implicitHeight + 20
                            radius: Theme.rounded ? 10 : 0
                            color: Theme.alpha(Theme.bg2, 0.6)

                            Column {
                                id: texts
                                anchors { left: parent.left; leftMargin: 14; right: featureSwitch.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                spacing: 3
                                Text {
                                    width: parent.width
                                    wrapMode: Text.WordWrap
                                    text: row.modelData.name
                                    font.family: Theme.bodyFont; font.pixelSize: 14
                                    color: Theme.fg
                                }
                                Text {
                                    width: parent.width
                                    wrapMode: Text.WordWrap
                                    text: row.modelData.about
                                    font.family: Theme.bodyFont; font.pixelSize: 13
                                    color: Theme.muted
                                }
                                Text {
                                    visible: row.modelData.experimental
                                    width: parent.width
                                    wrapMode: Text.WordWrap
                                    text: "Функция экспериментальная, возможны ошибки и баги"
                                    font.family: Theme.bodyFont; font.pixelSize: 13
                                    color: Theme.warn
                                }
                                Text {
                                    visible: row.modelData.missing.length > 0
                                    width: parent.width
                                    wrapMode: Text.WordWrap
                                    text: "Нужно установить: " + row.modelData.missing.join(", ")
                                          + " — установка предложится при включении"
                                    font.family: Theme.bodyFont; font.pixelSize: 13
                                    color: Theme.warn
                                }
                            }
                            Switch {
                                id: featureSwitch
                                anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                                checked: row.modelData.on
                                enabled: !page.features.busy
                                onToggled: page.features.toggle(row.modelData)
                            }
                        }
                    }
                }
            }
        }
    }

    Text {
        id: messageText
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        wrapMode: Text.WordWrap
        text: page.features.message
        font.family: Theme.bodyFont; font.pixelSize: 14
        color: Theme.warn
    }

    InstallDialog { install: page.features.install; anchors.fill: parent; z: 30; visible: install.item !== null }
    AccessDialog { features: page.features; anchors.fill: parent; z: 30; visible: features.asking !== null }
    CautionDialog { features: page.features; anchors.fill: parent; z: 30; visible: features.cautioning !== null }
}
