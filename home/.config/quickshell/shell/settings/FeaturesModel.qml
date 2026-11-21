import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// The rice's features as the «Функции» tab shows them (features.py list), and switching one on or off
// (features.py on|off <id>, which applies the change itself). The list is read again after every switch, so a
// switch shows what features.py made of it, and again whenever features.json changes (an install switching a feature
// on in the background). A feature whose packages are missing is switched on only once they are installed: all of
// them with one sudo password, and the installer switches it on itself, even if the dialog was closed meanwhile
// (PackageInstall). A feature that needs ports ufw keeps closed asks first whether to open them (`firewall`).
Scope {
    id: features

    // [{id, group, name, about, on, needs, missing, experimental, closedPorts}] in display order
    property var list: []
    readonly property var groups: [...new Set(list.map(feature => feature.group))]
    property string message: ""    // what features.py said about the last switch: why it was refused
    readonly property bool busy: runner.running || listProc.running  // a switch now would act on an old list
    readonly property alias install: install
    property var firewall: null             // the feature asking to open its ports, while the dialog is up
    readonly property bool openingPorts: portsRunner.running

    function toggle(feature) {
        if (feature.on) {
            turn(feature.id, "off");
        } else if (feature.closedPorts.length) {
            firewall = feature;
        } else {
            switchOn(feature);
        }
    }

    // The firewall dialog's answer: open the ports (the password goes to the polkit window), then switch the
    // feature on; or switch it on with them closed. Ports that did not open (the password window was cancelled)
    // leave the feature off and say why.
    function openPorts() {
        message = "";
        portsRunner.start(["open-ports", firewall.id], (lines, status) => {
            const feature = firewall;
            firewall = null;
            if (status === 0) {
                switchOn(feature);
            } else {
                message = lines.join(" ") || "features.py open-ports " + feature.id + ": код " + status;
            }
        });
    }

    function keepPortsClosed() {
        const feature = firewall;
        firewall = null;
        switchOn(feature);
    }

    function switchOn(feature) {
        if (feature.missing.length) {
            install.ask({ packages: feature.missing, title: feature.missing.join(", ") + " — " + feature.name,
                          feature: feature.id, done: "Установлено, «" + feature.name + "» включена.",
                          notice: "«" + feature.name + "» включена." });
        } else {
            turn(feature.id, "on");
        }
    }

    // verb: "on" or "off".
    function turn(id, verb) {
        message = "";
        runner.start([verb, id], (lines, status) => {
            message = lines.join(" ") || (status !== 0 ? "features.py " + verb + " " + id + ": код " + status : "");
            listProc.running = true;
        });
    }

    function read(text) {
        try {
            list = JSON.parse(text);
        } catch (error) {
            message = "Список функций не прочитался (features.py list)";
        }
    }

    ScriptRunner { id: runner; script: Features.script }
    ScriptRunner { id: portsRunner; script: Features.script }
    Process {
        id: listProc
        command: ["python3", Features.script, "list"]
        running: true
        stdout: StdioCollector { onStreamFinished: features.read(this.text) }
    }
    // The installed packages are no longer missing.
    PackageInstall {
        id: install
        onFinished: listProc.running = true
    }
    Connections {
        target: Features
        function onStateChanged() {
            listProc.running = true;
        }
    }
}
