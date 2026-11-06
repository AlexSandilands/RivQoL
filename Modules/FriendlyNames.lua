-- Keep floating friendly player names OFF while EllesmereUI's friendly
-- nameplates stay ON.
--
-- EllesmereUI Nameplates forces the UnitNameFriendlyPlayerName CVar to 1 on
-- every load while "Show EUI Friendly Player Nameplates" is enabled
-- (EUI_Nameplates_CastState.lua, SetupAuraCVars). Its nameplates still draw
-- friendly names in range; the CVar only controls the floating names you see
-- beyond nameplate range. We put it back to 0 right after EllesmereUI sets it,
-- plus once more shortly after each login/reload as a fallback.
local _, ns = ...

local CVAR = "UnitNameFriendlyPlayerName"

local M = {
    name = "friendlynames",
    title = "Friendly Names",
    description = "Hide floating friendly player names (EllesmereUI turns them back on at load)",
    defaults = { enabled = true },
}

local function Enforce()
    if not M.db.enabled then return end
    if GetCVar(CVAR) ~= "0" then
        C_CVar.SetCVar(CVAR, "0")
    end
end

function M:OnEnable()
    if self.started then Enforce(); return end
    self.started = true
    -- Post-hook EllesmereUI's CVar helper so we win immediately whenever it
    -- writes this CVar (load, options page, toggles).
    if EllesmereUI and type(EllesmereUI.SetCVar) == "function" and not self.hooked then
        hooksecurefunc(EllesmereUI, "SetCVar", function(name)
            if name == CVAR then Enforce() end
        end)
        self.hooked = true
    end
    -- Fallback: after every login / reload / zone-in, once everything settled.
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", function() C_Timer.After(1, Enforce) end)
    Enforce()
end

function M:OnDisable()
    -- The hook and event frame stay installed but do nothing while disabled.
    ns.Print("friendly names will follow your game/EllesmereUI setting again after /reload")
end

ns.RegisterModule(M)
