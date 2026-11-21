import QtQuick
import Quickshell
import Quickshell.Io
import "../common/keys.js" as KeyName

// The hotkeys the window edits: the binds keybind.lua registers ($XDG_RUNTIME_DIR/hypr-binds-registry.json), the
// main modifier, the user's own binds and keys for programs' global shortcuts; saved to
// ~/.config/hypr/binds-user.lua. A combo is recorded from the keyboard (or a mouse button) while Hyprland's
// passthrough submap lets every key reach the window.
Scope {
    id: keys

    readonly property string registryPath: Quickshell.env("XDG_RUNTIME_DIR") + "/hypr-binds-registry.json"
    property string mainMod: "ALT"
    property var binds: []      // {id, default, current, description, group, text}
    property var custom: []     // {keys, cmd, name}
    property var others: []     // hyprctl binds that are not editable here (for conflicts)
    // Shortcuts programs registered with Hyprland (Discord's push to talk, ...): which are there now
    // (hyprctl globalshortcuts) and the keys picked for them (binds-user.lua "globals").
    property var programShortcuts: []  // [{name, description}]
    property var globalKeys: ({})       // name → combo
    property string capturing: ""   // bind id, "global:<name>", "custom" or ""
    property string captured: ""
    property string customCombo: ""  // the combo recorded for the new own bind
    property string conflict: ""
    property string pendingId: ""   // a combo that conflicts, waiting for "assign anyway"
    property bool dirty: false
    property string status: ""

    // The window takes the keyboard back for the capture.
    signal captureStarted()

    function load(text) {
        let registry = {};
        try {
            registry = JSON.parse(text);
        } catch (e) {
            return;
        }
        mainMod = registry.mainMod || "ALT";
        binds = (registry.binds || []).map(b => {
            const parts = (b.description || "").split("|").map(s => s.trim());
            return Object.assign({}, b, { group: parts[0] || "Прочее", text: parts[1] || b.id });
        });
        custom = registry.custom || [];
        const picked = {};
        for (const g of registry.globals || []) {
            picked[g.name] = g.keys;
        }
        globalKeys = picked;
        dirty = false;
    }

    // A row per program shortcut: those registered now, and those with a key whose program is not running.
    function globalRows() {
        const rows = programShortcuts.map(g => ({ name: g.name, description: g.description || g.name,
                                                  keys: globalKeys[g.name] || "" }));
        for (const name of Object.keys(globalKeys)) {
            if (!rows.some(r => r.name === name)) {
                rows.push({ name: name, description: name + " (программа не запущена)", keys: globalKeys[name] });
            }
        }
        return rows;
    }

    function setGlobal(name, combo) {
        const next = Object.assign({}, globalKeys);
        if (combo) {
            next[name] = combo;
        } else {
            delete next[name];
        }
        globalKeys = next;
        dirty = true;
    }

    // A combo for a bind id, or for "global:<name>".
    function assign(target, combo) {
        if (target.startsWith("global:")) {
            setGlobal(target.slice(7), combo);
        } else {
            setCurrent(target, combo);
        }
    }

    function assignAnyway() {
        assign(pendingId, captured);
        pendingId = "";
        conflict = "";
    }

    function addCustom(combo, command, name) {
        custom = custom.concat([{ keys: combo, cmd: command, name: name || command }]);
        customCombo = "";
        dirty = true;
    }

    function removeCustom(index) {
        custom = custom.filter((u, i) => i !== index);
        dirty = true;
    }

    // "SUPER + SHIFT + G" <-> modmask + key, the way `hyprctl binds` reports them.
    function parseCombo(s) {
        const parts = s.split("+").map(x => x.trim()).filter(x => x);
        const bits = { SHIFT: 1, CTRL: 4, CONTROL: 4, ALT: 8, SUPER: 64, WIN: 64, MOD4: 64 };
        let mask = 0, key = "";
        for (const part of parts) {
            const upper = part.toUpperCase();
            if (bits[upper] !== undefined) {
                mask |= bits[upper];
            } else {
                key = part;
            }
        }
        return { mask: mask, key: key.toLowerCase() };
    }

    function label(s) {
        if (!s) {
            return "выключено";
        }
        const names = { "return": "Enter", "print": "PrtSc", "space": "Space", "tab": "Tab",
                        "left": "←", "right": "→", "up": "↑", "down": "↓", "prior": "PgUp", "next": "PgDn",
                        "mouse:274": "Колёсико", "mouse:275": "Мышь «назад»", "mouse:276": "Мышь «вперёд»" };
        const modifiers = { SUPER: "Super", ALT: "Alt", CTRL: "Ctrl", CONTROL: "Ctrl", SHIFT: "Shift" };
        return s.split("+").map(x => x.trim())
            .map(x => modifiers[x.toUpperCase()] || names[x.toLowerCase()] || (x.length === 1 ? x.toUpperCase() : x))
            .join("+");
    }

    // What already has the combo (its name), or "".
    function conflicts(combo, exceptId) {
        const wanted = parseCombo(combo);
        const same = s => {
            const other = parseCombo(s);
            return other.mask === wanted.mask && other.key === wanted.key;
        };
        for (const b of binds) {
            if (b.id !== exceptId && b.current && same(b.current)) return b.text;
        }
        for (const u of custom) {
            if (exceptId !== "custom:" + u.keys && same(u.keys)) return u.name || u.cmd;
        }
        for (const name of Object.keys(globalKeys)) {
            if (exceptId !== "global:" + name && same(globalKeys[name])) return name;
        }
        for (const o of others) {
            if (o.mask === wanted.mask && o.key === wanted.key) return o.text;
        }
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
        // Hyprland handles its own binds before any window sees the keys; in the passthrough submap everything
        // reaches us. Until the capture ends, every bind is off: the guard and the timeout below make sure it does.
        Quickshell.execDetached(["hyprctl", "dispatch", 'hl.dsp.submap("passthrough")']);
        captureGuard.running = true;
        captureTimeout.restart();
        captureStarted();
    }

    function stopCapture() {
        capturing = "";
        captureGuard.running = false;
        captureTimeout.stop();
        Quickshell.execDetached(["hyprctl", "dispatch", 'hl.dsp.submap("reset")']);
    }

    // Letters and digits by their place on the keyboard, so a Russian layout still gives "R".
    function keyName(e) {
        const placed = KeyName.of(e);
        if (placed) {
            return placed;
        }
        if (e.key >= Qt.Key_F1 && e.key <= Qt.Key_F24) {
            return "F" + (e.key - Qt.Key_F1 + 1);
        }
        const named = {};
        named[Qt.Key_Return] = "Return"; named[Qt.Key_Enter] = "KP_Enter"; named[Qt.Key_Space] = "space";
        named[Qt.Key_Tab] = "Tab"; named[Qt.Key_Backspace] = "BackSpace"; named[Qt.Key_Delete] = "Delete";
        named[Qt.Key_Insert] = "Insert"; named[Qt.Key_Home] = "Home"; named[Qt.Key_End] = "End";
        named[Qt.Key_PageUp] = "Prior"; named[Qt.Key_PageDown] = "Next"; named[Qt.Key_Left] = "left";
        named[Qt.Key_Right] = "right"; named[Qt.Key_Up] = "up"; named[Qt.Key_Down] = "down";
        named[Qt.Key_Print] = "Print";
        return named[e.key] || "";
    }

    function modifierNames(modifiers) {
        const parts = [];
        if (modifiers & Qt.MetaModifier) parts.push("SUPER");
        if (modifiers & Qt.ControlModifier) parts.push("CTRL");
        if (modifiers & Qt.AltModifier) parts.push("ALT");
        if (modifiers & Qt.ShiftModifier) parts.push("SHIFT");
        return parts;
    }

    // A key during a capture (Esc is the window's back(), which stops the capture).
    function onKey(e) {
        const modifierKeys = [Qt.Key_Shift, Qt.Key_Control, Qt.Key_Alt, Qt.Key_Meta, Qt.Key_Super_L,
                              Qt.Key_Super_R, Qt.Key_AltGr, Qt.Key_Hyper_L, Qt.Key_Hyper_R];
        if (modifierKeys.indexOf(e.key) !== -1) {
            return;
        }
        const name = keyName(e);
        if (!name) {
            status = "Эту клавишу назначить нельзя";
            return;
        }
        finishCapture(modifierNames(e.modifiers).concat([name]).join(" + "));
    }

    // A mouse button (the wheel, the side ones) as a key; left and right stay for the window.
    readonly property var mouseButtons: ({ [Qt.MiddleButton]: "mouse:274", [Qt.BackButton]: "mouse:275",
                                           [Qt.ForwardButton]: "mouse:276" })
    function onMouse(button, modifiers) {
        finishCapture(modifierNames(modifiers).concat([mouseButtons[button]]).join(" + "));
    }

    function finishCapture(combo) {
        captured = combo;
        const target = capturing;
        stopCapture();
        conflict = conflicts(captured, target);
        if (target === "custom") {
            customCombo = captured;
            return;
        }
        pendingId = target;
        if (!conflict) {
            assign(target, captured);
            pendingId = "";
        }
    }

    function save() {
        const q = s => JSON.stringify(String(s));
        const lines = ["-- Written by the settings panel (Alt+F2): your hotkey changes. Defaults are in keybind.lua.",
                       "return {"];
        if (mainMod !== "ALT") {
            lines.push(`    mainMod = ${q(mainMod)},`);
        }
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
        const programs = Object.keys(globalKeys);
        if (programs.length) {
            lines.push("    globals = {");
            for (const name of programs) lines.push(`        [${q(name)}] = ${q(globalKeys[name])},`);
            lines.push("    },");
        }
        lines.push("}");
        Files.write(Files.home + "/.config/hypr/binds-user.lua", lines.join("\n") + "\n", "hyprctl reload");
        status = "Сохранено, горячие клавиши обновлены";
        dirty = false;
        reloadTimer.restart();
    }

    function setMainMod(m) {
        if (m === mainMod) {
            return;
        }
        // Defaults follow the main key: binds still on their default move along.
        const from = mainMod;
        const moved = s => s.replace(new RegExp("^" + from + "( \\+ )"), m + "$1");
        binds = binds.map(b => Object.assign({}, b, { default: moved(b.default),
                                                      current: b.current === b.default ? moved(b.default) : b.current }));
        mainMod = m;
        dirty = true;
    }

    function read() {
        bindsProc.running = true;
        globalsProc.running = true;
    }

    Component.onCompleted: read()
    Component.onDestruction: if (capturing !== "") stopCapture()

    FileView { id: registryFile; path: keys.registryPath; blockLoading: true }

    // Binds come back if the shell dies during a capture (a crash, kill -9): the guard's stdin is a pipe from the
    // shell and closes only when the shell's process is gone. stopCapture stops the guard first, so a capture
    // that ends normally leaves the submap to it.
    Process {
        id: captureGuard
        stdinEnabled: true
        command: ["sh", "-c", 'read -r _; [ "$(hyprctl submap)" = passthrough ] && hyprctl dispatch \'hl.dsp.submap("reset")\'']
    }
    // A capture nobody finishes (the window lost the keyboard, the user walked away).
    Timer {
        id: captureTimeout
        interval: 15000
        onTriggered: {
            keys.stopCapture();
            keys.status = "Время вышло, клавиша не назначена";
        }
    }
    Process {
        id: bindsProc
        command: ["hyprctl", "binds", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                registryFile.reload();
                keys.load(registryFile.text());
                let all = [];
                try {
                    all = JSON.parse(this.text);
                } catch (e) {}
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
    Process {
        id: globalsProc
        command: ["hyprctl", "globalshortcuts", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    keys.programShortcuts = JSON.parse(this.text) || [];
                } catch (e) {
                    keys.programShortcuts = [];
                }
            }
        }
    }
    Timer { id: reloadTimer; interval: 900; onTriggered: keys.read() }
}
