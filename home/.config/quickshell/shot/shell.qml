// Screenshot overlay core. Started by ~/.local/bin/shot.
// The frozen frame, mouse/keyboard handling and saving live here; every theme provides
// themes/<name>/screenshot.qml that only draws the selection and the capture animation.
//
// Theme contract: the root Item gets `ctx` (the QtObject inside PanelWindow below) and should
//   - draw dimming/selection from ctx.sel (or ctx.hover while nothing is selected),
//   - start its capture animation when ctx.phase becomes "capture",
//   - call ctx.finish() when the animation is over (the overlay then quits).
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    readonly property string mode: Quickshell.env("SHOT_MODE") || "region"
    readonly property string run: Quickshell.env("SHOT_RUN")
    readonly property string themeDir: Quickshell.env("SHOT_THEME_DIR")
    readonly property string focusedName: Quickshell.env("SHOT_FOCUSED")
    readonly property string outFile: Quickshell.env("SHOT_OUT")
    readonly property string cropScript: Quickshell.env("SHOT_CROP")

    property var pal: ({ colors: {} })
    property var monitors: ({})
    property var clients: []

    // Selection is shared: only one screen owns it at a time.
    property string selScreen: ""
    property rect sel: Qt.rect(0, 0, 0, 0)
    property string phase: "select" // select -> saving -> capture

    FileView { id: palFile; path: root.themeDir + "/palette.json"; blockLoading: true }
    FileView { id: monitorsFile; path: root.run + "/monitors.json"; blockLoading: true }
    FileView { id: clientsFile; path: root.run + "/clients.json"; blockLoading: true }

    Component.onCompleted: {
        try { pal = JSON.parse(palFile.text()); } catch (e) { console.warn("palette:", e); }
        const mons = {};
        for (const m of JSON.parse(monitorsFile.text()))
            mons[m.name] = m;
        monitors = mons;
        clients = JSON.parse(clientsFile.text());
    }

    // Windows visible on a monitor, in monitor-local logical coords, topmost first.
    function visibleWindows(name) {
        const m = monitors[name];
        if (!m)
            return [];
        const shown = [m.activeWorkspace ? m.activeWorkspace.id : -1,
                       m.specialWorkspace ? m.specialWorkspace.id : -1];
        return clients
            .filter(c => c.mapped && !c.hidden && shown.indexOf(c.workspace.id) !== -1)
            .sort((a, b) => (b.floating - a.floating) || (a.focusHistoryID - b.focusHistoryID))
            .map(c => Qt.rect(c.at[0] - m.x, c.at[1] - m.y, c.size[0], c.size[1]));
    }

    function commit(screenName, rect) {
        if (phase !== "select" || rect.width < 2 || rect.height < 2)
            return;
        selScreen = screenName;
        sel = rect;
        phase = "saving";
        const shutter = themeDir + "/shutter.wav";
        Quickshell.execDetached(["sh", "-c", `[ -f "$1" ] && exec pw-play "$1"`, "sh", shutter]);
        const scr = Quickshell.screens.find(s => s.name === screenName);
        cropProc.command = ["python3", cropScript, `${run}/${screenName}.png`,
                            rect.x, rect.y, rect.width, rect.height,
                            scr.width, scr.height, outFile].map(String);
        cropProc.running = true;
    }

    Process {
        id: cropProc
        onExited: (code, status) => {
            if (code === 0) {
                root.phase = "capture";
                quitGuard.start();
            } else {
                Quickshell.execDetached(["notify-send", "-u", "critical", "Скриншот", "Не удалось сохранить снимок"]);
                Qt.quit();
            }
        }
    }

    // In case a theme never calls finish().
    Timer { id: quitGuard; interval: 6000; onTriggered: Qt.quit() }

    Region { id: noInput }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            readonly property string name: modelData.name
            readonly property bool isFocused: name === root.focusedName

            screen: modelData
            visible: root.mode !== "full" || isFocused
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "shot"
            WlrLayershell.keyboardFocus: isFocused && root.phase === "select"
                ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            // Let clicks reach the desktop while the capture animation plays.
            mask: root.phase === "capture" ? noInput : null

            QtObject {
                id: ctx
                readonly property var pal: root.pal
                readonly property string mode: root.mode
                readonly property string phase: root.phase
                readonly property string outFile: root.outFile
                readonly property bool owner: root.selScreen === win.name
                readonly property rect sel: owner ? root.sel : Qt.rect(0, 0, 0, 0)
                property rect hover: Qt.rect(0, 0, 0, 0)
                property point mouse: Qt.point(-1, -1)
                property bool dragging: false
                readonly property url frozen: "file://" + root.run + "/" + win.name + ".png"
                readonly property real scale: frozenImage.sourceSize.width > 0
                    ? frozenImage.sourceSize.width / win.width : 1
                readonly property string themeDir: root.themeDir
                // Themes may fade the frozen frame out to reveal the live desktop.
                property real frozenOpacity: 1
                // Hides the whole overlay on screens that do not own the shot.
                property real overlayOpacity: owner || root.phase === "select" ? 1 : 0
                function finish() { Qt.quit(); }
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
                    source: "file://" + root.themeDir + "/screenshot.qml"
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
                        target: root
                        enabled: fallback.visible
                        function onPhaseChanged() { if (root.phase === "capture") Qt.quit(); }
                    }
                }
            }

            MouseArea {
                id: mouse
                anchors.fill: parent
                enabled: root.phase === "select"
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.CrossCursor
                property point start
                property var windows: []

                Component.onCompleted: windows = root.visibleWindows(win.name)

                function windowAt(x, y) {
                    for (const r of windows)
                        if (x >= r.x && x < r.x + r.width && y >= r.y && y < r.y + r.height)
                            return r;
                    return Qt.rect(0, 0, 0, 0);
                }

                onPositionChanged: m => {
                    ctx.mouse = Qt.point(m.x, m.y);
                    if (pressed && (pressedButtons & Qt.LeftButton)) {
                        if (!ctx.dragging && Math.hypot(m.x - start.x, m.y - start.y) > 4) {
                            ctx.dragging = true;
                            root.selScreen = win.name;
                        }
                        if (ctx.dragging)
                            root.sel = Qt.rect(Math.min(start.x, m.x), Math.min(start.y, m.y),
                                               Math.abs(m.x - start.x), Math.abs(m.y - start.y));
                    } else {
                        ctx.hover = windowAt(m.x, m.y);
                    }
                }
                onExited: ctx.hover = Qt.rect(0, 0, 0, 0)
                onPressed: m => {
                    if (m.button === Qt.RightButton) {
                        Qt.quit();
                        return;
                    }
                    start = Qt.point(m.x, m.y);
                }
                onReleased: m => {
                    if (m.button !== Qt.LeftButton)
                        return;
                    if (ctx.dragging) {
                        ctx.dragging = false;
                        root.commit(win.name, root.sel);
                    } else {
                        // A click takes the window under the cursor, or the whole screen.
                        const r = windowAt(m.x, m.y);
                        root.commit(win.name, r.width > 0 ? r : Qt.rect(0, 0, win.width, win.height));
                    }
                }
            }

            Item {
                focus: win.isFocused
                Keys.onPressed: e => {
                    if (e.key === Qt.Key_Escape)
                        Qt.quit();
                    else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space)
                        root.commit(win.name, Qt.rect(0, 0, win.width, win.height));
                }
            }

            Timer {
                // `shot full` skips selection; give the frame a moment to map first.
                running: root.mode === "full" && win.isFocused
                interval: 120
                onTriggered: root.commit(win.name, Qt.rect(0, 0, win.width, win.height))
            }
        }
    }
}
