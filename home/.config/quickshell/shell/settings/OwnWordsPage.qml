import QtQuick
import qs.common

// Словарь: the user's own words, which the typo fix and the automatic layout fix know besides the dictionaries';
// the field adds one (a word, or word/model declining like model), a row's button takes it out.
Item {
    id: page

    required property OwnWordsModel ownWords

    function add() {
        if (field.text.trim() === "" || ownWords.busy) {
            return;
        }
        ownWords.add(field.text, () => field.text = "");
    }

    onVisibleChanged: {
        if (visible) {
            ownWords.refresh();
        }
    }

    Column {
        id: intro
        width: parent.width
        spacing: 10

        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Слова, которые исправление опечаток и автоисправление раскладки знают сверх словаря. "
                  + "Alt+Shift+Enter запоминает последнее набранное слово. «слово/образец» склоняется как образец: "
                  + "горутина/машина — «горутины», «горутиной»."
            font.family: Theme.bodyFont; font.pixelSize: 14
            color: Theme.muted
        }
        Row {
            spacing: 10
            Field {
                id: field
                width: 420
                placeholder: "слово или слово/образец, Enter — добавить"
                onAccepted: page.add()
            }
            IconButton {
                anchors.verticalCenter: field.verticalCenter
                glyph: "\uf067"
                onClicked: page.add()
            }
        }
    }

    Row {
        id: columns
        anchors { left: parent.left; right: parent.right; top: intro.bottom; bottom: messageText.top }
        anchors.topMargin: 18
        anchors.bottomMargin: 12
        spacing: 24

        Repeater {
            model: [["Русские", page.ownWords.ru], ["Английские", page.ownWords.us]]
            Item {
                id: language
                required property var modelData
                width: (columns.width - columns.spacing) / 2
                height: columns.height

                SectionTitle { id: title; text: language.modelData[0] }
                Text {
                    anchors { top: title.bottom; topMargin: 6 }
                    visible: language.modelData[1].length === 0
                    text: "Пока пусто"
                    font.family: Theme.bodyFont; font.pixelSize: 14
                    color: Theme.muted
                }
                Flickable {
                    anchors { left: parent.left; right: parent.right; top: title.bottom; bottom: parent.bottom }
                    anchors.topMargin: 6
                    contentHeight: wordList.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: wordList
                        width: parent.width
                        spacing: 4
                        Repeater {
                            model: language.modelData[1]
                            Rectangle {
                                id: row
                                required property string modelData
                                width: wordList.width
                                height: 36
                                radius: Theme.rounded ? 10 : 0
                                color: Theme.alpha(Theme.bg2, 0.6)
                                Text {
                                    anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                                    text: row.modelData
                                    font.family: Theme.bodyFont; font.pixelSize: 14
                                    color: Theme.fg
                                }
                                IconButton {
                                    anchors.right: parent.right
                                    anchors.rightMargin: 6
                                    anchors.verticalCenter: parent.verticalCenter
                                    small: true
                                    danger: true
                                    glyph: "\uf1f8"
                                    onClicked: page.ownWords.remove(row.modelData)
                                }
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
        text: page.ownWords.message
        font.family: Theme.bodyFont; font.pixelSize: 14
        color: Theme.warn
    }
}
