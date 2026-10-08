-------------------
--- KEYBINDINGS ---
-------------------
-- See https://wiki.hypr.land/Configuring/Basics/Binds/
-- Descriptions are "group | text [| keys label]"; the help panel (~/.local/bin/help-panel)
-- builds its hotkey list from them via `hyprctl binds`, so a bind without one stays hidden.

-- Locals from hyprland.lua are not visible here: every require() is its own scope.
local terminal    = "kitty"
local fileManager = "thunar"
local menu        = "~/.local/bin/launcher"
local browser     = "chromium"

local mainMod = "ALT"

local function key(combo)
    return mainMod .. " + " .. combo
end

local function desc(text, flags)
    local o = flags or {}
    o.description = text
    return o
end

-----------------
--- MY HOTKEY ---
-----------------

-- Swap window
hl.bind(key("SHIFT + H"), hl.dsp.window.swap({ direction = "left" }), desc("Окна | Поменять местами с соседним | Alt+Shift+H/J/K/L"))
hl.bind(key("SHIFT + J"), hl.dsp.window.swap({ direction = "down" }))
hl.bind(key("SHIFT + K"), hl.dsp.window.swap({ direction = "up" }))
hl.bind(key("SHIFT + L"), hl.dsp.window.swap({ direction = "right" }))

hl.bind("ALT + Tab", hl.dsp.focus({ workspace = "previous" }), desc("Воркспейсы | Предыдущий воркспейс"))

-- Resize window
hl.bind(key("L"), hl.dsp.window.resize({ x = 70,  y = 0,   relative = true }), desc("Окна | Изменить размер | Alt+H/J/K/L", { repeating = true }))
hl.bind(key("H"), hl.dsp.window.resize({ x = -70, y = 0,   relative = true }), { repeating = true })
hl.bind(key("K"), hl.dsp.window.resize({ x = 0,   y = -70, relative = true }), { repeating = true })
hl.bind(key("J"), hl.dsp.window.resize({ x = 0,   y = 70,  relative = true }), { repeating = true })

-- Main binds
hl.bind(key("I"), hl.dsp.exec_cmd("hyprlock"), desc("Система | Заблокировать экран"))
hl.bind(key("B"), hl.dsp.exec_cmd(browser), desc("Приложения | Браузер"))
hl.bind(key("T"), hl.dsp.exec_cmd("AyuGram"), desc("Приложения | AyuGram"))
hl.bind(key("SHIFT + T"), hl.dsp.exec_cmd("~/.local/bin/theme-picker"), desc("Оформление | Выбор темы"))
hl.bind(key("SHIFT + F"), hl.dsp.exec_cmd("~/.local/bin/screen-fx"), desc("Оформление | Эффект экрана (в теме hacker)"))
hl.bind(key("SHIFT + O"), hl.dsp.exec_cmd("killall waybar; waybar -c ~/.config/waybar/config.json --log-level error &"), desc("Оформление | Перезапустить панель"))
hl.bind(key("F1"), hl.dsp.exec_cmd("~/.local/bin/help-panel"), desc("Система | Эта справка"))

-- Passthrough for VMs and remote desktops: every key, Alt+… included, goes to the focused
-- window until Super+F12 is pressed again.
hl.define_submap("passthrough", function()
    hl.bind("SUPER + F12", hl.dsp.submap("reset"))
end)
hl.bind("SUPER + F12", hl.dsp.submap("passthrough"),
    desc("Система | Сквозной режим клавиш (для виртуалки), выход — снова Super+F12 | Super+F12"))

-- Themed screenshots (~/.local/bin/shot): saved to ~/Pictures/screenshots and copied.
-- Print: drag a region or click a window; Shift+Print: whole monitor.
hl.bind("Print",         hl.dsp.exec_cmd("~/.local/bin/shot"), desc("Скриншоты | Область или окно (клик), Enter — весь экран"))
hl.bind("SHIFT + Print", hl.dsp.exec_cmd("~/.local/bin/shot full"), desc("Скриншоты | Весь монитор"))

-------------
--- BASIC ---
-------------

hl.bind(key("Return"), hl.dsp.exec_cmd(terminal), desc("Приложения | Терминал"))
hl.bind(key("C"), hl.dsp.window.close(), desc("Окна | Закрыть окно"))
hl.bind(key("M"), hl.dsp.exit(), desc("Система | Выйти из Hyprland"))
hl.bind(key("E"), hl.dsp.exec_cmd(fileManager), desc("Приложения | Файлы (Thunar)"))
hl.bind(key("V"), hl.dsp.window.float(), desc("Окна | Плавающее / в сетке"))
hl.bind(key("R"), hl.dsp.exec_cmd(menu), desc("Приложения | Лаунчер"))
hl.bind(key("P"), hl.dsp.layout("togglesplit"), desc("Окна | Повернуть разбиение")) -- dwindle only

-- Move focus with mainMod + arrow keys
hl.bind(key("left"),  hl.dsp.focus({ direction = "left" }), desc("Окна | Фокус на соседнее окно | Alt+стрелки"))
hl.bind(key("right"), hl.dsp.focus({ direction = "right" }))
hl.bind(key("up"),    hl.dsp.focus({ direction = "up" }))
hl.bind(key("down"),  hl.dsp.focus({ direction = "down" }))

-- Switch workspaces with mainMod + [0-9]
-- Move active window to a workspace (silently) with mainMod + SHIFT + [0-9]
for i = 1, 10 do
    local k = i % 10 -- workspace 10 is on key 0
    hl.bind(key(k), hl.dsp.focus({ workspace = i }),
        i == 1 and desc("Воркспейсы | Перейти на воркспейс | Alt+1…0") or nil)
    hl.bind(key("SHIFT + " .. k), hl.dsp.window.move({ workspace = i, follow = false }),
        i == 1 and desc("Воркспейсы | Отправить окно на воркспейс | Alt+Shift+1…0") or nil)
end

-- Special workspace (scratchpad)
hl.bind(key("S"),         hl.dsp.workspace.toggle_special("magic"), desc("Воркспейсы | Скрытый воркспейс"))
hl.bind(key("SHIFT + S"), hl.dsp.window.move({ workspace = "special:magic" }), desc("Воркспейсы | Окно в скрытый воркспейс"))

-- Move/resize windows with mainMod + LMB/RMB and dragging
hl.bind(key("mouse:272"), hl.dsp.window.drag(),   desc("Окна | Перетащить окно", { mouse = true }))
hl.bind(key("mouse:273"), hl.dsp.window.resize(), desc("Окна | Тянуть размер окна", { mouse = true }))

-- Laptop multimedia keys for volume and LCD brightness
hl.bind("XF86AudioRaiseVolume",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"),      desc("Звук и яркость | Громкость | клавиши громкости", { locked = true, repeating = true }))
hl.bind("XF86AudioLowerVolume",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true })
hl.bind("XF86AudioMute",         hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     desc("Звук и яркость | Выключить звук | Mute", { locked = true, repeating = true }))
hl.bind("XF86AudioMicMute",      hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   desc("Звук и яркость | Выключить микрофон | Mic mute", { locked = true, repeating = true }))
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl s 10%+"),                           desc("Звук и яркость | Яркость | клавиши яркости", { locked = true, repeating = true }))
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl s 10%-"),                           { locked = true, repeating = true })

-- Requires playerctl
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       desc("Звук и яркость | Следующий / предыдущий трек | медиаклавиши", { locked = true }))
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), desc("Звук и яркость | Пауза / воспроизведение | Play/Pause", { locked = true }))
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true })
