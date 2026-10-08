// App launcher, toggled by ~/.local/bin/launcher (Alt+R).
// Apps come from DesktopEntries; launches are counted in ~/.local/state/launcher/usage.json so
// frequent apps rank higher. A few system commands live next to the apps.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets

ShellRoot {
    id: root

    readonly property string themeDir: Quickshell.env("LAUNCHER_THEME_DIR")
    readonly property string usagePath: Quickshell.env("HOME") + "/.local/state/launcher/usage.json"
    property var pal: ({ colors: {} })
    property var ui: ({})
    readonly property var c: pal.colors || {}
    readonly property string titleFont: ui.titleFont === "display" ? (pal.display || "serif") : (pal.font || "monospace")
    readonly property string bodyFont: !ui.bodyFont || ui.bodyFont === "font" ? (pal.font || "monospace")
                                       : ui.bodyFont === "display" ? (pal.display || "serif") : ui.bodyFont
    readonly property int r: Math.min(ui.radius ?? 14, 22)

    property var usage: ({})
    property string query: ""
    property int current: 0
    property string armed: ""   // id of a dangerous command waiting for a second Enter
    property bool closing: false

    FileView { id: palFile; path: root.themeDir + "/palette.json"; blockLoading: true }
    FileView { id: uiFile; path: root.themeDir + "/ui.json"; blockLoading: true }
    FileView { id: usageFile; path: root.usagePath; blockLoading: true }

    Component.onCompleted: {
        try { pal = JSON.parse(palFile.text()); } catch (e) {}
        try { ui = JSON.parse(uiFile.text()); } catch (e) {}
        try { usage = JSON.parse(usageFile.text()) || {}; } catch (e) { usage = {}; }
    }

    function a(col, al) {
        return "#" + ("0" + Math.round(al * 255).toString(16)).slice(-2) + String(col || "#888888").slice(1);
    }

    // ---------- commands ----------

    function sh(cmd) { return ["sh", "-c", cmd]; }

    readonly property var commands: {
        const list = [];
        let themes = [];
        try { themes = JSON.parse(Quickshell.env("LAUNCHER_THEMES") || "[]"); } catch (e) {}
        for (const t of themes)
            list.push({ id: "theme:" + t.name, name: "Тема " + t.label, desc: "changetheme " + t.name,
                        glyph: "\u{f03d8}", keys: "theme тема оформление " + t.name, run: ["changetheme", t.name] });
        list.push({ id: "picker", name: "Выбрать тему", desc: "Alt+Shift+T", glyph: "\u{f03d8}",
                    keys: "theme тема оформление выбор", run: [Quickshell.env("HOME") + "/.local/bin/theme-picker"] });
        // Screenshots wait a moment so the launcher itself is gone from the frame.
        list.push({ id: "shot", name: "Скриншот области", desc: "Print", glyph: "",
                    keys: "screenshot скрин снимок", run: sh("sleep 0.4; ~/.local/bin/shot") });
        list.push({ id: "shotfull", name: "Скриншот экрана", desc: "Shift+Print", glyph: "",
                    keys: "screenshot скрин снимок весь", run: sh("sleep 0.4; ~/.local/bin/shot full") });
        // Telegram cannot switch themes by itself: opening the file shows its "apply theme" prompt.
        list.push({ id: "telegram", name: "Тема AyuGram", desc: "применить тему текущего оформления",
                    glyph: "\uf2c6", keys: "telegram телеграм ayugram аюграм тема",
                    run: sh('AyuGram -- "$HOME/.local/share/hypr-themes/telegram/$(cat "$HOME/.config/hypr/current-theme").tdesktop-theme"') });
        list.push({ id: "notif", name: "Уведомления", desc: "история", glyph: "",
                    keys: "notifications уведомления история", run: [Quickshell.env("HOME") + "/.local/bin/notif-panel"] });
        list.push({ id: "lock", name: "Блокировка экрана", desc: "Alt+I", glyph: "",
                    keys: "lock блокировка заблокировать", run: ["hyprlock"] });
        list.push({ id: "suspend", name: "Сон", desc: "systemctl suspend", glyph: "",
                    keys: "suspend sleep сон", run: ["systemctl", "suspend"] });
        list.push({ id: "logout", name: "Выйти из сессии", desc: "нужно подтверждение", glyph: "", danger: true,
                    keys: "logout exit выход выйти", run: ["hyprctl", "dispatch", "hl.dsp.exit()"] });
        list.push({ id: "reboot", name: "Перезагрузка", desc: "нужно подтверждение", glyph: "", danger: true,
                    keys: "reboot restart перезагрузка перезапуск", run: ["systemctl", "reboot"] });
        list.push({ id: "poweroff", name: "Выключение", desc: "нужно подтверждение", glyph: "", danger: true,
                    keys: "poweroff shutdown выключение выключить", run: ["systemctl", "poweroff"] });
        return list;
    }

    // ---------- search ----------

    // Higher is better; 0 means no match.
    function score(text, q) {
        if (!text) return 0;
        const t = text.toLowerCase();
        if (t === q) return 100;
        if (t.startsWith(q)) return 80;
        if (t.split(/[\s\-_.]+/).some(w => w.startsWith(q))) return 60;
        if (t.indexOf(q) !== -1) return 40;
        if (q.length < 3) return 0;
        let i = 0;
        for (const ch of t) if (ch === q[i]) i++;
        return i === q.length ? 15 : 0;
    }

    // Same keys on the us/ru layouts, so "ешьу" still finds "time" and "сщву" finds "code".
    readonly property string enKeys: "`qwertyuiop[]asdfghjkl;'zxcvbnm,."
    readonly property string ruKeys: "ёйцукенгшщзхъфывапролджэячсмитьбю"
    function swapLayout(q) {
        let out = "";
        for (const ch of q) {
            const i = enKeys.indexOf(ch), j = ruKeys.indexOf(ch);
            out += i !== -1 ? ruKeys[i] : j !== -1 ? enKeys[j] : ch;
        }
        return out;
    }
    function bestScore(it, q) {
        return Math.max(score(it.name, q), score(it.keys, q) * 0.7);
    }

    readonly property var apps: DesktopEntries.applications.values
        .filter(e => !e.noDisplay)
        .map(e => ({ id: "app:" + e.id, name: e.name, desc: e.genericName || e.comment || "", icon: e.icon,
                     keys: [e.genericName, e.comment, (e.keywords || []).join(" "), (e.categories || []).join(" ")].join(" "),
                     entry: e }))

    readonly property var results: {
        const q = query.trim().toLowerCase();
        const all = apps.concat(commands);
        const used = it => Math.log(1 + (usage[it.id] || 0));
        let list;
        if (!q) {
            // Nothing typed: most used first, then the rest alphabetically.
            list = all.filter(it => !it.danger && !String(it.id).startsWith("theme:"))
                      .sort((x, y) => (usage[y.id] || 0) - (usage[x.id] || 0) || x.name.localeCompare(y.name));
        } else {
            const alt = swapLayout(q);
            list = all.map(it => ({ it: it, s: Math.max(bestScore(it, q), bestScore(it, alt) * 0.9) }))
                      .filter(x => x.s > 0)
                      .map(x => ({ it: x.it, s: x.s + used(x.it) * 6 }))
                      .sort((x, y) => y.s - x.s)
                      .map(x => x.it);
        }
        return list.slice(0, 60);
    }

    onResultsChanged: { current = 0; armed = ""; }

    function activate(i) {
        const it = results[i];
        if (!it) return;
        if (it.danger && armed !== it.id) {
            armed = it.id;
            return;
        }
        const u = Object.assign({}, usage);
        u[it.id] = (u[it.id] || 0) + 1;
        Quickshell.execDetached(["sh", "-c", 'mkdir -p "$(dirname "$1")" && printf "%s" "$2" > "$1"', "sh",
                                 usagePath, JSON.stringify(u)]);
        if (it.entry) it.entry.execute();
        else Quickshell.execDetached(it.run);
        close();
    }

    function close() {
        if (closing) return;
        closing = true;
        outAnim.start();
    }

    IpcHandler {
        target: "launcher"
        function close(): void { root.close(); }
    }

    PanelWindow {
        id: win
        implicitWidth: 680
        implicitHeight: 560
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "launcher"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        HyprlandFocusGrab {
            active: !root.closing
            windows: [win]
            onCleared: root.close()
        }

        Rectangle {
            id: box
            anchors.fill: parent
            radius: root.r
            color: root.a(root.c.bg, 0.93)
            border.width: root.ui.border ?? 1
            border.color: root.a(root.c.accent, 0.55)
            opacity: 0
            scale: 0.96
            clip: true

            Component.onCompleted: inAnim.start()
            ParallelAnimation {
                id: inAnim
                NumberAnimation { target: box; property: "opacity"; to: 1; duration: (root.ui.slideMs ?? 260) * 0.6 }
                NumberAnimation { target: box; property: "scale"; to: 1; duration: (root.ui.slideMs ?? 260) * 0.8; easing.type: Easing.OutCubic }
            }
            SequentialAnimation {
                id: outAnim
                ParallelAnimation {
                    NumberAnimation { target: box; property: "opacity"; to: 0; duration: 140 }
                    NumberAnimation { target: box; property: "scale"; to: 0.97; duration: 140 }
                }
                ScriptAction { script: Qt.quit() }
            }

            // Search field
            Rectangle {
                id: field
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
                height: 52
                radius: Math.min(root.r, 26)
                color: root.a(root.c.bg2, 0.95)
                border.color: root.a(root.c.accent, 0.45)

                Image {
                    id: fieldIcon
                    visible: !!root.ui.headerIcon
                    anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
                    source: root.ui.headerIcon ? "file://" + root.themeDir + "/" + root.ui.headerIcon : ""
                    width: 22; height: 22; sourceSize: Qt.size(44, 44)
                }
                Text {
                    id: fieldGlyph
                    visible: !root.ui.headerIcon
                    anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
                    text: root.ui.headerGlyph || ""
                    font.family: root.titleFont; font.pixelSize: 20; font.bold: true
                    color: root.c.accent || "white"
                }
                Text {
                    anchors { left: input.left; verticalCenter: parent.verticalCenter }
                    visible: !input.text
                    text: "Приложение или команда…"
                    font.family: root.bodyFont; font.pixelSize: 18; font.italic: !!root.ui.italicTitle
                    color: root.c.muted || "grey"
                }
                TextInput {
                    id: input
                    anchors { left: parent.left; leftMargin: 50; right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                    focus: true
                    font.family: root.bodyFont; font.pixelSize: 18
                    color: root.c.fg || "white"
                    selectionColor: root.a(root.c.accent, 0.4)
                    clip: true
                    onTextChanged: root.query = text
                    Keys.onPressed: e => {
                        if (e.key === Qt.Key_Escape) root.close();
                        else if (e.key === Qt.Key_Down || (e.key === Qt.Key_J && e.modifiers & Qt.ControlModifier) || e.key === Qt.Key_Tab) {
                            root.current = Math.min(root.current + 1, root.results.length - 1); root.armed = ""; e.accepted = true;
                        } else if (e.key === Qt.Key_Up || (e.key === Qt.Key_K && e.modifiers & Qt.ControlModifier) || e.key === Qt.Key_Backtab) {
                            root.current = Math.max(root.current - 1, 0); root.armed = ""; e.accepted = true;
                        } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                            root.activate(root.current); e.accepted = true;
                        }
                    }
                }
            }

            Text {
                id: sectionLabel
                anchors { left: parent.left; leftMargin: 24; top: field.bottom; topMargin: 14 }
                text: root.query ? "Результаты" : "Часто запускаемые"
                font.family: root.titleFont; font.pixelSize: 13; font.bold: true; font.italic: !!root.ui.italicTitle
                color: root.c.accent2 || root.c.accent || "white"
            }

            ListView {
                id: list
                anchors { left: parent.left; right: parent.right; top: sectionLabel.bottom; bottom: parent.bottom; margins: 12; topMargin: 8 }
                clip: true
                spacing: 4
                model: root.results
                currentIndex: root.current
                highlightMoveDuration: 120
                boundsBehavior: Flickable.StopAtBounds

                highlight: Rectangle {
                    width: list.width
                    radius: Math.min(root.r, 12)
                    color: root.a(root.c.accent, 0.22)
                    border.color: root.a(root.c.accent, 0.55)
                }

                delegate: Item {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool armed: root.armed === modelData.id
                    width: list.width
                    height: 54

                    Row {
                        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                        spacing: 14

                        Item {
                            width: 32; height: 32
                            anchors.verticalCenter: parent.verticalCenter
                            IconImage {
                                id: appIcon
                                anchors.fill: parent
                                visible: source != ""
                                source: row.modelData.icon ? Quickshell.iconPath(row.modelData.icon, true) : ""
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: !appIcon.visible
                                text: row.modelData.glyph || ""
                                font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 20
                                color: row.modelData.danger ? (root.c.crit || "red") : (root.c.accent || "white")
                            }
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            Text {
                                text: row.modelData.name
                                font.family: root.titleFont; font.pixelSize: 16
                                color: row.modelData.danger ? (root.c.crit || "red") : (root.c.fg || "white")
                            }
                            Text {
                                visible: text.length > 0
                                width: list.width - 140
                                elide: Text.ElideRight
                                text: row.armed ? "Нажми Enter ещё раз, чтобы подтвердить" : row.modelData.desc
                                font.family: root.bodyFont; font.pixelSize: 12
                                color: row.armed ? (root.c.warn || "yellow") : (root.c.muted || "grey")
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: { if (root.current !== row.index) { root.current = row.index; root.armed = ""; } }
                        onClicked: root.activate(row.index)
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: list.count === 0
                    text: "Ничего не нашлось"
                    font.family: root.titleFont; font.pixelSize: 16; font.italic: !!root.ui.italicTitle
                    color: root.c.muted || "grey"
                }
            }
        }
    }
}
