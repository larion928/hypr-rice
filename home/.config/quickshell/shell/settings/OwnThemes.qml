import QtQuick
import Quickshell
import Quickshell.Io
import qs.common
import qs.services

// Themes of the user's own and the list's tools: a new theme (a copy of another with its edits written in), one
// from a file, an export, a delete, a factory reset, bringing back a removed one. themegen.py does the work, then
// the theme list is read again.
Scope {
    id: ownThemes

    required property ThemeEditStore themeEdit
    property string dialog: ""     // "new", "import", "export", "delete", "factory" or "restore": what the dialog asks
    property var subject: null     // the theme a new one copies, or the one to export, reset or delete
    property string busy: ""       // what runs now
    property string error: ""
    property string done: ""       // where the export went
    property string openAfter: ""  // the theme to open once the list is read again
    property string pickingFor: "" // "import" or "export": what the file dialog is for
    property bool picking: false   // a file dialog is open: the window steps aside
    property var removed: []       // the rice's themes the user removed: [{name, label}]
    property string selected: ""   // the theme picked in the list; the current one until then
    property int themePage: 0      // the tab of the theme list shown
    readonly property int perPage: 8
    readonly property int pages: Math.max(1, Math.ceil(ThemeList.themes.length / perPage))

    function chosen() {
        return ThemeList.themes.find(t => t.name === selected) || ThemeList.themes.find(t => t.current) || null;
    }
    function ask(kind, entry) {
        subject = entry;
        error = "";
        done = "";
        dialog = kind;
    }
    function factory() {
        run("Возвращаю к заводским…", ["factory", subject.name]);
    }
    function create(label) {
        if (label.trim()) {
            run("Создаю тему…", ["new", label.trim(), "--from", subject.name]);
        }
    }
    function restore(name) {
        run("Возвращаю тему…", ["restore", name]);
    }
    function remove() {
        if (themeEdit.editing && themeEdit.editing.name === subject.name) {
            themeEdit.editing = null;
        }
        run("Удаляю…", ["delete", subject.name]);
    }
    function pickFile(kind) {
        pickingFor = kind;
        picking = true;
        fileDialogProc.command = kind === "import"
            ? ["zenity", "--file-selection", "--title=Тема из файла", "--file-filter=Темы | *.zip"]
            : ["zenity", "--file-selection", "--save", "--title=Куда сохранить тему",
               "--filename=" + Files.home + "/" + subject.name + ".zip"];
        fileDialogProc.running = true;
    }
    function picked(path) {
        if (!path) {
            return;
        }
        if (pickingFor === "import") {
            run("Добавляю тему…", ["import", path]);
        } else {
            run("Сохраняю…", ["export", subject.name, path]);
        }
    }
    function run(what, args) {
        busy = what;
        error = "";
        runner.start(args, (lines, status) => finished(args, lines, status));
    }
    function finished(args, lines, status) {
        busy = "";
        if (status !== 0) {
            error = lines.join("\n") || "не вышло (код " + status + ")";
            return;
        }
        const command = args[0];
        if (command === "export") {
            done = "Сохранено: " + args[2];
            return;
        }
        dialog = "";
        // new and import print the theme's name first; restore brings back the one it was given.
        const name = args[1];
        if (command === "factory" && subject.current) {
            Quickshell.execDetached(["changetheme", name]);  // the theme on screen changes too
        }
        const reopen = command === "factory" && themeEdit.editing && themeEdit.editing.name === name;
        openAfter = command === "new" || command === "import" ? lines[0] : command === "restore" || reopen ? name : "";
        if (openAfter) {
            selected = openAfter;
        }
        ThemeList.refresh();
        removedProc.running = true;
    }

    Connections {
        target: ThemeList
        function onRefreshed() {
            const made = ThemeList.themes.findIndex(t => t.name === ownThemes.openAfter);
            if (made >= 0) {
                ownThemes.themePage = Math.floor(made / ownThemes.perPage);
                ownThemes.themeEdit.open(ThemeList.themes[made]);
                ownThemes.openAfter = "";
            }
            ownThemes.themePage = Math.min(ownThemes.themePage, ownThemes.pages - 1);
        }
    }

    ScriptRunner { id: runner; script: Files.themegen }
    Process {
        id: removedProc
        command: ["python3", Files.themegen, "removed-themes"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    ownThemes.removed = JSON.parse(this.text);
                } catch (e) {
                    ownThemes.removed = [];
                }
            }
        }
    }
    Process {
        id: fileDialogProc
        stdout: StdioCollector { onStreamFinished: ownThemes.picked(this.text.trim()) }
        onExited: ownThemes.picking = false
    }
}
