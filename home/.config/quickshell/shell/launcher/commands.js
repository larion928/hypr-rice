.pragma library

// The rice's own entries of the launcher, next to the desktop applications. `themes` is the theme list
// ([{name, pal: {label}}]); `home` is $HOME. Each entry: id (counted in usage.json), name, desc, glyph, the
// words it is found by, what it runs; "danger" asks for a second Enter.
function all(themes, home) {
    const bin = home + "/.local/bin/";
    const settings = bin + "settings-panel";
    const power = bin + "power-mode";
    const sh = command => ["sh", "-c", command];
    const list = themes.map(theme => ({
        id: "theme:" + theme.name, name: "Тема " + theme.pal.label, desc: "changetheme " + theme.name, glyph: "\u{f03d8}",
        keys: "theme тема оформление " + theme.name, run: ["changetheme", theme.name] }));
    return list.concat([
        { id: "picker", name: "Выбрать тему", desc: "Alt+Shift+T", glyph: "\u{f03d8}",
          keys: "theme тема оформление выбор", run: [bin + "theme-picker"] },
        // Screenshots wait a moment so the launcher itself is gone from the frame.
        { id: "shot", name: "Скриншот области", desc: "Print", glyph: "\uf030",
          keys: "screenshot скрин снимок", run: sh("sleep 0.4; ~/.local/bin/shot") },
        { id: "shotfull", name: "Скриншот экрана", desc: "Shift+Print", glyph: "\uf030",
          keys: "screenshot скрин снимок весь", run: sh("sleep 0.4; ~/.local/bin/shot full") },
        // Telegram cannot switch themes by itself: the theme's cloud link opens its "apply" preview.
        { id: "telegram", name: "Тема Telegram", desc: "применить тему текущего оформления",
          glyph: "\uf2c6", keys: "telegram телеграм ayugram аюграм тема",
          run: sh('t=$(cat "$HOME/.config/hypr/current-theme"); '
                  + 's=$(jq -r ".telegramSlug // empty" "$HOME/.config/hypr/themes/$t/ui.json" 2>/dev/null); '
                  + 'c=$(command -v AyuGram || command -v Telegram); '
                  + '[ -n "$s" ] && [ -n "$c" ] && exec "$c" -- "tg://addtheme?slug=$s"') },
        { id: "games", name: "Игры", desc: "свои игры, .exe, AppImage, Steam · Alt+G", glyph: "\u{f0297}",
          keys: "games игры steam стим proton exe appimage", run: [bin + "games"] },
        { id: "clipboard", name: "История буфера обмена", desc: "скопированное недавно · Alt+Shift+V", glyph: "\uf0ea",
          keys: "clipboard буфер обмена история скопированное вставить cliphist", run: [bin + "clipboard-history"] },
        { id: "settings", name: "Настройки", desc: "мониторы, клавиши, тема, функции · Alt+F2", glyph: "\u{f0493}",
          keys: "settings настройки параметры", run: [settings] },
        { id: "monitors", name: "Мониторы", desc: "разрешение, частота, масштаб, расположение", glyph: "\u{f0379}",
          keys: "monitor display screen монитор экран разрешение частота герцовка масштаб", run: [settings, "monitors"] },
        { id: "hotkeys", name: "Горячие клавиши", desc: "изменить, добавить свои", glyph: "\u{f030c}",
          keys: "keys hotkeys binds клавиши горячие сочетания хоткеи", run: [settings, "keys"] },
        { id: "features", name: "Настройки: функции", desc: "анимации, звук затвора, жесты, размытие: вкл/выкл",
          glyph: "\u{f0521}", keys: "features функции анимации звук жесты свайп размытие обои проверка буфер включить выключить",
          run: [settings, "features"] },
        { id: "network", name: "Сеть", desc: "Wi-Fi, пароли, текущее подключение", glyph: "\u{f0928}",
          keys: "network wifi wi-fi сеть вайфай интернет подключение", run: [bin + "network-panel"] },
        { id: "power-saver", name: "Питание: экономия", desc: "без турбобуста, тише и дольше от батареи", glyph: "\u{f032a}",
          keys: "power battery saver питание экономия энергосбережение", run: [power, "saver"] },
        { id: "power-balanced", name: "Питание: баланс", desc: "частоты по нагрузке", glyph: "\u{f05d1}",
          keys: "power balanced питание баланс", run: [power, "balanced"] },
        { id: "power-performance", name: "Питание: производительность", desc: "максимальные частоты, для игр", glyph: "\u{f04c5}",
          keys: "power performance питание производительность игры", run: [power, "performance"] },
        { id: "battery-care", name: "Сбережение батареи", desc: "вкл/выкл: зарядка до ~60% (Lenovo IdeaPad)", glyph: "\u{f12a3}",
          keys: "battery conservation батарея сбережение заряд 60", run: [power, "battery-care", "toggle"] },
        { id: "notif", name: "Уведомления", desc: "история", glyph: "\uf0f3",
          keys: "notifications уведомления история", run: [bin + "notif-panel"] },
        { id: "lock", name: "Блокировка экрана", desc: "Alt+I", glyph: "\uf023",
          keys: "lock блокировка заблокировать", run: ["rice-lock"] },
        { id: "suspend", name: "Сон", desc: "systemctl suspend", glyph: "\uf186",
          keys: "suspend sleep сон", run: ["systemctl", "suspend"] },
        { id: "logout", name: "Выйти из сессии", desc: "нужно подтверждение", glyph: "\uf2f5", danger: true,
          keys: "logout exit выход выйти", run: ["hyprctl", "dispatch", "hl.dsp.exit()"] },
        { id: "reboot", name: "Перезагрузка", desc: "нужно подтверждение", glyph: "\uf2f9", danger: true,
          keys: "reboot restart перезагрузка перезапуск", run: ["systemctl", "reboot"] },
        { id: "poweroff", name: "Выключение", desc: "нужно подтверждение", glyph: "\uf011", danger: true,
          keys: "poweroff shutdown выключение выключить", run: ["systemctl", "poweroff"] },
    ]);
}
