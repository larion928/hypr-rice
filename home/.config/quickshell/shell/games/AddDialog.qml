import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.common
import "../common/url.js" as Url

// Adding a game: a file, a Steam game or an installed program.
Rectangle {
    id: dialog

    required property var library   // the games window
    property string tab: "file"     // file, steam, apps

    color: Theme.alpha(Theme.bg, 0.85)
    onVisibleChanged: if (visible) library.readSteam()
    MouseArea { anchors.fill: parent; onClicked: dialog.library.dialog = "" }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - 120, 900); height: Math.min(parent.height - 120, 640)
        radius: Theme.radius(22)
        color: Theme.bg2
        border.color: Theme.alpha(Theme.accent, 0.5)
        MouseArea { anchors.fill: parent }

        Row {
            id: tabs
            anchors { left: parent.left; top: parent.top; margins: 22 }
            spacing: 8
            Repeater {
                model: [["file", "Файл"], ["steam", "Steam"], ["apps", "Программы"]]
                Chip {
                    required property var modelData
                    text: modelData[1]
                    active: dialog.tab === modelData[0]
                    onClicked: dialog.tab = modelData[0]
                }
            }
        }
        Chip {
            anchors { right: parent.right; verticalCenter: tabs.verticalCenter; rightMargin: 22 }
            text: "Готово"
            onClicked: dialog.library.dialog = ""
        }

        Item {
            anchors { left: parent.left; right: parent.right; top: tabs.bottom; bottom: parent.bottom; margins: 22 }

            // ---- a file
            Column {
                visible: dialog.tab === "file"
                width: parent.width
                spacing: 16
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "Файл игры: .exe (и .msi) запустится через Proton с карточкой загрузки, .AppImage и "
                          + "программа Linux — как есть. Название возьмётся из имени файла, его можно поменять."
                    font.family: Theme.bodyFont; font.pixelSize: 14
                    color: Theme.fg
                }
                Chip { text: "Выбрать файл…"; primary: true; onClicked: dialog.library.pickFile("game") }
            }

            // ---- the Steam library
            GridView {
                visible: dialog.tab === "steam"
                anchors.fill: parent
                clip: true
                cellWidth: 130; cellHeight: 220
                boundsBehavior: Flickable.StopAtBounds
                model: dialog.library.steamGames
                delegate: Item {
                    id: steamCell
                    required property var modelData
                    readonly property bool inLibrary: dialog.library.added("steam", modelData.appid)
                    width: 130; height: 220
                    Rectangle {
                        x: 6; y: 6; width: 118; height: 177
                        radius: 8
                        color: Theme.bg
                        clip: true
                        border.width: steamArea.containsMouse ? 2 : 0
                        border.color: Theme.accent
                        opacity: steamCell.inLibrary ? 0.4 : 1
                        Image {
                            anchors.fill: parent
                            source: Url.fromPath(steamCell.modelData.cover)
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }
                        MouseArea {
                            id: steamArea
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: !steamCell.inLibrary
                            onClicked: dialog.library.run(["add-steam", steamCell.modelData.appid, steamCell.modelData.name])
                        }
                    }
                    Text {
                        x: 6; y: 188; width: 118
                        text: (steamCell.inLibrary ? "✓ " : "") + steamCell.modelData.name
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignHCenter
                        font.family: Theme.bodyFont; font.pixelSize: 13
                        color: steamCell.inLibrary ? Theme.muted : Theme.fg
                    }
                }
            }
            Text {
                visible: dialog.tab === "steam" && !dialog.library.steamGames.length && dialog.library.steamRead
                text: "Игр Steam не нашлось."
                font.family: Theme.bodyFont; font.pixelSize: 14
                color: Theme.muted
            }

            // ---- installed programs, games first
            Item {
                visible: dialog.tab === "apps"
                anchors.fill: parent
                Field {
                    id: appSearch
                    width: 320
                    placeholder: "\u{f0349}  найти программу"
                    onEscaped: dialog.library.back()
                }
                ListView {
                    anchors { left: parent.left; right: parent.right; top: appSearch.bottom; bottom: parent.bottom; topMargin: 12 }
                    clip: true
                    spacing: 4
                    boundsBehavior: Flickable.StopAtBounds
                    model: {
                        const q = appSearch.text.trim().toLowerCase();
                        const isGame = e => (e.categories || []).includes("Game");
                        return DesktopEntries.applications.values
                            .filter(e => !e.noDisplay && (!q || e.name.toLowerCase().includes(q)))
                            .sort((x, y) => isGame(y) - isGame(x) || x.name.localeCompare(y.name));
                    }
                    delegate: Rectangle {
                        id: appRow
                        required property var modelData
                        readonly property bool inLibrary: dialog.library.added("app", modelData.id)
                        width: ListView.view.width; height: 46
                        radius: Theme.rounded ? 8 : 0
                        color: appArea.containsMouse && !inLibrary ? Theme.alpha(Theme.accent, 0.12) : "transparent"
                        IconImage {
                            id: appIcon
                            x: 10; anchors.verticalCenter: parent.verticalCenter
                            implicitSize: 30
                            source: dialog.library.iconSource(appRow.modelData.icon)
                        }
                        Text {
                            anchors { left: appIcon.right; leftMargin: 12; verticalCenter: parent.verticalCenter }
                            text: appRow.modelData.name + ((appRow.modelData.categories || []).includes("Game") ? "   · игра" : "")
                                  + (appRow.inLibrary ? "   ✓ уже в списке" : "")
                            font.family: Theme.bodyFont; font.pixelSize: 15
                            color: appRow.inLibrary ? Theme.muted : Theme.fg
                        }
                        MouseArea {
                            id: appArea
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: !appRow.inLibrary
                            onClicked: dialog.library.run(["add-app", appRow.modelData.id, appRow.modelData.name, appRow.modelData.icon || ""])
                        }
                    }
                }
            }
        }
    }
}
