-- RivQoL's own look: warm near-black panels, thin bronze borders that turn
-- gold on hover or focus, Morpheus for titles and headers, Friz Quadrata
-- for body text. Every control in the options window comes from here.
local _, ns = ...

local T = {}
ns.Theme = T

local WHITE = "Interface\\Buttons\\WHITE8X8"

-- Colours as { r, g, b, a }.
local C = {
    window   = { 0.055, 0.050, 0.045, 0.97 },
    panel    = { 0.085, 0.078, 0.068, 0.92 },
    control  = { 0.030, 0.028, 0.025, 0.95 },
    raised   = { 0.150, 0.130, 0.100, 1 },   -- button top
    raisedLo = { 0.085, 0.074, 0.058, 1 },   -- button bottom
    border   = { 0.36, 0.30, 0.20, 1 },      -- bronze
    borderHi = { 0.80, 0.65, 0.36, 1 },      -- gold
    gold     = { 1.00, 0.82, 0.42, 1 },
    text     = { 0.93, 0.90, 0.83, 1 },      -- parchment
    textDim  = { 0.62, 0.58, 0.50, 1 },
    danger   = { 0.85, 0.32, 0.26, 1 },
}
T.colors = C

local function Unpack(c, alpha) return c[1], c[2], c[3], alpha or c[4] end
T.Unpack = Unpack

---------------------------------------------------------------------------
-- Fonts
---------------------------------------------------------------------------

local MORPHEUS = "Fonts\\MORPHEUS.TTF"
local FRIZ = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

local function MakeFont(name, file, size, color, flags)
    local font = _G[name] or CreateFont(name)
    font:SetFont(file, size, flags or "")
    font:SetTextColor(Unpack(color))
    font:SetShadowColor(0, 0, 0, 0.85)
    font:SetShadowOffset(1, -1)
    return font
end

T.fonts = {
    title  = MakeFont("RivQoLFontTitle", MORPHEUS, 20, C.gold),
    header = MakeFont("RivQoLFontHeader", MORPHEUS, 17, C.gold),
    body   = MakeFont("RivQoLFontBody", FRIZ, 12, C.text),
    small  = MakeFont("RivQoLFontSmall", FRIZ, 11, C.textDim),
    dim    = MakeFont("RivQoLFontDim", FRIZ, 12, C.textDim),
    button = MakeFont("RivQoLFontButton", FRIZ, 12, C.text),
    accent = MakeFont("RivQoLFontAccent", FRIZ, 12, C.gold),
}

-- Modules may still name stock font objects; map them onto ours.
local FONT_ALIASES = {
    GameFontHighlight = "body", GameFontHighlightSmall = "small", GameFontNormal = "accent",
    GameFontNormalLarge = "header", GameFontDisable = "dim", GameFontDisableSmall = "small",
}

function T.Font(name)
    if not name then return T.fonts.body end
    return T.fonts[name] or T.fonts[FONT_ALIASES[name] or ""] or _G[name] or T.fonts.body
end

function T.FontString(parent, font, layer)
    local fs = parent:CreateFontString(nil, layer or "ARTWORK")
    fs:SetFontObject(T.Font(font))
    return fs
end

---------------------------------------------------------------------------
-- Building blocks
---------------------------------------------------------------------------

-- A 1px border and a flat fill on any frame.
function T.Backdrop(frame, bg, border)
    if not frame.SetBackdrop then
        Mixin(frame, BackdropTemplateMixin)
        frame:HookScript("OnSizeChanged", frame.OnBackdropSizeChanged)
    end
    frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    frame:SetBackdropColor(Unpack(bg or C.panel))
    frame:SetBackdropBorderColor(Unpack(border or C.border))
end

function T.SetBorder(frame, color)
    if frame.SetBackdropBorderColor then frame:SetBackdropBorderColor(Unpack(color)) end
end

-- Texture gradient that works on both the old and new texture APIs.
function T.Gradient(tex, orientation, from, to)
    tex:SetTexture(WHITE)
    if tex.SetGradient and CreateColor then
        local ok = pcall(tex.SetGradient, tex, orientation, CreateColor(Unpack(from)), CreateColor(Unpack(to)))
        if ok then return end
    end
    if tex.SetGradientAlpha then
        tex:SetGradientAlpha(orientation, from[1], from[2], from[3], from[4], to[1], to[2], to[3], to[4])
    else
        tex:SetColorTexture(Unpack(from))
    end
end

-- A thin gold rule that fades out to the right (or both ways when centred).
function T.Rule(parent, width, centred)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(width, 1)
    local gold, clear = { C.gold[1], C.gold[2], C.gold[3], 0.55 }, { C.gold[1], C.gold[2], C.gold[3], 0 }
    if centred then
        local left = holder:CreateTexture(nil, "ARTWORK")
        left:SetPoint("TOPLEFT")
        left:SetPoint("BOTTOMRIGHT", holder, "BOTTOM")
        T.Gradient(left, "HORIZONTAL", clear, gold)
        local right = holder:CreateTexture(nil, "ARTWORK")
        right:SetPoint("TOPLEFT", holder, "TOP")
        right:SetPoint("BOTTOMRIGHT")
        T.Gradient(right, "HORIZONTAL", gold, clear)
    else
        local tex = holder:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        T.Gradient(tex, "HORIZONTAL", gold, clear)
    end
    return holder
end

-- Gold border while hovered (and while `frame.rqActive` is true).
local function HoverBorder(frame, target, normal, hover)
    target = target or frame
    normal, hover = normal or C.border, hover or C.borderHi
    frame:HookScript("OnEnter", function() T.SetBorder(target, hover) end)
    frame:HookScript("OnLeave", function()
        if not frame.rqActive then T.SetBorder(target, normal) end
    end)
end
T.HoverBorder = HoverBorder

---------------------------------------------------------------------------
-- Controls
---------------------------------------------------------------------------

-- Push button. variant "danger" turns red on hover (Delete, Remove).
function T.Button(parent, text, width, height, variant)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(width or 120, height or 22)
    T.Backdrop(b, { 0, 0, 0, 0 }, C.border)
    local fill = b:CreateTexture(nil, "BACKGROUND", nil, 1)
    fill:SetPoint("TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", -1, 1)
    T.Gradient(fill, "VERTICAL", C.raisedLo, C.raised)
    local shine = b:CreateTexture(nil, "HIGHLIGHT")
    shine:SetPoint("TOPLEFT", 1, -1)
    shine:SetPoint("BOTTOMRIGHT", -1, 1)
    shine:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.07)

    local label = T.FontString(b, "button")
    label:SetPoint("CENTER")
    label:SetText(text or "")
    b:SetFontString(label)
    b.Label = label

    local hover = variant == "danger" and C.danger or C.borderHi
    b:HookScript("OnEnter", function(self)
        T.SetBorder(self, hover)
        label:SetTextColor(Unpack(variant == "danger" and C.danger or C.gold))
    end)
    b:HookScript("OnLeave", function(self)
        T.SetBorder(self, C.border)
        label:SetTextColor(Unpack(C.text))
    end)
    b:SetScript("OnMouseDown", function() label:SetPoint("CENTER", 1, -1) end)
    b:SetScript("OnMouseUp", function() label:SetPoint("CENTER") end)
    return b
end

-- Checkbox: a small inset box that fills with gold when on. The label is
-- part of the button, so clicking the text toggles it too.
-- cb:SetChecked(v), cb:GetChecked(); onClick(cb) runs after the toggle.
function T.Checkbox(parent, text)
    local cb = CreateFrame("Button", nil, parent)
    cb:SetHeight(20)
    local box = CreateFrame("Frame", nil, cb, "BackdropTemplate")
    box:SetSize(16, 16)
    box:SetPoint("LEFT")
    T.Backdrop(box, C.control, C.border)
    local mark = box:CreateTexture(nil, "OVERLAY")
    mark:SetPoint("TOPLEFT", 4, -4)
    mark:SetPoint("BOTTOMRIGHT", -4, 4)
    T.Gradient(mark, "VERTICAL", { 0.80, 0.58, 0.22, 1 }, C.gold)
    mark:Hide()

    local label = T.FontString(cb, "body")
    label:SetPoint("LEFT", box, "RIGHT", 8, 0)
    label:SetJustifyH("LEFT")
    cb.Label, cb.Box, cb.Mark = label, box, mark

    function cb:SetLabel(s)
        label:SetText(s or "")
        self:SetWidth(16 + 8 + math.max(label:GetStringWidth(), 1) + 4)
    end
    function cb:SetChecked(v)
        self.checked = v and true or false
        mark:SetShown(self.checked)
    end
    function cb:GetChecked() return self.checked end

    cb:SetScript("OnClick", function(self)
        self:SetChecked(not self.checked)
        if self.onClick then self:onClick() end
    end)
    HoverBorder(cb, box)
    cb:SetLabel(text)
    return cb
end

-- Single-line edit box with an inset look; gold border while focused.
-- Use HookScript (not SetScript) for focus handlers so the look keeps working.
function T.EditBox(parent, width, height)
    local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    box:SetSize(width or 200, height or 22)
    T.Backdrop(box, C.control, C.border)
    box:SetFontObject(T.fonts.body)
    box:SetTextInsets(7, 7, 0, 0)
    box:SetAutoFocus(false)
    box:SetHighlightColor(C.gold[1], C.gold[2], C.gold[3], 0.35)
    box:HookScript("OnEditFocusGained", function(self) self.rqActive = true; T.SetBorder(self, C.borderHi) end)
    box:HookScript("OnEditFocusLost", function(self) self.rqActive = nil; T.SetBorder(self, C.border) end)
    box:HookScript("OnEscapePressed", function(self) self:ClearFocus() end)
    HoverBorder(box)
    return box
end

-- Restyle a WowStyle1DropdownTemplate button: hide its art, keep its text
-- and arrow, and put our inset box behind it.
function T.SkinDropdown(dd)
    for _, region in ipairs({ dd:GetRegions() }) do
        if region:IsObjectType("Texture") and region ~= dd.Arrow then region:SetAlpha(0) end
    end
    local bg = CreateFrame("Frame", nil, dd, "BackdropTemplate")
    bg:SetAllPoints()
    bg:SetFrameLevel(math.max(0, dd:GetFrameLevel() - 1))
    T.Backdrop(bg, C.control, C.border)
    if dd.Text then
        dd.Text:SetFontObject(T.fonts.body)
        dd.Text:SetTextColor(Unpack(C.text))
    end
    if dd.Arrow then dd.Arrow:SetVertexColor(Unpack(C.gold)) end
    HoverBorder(dd, bg)
    dd.rqBackground = bg
end

-- Square item slot with a bronze frame.
function T.Slot(parent, size)
    local slot = CreateFrame("Button", nil, parent, "BackdropTemplate")
    slot:SetSize(size, size)
    T.Backdrop(slot, C.control, C.border)
    local empty = slot:CreateTexture(nil, "BACKGROUND", nil, 1)
    empty:SetPoint("TOPLEFT", 2, -2)
    empty:SetPoint("BOTTOMRIGHT", -2, 2)
    empty:SetTexture("Interface\\PaperDoll\\UI-Backpack-EmptySlot")
    empty:SetAlpha(0.35)
    local icon = slot:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", -2, 2)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local shine = slot:CreateTexture(nil, "HIGHLIGHT")
    shine:SetAllPoints(icon)
    shine:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.15)
    HoverBorder(slot)
    slot.Icon, slot.Empty = icon, empty
    return slot
end

-- Close button: a gold-on-hover x in a small framed square.
function T.CloseButton(parent)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(20, 20)
    T.Backdrop(b, C.control, C.border)
    local x = T.FontString(b, "body")
    x:SetPoint("CENTER", 0, 1)
    x:SetText("x")
    x:SetTextColor(Unpack(C.textDim))
    b:HookScript("OnEnter", function(self) T.SetBorder(self, C.borderHi); x:SetTextColor(Unpack(C.gold)) end)
    b:HookScript("OnLeave", function(self) T.SetBorder(self, C.border); x:SetTextColor(Unpack(C.textDim)) end)
    return b
end
