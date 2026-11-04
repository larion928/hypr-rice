// The games window, toggled by ~/.local/bin/games (Alt+G): the user's games as cards with covers; a
// click starts one. Games are added from a file (.exe through Proton, .AppImage, a program), from
// the installed programs or from the Steam library. ~/.config/hypr/scripts/games.py keeps the
// library and starts the games.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import "common"
import "common/color.js" as Color

ShellRoot {
    id: root

    Theme { id: theme }

    readonly property string home: Quickshell.env("HOME")
    readonly property string backend: home + "/.config/hypr/scripts/games.py"
    readonly property int r: Math.min(theme.ui.radius ?? 14, 22)

    property var games: []
    property var steamGames: []
    property string query: ""
    property int current: 0
    property bool closing: false
    property bool picking: false   // a file dialog is open: the window steps aside
    property string dialog: ""     // "add" or "edit": what is open over the shelf
    property string addTab: "file" // file, steam, apps
    property var editing: null     // the game the edit dialog is for
    property string message: ""    // the last error

    readonly property var shown: {
        const q = root.query.trim().toLowerCase();
        return q ? root.games.filter(g => g.name.toLowerCase().includes(q)) : root.games;
    }
    readonly property var kindNames: ({ exe: "Proton", appimage: "AppImage", native: "Linux", app: "программа", steam: "Steam" })

    Component.onCompleted: listProc.running = true

    function close() {
        if (closing) return;
        closing = true;
        outAnim.start();
    }
    function back() {
        if (root.dialog) root.dialog = "";
        else root.close();
    }
    function launch(game) {
        if (!game) return;
        if (!game.present) {
            root.message = "«" + game.name + "» больше нет на месте: " + game.target;
            return;
        }
        Quickshell.execDetached(["python3", root.backend, "launch", game.id]);
        root.close();
    }
    function move(step) {
        if (root.shown.length) root.current = Math.max(0, Math.min(root.shown.length - 1, root.current + step));
    }

    // games.py with its output and then "@@exit <status>": one stream, so nothing comes after the end.
    function run(args) {
        root.message = "";
        runProc.command = ["sh", "-c", 'python3 "$0" "$@" 2>&1; echo "@@exit $?"', root.backend].concat(args);
        runProc.running = true;
    }
    function ran(output) {
        const lines = output.trim().split("\n");
        const code = parseInt(lines.pop().replace("@@exit ", ""));
        if (code !== 0) root.message = lines.join(" ") || "не вышло (код " + code + ")";
        listProc.running = true;
    }
    // zenity, then games.py with the picked file: "add-file" or "cover".
    property string pickFor: ""
    function pickFile(kind) {
        root.pickFor = kind;
        root.picking = true;
        fileProc.command = kind === "cover"
            ? ["zenity", "--file-selection", "--title=Обложка игры", "--file-filter=Картинки | *.png *.jpg *.jpeg *.webp"]
            : ["zenity", "--file-selection", "--title=Игра", "--file-filter=Игры и программы | *.exe *.msi *.AppImage *.appimage",
               "--file-filter=Все файлы | *"];
        fileProc.running = true;
    }
    function picked(path) {
        if (!path) return;
        if (root.pickFor === "cover") root.run(["cover", root.editing.id, path]);
        else {
            root.run(["add-file", path]);
            root.dialog = "";
        }
    }
    // A program's icon: a name from the icon theme, or (as some .desktop files give it) a picture's path.
    function iconSource(icon) {
        if (!icon) return "";
        return icon.startsWith("/") ? "file://" + icon : Quickshell.iconPath(icon, true);
    }
    function added(kind, target) {
        return root.games.some(g => g.kind === kind && g.target === target);
    }

    Process {
        id: listProc
        command: ["python3", root.backend, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.games = JSON.parse(this.text); } catch (e) { root.games = []; }
                root.current = Math.min(root.current, Math.max(0, root.shown.length - 1));
            }
        }
    }
    Process {
        id: steamProc
        command: ["python3", root.backend, "steam"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.steamGames = JSON.parse(this.text); } catch (e) { root.steamGames = []; }
            }
        }
    }
    Process {
        id: runProc
        stdout: StdioCollector { onStreamFinished: root.ran(this.text) }
    }
    Process {
        id: fileProc
        stdout: StdioCollector { onStreamFinished: root.picked(this.text.trim()) }
        onExited: root.picking = false
    }

    IpcHandler {
        target: "panel"
        function close(): void { root.close(); }
    }

    PanelWindow {
        visible: !root.picking
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "games"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        Item {
            id: scene
            anchors.fill: parent
            opacity: 0
            focus: true
            Component.onCompleted: inAnim.start()
            NumberAnimation { id: inAnim; target: scene; property: "opacity"; to: 1; duration: 180 }
            SequentialAnimation {
                id: outAnim
                NumberAnimation { target: scene; property: "opacity"; to: 0; duration: 150 }
                ScriptAction { script: Qt.quit() }
            }

            Keys.onPressed: e => {
                if (e.key === Qt.Key_Escape) root.back();
                else if (root.dialog) return;
                else if (e.key === Qt.Key_Left) root.move(-1);
                else if (e.key === Qt.Key_Right) root.move(1);
                else if (e.key === Qt.Key_Up) root.move(-shelf.columns);
                else if (e.key === Qt.Key_Down) root.move(shelf.columns);
                else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) root.launch(root.shown[root.current]);
                else if (e.text && e.text.trim()) {
                    search.focusWith(e.text);
                }
                e.accepted = true;
            }

            Rectangle { anchors.fill: parent; color: Color.withAlpha(theme.c.bg, 0.72) }
            MouseArea { anchors.fill: parent; onClicked: root.close() }

            Rectangle {
                id: sheet
                anchors.centerIn: parent
                width: Math.min(parent.width - 80, 1240)
                height: Math.min(parent.height - 80, 820)
                radius: root.r
                color: Color.withAlpha(theme.c.bg, 0.96)
                border.width: theme.ui.border ?? 1
                border.color: Color.withAlpha(theme.c.accent, 0.5)
                MouseArea { anchors.fill: parent; onClicked: scene.forceActiveFocus() }

                Row {
                    id: header
                    anchors { left: parent.left; top: parent.top; margins: 26 }
                    spacing: 16
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\u{f0297}"
                        font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 28
                        color: theme.c.accent || "white"
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Игры"
                        font.family: theme.titleFont; font.pixelSize: 28; font.italic: !!theme.ui.italicTitle
                        color: theme.c.fg || "white"
                    }
                    Field {
                        id: search
                        anchors.verticalCenter: parent.verticalCenter
                        width: 300
                        placeholder: "\u{f0349}  найти"
                        onTextChanged: { root.query = text; root.current = 0; }
                        onAccepted: root.launch(root.shown[root.current])
                    }
                }
                Chip {
                    anchors { right: parent.right; verticalCenter: header.verticalCenter; rightMargin: 26 }
                    text: "\u{f0415}  Добавить"
                    primary: true
                    onClicked: { root.message = ""; root.dialog = "add"; }
                }
                Text {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 26 }
                    visible: text !== ""
                    text: root.message
                    elide: Text.ElideRight
                    font.family: theme.bodyFont; font.pixelSize: 13
                    color: theme.c.crit || "red"
                }

                GridView {
                    id: shelf
                    readonly property int columns: Math.max(1, Math.floor(width / cellWidth))
                    anchors { left: parent.left; right: parent.right; top: header.bottom; bottom: parent.bottom
                              leftMargin: 26; rightMargin: 26; topMargin: 22; bottomMargin: 46 }
                    clip: true
                    cellWidth: 196; cellHeight: 330
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.shown
                    currentIndex: root.current
                    delegate: GameCard {}
                }
                Text {
                    anchors.centerIn: shelf
                    visible: !root.games.length && !listProc.running
                    width: 560
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: "Пока пусто. «Добавить»: файл игры (.exe пойдёт через Proton, .AppImage, программа), "
                          + "программа из системы, например osu!, или игра из Steam."
                    font.family: theme.bodyFont; font.pixelSize: 16
                    color: theme.c.muted || "grey"
                }
            }

            AddDialog { anchors.fill: parent; visible: root.dialog === "add" }
            EditDialog { anchors.fill: parent; visible: root.dialog === "edit" }
        }
    }

    // ================= components =================

    // A game: its cover (or its program's icon, or its first letter), its name and how it starts.
    component GameCard: Item {
        id: card
        required property var modelData
        required property int index
        readonly property bool chosen: root.current === index
        width: 196; height: 330
        // Hover from a handler: it stays on over the edit button too, which a MouseArea would lose.
        HoverHandler {
            id: cardHover
            onHoveredChanged: if (hovered) root.current = card.index
        }

        Rectangle {
            id: coverBox
            x: 8; y: 8; width: 180; height: 270
            radius: Math.min(root.r, 12)
            color: theme.c.bg2 || "black"
            clip: true
            border.width: card.chosen || cardHover.hovered ? 2 : 0
            border.color: theme.c.accent || "white"
            opacity: card.modelData.present ? 1 : 0.45
            scale: cardHover.hovered ? 1.03 : 1
            Behavior on scale { NumberAnimation { duration: 120 } }

            Image {
                id: coverImage
                anchors.fill: parent
                anchors.margins: parent.border.width
                visible: card.modelData.cover !== ""
                source: card.modelData.cover ? "file://" + card.modelData.cover : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }
            IconImage {
                anchors.centerIn: parent
                visible: !coverImage.visible && card.modelData.kind === "app"
                implicitSize: 88
                source: card.modelData.kind === "app" ? root.iconSource(card.modelData.icon) : ""
            }
            Text {
                anchors.centerIn: parent
                visible: !coverImage.visible && card.modelData.kind !== "app"
                text: card.modelData.name.charAt(0).toUpperCase()
                font.family: theme.titleFont; font.pixelSize: 96
                color: theme.c.accent || "white"
            }
            Rectangle {
                anchors { left: parent.left; bottom: parent.bottom; margins: 8 }
                width: kindText.implicitWidth + 12; height: 22
                radius: 6
                color: Color.withAlpha(theme.c.bg, 0.85)
                Text {
                    id: kindText
                    anchors.centerIn: parent
                    text: card.modelData.present ? root.kindNames[card.modelData.kind] : "нет на месте"
                    font.family: theme.bodyFont; font.pixelSize: 12
                    color: card.modelData.present ? (theme.c.muted || "grey") : (theme.c.crit || "red")
                }
            }
            Row {
                anchors { right: parent.right; top: parent.top; margins: 8 }
                visible: cardHover.hovered
                spacing: 6
                IconButton { glyph: "\u{f03eb}"; onClicked: { root.editing = card.modelData; root.message = ""; root.dialog = "edit"; } }
            }
        }
        Text {
            anchors { left: coverBox.left; right: coverBox.right; top: coverBox.bottom; topMargin: 8 }
            text: card.modelData.name
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
            font.family: theme.bodyFont; font.pixelSize: 15
            color: card.chosen ? (theme.c.accent || "white") : (theme.c.fg || "white")
        }
        MouseArea {
            anchors.fill: coverBox
            z: -1
            onClicked: root.launch(card.modelData)
        }
    }

    // Adding a game: a file, a Steam game or an installed program.
    component AddDialog: Rectangle {
        color: Color.withAlpha(theme.c.bg, 0.85)
        MouseArea { anchors.fill: parent; onClicked: root.dialog = "" }
        onVisibleChanged: if (visible && !root.steamGames.length) steamProc.running = true

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 120, 900); height: Math.min(parent.height - 120, 640)
            radius: root.r
            color: theme.c.bg2 || "black"
            border.color: Color.withAlpha(theme.c.accent, 0.5)
            MouseArea { anchors.fill: parent }

            Row {
                id: addTabs
                anchors { left: parent.left; top: parent.top; margins: 22 }
                spacing: 8
                Repeater {
                    model: [["file", "Файл"], ["steam", "Steam"], ["apps", "Программы"]]
                    Chip {
                        required property var modelData
                        text: modelData[1]
                        active: root.addTab === modelData[0]
                        onClicked: root.addTab = modelData[0]
                    }
                }
            }
            Chip {
                anchors { right: parent.right; verticalCenter: addTabs.verticalCenter; rightMargin: 22 }
                text: "Готово"
                onClicked: root.dialog = ""
            }

            Item {
                anchors { left: parent.left; right: parent.right; top: addTabs.bottom; bottom: parent.bottom; margins: 22 }

                // ---- a file
                Column {
                    visible: root.addTab === "file"
                    width: parent.width
                    spacing: 16
                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: "Файл игры: .exe (и .msi) запустится через Proton с карточкой загрузки, .AppImage и "
                              + "программа Linux — как есть. Название возьмётся из имени файла, его можно поменять."
                        font.family: theme.bodyFont; font.pixelSize: 14
                        color: theme.c.fg || "white"
                    }
                    Chip { text: "Выбрать файл…"; primary: true; onClicked: root.pickFile("game") }
                }

                // ---- the Steam library
                GridView {
                    visible: root.addTab === "steam"
                    anchors.fill: parent
                    clip: true
                    cellWidth: 130; cellHeight: 220
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.steamGames
                    delegate: Item {
                        id: steamCell
                        required property var modelData
                        readonly property bool inLibrary: root.added("steam", modelData.appid)
                        width: 130; height: 220
                        Rectangle {
                            x: 6; y: 6; width: 118; height: 177
                            radius: 8
                            color: theme.c.bg || "black"
                            clip: true
                            border.width: steamArea.containsMouse ? 2 : 0
                            border.color: theme.c.accent || "white"
                            opacity: steamCell.inLibrary ? 0.4 : 1
                            Image {
                                anchors.fill: parent
                                source: steamCell.modelData.cover ? "file://" + steamCell.modelData.cover : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                            }
                            MouseArea {
                                id: steamArea
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: !steamCell.inLibrary
                                onClicked: root.run(["add-steam", steamCell.modelData.appid, steamCell.modelData.name])
                            }
                        }
                        Text {
                            x: 6; y: 188; width: 118
                            text: (steamCell.inLibrary ? "✓ " : "") + steamCell.modelData.name
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignHCenter
                            font.family: theme.bodyFont; font.pixelSize: 13
                            color: steamCell.inLibrary ? (theme.c.muted || "grey") : (theme.c.fg || "white")
                        }
                    }
                }
                Text {
                    visible: root.addTab === "steam" && !root.steamGames.length && !steamProc.running
                    text: "Игр Steam не нашлось."
                    font.family: theme.bodyFont; font.pixelSize: 14
                    color: theme.c.muted || "grey"
                }

                // ---- installed programs, games first
                Item {
                    visible: root.addTab === "apps"
                    anchors.fill: parent
                    Field {
                        id: appSearch
                        width: 320
                        placeholder: "\u{f0349}  найти программу"
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
                            readonly property bool inLibrary: root.added("app", modelData.id)
                            width: ListView.view.width; height: 46
                            radius: root.r > 4 ? 8 : 0
                            color: appArea.containsMouse && !inLibrary ? Color.withAlpha(theme.c.accent, 0.12) : "transparent"
                            IconImage {
                                id: appIcon
                                x: 10; anchors.verticalCenter: parent.verticalCenter
                                implicitSize: 30
                                source: root.iconSource(appRow.modelData.icon)
                            }
                            Text {
                                anchors { left: appIcon.right; leftMargin: 12; verticalCenter: parent.verticalCenter }
                                text: appRow.modelData.name + ((appRow.modelData.categories || []).includes("Game") ? "   · игра" : "")
                                      + (appRow.inLibrary ? "   ✓ уже в списке" : "")
                                font.family: theme.bodyFont; font.pixelSize: 15
                                color: appRow.inLibrary ? (theme.c.muted || "grey") : (theme.c.fg || "white")
                            }
                            MouseArea {
                                id: appArea
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: !appRow.inLibrary
                                onClicked: root.run(["add-app", appRow.modelData.id, appRow.modelData.name, appRow.modelData.icon || ""])
                            }
                        }
                    }
                }
            }
        }
    }

    // One game: its name, its cover, or out of the list.
    component EditDialog: Rectangle {
        color: Color.withAlpha(theme.c.bg, 0.85)
        MouseArea { anchors.fill: parent; onClicked: root.dialog = "" }
        onVisibleChanged: if (visible && root.editing) nameField.text = root.editing.name

        Rectangle {
            anchors.centerIn: parent
            width: 520; height: editColumn.implicitHeight + 44
            radius: root.r
            color: theme.c.bg2 || "black"
            border.color: Color.withAlpha(theme.c.accent, 0.5)
            MouseArea { anchors.fill: parent }
            Column {
                id: editColumn
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 22 }
                spacing: 14
                Text {
                    text: "Игра"
                    font.family: theme.titleFont; font.pixelSize: 20; font.italic: !!theme.ui.italicTitle
                    color: theme.c.accent2 || theme.c.accent || "white"
                }
                Text {
                    width: parent.width
                    elide: Text.ElideMiddle
                    text: root.editing ? root.kindNames[root.editing.kind] + " · " + root.editing.target : ""
                    font.family: theme.font; font.pixelSize: 12
                    color: theme.c.muted || "grey"
                }
                Field {
                    id: nameField
                    width: parent.width
                    placeholder: "название"
                    onAccepted: saveName.clicked()
                }
                Row {
                    spacing: 10
                    Chip { id: saveName; text: "Сохранить название"; primary: true; onClicked: { root.run(["rename", root.editing.id, nameField.text]); root.dialog = ""; } }
                    Chip { text: "Обложка…"; onClicked: root.pickFile("cover") }
                    Chip { text: "Убрать из списка"; onClicked: { root.run(["remove", root.editing.id]); root.dialog = ""; } }
                }
            }
        }
    }

    component Chip: Rectangle {
        id: chip
        property string text
        property bool active
        property bool primary
        signal clicked()
        width: chipText.implicitWidth + 28; height: 36
        radius: root.r > 4 ? 9 : 0
        color: primary ? (theme.c.accent || "white") : active ? Color.withAlpha(theme.c.accent, 0.28)
               : (chipArea.containsMouse ? Color.withAlpha(theme.c.accent, 0.12) : Color.withAlpha(theme.c.bg2, 0.9))
        border.color: active || primary ? (theme.c.accent || "white") : Color.withAlpha(theme.c.muted, 0.35)
        Text {
            id: chipText
            anchors.centerIn: parent
            text: chip.text
            font.family: theme.bodyFont; font.pixelSize: 14; font.bold: chip.active || chip.primary
            color: chip.primary ? (theme.c.bg || "black") : chip.active ? (theme.c.accent || "white") : (theme.c.fg || "white")
        }
        MouseArea { id: chipArea; anchors.fill: parent; hoverEnabled: true; onClicked: chip.clicked() }
    }

    component IconButton: Rectangle {
        id: iconButton
        property string glyph
        signal clicked()
        width: 30; height: 30
        radius: 15
        color: iconArea.containsMouse ? (theme.c.accent || "white") : Color.withAlpha(theme.c.bg, 0.85)
        Text {
            anchors.centerIn: parent
            text: iconButton.glyph
            font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 15
            color: iconArea.containsMouse ? (theme.c.bg || "black") : (theme.c.fg || "white")
        }
        MouseArea { id: iconArea; anchors.fill: parent; hoverEnabled: true; onClicked: iconButton.clicked() }
    }

    component Field: Rectangle {
        id: field
        property alias text: input.text
        property string placeholder
        signal accepted()
        function focusWith(typed) {
            input.text += typed;
            input.forceActiveFocus();
        }
        height: 36
        radius: root.r > 4 ? 9 : 0
        color: Color.withAlpha(theme.c.bg2, 0.9)
        border.color: input.activeFocus ? (theme.c.accent || "white") : Color.withAlpha(theme.c.muted, 0.35)
        TextInput {
            id: input
            anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
            verticalAlignment: TextInput.AlignVCenter
            font.family: theme.bodyFont; font.pixelSize: 14
            color: theme.c.fg || "white"
            selectionColor: Color.withAlpha(theme.c.accent, 0.4)
            clip: true
            Keys.onEscapePressed: {
                if (input.text) input.text = "";
                else { scene.forceActiveFocus(); root.back(); }
            }
            Keys.onUpPressed: scene.forceActiveFocus()
            Keys.onDownPressed: scene.forceActiveFocus()
            onAccepted: field.accepted()
        }
        Text {
            anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
            visible: !input.text && !input.activeFocus
            text: field.placeholder
            font.family: theme.bodyFont; font.pixelSize: 14
            color: theme.c.muted || "grey"
        }
        MouseArea { anchors.fill: parent; onClicked: input.forceActiveFocus() }
    }
}
