import QtQuick
import Quickshell

// One menu of the shell: made when it opens and destroyed once it has closed, so a closed menu holds no memory.
// The menu itself is the component inside, an OverlayPanel that binds `argument` to the slot's.
LazyLoader {
    id: slot

    property string argument

    function open(argument) {
        if (active) {
            return;
        }
        slot.argument = argument;
        active = true;
    }

    function close() {
        if (item) {
            item.close();
        }
    }

    // A second press while the menu fades out changes nothing.
    function toggle(argument) {
        if (active) {
            close();
        } else {
            open(argument);
        }
    }

    // Later, not inside the menu's own signal: the menu is destroyed by this.
    readonly property Connections unloadOnClose: Connections {
        target: slot.item
        function onDismissed() {
            Qt.callLater(() => slot.active = false);
        }
    }
}
