import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// The rice's features as the «Функции» tab shows them (features.py list), and switching one on or off
// (features.py on|off <id>, which applies the change itself). The list is read again after every switch, so a
// switch shows what features.py made of it, and again whenever features.json changes (an install switching a feature
// on in the background). A feature whose packages are missing is switched on only once they are installed: all of
// them with one sudo password, and the installer switches it on itself, even if the dialog was closed meanwhile
// (PackageInstall). A feature that needs what the system does not allow yet (ports ufw keeps closed, a group the
// user is not in) asks first whether to allow it (`asking`, AccessDialog). One that may get in the way when it goes
// wrong (its caution) is switched on only once that warning is accepted (`cautioning`, CautionDialog).
Scope {
    id: features

    // [{id, group, name, about, on, needs, missing, experimental, closedPorts, missingGroups, caution}] in display order
    property var list: []
    readonly property var groups: [...new Set(list.map(feature => feature.group))]
    property string message: ""    // what features.py said about the last switch: why it was refused
    readonly property bool busy: runner.running || listProc.running  // a switch now would act on an old list
    readonly property alias install: install
    property var asking: null               // the feature asking for ports or groups, while the dialog is up
    property var cautioning: null           // the feature whose warning is up, before it is switched on
    readonly property bool granting: grantRunner.running

    function toggle(feature) {
        if (feature.on) {
            turn(feature.id, "off");
        } else if (feature.caution) {
            cautioning = feature;
        } else {
            switchOnAllowed(feature);
        }
    }

    // The warning's «Включить».
    function acceptCaution() {
        const feature = cautioning;
        cautioning = null;
        switchOnAllowed(feature);
    }

    // What the system must allow is asked about first.
    function switchOnAllowed(feature) {
        if (feature.closedPorts.length || feature.missingGroups.length) {
            asking = feature;
        } else {
            switchOn(feature);
        }
    }

    // The access dialog's answer: allow it (the password goes to the polkit window), then switch the feature on;
    // or switch it on without. What was not allowed (the password window was cancelled) leaves the feature off
    // and says why.
    function grant() {
        message = "";
        grantRunner.start(["grant", asking.id], (lines, status) => {
            const feature = asking;
            asking = null;
            if (status === 0) {
                switchOn(feature);
            } else {
                message = lines.join(" ") || "features.py grant " + feature.id + ": код " + status;
            }
        });
    }

    function switchOnWithout() {
        const feature = asking;
        asking = null;
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
    ScriptRunner { id: grantRunner; script: Features.script }
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
