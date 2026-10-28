// Network panel, toggled by ~/.local/bin/network-panel (click on the network in waybar).
// Wi-Fi on/off, the current connection, nearby networks with the password asked in place,
// forgetting saved networks. Everything goes through nmcli; the list refreshes every few seconds.
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    readonly property string themeDir: Quickshell.env("NET_THEME_DIR")
    property var pal: ({ colors: {} })
    property var ui: ({})
    readonly property var c: pal.colors || {}
    readonly property string titleFont: ui.titleFont === "display" ? (pal.display || "serif") : (pal.font || "monospace")
    readonly property string bodyFont: !ui.bodyFont || ui.bodyFont === "font" ? (pal.font || "monospace")
                                       : ui.bodyFont === "display" ? (pal.display || "serif") : ui.bodyFont
    readonly property string glyphFont: "JetBrainsMono Nerd Font"
    readonly property int r: Math.min(ui.radius ?? 14, 18)
    property bool closing: false

    FileView { id: palFile; path: root.themeDir + "/palette.json"; blockLoading: true }
    FileView { id: uiFile; path: root.themeDir + "/ui.json"; blockLoading: true }
    Component.onCompleted: {
        try { pal = JSON.parse(palFile.text()); } catch (e) {}
        try { ui = JSON.parse(uiFile.text()); } catch (e) {}
        net.refresh();
        editorCheck.running = true;
    }

    function a(col, al) {
        return "#" + ("0" + Math.round(al * 255).toString(16)).slice(-2) + String(col || "#888888").slice(1);
    }

    function close() {
        if (closing) return;
        closing = true;
        outAnim.start();
    }

    IpcHandler {
        target: "network"
        function close(): void { root.close(); }
    }

    // ---------- NetworkManager state ----------

    QtObject {
        id: net
        property bool wifiOn: true
        property string wifiDevice: ""
        property var active: null       // { ssid, signal, ip }
        property var others: []          // other connected devices: [{ type, name }]
        property var networks: []        // [{ ssid, signal, secure, band5, saved, inUse }]
        property var saved: ({})         // wifi profile name -> true
        property string busy: ""         // ssid being connected, or "" when idle
        property string message: ""
        property bool messageIsError: false
        property string expanded: ""     // ssid whose password row is open

        // nmcli -t separates fields with ':' and escapes ':' and '\' inside them.
        function fields(line) {
            const out = [];
            let cur = "";
            for (let i = 0; i < line.length; i++) {
                const ch = line[i];
                if (ch === "\\" && i + 1 < line.length) { cur += line[++i]; continue; }
                if (ch === ":") { out.push(cur); cur = ""; continue; }
                cur += ch;
            }
            out.push(cur);
            return out;
        }

        function refresh() {
            radioProc.running = true;
            devicesProc.running = true;
            savedProc.running = true;
            listProc.running = true;
        }

        function parseDevices(text) {
            const others = [];
            let wifiDevice = "", activeName = "";
            for (const line of text.trim().split("\n")) {
                const [dev, type, state, conn] = fields(line);
                if (type === "wifi") {
                    wifiDevice = dev;
                    if (state === "connected") activeName = conn;
                } else if (state.startsWith("connected") && type !== "loopback") {
                    others.push({ type: type, name: conn || dev });
                }
            }
            net.wifiDevice = wifiDevice;
            net.others = others;
            if (activeName && wifiDevice) {
                net.active = Object.assign({}, net.active || {}, { ssid: activeName });
                ipProc.command = ["nmcli", "-g", "IP4.ADDRESS", "device", "show", wifiDevice];
                ipProc.running = true;
            } else {
                net.active = null;
            }
        }

        function parseList(text) {
            const best = {};
            let current = null;
            for (const line of text.trim().split("\n")) {
                if (!line) continue;
                const [inUse, ssid, signal, security, freq] = fields(line);
                if (!ssid) continue;  // hidden networks: through the full settings
                const n = { ssid: ssid, signal: parseInt(signal) || 0, secure: !!security && security !== "--",
                            band5: parseInt(freq) >= 4900, inUse: inUse === "*" };
                if (n.inUse) current = n;
                if (!best[ssid] || best[ssid].signal < n.signal || n.inUse) best[ssid] = n;
            }
            const list = Object.values(best);
            list.sort((x, y) => (y.inUse - x.inUse) || (!!net.saved[y.ssid] - !!net.saved[x.ssid]) || (y.signal - x.signal));
            net.networks = list;
            if (current) net.active = Object.assign({}, net.active || {}, { ssid: current.ssid, signal: current.signal });
        }

        function connect(n, password) {
            busy = n.ssid;
            message = "Подключаюсь к " + n.ssid + "…";
            messageIsError = false;
            if (net.saved[n.ssid] && !password)
                connectProc.command = ["nmcli", "connection", "up", "id", n.ssid];
            else if (password)
                connectProc.command = ["nmcli", "device", "wifi", "connect", n.ssid, "password", password];
            else
                connectProc.command = ["nmcli", "device", "wifi", "connect", n.ssid];
            connectProc.target = n.ssid;
            connectProc.running = true;
        }

        function disconnect() {
            if (!net.active) return;
            run(["nmcli", "connection", "down", "id", net.active.ssid], "Отключено от " + net.active.ssid);
        }

        function forget(ssid) {
            run(["nmcli", "connection", "delete", "id", ssid], "Сеть " + ssid + " забыта");
        }

        function setWifi(on) {
            net.wifiOn = on;
            run(["nmcli", "radio", "wifi", on ? "on" : "off"], on ? "Wi-Fi включён" : "Wi-Fi выключен");
        }

        function run(cmd, done) {
            actionProc.done = done;
            actionProc.command = cmd;
            actionProc.running = true;
        }
    }

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
                const saved = {};
                for (const line of this.text.trim().split("\n")) {
                    const [name, type] = net.fields(line);
                    if (type === "802-11-wireless") saved[name] = true;
                }
                net.saved = saved;
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
        stderr: StdioCollector { id: connectErr }
        onExited: code => {
            net.busy = "";
            if (code === 0) {
                net.message = "Подключено к " + target;
                net.messageIsError = false;
                net.expanded = "";
            } else {
                const err = connectErr.text.toLowerCase();
                net.message = err.includes("secrets") || err.includes("password") || err.includes("802-1x")
                    ? "Не подошёл пароль для " + target : "Не удалось подключиться к " + target;
                net.messageIsError = true;
                net.expanded = target;
            }
            net.refresh();
        }
    }
    Process {
        id: actionProc
        property string done: ""
        onExited: code => {
            net.message = code === 0 ? done : "Не получилось: " + command.join(" ");
            net.messageIsError = code !== 0;
            net.refresh();
        }
    }
    Process {
        id: editorCheck
        property bool found: false
        command: ["sh", "-c", "command -v nm-connection-editor"]
        onExited: code => found = code === 0
    }
    Timer { interval: 5000; running: true; repeat: true; onTriggered: if (!net.busy) net.refresh() }

    function signalGlyph(signal) {
        const level = signal >= 75 ? 3 : signal >= 50 ? 2 : signal >= 25 ? 1 : 0;
        return ["\u{f091f}", "\u{f0922}", "\u{f0925}", "\u{f0928}"][level];
    }

    // ---------- window ----------

    PanelWindow {
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "network-panel"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        Item {
            id: scene
            anchors.fill: parent
            opacity: 0
            focus: true
            Keys.onEscapePressed: root.close()
            Component.onCompleted: inAnim.start()
            ParallelAnimation {
                id: inAnim
                NumberAnimation { target: scene; property: "opacity"; to: 1; duration: 160 }
                NumberAnimation { target: card; property: "anchors.topMargin"; from: 34; to: 50; duration: 220; easing.type: Easing.OutCubic }
            }
            SequentialAnimation {
                id: outAnim
                NumberAnimation { target: scene; property: "opacity"; to: 0; duration: 140 }
                ScriptAction { script: Qt.quit() }
            }

            Rectangle { anchors.fill: parent; color: root.a(root.c.bg, 0.25) }
            MouseArea { anchors.fill: parent; onClicked: root.close() }

            Rectangle {
                id: card
                anchors { top: parent.top; right: parent.right; topMargin: 50; rightMargin: 14 }
                width: 410
                // Header and footer keep their size; the network list gets what is left and scrolls.
                height: Math.min(18 + top.implicitHeight + (net.wifiOn ? 14 + list.implicitHeight : 0)
                                 + (bottom.implicitHeight > 0 ? 14 + bottom.implicitHeight : 0) + 18,
                                 parent.height - 80)
                radius: root.r
                color: root.a(root.c.bg, 0.96)
                border.width: root.ui.border ?? 1
                border.color: root.a(root.c.accent, root.ui.glow ? 0.9 : 0.4)
                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: root.ui.glow ? (root.c.accent || "black") : "#000000"
                    shadowBlur: 0.8; shadowVerticalOffset: root.ui.glow ? 0 : 8; blurMax: 32
                }
                MouseArea { anchors.fill: parent }   // clicks inside do not close

                Column {
                    id: top
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 18 }
                    spacing: 14

                    // Header: title, rescan, Wi-Fi switch.
                    Item {
                        width: parent.width; height: 34
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.ui.upperTitle ? "СЕТЬ" : "Сеть"
                            font.family: root.titleFont; font.pixelSize: 24; font.bold: true; font.italic: !!root.ui.italicTitle
                            color: root.c.fg || "white"
                        }
                        Row {
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            spacing: 10
                            IconButton {
                                glyph: "\u{f0450}"
                                hint: "Обновить список"
                                spinning: rescanProc.running
                                onClicked: { net.message = "Ищу сети…"; net.messageIsError = false; rescanProc.running = true; }
                            }
                            Switch {
                                checked: net.wifiOn
                                onToggled: net.setWifi(!net.wifiOn)
                            }
                        }
                    }

                    // The current Wi-Fi connection.
                    Rectangle {
                        visible: !!net.active
                        width: parent.width; height: 64
                        radius: root.r
                        color: root.a(root.c.accent, 0.14)
                        border.width: 1; border.color: root.a(root.c.accent, 0.5)
                        Text {
                            id: activeIcon
                            anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                            text: root.signalGlyph(net.active ? net.active.signal || 0 : 0)
                            font.family: root.glyphFont; font.pixelSize: 24
                            color: root.c.accent || "white"
                        }
                        Column {
                            anchors { left: activeIcon.right; leftMargin: 12; right: disconnectBtn.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                            spacing: 3
                            Text {
                                width: parent.width; elide: Text.ElideRight
                                text: net.active ? net.active.ssid || "" : ""
                                font.family: root.bodyFont; font.pixelSize: 15; font.bold: true
                                color: root.c.fg || "white"
                            }
                            Text {
                                text: "подключено" + (net.active && net.active.ip ? " · " + net.active.ip : "")
                                font.family: root.bodyFont; font.pixelSize: 12
                                color: root.c.muted || "grey"
                            }
                        }
                        TextButton {
                            id: disconnectBtn
                            anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                            label: "Отключить"
                            onClicked: net.disconnect()
                        }
                    }

                    // Ethernet, VPN tunnels and the like.
                    Repeater {
                        model: net.others
                        Row {
                            required property var modelData
                            spacing: 10
                            Text {
                                text: modelData.type === "ethernet" ? "\u{f0200}" : "\u{f0582}"
                                font.family: root.glyphFont; font.pixelSize: 16
                                color: root.c.good || "lightgreen"
                            }
                            Text {
                                text: (modelData.type === "ethernet" ? "Кабель: " : modelData.type === "tun" || modelData.type === "wireguard" || modelData.type === "vpn" ? "VPN: " : modelData.type + ": ") + modelData.name
                                font.family: root.bodyFont; font.pixelSize: 13
                                color: root.c.muted || "grey"
                            }
                        }
                    }

                    Text {
                        visible: net.wifiOn
                        text: "Доступные сети" + (net.networks.length ? "  ·  " + net.networks.length : "")
                        font.family: root.bodyFont; font.pixelSize: 12; font.capitalization: Font.AllUppercase
                        font.letterSpacing: 1
                        color: root.c.muted || "grey"
                    }
                    Text {
                        visible: !net.wifiOn
                        width: parent.width; wrapMode: Text.Wrap
                        text: "Wi-Fi выключен. Включи переключателем сверху."
                        font.family: root.bodyFont; font.pixelSize: 14
                        color: root.c.muted || "grey"
                    }
                }

                Flickable {
                        visible: net.wifiOn
                        anchors { left: parent.left; right: parent.right; top: top.bottom; bottom: bottom.top
                                  leftMargin: 18; rightMargin: 18; topMargin: 14; bottomMargin: bottom.implicitHeight > 0 ? 14 : 0 }
                        contentHeight: list.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        Column {
                            id: list
                            width: parent.width
                            spacing: 6
                            Repeater {
                                model: net.networks.filter(n => !n.inUse)
                                NetworkRow { required property var modelData; network: modelData }
                            }
                        }
                    }

                Column {
                    id: bottom
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 18 }
                    spacing: 10

                    Text {
                        visible: !!net.message
                        width: parent.width; wrapMode: Text.Wrap
                        text: net.message
                        font.family: root.bodyFont; font.pixelSize: 13
                        color: net.messageIsError ? (root.c.crit || "red") : (root.c.accent2 || root.c.fg || "white")
                    }

                    TextButton {
                        visible: editorCheck.found
                        label: "Все настройки сети…"
                        onClicked: { Quickshell.execDetached(["nm-connection-editor"]); root.close(); }
                    }
                }
            }
        }
    }

    // ---------- components ----------

    component NetworkRow: Rectangle {
        id: row
        property var network
        readonly property bool saved: !!net.saved[network.ssid]
        readonly property bool open: net.expanded === network.ssid
        readonly property bool connecting: net.busy === network.ssid
        width: parent ? parent.width : 0
        height: open ? 104 : 48
        radius: root.r
        color: rowHover.hovered || open ? root.a(root.c.bg2, 0.95) : root.a(root.c.bg2, 0.55)
        border.width: open ? 1 : 0
        border.color: root.a(root.c.accent, 0.5)
        Behavior on height { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        clip: true

        // Hover of the whole row, buttons inside included: a MouseArea loses it to the forget button
        // on top of it, which then hides the button, which gives the hover back, in a loop.
        HoverHandler { id: rowHover }

        MouseArea {
            id: rowMouse
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: 48
            hoverEnabled: true
            onClicked: {
                if (row.network.secure && !row.saved) {
                    const opening = !row.open;
                    net.expanded = opening ? row.network.ssid : "";
                    if (opening) pass.forceActiveFocus();
                } else {
                    net.connect(row.network, "");
                }
            }
        }

        Text {
            id: icon
            x: 14; y: 12
            text: root.signalGlyph(row.network.signal)
            font.family: root.glyphFont; font.pixelSize: 20
            color: row.saved ? (root.c.accent || "white") : (root.c.fg || "white")
        }
        Text {
            id: lock
            visible: row.network.secure
            anchors { left: icon.right; leftMargin: 2 }
            y: 20
            text: "\u{f033e}"
            font.family: root.glyphFont; font.pixelSize: 11
            color: root.c.muted || "grey"
        }
        Text {
            anchors { left: icon.right; leftMargin: 16; right: tags.left; rightMargin: 8 }
            y: 14
            elide: Text.ElideRight
            text: row.network.ssid
            font.family: root.bodyFont; font.pixelSize: 14
            color: root.c.fg || "white"
        }
        Row {
            id: tags
            anchors { right: parent.right; rightMargin: 12 }
            y: 12
            spacing: 6
            Chip { visible: row.network.band5; label: "5G" }
            Chip { visible: row.saved && !row.connecting; label: "сохранена" }
            Chip { visible: row.connecting; label: "подключаю…"; tone: root.c.accent }
            IconButton {
                visible: row.saved && !row.connecting && rowHover.hovered
                glyph: "\u{f0a7a}"
                hint: "Забыть сеть"
                small: true
                onClicked: net.forget(row.network.ssid)
            }
        }

        // Password, asked in place for a new secured network.
        Rectangle {
            visible: row.open
            x: 14; y: 54
            width: row.width - 28 - connectBtn.width - 10; height: 36
            radius: Math.min(root.r, 10)
            color: root.a(root.c.bg, 0.9)
            border.width: 1
            border.color: pass.activeFocus ? (root.c.accent || "white") : root.a(root.c.muted, 0.4)
            TextInput {
                id: pass
                anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                verticalAlignment: TextInput.AlignVCenter
                echoMode: TextInput.Password
                font.family: root.bodyFont; font.pixelSize: 14
                color: root.c.fg || "white"
                selectionColor: root.a(root.c.accent, 0.4)
                clip: true
                Keys.onReturnPressed: if (text.length >= 8) net.connect(row.network, text)
                Keys.onEscapePressed: { net.expanded = ""; scene.forceActiveFocus(); }
                Text {
                    visible: !parent.text
                    anchors.verticalCenter: parent.verticalCenter
                    text: "пароль"
                    font: parent.font
                    color: root.c.muted || "grey"
                }
            }
        }
        TextButton {
            id: connectBtn
            visible: row.open
            anchors { right: parent.right; rightMargin: 14 }
            y: 56
            label: "Подключить"
            enabled: pass.text.length >= 8 && !row.connecting
            onClicked: net.connect(row.network, pass.text)
        }
    }

    component Chip: Rectangle {
        property string label: ""
        property color tone: root.c.muted || "grey"
        height: 22; width: chipText.implicitWidth + 14
        radius: 11
        color: root.a(String(tone), 0.18)
        Text {
            id: chipText
            anchors.centerIn: parent
            text: parent.label
            font.family: root.bodyFont; font.pixelSize: 11
            color: parent.tone
        }
    }

    component TextButton: Rectangle {
        id: tb
        property string label: ""
        signal clicked()
        height: 32; width: tbText.implicitWidth + 24
        radius: Math.min(root.r, 10)
        opacity: enabled ? 1 : 0.45
        color: tbMouse.containsMouse && enabled ? root.a(root.c.accent, 0.3) : root.a(root.c.accent, 0.16)
        border.width: 1; border.color: root.a(root.c.accent, 0.55)
        Text {
            id: tbText
            anchors.centerIn: parent
            text: tb.label
            font.family: root.bodyFont; font.pixelSize: 13
            color: root.c.fg || "white"
        }
        MouseArea { id: tbMouse; anchors.fill: parent; hoverEnabled: true; onClicked: if (tb.enabled) tb.clicked() }
    }

    component IconButton: Rectangle {
        id: ib
        property string glyph: ""
        property string hint: ""
        property bool spinning: false
        property bool small: false
        signal clicked()
        width: small ? 24 : 32; height: width
        radius: width / 2
        color: ibMouse.containsMouse ? root.a(root.c.accent, 0.25) : "transparent"
        Text {
            anchors.centerIn: parent
            text: ib.glyph
            font.family: root.glyphFont; font.pixelSize: ib.small ? 14 : 18
            color: ibMouse.containsMouse ? (root.c.accent || "white") : (root.c.fg || "white")
            RotationAnimation on rotation { running: ib.spinning; from: 0; to: 360; duration: 900; loops: Animation.Infinite }
        }
        MouseArea { id: ibMouse; anchors.fill: parent; hoverEnabled: true; onClicked: ib.clicked() }
    }

    component Switch: Rectangle {
        id: sw
        property bool checked: false
        signal toggled()
        width: 46; height: 26
        radius: 13
        color: checked ? root.a(root.c.accent, 0.85) : root.a(root.c.muted, 0.35)
        Behavior on color { ColorAnimation { duration: 150 } }
        Rectangle {
            width: 20; height: 20; radius: 10
            y: 3
            x: sw.checked ? sw.width - width - 3 : 3
            color: root.c.bg || "black"
            Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        }
        MouseArea { anchors.fill: parent; onClicked: sw.toggled() }
    }
}
