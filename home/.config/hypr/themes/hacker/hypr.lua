local c = require("palette")

hl.config({
    general = {
        gaps_in     = 4,
        gaps_out    = 8,
        border_size = 2,
        col = {
            active_border   = { colors = { c.active, c.active2 }, angle = 45 },
            inactive_border = c.inactive,
        },
    },

    decoration = {
        rounding = 0,

        blur = {
            enabled = true,
            size    = 5,
            passes  = 2,
            new_optimizations = true,
        },
    },
})

-- Fast and hard-edged: short linear-ish moves, no bounce.
hl.curve("hackerSnap", { type = "bezier", points = { {0.1, 0.9}, {0.2, 1} } })
hl.animation({ leaf = "windowsIn",   enabled = true, speed = 1.6, bezier = "hackerSnap", style = "popin 96%" })
hl.animation({ leaf = "windowsOut",  enabled = true, speed = 1.2, bezier = "hackerSnap", style = "popin 96%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 1.8, bezier = "hackerSnap" })
hl.animation({ leaf = "fade",        enabled = true, speed = 1.5, bezier = "hackerSnap" })
hl.animation({ leaf = "workspaces",  enabled = true, speed = 1.6, bezier = "hackerSnap", style = "slide" })
