import QtQuick
import Quickshell
import Quickshell.Io

// The notification history as histui keeps it, read every few seconds, and the actions on it. Actions run one
// at a time in the order asked for; the list is read again once none is left, because a list read before an
// action finished would still show what the action changed.
Item {
    id: store

    property var items: []
    property bool dnd: false
    readonly property int unread: items.filter(n => !n.histui_dismissed_at).length
    readonly property var byId: {
        const map = {};
        for (const n of items) {
            map[n.histui_id] = n;
        }
        return map;
    }

    property string itemsJson: ""   // histui's last answer as text: an identical one changes nothing
    property int generation: 0      // bumped by every action
    property var pendingActions: []

    function refresh() {
        if (actionProc.running) {
            return;
        }
        if (!listProc.running) {
            listProc.generation = generation;
            listProc.running = true;
        }
        if (!dndProc.running) {
            dndProc.running = true;
        }
    }

    function act(command) {
        generation++;
        pendingActions.push(command);
        runNextAction();
    }

    function runNextAction() {
        if (actionProc.running) {
            return;
        }
        if (!pendingActions.length) {
            refresh();
            return;
        }
        actionProc.command = pendingActions.shift();
        actionProc.running = true;
    }

    // Shown gone at once; histui catches up.
    function forget(changed) {
        items = changed;
        itemsJson = "";
    }

    function remove(id) {
        forget(items.filter(n => n.histui_id !== id));
        act(["histui", "set", id, "--delete"]);
    }

    function markRead(id) {
        act(["histui", "set", id, "--dismiss"]);
    }

    function readAll() {
        act(["sh", "-c", "histui get --format ids | histui set --stdin --dismiss"]);
    }

    function clearAll() {
        forget([]);
        act(["histui", "prune", "--keep", "0"]);
    }

    function toggleDnd() {
        dnd = !dnd;
        act(["histui", "dnd", "toggle"]);
    }

    Component.onCompleted: refresh()
    Timer { interval: 4000; running: true; repeat: true; onTriggered: store.refresh() }

    Process {
        id: listProc
        property int generation
        command: ["histui", "get", "--format", "json", "--limit", "300"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (listProc.generation !== store.generation) {
                    Qt.callLater(store.refresh);
                    return;
                }
                if (this.text === store.itemsJson) {
                    return;
                }
                try {
                    store.items = JSON.parse(this.text) || [];
                    store.itemsJson = this.text;
                } catch (e) {
                    console.warn("histui:", e);
                }
            }
        }
    }
    Process {
        id: dndProc
        command: ["histui", "dnd", "status"]
        stdout: StdioCollector { onStreamFinished: store.dnd = /enabled/.test(this.text) && !/disabled/.test(this.text) }
    }
    Process {
        id: actionProc
        onExited: Qt.callLater(store.runNextAction)
    }
}
