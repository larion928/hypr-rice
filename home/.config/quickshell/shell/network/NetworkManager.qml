import QtQuick
import Quickshell.Io
import "../common/listmodel.js" as ListModelSync

// NetworkManager's state as nmcli reports it, refreshed every few seconds, and the changes asked of it.
Item {
    id: net

    property bool wifiOn: true
    property string wifiDevice: ""
    property var active: null       // { ssid, signal, ip }
    property var others: []         // other connected devices: [{ type, name }]
    property var networks: []       // [{ ssid, signal, secure, band5, inUse }]
    property var saved: ({})        // wifi profile name -> true
    property string busy: ""        // ssid being connected, or "" when idle
    property string message: ""
    property bool messageIsError: false
    property string expanded: ""    // ssid whose password row is open
    readonly property bool scanning: rescanProc.running
    readonly property bool hasEditor: editorCheck.found
    // The networks but the one in use, kept in place across refreshes: a row being typed into keeps its
    // password field and focus.
    readonly property ListModel otherNetworks: ListModel {}

    // nmcli -t separates fields with ':' and escapes ':' and '\' inside them.
    function fields(line) {
        const out = [];
        let field = "";
        for (let i = 0; i < line.length; i++) {
            const ch = line[i];
            if (ch === "\\" && i + 1 < line.length) {
                field += line[++i];
            } else if (ch === ":") {
                out.push(field);
                field = "";
            } else {
                field += ch;
            }
        }
        out.push(field);
        return out;
    }

    function refresh() {
        radioProc.running = true;
        devicesProc.running = true;
        savedProc.running = true;
        listProc.running = true;
    }

    function rescan() {
        say("Ищу сети…", false);
        rescanProc.running = true;
    }

    function say(text, isError) {
        message = text;
        messageIsError = isError;
    }

    function parseDevices(text) {
        const found = [];
        let wifi = "";
        let activeName = "";
        for (const line of text.trim().split("\n")) {
            const [device, type, state, connection] = fields(line);
            if (type === "wifi") {
                wifi = device;
                if (state === "connected") {
                    activeName = connection;
                }
            } else if (state.startsWith("connected") && type !== "loopback") {
                found.push({ type: type, name: connection || device });
            }
        }
        wifiDevice = wifi;
        others = found;
        if (activeName && wifi) {
            active = Object.assign({}, active || {}, { ssid: activeName });
            ipProc.command = ["nmcli", "-g", "IP4.ADDRESS", "device", "show", wifi];
            ipProc.running = true;
        } else {
            active = null;
        }
    }

    // The best signal per name; in use first, then saved ones, then by signal.
    function parseList(text) {
        const best = {};
        let current = null;
        for (const line of text.trim().split("\n")) {
            const [inUse, ssid, signal, security, frequency] = fields(line);
            if (!ssid) {
                continue;  // hidden networks: through the full settings
            }
            const network = { ssid: ssid, signal: parseInt(signal) || 0, secure: !!security && security !== "--",
                              band5: parseInt(frequency) >= 4900, inUse: inUse === "*" };
            if (network.inUse) {
                current = network;
            }
            if (!best[ssid] || best[ssid].signal < network.signal || network.inUse) {
                best[ssid] = network;
            }
        }
        const list = Object.values(best);
        list.sort((x, y) => (y.inUse - x.inUse) || (!!saved[y.ssid] - !!saved[x.ssid]) || (y.signal - x.signal));
        networks = list;
        ListModelSync.sync(otherNetworks, list.filter(n => !n.inUse), "ssid");
        if (current) {
            active = Object.assign({}, active || {}, { ssid: current.ssid, signal: current.signal });
        }
    }

    function connect(network, password) {
        busy = network.ssid;
        say("Подключаюсь к " + network.ssid + "…", false);
        // The password goes to nmcli's "Password:" prompt (--ask) through stdin: on the command line any user
        // would read it in `ps`.
        if (saved[network.ssid] && !password) {
            connectProc.command = ["nmcli", "connection", "up", "id", network.ssid];
        } else if (password) {
            connectProc.command = ["nmcli", "--ask", "device", "wifi", "connect", network.ssid];
        } else {
            connectProc.command = ["nmcli", "device", "wifi", "connect", network.ssid];
        }
        connectProc.password = password;
        connectProc.stdinEnabled = !!password;
        connectProc.target = network.ssid;
        connectProc.running = true;
    }

    function disconnect() {
        if (active) {
            run(["nmcli", "connection", "down", "id", active.ssid], "Отключено от " + active.ssid);
        }
    }

    function forget(ssid) {
        run(["nmcli", "connection", "delete", "id", ssid], "Сеть " + ssid + " забыта");
    }

    function setWifi(on) {
        wifiOn = on;
        run(["nmcli", "radio", "wifi", on ? "on" : "off"], on ? "Wi-Fi включён" : "Wi-Fi выключен");
    }

    function run(command, done) {
        actionProc.done = done;
        actionProc.command = command;
        actionProc.running = true;
    }

    Component.onCompleted: {
        refresh();
        editorCheck.running = true;
    }
    Timer { interval: 5000; running: true; repeat: true; onTriggered: if (!net.busy) net.refresh() }

    Process {
        id: radioProc
        command: ["nmcli", "radio", "wifi"]
        stdout: StdioCollector { onStreamFinished: net.wifiOn = this.text.trim() === "enabled" }
    }
    Process {
        id: devicesProc
        command: ["nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device"]
        stdout: StdioCollector { onStreamFinished: net.parseDevices(this.text) }
    }
    Process {
        id: ipProc
        stdout: StdioCollector {
            onStreamFinished: net.active = Object.assign({}, net.active || {}, { ip: this.text.trim().split("\n")[0].split("/")[0] })
        }
    }
    Process {
        id: savedProc
        command: ["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show"]
        stdout: StdioCollector {
            onStreamFinished: {
                const found = {};
                for (const line of this.text.trim().split("\n")) {
                    const [name, type] = net.fields(line);
                    if (type === "802-11-wireless") {
                        found[name] = true;
                    }
                }
                net.saved = found;
            }
        }
    }
    Process {
        id: listProc
        // --rescan no: the cached scan, instant; the refresh button asks for a new scan.
        command: ["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY,FREQ", "device", "wifi", "list", "--rescan", "no"]
        stdout: StdioCollector { onStreamFinished: net.parseList(this.text) }
    }
    Process {
        id: rescanProc
        command: ["nmcli", "device", "wifi", "rescan"]
        onExited: net.refresh()
    }
    Process {
        id: connectProc
        property string target: ""
        property string password: ""
        // Closing stdin after the one answer: a wrong password makes nmcli ask again, and an end of input then
        // fails the connection instead of leaving it waiting.
        onStarted: {
            if (!password) {
                return;
            }
            write(password + "\n");
            password = "";
            stdinEnabled = false;
        }
        stderr: StdioCollector { id: connectErr }
        onExited: code => {
            net.busy = "";
            if (code === 0) {
                net.say("Подключено к " + target, false);
                net.expanded = "";
            } else {
                const err = connectErr.text.toLowerCase();
                const wrongPassword = err.includes("secrets") || err.includes("password") || err.includes("802-1x");
                net.say((wrongPassword ? "Не подошёл пароль для " : "Не удалось подключиться к ") + target, true);
                net.expanded = target;
            }
            net.refresh();
        }
    }
    Process {
        id: actionProc
        property string done: ""
        onExited: code => {
            net.say(code === 0 ? done : "Не получилось: " + command.join(" "), code !== 0);
            net.refresh();
        }
    }
    Process {
        id: editorCheck
        property bool found: false
        command: ["sh", "-c", "command -v nm-connection-editor"]
        onExited: code => found = code === 0
    }
}
