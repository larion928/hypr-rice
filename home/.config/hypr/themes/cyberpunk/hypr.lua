local c = require("palette")

hl.config({
    general = {
        gaps_in     = 5,
        gaps_out    = 10,
        border_size = 2,
        col = {
            active_border   = { colors = { c.active, c.active2 }, angle = 45 },
            inactive_border = c.inactive,
        },
    },

    decoration = {
        rounding = 3,

        blur = {
            enabled = true,
            size    = 5,
            passes  = 2,
        },
    },
})

-- Overshooting moves and a neon gradient that keeps rotating around the active window.
hl.curve("cyberOvershoot", { type = "bezier", points = { {0.05, 0.9}, {0.1, 1.15} } })
hl.animation({ leaf = "windowsIn",   enabled = true, speed = 3.5, bezier = "cyberOvershoot", style = "slide" })
hl.animation({ leaf = "windowsOut",  enabled = true, speed = 2,   bezier = "cyberOvershoot", style = "popin 80%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 3,   bezier = "cyberOvershoot" })
hl.animation({ leaf = "workspaces",  enabled = true, speed = 3,   bezier = "cyberOvershoot", style = "slidevert" })
hl.animation({ leaf = "borderangle", enabled = true, speed = 60,  bezier = "linear",         style = "loop" })
