import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// The rice's features as the «Функции» tab shows them (features.py list), and switching one on or off
// (features.py on|off <id>, which applies the change itself). The list is read again after every switch, so a
// switch shows what features.py made of it. A feature whose packages are missing is switched on only once they
// are installed: one package at a time, each asking for the sudo password (PackageInstall).
Scope {
    id: features

    property var list: []          // [{id, group, name, about, on, needs, missing}] in display order
    readonly property var groups: [...new Set(list.map(feature => feature.group))]
    property string message: ""    // what features.py said about the last switch: why it was refused
    readonly property bool busy: runner.running || listProc.running  // a switch now would act on an old list
    // The feature whose package has just been installed: switched on (or its next package offered) once the list
    // read after the install has it.
    property string resume: ""
    readonly property alias install: install

    function toggle(feature) {
        if (feature.on) {
            turn(feature.id, "off");
        } else if (feature.missing.length) {
            install.ask({ package: feature.missing[0], title: feature.missing[0] + " — " + feature.name,
                          feature: feature.id, done: "Установлено, «" + feature.name + "» включается." });
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
            return;
        }
        const waiting = list.find(feature => feature.id === resume);
        resume = "";
        if (waiting && !waiting.on) {
            toggle(waiting);
        }
    }

    ScriptRunner { id: runner; script: Features.script }
    Process {
        id: listProc
        command: ["python3", Features.script, "list"]
        running: true
        stdout: StdioCollector { onStreamFinished: features.read(this.text) }
    }
    PackageInstall {
        id: install
        onFinished: ok => {
            if (ok) {
                features.resume = install.item.feature;
                listProc.running = true;
            }
        }
    }
}
