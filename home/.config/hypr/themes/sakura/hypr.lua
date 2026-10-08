local c = require("palette")

hl.config({
    general = {
        gaps_in     = 8,
        gaps_out    = 16,
        border_size = 2,
        col = {
            active_border   = { colors = { c.active, c.active2 }, angle = 135 },
            inactive_border = c.inactive,
        },
    },

    decoration = {
        rounding = 14,

        blur = {
            enabled = true,
            size    = 6,
            passes  = 2,
        },
    },
})

-- Petals: windows float in with a slight overshoot and drift out softly.
hl.curve("sakuraFloat", { type = "bezier", points = { {0.34, 1.36}, {0.64, 1} } })
hl.curve("sakuraFall",  { type = "bezier", points = { {0.45, 0}, {0.55, 1} } })
hl.animation({ leaf = "windowsIn",   enabled = true, speed = 5,   bezier = "sakuraFloat", style = "popin 85%" })
hl.animation({ leaf = "windowsOut",  enabled = true, speed = 4,   bezier = "sakuraFall",  style = "popin 85%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 5,   bezier = "sakuraFloat" })
hl.animation({ leaf = "fade",        enabled = true, speed = 5,   bezier = "sakuraFall" })
hl.animation({ leaf = "workspaces",  enabled = true, speed = 5,   bezier = "sakuraFall",  style = "slidefade 20%" })
