// The screenshot overlay, opened by ~/.local/bin/shot after it froze every monitor with grim into
// $XDG_RUNTIME_DIR/shot (one <monitor>.png each, with monitors.json and clients.json). The argument is
// "region" or "full", optionally ":<theme>" to draw with another theme's screenshot.qml.
// The frozen frame, mouse/keyboard handling and saving live here; every theme provides
// themes/<name>/screenshot.qml that only draws the selection and the capture animation.
//
// Theme contract: the root Item gets `ctx` (the QtObject inside each window below) and should
//   - draw dimming/selection from ctx.sel (or ctx.hover while nothing is selected),
//   - start its capture animation when ctx.phase becomes "capture",
//   - call ctx.finish() when the animation is over (the overlay then closes).
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.common
import "../common/url.js" as Url

Scope {
    id: overlay

    property string argument
    readonly property string mode: argument.split(":")[0] || "region"
    readonly property string themeDir: argument.split(":")[1] ? Theme.hypr + "/themes/" + argument.split(":")[1] : Theme.dir
    readonly property string run: Quickshell.env("XDG_RUNTIME_DIR") + "/shot"
    readonly property string outFile: Quickshell.env("HOME") + "/Pictures/screenshots/screenshot_"
                                      + Qt.formatDateTime(new Date(), "yyyyMMdd_HHmmss") + ".png"
    property bool closing: false

    property var monitors: ({})
    property var clients: []
    property string focusedName: ""

    // Selection is shared: only one screen owns it at a time.
    property string selScreen: ""
    property rect sel: Qt.rect(0, 0, 0, 0)
    property string phase: "select" // select -> saving -> capture

    signal dismissed()

    function close() {
        if (closing) {
            return;
        }
        closing = true;
        dismissed();
    }

    FileView { id: monitorsFile; path: overlay.run + "/monitors.json"; blockLoading: true }
    FileView { id: clientsFile; path: overlay.run + "/clients.json"; blockLoading: true }

    Component.onCompleted: {
        const byName = {};
        for (const m of JSON.parse(monitorsFile.text() || "[]")) {
            byName[m.name] = m;
            if (m.focused) {
                focusedName = m.name;
            }
        }
        monitors = byName;
        clients = JSON.parse(clientsFile.text() || "[]");
    }

    // Windows visible on a monitor, in monitor-local logical coords, topmost first.
    function visibleWindows(name) {
        const m = monitors[name];
        if (!m) {
            return [];
        }
        const shown = [m.activeWorkspace ? m.activeWorkspace.id : -1, m.specialWorkspace ? m.specialWorkspace.id : -1];
        return clients
            .filter(c => c.mapped && !c.hidden && shown.indexOf(c.workspace.id) !== -1)
            .sort((a, b) => (b.floating - a.floating) || (a.focusHistoryID - b.focusHistoryID))
            .map(c => Qt.rect(c.at[0] - m.x, c.at[1] - m.y, c.size[0], c.size[1]));
    }

    function commit(screenName, rect) {
        if (phase !== "select" || rect.width < 2 || rect.height < 2) {
            return;
        }
        selScreen = screenName;
        sel = rect;
        phase = "saving";
        Quickshell.execDetached(["sh", "-c", `[ -f "$1" ] && exec pw-play "$1"`, "sh", themeDir + "/shutter.wav"]);
        const screen = Quickshell.screens.find(s => s.name === screenName);
        cropProc.command = ["python3", Quickshell.shellDir + "/shot/crop.py", `${run}/${screenName}.png`,
                            rect.x, rect.y, rect.width, rect.height, screen.width, screen.height, outFile].map(String);
        cropProc.running = true;
    }

    Process {
        id: cropProc
        onExited: code => {
            if (code === 0) {
                overlay.phase = "capture";
                quitGuard.start();
            } else {
                Quickshell.execDetached(["notify-send", "-u", "critical", "Скриншот", "Не удалось сохранить снимок"]);
                overlay.close();
            }
        }
    }

    // In case a theme never calls finish().
    Timer { id: quitGuard; interval: 6000; onTriggered: overlay.close() }

    Region { id: noInput }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            readonly property string name: modelData.name
            readonly property bool isFocused: name === overlay.focusedName

            screen: modelData
            visible: overlay.mode !== "full" || isFocused
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "shot"
            WlrLayershell.keyboardFocus: isFocused && overlay.phase === "select" ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            // Let clicks reach the desktop while the capture animation plays.
            mask: overlay.phase === "capture" ? noInput : null

            QtObject {
                id: ctx
                readonly property var pal: Theme.pal
                readonly property string mode: overlay.mode
                readonly property string phase: overlay.phase
                readonly property string outFile: overlay.outFile
                readonly property bool owner: overlay.selScreen === win.name
                readonly property rect sel: owner ? overlay.sel : Qt.rect(0, 0, 0, 0)
                property rect hover: Qt.rect(0, 0, 0, 0)
                property point mouse: Qt.point(-1, -1)
                property bool dragging: false
                readonly property url frozen: Url.fromPath(overlay.run + "/" + win.name + ".png")
                readonly property real scale: frozenImage.sourceSize.width > 0 ? frozenImage.sourceSize.width / win.width : 1
                readonly property string themeDir: overlay.themeDir
                // Themes may fade the frozen frame out to reveal the live desktop.
                property real frozenOpacity: 1
                // Hides the whole overlay on screens that do not own the shot.
                property real overlayOpacity: owner || overlay.phase === "select" ? 1 : 0
                function finish() { overlay.close(); }
            }

            Item {
                anchors.fill: parent
                opacity: ctx.overlayOpacity
                Behavior on opacity { NumberAnimation { duration: 200 } }

                Image {
                    id: frozenImage
                    anchors.fill: parent
                    source: ctx.frozen
                    cache: false
                    smooth: ctx.scale !== 1
                    opacity: ctx.frozenOpacity
                }

                Loader {
                    id: themeLoader
                    anchors.fill: parent
                    source: Url.fromPath(overlay.themeDir + "/screenshot.qml")
                    onLoaded: item.ctx = ctx
                }

                // Minimal look if the theme file is missing or broken.
                Item {
                    id: fallback
                    anchors.fill: parent
                    visible: themeLoader.status === Loader.Error || themeLoader.status === Loader.Null
                    readonly property rect r: ctx.sel.width > 0 ? ctx.sel : ctx.hover
                    Rectangle { anchors.fill: parent; color: "#66000000"; visible: parent.r.width === 0 }
                    Rectangle {
                        x: parent.r.x; y: parent.r.y; width: parent.r.width; height: parent.r.height
                        color: "transparent"; border.color: "white"; border.width: 2
                    }
                    Connections {
                        target: overlay
                        enabled: fallback.visible
                        function onPhaseChanged() { if (overlay.phase === "capture") overlay.close(); }
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                enabled: overlay.phase === "select"
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.CrossCursor
                property point start
                property var windows: []

                Component.onCompleted: windows = overlay.visibleWindows(win.name)

                function windowAt(x, y) {
                    for (const r of windows) {
                        if (x >= r.x && x < r.x + r.width && y >= r.y && y < r.y + r.height) {
                            return r;
                        }
                    }
                    return Qt.rect(0, 0, 0, 0);
                }

                onPositionChanged: m => {
                    ctx.mouse = Qt.point(m.x, m.y);
                    if (pressed && (pressedButtons & Qt.LeftButton)) {
                        if (!ctx.dragging && Math.hypot(m.x - start.x, m.y - start.y) > 4) {
                            ctx.dragging = true;
                            overlay.selScreen = win.name;
                        }
                        if (ctx.dragging) {
                            overlay.sel = Qt.rect(Math.min(start.x, m.x), Math.min(start.y, m.y),
                                                  Math.abs(m.x - start.x), Math.abs(m.y - start.y));
                        }
                    } else {
                        ctx.hover = windowAt(m.x, m.y);
                    }
                }
                onExited: ctx.hover = Qt.rect(0, 0, 0, 0)
                onPressed: m => {
                    if (m.button === Qt.RightButton) {
                        overlay.close();
                        return;
                    }
                    start = Qt.point(m.x, m.y);
                }
                onReleased: m => {
                    if (m.button !== Qt.LeftButton) {
                        return;
                    }
                    if (ctx.dragging) {
                        ctx.dragging = false;
                        overlay.commit(win.name, overlay.sel);
                    } else {
                        // A click takes the window under the cursor, or the whole screen.
                        const r = windowAt(m.x, m.y);
                        overlay.commit(win.name, r.width > 0 ? r : Qt.rect(0, 0, win.width, win.height));
                    }
                }
            }

            Item {
                focus: win.isFocused
                Keys.onPressed: e => {
                    if (e.key === Qt.Key_Escape) {
                        overlay.close();
                    } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) {
                        overlay.commit(win.name, Qt.rect(0, 0, win.width, win.height));
                    }
                }
            }

            Timer {
                // `shot full` skips selection; give the frame a moment to map first.
                running: overlay.mode === "full" && win.isFocused
                interval: 120
                onTriggered: overlay.commit(win.name, Qt.rect(0, 0, win.width, win.height))
            }
        }
    }
}
