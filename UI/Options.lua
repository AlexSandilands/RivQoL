-- The RivQoL options window: module list on the left (on/off checkbox per
-- module), the selected module's page on the right. Built lazily the first
-- time it opens; stock Blizzard templates, themed through ns.Skin.
local _, ns = ...
local W = ns.Widgets

local FRAME_W, FRAME_H = 760, 520      -- default size; the window can be resized
local MIN_W, MIN_H = 620, 380
local SIDEBAR_W = 190
local TOP, BOTTOM, SIDE = -60, 8, 8     -- inset margins inside the window
local ROW_H = 26
local PAGE_PAD = 12
local SCROLLBAR_W = 22

local frame             -- the window
local rows = {}         -- module name -> sidebar row
local pages = {}        -- module name -> built page (scroll frame)
local selected

local function ModTitle(mod)
    return mod.title or mod.name
end

local function SavePosition(self)
    local point, _, relPoint, x, y = self:GetPoint(1)
    ns.uidb.point = { point, relPoint, x, y }
end

local function RestorePosition(self)
    self:ClearAllPoints()
    local p = ns.uidb and ns.uidb.point
    if p then
        self:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        self:SetPoint("CENTER")
    end
end

-- A ScrollFrame with a scroll child of fixed width; returns scroll, child.
local function MakeScroll(parent, width)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "ScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", -SCROLLBAR_W - 2, 4)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(width, 1)
    scroll:SetScrollChild(child)
    ns.Skin("ScrollBar", scroll.ScrollBar)
    return scroll, child
end

---------------------------------------------------------------------------
-- Pages
---------------------------------------------------------------------------

local function RefreshPage(page)
    if not page then return end
    for _, w in ipairs(page.content.rqWidgets) do
        if w.Refresh then w:Refresh() end
    end
end

-- Width of a page's scroll child for the window's current size.
local function PageWidth()
    return frame:GetWidth() - SIDEBAR_W - 2 * SIDE - 6 - 8 - SCROLLBAR_W - 2 * PAGE_PAD
end

-- Small modules set `group = "general"`: they share the General page (and
-- one sidebar entry) instead of each getting their own.
local GENERAL = "general"
local GROUP_INFO = {
    [GENERAL] = { title = "General", description = "Small tweaks, each with its own on/off switch." },
}

-- The sidebar entry / page a module lives on.
local function PageKey(name)
    local mod = ns.modules[name]
    return mod and mod.group or name
end

-- Sidebar entries in order: groups first (where they have modules), then
-- the modules with a page of their own.
local function Entries()
    local list, seen = {}, {}
    for _, name in ipairs(ns.order) do
        local group = ns.modules[name].group
        if group and not seen[group] then
            seen[group] = true
            table.insert(list, group)
        end
    end
    for _, name in ipairs(ns.order) do
        if not ns.modules[name].group then table.insert(list, name) end
    end
    return list
end

local function EntryTitle(key)
    return GROUP_INFO[key] and GROUP_INFO[key].title or ModTitle(ns.modules[key])
end

-- A module's own options under `y` on `parent`; returns the new y.
local function BuildModuleOptions(mod, parent, y)
    if not mod.BuildOptions then return y end
    y = y - W.GAP
    local ok, res = pcall(mod.BuildOptions, mod, parent, mod.db, y)
    if not ok then
        geterrorhandler()(res)
        local _
        _, y = W.Text(parent, y, "|cffff5555This module's options failed to load.|r")
        return y
    elseif type(res) == "number" then
        return res
    end
    return y - 600   -- builder didn't return its y (it should); leave room to scroll
end

local function EnabledCheckbox(parent, y, name, label)
    return W.Checkbox(parent, y, {
        label = label,
        get = function() return ns.IsModuleEnabled(name) end,
        set = function(v) ns.SetModuleEnabled(name, v) end,
    })
end

local function BuildPage(key)
    local group = GROUP_INFO[key]
    local scroll, content = MakeScroll(frame.PageInset, PageWidth())
    scroll:Hide()
    content.rqModule = not group and key or nil
    content.rqWidgets = {}

    -- Widgets lay out from x = 0; give the page some padding.
    local body = CreateFrame("Frame", nil, content)
    body:SetPoint("TOPLEFT", PAGE_PAD, -PAGE_PAD)
    body:SetSize(content:GetWidth(), 1)

    -- For pages whose content grows or shrinks after they are built (lists):
    -- the builder lays its widgets out again and calls body:SetPageHeight(-y).
    function body:SetPageHeight(height)
        self:SetHeight(height)
        content:SetHeight(height + 2 * PAGE_PAD)
    end

    local y = 0
    local _
    if group then
        _, y = W.SectionHeader(body, y, group.title)
        _, y = W.Text(body, y, group.description, { font = "GameFontHighlightSmall" })
        for _, name in ipairs(ns.order) do
            local mod = ns.modules[name]
            if mod.group == key then
                -- Each module gets its own frame, so its db/key widgets
                -- report changes for that module.
                local section = CreateFrame("Frame", nil, body)
                section:SetPoint("TOPLEFT", 0, y - W.GAP)
                section:SetSize(body:GetWidth(), 1)
                section.rqModule = name
                local sy = 0
                _, sy = EnabledCheckbox(section, sy, name, ModTitle(mod))
                if mod.description then
                    _, sy = W.Text(section, sy + 4, mod.description, { x = 30, font = "GameFontHighlightSmall" })
                end
                local inner = CreateFrame("Frame", nil, section)
                inner:SetPoint("TOPLEFT", 30, sy)
                inner:SetSize(section:GetWidth() - 30, 1)
                sy = sy + BuildModuleOptions(mod, inner, 0)
                section:SetHeight(-sy)
                y = y - W.GAP + sy - W.GAP
            end
        end
    else
        local mod = ns.modules[key]
        _, y = W.SectionHeader(body, y, ModTitle(mod))
        if mod.description then
            _, y = W.Text(body, y, mod.description, { font = "GameFontHighlightSmall" })
        end
        _, y = EnabledCheckbox(body, y, key, "Enabled")
        y = BuildModuleOptions(mod, body, y)
    end

    content:SetHeight(-y + 2 * PAGE_PAD)
    body:SetHeight(-y)
    scroll.content = content
    pages[key] = scroll
    return scroll
end

local Select

-- Widgets size their text to the page width when they are built, so after a
-- resize the pages are built again (the old ones are hidden and dropped).
local function RelayoutPages()
    for _, page in pairs(pages) do page:Hide() end
    wipe(pages)
    if selected then Select(selected) end
end

function Select(name)
    -- A page key ("general" or a module with its own page), or a module
    -- name, which opens the page it lives on.
    if name and ns.modules[name] then name = PageKey(name) end
    if not (GROUP_INFO[name] or ns.modules[name]) then name = Entries()[1] end
    if not name then return end
    selected = name
    ns.uidb.selected = name
    for n, page in pairs(pages) do page:SetShown(n == name) end
    local page = pages[name] or BuildPage(name)
    page:Show()
    RefreshPage(page)
    for n, row in pairs(rows) do row.Selected:SetShown(n == name) end
end

---------------------------------------------------------------------------
-- Sidebar
---------------------------------------------------------------------------

local function RefreshRows()
    for name, row in pairs(rows) do
        if row.Check then
            local on = ns.IsModuleEnabled(name)
            row.Check:SetChecked(on)
            row.Name:SetTextColor(on and 1 or 0.6, on and 1 or 0.6, on and 1 or 0.6)
        end
    end
end

local function BuildSidebar(parent)
    local width = SIDEBAR_W - 8 - SCROLLBAR_W - 2
    local _, list = MakeScroll(parent, width)
    local entries = Entries()
    for i, name in ipairs(entries) do
        local isGroup = GROUP_INFO[name] ~= nil
        local row = CreateFrame("Button", nil, list)
        row:SetSize(width, ROW_H)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)

        local sel = row:CreateTexture(nil, "BACKGROUND")
        sel:SetAllPoints()
        sel:SetColorTexture(1, 0.82, 0, 0.18)
        sel:Hide()
        row.Selected = sel
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.08)

        -- A group has no single on/off switch: its modules have theirs on
        -- its page. The name still lines up with the other rows.
        local cb
        if not isGroup then
            cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
            cb:SetSize(22, 22)
            cb:SetPoint("LEFT", 2, 0)
            cb:SetScript("OnClick", function(self)
                ns.SetModuleEnabled(name, self:GetChecked())
            end)
            cb:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(ns.IsModuleEnabled(name) and "Turn off" or "Turn on", 1, 1, 1)
                GameTooltip:Show()
            end)
            cb:SetScript("OnLeave", GameTooltip_Hide)
            row.Check = cb
            ns.Skin("Checkbox", cb)
        end

        local fs = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        fs:SetPoint("LEFT", row, "LEFT", 2 + 22 + 4, 0)
        fs:SetPoint("RIGHT", -4, 0)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        fs:SetText(EntryTitle(name))
        row.Name = fs

        row:SetScript("OnClick", function() Select(name) end)
        ns.Skin("Font", fs)
        rows[name] = row
    end
    list:SetHeight(math.max(1, #entries * ROW_H))
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

local function Create()
    frame = CreateFrame("Frame", "RivQoLOptionsFrame", UIParent, "ButtonFrameTemplate")
    local size = ns.uidb.size
    frame:SetSize(size and size[1] or FRAME_W, size and size[2] or FRAME_H)
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    if ButtonFrameTemplate_HidePortrait then ButtonFrameTemplate_HidePortrait(frame) end
    if ButtonFrameTemplate_HideButtonBar then ButtonFrameTemplate_HideButtonBar(frame) end
    if frame.SetTitle then
        frame:SetTitle("RivQoL")
    elseif frame.TitleText then
        frame.TitleText:SetText("RivQoL")
    end

    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition(self)
    end)
    RestorePosition(frame)
    tinsert(UISpecialFrames, "RivQoLOptionsFrame")

    -- Resize grip in the bottom-right corner.
    frame:SetResizable(true)
    local maxW, maxH = UIParent:GetWidth(), UIParent:GetHeight()
    if frame.SetResizeBounds then
        frame:SetResizeBounds(MIN_W, MIN_H, maxW, maxH)
    elseif frame.SetMinResize then
        frame:SetMinResize(MIN_W, MIN_H)
        frame:SetMaxResize(maxW, maxH)
    end
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -3, 3)
    grip:SetFrameLevel(frame:GetFrameLevel() + 20)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then frame:StartSizing("BOTTOMRIGHT") end
    end)
    grip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        ns.uidb.size = { math.floor(frame:GetWidth() + 0.5), math.floor(frame:GetHeight() + 0.5) }
        SavePosition(frame)
        RelayoutPages()
    end)
    grip:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Drag to resize", 1, 1, 1)
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", GameTooltip_Hide)
    frame.ResizeGrip = grip

    -- Template's Inset becomes the page area; add a matching sidebar inset.
    local pageInset = frame.Inset
    pageInset:ClearAllPoints()
    pageInset:SetPoint("TOPLEFT", SIDE + SIDEBAR_W + 6, TOP)
    pageInset:SetPoint("BOTTOMRIGHT", -SIDE, BOTTOM)
    frame.PageInset = pageInset

    local side = CreateFrame("Frame", nil, frame, "InsetFrameTemplate")
    side:SetPoint("TOPLEFT", SIDE, TOP)
    side:SetPoint("BOTTOMLEFT", SIDE, BOTTOM)
    side:SetWidth(SIDEBAR_W)
    frame.SideInset = side

    local hint = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", side, "TOPLEFT", 4, 6)
    hint:SetText("Modules")

    BuildSidebar(side)

    ns.Skin("Shell", frame)
    ns.Skin("CloseButton", frame.CloseButton)
    ns.Skin("Inset", side)
    ns.Skin("Inset", pageInset)

    frame:HookScript("OnShow", function()
        RefreshRows()
        RefreshPage(pages[selected])
    end)
    frame:Hide()
    Select(ns.uidb.selected)
end

function ns.OpenOptions(name)
    if not frame then Create() end
    if name then Select(name) end
    frame:Show()
    frame:Raise()
end

function ns.ToggleOptions()
    if frame and frame:IsShown() then
        frame:Hide()
    else
        ns.OpenOptions()
    end
end

-- Keep the window in sync with slash commands and other changes.
ns.RegisterCallback(function(name)
    if not frame or not frame:IsShown() then return end
    RefreshRows()
    RefreshPage(pages[PageKey(name)])
end)

---------------------------------------------------------------------------
-- Esc > Options > AddOns entry
---------------------------------------------------------------------------

local function RegisterSettingsPage()
    local panel = CreateFrame("Frame")
    panel.name = "RivQoL"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("RivQoL")

    local text = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    text:SetText("Module settings live in RivQoL's own window (also /rivqol).")

    local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    button:SetSize(160, 24)
    button:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -12)
    button:SetText("Open RivQoL")
    button:SetScript("OnClick", function()
        if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        ns.OpenOptions()
    end)
    ns.Skin("Button", button)

    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, "RivQoL")
        Settings.RegisterAddOnCategory(category)
        ns.settingsCategory = category
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

RegisterSettingsPage()
