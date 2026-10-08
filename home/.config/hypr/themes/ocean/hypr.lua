local c = require("palette")

hl.config({
    general = {
        gaps_in     = 8,
        gaps_out    = 18,
        border_size = 2,
        col = {
            active_border   = { colors = { c.active, c.active2 }, angle = 270 },
            inactive_border = c.inactive,
        },
    },

    decoration = {
        rounding = 16,

        blur = {
            enabled = true,
            size    = 8,
            passes  = 3,
        },
    },
})

-- Underwater: windows rise from below, workspaces move like diving deeper,
-- the border gradient slowly flows around.
hl.curve("oceanRise", { type = "bezier", points = { {0.16, 1}, {0.3, 1} } })
hl.curve("oceanSink", { type = "bezier", points = { {0.5, 0}, {0.75, 0} } })
hl.animation({ leaf = "windowsIn",   enabled = true, speed = 5,   bezier = "oceanRise", style = "slide bottom" })
hl.animation({ leaf = "windowsOut",  enabled = true, speed = 3,   bezier = "oceanSink", style = "popin 90%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 5,   bezier = "oceanRise" })
hl.animation({ leaf = "fade",        enabled = true, speed = 4,   bezier = "oceanRise" })
hl.animation({ leaf = "workspaces",  enabled = true, speed = 5,   bezier = "oceanRise", style = "slidefadevert 25%" })
hl.animation({ leaf = "borderangle", enabled = true, speed = 100, bezier = "linear",    style = "loop" })
