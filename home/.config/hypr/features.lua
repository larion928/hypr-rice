-- The features the user switched on or off (Alt+F2 → Функции): the flat {"id": true|false} that
-- ~/.config/hypr/scripts/features.py writes at every install and update, read again on every reload.
-- hyprland.lua and keybind.lua both require it; require() reads the file once per config load.
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

return function(feature)
    return features[feature] == true
end
