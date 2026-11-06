-- Item info on tooltips: hold Alt while hovering an item to see its type,
-- subtype and a few other facts (slot and item level for gear, stack size).
-- Handy for building Loot Filter rules, which pick items by type and subtype.
local _, ns = ...

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant

local M = {
    name = "iteminfo",
    title = "Item Info",
    group = "general",
    description = "Adds an item's type, subtype, slot and stack size to its tooltip, e.g. to pick Loot Filter rule types.",
    defaults = {
        enabled = true,
        altOnly = true,   -- only while Alt is held
        showIDs = false,  -- item ID and type/subtype IDs
    },
}

local LABEL = { 0.6, 0.8, 1 }     -- light blue labels
local VALUE = { 1, 1, 1 }

local function WithID(text, id)
    if M.db.showIDs and id then return string.format("%s (%d)", text or "?", id) end
    return text or "?"
end

local function AddLine(tooltip, label, value)
    tooltip:AddDoubleLine(label, value, LABEL[1], LABEL[2], LABEL[3], VALUE[1], VALUE[2], VALUE[3])
end

function M.AddLines(tooltip, itemID)
    local db = M.db
    if not (db and db.enabled and itemID) then return end
    if db.altOnly and not IsAltKeyDown() then return end

    local _, itemType, itemSubType, equipLoc, _, classID, subclassID = GetItemInfoInstant(itemID)
    if not classID then return end
    local _, _, _, itemLevel, _, _, _, stackCount = GetItemInfo(itemID)

    AddLine(tooltip, "Type", WithID(itemType, classID))
    AddLine(tooltip, "Subtype", WithID(itemSubType, subclassID))
    if equipLoc and equipLoc ~= "" and _G[equipLoc] then
        AddLine(tooltip, "Slot", _G[equipLoc])
        if itemLevel and itemLevel > 0 then AddLine(tooltip, "Item level", tostring(itemLevel)) end
    end
    if stackCount and stackCount > 1 then AddLine(tooltip, "Stacks to", tostring(stackCount)) end
    if db.showIDs then AddLine(tooltip, "Item ID", tostring(itemID)) end
end

local function Watched(tooltip)
    return tooltip == GameTooltip or tooltip == ItemRefTooltip
end

local hooked = false
local function Hook()
    if hooked then return end
    hooked = true
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
            if Watched(tooltip) and data then M.AddLines(tooltip, data.id) end
        end)
    else
        for _, tooltip in ipairs({ GameTooltip, ItemRefTooltip }) do
            tooltip:HookScript("OnTooltipSetItem", function(self)
                local _, link = self:GetItem()
                if link then M.AddLines(self, (GetItemInfoInstant(link))) end
            end)
        end
    end
end

-- Pressing or releasing Alt while hovering an item shows or hides the lines.
local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, _, key)
    if not (M.db.enabled and M.db.altOnly) then return end
    if key ~= "LALT" and key ~= "RALT" then return end
    if not (GameTooltip:IsShown() and GameTooltip:GetItem()) then return end
    if GameTooltip.RefreshData then
        GameTooltip:RefreshData()
        return
    end
    local owner = GameTooltip:GetOwner()
    local onEnter = owner and owner:GetScript("OnEnter")
    if onEnter and owner:IsMouseOver() then onEnter(owner) end
end)

function M:OnEnable()
    Hook()
    frame:RegisterEvent("MODIFIER_STATE_CHANGED")
end

function M:OnDisable()
    -- The tooltip hook stays installed but adds nothing while disabled.
    frame:UnregisterEvent("MODIFIER_STATE_CHANGED")
end

function M:BuildOptions(parent, db, y)
    local W = ns.Widgets
    local _
    _, y = W.Checkbox(parent, y, {
        label = "Only while Alt is held",
        tooltip = "Off: always add the lines to item tooltips.",
        db = db, key = "altOnly",
    })
    _, y = W.Checkbox(parent, y, {
        label = "Show IDs",
        tooltip = "Add the item ID, and the numeric IDs of the type and subtype.",
        db = db, key = "showIDs",
    })
    return y
end

ns.RegisterModule(M)
