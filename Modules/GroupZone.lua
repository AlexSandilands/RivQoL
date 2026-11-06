-- Group Browser zones: shows where players are in Forever's Looking For Group
-- browser (Blizzard_GroupFinder_VanillaStyle, load-on-demand), on each listing
-- and in its tooltip, so you don't have to /who them.
--
-- Where the zone comes from:
--   1. The search result itself: C_LFGList.GetSearchResultPlayerInfo /
--      GetSearchResultLeaderInfo carry an `areaName` field. When the server
--      fills it, that is used and nothing else happens.
--   2. Otherwise a /who for that player. C_FriendList.SendWho only works from a
--      hardware event (a click or key press), so lookups can't run in the
--      background: clicking a listing looks up its leader when the zone is
--      missing or older than FRESH, and the magnifier on a hovered row looks it
--      up now. One at a time, at most one every THROTTLE seconds. Our result is
--      kept out of chat and out of the Who lists (their WHO_LIST_UPDATE is
--      unregistered for the duration). A /who you type yourself always wins:
--      ours is dropped and yours shows as usual.
--
-- Hooks are post-hooks only (hooksecurefunc / HookScript). The labels copy the
-- font of the row's own text, so EllesmereUI's skin carries over.
local _, ns = ...

local M = {
    name = "groupzone",
    title = "Group Browser Zones",
    group = "general",
    description = "Shows where players are in the Group Browser: the leader's zone on each listing, the members' zones in its tooltip.",
    defaults = {
        enabled = true,
        showOnRows = true,   -- zone label on each listing (the tooltip always has it)
    },
}

local BLIZZ_ADDON = "Blizzard_GroupFinder_VanillaStyle"
local FRESH = 300      -- seconds a /who result counts as current
local THROTTLE = 5     -- seconds between our /who queries
local TIMEOUT = 5      -- seconds to wait for a /who answer
-- Frames that react to WHO_LIST_UPDATE; silenced while our query is in flight.
local WHO_FRAMES = { "FriendsFrame", "WhoFrame", "LFGWhoListFrame" }

local ZONE_COLOR = { 0.80, 0.80, 0.80 }
local NOTE_COLOR = "|cff808080"

local IsSecret = issecretvalue or function() return false end

-- A usable string, or nil (secret values in restricted content, empty strings).
local function Str(v)
    if type(v) ~= "string" or IsSecret(v) or v == "" then return nil end
    return v
end

local function Short(name)
    if not name then return nil end
    return Ambiguate and Ambiguate(name, "short") or name:match("^[^-]+")
end

local function Key(name)
    local short = Short(name)
    return short and short:lower()
end

-------------------------------------------------------------------------------
-- Zone cache and /who lookups
-------------------------------------------------------------------------------
local cache = {}        -- key -> { zone = string|nil (nil: not found), at = GetTime() }
local pending           -- our query in flight: { key, name, sentAt, silenced, prevToUi }
local lastSent = 0      -- GetTime() of the last /who, ours or the user's
local sendingOurs = false
local silenceKey, silenceUntil = nil, 0   -- chat filter window for our result
local silenceTotals = false               -- also drop "N players total" (off once the user's /who runs)

local RefreshAll        -- defined below

local function IsPending(name)
    return pending ~= nil and pending.key == Key(name)
end

-- text, state, checkedAt. state: "api" (zone sent with the listing), "cache"
-- (a /who result), "notfound" or nil (unknown). When /who names a place other
-- than the listing's zone (usually the subzone), both show: "Goldshire (Elwynn
-- Forest)", with state "cache".
local function ZoneFor(name, apiArea)
    local key = Key(name)
    local c = key and cache[key]
    if apiArea then
        if c and c.zone and c.zone ~= apiArea then
            return c.zone .. " (" .. apiArea .. ")", "cache", c.at
        end
        return apiArea, "api"
    end
    if c then return c.zone, c.zone and "cache" or "notfound", c.at end
    return nil
end
M.ZoneFor = ZoneFor

local function Ago(at)
    local s = GetTime() - at
    if s < 60 then return "just now" end
    if s < 3600 then return string.format("%dm ago", math.floor(s / 60)) end
    return string.format("%dh ago", math.floor(s / 3600))
end

local function CooldownLeft()
    return math.max(0, lastSent + THROTTLE - GetTime())
end

-- Ends our query: hands WHO_LIST_UPDATE back to the frames we silenced and
-- restores the who-to-UI setting. Also when the user's own /who takes over:
-- the setting is read when results arrive, so theirs goes where it normally
-- would (chat for a typed /who).
local function Finish()
    local p = pending
    if not p then return end
    pending = nil
    for _, f in ipairs(p.silenced) do
        if not f:IsEventRegistered("WHO_LIST_UPDATE") then f:RegisterEvent("WHO_LIST_UPDATE") end
    end
    if C_FriendList.SetWhoToUi then
        C_FriendList.SetWhoToUi(p.prevToUi and true or false)
    end
    RefreshAll()
end

-- Looks up `name` with /who. Must run from a click (hardware event).
-- force: look up even when the cached zone is still fresh.
function M.Lookup(name, force)
    if not (M.db and M.db.enabled and C_FriendList and C_FriendList.SendWho) then return end
    local key, short = Key(name), Short(name)
    if not key or pending then return end
    if not force then
        local c = cache[key]
        if c and GetTime() - c.at < FRESH then return end
    end
    if CooldownLeft() > 0 then return end

    local now = GetTime()
    local p = { key = key, name = short, sentAt = now, silenced = {} }
    p.prevToUi = C_FriendList.GetWhoToUi and C_FriendList.GetWhoToUi() or false
    for _, fname in ipairs(WHO_FRAMES) do
        local f = _G[fname]
        if f and f.IsEventRegistered and f:IsEventRegistered("WHO_LIST_UPDATE") then
            f:UnregisterEvent("WHO_LIST_UPDATE")
            p.silenced[#p.silenced + 1] = f
        end
    end
    pending = p
    silenceKey, silenceUntil, silenceTotals = key, now + TIMEOUT + 1, true
    if C_FriendList.SetWhoToUi then C_FriendList.SetWhoToUi(true) end

    sendingOurs = true
    local ok, err = pcall(C_FriendList.SendWho, 'n-"' .. short .. '"')
    sendingOurs = false
    lastSent = now
    if not ok then
        Finish()
        geterrorhandler()(err)
        return
    end
    C_Timer.After(TIMEOUT, function()
        if pending == p then Finish() end   -- no answer: stays unknown
    end)
    RefreshAll()
end

local whoFrame = CreateFrame("Frame")
whoFrame:SetScript("OnEvent", function()
    local p = pending
    if not p then return end
    local zone
    for i = 1, C_FriendList.GetNumWhoResults() or 0 do
        local info = C_FriendList.GetWhoInfo(i)
        if info and Key(Str(info.fullName)) == p.key then
            zone = Str(info.area)
            break
        end
    end
    cache[p.key] = { zone = zone, at = GetTime() }
    silenceUntil = GetTime() + 1
    -- Next frame, so the silenced frames don't get this very event.
    C_Timer.After(0, function()
        if pending == p then Finish() end
    end)
end)

-- The user's own /who (slash command, Who tab, LFG Who tab) goes first: drop
-- ours and let theirs reach the UI and chat as usual.
local function OnAnySendWho()
    if sendingOurs then return end
    lastSent = GetTime()
    -- Our answer may still arrive: keep hiding its line about our player
    -- until the original timeout, but let the user's total line through.
    silenceTotals = false
    if pending then Finish() end
end

-- Safety net in case the server still prints our result to chat.
local whoTotalPattern
local function ChatFilter(_, _, msg)
    if not silenceKey or GetTime() > silenceUntil or type(msg) ~= "string" or IsSecret(msg) then return false end
    -- The exact player, with or without a realm: |Hplayer:Name[-Realm]:...
    local key = silenceKey:gsub("%p", "%%%0")
    if msg:lower():find("|hplayer:" .. key .. "[%-:|]") then return true end
    if not silenceTotals then return false end
    if whoTotalPattern == nil then
        whoTotalPattern = false
        if type(WHO_NUM_RESULTS) == "string" then
            local pat = WHO_NUM_RESULTS:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
            pat = pat:gsub("%%d", "%%d+"):gsub("|4[^;]*;", ".-")
            whoTotalPattern = "^" .. pat .. "$"
        end
    end
    return whoTotalPattern and msg:find(whoTotalPattern) ~= nil or false
end

-------------------------------------------------------------------------------
-- Rows
-------------------------------------------------------------------------------
-- row -> { zone, button, leader, api, hasSelf, targets }
--   targets: the listing's players whose zone isn't sent with it, leader first
local rowExtras = setmetatable({}, { __mode = "k" })
local tipLabels = setmetatable({}, { __mode = "k" })   -- tooltip member frame -> FontString
local tipResultID

local function CopyFont(fs, from)
    local file, size, flags = from:GetFont()
    if file then fs:SetFont(file, size, flags or "") end
end

local function IsFresh(name)
    local c = cache[Key(name) or ""]
    return c and GetTime() - c.at < FRESH
end

-- Who the magnifier looks up next: the first player of the listing not looked
-- up in the last FRESH seconds (leader first), else the leader again. One per
-- click, since each /who needs its own click. /who can name a more specific
-- place than the zone sent with the listing, so everyone is a target.
local function NextTarget(e)
    local targets = e.targets
    if not (targets and targets[1]) then return nil end
    for _, name in ipairs(targets) do
        if not IsFresh(name) then return name end
    end
    return targets[1]
end

local function ShowButtonTip(btn)
    local e = btn.extras
    GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
    GameTooltip:SetText("Look up location")
    local target = e and NextTarget(e)
    if target then
        GameTooltip:AddLine("Sends /who for " .. target .. ".", 1, 1, 1, true)
        if #e.targets > 1 then
            GameTooltip:AddLine("Click again for the next group member.", 0.7, 0.7, 0.7, true)
        end
    end
    local wait = CooldownLeft()
    if pending then
        GameTooltip:AddLine("Waiting for the last lookup.", 1, 0.5, 0.25, true)
    elseif wait > 0 then
        GameTooltip:AddLine(string.format("Wait %d s (the server limits /who).", math.ceil(wait)), 1, 0.5, 0.25, true)
    end
    GameTooltip:Show()
end

local function ButtonWanted(row, e)
    return M.db.enabled and M.db.showOnRows and NextTarget(e) and row:IsMouseOver()
end

local function UpdateButton(row, e)
    e.button:SetShown(ButtonWanted(row, e) or e.button:IsMouseOver() and e.button:IsShown())
end

local function CreateExtras(row)
    local e = {}
    local fs = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmallLeft")
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(true)
    if fs.SetMaxLines then fs:SetMaxLines(2) end
    e.zone = fs   -- placed in Decorate, right of the role/count display

    local btn = CreateFrame("Button", nil, row)
    btn:SetSize(14, 14)
    -- Placed in Decorate, at the row's right edge.
    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    tex:SetVertexColor(0.8, 0.8, 0.8)
    btn:SetHighlightTexture("Interface\\Common\\UI-Searchbox-Icon", "ADD")
    btn.extras = e
    btn:SetScript("OnClick", function(self)
        local target = NextTarget(e)
        if target then M.Lookup(target, true) end
        if self:IsMouseOver() then ShowButtonTip(self) end
    end)
    btn:SetScript("OnEnter", ShowButtonTip)
    btn:SetScript("OnLeave", function(self)
        GameTooltip_Hide()
        if not row:IsMouseOver() then self:Hide() end
    end)
    btn:Hide()
    e.button = btn

    row:HookScript("OnEnter", function(self) UpdateButton(self, e) end)
    row:HookScript("OnLeave", function(self)
        if not e.button:IsMouseOver() then e.button:Hide() end
    end)
    -- Left-clicking a listing (a hardware event) looks up its leader unless
    -- that was done in the last FRESH seconds. Not your own or a delisted one
    -- (Blizzard ignores those clicks).
    row:HookScript("OnClick", function(self, button)
        if button ~= "LeftButton" or self.isDelisted or e.hasSelf then return end
        if M.db.enabled and e.leader then M.Lookup(e.leader, false) end
    end)

    rowExtras[row] = e
    return e
end

-- Screen x of the right-most visible content in the role/count display
-- ("Roles:" and its icons, or the role counts). Its frame is wider than what it
-- shows, so the frame's own edges don't tell where the content ends.
local function ContentRight(region, best, depth)
    local kind = region:GetObjectType()
    if kind == "FontString" then
        local text = region:GetText()
        if region:IsShown() and type(text) == "string" and not IsSecret(text) and text ~= "" then
            local l, r, w = region:GetLeft(), region:GetRight(), region:GetStringWidth()
            if l and r then
                local j = region:GetJustifyH()
                local x = j == "RIGHT" and r or j == "CENTER" and (l + r + w) / 2 or l + w
                best = best and math.max(best, x) or x
            end
        end
    elseif kind == "Texture" then
        if region:IsShown() and (region:GetAlpha() or 0) > 0 and region:GetDrawLayer() ~= "BACKGROUND"
            and (region:GetTexture() or region.GetAtlas and region:GetAtlas()) then
            local r = region:GetRight()
            if r then best = best and math.max(best, r) or r end
        end
    elseif region:IsShown() and depth < 4 then
        for _, r in ipairs({ region:GetRegions() }) do best = ContentRight(r, best, depth + 1) end
        for _, c in ipairs({ region:GetChildren() }) do best = ContentRight(c, best, depth + 1) end
    end
    return best
end

-- Where the label goes: x offset from the row's left edge (just right of the
-- roles), y offset of the display's centre from the row's centre, and the
-- room left before the magnifier. nil while the row isn't laid out yet.
local function LabelSpot(row)
    local dd = row.DataDisplay
    local rowL, rowR = row:GetLeft(), row:GetRight()
    local _, rowY = row:GetCenter()
    local _, ddY = dd:GetCenter()
    if not (rowL and rowR and rowY and ddY) then return nil end
    local right = ContentRight(dd, nil, 0) or dd:GetLeft()
    if not right then return nil end
    local x = right - rowL + 10
    return x, ddY - rowY, (rowR - rowL) - 6 - 14 - 4 - x
end

local Decorate   -- defined below; it retries itself until the row is laid out

local function HideRow(e)
    e.zone:Hide()
    e.button:Hide()
end

function Decorate(row)
    if not (row and row.resultID and row.ActivityName and row.DataDisplay) then return end
    local e = rowExtras[row]
    if not (M.db and M.db.enabled) then
        if e then HideRow(e) end
        return
    end
    e = e or CreateExtras(row)

    local info = C_LFGList.GetSearchResultInfo(row.resultID)
    local leaderInfo = C_LFGList.GetSearchResultLeaderInfo and C_LFGList.GetSearchResultLeaderInfo(row.resultID)
    e.leader = info and Str(info.leaderName) or leaderInfo and Str(leaderInfo.name)
    local api = leaderInfo and Str(leaderInfo.areaName)
    e.api = api ~= nil
    e.hasSelf = info and info.hasSelf == true
    local targets = {}
    if e.leader and not e.hasSelf then targets[1] = e.leader end
    local n = info and info.numMembers
    if not e.hasSelf and type(n) == "number" and not IsSecret(n) and n <= 10 then
        local leaderKey = Key(e.leader)
        for i = 1, n do
            local p = C_LFGList.GetSearchResultPlayerInfo(row.resultID, i)
            local name = p and Str(p.name)
            if name and Key(name) ~= leaderKey then
                targets[#targets + 1] = name
            end
        end
    end
    e.targets = targets

    if not (M.db.showOnRows and e.leader) then
        HideRow(e)
        return
    end

    local zone, state = ZoneFor(e.leader, api)
    local text
    if zone then
        text = zone
    elseif IsPending(e.leader) then
        text = NOTE_COLOR .. "looking up...|r"
    elseif state == "notfound" then
        text = NOTE_COLOR .. "not found|r"
    end

    -- Right of the roles, centred on them; the magnifier at the row's right
    -- edge. Before the row is laid out nothing can be measured: try again
    -- next frame.
    local x, y, room = LabelSpot(row)
    if not x then
        e.zone:Hide()
        if not e.retry then
            e.retry = true
            C_Timer.After(0, function() Decorate(row) end)
        end
        UpdateButton(row, e)
        return
    end
    e.retry = nil
    e.button:ClearAllPoints()
    e.button:SetPoint("RIGHT", row, "RIGHT", -6, y)
    e.zone:ClearAllPoints()
    e.zone:SetPoint("LEFT", row, "LEFT", x, y)
    CopyFont(e.zone, row.ActivityName)
    e.zone:SetTextColor(ZONE_COLOR[1], ZONE_COLOR[2], ZONE_COLOR[3])
    if text and room >= 30 then
        e.zone:SetWidth(room)
        e.zone:SetText(text)
        e.zone:Show()
    else
        e.zone:SetText("")
        e.zone:Hide()
    end
    UpdateButton(row, e)
end

-------------------------------------------------------------------------------
-- Tooltip
-------------------------------------------------------------------------------
local function TipText(name, apiArea)
    local zone, state, at = ZoneFor(name, apiArea)
    if zone then
        if IsPending(name) then return zone .. NOTE_COLOR .. " (looking up...)|r" end
        if state == "cache" then return zone .. NOTE_COLOR .. " (" .. Ago(at) .. ")|r" end
        return zone
    elseif IsPending(name) then
        return NOTE_COLOR .. "looking up...|r"
    elseif state == "notfound" then
        return NOTE_COLOR .. "not found (" .. Ago(at) .. ")|r"
    end
    return NOTE_COLOR .. "zone unknown|r"
end

-- Adds the zone after a member line's level and role icons; returns how far
-- right the line now reaches, relative to the tooltip's left edge.
local function SetMemberZone(tip, frame, name, apiArea)
    local fs = tipLabels[frame]
    if not fs then
        fs = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmallLeft")
        fs:SetWordWrap(false)
        tipLabels[frame] = fs
    end
    if not name then
        fs:Hide()
        return 0
    end
    local anchor = frame.Level
    for _, key in ipairs({ "Role", "Role2", "Role3" }) do
        local r = frame[key]
        if r and r:IsShown() then anchor = r end
    end
    CopyFont(fs, frame.Level)
    fs:SetTextColor(ZONE_COLOR[1], ZONE_COLOR[2], ZONE_COLOR[3])
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", anchor, "RIGHT", 6, 0)
    fs:SetText(TipText(name, apiArea))
    fs:Show()
    local right, left = fs:GetRight(), tip:GetLeft()
    if right and left then return right - left end
    return 0
end

local function OnTooltip(tip, resultID)
    tipResultID = resultID
    if not (M.db and M.db.enabled) then
        for _, fs in pairs(tipLabels) do fs:Hide() end
        return
    end
    local info = C_LFGList.GetSearchResultInfo(resultID)
    if not info then return end

    local areas = {}
    local n = info.numMembers
    if type(n) == "number" and not IsSecret(n) then
        for i = 1, n do
            local p = C_LFGList.GetSearchResultPlayerInfo(resultID, i)
            local name = p and Str(p.name)
            if name then areas[name] = Str(p.areaName) or false end
        end
    end

    local widest = 0
    if tip.Leader then
        local li = C_LFGList.GetSearchResultLeaderInfo and C_LFGList.GetSearchResultLeaderInfo(resultID)
        local name = li and Str(li.name) or Str(info.leaderName)
        local area = li and Str(li.areaName) or name and areas[name] or nil
        widest = math.max(widest, SetMemberZone(tip, tip.Leader, name, area or nil))
    end
    if tip.memberPool then
        for frame in tip.memberPool:EnumerateActive() do
            local name = Str(frame.Name and frame.Name:GetText())
            widest = math.max(widest, SetMemberZone(tip, frame, name, name and areas[name] or nil))
        end
    end

    -- Widen to fit; the comment then wraps differently, so fix the height too.
    local need = widest + 11
    if need > tip:GetWidth() then
        local cmt = tip.Comment
        local before = cmt and cmt:IsShown() and cmt:GetHeight() or 0
        tip:SetWidth(need)
        local after = cmt and cmt:IsShown() and cmt:GetHeight() or 0
        if after ~= before then tip:SetHeight(tip:GetHeight() + after - before) end
    end
end

-------------------------------------------------------------------------------
-- Wiring
-------------------------------------------------------------------------------
function RefreshAll()
    local sb = _G.LFGBrowseFrameScrollBox
    if sb and sb.ForEachFrame then sb:ForEachFrame(Decorate) end
    local tip = _G.LFGBrowseSearchEntryTooltip
    if tip and tip:IsShown() and tipResultID and _G.LFGBrowseSearchEntryTooltip_UpdateAndShow
        and C_LFGList.GetSearchResultInfo(tipResultID) then
        _G.LFGBrowseSearchEntryTooltip_UpdateAndShow(tip, tipResultID)
    end
end

local hooked = false
local function InstallHooks()
    if hooked or not _G.LFGBrowseSearchEntry_Update then return end
    hooked = true
    hooksecurefunc("LFGBrowseSearchEntry_Update", Decorate)
    if _G.LFGBrowseSearchEntryTooltip_UpdateAndShow then
        hooksecurefunc("LFGBrowseSearchEntryTooltip_UpdateAndShow", OnTooltip)
    end
    RefreshAll()
end

local whoHooked = false
local function HookWho()
    if whoHooked or not (C_FriendList and C_FriendList.SendWho) then return end
    whoHooked = true
    hooksecurefunc(C_FriendList, "SendWho", OnAnySendWho)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", ChatFilter)
end

local loader = CreateFrame("Frame")
loader:SetScript("OnEvent", function(self, _, addon)
    if addon == BLIZZ_ADDON then
        self:UnregisterEvent("ADDON_LOADED")
        if M.db.enabled then InstallHooks() end
    end
end)

function M:OnEnable()
    HookWho()
    whoFrame:RegisterEvent("WHO_LIST_UPDATE")
    if _G.LFGBrowseSearchEntry_Update then
        InstallHooks()
        RefreshAll()
    elseif not hooked then
        loader:RegisterEvent("ADDON_LOADED")
    end
end

function M:OnDisable()
    -- Hooks stay installed but do nothing while off.
    Finish()
    whoFrame:UnregisterEvent("WHO_LIST_UPDATE")
    for _, e in pairs(rowExtras) do HideRow(e) end
    RefreshAll()   -- redraws an open tooltip without the zones
    for _, fs in pairs(tipLabels) do fs:Hide() end
end

function M:BuildOptions(parent, db, y)
    local W = ns.Widgets
    local _
    _, y = W.Checkbox(parent, y, {
        label = "Show zone on listings",
        tooltip = "Show the leader's zone on each listing. The tooltip shows the members' zones while the module is on.",
        db = db, key = "showOnRows",
    })
    _, y = W.Text(parent, y, "Clicking a listing looks its leader up with /who, which can name a more specific place: \"Goldshire (Elwynn Forest)\". The magnifier on a hovered listing looks up the leader, then each member, one per click (one /who every 5 seconds).", { font = "small" })
    return y
end

ns.RegisterCallback(function(name, key)
    if name == M.name and key == "showOnRows" and M.db.enabled then RefreshAll() end
end)

ns.RegisterModule(M)
