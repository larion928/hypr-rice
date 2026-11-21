import QtQuick
import Quickshell
import Quickshell.Io

// Installing a missing package from the settings window (InstallDialog shows it): the window asks for the sudo
// password; the install itself runs in the background (~/.local/bin/rice-install-package), so the window may
// close. While the dialog is open the install's log is followed, and finished(ok) says how the install ended.
Scope {
    id: install

    readonly property string installer: Files.home + "/.local/bin/rice-install-package"
    property var item: null       // {package, title, source, done} whose install the dialog shows; null: no dialog
    property string phase: ""     // ask, checking (the password), running, done, failed
    property string message: ""
    property var log: []
    readonly property bool starting: installProc.running

    signal finished(bool ok)

    // source "aur" or "repo" says where the package comes from; done is what a successful install reads as.
    function ask(asked) {
        item = asked;
        phase = "ask";
        message = "";
        log = [];
        installLogFile.reload();  // an install of this package may be running already: then its log shows
    }
    function start(password) {
        installProc.password = password;
        installProc.command = [installer, item.package];
        phase = "checking";
        message = "";
        installProc.running = true;
    }
    // Esc: the dialog closes (the install goes on), except while the password is being checked.
    function dismiss() {
        if (phase !== "checking") {
            item = null;
        }
    }
    // The background install's log; its last line is "@@done <status>" once it is over.
    function readLog(text) {
        const lines = text.split("\n").filter(line => line);
        if (!lines.length || !item) {
            return;
        }
        const done = lines[lines.length - 1].match(/^@@done (\d+)$/);
        if (!done && phase === "ask") {
            phase = "running";
        }
        if (phase !== "running") {
            return;
        }
        log = lines.filter(line => !line.startsWith("@@done")).slice(-14);
        if (done) {
            const ok = done[1] === "0";
            phase = ok ? "done" : "failed";
            message = ok ? item.done : "Не установилось, подробности выше.";
            finished(ok);
        }
    }

    // The sudo password goes on the installer's stdin, never in its arguments, and is forgotten here as soon as
    // it is written.
    Process {
        id: installProc
        property string password: ""
        stdinEnabled: true
        onStarted: {
            installProc.write(installProc.password + "\n");
            installProc.password = "";
        }
        stdout: SplitParser {
            onRead: line => install.log = install.log.concat([line]).slice(-14)
        }
        onExited: exitCode => {
            if (exitCode === 0) {
                install.phase = "running";
                install.message = "Идёт в фоне: окно установки и настройки можно закрыть, по окончании придёт уведомление.";
                installLogFile.reload();
            } else if (exitCode === 2) {
                install.phase = "ask";
                install.message = "Пароль не подошёл. После трёх неверных паролей подряд sudo блокируется на 10 минут.";
            } else {
                install.phase = "failed";
                install.message = "Установка не запустилась.";
            }
        }
    }
    FileView {
        id: installLogFile
        path: install.item ? (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/rice-install-" + install.item.package + ".log" : ""
        watchChanges: true
        onFileChanged: reload()
        onLoaded: install.readLog(text())
    }
}
