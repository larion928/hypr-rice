-- Hyprland config (Lua, Hyprland 0.55+). Migrated from hyprland.conf;
-- the old hyprlang files are kept in hyprlang-backup/.

----------------
--- MONITORS ---
----------------

-- Machine-specific (outputs, modes, workspace placement): monitors.lua is not part of the
-- rice repo, the installer writes a generic one.
require("monitors")

-----------------
--- AUTOSTART ---
-----------------

hl.on("hyprland.start", function()
    -- Portals are systemd services (auto-restart on crash). They may already have been
    -- D-Bus-activated before the Wayland env reached systemd, so restart them after the import.
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE"
        .. " && systemctl --user restart xdg-desktop-portal-hyprland.service xdg-desktop-portal.service xdg-desktop-portal-gtk.service")
    hl.exec_cmd("systemctl --user start graphical-session.target")
    hl.exec_cmd("waybar -c ~/.config/waybar/config.json")
    -- Volume/brightness OSD, follows the current theme on its own.
    hl.exec_cmd("OSD_BACKLIGHT=$(ls -d /sys/class/backlight/* 2>/dev/null | head -n1) quickshell -d -p ~/.config/quickshell/osd")
    hl.exec_cmd("awww-daemon")
    -- The theme's wallpaper as written by changetheme (also covers a theme set offline).
    hl.exec_cmd("sleep 1; [ -f ~/.config/hypr/current-wallpaper ] && awww img \"$(cat ~/.config/hypr/current-wallpaper)\"")
end)

-----------------------------
--- ENVIRONMENT VARIABLES ---
-----------------------------

-- Cursor built from the osu! WhiteCat skin by scripts/build-cursor.py.
-- The rice's scripts live in ~/.local/bin, which a fresh Arch login does not put on PATH.
local local_bin = os.getenv("HOME") .. "/.local/bin"
if not (os.getenv("PATH") or ""):find(local_bin, 1, true) then
    hl.env("PATH", local_bin .. ":" .. (os.getenv("PATH") or "/usr/bin"))
end

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
        enabled = true,
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

hl.gesture({
    fingers   = 3,
    direction = "horizontal",
    action    = "workspace",
})

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

-- The screenshot overlay shows a frozen frame; any fade-in would look like a flicker.
hl.layer_rule({
    name  = "shot-no-anim",
    match = { namespace = "^shot$" },

    no_anim = true,
})

hl.layer_rule({
    name  = "notif-panel-blur",
    match = { namespace = "^notif-panel$" },

    blur         = true,
    ignore_alpha = 0.3,
})

hl.layer_rule({
    name  = "theme-picker-blur",
    match = { namespace = "^theme-picker$" },

    blur    = true,
    no_anim = true,
})

hl.layer_rule({
    name  = "launcher-blur",
    match = { namespace = "^launcher$" },

    blur         = true,
    ignore_alpha = 0.3,
})

hl.layer_rule({
    name  = "power-menu-blur",
    match = { namespace = "^power-menu$" },

    blur    = true,
    no_anim = true,
})

hl.layer_rule({
    name  = "help-panel-blur",
    match = { namespace = "^help-panel$" },

    blur    = true,
    no_anim = true,
})

hl.layer_rule({
    name  = "shots-gallery-blur",
    match = { namespace = "^shots-gallery$" },

    blur    = true,
    no_anim = true,
})


-------------------
--- OTHER FILES ---
-------------------

-- Per-device input settings; rewritten by ~/.local/bin/mouse-sens.
require("devices")
require("keybind")
-- Symlink to themes/<name>/hypr.lua, switched by ~/.local/bin/changetheme.
require("theme")
