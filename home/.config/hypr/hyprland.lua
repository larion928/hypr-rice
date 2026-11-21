-- Hyprland config (Lua, Hyprland 0.57+).

-- A file of the machine's or the user's own (not part of the rice repo), when it is there. One that
-- breaks (a typo in user.lua) is skipped with a notification on screen: an error here would stop
-- the whole config, and everything after it would be lost too.
local function load_if_present(name)
    local path = os.getenv("HOME") .. "/.config/hypr/" .. name
    local file = io.open(path, "r")
    if not file then
        return
    end
    file:close()
    local ok, problem = pcall(dofile, path)
    if not ok then
        hl.notification.create({ text = name .. " не загружен: " .. tostring(problem), timeout = 20000, icon = "error" })
    end
end

-- The features the user switched on or off (Alt+F2 → Функции): the flat {"id": true|false} that
-- ~/.config/hypr/scripts/features.py writes at every install and update, read again on every reload.
local function read_features()
    local file = io.open(os.getenv("HOME") .. "/.config/hypr-rice/features.json", "r")
    if not file then
        hl.notification.create({ text = "Нет features.json, функции райса выключены. Вернуть: rice repair",
                                 timeout = 20000, icon = "error" })
        return {}
    end
    local text = file:read("*a")
    file:close()
    local features = {}
    for id, value in text:gmatch('"([%w-]+)"%s*:%s*(%a+)') do
        features[id] = value == "true"
    end
    return features
end

local features = read_features()
local function on(feature)
    return features[feature] == true
end

----------------
--- MONITORS ---
----------------

-- Machine-specific (outputs, modes, workspace placement): monitors.lua is not part of the
-- rice repo, the installer writes a generic one.
load_if_present("monitors.lua")

-----------------
--- AUTOSTART ---
-----------------

hl.on("hyprland.start", function()
    -- Portals are systemd services (auto-restart on crash). They may already have been
    -- D-Bus-activated before the Wayland env reached systemd, so restart them after the import.
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE"
        .. " && systemctl --user restart xdg-desktop-portal-hyprland.service xdg-desktop-portal.service xdg-desktop-portal-gtk.service")
    hl.exec_cmd("systemctl --user start graphical-session.target")
    hl.exec_cmd("~/.local/bin/waybar-start")
    -- Apps installed or first started since the last theme change get the theme too.
    hl.exec_cmd("python3 ~/.config/hypr/scripts/themegen.py refresh")
    -- Session services that must not run under another desktop (its own notification daemon,
    -- portals): started here, stopped at shutdown.
    -- Another desktop's notification daemon that holds the bus is closed by histuid.service itself.
    hl.exec_cmd("systemctl --user start histuid.service portal-restart.timer")
    -- The menus and the volume/brightness OSD (~/.config/quickshell/shell); they follow the current theme.
    -- gtk3: Qt takes GTK's icon theme, the one the rice sets per theme; without it the shell finds no theme icons
    -- (the launcher's, the tray's). quickshell/menus.sh starts it the same way.
    hl.exec_cmd("QT_QPA_PLATFORMTHEME=gtk3 quickshell -d -n -p ~/.config/quickshell/shell")
    hl.exec_cmd("awww-daemon")
    -- The theme's wallpaper as written by changetheme (also covers a theme set offline).
    hl.exec_cmd("sleep 1; [ -f ~/.config/hypr/current-wallpaper ] && ~/.local/bin/wallpaper \"$(cat ~/.config/hypr/current-wallpaper)\"")
end)

hl.on("hyprland.shutdown", function()
    hl.exec_cmd("systemctl --user stop histuid.service portal-restart.timer")
end)

--------------------------
--- ANIMATED WALLPAPER ---
--------------------------

-- The animated wallpaper (~/.local/bin/wallpaper) is one mpv drawing on every monitor, so it pauses
-- everywhere or nowhere: it pauses while each monitor shows a fullscreen window, and plays while any
-- monitor shows the wallpaper. A fullscreen window on a workspace no monitor shows hides nothing.
-- A maximized window (fullscreen_mode 1) leaves the wallpaper in the gaps; only a fullscreen one (2) hides it.
local FULLSCREEN = 2

-- closing: the window being closed; its workspace still counts it as fullscreen when window.close comes.
local function hides_wallpaper(workspace, closing)
    if workspace == nil or workspace.fullscreen_mode < FULLSCREEN then
        return false
    end
    return closing == nil or workspace.fullscreen_window == nil
        or workspace.fullscreen_window.address ~= closing.address
end

local function wallpaper_hidden(closing)
    for _, monitor in ipairs(hl.get_monitors()) do
        if not hides_wallpaper(monitor.active_workspace, closing)
            and not hides_wallpaper(monitor.active_special_workspace, closing) then
            return false
        end
    end
    return true
end

-- Sent only when it changes: the events below come on every workspace switch, and each send starts a process.
local wallpaper_paused = nil

-- Switched off, the wallpaper never pauses; one paused when it was switched off resumes on the next event,
-- and until then fullscreen windows still hide it.
local function update_wallpaper_pause(closing)
    local hidden = on("wallpaper-pause") and wallpaper_hidden(closing)
    if hidden ~= wallpaper_paused then
        wallpaper_paused = hidden
        hl.exec_cmd("~/.local/bin/wallpaper-pause " .. (hidden and "yes" or "no"))
    end
end

hl.on("window.close", update_wallpaper_pause)
for _, event in ipairs({ "window.fullscreen", "window.open", "window.destroy", "window.move_to_workspace",
                         "workspace.active", "workspace.special_active", "workspace.move_to_monitor",
                         "monitor.added", "monitor.removed" }) do
    hl.on(event, function() update_wallpaper_pause(nil) end)
end
-- A new player (a theme change, the autostart) starts playing: it gets the current state again.
hl.on("layer.opened", function(layer)
    if layer.namespace == "mpvpaper" then
        wallpaper_paused = nil
        update_wallpaper_pause(nil)
    end
end)

-----------------------------
--- ENVIRONMENT VARIABLES ---
-----------------------------

-- The rice's scripts live in ~/.local/bin, which a fresh Arch login does not put on PATH.
local local_bin = os.getenv("HOME") .. "/.local/bin"
if not (os.getenv("PATH") or ""):find(local_bin, 1, true) then
    hl.env("PATH", local_bin .. ":" .. (os.getenv("PATH") or "/usr/bin"))
end

-- The rice keeps its kitty and waybar configs in ~/.config/hypr-rice, so another desktop on the
-- same account keeps its own ~/.config/kitty and ~/.config/waybar.
hl.env("KITTY_CONFIG_DIRECTORY", os.getenv("HOME") .. "/.config/hypr-rice/kitty")
-- Cursor built from the osu! WhiteCat skin by scripts/build-cursor.py; the one picked for the theme
-- (Alt+F2 → Тема → Курсор) comes from cursor.lua below.
hl.env("XCURSOR_THEME", "WhiteCat")
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_THEME", "WhiteCat")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")

---------------------
--- LOOK AND FEEL ---
---------------------
-- general{} and decoration{} come from the active theme (theme.lua, see the end of the file).

hl.config({
    animations = {
        enabled = on("animations"),
    },
})

-- Cursors in the XCursor format, as programs read them. A theme switched while Hyprland runs (hyprctl
-- setcursor, from Alt+F2 → Тема → Курсор) drew no cursor outside programs from the hyprcursor format of
-- the rice's WhiteCat; from XCursor it does.
hl.config({
    cursor = {
        enable_hyprcursor = false,
    },
})

hl.curve("easeOutQuint",   { type = "bezier", points = { {0.23, 1},    {0.32, 1}    } })
hl.curve("easeInOutCubic", { type = "bezier", points = { {0.65, 0.05}, {0.36, 1}    } })
hl.curve("linear",         { type = "bezier", points = { {0, 0},       {1, 1}       } })
hl.curve("almostLinear",   { type = "bezier", points = { {0.5, 0.5},   {0.75, 1.0}  } })
hl.curve("quick",          { type = "bezier", points = { {0.15, 0},    {0.1, 1}     } })

hl.animation({ leaf = "global",        enabled = true, speed = 10,   bezier = "default" })
hl.animation({ leaf = "border",        enabled = true, speed = 5.39, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows",       enabled = true, speed = 4.79, bezier = "easeOutQuint" })
hl.animation({ leaf = "windowsIn",     enabled = true, speed = 4.1,  bezier = "easeOutQuint", style = "popin 87%" })
hl.animation({ leaf = "windowsOut",    enabled = true, speed = 1.49, bezier = "linear",       style = "popin 87%" })
hl.animation({ leaf = "fadeIn",        enabled = true, speed = 1.73, bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut",       enabled = true, speed = 1.46, bezier = "almostLinear" })
hl.animation({ leaf = "fade",          enabled = true, speed = 3.03, bezier = "quick" })
hl.animation({ leaf = "layers",        enabled = true, speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn",      enabled = true, speed = 4,    bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut",     enabled = true, speed = 1.5,  bezier = "linear",       style = "fade" })
hl.animation({ leaf = "fadeLayersIn",  enabled = true, speed = 1.79, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.39, bezier = "almostLinear" })
hl.animation({ leaf = "workspaces",    enabled = true, speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesIn",  enabled = true, speed = 1.21, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesOut", enabled = true, speed = 1.94, bezier = "almostLinear", style = "fade" })

hl.config({
    dwindle = {
        preserve_split = true,
    },

    master = {
        new_status = "master",
    },

    misc = {
        force_default_wallpaper = -1,
        disable_hyprland_logo   = false,
    },
})

-------------
--- INPUT ---
-------------

hl.config({
    input = {
        kb_layout  = "us,ru",
        kb_variant = "",
        kb_model   = "",
        kb_options = "grp:win_space_toggle",
        kb_rules   = "",

        follow_mouse = 1,
        sensitivity  = -0.1,

        touchpad = {
            natural_scroll = true,
        },
    },
})

if on("gestures") then
    hl.gesture({
        fingers   = 3,
        direction = "horizontal",
        action    = "workspace",
    })
end

------------------------------
--- WINDOWS AND WORKSPACES ---
------------------------------

hl.window_rule({
    name  = "suppress-maximize-events",
    match = { class = ".*" },

    suppress_event = "maximize",
})

hl.window_rule({
    name  = "fix-xwayland-drags",
    match = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },

    no_focus = true,
})

-- Happ has no themes of its own; let the wallpaper and theme show through a little.
hl.window_rule({
    name  = "happ-translucent",
    match = { class = "^Happ$" },

    opacity = "0.875 0.875",
})

-- Telegram's media viewer, which is also where a theme link shows its "Apply" preview: tiled it
-- ends up as half a screen next to the chat and goes unnoticed.
hl.window_rule({
    name  = "telegram-viewer",
    match = { class = "^(com\\.ayugram\\.desktop|org\\.telegram\\.desktop)$", title = "^(Просмотр медиа|Media viewer)$" },

    float  = true,
    center = true,
    size   = "80% 85%",
})

-- The screenshot overlay shows a frozen frame; any fade-in would look like a flicker.
hl.layer_rule({
    name  = "shot-no-anim",
    match = { namespace = "^shot$" },

    no_anim = true,
})

hl.layer_rule({
    name  = "notif-panel-blur",
    match = { namespace = "^notif-panel$" },

    blur         = on("menu-blur"),
    ignore_alpha = 0.3,
})

hl.layer_rule({
    name  = "theme-picker-blur",
    match = { namespace = "^theme-picker$" },

    blur    = on("menu-blur"),
    no_anim = true,
})

hl.layer_rule({
    name  = "launcher-blur",
    match = { namespace = "^launcher$" },

    blur         = on("menu-blur"),
    ignore_alpha = 0.3,
})

hl.layer_rule({
    name  = "power-menu-blur",
    match = { namespace = "^power-menu$" },

    blur    = on("menu-blur"),
    no_anim = true,
})

hl.layer_rule({
    name  = "network-panel-blur",
    match = { namespace = "^network-panel$" },

    blur    = on("menu-blur"),
    no_anim = true,
})

hl.layer_rule({
    name  = "help-panel-blur",
    match = { namespace = "^help-panel$" },

    blur    = on("menu-blur"),
    no_anim = true,
})

hl.layer_rule({
    name  = "shots-gallery-blur",
    match = { namespace = "^shots-gallery$" },

    blur    = on("menu-blur"),
    no_anim = true,
})


-------------------
--- OTHER FILES ---
-------------------

-- Per-device input settings; written by mouse-sens and rice mouse-test.
load_if_present("devices.lua")
require("keybind")

-- Symlink to themes/<name>/hypr.lua, switched by ~/.local/bin/changetheme.
require("theme")
-- What the user changed in the theme's windows in the settings window (Alt+F2 → Тема → Окна),
-- written by themegen on every theme change.
load_if_present("theme-edits.lua")
load_if_present("cursor.lua")
-- Tearing in fullscreen games, when switched on in rice → Игры: оптимизация.
load_if_present("games.lua")
-- The user's own additions, loaded last so they can override anything above. Not part of the
-- rice repo: rice update leaves it alone.
load_if_present("user.lua")
