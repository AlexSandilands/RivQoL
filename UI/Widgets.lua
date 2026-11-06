-- Shared option widgets for module pages, built from stock Blizzard
-- templates and themed through ns.Skin when EllesmereUI skinning is on.
--
-- Every builder lays out top-down:   widget, y = W.Checkbox(page, y, opts)
-- `y` is the (negative) offset from the parent's top; the returned `y` is
-- where the next widget goes. opts.x indents (default 0).
--
-- Value-bound widgets take either opts.get/opts.set, or opts.db + opts.key.
-- With db/key, a change also fires ns.FireChanged(module, key), where module
-- is opts.module or the page's module. Each widget has :Refresh(), which the
-- options window calls on every visible widget after any setting changes.
local _, ns = ...

local W = {}
ns.Widgets = W

local GAP = 8          -- vertical space between widgets
W.GAP = GAP

local function FindModule(frame)
    while frame do
        if frame.rqModule then return frame.rqModule end
        frame = frame:GetParent()
    end
end

-- Register a widget on its page so the window can refresh it.
local function Track(parent, widget)
    local f = parent
    while f and not f.rqWidgets do f = f:GetParent() end
    if f then table.insert(f.rqWidgets, widget) end
end

local function Bind(parent, opts)
    if opts.get then return opts.get, opts.set or function() end end
    local db, key = opts.db, opts.key
    assert(db and key, "RivQoL widget needs get/set or db/key")
    local module = opts.module or FindModule(parent)
    return function() return db[key] end, function(v)
        if db[key] == v then return end
        db[key] = v
        if module then ns.FireChanged(module, key) end
    end
end

local function Tooltip(frame, title, text)
    if not text then return end
    frame:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title or "", 1, 1, 1)
        GameTooltip:AddLine(text, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", GameTooltip_Hide)
end

local function Width(parent, x)
    local w = parent:GetWidth()
    if not w or w <= 1 then w = 400 end
    return w - (x or 0) - 16
end

-- Section header: large gold text with a thin divider under it.
function W.SectionHeader(parent, y, text, opts)
    opts = opts or {}
    local x = opts.x or 0
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    ns.Skin("Font", fs)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.15)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -4)
    line:SetWidth(Width(parent, x))
    fs.Line = line
    return fs, y - fs:GetStringHeight() - 4 - 1 - GAP
end

-- Wrapped body text.
function W.Text(parent, y, text, opts)
    opts = opts or {}
    local x = opts.x or 0
    local fs = parent:CreateFontString(nil, "ARTWORK", opts.font or "GameFontHighlight")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetWidth(opts.width or Width(parent, x))
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(true)
    fs:SetText(text)
    ns.Skin("Font", fs)
    return fs, y - fs:GetStringHeight() - GAP
end

-- Checkbox with a label. opts: label, tooltip, get/set or db/key, onChange(v)
function W.Checkbox(parent, y, opts)
    local get, set = Bind(parent, opts)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    cb:SetPoint("TOPLEFT", opts.x or 0, y)
    local label = cb.Text or cb.text
    if not label then
        label = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    end
    label:SetFontObject("GameFontHighlight")
    label:SetText(opts.label or "")
    cb.Label = label
    cb:SetScript("OnClick", function(self)
        local v = self:GetChecked() and true or false
        set(v)
        if opts.onChange then opts.onChange(v) end
    end)
    function cb:Refresh() self:SetChecked(get() and true or false) end
    Tooltip(cb, opts.label, opts.tooltip)
    cb:Refresh()
    ns.Skin("Checkbox", cb)
    ns.Skin("Font", label)
    Track(parent, cb)
    return cb, y - 26 - GAP
end

-- Push button. opts: text, width, onClick, tooltip
function W.Button(parent, y, opts)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(opts.width or 140, opts.height or 22)
    b:SetPoint("TOPLEFT", opts.x or 0, y)
    b:SetText(opts.text or "")
    if opts.onClick then b:SetScript("OnClick", opts.onClick) end
    Tooltip(b, opts.text, opts.tooltip)
    ns.Skin("Button", b)
    return b, y - b:GetHeight() - GAP
end

-- Slider with label on the left and value on the right.
-- opts: label, min, max, step (default 1), format(v) -> string, width,
--       get/set or db/key, tooltip
function W.Slider(parent, y, opts)
    local get, set = Bind(parent, opts)
    local min, max, step = opts.min or 0, opts.max or 100, opts.step or 1
    local x = opts.x or 0
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetPoint("TOPLEFT", x, y)
    holder:SetSize(opts.width or math.min(Width(parent, x), 420), 26)

    local label = holder:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("LEFT")
    label:SetWidth(140)
    label:SetJustifyH("LEFT")
    label:SetText(opts.label or "")
    ns.Skin("Font", label)

    local slider = CreateFrame("Slider", nil, holder, "MinimalSliderWithSteppersTemplate")
    slider:SetPoint("LEFT", label, "RIGHT", 8, 0)
    slider:SetPoint("RIGHT", holder, "RIGHT", -40, 0)
    slider:SetHeight(20)
    local fmt = opts.format or function(v) return tostring(v) end
    local steps = math.max(1, math.floor((max - min) / step + 0.5))
    slider:Init(get() or min, min, max, steps, {
        [MinimalSliderWithSteppersMixin.Label.Right] = CreateMinimalSliderFormatter(
            MinimalSliderWithSteppersMixin.Label.Right, fmt),
    })
    slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, v)
        if holder.updating then return end
        v = min + math.floor((v - min) / step + 0.5) * step
        set(v)
    end, holder)
    holder.Slider, holder.Label = slider, label

    function holder:Refresh()
        self.updating = true
        slider:SetValue(get() or min)
        self.updating = false
    end
    Tooltip(holder, opts.label, opts.tooltip)
    Track(parent, holder)
    return holder, y - 26 - GAP
end

-- Gold / silver / copper input bound to a copper amount.
-- opts: label, get/set or db/key, tooltip
function W.MoneyInput(parent, y, opts)
    local get, set = Bind(parent, opts)
    local x = opts.x or 0
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetPoint("TOPLEFT", x, y)
    holder:SetSize(360, 24)

    local label = holder:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("LEFT")
    label:SetWidth(140)
    label:SetJustifyH("LEFT")
    label:SetText(opts.label or "")
    ns.Skin("Font", label)

    local parts = {
        { key = "gold",   width = 56, icon = "Interface\\MoneyFrame\\UI-GoldIcon",   mult = 10000 },
        { key = "silver", width = 30, icon = "Interface\\MoneyFrame\\UI-SilverIcon", mult = 100,  max = 99 },
        { key = "copper", width = 30, icon = "Interface\\MoneyFrame\\UI-CopperIcon", mult = 1,    max = 99 },
    }
    local anchor, boxes = label, {}

    local function Commit()
        local total = 0
        for _, p in ipairs(parts) do
            local n = tonumber(p.box:GetText()) or 0
            if p.max and n > p.max then n = p.max end
            total = total + n * p.mult
        end
        set(total)
    end

    for i, p in ipairs(parts) do
        local box = CreateFrame("EditBox", nil, holder, "InputBoxTemplate")
        box:SetSize(p.width, 20)
        box:SetPoint("LEFT", anchor, "RIGHT", i == 1 and 12 or 6, 0)
        box:SetAutoFocus(false)
        box:SetNumeric(true)
        box:SetMaxLetters(p.max and 2 or 7)
        box:SetJustifyH("RIGHT")
        box:SetScript("OnTextChanged", function(_, user) if user then Commit() end end)
        box:SetScript("OnEnterPressed", EditBox_ClearFocus)
        box:SetScript("OnEscapePressed", function(self) self:ClearFocus(); holder:Refresh() end)
        box:SetScript("OnEditFocusLost", function() holder:Refresh() end)
        local icon = holder:CreateTexture(nil, "ARTWORK")
        icon:SetSize(13, 13)
        icon:SetTexture(p.icon)
        icon:SetPoint("LEFT", box, "RIGHT", 2, 0)
        ns.Skin("EditBox", box)
        p.box, anchor = box, icon
        boxes[p.key] = box
    end
    holder.Boxes, holder.Label = boxes, label

    function holder:Refresh()
        local c = get() or 0
        local values = { gold = math.floor(c / 10000), silver = math.floor(c / 100) % 100, copper = c % 100 }
        for _, p in ipairs(parts) do
            if not p.box:HasFocus() then p.box:SetText(tostring(values[p.key])) end
        end
    end
    Tooltip(holder, opts.label, opts.tooltip)
    holder:Refresh()
    Track(parent, holder)
    return holder, y - 24 - GAP
end

-- Single-choice dropdown.
-- opts: label, choices = { {value=, text=}, ... } or function() -> choices,
--       width, get/set or db/key, tooltip
function W.Dropdown(parent, y, opts)
    local get, set = Bind(parent, opts)
    local x = opts.x or 0
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetPoint("TOPLEFT", x, y)
    holder:SetSize(360, 26)

    local label = holder:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("LEFT")
    label:SetWidth(140)
    label:SetJustifyH("LEFT")
    label:SetText(opts.label or "")
    ns.Skin("Font", label)

    local dd = CreateFrame("DropdownButton", nil, holder, "WowStyle1DropdownTemplate")
    dd:SetWidth(opts.width or 180)
    dd:SetPoint("LEFT", label, "RIGHT", 8, 0)
    dd:SetupMenu(function(_, root)
        local choices = type(opts.choices) == "function" and opts.choices() or opts.choices or {}
        for _, c in ipairs(choices) do
            root:CreateRadio(c.text, function() return get() == c.value end,
                function() set(c.value) end, c.value)
        end
    end)
    holder.Dropdown, holder.Label = dd, label

    function holder:Refresh() dd:GenerateMenu() end
    Tooltip(holder, opts.label, opts.tooltip)
    ns.Skin("Dropdown", dd)
    Track(parent, holder)
    return holder, y - 26 - GAP
end

-- An item slot you drop an item on (or click while holding one).
-- opts: label, size, onItem(itemID, itemLink), tooltip
-- slot:SetItem(itemID or nil) shows an item's icon.
function W.ItemDropSlot(parent, y, opts)
    local size = opts.size or 36
    local slot = CreateFrame("Button", nil, parent)
    slot:SetSize(size, size)
    slot:SetPoint("TOPLEFT", opts.x or 0, y)
    slot:RegisterForClicks("LeftButtonUp")

    local bg = slot:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\PaperDoll\\UI-Backpack-EmptySlot")
    local icon = slot:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    slot:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    slot.Icon, slot.Background = icon, bg

    local label = slot:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("LEFT", slot, "RIGHT", 8, 0)
    label:SetText(opts.label or "Drop an item here")
    ns.Skin("Font", label)
    slot.Label = label

    function slot:SetItem(itemID)
        self.itemID = itemID
        icon:SetTexture(itemID and C_Item.GetItemIconByID(itemID) or nil)
    end

    local function Accept()
        local kind, itemID, link = GetCursorInfo()
        if kind ~= "item" then return end
        ClearCursor()
        if opts.onItem then opts.onItem(itemID, link) end
    end
    slot:SetScript("OnReceiveDrag", Accept)
    slot:SetScript("OnClick", Accept)
    slot:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.itemID then
            GameTooltip:SetItemByID(self.itemID)
        else
            GameTooltip:SetText(opts.label or "Drop an item here", 1, 1, 1)
            if opts.tooltip then GameTooltip:AddLine(opts.tooltip, nil, nil, nil, true) end
        end
        GameTooltip:Show()
    end)
    slot:SetScript("OnLeave", GameTooltip_Hide)
    ns.Skin("SquareIcon", icon, slot)
    return slot, y - size - GAP
end
