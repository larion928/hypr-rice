import QtQuick
import Quickshell.Io

// Runs a Python script (games.py, themegen.py) with arguments. Its output, stdout and stderr together, comes
// back in one stream ended by "@@exit <status>", so nothing arrives after the end: then(lines, status) gets the
// lines without that marker and the exit status (0: it worked). A second run while one is going is ignored.
Process {
    id: runner

    property string script
    property var then: null

    function start(args, then) {
        if (running) {
            return;
        }
        runner.then = then;
        command = ["sh", "-c", 'python3 -u "$0" "$@" 2>&1; echo "@@exit $?"', script].concat(args);
        running = true;
    }

    stdout: StdioCollector {
        onStreamFinished: {
            const lines = this.text.trim().split("\n");
            const status = parseInt(lines.pop().replace("@@exit ", ""));
            if (runner.then) {
                runner.then(lines.filter(line => line !== ""), status);
            }
        }
    }
}
