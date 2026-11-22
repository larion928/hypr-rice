import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// The user's own words as the «Словарь» tab shows them (own_words.py list), and adding or taking out one
// (own_words.py add|remove, which restarts the layout fixer so that its hunspell reads them again). The fixer
// learns words by itself too (Alt+Shift+Enter), so the list is read again each time the tab is opened.
Scope {
    id: ownWords

    readonly property string script: Quickshell.env("HOME") + "/.config/hypr/scripts/own_words.py"
    property var ru: []
    property var us: []
    property string message: ""    // why own_words.py refused the last change
    readonly property bool busy: runner.running || listProc.running

    // added(): called once the entry is in the dictionary, not when it was refused.
    function add(entry, added) {
        change(["add", entry], added);
    }

    function remove(line) {
        change(["remove", line], () => {});
    }

    function refresh() {
        listProc.running = true;
    }

    function change(args, done) {
        message = "";
        runner.start(args, (lines, status) => {
            if (status === 0) {
                done();
            } else {
                message = lines.join(" ") || "own_words.py " + args[0] + ": код " + status;
            }
            refresh();
        });
    }

    function read(text) {
        try {
            const lists = JSON.parse(text);
            ru = lists.ru;
            us = lists.us;
        } catch (error) {
            message = "Словарь не прочитался (own_words.py list)";
        }
    }

    ScriptRunner { id: runner; script: ownWords.script }
    Process {
        id: listProc
        command: ["python3", ownWords.script, "list"]
        running: true
        stdout: StdioCollector { onStreamFinished: ownWords.read(this.text) }
    }
}
