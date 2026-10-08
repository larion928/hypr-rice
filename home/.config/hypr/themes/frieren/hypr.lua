local c = require("palette")

hl.config({
    general = {
        gaps_in     = 8,
        gaps_out    = 16,
        border_size = 2,
        col = {
            active_border   = { colors = { c.active, c.active2 }, angle = 45 },
            inactive_border = c.inactive,
        },
    },

    decoration = {
        rounding = 12,

        blur = {
            enabled = true,
            size    = 5,
            passes  = 2,
        },
    },
})

-- Slow and dreamy: long fades and gentle drifts.
hl.curve("frierenDrift", { type = "bezier", points = { {0.25, 0.1}, {0.25, 1} } })
hl.animation({ leaf = "windowsIn",   enabled = true, speed = 7,   bezier = "frierenDrift", style = "popin 80%" })
hl.animation({ leaf = "windowsOut",  enabled = true, speed = 5,   bezier = "frierenDrift", style = "popin 85%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 6,   bezier = "frierenDrift" })
hl.animation({ leaf = "fade",        enabled = true, speed = 6,   bezier = "frierenDrift" })
hl.animation({ leaf = "workspaces",  enabled = true, speed = 6,   bezier = "frierenDrift", style = "slidefade 30%" })
