-------------------
--- KEYBINDINGS ---
-------------------
-- See https://wiki.hypr.land/Configuring/Basics/Binds/
-- Descriptions are "group | text [| keys label]"; the help panel (~/.local/bin/help-panel)
-- builds its hotkey list from them via `hyprctl binds`, so a bind without one stays hidden.
--
-- Binds made with bind("id", …) can be changed in the settings panel (Alt+F2). Its changes live
-- in binds-user.lua (not part of the rice repo), this file keeps the defaults:
--   return { mainMod = "SUPER", keys = { launcher = "SUPER + D", browser = false },
--            custom = { { keys = "SUPER + G", cmd = "gimp", name = "GIMP" } } }

-- Locals from hyprland.lua are not visible here: every require() is its own scope.
local terminal    = "kitty"
local fileManager = "thunar"
local menu        = "~/.local/bin/launcher"
-- The default browser (xdg-settings), so it follows whichever one is installed.
local browser     = [[sh -c 'gtk-launch "$(xdg-settings get default-web-browser)"']]

local ok, user = pcall(dofile, os.getenv("HOME") .. "/.config/hypr/binds-user.lua")
if not ok or type(user) ~= "table" then user = {} end
user.keys = user.keys or {}

local mainMod = user.mainMod or "ALT"

local function key(combo)
    return mainMod .. " + " .. combo
end
-- How mainMod reads in the help panel labels.
local M = mainMod == "SUPER" and "Super" or mainMod == "CTRL" and "Ctrl" or "Alt"

local function desc(text, flags)
    local o = flags or {}
    o.description = text
    return o
end

-- What the settings panel lists: every editable bind with its default and current keys.
local registry = {}

local function bind(id, keys, dispatcher, opts)
    local override = user.keys[id]
    local current = keys
    if override == false then current = "" elseif override ~= nil then current = override end
    registry[#registry + 1] = { id = id, default = keys, current = current,
                                description = opts and opts.description or "" }
    if current ~= "" then hl.bind(current, dispatcher, opts) end
end

-----------------
--- MY HOTKEY ---
-----------------

-- Swap window
hl.bind(key("SHIFT + H"), hl.dsp.window.swap({ direction = "left" }), desc("Окна | Поменять местами с соседним | " .. M .. "+Shift+H/J/K/L"))
hl.bind(key("SHIFT + J"), hl.dsp.window.swap({ direction = "down" }))
hl.bind(key("SHIFT + K"), hl.dsp.window.swap({ direction = "up" }))
hl.bind(key("SHIFT + L"), hl.dsp.window.swap({ direction = "right" }))

bind("prev_workspace", key("Tab"), hl.dsp.focus({ workspace = "previous" }), desc("Воркспейсы | Предыдущий воркспейс"))

-- Resize window
hl.bind(key("L"), hl.dsp.window.resize({ x = 70,  y = 0,   relative = true }), desc("Окна | Изменить размер | " .. M .. "+H/J/K/L", { repeating = true }))
hl.bind(key("H"), hl.dsp.window.resize({ x = -70, y = 0,   relative = true }), { repeating = true })
hl.bind(key("K"), hl.dsp.window.resize({ x = 0,   y = -70, relative = true }), { repeating = true })
hl.bind(key("J"), hl.dsp.window.resize({ x = 0,   y = 70,  relative = true }), { repeating = true })

-- Main binds
bind("lock",         key("I"),         hl.dsp.exec_cmd("hyprlock"),                     desc("Система | Заблокировать экран"))
bind("browser",      key("B"),         hl.dsp.exec_cmd(browser),                        desc("Приложения | Браузер"))
bind("telegram",     key("T"),         hl.dsp.exec_cmd("AyuGram"),                      desc("Приложения | AyuGram"))
bind("theme_picker", key("SHIFT + T"), hl.dsp.exec_cmd("~/.local/bin/theme-picker"),    desc("Оформление | Выбор темы"))
bind("screen_fx",    key("SHIFT + F"), hl.dsp.exec_cmd("~/.local/bin/screen-fx"),       desc("Оформление | Эффект экрана (в теме hacker)"))
bind("bar_restart",  key("SHIFT + O"), hl.dsp.exec_cmd("~/.local/bin/waybar-start"),    desc("Оформление | Перезапустить панель"))
bind("help",         key("F1"),        hl.dsp.exec_cmd("~/.local/bin/help-panel"),      desc("Система | Эта справка"))
bind("settings",     key("F2"),        hl.dsp.exec_cmd("~/.local/bin/settings-panel"),  desc("Система | Настройки: мониторы и клавиши"))

-- Passthrough for VMs and remote desktops: every key, Alt+… included, goes to the focused
-- window until Super+F12 is pressed again.
hl.define_submap("passthrough", function()
    hl.bind("SUPER + F12", hl.dsp.submap("reset"))
end)
hl.bind("SUPER + F12", hl.dsp.submap("passthrough"),
    desc("Система | Сквозной режим клавиш (для виртуалки), выход — снова Super+F12 | Super+F12"))

-- VM and remote-desktop windows switch passthrough on by themselves while focused.
local passthrough_classes = {
    ["qemu"] = true, ["virt-manager"] = true, ["remote-viewer"] = true,
    ["VirtualBox Machine"] = true, ["org.remmina.Remmina"] = true,
}
hl.on("window.active", function(w)
    local want = w ~= nil and passthrough_classes[w.class] == true
    local on = hl.get_current_submap() == "passthrough"
    if want and not on then
        hl.dispatch(hl.dsp.submap("passthrough"))
    elseif on and not want then
        hl.dispatch(hl.dsp.submap("reset"))
    end
end)

-- Themed screenshots (~/.local/bin/shot): saved to ~/Pictures/screenshots and copied.
-- Print: drag a region or click a window; Shift+Print: whole monitor.
bind("screenshot",      "Print",         hl.dsp.exec_cmd("~/.local/bin/shot"),      desc("Скриншоты | Область или окно (клик), Enter — весь экран"))
bind("screenshot_full", "SHIFT + Print", hl.dsp.exec_cmd("~/.local/bin/shot full"), desc("Скриншоты | Весь монитор"))

-------------
--- BASIC ---
-------------

bind("terminal", key("Return"), hl.dsp.exec_cmd(terminal),    desc("Приложения | Терминал"))
bind("close",    key("C"),      hl.dsp.window.close(),        desc("Окна | Закрыть окно"))
bind("exit",     key("M"),      hl.dsp.exit(),                desc("Система | Выйти из Hyprland"))
bind("files",    key("E"),      hl.dsp.exec_cmd(fileManager), desc("Приложения | Файлы (Thunar)"))
bind("float",    key("V"),      hl.dsp.window.float(),        desc("Окна | Плавающее / в сетке"))
bind("launcher", key("R"),      hl.dsp.exec_cmd(menu),        desc("Приложения | Лаунчер"))
bind("split",    key("P"),      hl.dsp.layout("togglesplit"), desc("Окна | Повернуть разбиение")) -- dwindle only

-- Move focus with mainMod + arrow keys
hl.bind(key("left"),  hl.dsp.focus({ direction = "left" }), desc("Окна | Фокус на соседнее окно | " .. M .. "+стрелки"))
hl.bind(key("right"), hl.dsp.focus({ direction = "right" }))
hl.bind(key("up"),    hl.dsp.focus({ direction = "up" }))
hl.bind(key("down"),  hl.dsp.focus({ direction = "down" }))

-- Switch workspaces with mainMod + [0-9]
-- Move active window to a workspace (silently) with mainMod + SHIFT + [0-9]
for i = 1, 10 do
    local k = i % 10 -- workspace 10 is on key 0
    hl.bind(key(k), hl.dsp.focus({ workspace = i }),
        i == 1 and desc("Воркспейсы | Перейти на воркспейс | " .. M .. "+1…0") or nil)
    hl.bind(key("SHIFT + " .. k), hl.dsp.window.move({ workspace = i, follow = false }),
        i == 1 and desc("Воркспейсы | Отправить окно на воркспейс | " .. M .. "+Shift+1…0") or nil)
end

-- Special workspace (scratchpad)
bind("special",      key("S"),         hl.dsp.workspace.toggle_special("magic"),            desc("Воркспейсы | Скрытый воркспейс"))
bind("special_move", key("SHIFT + S"), hl.dsp.window.move({ workspace = "special:magic" }), desc("Воркспейсы | Окно в скрытый воркспейс"))

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

-- The user's own binds from the settings panel: keys → command.
for _, c in ipairs(user.custom or {}) do
    if type(c) == "table" and c.keys and c.keys ~= "" and c.cmd and c.cmd ~= "" then
        hl.bind(c.keys, hl.dsp.exec_cmd(c.cmd), desc("Свои | " .. (c.name or c.cmd)))
    end
end

-- Hand the registry to the settings panel.
local function jstr(s)
    return '"' .. tostring(s):gsub('[%c"\\]', function(ch)
        return ch == '"' and '\\"' or ch == "\\" and "\\\\" or string.format("\\u%04x", ch:byte())
    end) .. '"'
end
local rows = {}
for _, r in ipairs(registry) do
    rows[#rows + 1] = string.format('{"id":%s,"default":%s,"current":%s,"description":%s}',
        jstr(r.id), jstr(r.default), jstr(r.current), jstr(r.description))
end
local custom = {}
for _, c in ipairs(user.custom or {}) do
    if type(c) == "table" then
        custom[#custom + 1] = string.format('{"keys":%s,"cmd":%s,"name":%s}',
            jstr(c.keys or ""), jstr(c.cmd or ""), jstr(c.name or ""))
    end
end
local out = io.open((os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/hypr-binds-registry.json", "w")
if out then
    out:write('{"mainMod":', jstr(mainMod), ',"binds":[', table.concat(rows, ","),
              '],"custom":[', table.concat(custom, ","), "]}\n")
    out:close()
end
