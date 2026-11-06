-- Shared option widgets for module pages, drawn in RivQoL's own style
-- (UI/Theme.lua).
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
local T = ns.Theme

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
    -- Plain holder frames get no OnEnter without mouse motion; motion alone
    -- doesn't swallow clicks meant for the controls inside.
    if frame.SetMouseMotionEnabled then frame:SetMouseMotionEnabled(true) end
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

-- Section header: gold Morpheus text over a gold rule that fades out.
function W.SectionHeader(parent, y, text, opts)
    opts = opts or {}
    local x = opts.x or 0
    y = y - 4   -- a little air above each section
    local fs = T.FontString(parent, "header")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    local line = T.Rule(parent, Width(parent, x))
    line:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -5)
    fs.Line = line
    return fs, y - fs:GetStringHeight() - 5 - 1 - GAP - 2
end

-- Wrapped body text.
function W.Text(parent, y, text, opts)
    opts = opts or {}
    local x = opts.x or 0
    local fs = T.FontString(parent, opts.font)
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetWidth(opts.width or Width(parent, x))
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(true)
    fs:SetSpacing(2)
    fs:SetText(text)
    return fs, y - fs:GetStringHeight() - GAP
end

-- Checkbox with a label. opts: label, tooltip, get/set or db/key, onChange(v)
function W.Checkbox(parent, y, opts)
    local get, set = Bind(parent, opts)
    local cb = T.Checkbox(parent, opts.label)
    cb:SetPoint("TOPLEFT", opts.x or 0, y)
    function cb:onClick()
        local v = self:GetChecked() and true or false
        set(v)
        if opts.onChange then opts.onChange(v) end
    end
    function cb:Refresh() self:SetChecked(get() and true or false) end
    Tooltip(cb, opts.label, opts.tooltip)
    cb:Refresh()
    Track(parent, cb)
    return cb, y - 20 - GAP
end

-- Push button. opts: text, width, onClick, tooltip
function W.Button(parent, y, opts)
    local b = T.Button(parent, opts.text, opts.width or 140, opts.height or 24, opts.variant)
    b:SetPoint("TOPLEFT", opts.x or 0, y)
    if opts.onClick then b:SetScript("OnClick", opts.onClick) end
    Tooltip(b, opts.text, opts.tooltip)
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

    local label = T.FontString(holder, "body")
    label:SetPoint("LEFT")
    label:SetWidth(140)
    label:SetJustifyH("LEFT")
    label:SetText(opts.label or "")

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
-- opts: label, get/set or db/key, tooltip. Saved on Enter / focus loss.
function W.MoneyInput(parent, y, opts)
    local get, set = Bind(parent, opts)
    local x = opts.x or 0
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetPoint("TOPLEFT", x, y)
    holder:SetSize(370, 24)

    local label = T.FontString(holder, "body")
    label:SetPoint("LEFT")
    label:SetWidth(140)
    label:SetJustifyH("LEFT")
    label:SetText(opts.label or "")

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
        local box = T.EditBox(holder, p.width, 22)
        box:SetPoint("LEFT", anchor, "RIGHT", i == 1 and 8 or 6, 0)
        box:SetNumeric(true)
        box:SetMaxLetters(p.max and 2 or 7)
        box:SetJustifyH("RIGHT")
        -- Saved on Enter or when focus leaves; Escape restores the saved value.
        box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        box:SetScript("OnEscapePressed", function(self)
            self.cancel = true
            self:ClearFocus()
        end)
        box:HookScript("OnEditFocusLost", function(self)
            if self.cancel then
                self.cancel = nil
            else
                Commit()
            end
            holder:Refresh()
        end)
        local icon = holder:CreateTexture(nil, "ARTWORK")
        icon:SetSize(13, 13)
        icon:SetTexture(p.icon)
        icon:SetPoint("LEFT", box, "RIGHT", 3, 0)
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

-- One-line text input with a label on the left.
-- opts: label, width, maxLetters, get/set or db/key, tooltip.
-- Saved on Enter / focus loss; Escape restores the saved value.
function W.TextInput(parent, y, opts)
    local get, set = Bind(parent, opts)
    local x = opts.x or 0
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetPoint("TOPLEFT", x, y)
    holder:SetSize(160 + (opts.width or 200), 24)

    local label = T.FontString(holder, "body")
    label:SetPoint("LEFT")
    label:SetWidth(140)
    label:SetJustifyH("LEFT")
    label:SetText(opts.label or "")

    local box = T.EditBox(holder, opts.width or 200, 22)
    box:SetPoint("LEFT", label, "RIGHT", 8, 0)
    box:SetMaxLetters(opts.maxLetters or 100)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEscapePressed", function(self)
        self.cancel = true
        self:ClearFocus()
    end)
    box:HookScript("OnEditFocusLost", function(self)
        if self.cancel then
            self.cancel = nil
        else
            set(strtrim(self:GetText() or ""))
        end
        holder:Refresh()
    end)
    holder.EditBox, holder.Label = box, label

    function holder:Refresh()
        if not box:HasFocus() then
            box:SetText(get() or "")
            box:SetCursorPosition(0)
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

    local label = T.FontString(holder, "body")
    label:SetPoint("LEFT")
    label:SetWidth(140)
    label:SetJustifyH("LEFT")
    label:SetText(opts.label or "")

    local dd = CreateFrame("DropdownButton", nil, holder, "WowStyle1DropdownTemplate")
    dd:SetSize(opts.width or 200, 22)
    dd:SetPoint("LEFT", label, "RIGHT", 8, 0)
    T.SkinDropdown(dd)
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
    Track(parent, holder)
    return holder, y - 26 - GAP
end

-- An item slot you drop an item on (or click while holding one).
-- opts: label, size, onItem(itemID, itemLink), tooltip
-- slot:SetItem(itemID or nil) shows an item's icon.
function W.ItemDropSlot(parent, y, opts)
    local size = opts.size or 36
    local slot = T.Slot(parent, size)
    slot:SetPoint("TOPLEFT", opts.x or 0, y)
    slot:RegisterForClicks("LeftButtonUp")
    local icon = slot.Icon

    local label = T.FontString(slot, "body")
    label:SetPoint("LEFT", slot, "RIGHT", 10, 0)
    label:SetText(opts.label or "Drop an item here")
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
    slot:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.itemID then
            GameTooltip:SetItemByID(self.itemID)
        else
            GameTooltip:SetText(opts.label or "Drop an item here", 1, 1, 1)
            if opts.tooltip then GameTooltip:AddLine(opts.tooltip, nil, nil, nil, true) end
        end
        GameTooltip:Show()
    end)
    slot:HookScript("OnLeave", GameTooltip_Hide)
    return slot, y - size - GAP
end
