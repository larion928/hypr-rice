// The colour picker, opened by `~/.local/bin/shot color` (Alt+Shift+C) after it froze every monitor with grim into
// $XDG_RUNTIME_DIR/shot. A magnifier in the theme's colours follows the pointer over the frozen frame; a click
// copies the colour of the pixel under the pointer as #rrggbb (shot/color.py reads it from the capture). Esc or a
// right click leaves.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.common
import "../common/url.js" as Url

Scope {
    id: picker

    readonly property string run: Quickshell.env("XDG_RUNTIME_DIR") + "/shot"
    readonly property string focusedName: Hyprland.focusedMonitor?.name ?? ""
    property bool closing: false

    signal dismissed()

    function close() {
        if (closing) {
            return;
        }
        closing = true;
        dismissed();
    }

    function pick(screen, point) {
        Quickshell.execDetached(["python3", Quickshell.shellDir + "/shot/color.py", `${run}/${screen.name}.png`,
                                 point.x, point.y, screen.width, screen.height].map(String));
        close();
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            readonly property bool isFocused: modelData.name === picker.focusedName

            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Overlay
            // The screenshot overlay's namespace: no fade-in over the frozen frame (hyprland.lua shot-no-anim).
            WlrLayershell.namespace: "shot"
            WlrLayershell.keyboardFocus: isFocused ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            Image {
                id: frozen
                anchors.fill: parent
                source: Url.fromPath(picker.run + "/" + win.modelData.name + ".png")
                cache: false
            }

            MouseArea {
                id: pointer
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.CrossCursor
                onPressed: m => {
                    if (m.button === Qt.RightButton) {
                        picker.close();
                    } else {
                        picker.pick(win.modelData, Qt.point(m.x, m.y));
                    }
                }
            }

            Rectangle {
                id: loupe
                readonly property int cells: 15  // pixels across, an odd number so one is in the middle
                readonly property int cell: 9    // how big each is drawn
                readonly property int half: Math.floor(cells / 2)
                readonly property point pixel: Qt.point(Math.floor(pointer.mouseX), Math.floor(pointer.mouseY))
                readonly property int gap: 24    // from the pointer
                readonly property int frame: 3

                visible: pointer.containsMouse
                width: cells * cell + 2 * frame; height: width
                // Beside the pointer, on its other side near the right and bottom edges so it stays on screen.
                x: pixel.x + gap + width > win.width ? pixel.x - gap - width : pixel.x + gap
                y: pixel.y + gap + height > win.height ? pixel.y - gap - height : pixel.y + gap
                // Small: the magnified square inside has sharp corners.
                radius: Theme.radius(6)
                color: Theme.bg2
                border.color: Theme.accent
                border.width: frame

                ShaderEffectSource {
                    anchors { fill: parent; margins: loupe.frame }
                    sourceItem: frozen
                    sourceRect: Qt.rect(loupe.pixel.x - loupe.half, loupe.pixel.y - loupe.half, loupe.cells, loupe.cells)
                    smooth: false
                }
                // The pixel a click takes.
                Rectangle {
                    anchors.centerIn: parent
                    width: loupe.cell + 2; height: width
                    color: "transparent"
                    border.color: Theme.fg
                    border.width: 1
                }
                Rectangle {
                    anchors { top: parent.bottom; topMargin: 6; horizontalCenter: parent.horizontalCenter }
                    width: hint.implicitWidth + 16; height: hint.implicitHeight + 8
                    radius: Theme.radius(8)
                    color: Theme.alpha(Theme.bg2, 0.92)
                    Text {
                        id: hint
                        anchors.centerIn: parent
                        text: "клик — скопировать цвет · Esc — выход"
                        font.family: Theme.bodyFont; font.pixelSize: 12
                        color: Theme.muted
                    }
                }
            }

            Item {
                focus: win.isFocused
                Keys.onEscapePressed: picker.close()
            }
        }
    }
}
