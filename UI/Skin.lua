-- EllesmereUI skin layer. Every RivQoL frame that should be themed goes
-- through ns.Skin(kind, frame, ...). Without EllesmereUI, or with RivQoL's
-- third-party skin turned off in EUI, the skin callback never runs and frames
-- keep the stock Blizzard look.
--
-- kind is the name of an EUI skin primitive: "Shell", "Panel", "Inset",
-- "Button", "Checkbox", "EditBox", "Dropdown", "ScrollBar", "CloseButton",
-- "Font", "SquareIcon", ... (see EllesmereUI/SKINNING_API.md).
local _, ns = ...

local S          -- EUI's skin table, once the callback ran
local pending = {}
local settled = false   -- true once login is over; stop queueing if no skin

local function Apply(kind, frame, ...)
    local fn = S and S[kind]
    if not fn or not frame then return end
    local ok, err = pcall(fn, frame, ...)
    if not ok then geterrorhandler()(err) end
end

function ns.Skin(kind, frame, ...)
    if not frame then return end
    if S then
        Apply(kind, frame, ...)
    elseif not settled then
        table.insert(pending, { kind, frame, n = select("#", ...), ... })
    end
end

function ns.IsSkinned()
    return S ~= nil and (not S.IsEnabled or S.IsEnabled())
end

if EllesmereUI and EllesmereUI.RegisterSkin then
    EllesmereUI.RegisterSkin("RivQoL", function(skin)
        S = skin
        for _, p in ipairs(pending) do
            Apply(p[1], p[2], unpack(p, 3, p.n + 2))
        end
        pending = {}
    end)
end

-- EUI runs the callback at PLAYER_LOGIN. One frame later, if it hasn't run
-- (no EUI or skinning off), drop the queue and stop collecting.
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    C_Timer.After(0, function()
        settled = true
        if not S then pending = {} end
    end)
end)
