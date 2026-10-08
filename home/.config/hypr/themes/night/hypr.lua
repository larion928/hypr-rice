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
        rounding = 20,

        blur = {
            enabled = true,
            size    = 5,
            passes  = 2,
        },
    },
})

-- Calm: windows mostly fade, workspaces cross-fade.
hl.curve("nightCalm", { type = "bezier", points = { {0.4, 0}, {0.2, 1} } })
hl.animation({ leaf = "windowsIn",   enabled = true, speed = 4, bezier = "nightCalm", style = "popin 97%" })
hl.animation({ leaf = "windowsOut",  enabled = true, speed = 3, bezier = "nightCalm", style = "popin 97%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 4, bezier = "nightCalm" })
hl.animation({ leaf = "workspaces",  enabled = true, speed = 4, bezier = "nightCalm", style = "fade" })
