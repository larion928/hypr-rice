.pragma library

// The help cards Hyprland does not know about: the bar, the terminal, Code - OSS, the user's own files.
const sections = [
    { title: "Панель сверху", rows: [
        { keys: "\u{f03d8}", text: "Выбор темы" },
        { keys: "\uf059", text: "Эта справка" },
        { keys: "\u{f0493}", text: "Настройки: мониторы, клавиши, тема, функции" },
        { keys: "\uf0f3", text: "Уведомления (ПКМ — старый TUI)" },
        { keys: "\uf011", text: "Блокировка, сон, выход, выключение" },
        { keys: "\u{f05d1}", text: "Питание: клик — экономия / баланс / производительность" },
        { keys: "батарея ПКМ", text: "Сбережение батареи: зарядка до ~60%" },
        { keys: "\u{f0928} сеть", text: "Клик — выбор Wi-Fi, ПКМ — nmtui" },
        { keys: "us / ru", text: "Раскладка — Super+Space" },
        { keys: "✳ %", text: "Лимиты Claude (тема claude), клик — claude.ai" },
    ]},
    { title: "В терминале", rows: [
        { keys: "changetheme <тема>", text: "Сменить тему без окна выбора" },
        { keys: "themegen.py build", text: "Пересобрать темы Code, drift, Telegram" },
        { keys: "shot / shot full", text: "Скриншот из скрипта" },
        { keys: "mouse-sens", text: "Чувствительность мыши" },
        { keys: "rice mouse-test", text: "Мышь: угол датчика, DPI, частота опроса" },
        { keys: "portal-restart", text: "Перезапуск трансляции экрана" },
        { keys: "drift", text: "Скринсейвер в терминале" },
    ]},
    { title: "Code - OSS (git)", rows: [
        { keys: "Ctrl+Shift+G", text: "Изменения и коммит" },
        { keys: "Ctrl+Alt+G", text: "Граф веток" },
        { keys: "Ctrl+Alt+B / N", text: "Переключить / создать ветку" },
        { keys: "Ctrl+Alt+M", text: "Слить ветку" },
        { keys: "Ctrl+Alt+C", text: "Коммит" },
        { keys: "Ctrl+Alt+P", text: "Забрать изменения (pull)" },
    ]},
    { title: "Свои настройки", rows: [
        { keys: "~/.config/…", text: "Файлы ниже rice update не трогает, остальные заменит (старые — в ~/.rice-backup-*)" },
        { keys: "hypr/user.lua", text: "Hyprland, любой Lua, грузится последним (hyprctl reload)" },
        { keys: "hypr/binds-user.lua", text: "Горячие клавиши (окно Alt+F2)" },
        { keys: "hypr/monitors.lua", text: "Мониторы (окно Alt+F2)" },
        { keys: "hypr/devices.lua", text: "Мышь и тачпад (mouse-sens, rice mouse-test)" },
        { keys: "fish/user.fish", text: "fish: алиасы, PATH, переменные" },
        { keys: "hypr-rice/kitty/user.conf", text: "kitty: шрифт, прозрачность, клавиши" },
        { keys: "hypr-rice/waybar/user.css", text: "Стили панели (waybar-start)" },
        { keys: "…/waybar/config.local.json", text: "Модули панели поверх config.base.json" },
    ]},
];
