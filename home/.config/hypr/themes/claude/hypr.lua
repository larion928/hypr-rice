local c = require("palette")

hl.config({
    general = {
        gaps_in     = 6,
        gaps_out    = 12,
        border_size = 2,
        col = {
            active_border   = { colors = { c.active, c.active2 }, angle = 45 },
            inactive_border = c.inactive,
        },
    },

    decoration = {
        rounding = 10,

        blur = {
            enabled = true,
            size    = 5,
            passes  = 2,
        },
    },
})

-- Soft and a little springy, like the claude.ai UI.
hl.curve("claudeSoft",   { type = "bezier", points = { {0.22, 1}, {0.36, 1} } })
hl.curve("claudeSpring", { type = "spring", mass = 1, stiffness = 180, dampening = 20 })
hl.animation({ leaf = "windowsIn",  enabled = true, speed = 4.5, spring = "claudeSpring", style = "popin 90%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 2.5, bezier = "claudeSoft",   style = "popin 90%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 4,  spring = "claudeSpring" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 3.5, bezier = "claudeSoft",   style = "slidefade 15%" })
