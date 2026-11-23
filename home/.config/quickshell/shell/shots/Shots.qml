// Screenshot gallery (waybar camera icon): ~/Pictures/screenshots, newest first; a click opens a large preview
// (←/→ to flip). On hover: copy to the clipboard, open in the default viewer, move to the trash (press twice).
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.common
import "../common/keys.js" as KeyName
import "../common/url.js" as Url

OverlayPanel {
    id: menu

    readonly property string dir: Quickshell.env("HOME") + "/Pictures/screenshots"
    property int preview: -1        // index shown large, -1 = grid
    property string armed: ""       // file waiting for a second delete press

    readonly property var months: ["янв", "фев", "мар", "апр", "мая", "июн", "июл", "авг", "сен", "окт", "ноя", "дек"]
    readonly property var imageTypes: ({ png: "image/png", jpg: "image/jpeg", jpeg: "image/jpeg", webp: "image/webp" })

    function pathAt(index) {
        return files.get(index, "filePath");
    }

    // "screenshot_20261006_143300.png" -> "6 окт, 14:33"
    function stamp(name) {
        const m = /(\d{4})(\d{2})(\d{2})_(\d{2})(\d{2})/.exec(name);
        return m ? `${+m[3]} ${months[+m[2] - 1]}, ${m[4]}:${m[5]}` : name;
    }

    function copy(path) {
        const type = imageTypes[path.split(".").pop().toLowerCase()];
        fileAction.start(["sh", "-c", 'wl-copy --type "$2" < "$1"', "sh", path, type], "Скопировано в буфер");
    }

    function open(path) {
        Quickshell.execDetached(["xdg-open", path]);
        close();
    }

    function trash(path) {
        if (armed !== path) {
            armed = path;
            disarm.restart();
            return;
        }
        if (fileAction.running) {
            return;
        }
        armed = "";
        fileAction.start(["gio", "trash", path], "Перемещено в корзину");
        if (preview >= files.count - 1) {
            preview = files.count - 2;
        }
    }

    function back() {
        if (preview >= 0) {
            preview = -1;
        } else {
            close();
        }
    }

    namespace: "shots-gallery"
    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", dir])

    onKeyPressed: event => {
        const count = files.count;
        const name = KeyName.of(event);
        if (count === 0) {
            return;
        }
        const shown = preview >= 0 ? preview : grid.currentIndex;
        if (name === "C") {
            copy(pathAt(shown));
        } else if (event.key === Qt.Key_Delete) {
            trash(pathAt(shown));
        } else if (preview >= 0) {
            const step = KeyName.step(event, 0);
            if (step !== 0) {
                preview = Math.max(0, Math.min(count - 1, preview + step));
            } else if (KeyName.isEnter(event)) {
                open(pathAt(preview));
            }
        } else if (KeyName.isEnter(event)) {
            preview = grid.currentIndex;
        } else if (event.key === Qt.Key_Left) {
            grid.moveCurrentIndexLeft();
        } else if (event.key === Qt.Key_Right) {
            grid.moveCurrentIndexRight();
        } else if (event.key === Qt.Key_Up) {
            grid.moveCurrentIndexUp();
        } else if (event.key === Qt.Key_Down) {
            grid.moveCurrentIndexDown();
        }
    }

    FolderListModel {
        id: files
        folder: Url.fromPath(menu.dir)
        nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp"]
        showDirs: false
        sortField: FolderListModel.Time   // newest first
    }

    // Copy or trash; what it did is flashed only when it worked.
    Process {
        id: fileAction
        property string done: ""
        function start(command, done) {
            if (running) {
                return;
            }
            fileAction.done = done;
            fileAction.command = command;
            running = true;
        }
        onExited: code => {
            flash.text = code === 0 ? done : "Не получилось";
            flash.restart();
        }
    }

    Timer { id: disarm; interval: 3000; onTriggered: menu.armed = "" }

    Rectangle {
        id: sheet
        anchors.centerIn: parent
        width: Math.min(parent.width - 80, 1500)
        height: Math.min(parent.height - 80, 920)
        radius: Theme.radius(22)
        color: Theme.alpha(Theme.bg, 0.95)
        border.width: Theme.border
        border.color: Theme.alpha(Theme.accent, 0.5)
        clip: true
        MouseArea { anchors.fill: parent }

        // ---------- header ----------
        Row {
            id: header
            x: 28; y: 22
            spacing: 12
            HeaderTitle {
                anchors.verticalCenter: parent.verticalCenter
                text: "Скриншоты"
                size: 28
                markSize: 25
                fallbackGlyph: "\uf030"
                spacing: 12
            }
            Text {
                text: files.count
                font.family: Theme.bodyFont; font.pixelSize: 15
                color: Theme.muted
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        Row {
            anchors { right: parent.right; rightMargin: 24; verticalCenter: header.verticalCenter }
            spacing: 8
            Chip {
                glyph: "\uf07c"
                text: "Открыть папку"
                onClicked: {
                    Quickshell.execDetached(["thunar", menu.dir]);
                    menu.close();
                }
            }
            IconButton { glyph: "\uf00d"; filled: true; onClicked: menu.close() }
        }

        // ---------- grid ----------
        GridView {
            id: grid
            visible: menu.preview < 0
            anchors { left: parent.left; right: parent.right; top: header.bottom; bottom: hint.top; margins: 20; topMargin: 18 }
            readonly property int cols: Math.max(2, Math.floor(width / 300))
            cellWidth: Math.floor(width / cols)
            cellHeight: cellWidth * 9 / 16 + 34
            clip: true
            model: files
            boundsBehavior: Flickable.StopAtBounds
            keyNavigationEnabled: false

            delegate: Item {
                id: cell
                required property int index
                required property string fileName
                required property string filePath
                readonly property bool current: grid.currentIndex === index
                width: grid.cellWidth
                height: grid.cellHeight

                ClippingRectangle {
                    id: thumbBox
                    x: 8; y: 6
                    width: parent.width - 16
                    height: width * 9 / 16
                    radius: Theme.radius(12)
                    color: Theme.bg2
                    border.width: cell.current || hover.hovered ? 2 : 1
                    border.color: cell.current || hover.hovered ? Theme.accent : Theme.alpha(Theme.muted, 0.3)
                    Image {
                        anchors.fill: parent
                        source: Url.fromPath(cell.filePath)
                        sourceSize: Qt.size(480, 270)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: false
                    }
                    Row {
                        visible: hover.hovered
                        anchors { right: parent.right; top: parent.top; margins: 6 }
                        spacing: 4
                        IconButton { small: true; filled: true; glyph: "\uf0c5"; onClicked: menu.copy(cell.filePath) }
                        IconButton { small: true; filled: true; glyph: "\uf35d"; onClicked: menu.open(cell.filePath) }
                        IconButton {
                            small: true; filled: true; danger: true
                            glyph: menu.armed === cell.filePath ? "?" : "\uf1f8"
                            onClicked: menu.trash(cell.filePath)
                        }
                    }
                }
                Text {
                    anchors { left: thumbBox.left; top: thumbBox.bottom; topMargin: 6 }
                    text: menu.stamp(cell.fileName)
                    font.family: Theme.bodyFont; font.pixelSize: 12
                    color: cell.current ? Theme.accent : Theme.muted
                }
                HoverHandler { id: hover; onHoveredChanged: if (hovered) grid.currentIndex = cell.index }
                TapHandler { onTapped: menu.preview = cell.index }
            }

            Text {
                anchors.centerIn: parent
                visible: files.count === 0
                text: "Скриншотов пока нет. Сделать: Print"
                font.family: Theme.titleFont; font.pixelSize: 18; font.italic: Theme.italicTitle
                color: Theme.muted
            }
        }

        // ---------- large preview ----------
        Item {
            visible: menu.preview >= 0
            anchors { left: parent.left; right: parent.right; top: header.bottom; bottom: hint.top; margins: 20; topMargin: 18 }
            Image {
                anchors.fill: parent
                source: menu.preview >= 0 ? Url.fromPath(menu.pathAt(menu.preview)) : ""
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: false
            }
            Row {
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 8 }
                spacing: 8
                IconButton { glyph: "\uf060"; filled: true; onClicked: menu.preview = Math.max(0, menu.preview - 1) }
                Chip { glyph: "\uf0c5"; text: "Копировать"; onClicked: menu.copy(menu.pathAt(menu.preview)) }
                Chip { glyph: "\uf35d"; text: "Открыть"; onClicked: menu.open(menu.pathAt(menu.preview)) }
                Chip {
                    glyph: "\uf1f8"
                    danger: true
                    text: menu.armed === menu.pathAt(menu.preview) ? "Точно?" : "В корзину"
                    onClicked: menu.trash(menu.pathAt(menu.preview))
                }
                IconButton { glyph: "\uf061"; filled: true; onClicked: menu.preview = Math.min(files.count - 1, menu.preview + 1) }
            }
        }

        Text {
            id: hint
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 14 }
            text: menu.preview >= 0
                  ? menu.stamp(files.get(menu.preview, "fileName") || "") + "   ·   ← → листать · C копировать · Enter открыть · Del в корзину · Esc назад"
                  : "клик просмотр · C копировать · Del в корзину · Esc закрыть"
            font.family: Theme.bodyFont; font.pixelSize: 13
            color: Theme.muted
        }

        Rectangle {
            id: toast
            anchors { horizontalCenter: parent.horizontalCenter; bottom: hint.top; bottomMargin: 12 }
            width: toastText.implicitWidth + 28; height: 34; radius: 17
            color: Theme.alpha(Theme.accent, 0.9)
            opacity: 0
            Text {
                id: toastText
                anchors.centerIn: parent
                text: flash.text
                font.family: Theme.bodyFont; font.pixelSize: 14
                color: Theme.bg
            }
            SequentialAnimation {
                id: flash
                property string text: ""
                NumberAnimation { target: toast; property: "opacity"; to: 1; duration: 120 }
                PauseAnimation { duration: 1100 }
                NumberAnimation { target: toast; property: "opacity"; to: 0; duration: 300 }
            }
        }
    }
}
