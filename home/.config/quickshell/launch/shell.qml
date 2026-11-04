// The card proton-run shows while a Windows program starts: how far the start has got (percent)
// and what is happening now, with the time since the start, so a long first start (downloads,
// a new Wine prefix) does not look stuck. proton-run writes the state to $LAUNCH_STATE; the card
// closes itself when the start is over, or when proton-run ($LAUNCH_PID) is gone.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "common"
import "common/color.js" as Color

ShellRoot {
    id: root

    Theme { id: theme }

    property var launch: ({ title: "", percent: 0, stage: "", detail: "", status: "running", started: 0 })
    readonly property bool failed: launch.status === "failed"
    property real now: Date.now() / 1000

    FileView {
        path: Quickshell.env("LAUNCH_STATE")
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { root.launch = JSON.parse(text()); } catch (e) { return; }
            if (root.launch.status !== "running") closeTimer.restart();
        }
    }

    // A started program is shown for a moment; a failure stays long enough to read.
    Timer { id: closeTimer; interval: root.failed ? 8000 : 1500; onTriggered: Qt.quit() }
    Timer { interval: 1000; running: true; repeat: true; onTriggered: root.now = Date.now() / 1000 }
    Process {
        command: ["tail", "--pid=" + Quickshell.env("LAUNCH_PID"), "-f", "/dev/null"]
        running: true
        onExited: Qt.quit()
    }

    function elapsed() {
        const seconds = Math.max(0, Math.floor(root.now - root.launch.started));
        return Math.floor(seconds / 60) + ":" + String(seconds % 60).padStart(2, "0");
    }

    PanelWindow {
        anchors.bottom: true
        margins.bottom: 160
        implicitWidth: 480
        implicitHeight: 104
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "proton-launch"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        mask: Region {}

        Rectangle {
            anchors.fill: parent
            radius: Math.min(theme.ui.radius ?? 14, 22)
            color: Color.withAlpha(theme.c.bg, 0.94)
            border.color: Color.withAlpha(root.failed ? theme.c.crit : theme.c.accent, 0.5)

            Column {
                anchors { fill: parent; margins: 18 }
                spacing: 10

                Item {
                    width: parent.width; height: 22
                    Text {
                        anchors { left: parent.left; right: percentText.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        elide: Text.ElideRight
                        text: root.launch.title
                        font.family: theme.titleFont; font.pixelSize: 16; font.italic: !!theme.ui.italicTitle
                        color: theme.c.fg || "white"
                    }
                    Text {
                        id: percentText
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        text: root.launch.percent + "%"
                        font.family: theme.font; font.pixelSize: 16; font.bold: true
                        color: root.failed ? (theme.c.crit || "red") : (theme.c.accent || "white")
                    }
                }

                Rectangle {
                    width: parent.width; height: 8; radius: 4
                    color: Color.withAlpha(theme.c.muted, 0.3)
                    Rectangle {
                        width: parent.width * root.launch.percent / 100; height: parent.height; radius: 4
                        color: root.failed ? (theme.c.crit || "red") : (theme.c.accent || "white")
                        Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                    }
                }

                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: [root.launch.stage, root.launch.detail, root.elapsed()].filter(part => part).join(" · ")
                    font.family: theme.bodyFont; font.pixelSize: 13
                    color: root.failed ? (theme.c.crit || "red") : (theme.c.muted || "grey")
                }
            }
        }
    }
}
