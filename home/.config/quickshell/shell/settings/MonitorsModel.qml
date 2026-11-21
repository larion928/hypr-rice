import QtQuick
import Quickshell
import Quickshell.Io

// The monitors as Hyprland has them and as the window edits them. «Применить» applies the edit live and starts a
// 15 s countdown back to the old setup; «Оставить» writes ~/.config/hypr/monitors.lua.
Scope {
    id: mon

    readonly property string path: Files.home + "/.config/hypr/monitors.lua"
    property var list: []        // as Hyprland has them now
    property var edit: []        // what the window shows and changes
    property int sel: 0
    property bool pending: false // applied live, waiting for "keep"
    property int countdown: 0
    property string status: ""

    function parse(text) {
        let raw = [];
        try {
            raw = JSON.parse(text);
        } catch (e) {
            return;
        }
        const out = raw.map(m => {
            const modes = (m.availableModes || []).map(s => {
                const found = /^(\d+)x(\d+)@([\d.]+)Hz$/.exec(s);
                return found ? { w: +found[1], h: +found[2], rate: +found[3] } : null;
            }).filter(x => x);
            if (!modes.find(x => x.w === m.width && x.h === m.height)) {
                modes.push({ w: m.width, h: m.height, rate: m.refreshRate });
            }
            return { name: m.name, desc: m.description || "", w: m.width, h: m.height,
                     rate: m.refreshRate, x: m.x, y: m.y, scale: m.scale, disabled: !!m.disabled, modes: modes,
                     rotated: m.transform % 2 === 1 };
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
            e[i].w = w;
            e[i].h = h;
            e[i].rate = Math.max(...e[i].modes.filter(m => m.w === w && m.h === h).map(m => m.rate));
            delete e[i].res;
        }
        edit = e;
    }

    function resetEdit() {
        edit = JSON.parse(JSON.stringify(list));
    }

    function changed() {
        return JSON.stringify(edit) !== JSON.stringify(list);
    }

    // Logical size: a monitor turned by 90 or 270 degrees has its width and height swapped.
    function lw(m) {
        return Math.round((m.rotated ? m.h : m.w) / m.scale);
    }
    function lh(m) {
        return Math.round((m.rotated ? m.w : m.h) / m.scale);
    }

    // A monitor dropped at logical (x, y): snap to the other screens' edges, then keep the layout's top-left corner
    // at 0x0.
    function drop(i, x, y) {
        const e = JSON.parse(JSON.stringify(edit));
        const me = e[i];
        let bx = x, by = y, dx = 1e9, dy = 1e9;
        for (let j = 0; j < e.length; j++) {
            if (j === i || e[j].disabled) {
                continue;
            }
            const o = e[j];
            for (const cx of [o.x + lw(o), o.x - lw(me), o.x, o.x + lw(o) - lw(me)]) {
                if (Math.abs(cx - x) < dx) {
                    dx = Math.abs(cx - x);
                    bx = cx;
                }
            }
            for (const cy of [o.y + lh(o), o.y - lh(me), o.y, o.y + lh(o) - lh(me)]) {
                if (Math.abs(cy - y) < dy) {
                    dy = Math.abs(cy - y);
                    by = cy;
                }
            }
        }
        me.x = dx < 160 ? bx : Math.round(x);
        me.y = dy < 160 ? by : Math.round(y);
        const on = e.filter(m => !m.disabled);
        const minX = Math.min(...on.map(m => m.x));
        const minY = Math.min(...on.map(m => m.y));
        for (const m of e) {
            m.x -= minX;
            m.y -= minY;
        }
        edit = e;
    }

    // The window sets these fields of hl.monitor; whatever else monitors.lua has for an output (transform, mirror,
    // vrr, bitdepth, ...) is the user's and is written back as it is.
    readonly property var ownFields: ["output", "mode", "position", "scale", "disabled"]

    function spec(m, kept) {
        const extra = (kept[m.name] || []).map(field => ", " + field).join("");
        if (m.disabled) {
            return `hl.monitor({ output = "${m.name}", disabled = true${extra} })`;
        }
        const rate = (+m.rate).toFixed(2).replace(/\.?0+$/, "");
        return `hl.monitor({ output = "${m.name}", mode = "${m.w}x${m.h}@${rate}", position = "${m.x}x${m.y}", scale = ${m.scale}${extra} })`;
    }

    // output name -> the fields of its hl.monitor in monitors.lua that the window does not set, as Lua text
    // ("transform = 1").
    function keptFields(text) {
        const kept = {};
        for (const call of monitorCalls(text)) {
            const output = call.fields.map(f => /^output\s*=\s*["'](.*)["']$/.exec(f)).find(found => found);
            if (output) {
                kept[output[1]] = call.fields.filter(f => !ownFields.includes((/^(\w+)\s*=/.exec(f) || [])[1]));
            }
        }
        return kept;
    }

    // Every hl.monitor({...}) in Lua text: where it starts and ends, and its fields split at the top-level commas
    // (strings, nested tables and comments do not split them).
    function monitorCalls(text) {
        const calls = [];
        const opener = /hl\.monitor\(\{/g;
        let found;
        while ((found = opener.exec(text))) {
            const fields = [];
            let field = "", depth = 1, quote = "", i = opener.lastIndex;
            for (; i < text.length; i++) {
                const ch = text[i];
                if (quote) {
                    if (ch === "\\") {
                        field += text[i++];
                    } else if (ch === quote) {
                        quote = "";
                    }
                } else if (ch === "-" && text[i + 1] === "-") {
                    i = text.indexOf("\n", i);
                    if (i === -1) {
                        i = text.length;
                    }
                    continue;
                } else if (ch === '"' || ch === "'") {
                    quote = ch;
                } else if (ch === "{") {
                    depth++;
                } else if (ch === "}" && --depth === 0) {
                    break;
                } else if (ch === "," && depth === 1) {
                    fields.push(field.trim());
                    field = "";
                    continue;
                }
                field += text[i] || "";
            }
            fields.push(field.trim());
            const close = text.indexOf(")", i);
            const end = close === -1 ? text.length : close + 1;
            calls.push({ start: found.index, end: end, fields: fields.filter(f => f) });
            opener.lastIndex = end;
        }
        return calls;
    }

    function apply() {
        if (edit.filter(m => !m.disabled).length === 0) {
            status = "Хотя бы один экран должен остаться включённым";
            return;
        }
        const kept = keptFields(monFile.text());
        Quickshell.execDetached(["hyprctl", "eval", edit.map(m => spec(m, kept)).join("\n")]);
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
        // Our monitor lines replace any hl.monitor(...) in the file; the rest (workspace rules and the like) stays.
        let rest = oldText || "";
        for (const call of monitorCalls(rest).reverse()) {
            const lineEnd = /^[ \t]*\n?/.exec(rest.slice(call.end))[0].length;
            rest = rest.slice(0, call.start) + rest.slice(call.end + lineEnd);
        }
        rest = rest.replace(/^-- Monitors written by the settings panel.*\n/gm, "").replace(/^\s*\n/, "");
        const kept = keptFields(oldText || "");
        const head = "-- Monitors written by the settings panel (Alt+F2); other lines below are kept.\n"
            + 'hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })\n'
            + edit.map(m => spec(m, kept)).join("\n") + "\n";
        Files.write(path, head + (rest ? "\n" + rest : ""), "");
        list = JSON.parse(JSON.stringify(edit));
        status = "Сохранено в monitors.lua";
    }

    Component.onCompleted: monProc.running = true

    Process {
        id: monProc
        command: ["hyprctl", "monitors", "all", "-j"]
        stdout: StdioCollector { onStreamFinished: mon.parse(this.text) }
    }
    FileView { id: monFile; path: mon.path; blockLoading: true }
    Timer { id: saveTimer; interval: 150; onTriggered: mon.save(monFile.text()) }
    Timer { id: refreshTimer; interval: 1200; onTriggered: monProc.running = true }
    Timer {
        id: countdownTimer
        interval: 1000
        repeat: true
        onTriggered: {
            mon.countdown -= 1;
            if (mon.countdown <= 0) {
                mon.revert();
            }
        }
    }
}
