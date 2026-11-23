pragma Singleton

// The phones KDE Connect knows (feature "kdeconnect"), as phone.py watch reports them, and the one the phone
// menu and waybar's custom/phone show: the one picked in the menu, else the first paired phone in reach, else
// the first paired one. The menu's actions run phone.py <action> <id>. Waybar's module asks bar() and is
// signalled to ask again when what it shows changes.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common
import "../common/pango.js" as Pango

Singleton {
    id: phone

    readonly property string script: Quickshell.env("HOME") + "/.config/hypr/scripts/phone.py"
    readonly property string phoneGlyph: "\u{f011c}"
    readonly property string chargingGlyph: "\u{f0084}"
    // "signal" of custom/phone in waybar/config.base.json.
    readonly property int barSignal: 12

    readonly property bool enabled: Features.on("kdeconnect")
    property bool running: false            // kdeconnectd is on the bus
    // [{id, name, type, reachable, paired, requested, requestedByPeer, key, battery: {charge, charging} | null}]
    property var devices: []
    property string pickedId: ""
    readonly property var paired: devices.filter(device => device.paired)
    readonly property var current: devices.find(device => device.id === pickedId)
                                    ?? paired.find(device => device.reachable) ?? paired[0] ?? devices[0] ?? null
    property string message: ""             // why the last action failed
    readonly property string barJson: enabled ? barState(current)
                                              : JSON.stringify({ text: "", tooltip: "", class: "none" })

    function pick(device) {
        pickedId = device.id;
    }

    // Quick calls: a ping, a ring, the clipboard, pairing.
    function act(verb, device) {
        run(quickRunner, verb, device);
    }

    // Calls that wait for the user or the phone: picking files to send, mounting the phone's storage. Kept apart,
    // so a ring still goes while the file window is open.
    function actSlowly(verb, device) {
        run(slowRunner, verb, device);
    }

    function run(runner, verb, device) {
        message = "";
        runner.start([verb, device.id], (lines, status) => {
            if (status !== 0) {
                message = lines.join(" ") || "phone.py " + verb + ": код " + status;
            }
        });
    }

    function read(line) {
        try {
            const state = JSON.parse(line);
            running = state.running;
            devices = state.devices;
        } catch (error) {
            console.warn("phone.py watch:", line);
        }
    }

    // The glyph alone while no paired phone is in reach: a click still opens the menu, where it gets paired.
    function barState(device) {
        if (!device) {
            return idleBar("Телефон не найден: откройте KDE Connect на телефоне в той же сети");
        }
        if (!device.paired) {
            return idleBar(Pango.escape(device.name) + ": не сопряжён, клик, чтобы сопрячь");
        }
        if (!device.reachable) {
            return idleBar(Pango.escape(device.name) + ": не на связи");
        }
        const battery = device.battery;
        const charge = battery ? " " + battery.charge + "%" : "";
        const charging = battery && battery.charging ? " " + chargingGlyph : "";
        const status = !battery ? "на связи"
                       : "заряд " + battery.charge + "%" + (battery.charging ? ", заряжается" : "");
        return JSON.stringify({ text: phoneGlyph + charge + charging,
                                tooltip: Pango.escape(device.name) + ": " + status,
                                class: battery && battery.charging ? "charging" : "connected" });
    }

    // Set here, not bound: the restart below assigns it too, and an assignment would drop a binding.
    function idleBar(tooltip) {
        return JSON.stringify({ text: phoneGlyph, tooltip: tooltip, class: "none" });
    }

    onEnabledChanged: {
        watcher.running = enabled;
        if (!enabled) {
            running = false;
            devices = [];
        }
    }
    Component.onCompleted: watcher.running = enabled
    onBarJsonChanged: waybarModule.refresh()

    BarSignal {
        id: waybarModule
        number: phone.barSignal
    }

    Process {
        id: watcher
        command: ["python3", "-u", phone.script, "watch"]
        stdout: SplitParser { onRead: line => phone.read(line) }
        stderr: SplitParser { onRead: line => console.warn("phone.py watch:", line) }
        onExited: if (phone.enabled) restart.start()
    }

    // The watcher only ends on a crash: try again a bit later, not in a loop.
    Timer {
        id: restart
        interval: 5000
        onTriggered: watcher.running = phone.enabled
    }

    ScriptRunner { id: quickRunner; script: phone.script }
    ScriptRunner { id: slowRunner; script: phone.script }

    IpcHandler {
        target: "phone"

        function bar(): string {
            return phone.barJson;
        }
    }
}
