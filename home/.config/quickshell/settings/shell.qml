// Settings window, toggled by ~/.local/bin/settings-panel (Alt+F2, waybar gear, launcher).
//   Мониторы  — layout by dragging, resolution, refresh rate, scale, on/off. Applied live with a
//               15 s "keep?" countdown; kept settings go to ~/.config/hypr/monitors.lua.
//   Клавиши   — the editable binds keybind.lua registers ($XDG_RUNTIME_DIR/hypr-binds-registry.json),
//               the main modifier and the user's own binds; saved to ~/.config/hypr/binds-user.lua.
//   Тема      — the themes from $RICE_THEME_LIST (written by ../theme-list.py); a card opens that theme's
//               settings: fonts, colours, wallpapers (~/.config/hypr-rice/theme-edits.json, read by
//               themegen) and a button to switch to it. Quick switching is the theme picker's (Alt+Shift+T).
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import "common"
import "common/color.js" as Color

ShellRoot {
    id: root

    Theme { id: theme }

    readonly property string home: Quickshell.env("HOME")
    readonly property string registryPath: Quickshell.env("XDG_RUNTIME_DIR") + "/hypr-binds-registry.json"
    property var themes: []
    property bool closing: false
    property bool picking: false  // a file dialog is open: the window steps aside, it holds the keyboard
    // $SETTINGS_PAGE: monitors, keys, theme, or theme:<name>[:<section>] for one theme's settings.
    readonly property var startAt: (Quickshell.env("SETTINGS_PAGE") || "monitors").split(":")
    property string page: startAt[0]
    readonly property int r: Math.min(theme.ui.radius ?? 14, 22)

    FileView { id: themeListFile; path: Quickshell.env("RICE_THEME_LIST"); blockLoading: true }

    Component.onCompleted: {
        try { themes = JSON.parse(themeListFile.text()); } catch (e) {}
        const opened = themes.find(t => t.name === startAt[1]);
        if (opened) {
            themeEdit.open(opened);
            if (startAt[2]) themeEdit.section = startAt[2];
        }
        monProc.running = true;
        bindsProc.running = true;
    }

    function close() {
        if (closing) return;
        closing = true;
        if (keys.capturing !== "") keys.stopCapture();
        if (mon.pending) mon.revert();
        outAnim.start();
    }

    // Writes a file, then optionally runs a command (all detached, in that order).
    // Esc: out of the icon picker, then out of a theme's settings, then the window closes.
    function back() {
        if (userFiles.frameSource) {
            userFiles.closeFrames();
            return;
        }
        if (ownThemes.dialog) {
            if (!ownThemes.busy) ownThemes.dialog = "";
            return;
        }
        if (themeEdit.installing && themeEdit.installState !== "checking") themeEdit.installing = null;
        else if (themeEdit.installing) return;
        else if (themeEdit.iconFor) themeEdit.iconFor = "";
        else if (themeEdit.editing) themeEdit.editing = null;
        else root.close();
    }

    // text as one word for sh -c.
    function quote(text) {
        return "'" + String(text).replace(/'/g, "'\\''") + "'";
    }

    function writeFile(path, text, after) {
        Quickshell.execDetached(["sh", "-c", 'printf "%s" "$1" > "$2" && [ -z "$3" ] || sh -c "$3"',
                                 "sh", text, path, after || ""]);
    }

    IpcHandler {
        target: "panel"
        function close(): void { root.close(); }
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

    // ================= one theme's edits =================

    // What the user changes in a theme (fonts, colours, wallpapers), edited one theme at a time and
    // kept in ~/.config/hypr-rice/theme-edits.json, which themegen reads on every theme change.
    // An empty font or a missing colour keeps the theme's own.
    QtObject {
        id: themeEdit
        readonly property string path: root.home + "/.config/hypr-rice/theme-edits.json"
        readonly property string wallpaperDir: root.home + "/.local/share/hypr-rice/wallpapers"
        readonly property var sections: [["fonts", "Шрифты"], ["colors", "Цвета"], ["wallpapers", "Обои"],
                                         ["waybar", "Панель"], ["icons", "Значки"], ["cursor", "Курсор"],
                                         ["windows", "Окна"]]
        // The window settings the «Окна» section offers: key, what it is, range, step, and how it reads.
        readonly property var windowSettings: [
            ["gaps_in", "Отступ между окнами", 0, 30, 1, "px"], ["gaps_out", "Отступ от краёв экрана", 0, 40, 1, "px"],
            ["border_size", "Толщина рамки", 0, 8, 1, "px"], ["rounding", "Скругление углов", 0, 30, 1, "px"],
            ["active_opacity", "Непрозрачность активного окна", 0.5, 1, 0.05, "%"],
            ["inactive_opacity", "Непрозрачность остальных окон", 0.5, 1, 0.05, "%"],
            ["blur_size", "Сила размытия", 1, 16, 1, ""]
        ]
        // papirus-folders' colours; each has its folder icon in Papirus.
        readonly property var folderColors: ["adwaita", "black", "blue", "bluegrey", "breeze", "brown", "carmine", "cyan",
                                             "darkcyan", "deeporange", "green", "grey", "indigo", "magenta", "nordic",
                                             "orange", "palebrown", "paleorange", "pink", "red", "teal", "violet",
                                             "white", "yaru", "yellow"]
        readonly property string defaultIconTheme: "Papirus-Dark"  // what the rice ships
        readonly property var sides: [["modules-left", "Слева"], ["modules-center", "По центру"],
                                      ["modules-right", "Справа"]]
        readonly property var moduleNames: ({
            "hyprland/workspaces": "Рабочие столы", "hyprland/window": "Заголовок окна",
            "hyprland/language": "Раскладка", "pulseaudio": "Громкость", "cpu": "Процессор",
            "memory": "Память", "temperature": "Температура", "custom/power": "Режим питания",
            "custom/battery": "Батарея", "battery": "Батарея (стандартная)", "network": "Сеть",
            "custom/updates": "Обновления", "clock": "Часы", "custom/histui": "Уведомления",
            "custom/shots": "Скриншоты", "custom/settings": "Настройки", "custom/help": "Справка",
            "custom/theme": "Выбор темы", "custom/exit": "Выключение", "custom/claude": "Лимиты Claude",
            "tray": "Трей", "backlight": "Яркость", "bluetooth": "Bluetooth", "idle_inhibitor": "Не засыпать",
            "mpris": "Плеер", "disk": "Диск", "power-profiles-daemon": "Профиль питания (системный)"
        })
        readonly property var fontSlots: [["font", "Основной", "панель, терминал, моноширинный текст"],
                                          ["display", "Заголовки", "названия, часы на экране блокировки"],
                                          ["body", "Текст", "окна райса, браузеры, Discord"]]
        readonly property var colorNames: [["bg", "Фон"], ["bg2", "Фон панелей"], ["fg", "Текст"],
                                           ["muted", "Приглушённый"], ["accent", "Акцент"],
                                           ["accent2", "Акцент 2"], ["accent3", "Акцент 3"],
                                           ["good", "Хорошо"], ["warn", "Внимание"], ["crit", "Ошибка"]]
        property var everyTheme: ({})  // the whole file's "themes"
        property var everywhere: ({})  // the whole file's "everywhere": what was saved for all themes
        property var editing: null     // the card being edited, an entry of root.themes
        property var edit: ({})        // {fonts, colors, wallpapers: {added, off}}
        property string saved: ""      // edit as last saved, to see what changed
        property string section: "fonts"
        property string panelView: "layout"  // the panel section shows the bar ("layout") or its modules' icons ("icons")
        // The icon picker for one panel module; nothing changes until «Применить».
        property string iconFor: ""
        property string iconChoice: ""       // what «Применить» sets; "" is the theme's own icon
        property string iconQuery: ""
        // Installed icon themes with sample icons, and the ones to install (themegen.py icon-themes).
        property var iconThemes: ({ installed: [], downloadable: [] })
        // Installed cursor themes with pictures of a few cursors, and the ones to install (themegen.py cursor-themes).
        property var cursorThemes: ({ installed: [], downloadable: [] })
        readonly property string defaultCursor: "WhiteCat"  // what the rice ships
        readonly property var cursorSizes: [24, 32, 40, 48]
        // What each module shows on this machine now (themegen.py bar-preview): {module: {text, state, note}};
        // state is shown, sometimes or missing. Asked for when the «Панель» section opens; until it comes,
        // the modules show samples.
        property var live: ({})
        // Every icon of the Nerd Font, [[glyph, name], ...] (themegen.py icons), asked for on first use.
        property var allIcons: []
        readonly property var iconHints: ({
            "pulseaudio": "volume", "cpu": "chip", "memory": "memory", "temperature": "thermometer",
            "backlight": "brightness", "battery": "battery", "bluetooth": "bluetooth", "disk": "harddisk",
            "network": "wifi", "custom/exit": "power", "custom/help": "help", "custom/histui": "bell",
            "custom/settings": "cog", "custom/shots": "image", "custom/theme": "palette"
        })
        property string liveFor: ""
        onSectionChanged: {
            themeEdit.askLive();
            if (themeEdit.section === "icons" && !themeEdit.iconThemes.installed.length) iconThemesProc.running = true;
            if (themeEdit.section === "cursor" && !themeEdit.cursorThemes.installed.length) cursorThemesProc.running = true;
        }
        function askLive() {
            if (themeEdit.section !== "waybar" || !themeEdit.editing || themeEdit.liveFor === themeEdit.editing.name) return;
            themeEdit.live = {};
            themeEdit.liveFor = themeEdit.editing.name;
            barPreviewProc.command = ["python3", root.home + "/.config/hypr/scripts/themegen.py", "bar-preview", themeEdit.editing.name];
            barPreviewProc.running = true;
        }
        property string fontSlot: "font"
        property string colorKey: "accent"
        property var installedFonts: []
        property string fontQuery: ""
        readonly property var matchingFonts: themeEdit.installedFonts.filter(
            name => name.toLowerCase().includes(themeEdit.fontQuery.toLowerCase()))
        readonly property bool dirty: themeEdit.editing !== null && JSON.stringify(themeEdit.edit) !== themeEdit.saved

        function open(entry) {
            themeEditFile.reload();
            let file = {};
            try { file = JSON.parse(themeEditFile.text()) || {}; } catch (e) {}
            themeEdit.everyTheme = file.themes || {};
            themeEdit.everywhere = file.everywhere || {};
            const mine = themeEdit.everyTheme[entry.name] || {};
            const walls = mine.wallpapers || {};
            themeEdit.edit = { fonts: Object.assign({ font: "", display: "", body: "" }, mine.fonts || {}),
                               colors: Object.assign({}, mine.colors || {}),
                               wallpapers: { added: (walls.added || []).slice(), off: (walls.off || []).slice() },
                               waybar: mine.waybar ? JSON.parse(JSON.stringify(mine.waybar)) : null,
                               icons: Object.assign({}, mine.icons || {}),
                               folders: mine.folders || "", iconTheme: mine.iconTheme || "", battery: mine.battery || "",
                               cursor: mine.cursor || "", cursorSize: mine.cursorSize || 0,
                               windows: Object.assign({}, mine.windows || {}) };
            themeEdit.saved = JSON.stringify(themeEdit.edit);
            themeEdit.section = "fonts";
            themeEdit.fontSlot = "font";
            themeEdit.fontQuery = "";
            themeEdit.editing = entry;
            themeEdit.askLive();
            if (!themeEdit.installedFonts.length) fontsProc.running = true;
        }

        function change(part, value) {
            themeEdit.edit = Object.assign({}, themeEdit.edit, { [part]: value });
        }

        // ---- fonts
        function font(key) {
            return themeEdit.edit.fonts[key] || themeEdit.editing.own.fonts[key];
        }
        function chooseFont(name) {
            themeEdit.change("fonts", Object.assign({}, themeEdit.edit.fonts, { [themeEdit.fontSlot]: name }));
        }

        // ---- colours
        function color(key) {
            return themeEdit.edit.colors[key] || themeEdit.editing.own.colors[key];
        }
        function chooseColor(hex) {
            themeEdit.change("colors", Object.assign({}, themeEdit.edit.colors, { [themeEdit.colorKey]: hex }));
        }
        function ownColor() {
            const colors = Object.assign({}, themeEdit.edit.colors);
            delete colors[themeEdit.colorKey];
            themeEdit.change("colors", colors);
        }

        // ---- wallpapers: the theme's own, then the added ones; each one on or off
        function wallpapers() {
            const own = themeEdit.editing.wallpapers.filter(w => !w.added).map(w => w.path);
            const thumbs = {};
            for (const w of themeEdit.editing.wallpapers) thumbs[w.path] = w.thumb;
            const added = themeEdit.edit.wallpapers.added;
            return own.concat(added).map(path => ({ path: path, thumb: thumbs[path] || path,
                                                    added: added.includes(path),
                                                    on: !themeEdit.edit.wallpapers.off.includes(path) }));
        }
        function toggleWallpaper(path) {
            const off = themeEdit.edit.wallpapers.off;
            const next = off.includes(path) ? off.filter(p => p !== path) : off.concat([path]);
            themeEdit.change("wallpapers", { added: themeEdit.edit.wallpapers.added, off: next });
        }
        function removeWallpaper(path) {
            themeEdit.change("wallpapers", { added: themeEdit.edit.wallpapers.added.filter(p => p !== path),
                                             off: themeEdit.edit.wallpapers.off.filter(p => p !== path) });
        }
        function addWallpaper(path) {
            if (!path || themeEdit.edit.wallpapers.added.includes(path)) return;
            themeEdit.change("wallpapers", { added: themeEdit.edit.wallpapers.added.concat([path]),
                                             off: themeEdit.edit.wallpapers.off });
        }
        function pickWallpaper() {
            root.picking = true;
            wallpaperPicker.command = ["sh", "-c",
                'f=$(zenity --file-selection --title="Обои для темы" --file-filter="Картинки и GIF | *.png *.jpg *.jpeg *.webp *.gif") '
                + '&& mkdir -p "$1" && cp "$f" "$1/" && printf "%s" "$1/$(basename "$f")"',
                "sh", themeEdit.wallpaperDir + "/" + themeEdit.editing.name];
            wallpaperPicker.running = true;
        }
        // The current theme only: the edits are saved (a just-added wallpaper has to be in the list
        // changetheme picks from), the picture is shown, and the theme applied again with it, so the
        // lock screen, login screen and browsers get it too.
        function showWallpaper(path) {
            themeEdit.write("printf '%s\\n' " + root.quote(path) + " > " + root.quote(root.home + "/.config/hypr/current-wallpaper")
                            + " && awww img " + root.quote(path)
                            + " && changetheme --keep-wallpaper " + themeEdit.editing.name);
        }

        // ---- panel: this theme's own waybar layout, or null to follow the one saved for every theme
        function panel() {
            return themeEdit.edit.waybar || themeEdit.editing.waybar.withoutOwn;
        }
        function panelCopy() {
            return JSON.parse(JSON.stringify(themeEdit.panel()));
        }
        function onPanel(module) {
            return themeEdit.sides.some(([side]) => (themeEdit.panel()[side] || []).includes(module));
        }
        function moduleName(module) {
            return themeEdit.moduleNames[module] || module;
        }
        function preview(module) {
            const now = themeEdit.live[module];
            const text = (now && now.text) || (themeEdit.editing && themeEdit.editing.waybar.preview[module]) || "";
            return themeEdit.withIcon(module, text) || themeEdit.moduleName(module);
        }
        // text with the icon picked for module in front, in place of the one it starts with.
        function withIcon(module, text) {
            const glyph = themeEdit.edit.icons ? themeEdit.edit.icons[module] : "";
            if (!glyph) return text;
            const characters = Array.from(text);
            const startsWithIcon = characters.length && characters[0].codePointAt(0) >= 0xE000;
            return glyph + (startsWithIcon ? characters.slice(1).join("") : " " + text);
        }
        function iconEditable(module) {
            return !!themeEdit.editing && themeEdit.editing.waybar.iconEditable.includes(module);
        }
        function setIcon(module, glyph) {
            const icons = Object.assign({}, themeEdit.edit.icons);
            if (glyph) icons[module] = glyph;
            else delete icons[module];
            themeEdit.change("icons", icons);
        }
        function openIconPicker(module) {
            themeEdit.iconFor = module;
            themeEdit.iconChoice = themeEdit.edit.icons[module] || "";
            themeEdit.iconQuery = themeEdit.iconHints[module] || "";
            themeEdit.askIcons();
        }
        function applyIcon() {
            themeEdit.setIcon(themeEdit.iconFor, themeEdit.iconChoice);
            themeEdit.iconFor = "";
        }
        // The module's icon as the bar shows it now: the first character of its text.
        function iconOf(module) {
            const characters = Array.from(themeEdit.preview(module));
            return characters.length && characters[0].codePointAt(0) >= 0xE000 ? characters[0] : "";
        }
        // The theme's own: written into its ui.json (a theme made in this window), or the rice's.
        function themesIconTheme() {
            return (themeEdit.editing && themeEdit.editing.ui.iconTheme) || themeEdit.defaultIconTheme;
        }
        function iconThemeNow() {
            return themeEdit.edit.iconTheme || themeEdit.themesIconTheme();
        }
        // ---- cursor: a pick here, or the theme's own (written into its ui.json, or the rice's)
        function themesCursor() {
            return (themeEdit.editing && themeEdit.editing.ui.cursor) || themeEdit.defaultCursor;
        }
        function themesCursorSize() {
            return (themeEdit.editing && themeEdit.editing.ui.cursorSize) || 24;
        }
        function cursorNow() {
            return themeEdit.edit.cursor || themeEdit.themesCursor();
        }
        function cursorSizeNow() {
            return themeEdit.edit.cursorSize || themeEdit.themesCursorSize();
        }
        // The theme's own takes the pick away: «как в теме» is the absence of one.
        function pickCursor(name) {
            themeEdit.change("cursor", name === themeEdit.themesCursor() ? "" : name);
        }
        function pickCursorSize(pixels) {
            themeEdit.change("cursorSize", pixels === themeEdit.themesCursorSize() ? 0 : pixels);
        }
        // ---- installing an icon theme: the window asks for the sudo password; the install itself runs
        // in the background (rice-install-package), so this window may close. Its log is shown here.
        property var installing: null      // {package, title, source} whose install the dialog shows
        property string installState: ""   // ask, checking (the password), running, done, failed
        property string installMessage: ""
        property var installLog: []
        // ---- windows: a value set here, or the theme's own
        function windowValue(key) {
            const own = themeEdit.editing ? themeEdit.editing.windows[key] : undefined;
            return key in themeEdit.edit.windows ? themeEdit.edit.windows[key] : own;
        }
        // The theme's own value takes the edit away: «как в теме» is the absence of one.
        function setWindow(key, value) {
            const windows = Object.assign({}, themeEdit.edit.windows);
            if (themeEdit.editing && themeEdit.editing.windows[key] === value) delete windows[key];
            else windows[key] = value;
            themeEdit.change("windows", windows);
        }
        function askInstall(item) {
            themeEdit.installing = item;
            themeEdit.installState = "ask";
            themeEdit.installMessage = "";
            themeEdit.installLog = [];
            installLogFile.reload();  // an install of this package may be running already: then its log shows
        }
        function startInstall(password) {
            installProc.password = password;
            installProc.command = [root.home + "/.local/bin/rice-install-package", themeEdit.installing.package];
            themeEdit.installState = "checking";
            themeEdit.installMessage = "";
            installProc.running = true;
        }
        // The background install's log; its last line is "@@done <status>" once it is over.
        function readInstallLog(text) {
            const lines = text.split("\n").filter(line => line);
            if (!lines.length || !themeEdit.installing) return;
            const done = lines[lines.length - 1].match(/^@@done (\d+)$/);
            if (!done && themeEdit.installState === "ask") themeEdit.installState = "running";
            if (themeEdit.installState !== "running") return;
            themeEdit.installLog = lines.filter(line => !line.startsWith("@@done")).slice(-14);
            if (done) {
                themeEdit.installState = done[1] === "0" ? "done" : "failed";
                themeEdit.installMessage = done[1] === "0" ? "Установлено. Тема появилась в списке." : "Не установилось, подробности выше.";
                iconThemesProc.running = true;
                cursorThemesProc.running = true;
            }
        }
        function askIcons() {
            if (!themeEdit.allIcons.length && !iconsProc.running) iconsProc.running = true;
        }
        function moduleState(module) {
            return (themeEdit.live[module] || {}).state || "shown";
        }
        function moduleNote(module) {
            return (themeEdit.live[module] || {}).note || "";
        }
        function setPosition(position) {
            themeEdit.change("waybar", Object.assign(themeEdit.panelCopy(), { position: position }));
        }
        // The layout on screen becomes the one for every theme; this theme follows it from now on.
        function savePanelEverywhere() {
            themeEdit.everywhere = Object.assign({}, themeEdit.everywhere, { waybar: themeEdit.panelCopy() });
            themeEdit.change("waybar", null);
            themeEdit.write(themeEdit.applyCurrent());
        }
        function dropSharedPanel() {
            const everywhere = Object.assign({}, themeEdit.everywhere);
            delete everywhere.waybar;
            themeEdit.everywhere = everywhere;
            themeEdit.write(themeEdit.applyCurrent());
        }
        // Whatever theme is on now, applied again: a layout for every theme concerns it too.
        function applyCurrent() {
            return 'changetheme --keep-wallpaper "$(cat ~/.config/hypr/current-theme)"';
        }

        // ---- the section's "back to the theme"
        function sectionEdited() {
            const part = themeEdit.edit[themeEdit.section] || {};
            if (themeEdit.section === "wallpapers") return part.added.length > 0 || part.off.length > 0;
            if (themeEdit.section === "waybar") return themeEdit.edit.waybar !== null || Object.keys(themeEdit.edit.icons).length > 0;
            if (themeEdit.section === "colors") return Object.keys(themeEdit.edit.colors).length > 0 || !!themeEdit.edit.folders;
            if (themeEdit.section === "icons") return !!themeEdit.edit.iconTheme || !!themeEdit.edit.battery;
            if (themeEdit.section === "cursor") return !!themeEdit.edit.cursor || !!themeEdit.edit.cursorSize;
            if (themeEdit.section === "windows") return Object.keys(themeEdit.edit.windows).length > 0;
            return Object.values(part).some(value => !!value);
        }
        function resetSection() {
            const empty = { fonts: { font: "", display: "", body: "" }, colors: {}, wallpapers: { added: [], off: [] },
                            waybar: null };
            themeEdit.change(themeEdit.section, empty[themeEdit.section]);
            if (themeEdit.section === "waybar") themeEdit.change("icons", {});
            if (themeEdit.section === "colors") themeEdit.change("folders", "");
            if (themeEdit.section === "windows") themeEdit.change("windows", {});
            if (themeEdit.section === "icons") {
                themeEdit.change("iconTheme", "");
                themeEdit.change("battery", "");
            }
            if (themeEdit.section === "cursor") {
                themeEdit.change("cursor", "");
                themeEdit.change("cursorSize", 0);
            }
        }

        // ---- saving
        function save() {
            themeEdit.write(themeEdit.editing.current ? "changetheme --keep-wallpaper " + themeEdit.editing.name : "");
        }
        function switchTo() {
            themeEdit.write("changetheme " + themeEdit.editing.name);
            root.close();
        }
        // Writes the file, then runs: the removed wallpapers' copies go, a colour change rebuilds what
        // themegen draws for every theme (battery icon, Telegram, Code - OSS), then `then`.
        function write(then) {
            const before = JSON.parse(themeEdit.saved);
            const next = Object.assign({}, themeEdit.everyTheme);
            const pruned = themeEdit.pruned(themeEdit.edit);
            if (Object.keys(pruned).length) next[themeEdit.editing.name] = pruned;
            else delete next[themeEdit.editing.name];
            const steps = before.wallpapers.added.filter(p => !themeEdit.edit.wallpapers.added.includes(p))
                .filter(p => p.startsWith(themeEdit.wallpaperDir + "/")).map(p => "rm -f " + root.quote(p));
            // Colours and the battery drawing are in what build draws for every theme.
            if (JSON.stringify(before.colors) !== JSON.stringify(themeEdit.edit.colors) || before.battery !== themeEdit.edit.battery)
                steps.push("python3 ~/.config/hypr/scripts/themegen.py build >/dev/null 2>&1");
            if (then) steps.push(then);
            const file = { themes: next };
            if (Object.keys(themeEdit.everywhere).length) file.everywhere = themeEdit.everywhere;
            root.writeFile(themeEdit.path, JSON.stringify(file, null, 2) + "\n", steps.join("; "));
            themeEdit.everyTheme = next;
            themeEdit.saved = JSON.stringify(themeEdit.edit);
            // What each theme follows when it has no layout of its own, now that the shared one may differ.
            const shared = themeEdit.everywhere.waybar;
            root.themes = root.themes.map(t => {
                const waybar = Object.assign({}, t.waybar, { withoutOwn: shared || t.waybar.themesOwn });
                return Object.assign({}, t, { waybar: waybar }, t.name === themeEdit.editing.name ? { edits: pruned } : {});
            });
            themeEdit.editing = root.themes.find(t => t.name === themeEdit.editing.name);
        }
        // Only what differs from the theme: no empty fonts, colours or lists.
        function pruned(edit) {
            const out = {};
            const fonts = {};
            for (const [key, value] of Object.entries(edit.fonts))
                if (value) fonts[key] = value;
            if (Object.keys(fonts).length) out.fonts = fonts;
            if (Object.keys(edit.colors).length) out.colors = edit.colors;
            const walls = {};
            if (edit.wallpapers.added.length) walls.added = edit.wallpapers.added;
            if (edit.wallpapers.off.length) walls.off = edit.wallpapers.off;
            if (Object.keys(walls).length) out.wallpapers = walls;
            if (edit.waybar) out.waybar = edit.waybar;
            if (Object.keys(edit.icons).length) out.icons = edit.icons;
            for (const key of ["folders", "iconTheme", "battery", "cursor", "cursorSize"])
                if (edit[key]) out[key] = edit[key];
            if (Object.keys(edit.windows).length) out.windows = edit.windows;
            return out;
        }
    }
    FileView { id: themeEditFile; path: themeEdit.path; blockLoading: true }
    Process {
        id: fontsProc
        command: ["sh", "-c", "fc-list : family | cut -d, -f1 | sort -u"]
        stdout: StdioCollector { onStreamFinished: themeEdit.installedFonts = this.text.split("\n").filter(name => name) }
    }
    Process {
        id: iconThemesProc
        command: ["python3", root.home + "/.config/hypr/scripts/themegen.py", "icon-themes"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { themeEdit.iconThemes = JSON.parse(this.text); } catch (e) {}
            }
        }
    }
    // A package being installed by rice-install-package; the sudo password goes on its stdin, never in
    // its arguments, and is forgotten here as soon as it is written.
    Process {
        id: installProc
        property string password: ""
        stdinEnabled: true
        onStarted: {
            installProc.write(installProc.password + "\n");
            installProc.password = "";
        }
        stdout: SplitParser {
            onRead: line => themeEdit.installLog = themeEdit.installLog.concat([line]).slice(-14)
        }
        onExited: exitCode => {
            if (exitCode === 0) {
                themeEdit.installState = "running";
                themeEdit.installMessage = "Идёт в фоне: окно установки и настройки можно закрыть, по окончании придёт уведомление.";
                installLogFile.reload();
            } else if (exitCode === 2) {
                themeEdit.installState = "ask";
                themeEdit.installMessage = "Пароль не подошёл. После трёх неверных паролей подряд sudo блокируется на 10 минут.";
            } else {
                themeEdit.installState = "failed";
                themeEdit.installMessage = "Установка не запустилась.";
            }
        }
    }
    FileView {
        id: installLogFile
        path: themeEdit.installing ? (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/rice-install-" + themeEdit.installing.package + ".log" : ""
        watchChanges: true
        onFileChanged: reload()
        onLoaded: themeEdit.readInstallLog(text())
    }
    Process {
        id: cursorThemesProc
        command: ["python3", root.home + "/.config/hypr/scripts/themegen.py", "cursor-themes"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { themeEdit.cursorThemes = JSON.parse(this.text); } catch (e) {}
            }
        }
    }
    Process {
        id: iconsProc
        command: ["python3", root.home + "/.config/hypr/scripts/themegen.py", "icons"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { themeEdit.allIcons = JSON.parse(this.text); } catch (e) { themeEdit.allIcons = []; }
            }
        }
    }
    Process {
        id: barPreviewProc
        stdout: StdioCollector {
            onStreamFinished: {
                try { themeEdit.live = JSON.parse(this.text); } catch (e) { themeEdit.live = {}; }
            }
        }
    }
    // ================= theme: themes of the user's own =================
    // A new theme (a copy of another with its edits written in), one from a file, an exported one, a
    // deleted one: themegen.py does the work, then the list is read again.
    QtObject {
        id: ownThemes
        property string dialog: ""     // "new", "import", "export" or "delete": what the dialog asks
        property var subject: null     // the theme a new one copies, or the one to export or delete
        property string busy: ""       // what runs now
        property string error: ""
        property string done: ""       // where the export went
        property string openAfter: ""  // the theme to open once the list is read again
        property string picking: ""    // "import" or "export": what the file dialog is for
        property var removed: []       // the rice's themes the user removed: [{name, label}]
        property string selected: ""   // the theme picked in the list; the current one until then
        property int themePage: 0      // the tab of the theme list shown
        readonly property int perPage: 8
        readonly property int pages: Math.max(1, Math.ceil(root.themes.length / ownThemes.perPage))

        function chosen() {
            return root.themes.find(t => t.name === ownThemes.selected) || root.themes.find(t => t.current) || null;
        }
        function factory() {
            ownThemes.run("Возвращаю к заводским…", ["factory", ownThemes.subject.name]);
        }
        function ask(kind, entry) {
            ownThemes.subject = entry;
            ownThemes.error = "";
            ownThemes.done = "";
            ownThemes.dialog = kind;
        }
        function create(label) {
            if (label.trim()) ownThemes.run("Создаю тему…", ["new", label.trim(), "--from", ownThemes.subject.name]);
        }
        function restore(name) {
            ownThemes.run("Возвращаю тему…", ["restore", name]);
        }
        function remove() {
            if (themeEdit.editing && themeEdit.editing.name === ownThemes.subject.name) themeEdit.editing = null;
            ownThemes.run("Удаляю…", ["delete", ownThemes.subject.name]);
        }
        function pickFile(kind) {
            ownThemes.picking = kind;
            root.picking = true;
            fileDialogProc.command = kind === "import"
                ? ["zenity", "--file-selection", "--title=Тема из файла", "--file-filter=Темы | *.zip"]
                : ["zenity", "--file-selection", "--save", "--title=Куда сохранить тему",
                   "--filename=" + root.home + "/" + ownThemes.subject.name + ".zip"];
            fileDialogProc.running = true;
        }
        function picked(path) {
            if (!path) return;
            if (ownThemes.picking === "import") ownThemes.run("Добавляю тему…", ["import", path]);
            else ownThemes.run("Сохраняю…", ["export", ownThemes.subject.name, path]);
        }
        // themegen.py's output and then "@@exit <status>": one stream, so nothing arrives after the end.
        function run(what, args) {
            ownThemes.busy = what;
            ownThemes.error = "";
            manageProc.args = args;
            manageProc.command = ["sh", "-c", 'python3 -u "$0" "$@" 2>&1; echo "@@exit $?"',
                                  root.home + "/.config/hypr/scripts/themegen.py"].concat(args);
            manageProc.running = true;
        }
        function finished(output) {
            ownThemes.busy = "";
            const lines = output.trim().split("\n");
            const code = parseInt(lines.pop().replace("@@exit ", ""));
            if (code !== 0) {
                ownThemes.error = lines.join("\n") || "не вышло (код " + code + ")";
                return;
            }
            if (manageProc.args[0] === "export") {
                ownThemes.done = "Сохранено: " + manageProc.args[2];
                return;
            }
            ownThemes.dialog = "";
            const command = manageProc.args[0];
            // new and import print the theme's name first; restore brings back the one it was given.
            const subject = manageProc.args[1];
            if (command === "factory" && ownThemes.subject.current)
                Quickshell.execDetached(["changetheme", subject]);  // the theme on screen changes too
            const reopen = command === "factory" && themeEdit.editing && themeEdit.editing.name === subject;
            ownThemes.openAfter = command === "new" || command === "import" ? lines[0]
                                  : command === "restore" || reopen ? subject : "";
            if (ownThemes.openAfter) ownThemes.selected = ownThemes.openAfter;
            themeListProc.running = true;
        }
        function listRead(text) {
            try { root.themes = JSON.parse(text); } catch (e) {}
            removedProc.running = true;
            const made = root.themes.findIndex(t => t.name === ownThemes.openAfter);
            if (made >= 0) {
                ownThemes.themePage = Math.floor(made / ownThemes.perPage);
                themeEdit.open(root.themes[made]);
            }
            ownThemes.themePage = Math.min(ownThemes.themePage, ownThemes.pages - 1);
        }
    }
    Process {
        id: manageProc
        property var args: []
        stdout: StdioCollector { onStreamFinished: ownThemes.finished(this.text) }
    }
    Process {
        id: removedProc
        command: ["python3", root.home + "/.config/hypr/scripts/themegen.py", "removed-themes"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try { ownThemes.removed = JSON.parse(this.text); } catch (e) { ownThemes.removed = []; }
            }
        }
    }
    // The list comes on stdout, not read back through themeListFile: read that way right after reload(),
    // a new theme was missing until the window was opened again (reload() most likely not done yet).
    Process {
        id: themeListProc
        command: ["sh", "-c", 'python3 "$0" "$1" && cat "$1"',
                  root.home + "/.config/quickshell/theme-list.py", Quickshell.env("RICE_THEME_LIST")]
        stdout: StdioCollector { onStreamFinished: ownThemes.listRead(this.text) }
    }
    Process {
        id: fileDialogProc
        stdout: StdioCollector { onStreamFinished: ownThemes.picked(this.text.trim()) }
        onExited: root.picking = false
    }

    // ================= theme: cursors and wallpaper frames from the user's files =================
    // themegen.py with its output and then "@@exit <status>" in one stream; then(lines, ok) gets them.
    QtObject {
        id: userFiles
        property var then: null
        property string message: ""      // what the last step did, or why it did not
        property bool failed: false
        property string pickFor: ""      // "cursor" or "frames": what the file dialog is for
        // The frame picker: the file, what is read of it (a GIF made into an mp4), its length, the
        // moment shown and its preview.
        property string frameSource: ""
        property string frameInput: ""
        property var frameLength: null   // {kind: gif, frames} or {kind: video, seconds}
        property real frameAt: 0
        property string framePreview: ""
        property int previewNumber: 0    // a new file name per preview: the same name would stay cached
        readonly property string runtime: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"

        function run(args, then) {
            userFiles.then = then;
            userFilesProc.command = ["sh", "-c", 'python3 "$0" "$@" 2>&1; echo "@@exit $?"',
                                     root.home + "/.config/hypr/scripts/themegen.py"].concat(args);
            userFilesProc.running = true;
        }
        function done(output) {
            const lines = output.trim().split("\n");
            const ok = lines.pop() === "@@exit 0";
            if (!ok) {
                userFiles.failed = true;
                userFiles.message = lines.join(" ") || "не вышло";
            }
            if (userFiles.then) userFiles.then(lines, ok);
        }
        function say(text) {
            userFiles.failed = false;
            userFiles.message = text;
        }
        function pick(kind) {
            userFiles.pickFor = kind;
            userFiles.message = "";
            root.picking = true;
            userFileDialog.command = kind === "cursor"
                ? ["zenity", "--file-selection", "--title=Курсор",
                   "--file-filter=Курсоры и скины osu! | *.tar.gz *.tgz *.tar.xz *.txz *.tar.bz2 *.zip *.osk"]
                : ["zenity", "--file-selection", "--title=GIF или видео",
                   "--file-filter=GIF и видео | *.gif *.mp4 *.webm *.mkv *.mov *.avi *.m4v"];
            userFileDialog.running = true;
        }
        function picked(path) {
            if (!path) return;
            if (userFiles.pickFor === "cursor") userFiles.addCursor(path);
            else userFiles.openFrames(path);
        }

        // ---- cursors
        function addCursor(path) {
            userFiles.say("Ставлю курсор…");
            userFiles.run(["cursor-add", path], (lines, ok) => {
                if (ok) userFiles.say("Добавлено: " + JSON.parse(lines[lines.length - 1]).join(", "));
                cursorThemesProc.running = true;
            });
        }
        function removeCursor(name) {
            userFiles.run(["cursor-remove", name], (lines, ok) => {
                if (!ok) return;
                if (themeEdit.edit.cursor === name) themeEdit.change("cursor", "");
                userFiles.say("Курсор «" + name + "» удалён");
                cursorThemesProc.running = true;
            });
        }

        // ---- a wallpaper from a moment of a GIF or a video
        function openFrames(path) {
            userFiles.frameSource = path;
            userFiles.frameInput = "";
            userFiles.frameLength = null;
            userFiles.framePreview = "";
            userFiles.say(path.toLowerCase().endsWith(".gif") ? "Перевожу GIF в видео для быстрой перемотки…" : "Открываю…");
            userFiles.run(["frame-prepare", path], (lines, ok) => {
                if (!ok) return;
                const prepared = JSON.parse(lines[lines.length - 1]);
                userFiles.frameInput = prepared.source;
                userFiles.frameLength = prepared;
                userFiles.say("");
                userFiles.showFrame(0);
            });
        }
        // Closes the picker: its preview and a GIF's mp4 go.
        function closeFrames() {
            userFiles.forgetPreview();
            if (userFiles.frameInput && userFiles.frameInput !== userFiles.frameSource)
                Quickshell.execDetached(["python3", root.home + "/.config/hypr/scripts/themegen.py", "frame-forget", userFiles.frameInput]);
            userFiles.frameInput = "";
            userFiles.frameSource = "";
        }
        function frameEnd() {
            const length = userFiles.frameLength;
            return !length ? 0 : length.kind === "gif" ? Math.max(0, length.frames - 1) : Math.max(0, length.seconds - 0.05);
        }
        function frameLabel() {
            const length = userFiles.frameLength;
            if (!length) return "";
            return length.kind === "gif" ? "кадр " + (Math.round(userFiles.frameAt) + 1) + " из " + length.frames
                                         : userFiles.frameAt.toFixed(1) + " с из " + length.seconds.toFixed(1) + " с";
        }
        function showFrame(at) {
            userFiles.frameAt = at;
            framePreviewTimer.restart();
        }
        function preview() {
            if (userFilesProc.running) { framePreviewTimer.restart(); return; }
            userFiles.previewNumber += 1;
            const out = userFiles.runtime + "/frame-preview-" + userFiles.previewNumber + ".png";
            userFiles.run(["frame", userFiles.frameInput, String(userFiles.frameAt), out, "960"], (lines, ok) => {
                if (!ok) return;
                userFiles.forgetPreview();
                userFiles.framePreview = out;
            });
        }
        function forgetPreview() {
            if (userFiles.framePreview) Quickshell.execDetached(["rm", "-f", userFiles.framePreview]);
            userFiles.framePreview = "";
        }
        function takeFrame() {
            const name = userFiles.frameSource.split("/").pop().replace(/\.[^.]*$/, "");
            const out = themeEdit.wallpaperDir + "/" + themeEdit.editing.name + "/" + name + "-"
                        + String(userFiles.frameAt.toFixed(1)).replace(".", "_") + ".png";
            userFiles.say("Сохраняю кадр…");
            userFiles.run(["frame", userFiles.frameInput, String(userFiles.frameAt), out], (lines, ok) => {
                if (!ok) return;
                themeEdit.addWallpaper(out);
                userFiles.closeFrames();
                userFiles.say("Кадр добавлен в обои: сохрани тему, чтобы он остался");
            });
        }
    }
    Process {
        id: userFilesProc
        stdout: StdioCollector { onStreamFinished: userFiles.done(this.text) }
    }
    Process {
        id: userFileDialog
        stdout: StdioCollector { onStreamFinished: userFiles.picked(this.text.trim()) }
        onExited: root.picking = false
    }
    // The preview follows the slider once it rests for a moment, not on every step of a drag.
    Timer { id: framePreviewTimer; interval: 180; onTriggered: userFiles.preview() }

    Process {
        id: wallpaperPicker
        stdout: StdioCollector { onStreamFinished: themeEdit.addWallpaper(this.text.trim()) }
        onExited: root.picking = false
    }

    PanelWindow {
        visible: !root.picking
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
                if (e.key === Qt.Key_Escape) root.back();
            }
            Component.onCompleted: inAnim.start()
            NumberAnimation { id: inAnim; target: scene; property: "opacity"; to: 1; duration: 200 }
            SequentialAnimation {
                id: outAnim
                NumberAnimation { target: scene; property: "opacity"; to: 0; duration: 160 }
                ScriptAction { script: Qt.quit() }
            }

            Rectangle { anchors.fill: parent; color: Color.withAlpha(theme.c.bg, 0.7) }
            MouseArea { anchors.fill: parent; onClicked: root.close() }

            Rectangle {
                id: sheet
                anchors.centerIn: parent
                width: Math.min(parent.width - 80, 1280)
                height: Math.min(parent.height - 80, 860)
                radius: root.r
                color: Color.withAlpha(theme.c.bg, 0.96)
                border.width: theme.ui.border ?? 1
                border.color: Color.withAlpha(theme.c.accent, 0.5)
                MouseArea { anchors.fill: parent; onClicked: scene.forceActiveFocus() }

                Row {
                    id: header
                    x: 32; y: 24
                    spacing: 14
                    Text {
                        text: "\u{f0493}"
                        font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 26
                        color: theme.c.accent || "white"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: theme.ui.upperTitle ? "НАСТРОЙКИ" : "Настройки"
                        font.family: theme.titleFont; font.pixelSize: 30; font.italic: !!theme.ui.italicTitle
                        color: theme.c.fg || "white"
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
                    font.family: theme.bodyFont; font.pixelSize: 14
                    color: theme.c.muted || "grey"
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
                            color: Color.withAlpha(theme.c.bg2, 0.8)
                            border.color: Color.withAlpha(theme.c.muted, 0.25)

                            readonly property var on: mon.edit.filter(m => !m.disabled)
                            readonly property real bw: Math.max(1, Math.max(...on.map(m => m.x + mon.lw(m)), 1))
                            readonly property real bh: Math.max(1, Math.max(...on.map(m => m.y + mon.lh(m)), 1))
                            readonly property real fit: Math.min((width - 80) / bw, (height - 110) / bh) * 0.8
                            readonly property real ox: (width - bw * fit) / 2
                            readonly property real oy: (height - 40 - bh * fit) / 2

                            Text {
                                x: 18; y: 14
                                text: "Расположение — перетащи экран мышкой"
                                font.family: theme.bodyFont; font.pixelSize: 14
                                color: theme.c.muted || "grey"
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
                                    color: mon.sel === index ? Color.withAlpha(theme.c.accent, 0.3) : Color.withAlpha(theme.c.accent, 0.12)
                                    border.width: mon.sel === index ? 2 : 1
                                    border.color: theme.c.accent || "white"
                                    Column {
                                        anchors.centerIn: parent
                                        spacing: 4
                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: screenRect.modelData.name
                                            font.family: theme.titleFont; font.pixelSize: 18; font.bold: true
                                            color: theme.c.fg || "white"
                                        }
                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: screenRect.modelData.w + "×" + screenRect.modelData.h + " · "
                                                  + Math.round(screenRect.modelData.rate) + " Гц · ×" + screenRect.modelData.scale
                                            font.family: theme.bodyFont; font.pixelSize: 13
                                            color: theme.c.muted || "grey"
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
                                    font.family: theme.bodyFont; font.pixelSize: 14
                                    color: theme.c.muted || "grey"
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
                                font.family: theme.bodyFont; font.pixelSize: 14
                                color: theme.c.accent2 || "white"
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
                            color: theme.c.bg2 || "black"
                            border.width: 2
                            border.color: theme.c.accent || "white"
                            Column {
                                anchors.centerIn: parent
                                spacing: 18
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "Оставить эти настройки?"
                                    font.family: theme.titleFont; font.pixelSize: 24
                                    color: theme.c.fg || "white"
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "Вернётся как было через " + mon.countdown + " с"
                                    font.family: theme.bodyFont; font.pixelSize: 15
                                    color: theme.c.muted || "grey"
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
                                font.family: theme.bodyFont; font.pixelSize: 15
                                color: theme.c.fg || "white"
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
                                font.family: theme.bodyFont; font.pixelSize: 14
                                color: keys.conflict ? (theme.c.warn || "orange") : (theme.c.accent2 || "white")
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
                    // On the left what adds or brings back themes and the tabs of the list (8 themes to a
                    // tab); on the right what can be done with the theme selected below.
                    Row {
                        id: themeTools
                        visible: root.page === "theme"
                        spacing: 10
                        Chip { text: "Из файла…"; onClicked: ownThemes.ask("import", null) }
                        Chip {
                            visible: ownThemes.removed.length > 0
                            text: "Вернуть удалённые (" + ownThemes.removed.length + ")"
                            onClicked: ownThemes.ask("restore", null)
                        }
                        Item { visible: ownThemes.pages > 1; width: 12; height: 1 }
                        Repeater {
                            model: ownThemes.pages > 1 ? ownThemes.pages : 0
                            TabButton {
                                required property int index
                                text: String(index + 1)
                                active: ownThemes.themePage === index
                                onClicked: ownThemes.themePage = index
                            }
                        }
                    }
                    Row {
                        readonly property var chosen: ownThemes.chosen()
                        anchors { right: parent.right; verticalCenter: themeTools.verticalCenter }
                        visible: root.page === "theme" && chosen !== null
                        spacing: 10
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: parent.chosen ? "«" + parent.chosen.pal.label + "»" : ""
                            font.family: theme.titleFont; font.pixelSize: 16; font.italic: !!theme.ui.italicTitle
                            color: theme.c.accent2 || theme.c.accent || "white"
                        }
                        Chip { text: "Изменить"; primary: true; onClicked: themeEdit.open(parent.chosen) }
                        Chip { text: "Добавить на её основе"; onClicked: ownThemes.ask("new", parent.chosen) }
                        Chip { text: "Экспорт…"; onClicked: ownThemes.ask("export", parent.chosen) }
                        Chip { text: "К заводским"; onClicked: ownThemes.ask("factory", parent.chosen) }
                        Chip { visible: parent.chosen !== null && !parent.chosen.current; text: "Удалить"; onClicked: ownThemes.ask("delete", parent.chosen) }
                    }
                    Flow {
                        anchors { left: parent.left; right: parent.right; top: themeTools.bottom; bottom: parent.bottom; topMargin: 16 }
                        visible: root.page === "theme"
                        spacing: 16
                        Repeater {
                            model: root.themes.slice(ownThemes.themePage * ownThemes.perPage, (ownThemes.themePage + 1) * ownThemes.perPage)
                            Rectangle {
                                id: tcard
                                required property var modelData
                                width: 280; height: 230
                                radius: Math.min(root.r, 14)
                                color: modelData.pal.colors.bg
                                readonly property bool chosen: ownThemes.chosen() !== null && ownThemes.chosen().name === modelData.name
                                border.width: chosen ? 3 : tma.containsMouse || modelData.current ? 2 : 1
                                border.color: modelData.pal.colors.accent
                                clip: true
                                Image {
                                    x: 8; y: 8; width: parent.width - 16; height: 140
                                    source: tcard.modelData.thumb ? "file://" + tcard.modelData.thumb : ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                }
                                Text {
                                    visible: tcard.modelData.current
                                    anchors { right: parent.right; rightMargin: 14; bottom: parent.bottom; bottomMargin: 16 }
                                    text: "сейчас"
                                    font.family: theme.bodyFont; font.pixelSize: 13
                                    color: tcard.modelData.pal.colors.accent
                                }
                                Column {
                                    x: 18; y: 160
                                    spacing: 10
                                    Text {
                                        text: tcard.modelData.pal.label
                                        font.family: theme.titleFont; font.pixelSize: 22
                                        color: tcard.modelData.pal.colors.fg
                                    }
                                    Row {
                                        spacing: 6
                                        Repeater {
                                            model: [tcard.modelData.pal.colors.accent, tcard.modelData.pal.colors.accent2, tcard.modelData.pal.colors.fg]
                                            Rectangle { required property string modelData; width: 22; height: 22; radius: 11; color: modelData }
                                        }
                                    }
                                }
                                Text {
                                    visible: tcard.modelData.user && !tcard.modelData.current
                                    anchors { right: parent.right; rightMargin: 14; bottom: parent.bottom; bottomMargin: 16 }
                                    text: "своя"
                                    font.family: theme.bodyFont; font.pixelSize: 13
                                    color: tcard.modelData.pal.colors.muted
                                }
                                MouseArea {
                                    id: tma
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: ownThemes.selected = tcard.modelData.name
                                    onDoubleClicked: themeEdit.open(tcard.modelData)
                                }
                            }
                        }
                    }

                    // ---------------- Настройки одной темы ----------------
                    ThemeSettings {
                        anchors.fill: parent
                        visible: root.page === "theme" && themeEdit.editing !== null
                    }
                    OwnThemeDialog {
                        anchors.fill: parent
                        visible: root.page === "theme" && ownThemes.dialog !== ""
                    }
                }

                // Shown while a combo is being recorded.
                Rectangle {
                    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 70 }
                    visible: keys.capturing !== ""
                    width: capText.implicitWidth + 48; height: 52
                    radius: 26
                    color: theme.c.bg2 || "black"
                    border.width: 2
                    border.color: theme.c.accent || "white"
                    Text {
                        id: capText
                        anchors.centerIn: parent
                        text: "Нажми новое сочетание · Esc — отмена"
                        font.family: theme.bodyFont; font.pixelSize: 16
                        color: theme.c.fg || "white"
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
        color: active ? Color.withAlpha(theme.c.accent, 0.25) : (tbm.containsMouse ? Color.withAlpha(theme.c.accent, 0.1) : "transparent")
        border.color: active ? (theme.c.accent || "white") : Color.withAlpha(theme.c.muted, 0.3)
        Text {
            id: tbText
            anchors.centerIn: parent
            text: tb.text
            font.family: theme.bodyFont; font.pixelSize: 15; font.bold: tb.active
            color: tb.active ? (theme.c.accent || "white") : (theme.c.fg || "white")
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
        color: primary ? (theme.c.accent || "white") : active ? Color.withAlpha(theme.c.accent, 0.28)
               : (chm.containsMouse ? Color.withAlpha(theme.c.accent, 0.12) : Color.withAlpha(theme.c.bg2, 0.9))
        border.color: active || primary ? (theme.c.accent || "white") : Color.withAlpha(theme.c.muted, 0.35)
        Text {
            id: chText
            anchors.centerIn: parent
            text: ch.text
            font.family: theme.bodyFont; font.pixelSize: 14; font.bold: ch.active || ch.primary
            color: ch.primary ? (theme.c.bg || "black") : ch.active ? (theme.c.accent || "white") : (theme.c.fg || "white")
        }
        MouseArea { id: chm; anchors.fill: parent; hoverEnabled: true; enabled: ch.enabled; onClicked: ch.clicked() }
    }

    // One theme's settings (themeEdit.editing): a header with saving and switching, the section tabs
    // and the section itself.
    component ThemeSettings: Rectangle {
        color: theme.c.bg || "black"
        MouseArea { anchors.fill: parent }

        Row {
            id: editHeader
            anchors { left: parent.left; top: parent.top }
            spacing: 14
            Chip { text: "← Темы"; onClicked: themeEdit.editing = null }
            SectionTitle {
                anchors.verticalCenter: parent.verticalCenter
                text: themeEdit.editing ? "Тема «" + themeEdit.editing.pal.label + "»" : ""
            }
        }
        Row {
            anchors { right: parent.right; top: parent.top }
            spacing: 10
            Chip { text: "Копия…"; enabled: themeEdit.editing !== null; onClicked: ownThemes.ask("new", themeEdit.editing) }
            Chip { text: "Экспорт…"; enabled: themeEdit.editing !== null; onClicked: ownThemes.ask("export", themeEdit.editing) }
            Chip {
                visible: themeEdit.editing !== null && !themeEdit.editing.current
                text: "Удалить"
                onClicked: ownThemes.ask("delete", themeEdit.editing)
            }
            Chip { text: "Сбросить раздел"; enabled: themeEdit.editing !== null && themeEdit.sectionEdited(); onClicked: themeEdit.resetSection() }
            Chip { text: "К заводским"; enabled: themeEdit.editing !== null; onClicked: ownThemes.ask("factory", themeEdit.editing) }
            Chip { visible: themeEdit.editing !== null && !themeEdit.editing.current; text: "Включить тему"; onClicked: themeEdit.switchTo() }
            Chip { text: "Сохранить"; primary: true; enabled: themeEdit.dirty; onClicked: themeEdit.save() }
        }
        Row {
            id: sectionTabs
            anchors { left: parent.left; top: editHeader.bottom; topMargin: 16 }
            spacing: 8
            Repeater {
                model: themeEdit.sections
                TabButton {
                    required property var modelData
                    text: modelData[1]
                    active: themeEdit.section === modelData[0]
                    onClicked: themeEdit.section = modelData[0]
                }
            }
        }
        Text {
            anchors { right: parent.right; verticalCenter: sectionTabs.verticalCenter }
            text: !themeEdit.editing ? "" : themeEdit.editing.current ? "Тема включена: изменения применятся при сохранении"
                                                                       : "Изменения применятся, когда включишь эту тему"
            font.family: theme.bodyFont; font.pixelSize: 13
            color: theme.c.muted || "grey"
        }

        Item {
            anchors { left: parent.left; right: parent.right; top: sectionTabs.bottom; bottom: parent.bottom; topMargin: 20 }
            FontsSection { anchors.fill: parent; visible: themeEdit.section === "fonts" }
            ColorsSection { anchors.fill: parent; visible: themeEdit.section === "colors" }
            WallpapersSection { anchors.fill: parent; visible: themeEdit.section === "wallpapers" }
            PanelSection { anchors.fill: parent; visible: themeEdit.section === "waybar" }
            IconsSection { anchors.fill: parent; visible: themeEdit.section === "icons" }
            WindowsSection { anchors.fill: parent; visible: themeEdit.section === "windows" }
            CursorSection { anchors.fill: parent; visible: themeEdit.section === "cursor" }
            FramePicker { anchors.fill: parent; z: 20; visible: userFiles.frameSource !== "" }
            InstallDialog { anchors.fill: parent; z: 30; visible: themeEdit.installing !== null }
        }
    }

    // Cursor themes (installed ones with a few cursors drawn, missing ones to install) and the size.
    component CursorSection: Item {
        SectionTitle {
            id: cursorTitle
            text: "Курсор"
        }
        Text {
            anchors { left: cursorTitle.right; leftMargin: 12; verticalCenter: cursorTitle.verticalCenter }
            text: themeEdit.editing && !themeEdit.edit.cursor ? "как в теме: " + themeEdit.themesCursor() : ""
            font.family: theme.bodyFont; font.pixelSize: 13
            color: theme.c.muted || "grey"
        }
        Row {
            id: cursorFileRow
            anchors { left: cursorTitle.right; leftMargin: 220; verticalCenter: cursorTitle.verticalCenter }
            spacing: 12
            Chip { text: "Добавить из файла…"; enabled: !userFilesProc.running; onClicked: userFiles.pick("cursor") }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: 360
                elide: Text.ElideRight
                text: userFiles.pickFor === "cursor" ? userFiles.message : ""
                font.family: theme.bodyFont; font.pixelSize: 13
                color: userFiles.failed ? (theme.c.crit || "red") : (theme.c.muted || "grey")
            }
        }
        Row {
            id: cursorSizeRow
            anchors { right: parent.right; verticalCenter: cursorTitle.verticalCenter }
            spacing: 8
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Размер"
                font.family: theme.bodyFont; font.pixelSize: 14
                color: theme.c.fg || "white"
            }
            Repeater {
                model: themeEdit.cursorSizes
                Chip {
                    required property int modelData
                    text: modelData + " px"
                    active: themeEdit.editing !== null && themeEdit.cursorSizeNow() === modelData
                    onClicked: themeEdit.pickCursorSize(modelData)
                }
            }
        }
        ListView {
            id: cursorList
            anchors { left: parent.left; right: parent.right; top: cursorTitle.bottom; bottom: parent.bottom; topMargin: 14 }
            clip: true
            spacing: 4
            boundsBehavior: Flickable.StopAtBounds
            model: themeEdit.cursorThemes.installed.concat(themeEdit.cursorThemes.downloadable.filter(item => !item.installed))
            delegate: Rectangle {
                id: cursorRow
                required property var modelData
                readonly property bool installed: modelData.name !== undefined
                readonly property bool chosen: installed && themeEdit.cursorNow() === modelData.name
                width: ListView.view.width; height: 60
                radius: root.r > 4 ? 8 : 0
                color: chosen ? Color.withAlpha(theme.c.accent, 0.2) : (cursorHover.containsMouse ? Color.withAlpha(theme.c.accent, 0.08) : Color.withAlpha(theme.c.bg2, 0.9))
                border.color: chosen ? (theme.c.accent || "white") : "transparent"
                MouseArea {
                    id: cursorHover
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: cursorRow.installed
                    onClicked: themeEdit.pickCursor(cursorRow.modelData.name)
                }
                Text {
                    id: cursorName
                    x: 14; anchors.verticalCenter: parent.verticalCenter
                    width: 220
                    elide: Text.ElideRight
                    text: cursorRow.installed ? cursorRow.modelData.label : cursorRow.modelData.title
                    font.family: theme.bodyFont; font.pixelSize: 15
                    color: theme.c.fg || "white"
                }
                Row {
                    visible: cursorRow.installed
                    anchors { left: cursorName.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
                    spacing: 14
                    Repeater {
                        model: cursorRow.installed ? cursorRow.modelData.previews : []
                        Image {
                            required property string modelData
                            width: 40; height: 40
                            source: "file://" + modelData
                            asynchronous: true
                        }
                    }
                }
                Text {
                    visible: !cursorRow.installed
                    anchors { left: cursorName.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
                    text: (cursorRow.modelData.source === "aur" ? "из AUR" : "из репозитория") + " · не установлен"
                    font.family: theme.bodyFont; font.pixelSize: 13
                    color: theme.c.muted || "grey"
                }
                Chip {
                    visible: !cursorRow.installed
                    anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    text: "Установить"
                    enabled: !installProc.running
                    onClicked: themeEdit.askInstall(cursorRow.modelData)
                }
                Chip {
                    visible: cursorRow.installed && !!cursorRow.modelData.removable
                    anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    text: "Удалить"
                    enabled: !userFilesProc.running
                    onClicked: userFiles.removeCursor(cursorRow.modelData.name)
                }
            }
        }
        Text {
            visible: !themeEdit.cursorThemes.installed.length
            anchors { left: cursorList.left; top: cursorList.top }
            text: "читаю курсоры…"
            font.family: theme.bodyFont; font.pixelSize: 13
            color: theme.c.muted || "grey"
        }
    }

    // Installing an icon or cursor theme: the password, then the installer's output.
    component InstallDialog: Rectangle {
        color: Color.withAlpha(theme.c.bg, 0.92)
        MouseArea { anchors.fill: parent }
        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 40, 720); height: installColumn.implicitHeight + 48
            radius: root.r
            color: theme.c.bg2 || "black"
            border.color: theme.c.accent || "white"
            Column {
                id: installColumn
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24 }
                spacing: 12
                SectionTitle {
                    text: themeEdit.installing ? "Установка «" + themeEdit.installing.title + "»" : ""
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: !themeEdit.installing ? ""
                          : (themeEdit.installing.source === "aur" ? "Из AUR: пакет соберётся на этой машине, это может занять пару минут. "
                                                                   : "Из репозитория Arch. ")
                            + "Нужен пароль администратора (sudo): он передаётся установщику напрямую и нигде не сохраняется."
                    font.family: theme.bodyFont; font.pixelSize: 14
                    color: theme.c.fg || "white"
                }
                Row {
                    visible: themeEdit.installState === "ask"
                    spacing: 10
                    Field {
                        id: passwordField
                        width: 300
                        echoMode: TextInput.Password
                        placeholder: "пароль sudo"
                        onAccepted: if (text) { themeEdit.startInstall(text); text = ""; }
                    }
                    Chip {
                        text: "Установить"
                        primary: true
                        enabled: passwordField.text !== ""
                        onClicked: { themeEdit.startInstall(passwordField.text); passwordField.text = ""; }
                    }
                    Chip { text: "Отмена"; onClicked: themeEdit.installing = null }
                }
                Rectangle {
                    visible: themeEdit.installState === "running" || themeEdit.installState === "done" || themeEdit.installState === "failed"
                    width: parent.width; height: 260
                    radius: 8
                    color: theme.c.bg || "black"
                    Text {
                        anchors { fill: parent; margins: 12 }
                        text: themeEdit.installLog.join("\n")
                        font.family: theme.font; font.pixelSize: 12
                        color: theme.c.muted || "grey"
                        wrapMode: Text.WrapAnywhere
                        clip: true
                        verticalAlignment: Text.AlignBottom
                    }
                }
                Text {
                    visible: themeEdit.installMessage !== ""
                    text: themeEdit.installMessage
                    font.family: theme.bodyFont; font.pixelSize: 14; font.bold: true
                    color: themeEdit.installState === "done" ? (theme.c.good || "green")
                           : themeEdit.installState === "running" ? (theme.c.accent || "white") : (theme.c.crit || "red")
                }
                Text {
                    visible: themeEdit.installState === "checking"
                    text: "Проверяю пароль…"
                    font.family: theme.bodyFont; font.pixelSize: 14
                    color: theme.c.accent || "white"
                }
                Chip {
                    visible: themeEdit.installState === "running"
                    text: "Скрыть (установка продолжится)"
                    onClicked: themeEdit.installing = null
                }
                Chip {
                    visible: themeEdit.installState === "done" || themeEdit.installState === "failed"
                    text: "Закрыть"
                    onClicked: themeEdit.installing = null
                }
            }
        }
    }

    // What ownThemes asks: a new theme's name, a file to add or to save to, whether to delete.
    component OwnThemeDialog: Rectangle {
        id: ownDialog
        readonly property string label: ownThemes.subject ? ownThemes.subject.pal.label : ""
        // A copy and an export take the saved edits only.
        readonly property string unsaved: themeEdit.dirty && ownThemes.subject && themeEdit.editing
                                          && ownThemes.subject.name === themeEdit.editing.name
                                          ? " Несохранённые изменения туда не попадут: сначала сохрани." : ""
        readonly property var texts: ({
            "new": ["Новая тема", "Копия темы «" + label + "» со всеми её правками из этого окна. Дальше настраивай её здесь же; обновления райса её не трогают." + unsaved, "Создать"],
            "import": ["Тема из файла", "Архив .zip, сохранённый кнопкой «Экспорт…». В теме есть и программы (hypr.lua, battery.py, screenshot.qml): добавляй темы только от тех, кому доверяешь.", "Выбрать файл…"],
            "export": ["Экспорт темы", "Тема «" + label + "» со всеми правками в одном архиве .zip. Друг добавит её кнопкой «Из файла…» в списке тем." + unsaved, "Сохранить как…"],
            "delete": ["Удалить тему", ownThemes.subject && ownThemes.subject.user
                       ? "Тема «" + label + "» и её правки удалятся насовсем."
                       : "Тема «" + label + "» уйдёт из списка, обновления райса её не вернут. Вернуть её можно кнопкой «Вернуть удалённые» над списком тем, вместе с твоими правками.", "Удалить"],
            "factory": ["Вернуть к заводским", ownThemes.subject && ownThemes.subject.user
                        ? "У своей темы нет заводского вида: уберутся все правки из этого окна, тема станет такой, какой её создали."
                        : "Тема «" + label + "» станет такой, как в райсе: уберутся все правки из этого окна и добавленные обои, файлы темы возьмутся заново из копии райса (так уйдут и правки руками в её папке). Общая раскладка панели для всех тем останется: её убирает кнопка в разделе «Панель».", "Вернуть"],
            "restore": ["Вернуть удалённые темы", "Темы райса, которые ты удалил: нажми на тему, и она вернётся из копии райса на этом компьютере вместе с твоими правками.", ""]
        })
        readonly property var wording: texts[ownThemes.dialog] || ["", "", ""]
        function act() {
            if (ownThemes.dialog === "new") ownThemes.create(nameField.text);
            else if (ownThemes.dialog === "delete") ownThemes.remove();
            else if (ownThemes.dialog === "factory") ownThemes.factory();
            else ownThemes.pickFile(ownThemes.dialog);
        }
        onVisibleChanged: {
            if (!visible || ownThemes.dialog !== "new") return;
            nameField.text = "";
            nameField.focusInput();
        }
        color: Color.withAlpha(theme.c.bg, 0.85)
        MouseArea { anchors.fill: parent }  // the page under it waits

        Rectangle {
            anchors.centerIn: parent
            width: 560; height: dialogColumn.implicitHeight + 48
            radius: Math.min(root.r, 14)
            color: theme.c.bg2 || "black"
            border.color: Color.withAlpha(theme.c.accent, 0.5)
            Column {
                id: dialogColumn
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24 }
                spacing: 14
                SectionTitle { text: ownDialog.wording[0] }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: ownDialog.wording[1]
                    font.family: theme.bodyFont; font.pixelSize: 14
                    color: theme.c.fg || "white"
                }
                Flow {
                    visible: ownThemes.dialog === "restore"
                    width: parent.width
                    spacing: 8
                    Repeater {
                        model: ownThemes.removed
                        Chip {
                            required property var modelData
                            text: modelData.label
                            enabled: !ownThemes.busy
                            onClicked: ownThemes.restore(modelData.name)
                        }
                    }
                }
                Field {
                    id: nameField
                    visible: ownThemes.dialog === "new"
                    width: parent.width
                    placeholder: "Название, например «Моя тема»"
                    onAccepted: ownDialog.act()
                }
                Text {
                    visible: text !== ""
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: ownThemes.busy || ownThemes.error || ownThemes.done
                    font.family: theme.bodyFont; font.pixelSize: 13
                    color: ownThemes.error ? (theme.c.crit || "red") : (theme.c.muted || "grey")
                }
                Row {
                    anchors.right: parent.right
                    spacing: 10
                    Chip { text: ownThemes.done ? "Закрыть" : "Отмена"; enabled: !ownThemes.busy; onClicked: ownThemes.dialog = "" }
                    Chip {
                        visible: !ownThemes.done && ownDialog.wording[2] !== ""
                        primary: true
                        enabled: !ownThemes.busy && (ownThemes.dialog !== "new" || nameField.text.trim() !== "")
                        text: ownDialog.wording[2]
                        onClicked: ownDialog.act()
                    }
                }
            }
        }
    }

    // The three fonts on the left; on the right the installed fonts, each in its own face.
    component FontsSection: Item {
        Column {
            id: slotColumn
            anchors { left: parent.left; top: parent.top }
            width: 400
            spacing: 12
            Repeater {
                model: themeEdit.fontSlots
                Rectangle {
                    id: slotRow
                    required property var modelData
                    readonly property string key: modelData[0]
                    readonly property bool active: themeEdit.fontSlot === key
                    width: slotColumn.width; height: 92
                    radius: root.r > 4 ? 10 : 0
                    color: active ? Color.withAlpha(theme.c.accent, 0.16) : Color.withAlpha(theme.c.bg2, 0.9)
                    border.color: active ? (theme.c.accent || "white") : Color.withAlpha(theme.c.muted, 0.3)
                    Column {
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 16 }
                        spacing: 4
                        Text {
                            text: slotRow.modelData[1] + " · " + slotRow.modelData[2]
                            font.family: theme.bodyFont; font.pixelSize: 13
                            color: theme.c.muted || "grey"
                        }
                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: themeEdit.editing ? themeEdit.font(slotRow.key) : ""
                            font.family: text; font.pixelSize: 22
                            color: theme.c.fg || "white"
                        }
                        Text {
                            readonly property bool own: !themeEdit.editing || !themeEdit.edit.fonts[slotRow.key]
                            text: own ? "как в теме" : "свой выбор"
                            font.family: theme.bodyFont; font.pixelSize: 12
                            color: own ? (theme.c.muted || "grey") : (theme.c.accent || "white")
                        }
                    }
                    MouseArea { anchors.fill: parent; onClicked: themeEdit.fontSlot = slotRow.key }
                }
            }
            Chip {
                text: "Как в теме"
                enabled: themeEdit.editing !== null && !!themeEdit.edit.fonts[themeEdit.fontSlot]
                onClicked: themeEdit.chooseFont("")
            }
        }

        Field {
            id: fontSearch
            anchors { left: slotColumn.right; right: parent.right; top: parent.top; leftMargin: 24 }
            placeholder: "Поиск шрифта"
            onTextChanged: themeEdit.fontQuery = text
        }
        ListView {
            anchors { left: fontSearch.left; right: parent.right; top: fontSearch.bottom; bottom: parent.bottom; topMargin: 10 }
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            model: themeEdit.matchingFonts
            delegate: Rectangle {
                id: fontRow
                required property string modelData
                readonly property bool picked: themeEdit.editing !== null && themeEdit.font(themeEdit.fontSlot) === modelData
                width: ListView.view.width; height: 44
                radius: root.r > 4 ? 8 : 0
                color: picked ? Color.withAlpha(theme.c.accent, 0.22)
                       : (rowArea.containsMouse ? Color.withAlpha(theme.c.accent, 0.1) : "transparent")
                Text {
                    anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                    text: fontRow.modelData
                    font.family: theme.bodyFont; font.pixelSize: 14
                    color: theme.c.fg || "white"
                }
                Text {
                    anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                    text: "Аа Бб Вв 0123"
                    font.family: fontRow.modelData; font.pixelSize: 18
                    color: fontRow.picked ? (theme.c.accent || "white") : (theme.c.muted || "grey")
                }
                MouseArea { id: rowArea; anchors.fill: parent; hoverEnabled: true; onClicked: themeEdit.chooseFont(fontRow.modelData) }
            }
        }
    }

    // The ten palette colours on the left, the picker for the chosen one on the right, and a strip
    // drawn in the edited colours to see them together.
    component ColorsSection: Item {
        Column {
            id: colorColumn
            anchors { left: parent.left; top: parent.top }
            width: 400
            spacing: 6
            Repeater {
                model: themeEdit.colorNames
                Rectangle {
                    id: colorRow
                    required property var modelData
                    readonly property string key: modelData[0]
                    readonly property bool active: themeEdit.colorKey === key
                    width: colorColumn.width; height: 44
                    radius: root.r > 4 ? 8 : 0
                    color: active ? Color.withAlpha(theme.c.accent, 0.16) : (colorRowArea.containsMouse ? Color.withAlpha(theme.c.accent, 0.08) : "transparent")
                    border.color: active ? (theme.c.accent || "white") : "transparent"
                    Rectangle {
                        id: swatch
                        anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                        width: 28; height: 28; radius: 6
                        color: themeEdit.editing ? themeEdit.color(colorRow.key) : "transparent"
                        border.color: Color.withAlpha(theme.c.fg, 0.4)
                    }
                    Text {
                        anchors { left: swatch.right; leftMargin: 12; verticalCenter: parent.verticalCenter }
                        text: colorRow.modelData[1]
                        font.family: theme.bodyFont; font.pixelSize: 15
                        color: theme.c.fg || "white"
                    }
                    Text {
                        anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        readonly property bool own: !themeEdit.editing || !themeEdit.edit.colors[colorRow.key]
                        text: (themeEdit.editing ? themeEdit.color(colorRow.key) : "") + (own ? "" : "  · свой")
                        font.family: theme.font; font.pixelSize: 13
                        color: own ? (theme.c.muted || "grey") : (theme.c.accent || "white")
                    }
                    MouseArea { id: colorRowArea; anchors.fill: parent; hoverEnabled: true; onClicked: themeEdit.colorKey = colorRow.key }
                }
            }
        }

        ColorPicker {
            id: picker
            anchors { left: colorColumn.right; top: parent.top; leftMargin: 28 }
            value: themeEdit.editing ? themeEdit.color(themeEdit.colorKey) : "#000000"
            onPicked: hex => themeEdit.chooseColor(hex)
        }
        Chip {
            anchors { left: picker.left; top: picker.bottom; topMargin: 12 }
            text: "Как в теме"
            enabled: themeEdit.editing !== null && !!themeEdit.edit.colors[themeEdit.colorKey]
            onClicked: themeEdit.ownColor()
        }

        // Folder colour (Papirus only: papirus-folders recolours its folder icons).
        Text {
            id: folderTitle
            anchors { left: picker.left; top: picker.bottom; topMargin: 64 }
            text: themeEdit.iconThemeNow().startsWith("Papirus")
                  ? "Цвет папок" + (themeEdit.editing && !themeEdit.edit.folders ? "  · как в теме: " + (themeEdit.editing.own.folders || "стандартный") : "")
                  : "Цвет папок меняется только у тем значков Papirus (тема значков — в разделе «Значки»)"
            font.family: theme.bodyFont; font.pixelSize: 14; font.bold: true
            color: theme.c.fg || "white"
        }
        Flow {
            visible: themeEdit.iconThemeNow().startsWith("Papirus")
            anchors { left: picker.left; right: parent.right; top: folderTitle.bottom; topMargin: 8 }
            spacing: 4
            Repeater {
                model: themeEdit.folderColors
                Rectangle {
                    id: folderCell
                    required property string modelData
                    readonly property bool chosen: themeEdit.editing !== null
                        && (themeEdit.edit.folders || themeEdit.editing.own.folders) === modelData
                    width: 44; height: 44
                    radius: 8
                    color: chosen ? Color.withAlpha(theme.c.accent, 0.25) : (folderArea.containsMouse ? Color.withAlpha(theme.c.accent, 0.1) : "transparent")
                    border.color: chosen ? (theme.c.accent || "white") : "transparent"
                    Image {
                        anchors.centerIn: parent
                        width: 32; height: 32
                        sourceSize: Qt.size(64, 64)
                        source: "file:///usr/share/icons/Papirus/48x48/places/folder-" + folderCell.modelData + ".svg"
                    }
                    MouseArea {
                        id: folderArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: themeEdit.change("folders", folderCell.modelData === themeEdit.editing.own.folders ? "" : folderCell.modelData)
                    }
                }
            }
        }

        // A little bar in the edited colours.
        Rectangle {
            anchors { left: picker.left; right: parent.right; bottom: parent.bottom }
            height: 64
            radius: root.r > 4 ? 12 : 0
            readonly property var c: {
                const colors = {};
                if (themeEdit.editing)
                    for (const [key] of themeEdit.colorNames) colors[key] = themeEdit.color(key);
                return colors;
            }
            color: c.bg || "black"
            border.color: c.accent || "white"
            Row {
                anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter }
                spacing: 14
                Rectangle { width: 30; height: 30; radius: 15; color: parent.parent.c.accent || "white"; anchors.verticalCenter: parent.verticalCenter }
                Text { text: "Текст"; color: parent.parent.c.fg || "white"; font.family: theme.bodyFont; font.pixelSize: 16; anchors.verticalCenter: parent.verticalCenter }
                Text { text: "приглушённый"; color: parent.parent.c.muted || "grey"; font.family: theme.bodyFont; font.pixelSize: 16; anchors.verticalCenter: parent.verticalCenter }
                Rectangle {
                    width: 120; height: 34; radius: 8; color: parent.parent.c.bg2 || "black"
                    anchors.verticalCenter: parent.verticalCenter
                    Text { anchors.centerIn: parent; text: "кнопка"; color: parent.parent.parent.c.accent2 || "white"; font.family: theme.bodyFont; font.pixelSize: 15 }
                }
                Text { text: "ок"; color: parent.parent.c.good || "green"; font.family: theme.bodyFont; font.pixelSize: 16; anchors.verticalCenter: parent.verticalCenter }
                Text { text: "внимание"; color: parent.parent.c.warn || "yellow"; font.family: theme.bodyFont; font.pixelSize: 16; anchors.verticalCenter: parent.verticalCenter }
                Text { text: "ошибка"; color: parent.parent.c.crit || "red"; font.family: theme.bodyFont; font.pixelSize: 16; anchors.verticalCenter: parent.verticalCenter }
            }
        }
    }

    // Saturation and value in the square, hue in the bar below, and the hex code. value comes in;
    // picked(hex) goes out on every change the user makes.
    component ColorPicker: Column {
        id: cp
        property string value: "#000000"
        property real hue: 0
        property real saturation: 0
        property real brightness: 0
        signal picked(string hex)
        spacing: 12
        onValueChanged: load(value)
        Component.onCompleted: load(value)

        function load(hex) {
            const c = Qt.color(hex);
            if (c.hsvHue >= 0) cp.hue = c.hsvHue;
            cp.saturation = c.hsvSaturation;
            cp.brightness = c.hsvValue;
            hexField.text = hex;
        }
        function pick() {
            const hex = Qt.hsva(cp.hue, cp.saturation, cp.brightness, 1).toString();
            hexField.text = hex;
            cp.picked(hex);
        }

        Rectangle {
            id: square
            width: 320; height: 220
            radius: 6
            color: Qt.hsva(cp.hue, 1, 1, 1)
            Rectangle {
                anchors.fill: parent; radius: parent.radius
                gradient: Gradient { orientation: Gradient.Horizontal; GradientStop { position: 0; color: "white" } GradientStop { position: 1; color: "transparent" } }
            }
            Rectangle {
                anchors.fill: parent; radius: parent.radius
                gradient: Gradient { GradientStop { position: 0; color: "transparent" } GradientStop { position: 1; color: "black" } }
            }
            Rectangle {
                x: cp.saturation * parent.width - 8; y: (1 - cp.brightness) * parent.height - 8
                width: 16; height: 16; radius: 8
                color: "transparent"; border.color: "white"; border.width: 2
            }
            MouseArea {
                anchors.fill: parent
                function set(mouse) {
                    cp.saturation = Math.max(0, Math.min(1, mouse.x / width));
                    cp.brightness = Math.max(0, Math.min(1, 1 - mouse.y / height));
                    cp.pick();
                }
                onPressed: mouse => set(mouse)
                onPositionChanged: mouse => set(mouse)
            }
        }
        Rectangle {
            width: square.width; height: 22
            radius: 6
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "#ff0000" }
                GradientStop { position: 0.17; color: "#ffff00" }
                GradientStop { position: 0.33; color: "#00ff00" }
                GradientStop { position: 0.5; color: "#00ffff" }
                GradientStop { position: 0.67; color: "#0000ff" }
                GradientStop { position: 0.83; color: "#ff00ff" }
                GradientStop { position: 1.0; color: "#ff0000" }
            }
            Rectangle {
                x: cp.hue * parent.width - 3; y: -3
                width: 6; height: parent.height + 6; radius: 3
                color: "white"; border.color: "black"
            }
            MouseArea {
                anchors.fill: parent
                function set(mouse) {
                    cp.hue = Math.max(0, Math.min(0.999, mouse.x / width));
                    cp.pick();
                }
                onPressed: mouse => set(mouse)
                onPositionChanged: mouse => set(mouse)
            }
        }
        Row {
            spacing: 10
            Rectangle { width: 34; height: 34; radius: 8; color: cp.value; border.color: Color.withAlpha(theme.c.fg, 0.4) }
            Field {
                id: hexField
                width: 140
                placeholder: "#rrggbb"
                onAccepted: {
                    if (/^#[0-9a-fA-F]{6}$/.test(text)) cp.picked(text.toLowerCase());
                }
            }
        }
    }

    // The waybar layout as a bar to drag modules around on: within the bar to move them, off the bar to
    // take them away, from the set below onto it to add them. Saved for this theme with «Сохранить»
    // above, or for every theme with the button here.
    component PanelSection: Item {
        id: panelEditor
        property var drag: null      // the module being dragged: {module, side, index}; side "" from the set below
        property var target: null    // where letting go puts it: {side, index, x}; null off the bar, which takes it away
        property var pressedAt: null  // where the drag began: a release close to it is a click, which picks an icon
        property string iconHovered: ""
        readonly property var foundIcons: {
            const words = themeEdit.iconQuery.toLowerCase().split(/\s+/).filter(word => word);
            if (!words.length) return themeEdit.allIcons;
            return themeEdit.allIcons.filter(([, name]) => words.every(word => name.includes(word)));
        }
        property string hovered: ""
        readonly property var sideNames: ({ "modules-left": "слева", "modules-center": "по центру",
                                            "modules-right": "справа" })

        function row(side) {
            return side === "modules-left" ? leftRow : side === "modules-center" ? centerRow : rightRow;
        }
        function pills(side) {
            const list = [];
            for (const child of panelEditor.row(side).children)
                if (child.pillModule !== undefined) list.push(child);
            return list;
        }
        // Every place a module can go, in the bar's coordinates: each gap of each group, a group's two
        // ends, and the bar's middle while the centre group is empty. A drop takes the nearest one.
        function slots() {
            const list = [];
            for (const [side] of themeEdit.sides) {
                const pills = panelEditor.pills(side);
                if (!pills.length) {
                    const x = side === "modules-left" ? 16 : side === "modules-right" ? mockBar.width - 16 : mockBar.width / 2;
                    list.push({ side: side, index: 0, x: x });
                    continue;
                }
                const row = panelEditor.row(side);
                for (let i = 0; i <= pills.length; i++) {
                    const edge = i < pills.length ? pills[i].x - 3 : pills[i - 1].x + pills[i - 1].width + 3;
                    list.push({ side: side, index: i, x: row.mapToItem(mockBar, edge, 0).x });
                }
            }
            return list;
        }
        function start(module, side, index, point) {
            panelEditor.drag = { module: module, side: side, index: index };
            panelEditor.pressedAt = point;
            panelEditor.follow(point);
        }
        // point is in panelEditor's coordinates.
        function follow(point) {
            if (panelEditor.pressedAt && Math.hypot(point.x - panelEditor.pressedAt.x, point.y - panelEditor.pressedAt.y) > 6)
                panelEditor.pressedAt = null;
            ghost.x = point.x - ghost.width / 2;
            ghost.y = point.y - ghost.height / 2;
            const onBar = mockBar.mapFromItem(panelEditor, point.x, point.y);
            if (onBar.y < -30 || onBar.y > mockBar.height + 30) {
                panelEditor.target = null;
                return;
            }
            let nearest = null;
            for (const slot of panelEditor.slots())
                if (!nearest || Math.abs(slot.x - onBar.x) < Math.abs(nearest.x - onBar.x)) nearest = slot;
            panelEditor.target = nearest;
        }
        function finish() {
            const drag = panelEditor.drag;
            const target = panelEditor.target;
            const click = panelEditor.pressedAt !== null;
            panelEditor.drag = null;
            panelEditor.target = null;
            panelEditor.pressedAt = null;
            if (click) {
                if (drag && drag.side && themeEdit.iconEditable(drag.module)) themeEdit.openIconPicker(drag.module);
                return;
            }
            if (!drag || (!drag.side && !target)) return;
            const layout = themeEdit.panelCopy();
            if (drag.side) layout[drag.side].splice(drag.index, 1);
            if (target) {
                let index = target.index;
                if (drag.side === target.side && drag.index < index) index--;  // it was taken out above
                layout[target.side] = (layout[target.side] || []);
                layout[target.side].splice(index, 0, drag.module);
            }
            // After this release handler: the dragged module's own delegate goes away with the change,
            // and an item replaced while it still holds the mouse grab can stay drawn where it was.
            Qt.callLater(() => themeEdit.change("waybar", layout));
        }

        Row {
            id: panelTop
            spacing: 10
            TabButton { text: "Раскладка"; active: themeEdit.panelView === "layout"; onClicked: themeEdit.panelView = "layout" }
            TabButton { text: "Значки модулей"; active: themeEdit.panelView === "icons"; onClicked: themeEdit.panelView = "icons" }
            Item { width: 16; height: 1 }
            Chip { text: "Сверху"; active: themeEdit.editing !== null && themeEdit.panel().position !== "bottom"; onClicked: themeEdit.setPosition("top") }
            Chip { text: "Снизу"; active: themeEdit.editing !== null && themeEdit.panel().position === "bottom"; onClicked: themeEdit.setPosition("bottom") }
            Item { width: 16; height: 1 }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: !themeEdit.editing ? ""
                      : themeEdit.edit.waybar ? "своя раскладка у этой темы"
                      : themeEdit.everywhere.waybar ? "общая раскладка для всех тем" : "как в теме"
                font.family: theme.bodyFont; font.pixelSize: 13
                color: theme.c.accent || "white"
            }
        }
        Row {
            anchors { right: parent.right; verticalCenter: panelTop.verticalCenter }
            spacing: 10
            Chip {
                visible: themeEdit.editing !== null && !!themeEdit.everywhere.waybar
                text: "Убрать общую раскладку"
                onClicked: themeEdit.dropSharedPanel()
            }
            Chip { text: "Сохранить для всех тем"; onClicked: themeEdit.savePanelEverywhere() }
        }
        Text {
            id: panelHint
            anchors { left: parent.left; top: panelTop.bottom; topMargin: 14 }
            text: "Перетаскивай модули: по панели — переставить, с панели вниз — убрать, из набора снизу на панель — добавить. "
                  + "Значки меняются во вкладке «Значки модулей» или нажатием на модуль."
                  + (barPreviewProc.running ? "   · обновляю данные панели…" : "")
            font.family: theme.bodyFont; font.pixelSize: 13
            color: theme.c.muted || "grey"
        }

        Rectangle {
            id: mockBar
            anchors { left: parent.left; right: parent.right; top: panelHint.bottom; topMargin: 22 }
            height: 54
            radius: Math.min(theme.ui.radius ?? 12, 16)
            color: Color.withAlpha(theme.c.bg, 0.95)
            border.width: panelEditor.target ? 2 : 1
            border.color: panelEditor.target ? (theme.c.accent || "white") : Color.withAlpha(theme.c.accent, 0.4)

            // The empty centre group, as a place to drop on while dragging.
            Rectangle {
                visible: panelEditor.drag !== null && (themeEdit.panel()["modules-center"] || []).length === 0
                anchors.centerIn: parent
                width: 110; height: parent.height - 14
                radius: 8
                color: Color.withAlpha(theme.c.accent, 0.08)
                border.color: Color.withAlpha(theme.c.accent, 0.4)
                Text {
                    anchors.centerIn: parent
                    text: "центр"
                    font.family: theme.bodyFont; font.pixelSize: 12
                    color: theme.c.muted || "grey"
                }
            }
            Row {
                id: leftRow
                anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                spacing: 6
                Repeater {
                    model: themeEdit.editing ? (themeEdit.panel()["modules-left"] || []) : []
                    BarModule { editor: panelEditor; side: "modules-left" }
                }
            }
            Row {
                id: centerRow
                anchors.centerIn: parent
                spacing: 6
                Repeater {
                    model: themeEdit.editing ? (themeEdit.panel()["modules-center"] || []) : []
                    BarModule { editor: panelEditor; side: "modules-center" }
                }
            }
            Row {
                id: rightRow
                anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                spacing: 6
                Repeater {
                    model: themeEdit.editing ? (themeEdit.panel()["modules-right"] || []) : []
                    BarModule { editor: panelEditor; side: "modules-right" }
                }
            }
            Rectangle {
                id: dropMarker
                visible: panelEditor.target !== null
                x: panelEditor.target ? panelEditor.target.x - 1 : 0; y: 6
                width: 3; height: parent.height - 12; radius: 1
                color: theme.c.accent || "white"
                Text {
                    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.top; bottomMargin: 10 }
                    text: panelEditor.target ? panelEditor.sideNames[panelEditor.target.side] : ""
                    font.family: theme.bodyFont; font.pixelSize: 12; font.bold: true
                    color: theme.c.accent || "white"
                }
            }
        }
        Text {
            id: hoveredName
            anchors { left: parent.left; top: mockBar.bottom; topMargin: 30 }
            text: panelEditor.drag ? (panelEditor.target ? "Отпусти — встанет " + panelEditor.sideNames[panelEditor.target.side]
                                                          : panelEditor.drag.side ? "Отпусти здесь, чтобы убрать с панели" : "Тащи на панель")
                  : panelEditor.hovered ? themeEdit.moduleName(panelEditor.hovered)
                                          + (themeEdit.moduleNote(panelEditor.hovered) ? " — " + themeEdit.moduleNote(panelEditor.hovered) : "")
                                          + (themeEdit.iconEditable(panelEditor.hovered) ? " · нажми — сменить значок, тащи — переставить"
                                                                                         : " · тащи — переставить; значок не меняется")
                  : " "
            font.family: theme.bodyFont; font.pixelSize: 14
            color: panelEditor.drag && panelEditor.drag.side && !panelEditor.target ? (theme.c.crit || "red") : (theme.c.fg || "white")
        }

        Text {
            id: setTitle
            anchors { left: parent.left; top: hoveredName.bottom; topMargin: 22 }
            text: "Можно добавить"
            font.family: theme.bodyFont; font.pixelSize: 14; font.bold: true
            color: theme.c.fg || "white"
        }
        Flow {
            anchors { left: parent.left; right: parent.right; top: setTitle.bottom; topMargin: 10 }
            spacing: 8
            Repeater {
                model: themeEdit.editing ? themeEdit.editing.waybar.available.filter(module => !themeEdit.onPanel(module)) : []
                BarModule { editor: panelEditor; side: ""; showName: true }
            }
        }

        // The modules on the bar with their icons, one «Сменить» each.
        Rectangle {
            visible: themeEdit.panelView === "icons"
            anchors { left: parent.left; right: parent.right; top: panelTop.bottom; bottom: parent.bottom; topMargin: 14 }
            z: 15
            color: theme.c.bg || "black"
            MouseArea { anchors.fill: parent }
            ListView {
                anchors.fill: parent
                clip: true
                spacing: 4
                boundsBehavior: Flickable.StopAtBounds
                model: themeEdit.editing ? themeEdit.sides.reduce((all, [side]) => all.concat(themeEdit.panel()[side] || []), []) : []
                delegate: Rectangle {
                    id: iconRow
                    required property string modelData
                    readonly property bool editable: themeEdit.iconEditable(modelData)
                    width: ListView.view.width; height: 50
                    radius: root.r > 4 ? 8 : 0
                    color: Color.withAlpha(theme.c.bg2, 0.9)
                    Text {
                        id: rowIcon
                        x: 16; anchors.verticalCenter: parent.verticalCenter
                        width: 36
                        text: themeEdit.iconOf(iconRow.modelData) || "·"
                        font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 22
                        color: theme.c.fg || "white"
                    }
                    Text {
                        anchors { left: rowIcon.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
                        text: themeEdit.moduleName(iconRow.modelData)
                              + (themeEdit.edit.icons && themeEdit.edit.icons[iconRow.modelData] ? "  · свой значок" : "")
                              + (iconRow.editable ? "" : "  · значок не меняется: он показывает состояние или его рисует скрипт")
                        font.family: theme.bodyFont; font.pixelSize: 15
                        color: iconRow.editable ? (theme.c.fg || "white") : (theme.c.muted || "grey")
                    }
                    Chip {
                        visible: iconRow.editable
                        anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        text: "Сменить"
                        onClicked: themeEdit.openIconPicker(iconRow.modelData)
                    }
                }
            }
        }

        // The icon picker for themeEdit.iconFor: every icon of the font, searched by name. A click
        // chooses, «Применить» sets it; «Отмена» or Esc leave the icon as it was.
        Rectangle {
            visible: themeEdit.iconFor !== ""
            anchors.fill: parent
            z: 20
            color: theme.c.bg || "black"
            onVisibleChanged: if (visible) iconSearch.text = themeEdit.iconQuery
            MouseArea { anchors.fill: parent }
            Row {
                id: pickerTop
                spacing: 12
                SectionTitle {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Значок: " + themeEdit.moduleName(themeEdit.iconFor)
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: (themeEdit.iconOf(themeEdit.iconFor) || "·") + "  →  "
                          + (themeEdit.iconChoice || (themeEdit.editing ? (Array.from(themeEdit.editing.waybar.preview[themeEdit.iconFor] || "")[0] || "·") : ""))
                    font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 24
                    color: theme.c.accent || "white"
                }
                Field {
                    id: iconSearch
                    anchors.verticalCenter: parent.verticalCenter
                    width: 300
                    placeholder: "поиск по-английски: volume, cpu, wifi…"
                    onTextChanged: themeEdit.iconQuery = text
                }
            }
            Row {
                anchors { right: parent.right; verticalCenter: pickerTop.verticalCenter }
                spacing: 10
                Chip { text: "Как в теме"; active: themeEdit.iconChoice === ""; onClicked: themeEdit.iconChoice = "" }
                Chip { text: "Отмена"; onClicked: themeEdit.iconFor = "" }
                Chip { text: "Применить"; primary: true; onClicked: themeEdit.applyIcon() }
            }
            Text {
                id: pickerStatus
                anchors { left: parent.left; top: pickerTop.bottom; topMargin: 10 }
                text: !themeEdit.allIcons.length ? "загружаю значки шрифта…"
                      : panelEditor.foundIcons.length + " значков · нажми, чтобы выбрать, двойной щелчок — сразу применить"
                        + (panelEditor.iconHovered ? " · " + panelEditor.iconHovered : "")
                        + (["pulseaudio", "temperature", "backlight", "battery"].includes(themeEdit.iconFor)
                           ? " · у этого модуля значок меняется по уровню, свой будет один на все уровни" : "")
                font.family: theme.bodyFont; font.pixelSize: 13
                color: theme.c.muted || "grey"
            }
            GridView {
                anchors { left: parent.left; right: parent.right; top: pickerStatus.bottom; bottom: parent.bottom; topMargin: 10 }
                clip: true
                cellWidth: 52; cellHeight: 52
                boundsBehavior: Flickable.StopAtBounds
                model: panelEditor.foundIcons
                delegate: Rectangle {
                    id: iconCell
                    required property var modelData
                    readonly property bool picked: themeEdit.iconChoice === modelData[0]
                    width: 48; height: 48
                    radius: 8
                    color: picked ? Color.withAlpha(theme.c.accent, 0.3)
                           : (cellArea.containsMouse ? Color.withAlpha(theme.c.accent, 0.14) : Color.withAlpha(theme.c.bg2, 0.8))
                    border.color: picked ? (theme.c.accent || "white") : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: iconCell.modelData[0]
                        font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 24
                        color: iconCell.picked ? (theme.c.accent || "white") : (theme.c.fg || "white")
                    }
                    MouseArea {
                        id: cellArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: panelEditor.iconHovered = iconCell.modelData[1]
                        onClicked: themeEdit.iconChoice = iconCell.modelData[0]
                        onDoubleClicked: {
                            themeEdit.iconChoice = iconCell.modelData[0];
                            themeEdit.applyIcon();
                        }
                    }
                }
            }
        }

        // What follows the pointer while dragging.
        Rectangle {
            id: ghost
            visible: panelEditor.drag !== null
            z: 10
            width: ghostText.implicitWidth + 24; height: 38
            radius: 8
            color: Color.withAlpha(theme.c.bg2, 0.95)
            border.color: theme.c.accent || "white"
            Text {
                id: ghostText
                anchors.centerIn: parent
                text: panelEditor.drag ? (themeEdit.preview(panelEditor.drag.module) || themeEdit.moduleName(panelEditor.drag.module)) : ""
                font.family: theme.font; font.pixelSize: 16
                color: theme.c.fg || "white"
            }
        }
    }

    // One module as it looks on the bar; drag it. With showName (the set below the bar) its name is
    // written next to it.
    component BarModule: Rectangle {
        id: barModule
        required property string modelData
        required property int index
        property var editor
        property string side
        property bool showName: false
        readonly property string pillModule: modelData
        readonly property bool lifted: editor.drag !== null && editor.drag.side === side && editor.drag.index === index && side !== ""
        readonly property string shows: themeEdit.moduleState(modelData)  // shown, sometimes or missing
        readonly property bool tray: modelData === "tray"
        width: moduleContent.implicitWidth + 22; height: 36
        radius: 8
        color: moduleArea.containsMouse ? Color.withAlpha(theme.c.accent, 0.18) : Color.withAlpha(theme.c.bg2, 0.9)
        border.color: shows === "missing" ? Color.withAlpha(theme.c.crit, 0.6) : Color.withAlpha(theme.c.muted, 0.3)
        opacity: lifted ? 0.25 : shows === "missing" ? 0.4 : shows === "sometimes" ? 0.6 : 1
        Row {
            id: moduleContent
            anchors.centerIn: parent
            spacing: 6
            // The tray's real icons; waybar draws nothing for an empty tray.
            Repeater {
                model: barModule.tray ? SystemTray.items : []
                IconImage {
                    required property var modelData
                    anchors.verticalCenter: parent.verticalCenter
                    implicitSize: 16
                    source: modelData.icon
                }
            }
            // The theme's battery icon, which its CSS puts in front of the percentage.
            Image {
                visible: barModule.modelData === "custom/battery" && themeEdit.editing !== null
                anchors.verticalCenter: parent.verticalCenter
                width: visible ? 16 : 0; height: 16
                sourceSize: Qt.size(32, 32)
                source: visible ? "file://" + themeEdit.editing.dir + "/assets/battery-0.svg" : ""
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: (barModule.tray && SystemTray.items.values.length === 0 ? "трей пуст"
                       : barModule.tray ? "" : themeEdit.preview(barModule.modelData))
                      + (barModule.showName ? "  " + themeEdit.moduleName(barModule.modelData) : "")
                visible: text !== ""
                font.family: theme.font; font.pixelSize: 15
                color: theme.c.fg || "white"
            }
        }
        Text {
            visible: moduleArea.containsMouse && barModule.side !== "" && themeEdit.iconEditable(barModule.modelData)
            anchors { right: parent.right; top: parent.top; rightMargin: -5; topMargin: -7 }
            text: "\u{f03eb}"  // md-pencil
            font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 13
            color: theme.c.accent || "white"
        }
        MouseArea {
            id: moduleArea
            anchors.fill: parent
            hoverEnabled: true
            preventStealing: true
            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            onEntered: barModule.editor.hovered = barModule.modelData
            onExited: if (barModule.editor.hovered === barModule.modelData) barModule.editor.hovered = ""
            onPressed: mouse => barModule.editor.start(barModule.modelData, barModule.side, barModule.index,
                                                       mapToItem(barModule.editor, mouse.x, mouse.y))
            onPositionChanged: mouse => { if (pressed) barModule.editor.follow(mapToItem(barModule.editor, mouse.x, mouse.y)); }
            onReleased: barModule.editor.finish()
        }
    }

    // The icon theme of GTK programs (installed ones with samples, missing ones to install) on the left,
    // the battery drawing (any theme's, in this theme's colours) on the right.
    component IconsSection: Item {
        SectionTitle {
            id: iconThemeTitle
            text: "Тема значков"
        }
        Text {
            anchors { left: iconThemeTitle.right; leftMargin: 12; verticalCenter: iconThemeTitle.verticalCenter }
            text: themeEdit.editing && !themeEdit.edit.iconTheme ? "как в теме: " + themeEdit.themesIconTheme() : ""
            font.family: theme.bodyFont; font.pixelSize: 13
            color: theme.c.muted || "grey"
        }
        ListView {
            id: iconThemeList
            anchors { left: parent.left; top: iconThemeTitle.bottom; bottom: parent.bottom; topMargin: 10 }
            width: parent.width * 0.58
            clip: true
            spacing: 4
            boundsBehavior: Flickable.StopAtBounds
            model: themeEdit.iconThemes.installed.concat(themeEdit.iconThemes.downloadable.filter(item => !item.installed))
            delegate: Rectangle {
                id: themeRow
                required property var modelData
                readonly property bool installed: modelData.name !== undefined
                readonly property bool chosen: installed && themeEdit.iconThemeNow() === modelData.name
                width: ListView.view.width; height: 52
                radius: root.r > 4 ? 8 : 0
                color: chosen ? Color.withAlpha(theme.c.accent, 0.2) : (rowHover.containsMouse ? Color.withAlpha(theme.c.accent, 0.08) : Color.withAlpha(theme.c.bg2, 0.9))
                border.color: chosen ? (theme.c.accent || "white") : "transparent"
                MouseArea {
                    id: rowHover
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: themeRow.installed
                    onClicked: themeEdit.change("iconTheme", themeRow.modelData.name === themeEdit.themesIconTheme() ? "" : themeRow.modelData.name)
                }
                Text {
                    id: themeName
                    x: 14; anchors.verticalCenter: parent.verticalCenter
                    width: 190
                    elide: Text.ElideRight
                    text: themeRow.installed ? themeRow.modelData.label : themeRow.modelData.title
                    font.family: theme.bodyFont; font.pixelSize: 15
                    color: theme.c.fg || "white"
                }
                Row {
                    visible: themeRow.installed
                    anchors { left: themeName.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
                    spacing: 8
                    Repeater {
                        model: themeRow.installed ? themeRow.modelData.previews : []
                        Image {
                            required property string modelData
                            width: 28; height: 28
                            sourceSize: Qt.size(56, 56)
                            source: "file://" + modelData
                            asynchronous: true
                        }
                    }
                }
                Text {
                    visible: !themeRow.installed
                    anchors { left: themeName.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
                    text: themeRow.installed ? "" : (themeRow.modelData.source === "aur" ? "из AUR" : "из репозитория") + " · не установлена"
                    font.family: theme.bodyFont; font.pixelSize: 13
                    color: theme.c.muted || "grey"
                }
                Chip {
                    visible: !themeRow.installed
                    anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    text: "Установить"
                    enabled: !installProc.running
                    onClicked: themeEdit.askInstall(themeRow.modelData)
                }
            }
        }
        Text {
            visible: !themeEdit.iconThemes.installed.length
            anchors { left: iconThemeList.left; top: iconThemeList.top }
            text: "читаю темы значков…"
            font.family: theme.bodyFont; font.pixelSize: 13
            color: theme.c.muted || "grey"
        }

        SectionTitle {
            id: batteryTitle
            anchors { left: iconThemeList.right; leftMargin: 28 }
            text: "Рисунок батареи"
        }
        Text {
            id: batteryNote
            anchors { left: batteryTitle.left; top: batteryTitle.bottom; topMargin: 4 }
            text: "у любой темы, в цветах этой; анимация — та, что у рисунка"
            font.family: theme.bodyFont; font.pixelSize: 13
            color: theme.c.muted || "grey"
        }
        Flow {
            anchors { left: batteryTitle.left; right: parent.right; top: batteryNote.bottom; topMargin: 12 }
            spacing: 10
            Repeater {
                model: root.themes
                Rectangle {
                    id: batteryCell
                    required property var modelData
                    readonly property bool chosen: themeEdit.editing !== null
                        && (themeEdit.edit.battery || themeEdit.editing.name) === modelData.name
                    width: 96; height: 92
                    radius: root.r > 4 ? 10 : 0
                    color: chosen ? Color.withAlpha(theme.c.accent, 0.2) : (batteryArea.containsMouse ? Color.withAlpha(theme.c.accent, 0.08) : Color.withAlpha(theme.c.bg2, 0.9))
                    border.color: chosen ? (theme.c.accent || "white") : "transparent"
                    Image {
                        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 12 }
                        width: 40; height: 40
                        sourceSize: Qt.size(80, 80)
                        source: "file://" + batteryCell.modelData.dir + "/assets/battery-0.svg"
                    }
                    Text {
                        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 10 }
                        text: batteryCell.modelData.pal.label
                        font.family: theme.bodyFont; font.pixelSize: 12
                        color: theme.c.fg || "white"
                    }
                    MouseArea {
                        id: batteryArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: themeEdit.change("battery", batteryCell.modelData.name === themeEdit.editing.name ? "" : batteryCell.modelData.name)
                    }
                }
            }
        }
    }

    // Hyprland's windows: sliders on the left, two windows drawn with those values on the right.
    component WindowsSection: Item {
        Column {
            id: windowControls
            width: 700
            spacing: 10
            Repeater {
                model: themeEdit.windowSettings
                Item {
                    id: settingRow
                    required property var modelData
                    readonly property string key: modelData[0]
                    readonly property bool percent: modelData[5] === "%"
                    readonly property bool edited: themeEdit.editing !== null && settingRow.key in themeEdit.edit.windows
                    width: windowControls.width; height: 34
                    function shown(value) {
                        return settingRow.percent ? Math.round(value * 100) + "%" : value + (settingRow.modelData[5] ? " " + settingRow.modelData[5] : "");
                    }
                    Text {
                        width: 250; anchors.verticalCenter: parent.verticalCenter
                        text: settingRow.modelData[1]
                        font.family: theme.bodyFont; font.pixelSize: 14
                        color: theme.c.fg || "white"
                    }
                    NumberSlider {
                        id: rowSlider
                        x: 255; width: 200; anchors.verticalCenter: parent.verticalCenter
                        from: settingRow.modelData[2]; to: settingRow.modelData[3]; step: settingRow.modelData[4]
                        value: themeEdit.editing ? themeEdit.windowValue(settingRow.key) : 0
                        onMoved: value => themeEdit.setWindow(settingRow.key, value)
                    }
                    Text {
                        x: 470; anchors.verticalCenter: parent.verticalCenter
                        text: themeEdit.editing ? settingRow.shown(themeEdit.windowValue(settingRow.key)) : ""
                        font.family: theme.font; font.pixelSize: 14
                        color: settingRow.edited ? (theme.c.accent || "white") : (theme.c.fg || "white")
                    }
                    Text {
                        x: 535; anchors.verticalCenter: parent.verticalCenter
                        text: settingRow.edited ? "↺ тема: " + settingRow.shown(themeEdit.editing.windows[settingRow.key]) : ""
                        font.family: theme.bodyFont; font.pixelSize: 12
                        color: theme.c.muted || "grey"
                        MouseArea { anchors.fill: parent; onClicked: themeEdit.setWindow(settingRow.key, themeEdit.editing.windows[settingRow.key]) }
                    }
                }
            }
            Row {
                spacing: 8
                Text {
                    width: 250; anchors.verticalCenter: parent.verticalCenter
                    text: "Размытие под окнами"
                    font.family: theme.bodyFont; font.pixelSize: 14
                    color: theme.c.fg || "white"
                }
                Chip { text: "Вкл"; active: themeEdit.editing !== null && !!themeEdit.windowValue("blur"); onClicked: themeEdit.setWindow("blur", true) }
                Chip { text: "Выкл"; active: themeEdit.editing !== null && !themeEdit.windowValue("blur"); onClicked: themeEdit.setWindow("blur", false) }
            }
            Row {
                spacing: 8
                Text {
                    width: 250; anchors.verticalCenter: parent.verticalCenter
                    text: "Анимации"
                    font.family: theme.bodyFont; font.pixelSize: 14
                    color: theme.c.fg || "white"
                }
                Repeater {
                    model: [["", "Как в теме"], ["fast", "Быстрее"], ["slow", "Медленнее"], ["off", "Выключить"]]
                    Chip {
                        required property var modelData
                        text: modelData[1]
                        active: themeEdit.editing !== null && (themeEdit.edit.windows.animations || "") === modelData[0]
                        onClicked: {
                            const windows = Object.assign({}, themeEdit.edit.windows);
                            if (modelData[0]) windows.animations = modelData[0];
                            else delete windows.animations;
                            themeEdit.change("windows", windows);
                        }
                    }
                }
            }
        }

        // Two windows over the theme's wallpaper, at the real gaps, border and rounding.
        Rectangle {
            id: windowsPreview
            anchors { left: windowControls.right; right: parent.right; top: parent.top; leftMargin: 28 }
            height: 320
            radius: 8
            clip: true
            color: theme.c.bg2 || "black"
            Image {
                anchors.fill: parent
                source: themeEdit.editing && themeEdit.editing.thumb ? "file://" + themeEdit.editing.thumb : ""
                fillMode: Image.PreserveAspectCrop
            }
            Repeater {
                model: 2
                Rectangle {
                    required property int index
                    readonly property real outer: themeEdit.editing ? themeEdit.windowValue("gaps_out") : 0
                    readonly property real inner: themeEdit.editing ? themeEdit.windowValue("gaps_in") : 0
                    readonly property real half: (windowsPreview.width - 2 * outer - 2 * inner) / 2
                    x: outer + index * (half + 2 * inner); y: outer + 26
                    width: half; height: windowsPreview.height - 2 * outer - 26
                    radius: themeEdit.editing ? themeEdit.windowValue("rounding") : 0
                    color: Color.withAlpha(theme.c.bg, themeEdit.editing ? themeEdit.windowValue(index === 0 ? "active_opacity" : "inactive_opacity") : 1)
                    border.width: themeEdit.editing ? themeEdit.windowValue("border_size") : 0
                    border.color: index === 0 ? (theme.c.accent || "white") : Color.withAlpha(theme.c.muted, 0.67)
                    Text {
                        anchors.centerIn: parent
                        text: index === 0 ? "активное окно" : "окно"
                        font.family: theme.bodyFont; font.pixelSize: 13
                        color: theme.c.fg || "white"
                    }
                }
            }
            Rectangle {
                x: 8; y: 4; width: parent.width - 16; height: 18; radius: 5
                color: Color.withAlpha(theme.c.bg, 0.85)
                Text {
                    anchors.centerIn: parent
                    text: "панель"
                    font.family: theme.bodyFont; font.pixelSize: 10
                    color: theme.c.muted || "grey"
                }
            }
        }
        Text {
            anchors { left: windowsPreview.left; right: windowsPreview.right; top: windowsPreview.bottom; topMargin: 10 }
            wrapMode: Text.WordWrap
            text: "Образец в настоящих пикселях. Размытие и анимации видны только на экране: сохрани, тема применится заново."
            font.family: theme.bodyFont; font.pixelSize: 12
            color: theme.c.muted || "grey"
        }
    }

    // A number on a track; moved(value) on every drag, rounded to step.
    component NumberSlider: Item {
        id: slider
        property real from: 0
        property real to: 10
        property real step: 1
        property real value: 0
        signal moved(real value)
        implicitHeight: 24
        readonly property real fraction: Math.max(0, Math.min(1, (value - from) / (to - from)))
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width; height: 6; radius: 3
            color: Color.withAlpha(theme.c.bg2, 0.9)
            border.color: Color.withAlpha(theme.c.muted, 0.35)
        }
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: slider.fraction * (parent.width - 18) + 9; height: 6; radius: 3
            color: theme.c.accent || "white"
        }
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            x: slider.fraction * (parent.width - 18)
            width: 18; height: 18; radius: 9
            color: theme.c.accent || "white"
            border.color: theme.c.bg || "black"
        }
        MouseArea {
            anchors.fill: parent
            preventStealing: true
            function set(x) {
                const share = Math.max(0, Math.min(1, (x - 9) / (width - 18)));
                const raw = slider.from + share * (slider.to - slider.from);
                slider.moved(Number((Math.round(raw / slider.step) * slider.step).toFixed(2)));
            }
            onPressed: mouse => set(mouse.x)
            onPositionChanged: mouse => { if (pressed) set(mouse.x); }
        }
    }

    // The wallpapers changetheme picks from: click one to switch it on or off.
    // A moment of a GIF or a video picked with a slider, then kept as one of the theme's wallpapers.
    component FramePicker: Rectangle {
        color: Color.withAlpha(theme.c.bg, 0.92)
        MouseArea { anchors.fill: parent }
        Column {
            anchors.centerIn: parent
            width: Math.min(parent.width - 60, 980)
            spacing: 14
            SectionTitle { text: "Кадр для обоев" }
            Text {
                width: parent.width
                elide: Text.ElideMiddle
                text: userFiles.frameSource
                font.family: theme.font; font.pixelSize: 12
                color: theme.c.muted || "grey"
            }
            Rectangle {
                width: parent.width; height: width * 9 / 16
                radius: root.r > 4 ? 10 : 0
                color: theme.c.bg2 || "black"
                clip: true
                Image {
                    anchors.fill: parent
                    source: userFiles.framePreview ? "file://" + userFiles.framePreview : ""
                    fillMode: Image.PreserveAspectFit
                    cache: false
                }
            }
            Row {
                spacing: 14
                NumberSlider {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 640
                    from: 0; to: userFiles.frameEnd()
                    step: userFiles.frameLength && userFiles.frameLength.kind === "gif" ? 1 : 0.1
                    value: userFiles.frameAt
                    onMoved: value => userFiles.showFrame(value)
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: userFiles.frameLabel()
                    font.family: theme.font; font.pixelSize: 14
                    color: theme.c.fg || "white"
                }
            }
            Row {
                spacing: 10
                Chip {
                    text: "Взять этот кадр"
                    primary: true
                    enabled: userFiles.framePreview !== "" && userFiles.frameInput !== "" && !userFilesProc.running
                    onClicked: userFiles.takeFrame()
                }
                Chip { text: "Отмена"; onClicked: userFiles.closeFrames() }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: userFiles.pickFor === "frames" ? userFiles.message : ""
                    font.family: theme.bodyFont; font.pixelSize: 13
                    color: userFiles.failed ? (theme.c.crit || "red") : (theme.c.muted || "grey")
                }
            }
        }
    }

    component WallpapersSection: Item {
        Row {
            id: wallpaperActions
            spacing: 10
            Chip { text: "Добавить обои"; onClicked: themeEdit.pickWallpaper() }
            Chip { text: "Кадр из GIF или видео…"; enabled: !userFilesProc.running; onClicked: userFiles.pick("frames") }
            Text {
                readonly property bool news: userFiles.pickFor === "frames" && userFiles.message !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: news ? userFiles.message
                           : "Нажми на картинку, чтобы включить или выключить её; при смене темы обои выбираются случайно из включённых."
                font.family: theme.bodyFont; font.pixelSize: 13
                color: news && userFiles.failed ? (theme.c.crit || "red") : (theme.c.muted || "grey")
            }
        }
        GridView {
            anchors { left: parent.left; right: parent.right; top: wallpaperActions.bottom; bottom: parent.bottom; topMargin: 16 }
            clip: true
            cellWidth: 260; cellHeight: 196
            boundsBehavior: Flickable.StopAtBounds
            model: themeEdit.editing ? themeEdit.wallpapers() : []
            delegate: Item {
                id: wallTile
                required property var modelData
                width: 248; height: 184
                Rectangle {
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    height: 140
                    radius: root.r > 4 ? 10 : 0
                    clip: true
                    color: theme.c.bg2 || "black"
                    border.width: 2
                    border.color: wallTile.modelData.on ? (theme.c.accent || "white") : Color.withAlpha(theme.c.muted, 0.3)
                    Image {
                        anchors { fill: parent; margins: 2 }
                        source: "file://" + wallTile.modelData.thumb
                        sourceSize.width: 480
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        opacity: wallTile.modelData.on ? 1 : 0.3
                    }
                    Text {
                        visible: !wallTile.modelData.on
                        anchors.centerIn: parent
                        text: "выключены"
                        font.family: theme.bodyFont; font.pixelSize: 15; font.bold: true
                        color: theme.c.fg || "white"
                    }
                    MouseArea { anchors.fill: parent; onClicked: themeEdit.toggleWallpaper(wallTile.modelData.path) }
                }
                Row {
                    anchors { left: parent.left; bottom: parent.bottom }
                    spacing: 6
                    Chip {
                        visible: themeEdit.editing !== null && themeEdit.editing.current && wallTile.modelData.on
                        text: "Поставить сейчас"
                        onClicked: themeEdit.showWallpaper(wallTile.modelData.path)
                    }
                    Chip {
                        visible: wallTile.modelData.added
                        text: "Убрать"
                        onClicked: themeEdit.removeWallpaper(wallTile.modelData.path)
                    }
                }
            }
        }
    }

    component SectionTitle: Text {
        font.family: theme.titleFont; font.pixelSize: 17; font.bold: true; font.italic: !!theme.ui.italicTitle
        color: theme.c.accent2 || theme.c.accent || "white"
        topPadding: 6
    }

    component Field: Rectangle {
        id: fld
        property alias text: input.text
        property alias echoMode: input.echoMode
        property string placeholder
        signal accepted()
        function focusInput() { input.forceActiveFocus(); }
        height: 34
        radius: root.r > 4 ? 9 : 0
        color: Color.withAlpha(theme.c.bg2, 0.9)
        border.color: input.activeFocus ? (theme.c.accent || "white") : Color.withAlpha(theme.c.muted, 0.35)
        TextInput {
            id: input
            anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
            verticalAlignment: TextInput.AlignVCenter
            font.family: theme.bodyFont; font.pixelSize: 14
            color: theme.c.fg || "white"
            selectionColor: Color.withAlpha(theme.c.accent, 0.4)
            clip: true
            Keys.onEscapePressed: {
                scene.forceActiveFocus();
                if (themeEdit.editing || ownThemes.dialog) root.back();
            }
            onAccepted: fld.accepted()
        }
        Text {
            anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
            visible: !input.text && !input.activeFocus
            text: fld.placeholder
            font.family: theme.bodyFont; font.pixelSize: 14
            color: theme.c.muted || "grey"
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
        color: capturing ? Color.withAlpha(theme.c.accent, 0.15) : Color.withAlpha(theme.c.bg2, 0.6)
        border.color: capturing ? (theme.c.accent || "white") : "transparent"
        Text {
            anchors { left: parent.left; leftMargin: 14; right: rowButtons.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
            text: row.title
            elide: Text.ElideRight
            font.family: theme.bodyFont; font.pixelSize: 14
            color: row.combo ? (theme.c.fg || "white") : (theme.c.muted || "grey")
        }
        Row {
            id: rowButtons
            anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
            spacing: 8
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(110, comboText.implicitWidth + 20); height: 28
                radius: root.r > 4 ? 7 : 0
                color: Color.withAlpha(theme.c.accent, row.combo ? 0.16 : 0.05)
                border.color: Color.withAlpha(theme.c.accent, row.isDefault ? 0.45 : 0.9)
                Text {
                    id: comboText
                    anchors.centerIn: parent
                    text: row.capturing ? "…" : keys.label(row.combo)
                    font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 13
                    color: row.combo ? (theme.c.accent || "white") : (theme.c.muted || "grey")
                }
            }
            Chip { visible: !row.removable; text: "Изменить"; onClicked: row.edit() }
            Chip { visible: !row.removable; text: row.combo ? "Выкл" : "Вкл"; onClicked: row.toggle() }
            Chip { visible: !row.removable && !row.isDefault; text: "Сброс"; onClicked: row.reset() }
            Chip { visible: row.removable; text: "Удалить"; onClicked: row.remove() }
        }
    }
}
