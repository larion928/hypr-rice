// The games window (Alt+G): the user's games as cards with covers; a click starts one. Games are added from a
// file (.exe through Proton, .AppImage, a program), from the installed programs or from the Steam library.
// ~/.config/hypr/scripts/games.py keeps the library and starts the games.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common
import "../common/url.js" as Url

OverlayPanel {
    id: menu

    readonly property string backend: Quickshell.env("HOME") + "/.config/hypr/scripts/games.py"

    property var games: []
    property var steamGames: []
    property string query: ""
    property int current: 0
    property bool picking: false   // a file dialog is open: the window steps aside
    property string dialog: ""     // "add" or "edit": what is open over the shelf
    property var editing: null     // the game the edit dialog is for
    property string message: ""    // the last error
    property string pickFor: ""    // what the file dialog is for: "game" or "cover"

    readonly property var shown: {
        const q = query.trim().toLowerCase();
        return q ? games.filter(g => g.name.toLowerCase().includes(q)) : games;
    }
    readonly property var kindNames: ({ exe: "Proton", appimage: "AppImage", native: "Linux", app: "программа", steam: "Steam" })
    readonly property bool steamRead: !steamProc.running

    function back() {
        if (dialog) {
            dialog = "";
        } else {
            close();
        }
    }

    function launch(game) {
        if (!game) {
            return;
        }
        if (!game.present) {
            message = "«" + game.name + "» больше нет на месте: " + game.target;
            return;
        }
        Quickshell.execDetached(["python3", backend, "launch", game.id]);
        close();
    }

    function move(step) {
        if (shown.length) {
            current = Math.max(0, Math.min(shown.length - 1, current + step));
        }
    }

    function run(args) {
        message = "";
        runner.start(args, (lines, status) => {
            if (status !== 0) {
                message = lines.join(" ") || "не вышло (код " + status + ")";
            }
            listProc.running = true;
            findProc.running = true;  // a new game gets its picture
        });
    }

    function edit(game) {
        editing = game;
        message = "";
        dialog = "edit";
    }

    // zenity, then games.py with the picked file: "add-file" or "cover".
    function pickFile(kind) {
        pickFor = kind;
        picking = true;
        fileProc.command = kind === "cover"
            ? ["zenity", "--file-selection", "--title=Обложка игры", "--file-filter=Картинки | *.png *.jpg *.jpeg *.webp"]
            : ["zenity", "--file-selection", "--title=Игра", "--file-filter=Игры и программы | *.exe *.msi *.AppImage *.appimage",
               "--file-filter=Все файлы | *"];
        fileProc.running = true;
    }

    function picked(path) {
        if (!path) {
            return;
        }
        if (pickFor === "cover") {
            run(["cover", editing.id, path]);
        } else {
            run(["add-file", path]);
            dialog = "";
        }
    }

    // A program's icon: a name from the icon theme, or (as some .desktop files give it) a picture's path.
    function iconSource(icon) {
        if (!icon) {
            return "";
        }
        return icon.startsWith("/") ? Url.fromPath(icon) : Quickshell.iconPath(icon, true);
    }

    function added(kind, target) {
        return games.some(g => g.kind === kind && g.target === target);
    }

    function readSteam() {
        if (!steamGames.length) {
            steamProc.running = true;
        }
    }

    // games.py's JSON on stdout; when that is not JSON, what it said on stderr is the message (an empty shelf
    // alone would look like "no games yet").
    function parsed(what, code, out, err) {
        try {
            return JSON.parse(out.text);
        } catch (e) {
            message = "games.py " + what + ": " + (err.text.trim().split("\n").pop() || "код " + code);
            return null;
        }
    }

    namespace: "games"
    visible: !picking
    dim: 0.72

    onKeyPressed: event => {
        if (dialog) {
            return;
        }
        if (event.key === Qt.Key_Left) {
            move(-1);
        } else if (event.key === Qt.Key_Right) {
            move(1);
        } else if (event.key === Qt.Key_Up) {
            move(-shelf.columns);
        } else if (event.key === Qt.Key_Down) {
            move(shelf.columns);
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            launch(shown[current]);
        } else if (event.text && event.text.trim()) {
            search.type(event.text);
        }
        event.accepted = true;
    }

    Process {
        id: listProc
        command: ["python3", menu.backend, "list"]
        running: true
        stdout: StdioCollector { id: listOut }
        stderr: StdioCollector { id: listErr }
        onExited: code => {
            menu.games = menu.parsed("list", code, listOut, listErr) || menu.games;
            menu.current = Math.min(menu.current, Math.max(0, menu.shown.length - 1));
        }
    }
    // Pictures for games that have none: found in the background, then the shelf is read again.
    Process {
        id: findProc
        command: ["python3", menu.backend, "find"]
        running: true
        onExited: listProc.running = true
    }
    Process {
        id: steamProc
        command: ["python3", menu.backend, "steam"]
        stdout: StdioCollector { id: steamOut }
        stderr: StdioCollector { id: steamErr }
        onExited: code => menu.steamGames = menu.parsed("steam", code, steamOut, steamErr) || []
    }
    ScriptRunner { id: runner; script: menu.backend }
    Process {
        id: fileProc
        stdout: StdioCollector { onStreamFinished: menu.picked(this.text.trim()) }
        onExited: menu.picking = false
    }

    Rectangle {
        id: sheet
        anchors.centerIn: parent
        width: Math.min(parent.width - 80, 1240)
        height: Math.min(parent.height - 80, 820)
        radius: Theme.radius(22)
        color: Theme.alpha(Theme.bg, 0.96)
        border.width: Theme.border
        border.color: Theme.alpha(Theme.accent, 0.5)
        MouseArea { anchors.fill: parent; onClicked: menu.focusScene() }

        Row {
            id: header
            anchors { left: parent.left; top: parent.top; margins: 26 }
            spacing: 16
            HeaderTitle {
                anchors.verticalCenter: parent.verticalCenter
                icon: "\u{f0297}"
                text: "Игры"
                size: 28
                markSize: 28
                spacing: 16
            }
            Field {
                id: search
                anchors.verticalCenter: parent.verticalCenter
                width: 300
                placeholder: "\u{f0349}  найти"
                onTextChanged: {
                    menu.query = text;
                    menu.current = 0;
                }
                onAccepted: menu.launch(menu.shown[menu.current])
                onEscaped: {
                    if (text) {
                        text = "";
                    } else {
                        menu.back();
                    }
                }
            }
        }
        Chip {
            anchors { right: parent.right; verticalCenter: header.verticalCenter; rightMargin: 26 }
            glyph: "\u{f0415}"
            text: "Добавить"
            primary: true
            onClicked: {
                menu.message = "";
                menu.dialog = "add";
            }
        }
        Text {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 26 }
            visible: text !== ""
            text: menu.message
            elide: Text.ElideRight
            font.family: Theme.bodyFont; font.pixelSize: 13
            color: Theme.crit
        }

        GridView {
            id: shelf
            readonly property int columns: Math.max(1, Math.floor(width / cellWidth))
            anchors { left: parent.left; right: parent.right; top: header.bottom; bottom: parent.bottom
                      leftMargin: 26; rightMargin: 26; topMargin: 22; bottomMargin: 46 }
            clip: true
            cellWidth: 196; cellHeight: 330
            boundsBehavior: Flickable.StopAtBounds
            model: menu.shown
            currentIndex: menu.current
            delegate: GameCard {
                required property var modelData
                required property int index
                game: modelData
                chosen: menu.current === index
                kindName: menu.kindNames[modelData.kind]
                iconSource: menu.iconSource(modelData.icon)
                onHovered: menu.current = index
                onLaunched: menu.launch(modelData)
                onEdited: menu.edit(modelData)
            }
        }
        Text {
            anchors.centerIn: shelf
            visible: !menu.games.length && !listProc.running
            width: 560
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: "Пока пусто. «Добавить»: файл игры (.exe пойдёт через Proton, .AppImage, программа), "
                  + "программа из системы, например osu!, или игра из Steam."
            font.family: Theme.bodyFont; font.pixelSize: 16
            color: Theme.muted
        }
    }

    AddDialog { anchors.fill: parent; visible: menu.dialog === "add"; library: menu }
    EditDialog { anchors.fill: parent; visible: menu.dialog === "edit"; library: menu }
}
