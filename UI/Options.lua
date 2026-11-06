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

local function BuildPage(name)
    local mod = ns.modules[name]
    local scroll, content = MakeScroll(frame.PageInset, PageWidth())
    scroll:Hide()
    content.rqModule = name
    content.rqWidgets = {}

    -- Widgets lay out from x = 0; give the page some padding.
    local body = CreateFrame("Frame", nil, content)
    body:SetPoint("TOPLEFT", PAGE_PAD, -PAGE_PAD)
    body:SetSize(content:GetWidth(), 1)

    local y = 0
    local _
    _, y = W.SectionHeader(body, y, ModTitle(mod))
    if mod.description then
        _, y = W.Text(body, y, mod.description, { font = "GameFontHighlightSmall" })
    end
    _, y = W.Checkbox(body, y, {
        label = "Enabled",
        get = function() return ns.IsModuleEnabled(name) end,
        set = function(v) ns.SetModuleEnabled(name, v) end,
    })

    -- For pages whose content grows or shrinks after they are built (lists):
    -- the builder lays its widgets out again and calls body:SetPageHeight(-y).
    function body:SetPageHeight(height)
        self:SetHeight(height)
        content:SetHeight(height + 2 * PAGE_PAD)
    end

    if mod.BuildOptions then
        y = y - W.GAP
        local ok, res = pcall(mod.BuildOptions, mod, body, mod.db, y)
        if not ok then
            geterrorhandler()(res)
            _, y = W.Text(body, y, "|cffff5555This module's options failed to load.|r")
        elseif type(res) == "number" then
            y = res
        else
            -- Builder didn't return its y (it should); leave room to scroll.
            y = y - 600
        end
    end

    content:SetHeight(-y + 2 * PAGE_PAD)
    body:SetHeight(-y)
    scroll.content = content
    pages[name] = scroll
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
    if not ns.modules[name] then name = ns.order[1] end
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
        local on = ns.IsModuleEnabled(name)
        row.Check:SetChecked(on)
        row.Name:SetTextColor(on and 1 or 0.6, on and 1 or 0.6, on and 1 or 0.6)
    end
end

local function BuildSidebar(parent)
    local width = SIDEBAR_W - 8 - SCROLLBAR_W - 2
    local _, list = MakeScroll(parent, width)
    for i, name in ipairs(ns.order) do
        local mod = ns.modules[name]
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

        local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
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

        local fs = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        fs:SetPoint("RIGHT", -4, 0)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        fs:SetText(ModTitle(mod))
        row.Name = fs

        row:SetScript("OnClick", function() Select(name) end)
        ns.Skin("Checkbox", cb)
        ns.Skin("Font", fs)
        rows[name] = row
    end
    list:SetHeight(math.max(1, #ns.order * ROW_H))
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
    Select(ns.uidb.selected or ns.order[1])
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
    RefreshPage(pages[name])
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
