// Screenshot gallery, toggled by ~/.local/bin/shots-gallery (waybar camera icon).
// Grid of ~/Pictures/screenshots, newest first; click opens a large preview (←/→ to flip).
// Hover buttons: copy to clipboard, open in the default viewer, move to trash (press twice).
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

ShellRoot {
    id: root

    readonly property string themeDir: Quickshell.env("SHOTS_THEME_DIR")
    readonly property string dir: Quickshell.env("SHOTS_DIR")
    property var pal: ({ colors: {} })
    property var ui: ({})
    readonly property var c: pal.colors || {}
    readonly property string titleFont: ui.titleFont === "display" ? (pal.display || "serif") : (pal.font || "monospace")
    readonly property string bodyFont: !ui.bodyFont || ui.bodyFont === "font" ? (pal.font || "monospace")
                                       : ui.bodyFont === "display" ? (pal.display || "serif") : ui.bodyFont
    readonly property int r: Math.min(ui.radius ?? 14, 22)

    property int preview: -1        // index shown large, -1 = grid
    property string armed: ""       // file waiting for a second delete press
    property bool closing: false

    FileView { id: palFile; path: root.themeDir + "/palette.json"; blockLoading: true }
    FileView { id: uiFile; path: root.themeDir + "/ui.json"; blockLoading: true }
    Component.onCompleted: {
        try { pal = JSON.parse(palFile.text()); } catch (e) {}
        try { ui = JSON.parse(uiFile.text()); } catch (e) {}
    }

    function a(col, al) {
        return "#" + ("0" + Math.round(al * 255).toString(16)).slice(-2) + String(col || "#888888").slice(1);
    }

    FolderListModel {
        id: files
        folder: "file://" + root.dir
        nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp"]
        showDirs: false
        sortField: FolderListModel.Time   // newest first
    }

    function pathAt(i) { return files.get(i, "filePath"); }

    // "screenshot_20261006_143300.png" -> "6 окт, 14:33"
    readonly property var months: ["янв", "фев", "мар", "апр", "мая", "июн", "июл", "авг", "сен", "окт", "ноя", "дек"]
    function stamp(name) {
        const m = /(\d{4})(\d{2})(\d{2})_(\d{2})(\d{2})/.exec(name);
        return m ? `${+m[3]} ${months[+m[2] - 1]}, ${m[4]}:${m[5]}` : name;
    }

    function copy(path) {
        Quickshell.execDetached(["sh", "-c", 'wl-copy --type image/png < "$1"', "sh", path]);
        flash.text = "Скопировано в буфер";
        flash.restart();
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
        armed = "";
        Quickshell.execDetached(["gio", "trash", path]);
        flash.text = "Перемещено в корзину";
        flash.restart();
        if (preview >= files.count - 1) preview = files.count - 2;
    }

    function close() {
        if (closing) return;
        closing = true;
        outAnim.start();
    }

    Timer { id: disarm; interval: 3000; onTriggered: root.armed = "" }

    IpcHandler {
        target: "shots"
        function close(): void { root.close(); }
    }

    PanelWindow {
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "shots-gallery"
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
                NumberAnimation { target: scene; property: "opacity"; to: 0; duration: 160 }
                ScriptAction { script: Qt.quit() }
            }

            Keys.onPressed: e => {
                const n = files.count;
                if (e.key === Qt.Key_Escape) {
                    if (root.preview >= 0) root.preview = -1; else root.close();
                } else if (root.preview >= 0) {
                    if (e.key === Qt.Key_Left || e.key === Qt.Key_H) root.preview = Math.max(0, root.preview - 1);
                    else if (e.key === Qt.Key_Right || e.key === Qt.Key_L) root.preview = Math.min(n - 1, root.preview + 1);
                    else if (e.key === Qt.Key_C) root.copy(root.pathAt(root.preview));
                    else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) root.open(root.pathAt(root.preview));
                    else if (e.key === Qt.Key_Delete) root.trash(root.pathAt(root.preview));
                } else {
                    if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) root.preview = grid.currentIndex;
                    else if (e.key === Qt.Key_Left) grid.moveCurrentIndexLeft();
                    else if (e.key === Qt.Key_Right) grid.moveCurrentIndexRight();
                    else if (e.key === Qt.Key_Up) grid.moveCurrentIndexUp();
                    else if (e.key === Qt.Key_Down) grid.moveCurrentIndexDown();
                    else if (e.key === Qt.Key_C) root.copy(root.pathAt(grid.currentIndex));
                    else if (e.key === Qt.Key_Delete) root.trash(root.pathAt(grid.currentIndex));
                }
            }

            Rectangle { anchors.fill: parent; color: root.a(root.c.bg, 0.7) }
            MouseArea { anchors.fill: parent; onClicked: root.close() }

            Rectangle {
                id: sheet
                anchors.centerIn: parent
                width: Math.min(parent.width - 80, 1500)
                height: Math.min(parent.height - 80, 920)
                radius: root.r
                color: root.a(root.c.bg, 0.95)
                border.width: root.ui.border ?? 1
                border.color: root.a(root.c.accent, 0.5)
                clip: true
                MouseArea { anchors.fill: parent }

                // ---------- header ----------
                Row {
                    id: header
                    x: 28; y: 22
                    spacing: 12
                    Image {
                        visible: !!root.ui.headerIcon
                        source: root.ui.headerIcon ? "file://" + root.themeDir + "/" + root.ui.headerIcon : ""
                        width: 26; height: 26; sourceSize: Qt.size(52, 52)
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        visible: !root.ui.headerIcon
                        text: root.ui.headerGlyph || ""
                        font.family: root.titleFont; font.pixelSize: 24; font.bold: true
                        color: root.c.accent || "white"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: root.ui.upperTitle ? "СКРИНШОТЫ" : "Скриншоты"
                        font.family: root.titleFont; font.pixelSize: 28; font.italic: !!root.ui.italicTitle
                        color: root.c.fg || "white"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: files.count
                        font.family: root.bodyFont; font.pixelSize: 15
                        color: root.c.muted || "grey"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                Row {
                    anchors { right: parent.right; rightMargin: 24; verticalCenter: header.verticalCenter }
                    spacing: 8
                    Btn { glyph: ""; label: "Открыть папку"; onClicked: { Quickshell.execDetached(["thunar", root.dir]); root.close(); } }
                    Btn { glyph: ""; onClicked: root.close() }
                }

                // ---------- grid ----------
                GridView {
                    id: grid
                    visible: root.preview < 0
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
                            radius: Math.min(root.r, 12)
                            color: root.c.bg2 || "#222"
                            border.width: cell.current || hover.hovered ? 2 : 1
                            border.color: cell.current || hover.hovered ? (root.c.accent || "white") : root.a(root.c.muted, 0.3)
                            Image {
                                anchors.fill: parent
                                source: "file://" + cell.filePath
                                sourceSize: Qt.size(480, 270)
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: false
                            }
                            Row {
                                visible: hover.hovered
                                anchors { right: parent.right; top: parent.top; margins: 6 }
                                spacing: 4
                                Btn { small: true; glyph: ""; onClicked: root.copy(cell.filePath) }
                                Btn { small: true; glyph: ""; onClicked: root.open(cell.filePath) }
                                Btn { small: true; danger: true; glyph: root.armed === cell.filePath ? "?" : ""; onClicked: root.trash(cell.filePath) }
                            }
                        }
                        Text {
                            anchors { left: thumbBox.left; top: thumbBox.bottom; topMargin: 6 }
                            text: root.stamp(cell.fileName)
                            font.family: root.bodyFont; font.pixelSize: 12
                            color: cell.current ? (root.c.accent || "white") : (root.c.muted || "grey")
                        }
                        HoverHandler { id: hover; onHoveredChanged: if (hovered) grid.currentIndex = cell.index }
                        TapHandler { onTapped: root.preview = cell.index }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: files.count === 0
                        text: "Скриншотов пока нет — Print, чтобы сделать"
                        font.family: root.titleFont; font.pixelSize: 18; font.italic: !!root.ui.italicTitle
                        color: root.c.muted || "grey"
                    }
                }

                // ---------- large preview ----------
                Item {
                    visible: root.preview >= 0
                    anchors { left: parent.left; right: parent.right; top: header.bottom; bottom: hint.top; margins: 20; topMargin: 18 }
                    Image {
                        id: big
                        anchors.fill: parent
                        source: root.preview >= 0 ? "file://" + root.pathAt(root.preview) : ""
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        cache: false
                    }
                    Row {
                        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 8 }
                        spacing: 8
                        Btn { glyph: ""; onClicked: root.preview = Math.max(0, root.preview - 1) }
                        Btn { glyph: ""; label: "Копировать"; onClicked: root.copy(root.pathAt(root.preview)) }
                        Btn { glyph: ""; label: "Открыть"; onClicked: root.open(root.pathAt(root.preview)) }
                        Btn { glyph: ""; danger: true; label: root.armed === root.pathAt(root.preview) ? "Точно?" : "В корзину"
                              onClicked: root.trash(root.pathAt(root.preview)) }
                        Btn { glyph: ""; onClicked: root.preview = Math.min(files.count - 1, root.preview + 1) }
                    }
                }

                Text {
                    id: hint
                    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 14 }
                    text: root.preview >= 0
                          ? root.stamp(files.get(root.preview, "fileName") || "") + "   ·   ← → листать · C копировать · Enter открыть · Del в корзину · Esc назад"
                          : "клик — просмотр · C копировать · Del в корзину · Esc закрыть"
                    font.family: root.bodyFont; font.pixelSize: 13
                    color: root.c.muted || "grey"
                }

                Rectangle {
                    id: toast
                    anchors { horizontalCenter: parent.horizontalCenter; bottom: hint.top; bottomMargin: 12 }
                    width: toastText.implicitWidth + 28; height: 34; radius: 17
                    color: root.a(root.c.accent, 0.9)
                    opacity: 0
                    Text {
                        id: toastText
                        anchors.centerIn: parent
                        text: flash.text
                        font.family: root.bodyFont; font.pixelSize: 14
                        color: root.c.bg || "black"
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
    }

    component Btn: Rectangle {
        id: btn
        property string glyph
        property string label: ""
        property bool danger: false
        property bool small: false
        signal clicked()
        width: label ? row.implicitWidth + 24 : (small ? 28 : 36)
        height: small ? 28 : 36
        radius: Math.min(root.r, height / 2)
        color: btnHover.hovered ? root.a(danger ? root.c.crit : root.c.accent, 0.3) : root.a(root.c.bg2, 0.9)
        border.color: root.a(danger ? root.c.crit : root.c.accent, 0.4)
        HoverHandler { id: btnHover }
        TapHandler { onTapped: btn.clicked() }
        Row {
            id: row
            anchors.centerIn: parent
            spacing: 8
            Text {
                text: btn.glyph
                font.family: "JetBrainsMono Nerd Font"; font.pixelSize: btn.small ? 13 : 15
                color: btn.danger ? (root.c.crit || "red") : (root.c.fg || "white")
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                visible: !!btn.label
                text: btn.label
                font.family: root.bodyFont; font.pixelSize: 13
                color: root.c.fg || "white"
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
}
