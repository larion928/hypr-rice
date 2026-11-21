import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// The clipboard history as cliphist keeps it (rice-clipboard.service stores every copy through clipboard-store):
// its entries newest first, copying one back, deleting one or all. Nothing is read while the feature is off.
Scope {
    id: history

    readonly property bool on: Features.on("clipboard")
    property var entries: []    // [{id, label}] newest first

    function read() {
        if (on) {
            listProc.running = true;
        } else {
            entries = [];
        }
    }

    function copy(id) {
        Quickshell.execDetached(["sh", "-c", 'cliphist decode "$1" | wl-copy', "sh", id]);
    }

    // One change at a time: a key held down while cliphist is busy changes nothing more.
    function remove(id) {
        change(["sh", "-c", 'printf "%s\\n" "$1" | cliphist delete', "sh", id]);
    }
    function wipe() {
        change(["cliphist", "wipe"]);
    }
    function change(command) {
        if (!changer.running) {
            changer.command = command;
            changer.running = true;
        }
    }

    // cliphist list: "<id>\t<preview>" per line.
    function parse(text) {
        return text.split("\n").filter(line => line.includes("\t")).map(line => {
            const tab = line.indexOf("\t");
            return { id: line.slice(0, tab), label: label(line.slice(tab + 1)) };
        });
    }

    // cliphist's preview of a picture, "[[ binary data 120 KiB png 1920x1080 ]]", in words; text stays as it is.
    function label(preview) {
        const binary = preview.match(/^\[\[ binary data (\d+) (B|KiB|MiB)(?: \w+ (\d+)x(\d+))? \]\]$/);
        if (!binary) {
            return preview;
        }
        const size = binary[1] + " " + { B: "Б", KiB: "КБ", MiB: "МБ" }[binary[2]];
        return binary[3] ? "картинка " + binary[3] + "×" + binary[4] + ", " + size : "данные, " + size;
    }

    onOnChanged: read()
    Component.onCompleted: read()

    Process {
        id: listProc
        command: ["cliphist", "list"]
        stdout: StdioCollector { onStreamFinished: history.entries = history.parse(this.text) }
    }
    Process {
        id: changer
        onExited: history.read()
    }
}
