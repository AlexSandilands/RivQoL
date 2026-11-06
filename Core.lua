-- RivQoL core: saved settings, a tiny module registry and the /rivqol command.
local ADDON, ns = ...

ns.modules = {}   -- name -> module table, in registration order via ns.order
ns.order = {}

local PREFIX = "|cff33ff99RivQoL|r: "
function ns.Print(...)
    print(PREFIX .. string.join(" ", tostringall(...)))
end

-- A module is a table with:
--   name         short key, used in slash commands and the saved settings
--   title        optional display name for the options window (defaults to name)
--   description  one line shown by /rivqol list and on the module's options page
--   defaults     table of default settings (must include `enabled`)
--   OnEnable(db)  called at PLAYER_LOGIN when the module is enabled, and again
--                 whenever it is turned on in-session, so it must be safe to
--                 call more than once
--   OnDisable(db) optional, called when the module is turned off in-session
--   BuildOptions(page, db, y) -> y  optional, fills the module's page in the
--                 options window below the title, description and Enabled
--                 toggle: lay widgets out from `y` (see UI/Widgets.lua) and
--                 return the final y so the page scrolls to fit
function ns.RegisterModule(mod)
    assert(mod.name and not ns.modules[mod.name], "RivQoL: bad or duplicate module name")
    ns.modules[mod.name] = mod
    table.insert(ns.order, mod.name)
end

-- Settings-changed callbacks: fn(moduleName, key) runs after a module's
-- setting changes (key "enabled" for on/off). The options window uses this to
-- stay in sync with slash commands.
local callbacks = {}
function ns.RegisterCallback(fn)
    table.insert(callbacks, fn)
end

function ns.FireChanged(name, key)
    for _, fn in ipairs(callbacks) do
        local ok, err = pcall(fn, name, key)
        if not ok then geterrorhandler()(err) end
    end
end

local loggedIn = false

local function Call(mod, method)
    local fn = mod[method]
    if not fn then return end
    local ok, err = pcall(fn, mod, mod.db)
    if not ok then ns.Print("module", mod.name, method, "failed:", err) end
end

-- The one way to turn a module on or off (slash command and options window).
function ns.SetModuleEnabled(name, on)
    local mod = ns.modules[name]
    if not mod then return end
    on = not not on
    if mod.db.enabled == on then return end
    mod.db.enabled = on
    if loggedIn then
        Call(mod, on and "OnEnable" or "OnDisable")
    end
    ns.FireChanged(name, "enabled")
end

function ns.IsModuleEnabled(name)
    local mod = ns.modules[name]
    return mod and mod.db and mod.db.enabled or false
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
        RivQoLDB.ui = RivQoLDB.ui or {}
        for name, mod in pairs(ns.modules) do
            RivQoLDB.modules[name] = RivQoLDB.modules[name] or {}
            ApplyDefaults(RivQoLDB.modules[name], mod.defaults or { enabled = true })
            mod.db = RivQoLDB.modules[name]
        end
        ns.uidb = RivQoLDB.ui
    elseif event == "PLAYER_LOGIN" then
        loggedIn = true
        for _, name in ipairs(ns.order) do
            local mod = ns.modules[name]
            if mod.db.enabled then Call(mod, "OnEnable") end
        end
    end
end)

local function PrintList()
    ns.Print("modules (/rivqol toggle <name>, /rivqol to open the options):")
    for _, name in ipairs(ns.order) do
        local mod = ns.modules[name]
        print(string.format("  %s %s - %s",
            mod.db.enabled and "|cff00ff00[on]|r " or "|cffff5555[off]|r",
            name, mod.description or ""))
    end
end

SLASH_RIVQOL1 = "/rivqol"
SLASH_RIVQOL2 = "/rq"
SlashCmdList.RIVQOL = function(msg)
    local cmd, arg = strsplit(" ", strtrim(msg or ""):lower(), 2)
    if cmd == "toggle" and arg and ns.modules[arg] then
        ns.SetModuleEnabled(arg, not ns.modules[arg].db.enabled)
        ns.Print(arg, ns.modules[arg].db.enabled and "|cff00ff00enabled|r" or "|cffff5555disabled|r")
        return
    end
    if cmd == "" and ns.ToggleOptions then
        ns.ToggleOptions()
        return
    end
    if cmd == "toggle" then
        ns.Print("unknown module:", arg or "(none)")
    end
    PrintList()
end
