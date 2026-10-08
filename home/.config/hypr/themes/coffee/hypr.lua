local c = require("palette")

hl.config({
    general = {
        gaps_in     = 5,
        gaps_out    = 10,
        border_size = 3,
        col = {
            active_border   = { colors = { c.active, c.active2 }, angle = 90 },
            inactive_border = c.inactive,
        },
    },

    decoration = {
        rounding = 6,

        blur = {
            enabled = true,
            size    = 4,
            passes  = 2,
        },
    },
})

-- Unhurried but short: no bounce, nothing flies across the screen.
hl.curve("coffeeCalm", { type = "bezier", points = { {0.3, 0}, {0.2, 1} } })
hl.animation({ leaf = "windowsIn",   enabled = true, speed = 3,   bezier = "coffeeCalm", style = "popin 94%" })
hl.animation({ leaf = "windowsOut",  enabled = true, speed = 2.5, bezier = "coffeeCalm", style = "popin 94%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 3,   bezier = "coffeeCalm" })
hl.animation({ leaf = "fade",        enabled = true, speed = 3,   bezier = "coffeeCalm" })
hl.animation({ leaf = "workspaces",  enabled = true, speed = 3,   bezier = "coffeeCalm", style = "slide" })
