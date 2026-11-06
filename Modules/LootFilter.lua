-- Loot filter: when auto-looting, leave junk on the corpse instead of
-- picking it up. Nothing is ever deleted and items already in your bags are
-- never touched; filtered items simply aren't looted.
--
-- While enabled the module does the auto-looting itself: it turns the game's
-- autoLootDefault CVar off (its value seeds the module's own auto-loot
-- toggle, and that toggle is written back to the CVar when the module is
-- disabled), and on LOOT_READY loots every slot except the
-- filtered ones, then closes the window once only skipped items are left.
-- The auto-loot key (Interface > Controls) still inverts auto-loot: the
-- client would otherwise loot everything itself while the key is held, so
-- the module also sets the key binding to NONE while it is on (for this
-- session only, keeping the saved bindings intact) and checks the key itself.
--
-- An item is skipped when it is on the skip list, or when any rule matches it
-- (all of a rule's conditions must hold). Safety rails, checked in order:
--   * coins and currencies are always looted
--   * the never-skip list always wins
--   * the skip list wins over the remaining rails (you asked for it by name)
--   * rules never match quest items, Rare or better items, or (for a rule
--     with a price limit) items with no vendor price
--   * item info not cached yet -> loot it (fail safe)
local _, ns = ...

local CVAR = "autoLootDefault"
local RARE = (Enum.ItemQuality and Enum.ItemQuality.Rare) or 3
local QUEST_CLASS = (Enum.ItemClass and (Enum.ItemClass.Questitem or Enum.ItemClass.QuestItem)) or 12
local BIND_QUEST = 4
local SLOT_ITEM = (Enum.LootSlotType and Enum.LootSlotType.Item) or LOOT_SLOT_ITEM or 1
local SLOT_NONE = (Enum.LootSlotType and Enum.LootSlotType.None) or LOOT_SLOT_NONE or 0
local MODCLICK = "AUTOLOOTTOGGLE"

local SetCVar = (C_CVar and C_CVar.SetCVar) or SetCVar
local GetCVar = (C_CVar and C_CVar.GetCVar) or GetCVar
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant

local M = {
    name = "lootfilter",
    title = "Loot Filter",
    description = "When auto-looting, leave junk you've listed or that matches a rule on the corpse. Nothing is deleted.",
    defaults = {
        enabled = false,    -- it takes over auto-loot, so opt in
        items = {},         -- [itemID] = true: always skip
        never = {},         -- [itemID] = true: always loot
        rules = {},         -- { class = id|nil, subclass = id|nil, maxQuality = n|nil, maxPrice = copper (0 = any) }
        announce = true,    -- chat line per skipped item
        -- autoLoot: our auto-loot on/off, seeded from the game's setting
        -- tookOver: true while we hold autoLootDefault at 0
        -- lootKey: the auto-loot key ("SHIFT", "CTRL", "ALT", "NONE") we read the
        --   binding as when taking over; the binding itself is NONE meanwhile
    },
}

M.skippedCount = 0      -- items left on corpses this session

local frame = CreateFrame("Frame")

---------------------------------------------------------------------------
-- Matching
---------------------------------------------------------------------------

-- Does `rule` match an item with this info? A rule with no conditions at all
-- never matches, so a blank new rule can't skip everything.
local function RuleMatches(rule, classID, subclassID, quality, sellPrice)
    local any = false
    if rule.class ~= nil then
        if classID ~= rule.class then return false end
        any = true
        if rule.subclass ~= nil and subclassID ~= rule.subclass then return false end
    end
    if rule.maxQuality ~= nil then
        if quality > rule.maxQuality then return false end
        any = true
    end
    if rule.maxPrice and rule.maxPrice > 0 then
        if sellPrice <= 0 or sellPrice > rule.maxPrice then return false end
        any = true
    end
    return any
end

-- Should this item be left behind? Returns skip, reason.
function M:ShouldSkipItem(itemID)
    local db = self.db
    if not itemID then return false end
    if db.never[itemID] then return false end
    if db.items[itemID] then return true, "list" end
    if #db.rules == 0 then return false end

    local _, _, quality, _, _, _, _, _, _, _, sellPrice, classID, subclassID, bindType = GetItemInfo(itemID)
    if not quality then
        -- Not cached: we can't tell, so loot it.
        if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
        return false
    end
    if not classID then
        local _
        _, _, _, _, _, classID, subclassID = GetItemInfoInstant(itemID)
    end
    if quality >= RARE or classID == QUEST_CLASS or bindType == BIND_QUEST then return false end
    sellPrice = sellPrice or 0
    for _, rule in ipairs(db.rules) do
        if RuleMatches(rule, classID, subclassID, quality, sellPrice) then return true, "rule" end
    end
    return false
end

local function SlotItemID(slot)
    local link = GetLootSlotLink(slot)
    if not link then return nil, nil end
    local itemID = GetItemInfoInstant(link)
    return itemID, link
end

-- Should loot slot `slot` be left behind?
function M:ShouldSkipSlot(slot)
    if GetLootSlotType(slot) ~= SLOT_ITEM then return false end   -- coins, currency
    local itemID = SlotItemID(slot)
    return (self:ShouldSkipItem(itemID))
end

---------------------------------------------------------------------------
-- Looting
---------------------------------------------------------------------------

local session            -- state for the open loot window, nil when not auto-looting

local KEY_DOWN = {
    SHIFT = function() return IsShiftKeyDown() end,
    CTRL = function() return IsControlKeyDown() end,
    ALT = function() return IsAltKeyDown() end,
}

local function LootKeyDown()
    local key = M.db.lootKey
    if key == nil then return IsModifiedClick(MODCLICK) end   -- binding not taken over (yet)
    local down = KEY_DOWN[key]
    return down and down() or false
end

local function AutoLootApplies()
    local on = M.db.autoLoot and true or false
    if LootKeyDown() then on = not on end
    return on
end

-- Anything (item, coins, currency) still in this slot? LootSlotHasItem is
-- false for coin slots, so check the slot type too.
local function SlotFilled(slot)
    if LootSlotHasItem(slot) then return true end
    local kind = GetLootSlotType(slot)
    return kind ~= nil and kind ~= SLOT_NONE
end

-- Close the window once every item left is one we skip.
local function CloseIfOnlySkipped()
    if not session then return end
    for slot = 1, GetNumLootItems() do
        if SlotFilled(slot) and not session.skipped[slot] then return end
    end
    CloseLoot()
end

local function Announce(link, quantity)
    if not M.db.announce then return end
    ns.Print("left on corpse:", (link or "?") .. ((quantity and quantity > 1) and ("x" .. quantity) or ""))
end

local function OnLootReady(clientAutoLoot)
    if session then return end   -- LOOT_READY can fire more than once per window
    -- The client is looting everything itself (the key binding couldn't be
    -- taken over, e.g. in combat): don't pretend to filter.
    if clientAutoLoot then return end
    if not AutoLootApplies() then return end
    session = { skipped = {} }
    local skippedAny = false
    for slot = GetNumLootItems(), 1, -1 do
        if SlotFilled(slot) then
            if M:ShouldSkipSlot(slot) then
                session.skipped[slot] = true
                skippedAny = true
                local _, link = SlotItemID(slot)
                local quantity = select(3, GetLootSlotInfo(slot))
                M.skippedCount = M.skippedCount + 1
                Announce(link, quantity)
            else
                LootSlot(slot)
            end
        end
    end
    if skippedAny then
        ns.FireChanged(M.name, "skippedCount")
        CloseIfOnlySkipped()   -- nothing else was there
    end
end

frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "LOOT_READY" then
        OnLootReady(arg1 == true or arg1 == 1)
    elseif event == "LOOT_SLOT_CLEARED" then
        CloseIfOnlySkipped()
    elseif event == "LOOT_CLOSED" then
        session = nil
    elseif event == "PLAYER_LOGOUT" then
        -- Hand the CVar back on every logout, so disabling or removing the
        -- addon never leaves auto-loot stuck off. The next login takes over
        -- again and reads the same value back.
        M:Release(M.db)
    elseif event == "CVAR_UPDATE" then
        -- The game's own auto-loot checkbox (or another addon) turned the
        -- CVar back on: take that as the new setting and keep the CVar off.
        -- (The event's arguments differ between clients, so just re-check.)
        if GetCVar(CVAR) == "1" then
            M.db.autoLoot = true
            SetCVar(CVAR, "0")
            ns.FireChanged(M.name, "autoLoot")
        end
    end
end)

---------------------------------------------------------------------------
-- The auto-loot key binding
---------------------------------------------------------------------------
-- With autoLootDefault at 0, holding the auto-loot key makes the client loot
-- everything itself, filters or not. So while we're on, the binding is NONE
-- and LootKeyDown() checks db.lootKey instead. The change is never saved: if
-- something saves the key bindings meanwhile, we write the real key back.

local keyFrame = CreateFrame("Frame")
local holdingKey = false     -- binding set to NONE by us this session
local wantKey                -- "take" / "release" waiting for combat to end
local savingBindings = false

local function CanBind()
    return GetModifiedClick and SetModifiedClick and true or false
end

local function TakeKey(db)
    if holdingKey or not CanBind() then return end
    if InCombatLockdown() then wantKey = "take"; keyFrame:RegisterEvent("PLAYER_REGEN_ENABLED"); return end
    local current = GetModifiedClick(MODCLICK)
    -- After a crash db.lootKey survives; the binding then still reads as the
    -- saved (real) key, which wins unless it reads NONE.
    if db.lootKey == nil or (current and current ~= "NONE") then db.lootKey = current or "NONE" end
    SetModifiedClick(MODCLICK, "NONE")
    holdingKey = true
end

local function ReleaseKey(db)
    if not holdingKey then db.lootKey = nil; return end
    if InCombatLockdown() then wantKey = "release"; keyFrame:RegisterEvent("PLAYER_REGEN_ENABLED"); return end
    SetModifiedClick(MODCLICK, db.lootKey or "NONE")
    holdingKey = false
    db.lootKey = nil
end

keyFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    local want = wantKey
    wantKey = nil
    if want == "take" and M.db.tookOver then TakeKey(M.db)
    elseif want == "release" and not M.db.tookOver then ReleaseKey(M.db) end
end)

if hooksecurefunc and SaveBindings then
    hooksecurefunc("SaveBindings", function(set)
        if not holdingKey or savingBindings then return end
        local current = GetModifiedClick(MODCLICK)
        if current and current ~= "NONE" then
            -- You picked a new auto-loot key (Interface > Controls): that is
            -- what got saved, so adopt it and hold the binding again.
            M.db.lootKey = current
            SetModifiedClick(MODCLICK, "NONE")
        else
            -- Something else saved the bindings with our NONE in them: save
            -- again with the real key.
            savingBindings = true
            SetModifiedClick(MODCLICK, M.db.lootKey or "NONE")
            pcall(SaveBindings, set or GetCurrentBindingSet())
            SetModifiedClick(MODCLICK, "NONE")
            savingBindings = false
        end
    end)
end

function M:OnEnable(db)
    if not db.tookOver then
        -- Seed our toggle from the game's setting. Only when taking over:
        -- after a crash (no PLAYER_LOGOUT) the CVar still holds our own "0".
        db.autoLoot = GetCVar(CVAR) == "1"
        db.tookOver = true
    end
    if GetCVar(CVAR) ~= "0" then SetCVar(CVAR, "0") end
    TakeKey(db)
    frame:RegisterEvent("LOOT_READY")
    frame:RegisterEvent("LOOT_SLOT_CLEARED")
    frame:RegisterEvent("LOOT_CLOSED")
    frame:RegisterEvent("CVAR_UPDATE")
    frame:RegisterEvent("PLAYER_LOGOUT")
end

-- Give autoLootDefault (as our toggle has it now) and the auto-loot key
-- back to the game.
function M:Release(db)
    frame:UnregisterAllEvents()
    session = nil
    ReleaseKey(db)
    if db.tookOver then
        -- Hand auto-loot back to the game, as it is set now (the game's
        -- value from before, unless you changed it while we had it).
        SetCVar(CVAR, db.autoLoot and "1" or "0")
        db.tookOver = nil
    end
end

function M:OnDisable(db)
    self:Release(db)
end

-- Auto-loot as the player sees it: ours while we hold the CVar, otherwise
-- the game's own setting (so the toggle works with the module off too).
function M:GetAutoLoot()
    if self.db.tookOver then return self.db.autoLoot and true or false end
    return GetCVar(CVAR) == "1"
end

function M:SetAutoLoot(on)
    on = not not on
    if self.db.tookOver then
        self.db.autoLoot = on
    else
        SetCVar(CVAR, on and "1" or "0")
    end
    ns.FireChanged(self.name, "autoLoot")
end

---------------------------------------------------------------------------
-- Options page
---------------------------------------------------------------------------

local GetItemClassInfo = (C_Item and C_Item.GetItemClassInfo) or GetItemClassInfo
local GetItemSubClassInfo = (C_Item and C_Item.GetItemSubClassInfo) or GetItemSubClassInfo
local ANY = -1          -- dropdown value for "no condition"
local ROW_H = 24

local page              -- the module's options page (set by BuildOptions)
local Rebuild           -- lays out the lists and rules again

local function OtherList(list) return list == "items" and "never" or "items" end

-- Put an item on the skip ("items") or never-skip ("never") list. An item is
-- only ever on one of them.
function M:AddItem(list, itemID)
    if not itemID then return end
    self.db[list][itemID] = true
    self.db[OtherList(list)][itemID] = nil
    if Rebuild then Rebuild() end
    ns.FireChanged(self.name, list)
end

function M:RemoveItem(list, itemID)
    self.db[list][itemID] = nil
    if Rebuild then Rebuild() end
    ns.FireChanged(self.name, list)
end

-- Refresh `obj` along with the page's other widgets.
local function TrackOnPage(parent, obj)
    local f = parent
    while f and not f.rqWidgets do f = f:GetParent() end
    if f then table.insert(f.rqWidgets, obj) end
end

local function SortedIDs(set)
    local ids = {}
    for id in pairs(set) do ids[#ids + 1] = id end
    table.sort(ids)
    return ids
end

local function SetItemName(fs, itemID)
    local function Apply()
        local name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
        local quality = C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(itemID)
        fs:SetText(name or ("item:" .. itemID))
        local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
        if color then fs:SetTextColor(color.r, color.g, color.b) else fs:SetTextColor(1, 1, 1) end
        return name ~= nil
    end
    if not Apply() and Item and Item.CreateFromItemID then
        local item = Item:CreateFromItemID(itemID)
        if not item:IsItemEmpty() then item:ContinueOnItemLoad(Apply) end
    end
end

-- One list row: icon, name (tooltip on hover) and a Remove button.
local function ItemRow(parent, y, list, itemID)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", 0, y)
    row:SetSize(math.min(parent:GetWidth() - 16, 420), ROW_H)

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("LEFT", 2, 0)
    icon:SetTexture(C_Item.GetItemIconByID(itemID))

    local remove = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    remove:SetSize(70, 20)
    remove:SetPoint("RIGHT")
    remove:SetText(REMOVE or "Remove")
    remove:SetScript("OnClick", function() M:RemoveItem(list, itemID) end)
    ns.Skin("Button", remove)

    local name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    name:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    name:SetPoint("RIGHT", remove, "LEFT", -6, 0)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    ns.Skin("Font", name)
    SetItemName(name, itemID)

    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(itemID)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    return row, y - ROW_H - 2
end

local function ItemListSection(parent, y, list, title, help, dropLabel)
    local W = ns.Widgets
    local _
    _, y = W.SectionHeader(parent, y, title)
    _, y = W.Text(parent, y, help, { font = "GameFontHighlightSmall" })
    _, y = W.ItemDropSlot(parent, y, {
        label = dropLabel,
        tooltip = "Drag an item from your bags onto this slot, or Alt-click an item in your bags while this page is open.",
        onItem = function(itemID) M:AddItem(list, itemID) end,
    })
    local ids = SortedIDs(M.db[list])
    if #ids == 0 then
        _, y = W.Text(parent, y, "No items yet.", { font = "GameFontDisable" })
    end
    for _, id in ipairs(ids) do
        local _row
        _row, y = ItemRow(parent, y, list, id)
    end
    return y - W.GAP
end

local function ClassChoices()
    local choices = { { value = ANY, text = "Any type" } }
    for classID = 0, 20 do
        local name = GetItemClassInfo(classID)
        if name and name ~= "" then choices[#choices + 1] = { value = classID, text = name } end
    end
    return choices
end

local function SubclassChoices(classID)
    local choices = { { value = ANY, text = "Any subtype" } }
    if classID == nil then return choices end
    for sub = 0, 40 do
        local name = GetItemSubClassInfo(classID, sub)
        if name and name ~= "" then choices[#choices + 1] = { value = sub, text = name } end
    end
    return choices
end

local function QualityChoices()
    local choices = { { value = ANY, text = "Any quality" } }
    for q = 0, RARE - 1 do
        local name = _G["ITEM_QUALITY" .. q .. "_DESC"] or tostring(q)
        local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
        if color and color.hex then name = color.hex .. name .. "|r" end
        choices[#choices + 1] = { value = q, text = name }
    end
    return choices
end

local function HasCondition(rule)
    return rule.class ~= nil or rule.maxQuality ~= nil or (rule.maxPrice or 0) > 0
end

local function RuleBlock(parent, y, index, rule)
    local W = ns.Widgets
    local _
    local header = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    header:SetPoint("TOPLEFT", 0, y)
    header:SetText("Rule " .. index)
    ns.Skin("Font", header)
    local delete = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    delete:SetSize(70, 20)
    delete:SetPoint("LEFT", header, "RIGHT", 12, 0)
    delete:SetText(DELETE or "Delete")
    delete:SetScript("OnClick", function()
        table.remove(M.db.rules, index)
        Rebuild()
        ns.FireChanged(M.name, "rules")
    end)
    ns.Skin("Button", delete)
    y = y - 22 - W.GAP

    local warning
    local function UpdateWarning()
        warning:SetShown(not HasCondition(rule))
    end
    local function Changed()
        UpdateWarning()
        ns.FireChanged(M.name, "rules")
    end

    local subtype
    _, y = W.Dropdown(parent, y, {
        x = 12, label = "Type",
        choices = ClassChoices,
        get = function() return rule.class or ANY end,
        set = function(v)
            rule.class = v ~= ANY and v or nil
            rule.subclass = nil
            subtype:Refresh()
            Changed()
        end,
    })
    subtype, y = W.Dropdown(parent, y, {
        x = 12, label = "Subtype",
        choices = function() return SubclassChoices(rule.class) end,
        get = function() return rule.subclass or ANY end,
        set = function(v) rule.subclass = v ~= ANY and v or nil; Changed() end,
        tooltip = "Only used together with a type.",
    })
    _, y = W.Dropdown(parent, y, {
        x = 12, label = "Max quality",
        choices = QualityChoices,
        get = function() return rule.maxQuality or ANY end,
        set = function(v) rule.maxQuality = v ~= ANY and v or nil; Changed() end,
        tooltip = "Items of this quality or lower. Rare and better items are never skipped by rules.",
    })
    _, y = W.MoneyInput(parent, y, {
        x = 12, label = "Max sell price",
        get = function() return rule.maxPrice or 0 end,
        set = function(v) rule.maxPrice = v; Changed() end,
        tooltip = "Vendor price per item, at most this much. 0 = any price. With a limit set, items that can't be sold to a vendor are never skipped.",
    })
    warning, y = W.Text(parent, y, "|cffff8800This rule has no conditions yet, so it skips nothing.|r",
        { x = 12, font = "GameFontHighlightSmall" })
    UpdateWarning()
    return y - W.GAP
end

local function RulesSection(parent, y)
    local W = ns.Widgets
    local _
    _, y = W.SectionHeader(parent, y, "Rules")
    _, y = W.Text(parent, y, "An item is skipped when all conditions of any rule match it. Rules never skip quest items or Rare and better items.",
        { font = "GameFontHighlightSmall" })
    for i, rule in ipairs(M.db.rules) do
        y = RuleBlock(parent, y, i, rule)
    end
    _, y = W.Button(parent, y, {
        text = "Add rule",
        onClick = function()
            table.insert(M.db.rules, { maxPrice = 0 })
            Rebuild()
            ns.FireChanged(M.name, "rules")
        end,
    })
    return y
end

-- Alt-click an item in your bags while the page is open to add it to the
-- skip list.
local function HookAltClick()
    if M.altHooked or not HandleModifiedItemClick then return end
    M.altHooked = true
    hooksecurefunc("HandleModifiedItemClick", function(link)
        if not (page and page:IsVisible()) then return end
        if not IsAltKeyDown() or IsShiftKeyDown() or IsControlKeyDown() then return end
        local itemID = type(link) == "string" and GetItemInfoInstant(link)
        if itemID then
            M:AddItem("items", itemID)
            ns.Print("added to the skip list:", link)
        end
    end)
end

function M:BuildOptions(parent, db, y)
    local W = ns.Widgets
    local _
    page = parent

    _, y = W.SectionHeader(parent, y, "Looting")
    _, y = W.Checkbox(parent, y, {
        label = "Auto-loot",
        tooltip = "While this module is on it does the auto-looting and replaces the game's Auto Loot setting (Interface > Controls), which it hands back when turned off. The auto-loot key still inverts it.",
        get = function() return M:GetAutoLoot() end,
        set = function(v) M:SetAutoLoot(v) end,
    })
    _, y = W.Checkbox(parent, y, {
        label = "Announce skipped items in chat",
        db = db, key = "announce",
    })
    local count
    count, y = W.Text(parent, y, "", { font = "GameFontHighlightSmall" })
    function count:Refresh()
        self:SetText("Left on corpses this session: " .. M.skippedCount)
    end
    count:Refresh()
    TrackOnPage(parent, count)
    _, y = W.Text(parent, y, "Filters only apply while auto-looting. When you loot by hand, you pick what to take. Coins and currencies are always looted, and nothing is ever deleted.",
        { font = "GameFontHighlightSmall" })
    y = y - W.GAP

    -- Everything below is laid out again whenever a list or the rules change.
    local top = y
    local holder
    Rebuild = function()
        if holder then holder:Hide() end
        holder = CreateFrame("Frame", nil, parent)
        holder:SetPoint("TOPLEFT", 0, top)
        holder:SetSize(parent:GetWidth(), 1)
        holder.rqWidgets = {}   -- keep rebuilt widgets off the page's list
        local h = 0
        h = ItemListSection(holder, h, "items", "Always skip",
            "Left on the corpse whenever you auto-loot, even Rare or quest items.", "Drop an item to always skip")
        h = ItemListSection(holder, h, "never", "Never skip",
            "Always looted, whatever the rules say.", "Drop an item to never skip")
        h = RulesSection(holder, h)
        holder:SetHeight(-h)
        if parent.SetPageHeight then parent:SetPageHeight(-(top + h)) end
        return top + h
    end
    HookAltClick()
    return Rebuild()
end

ns.RegisterModule(M)
