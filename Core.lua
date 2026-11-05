-- RivQoL core: saved settings, a tiny module registry and the /rivqol command.
local ADDON, ns = ...

ns.modules = {}   -- name -> module table, in registration order via ns.order
ns.order = {}

local PREFIX = "|cff33ff99RivQoL|r: "
function ns.Print(...)
    print(PREFIX .. string.join(" ", tostringall(...)))
end

-- A module is a table with:
--   name        short key, used in slash commands and the saved settings
--   description one line shown by /rivqol
--   defaults    table of default settings (must include `enabled`)
--   OnEnable(db) called once at PLAYER_LOGIN when the module is enabled
--   OnToggle(db) optional, called when /rivqol toggles it in-session
function ns.RegisterModule(mod)
    assert(mod.name and not ns.modules[mod.name], "RivQoL: bad or duplicate module name")
    ns.modules[mod.name] = mod
    table.insert(ns.order, mod.name)
end

local function ApplyDefaults(db, defaults)
    for k, v in pairs(defaults) do
        if db[k] == nil then db[k] = v end
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        RivQoLDB = RivQoLDB or {}
        RivQoLDB.modules = RivQoLDB.modules or {}
        for name, mod in pairs(ns.modules) do
            RivQoLDB.modules[name] = RivQoLDB.modules[name] or {}
            ApplyDefaults(RivQoLDB.modules[name], mod.defaults or { enabled = true })
            mod.db = RivQoLDB.modules[name]
        end
    elseif event == "PLAYER_LOGIN" then
        for _, name in ipairs(ns.order) do
            local mod = ns.modules[name]
            if mod.db.enabled and mod.OnEnable then
                local ok, err = pcall(mod.OnEnable, mod, mod.db)
                if not ok then ns.Print("module", name, "failed:", err) end
            end
        end
    end
end)

SLASH_RIVQOL1 = "/rivqol"
SLASH_RIVQOL2 = "/rq"
SlashCmdList.RIVQOL = function(msg)
    local cmd, arg = strsplit(" ", strtrim(msg or ""):lower(), 2)
    if cmd == "toggle" and arg and ns.modules[arg] then
        local mod = ns.modules[arg]
        mod.db.enabled = not mod.db.enabled
        if mod.OnToggle then mod:OnToggle(mod.db) end
        ns.Print(arg, mod.db.enabled and "|cff00ff00enabled|r" or "|cffff5555disabled|r")
        return
    end
    ns.Print("modules (/rivqol toggle <name>):")
    for _, name in ipairs(ns.order) do
        local mod = ns.modules[name]
        print(string.format("  %s %s - %s",
            mod.db.enabled and "|cff00ff00[on]|r " or "|cffff5555[off]|r",
            name, mod.description or ""))
    end
end
