import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

// What the user changes in a theme (fonts, colours, wallpapers, panel, icons, cursor, windows), edited one theme
// at a time and kept in ~/.config/hypr-rice/theme-edits.json, which themegen reads on every theme change. An
// empty value or a missing key keeps the theme's own. Also the lists the sections pick from (installed fonts,
// icon and cursor themes, the font's icons, what the bar shows now) and installing a missing package.
Scope {
    id: themeEdit

    readonly property string path: Files.home + "/.config/hypr-rice/theme-edits.json"
    readonly property string wallpaperDir: Files.home + "/.local/share/hypr-rice/wallpapers"
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
    readonly property var sides: [["modules-left", "Слева"], ["modules-center", "По центру"], ["modules-right", "Справа"]]
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
    readonly property var iconHints: ({
        "pulseaudio": "volume", "cpu": "chip", "memory": "memory", "temperature": "thermometer",
        "backlight": "brightness", "battery": "battery", "bluetooth": "bluetooth", "disk": "harddisk",
        "network": "wifi", "custom/exit": "power", "custom/help": "help", "custom/histui": "bell",
        "custom/settings": "cog", "custom/shots": "image", "custom/theme": "palette"
    })
    readonly property string defaultCursor: "WhiteCat"  // what the rice ships
    readonly property var cursorSizes: [24, 32, 40, 48]

    property var everyTheme: ({})  // the whole file's "themes"
    property var everywhere: ({})  // the whole file's "everywhere": what was saved for all themes
    property var editing: null     // the theme being edited, an entry of ThemeList.themes
    property var edit: ({})        // {fonts, colors, wallpapers: {added, off}, waybar, icons, ...}
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
    // What each module shows on this machine now (themegen.py bar-preview): {module: {text, state, note}}; state is
    // shown, sometimes or missing. Asked for when the «Панель» section opens; until it comes, the modules show
    // samples.
    property var live: ({})
    property string liveFor: ""
    readonly property bool liveReading: barPreviewProc.running
    // Every icon of the Nerd Font, [[glyph, name], ...] (themegen.py icons), asked for on first use.
    property var allIcons: []
    property string fontSlot: "font"
    property string colorKey: "accent"
    property var installedFonts: []
    property string fontQuery: ""
    readonly property var matchingFonts: installedFonts.filter(name => name.toLowerCase().includes(fontQuery.toLowerCase()))
    readonly property bool dirty: editing !== null && JSON.stringify(edit) !== saved
    // A file dialog is open: the window steps aside.
    property bool picking: false
    // ---- animated wallpapers need mpvpaper (with mpv and ffmpeg): offered the moment one is used
    property string wallpaperNeeds: ""   // the package still missing (themegen.py wallpaper-needs), or ""
    // ---- installing a package: the window asks for the sudo password; the install itself runs in the background
    // (rice-install-package), so the window may close. Its log is shown here.
    property var installing: null      // {package, title, source} whose install the dialog shows
    property string installState: ""   // ask, checking (the password), running, done, failed
    property string installMessage: ""
    property var installLog: []
    readonly property bool installStarting: installProc.running

    onSectionChanged: {
        askLive();
        if (section === "icons" && !iconThemes.installed.length) {
            iconThemesProc.running = true;
        }
        if (section === "cursor" && !cursorThemes.installed.length) {
            cursorThemesProc.running = true;
        }
    }

    function askLive() {
        if (section !== "waybar" || !editing || liveFor === editing.name) {
            return;
        }
        live = {};
        liveFor = editing.name;
        barPreviewProc.command = ["python3", Files.themegen, "bar-preview", editing.name];
        barPreviewProc.running = true;
    }

    function open(entry) {
        themeEditFile.reload();
        let file = {};
        try {
            file = JSON.parse(themeEditFile.text()) || {};
        } catch (e) {}
        everyTheme = file.themes || {};
        everywhere = file.everywhere || {};
        const mine = everyTheme[entry.name] || {};
        const walls = mine.wallpapers || {};
        edit = { fonts: Object.assign({ font: "", display: "", body: "" }, mine.fonts || {}),
                 colors: Object.assign({}, mine.colors || {}),
                 wallpapers: { added: (walls.added || []).slice(), off: (walls.off || []).slice() },
                 waybar: mine.waybar ? JSON.parse(JSON.stringify(mine.waybar)) : null,
                 icons: Object.assign({}, mine.icons || {}),
                 folders: mine.folders || "", iconTheme: mine.iconTheme || "", battery: mine.battery || "",
                 cursor: mine.cursor || "", cursorSize: mine.cursorSize || 0,
                 windows: Object.assign({}, mine.windows || {}) };
        saved = JSON.stringify(edit);
        section = "fonts";
        fontSlot = "font";
        fontQuery = "";
        editing = entry;
        askLive();
        if (!installedFonts.length) {
            fontsProc.running = true;
        }
    }

    function change(part, value) {
        edit = Object.assign({}, edit, { [part]: value });
    }

    // ---- fonts
    function font(key) {
        return edit.fonts[key] || editing.own.fonts[key];
    }
    function chooseFont(name) {
        change("fonts", Object.assign({}, edit.fonts, { [fontSlot]: name }));
    }

    // ---- colours
    function color(key) {
        return edit.colors[key] || editing.own.colors[key];
    }
    function chooseColor(hex) {
        change("colors", Object.assign({}, edit.colors, { [colorKey]: hex }));
    }
    function ownColor() {
        const colors = Object.assign({}, edit.colors);
        delete colors[colorKey];
        change("colors", colors);
    }
    function chooseFolders(name) {
        change("folders", name === editing.own.folders ? "" : name);
    }

    // ---- wallpapers: the theme's own, then the added ones; each one on or off
    function wallpapers() {
        const own = editing.wallpapers.filter(w => !w.added).map(w => w.path);
        const thumbs = {};
        for (const w of editing.wallpapers) {
            thumbs[w.path] = w.thumb;
        }
        const added = edit.wallpapers.added;
        return own.concat(added).map(path => ({ path: path, thumb: thumbs[path] || path, added: added.includes(path),
                                                on: !edit.wallpapers.off.includes(path) }));
    }
    function toggleWallpaper(path) {
        const off = edit.wallpapers.off;
        const next = off.includes(path) ? off.filter(p => p !== path) : off.concat([path]);
        change("wallpapers", { added: edit.wallpapers.added, off: next });
    }
    function removeWallpaper(path) {
        change("wallpapers", { added: edit.wallpapers.added.filter(p => p !== path),
                               off: edit.wallpapers.off.filter(p => p !== path) });
    }
    function addWallpaper(path) {
        if (!path || edit.wallpapers.added.includes(path)) {
            return;
        }
        change("wallpapers", { added: edit.wallpapers.added.concat([path]), off: edit.wallpapers.off });
        offerAnimated(path);
    }
    function isAnimated(path) {
        return /\.(gif|mp4|webm|mkv|mov|avi|m4v)$/i.test(path);
    }
    function offerAnimated(path) {
        if (!isAnimated(path) || !wallpaperNeeds || installing) {
            return;
        }
        askInstall({ package: wallpaperNeeds, title: "mpvpaper — анимированные обои", source: "aur",
                     done: "Установлено. Нажми «Поставить сейчас» на анимированных обоях, и они заиграют." });
    }
    // This theme's folder for wallpapers the user adds to it.
    function ownWallpaperDir() {
        return wallpaperDir + "/" + editing.name;
    }
    function pickWallpaper() {
        picking = true;
        wallpaperPicker.command = ["sh", "-c",
            // A picture is copied as it is; an animation is kept as the mp4 it plays from.
            'f=$(zenity --file-selection --title="Обои для темы" '
            + '--file-filter="Картинки, GIF и видео | *.png *.jpg *.jpeg *.webp *.gif *.mp4 *.webm *.mkv *.mov *.avi *.m4v") '
            + '&& mkdir -p "$1" && case "$(printf %s "$f" | tr A-Z a-z)" in '
            + '*.gif|*.mp4|*.webm|*.mkv|*.mov|*.avi|*.m4v) python3 "$2" wallpaper-import "$f" "$1" | tr -d "\n" ;; '
            + '*) cp "$f" "$1/" && printf "%s" "$1/$(basename "$f")" ;; esac',
            "sh", ownWallpaperDir(), Files.themegen];
        wallpaperPicker.running = true;
    }
    // The current theme only: the edits are saved (a just-added wallpaper has to be in the list changetheme picks
    // from), the picture is shown, and the theme applied again with it, so the lock screen, login screen and
    // browsers get it too.
    function showWallpaper(path) {
        offerAnimated(path);
        write("printf '%s\\n' " + Files.quote(path) + " > " + Files.quote(Files.home + "/.config/hypr/current-wallpaper")
              + " && " + Files.quote(Files.home + "/.local/bin/wallpaper") + " " + Files.quote(path)
              + " && changetheme --keep-wallpaper " + Files.quote(editing.name));
    }

    // ---- panel: this theme's own waybar layout, or null to follow the one saved for every theme
    function panel() {
        return edit.waybar || editing.waybar.withoutOwn;
    }
    function panelCopy() {
        return JSON.parse(JSON.stringify(panel()));
    }
    function onPanel(module) {
        return sides.some(([side]) => (panel()[side] || []).includes(module));
    }
    function moduleName(module) {
        return moduleNames[module] || module;
    }
    function preview(module) {
        const now = live[module];
        const text = (now && now.text) || (editing && editing.waybar.preview[module]) || "";
        return withIcon(module, text) || moduleName(module);
    }
    // text with the icon picked for module in front, in place of the one it starts with.
    function withIcon(module, text) {
        const glyph = edit.icons ? edit.icons[module] : "";
        if (!glyph) {
            return text;
        }
        const characters = Array.from(text);
        const startsWithIcon = characters.length && characters[0].codePointAt(0) >= 0xE000;
        return glyph + (startsWithIcon ? characters.slice(1).join("") : " " + text);
    }
    function iconEditable(module) {
        return !!editing && editing.waybar.iconEditable.includes(module);
    }
    function setIcon(module, glyph) {
        const icons = Object.assign({}, edit.icons);
        if (glyph) {
            icons[module] = glyph;
        } else {
            delete icons[module];
        }
        change("icons", icons);
    }
    function openIconPicker(module) {
        iconFor = module;
        iconChoice = edit.icons[module] || "";
        iconQuery = iconHints[module] || "";
        if (!allIcons.length) {
            iconsProc.running = true;
        }
    }
    function applyIcon() {
        setIcon(iconFor, iconChoice);
        iconFor = "";
    }
    // The module's icon as the bar shows it now: the first character of its text.
    function iconOf(module) {
        const characters = Array.from(preview(module));
        return characters.length && characters[0].codePointAt(0) >= 0xE000 ? characters[0] : "";
    }
    function moduleState(module) {
        return (live[module] || {}).state || "shown";
    }
    function moduleNote(module) {
        return (live[module] || {}).note || "";
    }
    function setPosition(position) {
        change("waybar", Object.assign(panelCopy(), { position: position }));
    }
    // The layout on screen becomes the one for every theme; this theme follows it from now on.
    function savePanelEverywhere() {
        everywhere = Object.assign({}, everywhere, { waybar: panelCopy() });
        change("waybar", null);
        write(applyCurrent());
    }
    function dropSharedPanel() {
        const shared = Object.assign({}, everywhere);
        delete shared.waybar;
        everywhere = shared;
        write(applyCurrent());
    }
    // Whatever theme is on now, applied again: a layout for every theme concerns it too.
    function applyCurrent() {
        return 'changetheme --keep-wallpaper "$(cat ~/.config/hypr/current-theme)"';
    }

    // ---- icons: the theme's own icon theme is written into its ui.json (a theme made in this window), or the rice's
    function themesIconTheme() {
        return (editing && editing.ui.iconTheme) || defaultIconTheme;
    }
    function iconThemeNow() {
        return edit.iconTheme || themesIconTheme();
    }
    function pickIconTheme(name) {
        change("iconTheme", name === themesIconTheme() ? "" : name);
    }
    function pickBattery(name) {
        change("battery", name === editing.name ? "" : name);
    }

    // ---- cursor: a pick here, or the theme's own (written into its ui.json, or the rice's)
    function themesCursor() {
        return (editing && editing.ui.cursor) || defaultCursor;
    }
    function themesCursorSize() {
        return (editing && editing.ui.cursorSize) || 24;
    }
    function cursorNow() {
        return edit.cursor || themesCursor();
    }
    function cursorSizeNow() {
        return edit.cursorSize || themesCursorSize();
    }
    // The theme's own takes the pick away: «как в теме» is the absence of one.
    function pickCursor(name) {
        change("cursor", name === themesCursor() ? "" : name);
    }
    function pickCursorSize(pixels) {
        change("cursorSize", pixels === themesCursorSize() ? 0 : pixels);
    }
    function readCursorThemes() {
        cursorThemesProc.running = true;
    }

    // ---- windows: a value set here, or the theme's own
    function windowValue(key) {
        const own = editing ? editing.windows[key] : undefined;
        return key in edit.windows ? edit.windows[key] : own;
    }
    // The theme's own value takes the edit away: «как в теме» is the absence of one.
    function setWindow(key, value) {
        const windows = Object.assign({}, edit.windows);
        if (editing && editing.windows[key] === value) {
            delete windows[key];
        } else {
            windows[key] = value;
        }
        change("windows", windows);
    }
    function setAnimations(speed) {
        const windows = Object.assign({}, edit.windows);
        if (speed) {
            windows.animations = speed;
        } else {
            delete windows.animations;
        }
        change("windows", windows);
    }

    // ---- installing
    function askInstall(item) {
        installing = item;
        installState = "ask";
        installMessage = "";
        installLog = [];
        installLogFile.reload();  // an install of this package may be running already: then its log shows
    }
    function startInstall(password) {
        installProc.password = password;
        installProc.command = [Files.home + "/.local/bin/rice-install-package", installing.package];
        installState = "checking";
        installMessage = "";
        installProc.running = true;
    }
    // The background install's log; its last line is "@@done <status>" once it is over.
    function readInstallLog(text) {
        const lines = text.split("\n").filter(line => line);
        if (!lines.length || !installing) {
            return;
        }
        const done = lines[lines.length - 1].match(/^@@done (\d+)$/);
        if (!done && installState === "ask") {
            installState = "running";
        }
        if (installState !== "running") {
            return;
        }
        installLog = lines.filter(line => !line.startsWith("@@done")).slice(-14);
        if (done) {
            installState = done[1] === "0" ? "done" : "failed";
            installMessage = done[1] !== "0" ? "Не установилось, подробности выше."
                                             : installing.done || "Установлено. Тема появилась в списке.";
            iconThemesProc.running = true;
            cursorThemesProc.running = true;
            wallpaperNeedsProc.running = true;
        }
    }

    // ---- the section's "back to the theme"
    function sectionEdited() {
        const part = edit[section] || {};
        if (section === "wallpapers") return part.added.length > 0 || part.off.length > 0;
        if (section === "waybar") return edit.waybar !== null || Object.keys(edit.icons).length > 0;
        if (section === "colors") return Object.keys(edit.colors).length > 0 || !!edit.folders;
        if (section === "icons") return !!edit.iconTheme || !!edit.battery;
        if (section === "cursor") return !!edit.cursor || !!edit.cursorSize;
        if (section === "windows") return Object.keys(edit.windows).length > 0;
        return Object.values(part).some(value => !!value);
    }
    function resetSection() {
        const empty = { fonts: { font: "", display: "", body: "" }, colors: {}, wallpapers: { added: [], off: [] },
                        waybar: null };
        change(section, empty[section]);
        if (section === "waybar") {
            change("icons", {});
        }
        if (section === "colors") {
            change("folders", "");
        }
        if (section === "windows") {
            change("windows", {});
        }
        if (section === "icons") {
            change("iconTheme", "");
            change("battery", "");
        }
        if (section === "cursor") {
            change("cursor", "");
            change("cursorSize", 0);
        }
    }

    // ---- saving
    function save() {
        write(editing.current ? "changetheme --keep-wallpaper " + Files.quote(editing.name) : "");
    }
    function switchTo() {
        write("changetheme " + Files.quote(editing.name));
    }
    // Writes the file, then runs: the removed wallpapers' copies go, a colour change rebuilds what themegen draws
    // for every theme (battery icon, Telegram, Code - OSS), then `then`.
    function write(then) {
        const before = JSON.parse(saved);
        const next = Object.assign({}, everyTheme);
        const kept = pruned(edit);
        if (Object.keys(kept).length) {
            next[editing.name] = kept;
        } else {
            delete next[editing.name];
        }
        const steps = before.wallpapers.added.filter(p => !edit.wallpapers.added.includes(p))
            .filter(p => p.startsWith(wallpaperDir + "/")).map(p => "rm -f " + Files.quote(p));
        // Colours and the battery drawing are in what build draws for every theme.
        if (JSON.stringify(before.colors) !== JSON.stringify(edit.colors) || before.battery !== edit.battery) {
            steps.push("python3 ~/.config/hypr/scripts/themegen.py build >/dev/null 2>&1");
        }
        if (then) {
            steps.push(then);
        }
        const file = { themes: next };
        if (Object.keys(everywhere).length) {
            file.everywhere = everywhere;
        }
        Files.write(path, JSON.stringify(file, null, 2) + "\n", steps.join("; "));
        everyTheme = next;
        saved = JSON.stringify(edit);
        // What each theme follows when it has no layout of its own, now that the shared one may differ.
        const shared = everywhere.waybar;
        const name = editing.name;
        ThemeList.replace(ThemeList.themes.map(t => {
            const waybar = Object.assign({}, t.waybar, { withoutOwn: shared || t.waybar.themesOwn });
            return Object.assign({}, t, { waybar: waybar }, t.name === name ? { edits: kept } : {});
        }));
        editing = ThemeList.themes.find(t => t.name === name);
    }
    // Only what differs from the theme: no empty fonts, colours or lists.
    function pruned(edited) {
        const out = {};
        const fonts = {};
        for (const [key, value] of Object.entries(edited.fonts)) {
            if (value) {
                fonts[key] = value;
            }
        }
        if (Object.keys(fonts).length) out.fonts = fonts;
        if (Object.keys(edited.colors).length) out.colors = edited.colors;
        const walls = {};
        if (edited.wallpapers.added.length) walls.added = edited.wallpapers.added;
        if (edited.wallpapers.off.length) walls.off = edited.wallpapers.off;
        if (Object.keys(walls).length) out.wallpapers = walls;
        if (edited.waybar) out.waybar = edited.waybar;
        if (Object.keys(edited.icons).length) out.icons = edited.icons;
        for (const key of ["folders", "iconTheme", "battery", "cursor", "cursorSize"]) {
            if (edited[key]) out[key] = edited[key];
        }
        if (Object.keys(edited.windows).length) out.windows = edited.windows;
        return out;
    }

    FileView { id: themeEditFile; path: themeEdit.path; blockLoading: true }
    Process {
        id: fontsProc
        command: ["sh", "-c", "fc-list : family | cut -d, -f1 | sort -u"]
        stdout: StdioCollector { onStreamFinished: themeEdit.installedFonts = this.text.split("\n").filter(name => name) }
    }
    Process {
        id: iconThemesProc
        command: ["python3", Files.themegen, "icon-themes"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    themeEdit.iconThemes = JSON.parse(this.text);
                } catch (e) {}
            }
        }
    }
    Process {
        id: cursorThemesProc
        command: ["python3", Files.themegen, "cursor-themes"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    themeEdit.cursorThemes = JSON.parse(this.text);
                } catch (e) {}
            }
        }
    }
    Process {
        id: iconsProc
        command: ["python3", Files.themegen, "icons"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    themeEdit.allIcons = JSON.parse(this.text);
                } catch (e) {
                    themeEdit.allIcons = [];
                }
            }
        }
    }
    Process {
        id: barPreviewProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    themeEdit.live = JSON.parse(this.text);
                } catch (e) {
                    themeEdit.live = {};
                }
            }
        }
    }
    Process {
        id: wallpaperNeedsProc
        command: ["python3", Files.themegen, "wallpaper-needs"]
        running: true
        stdout: StdioCollector { onStreamFinished: themeEdit.wallpaperNeeds = this.text.trim() }
    }
    Process {
        id: wallpaperPicker
        stdout: StdioCollector { onStreamFinished: themeEdit.addWallpaper(this.text.trim()) }
        onExited: themeEdit.picking = false
    }
    // A package being installed by rice-install-package; the sudo password goes on its stdin, never in its
    // arguments, and is forgotten here as soon as it is written.
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
}
