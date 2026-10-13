// Settings window, toggled by ~/.local/bin/settings-panel (Alt+F2, waybar gear, launcher).
//   Мониторы  — layout by dragging, resolution, refresh rate, scale, on/off. Applied live with a
//               15 s "keep?" countdown; kept settings go to ~/.config/hypr/monitors.lua.
//   Клавиши   — the editable binds keybind.lua registers ($XDG_RUNTIME_DIR/hypr-binds-registry.json),
//               the main modifier and the user's own binds; saved to ~/.config/hypr/binds-user.lua.
//   Тема      — the themes, as in the theme picker.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string themeDir: Quickshell.env("SETTINGS_THEME_DIR")
    readonly property string registryPath: Quickshell.env("XDG_RUNTIME_DIR") + "/hypr-binds-registry.json"
    property var pal: ({ colors: {} })
    property var ui: ({})
    property var themes: []
    property bool closing: false
    property string page: Quickshell.env("SETTINGS_PAGE") || "monitors"
    readonly property var c: pal.colors || {}
    readonly property string titleFont: ui.titleFont === "display" ? (pal.display || "serif") : (pal.font || "monospace")
    readonly property string bodyFont: !ui.bodyFont || ui.bodyFont === "font" ? (pal.font || "monospace")
                                       : ui.bodyFont === "display" ? (pal.display || "serif") : ui.bodyFont
    readonly property int r: Math.min(ui.radius ?? 14, 22)

    FileView { id: palFile; path: root.themeDir + "/palette.json"; blockLoading: true }
    FileView { id: uiFile; path: root.themeDir + "/ui.json"; blockLoading: true }

    Component.onCompleted: {
        try { pal = JSON.parse(palFile.text()); } catch (e) {}
        try { ui = JSON.parse(uiFile.text()); } catch (e) {}
        try { themes = JSON.parse(Quickshell.env("SETTINGS_THEMES") || "[]"); } catch (e) {}
        monProc.running = true;
        bindsProc.running = true;
    }

    function a(col, al) {
        return "#" + ("0" + Math.round(al * 255).toString(16)).slice(-2) + String(col || "#888888").slice(1);
    }

    function close() {
        if (closing) return;
        closing = true;
        if (keys.capturing !== "") keys.stopCapture();
        if (mon.pending) mon.revert();
        outAnim.start();
    }

    // Writes a file, then optionally runs a command (all detached, in that order).
    function writeFile(path, text, after) {
        Quickshell.execDetached(["sh", "-c", 'printf "%s" "$1" > "$2" && [ -z "$3" ] || sh -c "$3"',
                                 "sh", text, path, after || ""]);
    }

    IpcHandler {
        target: "settings"
        function close(): void { root.close(); }
        function show(name: string): void { root.page = name; }
    }

    // ================= monitors: data =================

    QtObject {
        id: mon
        property var list: []        // as Hyprland has them now
        property var edit: []        // what the panel shows and changes
        property int sel: 0
        property bool pending: false // applied live, waiting for "keep"
        property int countdown: 0
        property string status: ""

        function parse(text) {
            let raw = [];
            try { raw = JSON.parse(text); } catch (e) { return; }
            const out = raw.map(m => {
                const modes = (m.availableModes || []).map(s => {
                    const mm = /^(\d+)x(\d+)@([\d.]+)Hz$/.exec(s);
                    return mm ? { w: +mm[1], h: +mm[2], rate: +mm[3] } : null;
                }).filter(x => x);
                if (!modes.find(x => x.w === m.width && x.h === m.height))
                    modes.push({ w: m.width, h: m.height, rate: m.refreshRate });
                return { name: m.name, desc: m.description || "", w: m.width, h: m.height,
                         rate: m.refreshRate, x: m.x, y: m.y, scale: m.scale, disabled: !!m.disabled, modes: modes };
            });
            list = out;
            edit = JSON.parse(JSON.stringify(out));
            sel = Math.min(sel, Math.max(0, edit.length - 1));
        }

        function setField(i, key, value) {
            const e = JSON.parse(JSON.stringify(edit));
            e[i][key] = value;
            if (key === "res") {
                const [w, h] = value.split("x").map(Number);
                e[i].w = w; e[i].h = h;
                e[i].rate = Math.max(...e[i].modes.filter(m => m.w === w && m.h === h).map(m => m.rate));
                delete e[i].res;
            }
            edit = e;
        }

        function changed() { return JSON.stringify(edit) !== JSON.stringify(list); }
        function lw(m) { return Math.round(m.w / m.scale); }
        function lh(m) { return Math.round(m.h / m.scale); }

        // A monitor dropped at logical (x, y): snap to the other screens' edges, then keep the
        // layout's top-left corner at 0x0.
        function drop(i, x, y) {
            const e = JSON.parse(JSON.stringify(edit));
            const me = e[i];
            let bx = x, by = y, dx = 1e9, dy = 1e9;
            for (let j = 0; j < e.length; j++) {
                if (j === i || e[j].disabled) continue;
                const o = e[j];
                for (const cx of [o.x + lw(o), o.x - lw(me), o.x, o.x + lw(o) - lw(me)])
                    if (Math.abs(cx - x) < dx) { dx = Math.abs(cx - x); bx = cx; }
                for (const cy of [o.y + lh(o), o.y - lh(me), o.y, o.y + lh(o) - lh(me)])
                    if (Math.abs(cy - y) < dy) { dy = Math.abs(cy - y); by = cy; }
            }
            me.x = dx < 160 ? bx : Math.round(x);
            me.y = dy < 160 ? by : Math.round(y);
            const on = e.filter(m => !m.disabled);
            const minX = Math.min(...on.map(m => m.x)), minY = Math.min(...on.map(m => m.y));
            for (const m of e) { m.x -= minX; m.y -= minY; }
            edit = e;
        }

        function spec(m) {
            if (m.disabled) return `hl.monitor({ output = "${m.name}", disabled = true })`;
            const rate = (+m.rate).toFixed(2).replace(/\.?0+$/, "");
            return `hl.monitor({ output = "${m.name}", mode = "${m.w}x${m.h}@${rate}", position = "${m.x}x${m.y}", scale = ${m.scale} })`;
        }

        function apply() {
            if (edit.filter(m => !m.disabled).length === 0) { status = "Хотя бы один экран должен остаться включённым"; return; }
            Quickshell.execDetached(["hyprctl", "eval", edit.map(spec).join("\n")]);
            pending = true;
            countdown = 15;
            status = "";
            countdownTimer.restart();
        }

        function keep() {
            pending = false;
            countdownTimer.stop();
            monFile.reload();
            saveTimer.restart();
        }

        function revert() {
            pending = false;
            countdownTimer.stop();
            // monitors.lua still has the old setup; a reload puts it back.
            Quickshell.execDetached(["hyprctl", "reload"]);
            status = "Вернул как было";
            refreshTimer.restart();
        }

        function save(oldText) {
            // Our monitor lines replace any hl.monitor(...) in the file; the rest (workspace rules
            // and the like) stays.
            const rest = (oldText || "")
                .replace(/^-- Monitors written by the settings panel.*\n/gm, "")
                .replace(/hl\.monitor\(\{[\s\S]*?\}\)[ \t]*\n?/g, "")
                .replace(/^\s*\n/, "");
            const head = "-- Monitors written by the settings panel (Alt+F2); other lines below are kept.\n"
                + 'hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })\n'
                + edit.map(spec).join("\n") + "\n";
            root.writeFile(root.home + "/.config/hypr/monitors.lua", head + (rest ? "\n" + rest : ""), "");
            list = JSON.parse(JSON.stringify(edit));
            status = "Сохранено в monitors.lua";
        }
    }

    Process {
        id: monProc
        command: ["hyprctl", "monitors", "all", "-j"]
        stdout: StdioCollector { onStreamFinished: mon.parse(this.text) }
    }
    FileView { id: monFile; path: root.home + "/.config/hypr/monitors.lua" }
    Timer { id: saveTimer; interval: 150; onTriggered: mon.save(monFile.text()) }
    Timer { id: refreshTimer; interval: 1200; onTriggered: monProc.running = true }
    Timer {
        id: countdownTimer
        interval: 1000; repeat: true
        onTriggered: { mon.countdown -= 1; if (mon.countdown <= 0) mon.revert(); }
    }

    // ================= hotkeys: data =================

    QtObject {
        id: keys
        property string mainMod: "ALT"
        property var binds: []      // {id, default, current, description, group, text}
        property var custom: []     // {keys, cmd, name}
        property var others: []     // hyprctl binds that are not editable here (for conflicts)
        property string capturing: ""   // bind id, "custom" or ""
        property string captured: ""
        property string conflict: ""
        property bool dirty: false
        property string status: ""

        function load(text) {
            let reg = {};
            try { reg = JSON.parse(text); } catch (e) { return; }
            mainMod = reg.mainMod || "ALT";
            binds = (reg.binds || []).map(b => {
                const p = (b.description || "").split("|").map(s => s.trim());
                return Object.assign({}, b, { group: p[0] || "Прочее", text: p[1] || b.id });
            });
            custom = reg.custom || [];
            dirty = false;
        }

        // "SUPER + SHIFT + G" <-> modmask + key, the way `hyprctl binds` reports them.
        function parseCombo(s) {
            const parts = s.split("+").map(x => x.trim()).filter(x => x);
            const bits = { SHIFT: 1, CTRL: 4, CONTROL: 4, ALT: 8, SUPER: 64, WIN: 64, MOD4: 64 };
            let mask = 0, k = "";
            for (const p of parts) {
                const u = p.toUpperCase();
                if (bits[u] !== undefined) mask |= bits[u]; else k = p;
            }
            return { mask: mask, key: k.toLowerCase() };
        }

        function label(s) {
            if (!s) return "выключено";
            const names = { "return": "Enter", "print": "PrtSc", "space": "Space", "tab": "Tab",
                            "left": "←", "right": "→", "up": "↑", "down": "↓", "prior": "PgUp", "next": "PgDn" };
            return s.split("+").map(x => x.trim()).map(x => {
                const u = x.toUpperCase();
                if (u === "SUPER") return "Super";
                if (u === "ALT") return "Alt";
                if (u === "CTRL" || u === "CONTROL") return "Ctrl";
                if (u === "SHIFT") return "Shift";
                return names[x.toLowerCase()] || (x.length === 1 ? x.toUpperCase() : x);
            }).join("+");
        }

        function conflicts(combo, exceptId) {
            const c = parseCombo(combo);
            const same = s => { const o = parseCombo(s); return o.mask === c.mask && o.key === c.key; };
            for (const b of binds)
                if (b.id !== exceptId && b.current && same(b.current)) return b.text;
            for (const u of custom)
                if (exceptId !== "custom:" + u.keys && same(u.keys)) return u.name || u.cmd;
            for (const o of others)
                if (o.mask === c.mask && o.key === c.key) return o.text;
            return "";
        }

        function setCurrent(id, combo) {
            binds = binds.map(b => b.id === id ? Object.assign({}, b, { current: combo }) : b);
            dirty = true;
        }

        function startCapture(id) {
            capturing = id;
            captured = "";
            conflict = "";
            // Hyprland handles its own binds before any window sees the keys; in the passthrough
            // submap everything reaches us.
            Quickshell.execDetached(["hyprctl", "dispatch", 'hl.dsp.submap("passthrough")']);
            scene.forceActiveFocus();
        }

        function stopCapture() {
            capturing = "";
            Quickshell.execDetached(["hyprctl", "dispatch", 'hl.dsp.submap("reset")']);
        }

        // Layout-independent: letters and digits by keycode (US positions), so a Russian layout
        // still gives "R" for the R key.
        readonly property var byCode: ({
            10: "1", 11: "2", 12: "3", 13: "4", 14: "5", 15: "6", 16: "7", 17: "8", 18: "9", 19: "0",
            20: "minus", 21: "equal", 24: "Q", 25: "W", 26: "E", 27: "R", 28: "T", 29: "Y", 30: "U",
            31: "I", 32: "O", 33: "P", 34: "bracketleft", 35: "bracketright", 38: "A", 39: "S", 40: "D",
            41: "F", 42: "G", 43: "H", 44: "J", 45: "K", 46: "L", 47: "semicolon", 48: "apostrophe",
            49: "grave", 51: "backslash", 52: "Z", 53: "X", 54: "C", 55: "V", 56: "B", 57: "N", 58: "M",
            59: "comma", 60: "period", 61: "slash"
        })

        function keyName(e) {
            if (byCode[e.nativeScanCode]) return byCode[e.nativeScanCode];
            if (e.key >= Qt.Key_F1 && e.key <= Qt.Key_F24) return "F" + (e.key - Qt.Key_F1 + 1);
            const named = {};
            named[Qt.Key_Return] = "Return"; named[Qt.Key_Enter] = "KP_Enter"; named[Qt.Key_Space] = "space";
            named[Qt.Key_Tab] = "Tab"; named[Qt.Key_Backspace] = "BackSpace"; named[Qt.Key_Delete] = "Delete";
            named[Qt.Key_Insert] = "Insert"; named[Qt.Key_Home] = "Home"; named[Qt.Key_End] = "End";
            named[Qt.Key_PageUp] = "Prior"; named[Qt.Key_PageDown] = "Next"; named[Qt.Key_Left] = "left";
            named[Qt.Key_Right] = "right"; named[Qt.Key_Up] = "up"; named[Qt.Key_Down] = "down";
            named[Qt.Key_Print] = "Print";
            return named[e.key] || "";
        }

        function onKey(e) {
            const mods = [Qt.Key_Shift, Qt.Key_Control, Qt.Key_Alt, Qt.Key_Meta, Qt.Key_Super_L,
                          Qt.Key_Super_R, Qt.Key_AltGr, Qt.Key_Hyper_L, Qt.Key_Hyper_R];
            if (mods.indexOf(e.key) !== -1) return;
            if (e.key === Qt.Key_Escape && !e.modifiers) { stopCapture(); return; }
            const k = keyName(e);
            if (!k) { status = "Эту клавишу назначить нельзя"; return; }
            const parts = [];
            if (e.modifiers & Qt.MetaModifier) parts.push("SUPER");
            if (e.modifiers & Qt.ControlModifier) parts.push("CTRL");
            if (e.modifiers & Qt.AltModifier) parts.push("ALT");
            if (e.modifiers & Qt.ShiftModifier) parts.push("SHIFT");
            parts.push(k);
            captured = parts.join(" + ");
            const target = capturing;
            stopCapture();
            conflict = conflicts(captured, target);
            if (target === "custom") { customForm.combo = captured; return; }
            pendingId = target;
            if (!conflict) { setCurrent(target, captured); pendingId = ""; }
        }
        property string pendingId: ""   // a combo that conflicts, waiting for "assign anyway"

        function save() {
            const q = s => JSON.stringify(String(s));
            const lines = ["-- Written by the settings panel (Alt+F2): your hotkey changes. Defaults are in keybind.lua.",
                           "return {"];
            if (mainMod !== "ALT") lines.push(`    mainMod = ${q(mainMod)},`);
            const over = binds.filter(b => b.current !== b.default);
            if (over.length) {
                lines.push("    keys = {");
                for (const b of over) lines.push(`        [${q(b.id)}] = ${b.current ? q(b.current) : "false"},`);
                lines.push("    },");
            }
            if (custom.length) {
                lines.push("    custom = {");
                for (const u of custom) lines.push(`        { keys = ${q(u.keys)}, cmd = ${q(u.cmd)}, name = ${q(u.name)} },`);
                lines.push("    },");
            }
            lines.push("}");
            root.writeFile(root.home + "/.config/hypr/binds-user.lua", lines.join("\n") + "\n", "hyprctl reload");
            status = "Сохранено, горячие клавиши обновлены";
            dirty = false;
            reloadTimer.restart();
        }

        function setMainMod(m) {
            if (m === mainMod) return;
            // Defaults follow the main key: binds still on their default move along.
            const from = mainMod;
            binds = binds.map(b => {
                const moved = s => s.replace(new RegExp("^" + from + "( \\+ )"), m + "$1");
                return Object.assign({}, b, { default: moved(b.default),
                                              current: b.current === b.default ? moved(b.default) : b.current });
            });
            mainMod = m;
            dirty = true;
        }
    }

    FileView { id: registryFile; path: root.registryPath; blockLoading: true }
    Process {
        id: bindsProc
        command: ["hyprctl", "binds", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                registryFile.reload();
                keys.load(registryFile.text());
                let all = [];
                try { all = JSON.parse(this.text); } catch (e) {}
                // Everything that is neither an editable bind nor one of the user's own.
                const mine = new Set(keys.binds.filter(b => b.current).map(b => JSON.stringify(keys.parseCombo(b.current)))
                    .concat(keys.custom.map(u => JSON.stringify(keys.parseCombo(u.keys)))));
                keys.others = all.filter(b => b.submap === "")
                    .map(b => ({ mask: b.modmask, key: String(b.key).toLowerCase(),
                                 text: (b.description || "").split("|")[1]?.trim() || b.key }))
                    .filter(o => !mine.has(JSON.stringify({ mask: o.mask, key: o.key })));
            }
        }
    }
    Timer { id: reloadTimer; interval: 900; onTriggered: bindsProc.running = true }

    // ================= window =================

    PanelWindow {
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "settings-panel"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        Item {
            id: scene
            anchors.fill: parent
            opacity: 0
            focus: true
            Keys.onPressed: e => {
                e.accepted = true;
                if (keys.capturing !== "") { keys.onKey(e); return; }
                if (e.key === Qt.Key_Escape) root.close();
            }
            Component.onCompleted: inAnim.start()
            NumberAnimation { id: inAnim; target: scene; property: "opacity"; to: 1; duration: 200 }
            SequentialAnimation {
                id: outAnim
                NumberAnimation { target: scene; property: "opacity"; to: 0; duration: 160 }
                ScriptAction { script: Qt.quit() }
            }

            Rectangle { anchors.fill: parent; color: root.a(root.c.bg, 0.7) }
            MouseArea { anchors.fill: parent; onClicked: root.close() }

            Rectangle {
                id: sheet
                anchors.centerIn: parent
                width: Math.min(parent.width - 80, 1280)
                height: Math.min(parent.height - 80, 860)
                radius: root.r
                color: root.a(root.c.bg, 0.96)
                border.width: root.ui.border ?? 1
                border.color: root.a(root.c.accent, 0.5)
                MouseArea { anchors.fill: parent; onClicked: scene.forceActiveFocus() }

                Row {
                    id: header
                    x: 32; y: 24
                    spacing: 14
                    Text {
                        text: "\u{f0493}"
                        font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 26
                        color: root.c.accent || "white"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: root.ui.upperTitle ? "НАСТРОЙКИ" : "Настройки"
                        font.family: root.titleFont; font.pixelSize: 30; font.italic: !!root.ui.italicTitle
                        color: root.c.fg || "white"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Item { width: 24; height: 1 }
                    Repeater {
                        model: [["monitors", "Мониторы"], ["keys", "Клавиши"], ["theme", "Тема"]]
                        TabButton {
                            required property var modelData
                            text: modelData[1]
                            active: root.page === modelData[0]
                            anchors.verticalCenter: parent.verticalCenter
                            onClicked: root.page = modelData[0]
                        }
                    }
                }
                Text {
                    anchors { right: parent.right; rightMargin: 32; verticalCenter: header.verticalCenter }
                    text: "Esc — закрыть"
                    font.family: root.bodyFont; font.pixelSize: 14
                    color: root.c.muted || "grey"
                }

                Item {
                    id: body
                    anchors { left: parent.left; right: parent.right; top: header.bottom; bottom: parent.bottom; margins: 28; topMargin: 22 }

                    // ---------------- Мониторы ----------------
                    Item {
                        anchors.fill: parent
                        visible: root.page === "monitors"

                        Rectangle {
                            id: layoutBox
                            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                            width: parent.width * 0.56
                            radius: Math.min(root.r, 16)
                            color: root.a(root.c.bg2, 0.8)
                            border.color: root.a(root.c.muted, 0.25)

                            readonly property var on: mon.edit.filter(m => !m.disabled)
                            readonly property real bw: Math.max(1, Math.max(...on.map(m => m.x + mon.lw(m)), 1))
                            readonly property real bh: Math.max(1, Math.max(...on.map(m => m.y + mon.lh(m)), 1))
                            readonly property real fit: Math.min((width - 80) / bw, (height - 110) / bh) * 0.8
                            readonly property real ox: (width - bw * fit) / 2
                            readonly property real oy: (height - 40 - bh * fit) / 2

                            Text {
                                x: 18; y: 14
                                text: "Расположение — перетащи экран мышкой"
                                font.family: root.bodyFont; font.pixelSize: 14
                                color: root.c.muted || "grey"
                            }

                            Repeater {
                                model: mon.edit
                                Rectangle {
                                    id: screenRect
                                    required property var modelData
                                    required property int index
                                    visible: !modelData.disabled
                                    x: layoutBox.ox + modelData.x * layoutBox.fit
                                    y: layoutBox.oy + modelData.y * layoutBox.fit + 20
                                    width: mon.lw(modelData) * layoutBox.fit
                                    height: mon.lh(modelData) * layoutBox.fit
                                    radius: 8
                                    color: mon.sel === index ? root.a(root.c.accent, 0.3) : root.a(root.c.accent, 0.12)
                                    border.width: mon.sel === index ? 2 : 1
                                    border.color: root.c.accent || "white"
                                    Column {
                                        anchors.centerIn: parent
                                        spacing: 4
                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: screenRect.modelData.name
                                            font.family: root.titleFont; font.pixelSize: 18; font.bold: true
                                            color: root.c.fg || "white"
                                        }
                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: screenRect.modelData.w + "×" + screenRect.modelData.h + " · "
                                                  + Math.round(screenRect.modelData.rate) + " Гц · ×" + screenRect.modelData.scale
                                            font.family: root.bodyFont; font.pixelSize: 13
                                            color: root.c.muted || "grey"
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        drag.target: parent
                                        cursorShape: Qt.SizeAllCursor
                                        onPressed: mon.sel = screenRect.index
                                        onReleased: mon.drop(screenRect.index,
                                                             (screenRect.x - layoutBox.ox) / layoutBox.fit,
                                                             (screenRect.y - 20 - layoutBox.oy) / layoutBox.fit)
                                    }
                                }
                            }
                        }

                        // Details of the selected screen.
                        Flickable {
                            anchors { left: layoutBox.right; leftMargin: 24; right: parent.right; top: parent.top; bottom: monButtons.top; bottomMargin: 12 }
                            contentHeight: details.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            Column {
                                id: details
                                width: parent.width
                                spacing: 14
                                readonly property var m: mon.edit[mon.sel] || null

                                Row {
                                    spacing: 8
                                    Repeater {
                                        model: mon.edit
                                        TabButton {
                                            required property var modelData
                                            required property int index
                                            text: modelData.name
                                            active: mon.sel === index
                                            onClicked: mon.sel = index
                                        }
                                    }
                                }
                                Text {
                                    visible: !!details.m
                                    width: parent.width
                                    text: details.m ? details.m.desc : ""
                                    wrapMode: Text.Wrap
                                    font.family: root.bodyFont; font.pixelSize: 14
                                    color: root.c.muted || "grey"
                                }

                                SectionTitle { text: "Экран" }
                                Row {
                                    spacing: 8
                                    Chip { text: "Включён"; active: details.m && !details.m.disabled; onClicked: mon.setField(mon.sel, "disabled", false) }
                                    Chip { text: "Выключен"; active: details.m && details.m.disabled; onClicked: mon.setField(mon.sel, "disabled", true) }
                                }

                                SectionTitle { text: "Разрешение" }
                                Flow {
                                    width: parent.width
                                    spacing: 8
                                    Repeater {
                                        model: details.m ? [...new Set(details.m.modes.map(x => x.w + "x" + x.h))]
                                                             .sort((p, q) => q.split("x")[0] * q.split("x")[1] - p.split("x")[0] * p.split("x")[1]) : []
                                        Chip {
                                            required property string modelData
                                            text: modelData.replace("x", "×")
                                            active: details.m && modelData === details.m.w + "x" + details.m.h
                                            onClicked: mon.setField(mon.sel, "res", modelData)
                                        }
                                    }
                                }

                                SectionTitle { text: "Частота" }
                                Flow {
                                    width: parent.width
                                    spacing: 8
                                    Repeater {
                                        model: details.m ? details.m.modes.filter(x => x.w === details.m.w && x.h === details.m.h)
                                                             .map(x => x.rate).filter((v, i, s) => s.indexOf(v) === i).sort((p, q) => q - p) : []
                                        Chip {
                                            required property real modelData
                                            text: (Math.round(modelData * 100) / 100) + " Гц"
                                            active: details.m && Math.abs(modelData - details.m.rate) < 0.01
                                            onClicked: mon.setField(mon.sel, "rate", modelData)
                                        }
                                    }
                                }

                                SectionTitle { text: "Масштаб" }
                                Flow {
                                    width: parent.width
                                    spacing: 8
                                    Repeater {
                                        model: [1, 1.25, 1.5, 1.75, 2]
                                        Chip {
                                            required property real modelData
                                            text: "×" + modelData
                                            active: details.m && Math.abs(modelData - details.m.scale) < 0.01
                                            onClicked: mon.setField(mon.sel, "scale", modelData)
                                        }
                                    }
                                }
                            }
                        }

                        Row {
                            id: monButtons
                            anchors { right: parent.right; bottom: parent.bottom }
                            spacing: 10
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: mon.status
                                font.family: root.bodyFont; font.pixelSize: 14
                                color: root.c.accent2 || "white"
                            }
                            Chip { text: "Сбросить"; enabled: mon.changed(); onClicked: mon.edit = JSON.parse(JSON.stringify(mon.list)) }
                            Chip { text: "Применить"; primary: true; enabled: mon.changed(); onClicked: mon.apply() }
                        }

                        // "Keep these settings?" with a countdown.
                        Rectangle {
                            anchors.centerIn: parent
                            visible: mon.pending
                            width: 520; height: 190
                            radius: Math.min(root.r, 16)
                            color: root.c.bg2 || "black"
                            border.width: 2
                            border.color: root.c.accent || "white"
                            Column {
                                anchors.centerIn: parent
                                spacing: 18
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "Оставить эти настройки?"
                                    font.family: root.titleFont; font.pixelSize: 24
                                    color: root.c.fg || "white"
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "Вернётся как было через " + mon.countdown + " с"
                                    font.family: root.bodyFont; font.pixelSize: 15
                                    color: root.c.muted || "grey"
                                }
                                Row {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    spacing: 12
                                    Chip { text: "Вернуть"; onClicked: mon.revert() }
                                    Chip { text: "Оставить"; primary: true; onClicked: mon.keep() }
                                }
                            }
                        }
                    }

                    // ---------------- Клавиши ----------------
                    Item {
                        anchors.fill: parent
                        visible: root.page === "keys"

                        Row {
                            id: modRow
                            spacing: 10
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Главная клавиша:"
                                font.family: root.bodyFont; font.pixelSize: 15
                                color: root.c.fg || "white"
                            }
                            Chip { text: "Alt"; active: keys.mainMod === "ALT"; onClicked: keys.setMainMod("ALT") }
                            Chip { text: "Super (Win)"; active: keys.mainMod === "SUPER"; onClicked: keys.setMainMod("SUPER") }
                        }

                        Flickable {
                            anchors { left: parent.left; right: parent.right; top: modRow.bottom; topMargin: 18; bottom: keyButtons.top; bottomMargin: 12 }
                            contentHeight: keyList.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            Column {
                                id: keyList
                                width: parent.width
                                spacing: 6

                                Repeater {
                                    // Same order as the help panel.
                                    model: [...new Set(keys.binds.map(b => b.group))].sort((p, q) => {
                                        const o = ["Приложения", "Окна", "Воркспейсы", "Скриншоты", "Оформление", "Система"];
                                        return (o.indexOf(p) + 1 || 99) - (o.indexOf(q) + 1 || 99);
                                    })
                                    Column {
                                        id: grp
                                        required property string modelData
                                        width: keyList.width
                                        spacing: 6
                                        SectionTitle { text: grp.modelData }
                                        Repeater {
                                            model: keys.binds.filter(b => b.group === grp.modelData)
                                            BindRow {
                                                required property var modelData
                                                width: grp.width
                                                title: modelData.text
                                                combo: modelData.current
                                                isDefault: modelData.current === modelData.default
                                                capturing: keys.capturing === modelData.id
                                                onEdit: keys.startCapture(modelData.id)
                                                onToggle: keys.setCurrent(modelData.id, modelData.current ? "" : modelData.default)
                                                onReset: keys.setCurrent(modelData.id, modelData.default)
                                            }
                                        }
                                    }
                                }

                                SectionTitle { text: "Свои сочетания" }
                                Repeater {
                                    model: keys.custom
                                    BindRow {
                                        required property var modelData
                                        required property int index
                                        width: keyList.width
                                        title: (modelData.name || modelData.cmd) + "  —  " + modelData.cmd
                                        combo: modelData.keys
                                        isDefault: true
                                        removable: true
                                        onRemove: { keys.custom = keys.custom.filter((u, i) => i !== index); keys.dirty = true; }
                                    }
                                }

                                // New custom bind: name, command, keys.
                                Row {
                                    id: customForm
                                    property string combo: ""
                                    spacing: 10
                                    Field { id: cName; width: 200; placeholder: "Название" }
                                    Field { id: cCmd; width: 340; placeholder: "Команда, например: gimp" }
                                    Chip {
                                        text: keys.capturing === "custom" ? "Нажми сочетание…" : (customForm.combo ? keys.label(customForm.combo) : "Сочетание")
                                        active: keys.capturing === "custom"
                                        onClicked: keys.startCapture("custom")
                                    }
                                    Chip {
                                        text: "Добавить"
                                        primary: true
                                        enabled: customForm.combo !== "" && cCmd.text.trim() !== ""
                                        onClicked: {
                                            keys.custom = keys.custom.concat([{ keys: customForm.combo, cmd: cCmd.text.trim(),
                                                                                 name: cName.text.trim() || cCmd.text.trim() }]);
                                            customForm.combo = ""; cName.text = ""; cCmd.text = "";
                                            keys.dirty = true;
                                        }
                                    }
                                }
                            }
                        }

                        Row {
                            id: keyButtons
                            anchors { right: parent.right; bottom: parent.bottom }
                            spacing: 10
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: keys.conflict ? "Уже занято: " + keys.conflict : keys.status
                                font.family: root.bodyFont; font.pixelSize: 14
                                color: keys.conflict ? (root.c.warn || "orange") : (root.c.accent2 || "white")
                            }
                            Chip {
                                visible: keys.pendingId !== ""
                                text: "Всё равно назначить"
                                onClicked: { keys.setCurrent(keys.pendingId, keys.captured); keys.pendingId = ""; keys.conflict = ""; }
                            }
                            Chip { text: "Сохранить"; primary: true; enabled: keys.dirty; onClicked: keys.save() }
                        }
                    }

                    // ---------------- Тема ----------------
                    Flow {
                        anchors.fill: parent
                        visible: root.page === "theme"
                        spacing: 16
                        Repeater {
                            model: root.themes
                            Rectangle {
                                id: tcard
                                required property var modelData
                                readonly property bool current: root.themeDir.endsWith("/" + modelData.name)
                                width: 280; height: 230
                                radius: Math.min(root.r, 14)
                                color: modelData.colors.bg
                                border.width: tma.containsMouse || current ? 2 : 1
                                border.color: modelData.colors.accent
                                clip: true
                                Image {
                                    // Wallpaper thumbnails cached by the theme picker.
                                    x: 8; y: 8; width: parent.width - 16; height: 140
                                    source: "file://" + root.home + "/.cache/theme-thumbs/" + tcard.modelData.name + ".jpg"
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                }
                                Text {
                                    visible: tcard.current
                                    anchors { right: parent.right; rightMargin: 14; bottom: parent.bottom; bottomMargin: 16 }
                                    text: "сейчас"
                                    font.family: root.bodyFont; font.pixelSize: 13
                                    color: tcard.modelData.colors.accent
                                }
                                Column {
                                    x: 18; y: 160
                                    spacing: 10
                                    Text {
                                        text: tcard.modelData.label
                                        font.family: root.titleFont; font.pixelSize: 22
                                        color: tcard.modelData.colors.fg
                                    }
                                    Row {
                                        spacing: 6
                                        Repeater {
                                            model: [tcard.modelData.colors.accent, tcard.modelData.colors.accent2, tcard.modelData.colors.fg]
                                            Rectangle { required property string modelData; width: 22; height: 22; radius: 11; color: modelData }
                                        }
                                    }
                                }
                                MouseArea {
                                    id: tma
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: { Quickshell.execDetached(["changetheme", tcard.modelData.name]); root.close(); }
                                }
                            }
                        }
                    }
                }

                // Shown while a combo is being recorded.
                Rectangle {
                    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 70 }
                    visible: keys.capturing !== ""
                    width: capText.implicitWidth + 48; height: 52
                    radius: 26
                    color: root.c.bg2 || "black"
                    border.width: 2
                    border.color: root.c.accent || "white"
                    Text {
                        id: capText
                        anchors.centerIn: parent
                        text: "Нажми новое сочетание · Esc — отмена"
                        font.family: root.bodyFont; font.pixelSize: 16
                        color: root.c.fg || "white"
                    }
                }
            }
        }
    }

    // ================= small components =================

    component TabButton: Rectangle {
        id: tb
        property string text
        property bool active
        signal clicked()
        width: tbText.implicitWidth + 30; height: 36
        radius: root.r > 4 ? 18 : 0
        color: active ? root.a(root.c.accent, 0.25) : (tbm.containsMouse ? root.a(root.c.accent, 0.1) : "transparent")
        border.color: active ? (root.c.accent || "white") : root.a(root.c.muted, 0.3)
        Text {
            id: tbText
            anchors.centerIn: parent
            text: tb.text
            font.family: root.bodyFont; font.pixelSize: 15; font.bold: tb.active
            color: tb.active ? (root.c.accent || "white") : (root.c.fg || "white")
        }
        MouseArea { id: tbm; anchors.fill: parent; hoverEnabled: true; onClicked: tb.clicked() }
    }

    component Chip: Rectangle {
        id: ch
        property string text
        property bool active
        property bool primary
        signal clicked()
        opacity: enabled ? 1 : 0.4
        width: chText.implicitWidth + 26; height: 34
        radius: root.r > 4 ? 9 : 0
        color: primary ? (root.c.accent || "white") : active ? root.a(root.c.accent, 0.28)
               : (chm.containsMouse ? root.a(root.c.accent, 0.12) : root.a(root.c.bg2, 0.9))
        border.color: active || primary ? (root.c.accent || "white") : root.a(root.c.muted, 0.35)
        Text {
            id: chText
            anchors.centerIn: parent
            text: ch.text
            font.family: root.bodyFont; font.pixelSize: 14; font.bold: ch.active || ch.primary
            color: ch.primary ? (root.c.bg || "black") : ch.active ? (root.c.accent || "white") : (root.c.fg || "white")
        }
        MouseArea { id: chm; anchors.fill: parent; hoverEnabled: true; enabled: ch.enabled; onClicked: ch.clicked() }
    }

    component SectionTitle: Text {
        font.family: root.titleFont; font.pixelSize: 17; font.bold: true; font.italic: !!root.ui.italicTitle
        color: root.c.accent2 || root.c.accent || "white"
        topPadding: 6
    }

    component Field: Rectangle {
        id: fld
        property alias text: input.text
        property string placeholder
        height: 34
        radius: root.r > 4 ? 9 : 0
        color: root.a(root.c.bg2, 0.9)
        border.color: input.activeFocus ? (root.c.accent || "white") : root.a(root.c.muted, 0.35)
        TextInput {
            id: input
            anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
            verticalAlignment: TextInput.AlignVCenter
            font.family: root.bodyFont; font.pixelSize: 14
            color: root.c.fg || "white"
            selectionColor: root.a(root.c.accent, 0.4)
            clip: true
            Keys.onEscapePressed: scene.forceActiveFocus()
        }
        Text {
            anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
            visible: !input.text && !input.activeFocus
            text: fld.placeholder
            font.family: root.bodyFont; font.pixelSize: 14
            color: root.c.muted || "grey"
        }
        MouseArea { anchors.fill: parent; onClicked: input.forceActiveFocus() }
    }

    component BindRow: Rectangle {
        id: row
        property string title
        property string combo
        property bool isDefault
        property bool capturing
        property bool removable
        signal edit()
        signal toggle()
        signal reset()
        signal remove()
        height: 44
        radius: root.r > 4 ? 10 : 0
        color: capturing ? root.a(root.c.accent, 0.15) : root.a(root.c.bg2, 0.6)
        border.color: capturing ? (root.c.accent || "white") : "transparent"
        Text {
            anchors { left: parent.left; leftMargin: 14; right: rowButtons.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
            text: row.title
            elide: Text.ElideRight
            font.family: root.bodyFont; font.pixelSize: 14
            color: row.combo ? (root.c.fg || "white") : (root.c.muted || "grey")
        }
        Row {
            id: rowButtons
            anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
            spacing: 8
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(110, comboText.implicitWidth + 20); height: 28
                radius: root.r > 4 ? 7 : 0
                color: root.a(root.c.accent, row.combo ? 0.16 : 0.05)
                border.color: root.a(root.c.accent, row.isDefault ? 0.45 : 0.9)
                Text {
                    id: comboText
                    anchors.centerIn: parent
                    text: row.capturing ? "…" : keys.label(row.combo)
                    font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 13
                    color: row.combo ? (root.c.accent || "white") : (root.c.muted || "grey")
                }
            }
            Chip { visible: !row.removable; text: "Изменить"; onClicked: row.edit() }
            Chip { visible: !row.removable; text: row.combo ? "Выкл" : "Вкл"; onClicked: row.toggle() }
            Chip { visible: !row.removable && !row.isDefault; text: "Сброс"; onClicked: row.reset() }
            Chip { visible: row.removable; text: "Удалить"; onClicked: row.remove() }
        }
    }
}
