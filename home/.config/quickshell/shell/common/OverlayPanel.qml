// A menu's window: a layer on the monitor that had focus when the menu opened, holding the keyboard. Full-screen
// menus dim the screen and close on a click on the dimmed part; a smaller one (fullscreen: false, with its own
// anchors or size) closes on a click anywhere outside it. Esc calls back(), which closes; a menu with steps to
// go back through redefines back(). The content fades in, and out on close(); then dismissed() tells the shell
// to unload the menu.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

PanelWindow {
    id: panel

    // What the menu was opened with (`menus toggle <name> <argument>`), e.g. the settings page.
    property string argument
    property string namespace
    property bool fullscreen: true
    property real dim: 0.7
    property int layer: WlrLayer.Overlay
    property int keyboard: WlrKeyboardFocus.Exclusive
    property int fadeInMs: 180
    property int fadeOutMs: 160
    // How long the menu stays as it is before fading out (the theme picker shows the picked card a moment).
    property int lingerMs: 0
    // True while open: menus bind their own motion (a card sliding in) to it.
    property bool shown: false
    property bool closing: false
    default property alias content: scene.data
    readonly property Item scene: scene

    signal dismissed()
    signal keyPressed(var event)

    function close() {
        if (closing) {
            return;
        }
        closing = true;
        lingerTimer.start();
    }

    function back() {
        close();
    }

    // Gives the keyboard back to the menu's own keys, from a text field for one.
    function focusScene() {
        scene.forceActiveFocus();
    }

    anchors { top: fullscreen; bottom: fullscreen; left: fullscreen; right: fullscreen }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: panel.layer
    WlrLayershell.namespace: panel.namespace
    WlrLayershell.keyboardFocus: panel.keyboard

    // Set once: the menu stays where it opened when the focus moves to another monitor.
    Component.onCompleted: {
        screen = Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? null;
        shown = true;
    }

    Timer {
        id: lingerTimer
        interval: panel.lingerMs
        onTriggered: {
            panel.shown = false;
            fadeOutTimer.start();
        }
    }
    Timer { id: fadeOutTimer; interval: panel.fadeOutMs; onTriggered: panel.dismissed() }

    HyprlandFocusGrab {
        active: !panel.fullscreen && !panel.closing
        windows: [panel]
        onCleared: panel.close()
    }

    Rectangle {
        anchors.fill: parent
        visible: panel.fullscreen && panel.dim > 0
        opacity: scene.opacity
        color: Theme.alpha(Theme.bg, panel.dim)
        MouseArea { anchors.fill: parent; onClicked: panel.close() }
    }

    FocusScope {
        id: scene
        anchors.fill: parent
        focus: true
        opacity: panel.shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: panel.shown ? panel.fadeInMs : panel.fadeOutMs } }
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                event.accepted = true;
                panel.back();
                return;
            }
            panel.keyPressed(event);
        }
    }
}
