-- Minimal WoW API mock of the Forever client: enough to load SmoothAnimatedBars, drive it with events
-- and read back every region's layout so Python can draw it. As strict as the client where it
-- matters: when the client rejects something the mock accepted, make the mock reject it too.

__regions, __frames, __timers, __now, __chat = {}, {}, {}, 0, {}
__player = {}

local function anchorPos(name, w, h)
    local x = name:find("LEFT") and 0 or (name:find("RIGHT") and w or w / 2)
    local y = name:find("TOP") and 0 or (name:find("BOTTOM") and h or h / 2)
    return x, y
end

local Region = {}
Region.__index = Region

local function NewRegion(kind, parent, layer, sub)
    local r = setmetatable({
        kind = kind, parent = parent, layer = layer or "ARTWORK", sub = sub or 0,
        points = {}, w = 0, h = 0, shown = true, alpha = 1, vc = { 1, 1, 1, 1 },
        tc = { 0, 1, 0, 1 }, blend = "BLEND", order = #__regions + 1, scripts = {}, events = {},
    }, Region)
    __regions[#__regions + 1] = r
    return r
end

function Region:SetPoint(point, a, b, c, d)
    local rel, relPoint, x, y
    if a == nil then
        rel, relPoint, x, y = self.parent, point, 0, 0
    elseif type(a) == "number" then
        rel, relPoint, x, y = self.parent, point, a, b or 0
    elseif type(b) == "string" then
        rel, relPoint, x, y = a, b, c or 0, d or 0
    else
        rel, relPoint, x, y = a, point, b or 0, c or 0
    end
    self.points[point] = { rel = rel, relPoint = relPoint, x = x, y = y }
end
function Region:ClearAllPoints() self.points = {} end
-- Like the client: over the region given, else over the parent.
function Region:SetAllPoints(rel)
    self.points = {}
    if rel then
        self:SetPoint("TOPLEFT", rel, "TOPLEFT")
        self:SetPoint("BOTTOMRIGHT", rel, "BOTTOMRIGHT")
    else
        self:SetPoint("TOPLEFT")
        self:SetPoint("BOTTOMRIGHT")
    end
end
function Region:GetPoint()
    for p, v in pairs(self.points) do return p, v.rel, v.relPoint, v.x, v.y end
end
function Region:SetWidth(w) self.w = w end
function Region:SetHeight(h) self.h = h end
function Region:SetSize(w, h)
    local changed = w ~= self.w or h ~= self.h
    self.w, self.h = w, h
    if changed and self.scripts.OnSizeChanged then self.scripts.OnSizeChanged(self, w, h) end
end
function Region:GetSize() return self.w, self.h end
function Region:GetWidth() return self.w end
function Region:GetHeight() return self.h end
function Region:GetLeft() return 660 end
function Region:GetTop() return 1040 end
function Region:SetResizable() end
function Region:SetResizeBounds(...) self.bounds = { ... } end
function Region:StartSizing(point) self.sizing = point end
function Region:SetFrameLevel(l) self.level = l end
function Region:GetFrameLevel() return self.level or 1 end
-- Showing a hidden frame runs its OnShow and hiding a shown one its OnHide, as in the client.
-- SetShown does not go through Show or Hide.
local function setShown(self, v)
    local was = self.shown
    self.shown = not not v
    if self.shown and not was and self.scripts.OnShow then self.scripts.OnShow(self) end
    if was and not self.shown and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function Region:Show() setShown(self, true) end
function Region:Hide() setShown(self, false) end
function Region:IsShown() return self.shown end
function Region:SetShown(v) setShown(self, v) end
function Region:SetScrollChild(child) self.scrollChild = child end
function Region:EnableMouseWheel(v) self.mouseWheel = v end
function Region:GetVerticalScroll() return self.vscroll or 0 end
function Region:SetVerticalScroll(v) self.vscroll = v end
-- How far a scroll frame scrolls: its scroll child's height past its own.
function Region:GetVerticalScrollRange()
    local child = self.scrollChild
    return child and math.max(0, (child.h or 0) - (self.h or 0)) or 0
end
-- Alpha from a boolean, which may be a secret (SimpleRegionAPI: AllowedWhenTainted); the mock keeps what it stands for.
function Region:SetAlphaFromBoolean(v, ifTrue, ifFalse)
    assert(type(v) == "boolean" or issecretvalue(v), "Usage: SetAlphaFromBoolean(value [, alphaIfTrue, alphaIfFalse])")
    local on = __reveal(v)
    self.alpha = __secret(on and (ifTrue or 1) or (ifFalse or 0))
end
-- A number, or a secret (Forever's SetAlpha takes one, from a curve, say).
function Region:SetAlpha(a)
    assert(type(a) == "number" or issecretvalue(a), "Usage: SetAlpha(alpha)")
    self.alpha = a
end
function Region:SetScale(s) self.scale = s end
local STRATA = { BACKGROUND = true, LOW = true, MEDIUM = true, HIGH = true, DIALOG = true,
                 FULLSCREEN = true, FULLSCREEN_DIALOG = true, TOOLTIP = true }
function Region:SetFrameStrata(s)
    assert(STRATA[s], "bad frame strata " .. tostring(s))
    self.strata = s
end
function Region:GetFrameStrata() return self.strata or (self.parent and self.parent:GetFrameStrata()) or "MEDIUM" end
function Region:SetParent(p)
    assert(p == nil or (type(p) == "table" and p.kind == "Frame"), "SetParent needs a frame")
    self.parent = p
end
function Region:GetParent() return self.parent end
function Region:GetName() return self.name end
function Region:GetChildren()
    local out = {}
    for _, f in ipairs(__frames) do
        if f.parent == self then out[#out + 1] = f end
    end
    return unpack(out)
end
function Region:IsVisible()
    return self.shown and (not self.parent or self.parent:IsVisible())
end
function Region:SetClampedToScreen() end
function Region:SetMovable() end
function Region:RegisterForDrag() end
function Region:EnableMouse(v) self.mouse = v end
function Region:StartMoving() self.moving = true end
function Region:StopMovingOrSizing() self.moving, self.sizing = nil, nil end
function Region:SetScript(name, fn) self.scripts[name] = fn end
-- Forever blocks the combat log for addons, with a popup naming the addon.
local FORBIDDEN_EVENTS = { COMBAT_LOG_EVENT_UNFILTERED = true }
function Region:RegisterEvent(e)
    assert(not FORBIDDEN_EVENTS[e], e .. " is blocked for addons on Forever")
    self.events[e] = true
end
-- A unit event registered for a unit only reaches the frame for that unit.
function Region:RegisterUnitEvent(e, unit)
    assert(not FORBIDDEN_EVENTS[e], e .. " is blocked for addons on Forever")
    assert(type(unit) == "string", "RegisterUnitEvent needs a unit")
    self.events[e] = unit
end
function Region:UnregisterEvent(e) self.events[e] = nil end
function Region:UnregisterAllEvents() self.events = {} end
function Region:IsEventRegistered(e) return self.events[e] end
function Region:SetTexture(file, wh, wv) self.file, self.wrap, self.wrapV, self.color = file, wh, wv or wh, nil end
function Region:SetColorTexture(r, g, b, a) self.file, self.color = "SOLID", { r, g, b, a or 1 } end
function Region:SetVertexColor(r, g, b, a) self.vc, self.grad = { r, g, b, a or 1 }, nil end
function Region:SetGradient(_, c1, c2)
    self.grad = { { c1:GetRGBA() }, { c2:GetRGBA() } }
end
function Region:SetBlendMode(m) self.blend = m end
function Region:SetHorizTile(v) self.horizTile = v end
function Region:SetVertTile(v) self.vertTile = v end
function Region:SetTexCoord(l, r, t, b) self.tc = { l, r, t, b } end
function Region:SetRotation(rad) self.rotation = rad end
function Region:SetDrawLayer(layer, sub) self.layer, self.sub = layer, sub or 0 end
function Region:SetSnapToPixelGrid() end
function Region:SetTexelSnappingBias() end
function Region:SetFont(path, size, flags)
    self.fontPath, self.fontSize, self.fontFlags = path, size, flags
    return true
end
function Region:GetFont()
    if self.fontObject and not self.fontPath then return self.fontObject:GetFont() end
    return self.fontPath or "Fonts\\FRIZQT__.TTF", self.fontSize or 12, self.fontFlags or ""
end
-- A font object; GetFont then answers with its font, as in the client, not any SetTextHeight.
function Region:SetFontObject(object)
    assert(type(object) == "table" and object.GetFont, "SetFontObject needs a font object")
    self.fontObject, self.fontPath, self.fontFlags = object, nil, nil
    self.fontSize = select(2, object:GetFont())
end
function Region:GetFontObject() return self.fontObject end
function Region:SetTextHeight(h) self.textHeight = h end
-- The height of a line as drawn (SetTextHeight's, else the font's), and the font's size set to a number of pixels.
function Region:GetLineHeight() return self.fontHeight or self.textHeight or self.fontSize or 12 end
function Region:SetFontHeight(h)
    assert(type(h) == "number" and h > 0, "SetFontHeight needs a height")
    self.fontHeight = h
end
function Region:SetShadowColor(r, g, b, a) self.shadowColor = { r, g, b, a or 1 } end
function Region:GetShadowColor() return unpack(self.shadowColor or { 0, 0, 0, 1 }) end
function Region:SetShadowOffset(x, y) self.shadowOffset = { x, y } end
function Region:GetShadowOffset() return unpack(self.shadowOffset or { 0, 0 }) end
function Region:SetTextColor(r, g, b, a) self.textColor = { r, g, b, a or 1 } end
function Region:GetTextColor() return unpack(self.textColor or { 1, 1, 1, 1 }) end
function Region:SetJustifyH(j) self.justifyH = j end
function Region:GetJustifyH() return self.justifyH or "CENTER" end
function Region:SetJustifyV(j) self.justifyV = j end
function Region:GetJustifyV() return self.justifyV or "MIDDLE" end
function Region:SetWordWrap(v) self.wordWrap = v end
function Region:SetMaxLines(n) self.maxLines = n end
-- Forever's FontString answers with CanWordWrap; it has no GetWordWrap (SimpleFontStringAPIDocumentation).
function Region:CanWordWrap() return self.wordWrap ~= false end
function Region:SetToplevel() end
function Region:SetChecked(v) self.checked = not not v end
function Region:GetChecked() return self.checked end
function Region:SetText(t) self.text = t end
function Region:GetText() return self.text end
function Region:SetFormattedText(fmt, ...) self.text = string.format(fmt, ...) end
function Region:GetStringWidth()
    local plain = (self.text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return #plain * (self.fontSize or 12) * 0.55
end
-- Wrapped over its width, if it has one, a line per width's worth of text.
function Region:GetStringHeight()
    local lines = 1
    if self.w and self.w > 0 then lines = math.max(1, math.ceil(self:GetStringWidth() / self.w)) end
    return lines * (self.fontSize or 12)
end
function Region:CreateTexture(_, layer, _, sub) return NewRegion("Texture", self, layer, sub) end
function Region:CreateMaskTexture(_, layer, _, sub) return NewRegion("MaskTexture", self, layer, sub) end
function Region:GetObjectType() return self.kind end
function Region:GetRegions()
    local out = {}
    for _, r in ipairs(__regions) do
        if r.parent == self and r.kind ~= "Frame" then out[#out + 1] = r end
    end
    return unpack(out)
end
-- Masks: as in the client, only textures take them, only mask textures can be one, and a texture
-- cannot take the same mask twice.
function Region:AddMaskTexture(mask)
    assert(self.kind == "Texture", "AddMaskTexture on a " .. self.kind)
    assert(mask and mask.kind == "MaskTexture", "AddMaskTexture needs a MaskTexture")
    self.masks = self.masks or {}
    for _, m in ipairs(self.masks) do assert(m ~= mask, "mask already added") end
    self.masks[#self.masks + 1] = mask
end
function Region:RemoveMaskTexture(mask)
    for i, m in ipairs(self.masks or {}) do
        if m == mask then table.remove(self.masks, i) return end
    end
end
-- Font objects the game defines; the client errors on any other name.
local FONT_OBJECTS = {
    GameFontNormal = true, GameFontNormalSmall = true, GameFontNormalLarge = true, GameFontNormalHuge = true,
    GameFontHighlight = true, GameFontHighlightSmall = true, GameFontHighlightLarge = true,
    GameFontHighlightHuge = true, GameFontDisableSmall = true,
    TextStatusBarText = true, WhiteLargeNumberFont = true,
}
function Region:CreateFontString(_, layer, template)
    assert(template == nil or FONT_OBJECTS[template], "unknown font object " .. tostring(template))
    return NewRegion("FontString", self, layer, 0)
end

-- Rect relative to the region's parent, top-left origin, y down.
function Region:Rect()
    local pw, ph = 600, 30
    if self.parent and self.parent.w then pw, ph = self.parent.w, self.parent.h end
    local w, h = self.w, self.h
    if self.kind == "FontString" then
        w, h = self:GetStringWidth(), (self.fontSize or 12)
    end
    local left, right, cx, top, bottom, cy
    for p, a in pairs(self.points) do
        local ax, ay = anchorPos(a.relPoint, pw, ph)
        local x, y = ax + a.x, ay - a.y
        if p:find("LEFT") then left = x elseif p:find("RIGHT") then right = x else cx = x end
        if p:find("TOP") then top = y elseif p:find("BOTTOM") then bottom = y else cy = y end
    end
    if left and right then w = right - left
    elseif right then left = right - w
    elseif not left then left = (cx or 0) - w / 2 end
    if top and bottom then h = bottom - top
    elseif bottom then top = bottom - h
    elseif not top then top = (cy or 0) - h / 2 end
    return left, top, w, h
end

UIParent = NewRegion("Frame", nil, "BACKGROUND", 0)
UIParent.w, UIParent.h = 1920, 1080

-- The settings row templates (Blizzard_SettingControls.xml). Their Init reads the row's initializer
-- back through GetElementData, which the game's list (or a canvas of ours) puts on the frame, and
-- registers callbacks that Release drops, so a row is not initialised twice without a Release.
local ROW_TEMPLATES = {
    SettingsCheckboxControlTemplate = true, SettingsSliderControlTemplate = true,
    SettingsDropdownControlTemplate = true, SettingButtonControlTemplate = true,
    SettingsListSectionHeaderTemplate = true,
}
local TEMPLATES = { MinimalScrollBar = true, UIPanelButtonTemplate = true, UIRadioButtonTemplate = true,
                    ButtonFrameTemplate = true }
local RowTemplate = {}
function RowTemplate.Init(self, initializer)
    assert(self.GetElementData and self:GetElementData() == initializer, "row Init without its GetElementData")
    assert(not self.initialized, "row initialised again without Release")
    self.initialized, self.initializer = true, initializer
    local setting = initializer.data.setting
    self.value = setting and setting:GetValue()
end
function RowTemplate.Release(self) self.initialized = false end

local function insideOpenSettings(f)
    while f do
        if f == __settingsPanel then return __settingsPanel.shown end
        f = f.parent
    end
end

-- A model frame (SimpleModelAPI): the model by file ID or path, its facing and its alpha, as Forever's docs list them.
function __makeModel(f)
    f.kind, f.modelAlpha, f.facing = "PlayerModel", 1, 0
    function f:SetModel(asset)
        assert(type(asset) == "number" or type(asset) == "string", "SetModel: a file ID or path")
        self.model = asset
    end
    function f:SetFacing(radians) assert(type(radians) == "number", "SetFacing: radians"); self.facing = radians end
    function f:GetFacing() return self.facing end
    function f:SetModelAlpha(a)
        assert(type(a) == "number" and a >= 0 and a <= 1, "SetModelAlpha: 0 to 1")
        self.modelAlpha = a
    end
    function f:GetModelAlpha() return self.modelAlpha end
end

function CreateFrame(frameType, name, parent, template)
    assert(template == nil or ROW_TEMPLATES[template] or TEMPLATES[template], "unknown template " .. tostring(template))
    local f = NewRegion("Frame", parent, "BACKGROUND", 0)
    __frames[#__frames + 1] = f
    if name then _G[name], f.name = f, name end
    if frameType == "StatusBar" then __makeStatusBar(f) end
    if frameType == "PlayerModel" then __makeModel(f) end
    if ROW_TEMPLATES[template] then
        f.rowTemplate, f.Init, f.Release = template, RowTemplate.Init, RowTemplate.Release
    end
    -- The game's window: background, inset, a title and a close button that hides it.
    if template == "ButtonFrameTemplate" then
        f.Bg = NewRegion("Texture", f, "BACKGROUND", 0)
        f.Bg:SetPoint("TOPLEFT", 2, -21)
        f.Inset = CreateFrame("Frame", nil, f)
        f.CloseButton = CreateFrame("Button", nil, f)
        f.CloseButton.scripts.OnClick = function() f:Hide() end
        function f:SetTitle(text) self.title = text end
    end
    -- With the gamepad UI on, Forever's SmartNavigation hooks CreateFrame and, for a frame made
    -- inside the open settings panel, rebuilds the panel's navigation state from the caller's code,
    -- which then gets the panel's protected close blocked.
    if insideOpenSettings(parent) then __builtInOpenPanel = true end
    return f
end

local Color = {}
Color.__index = Color
function Color:SetRGBA(r, g, b, a) self.r, self.g, self.b, self.a = r, g, b, a end
function Color:GetRGBA() return self.r, self.g, self.b, self.a end
function CreateColor(r, g, b, a) return setmetatable({ r = r, g = g, b = b, a = a or 1 }, Color) end

__player.class, __player.faction = "PALADIN", "Alliance"
__player.name, __player.realm = "Testchar", "Mockrealm"
-- Like the client, UnitName gives no realm for your own character; GetRealmName has it. On Forever
-- the second value is the character's surname: set __player.surname for that.
function UnitName(unit)
    if unit == "player" then return __player.name, __player.surname end
    if __identitySecret[unit] then return __secret() end
    if unit == "target" and __target then return __target.name end
end
-- Units whose identity is secret (in an instance or battleground): __identitySecret[unit] = true. Their names are
-- secret, and so is the width of a menu title showing one (see __openUnitMenu).
__identitySecret = {}
C_Secrets = {
    ShouldUnitIdentityBeSecret = function(unit)
        assert(type(unit) == "string", "ShouldUnitIdentityBeSecret(unit)")
        return __identitySecret[unit] == true
    end,
}
function GetRealmName() return __player.realm end
-- Other units than the player: the target is __target, the rest __units[unit] (focus, targettarget, pet...). Each
-- has its class (__secret() for one kept secret), reaction and isOtherPlayer.
__units = {}
local function other(unit)
    if unit == "target" then return __target end
    return __units[unit]
end
function UnitClass(unit)
    if unit == "player" then return "Paladin", __player.class end
    local u = other(unit)
    return u and "Other", u and u.class
end
function UnitIsPlayer(unit)
    if unit == "player" then return true end
    local u = other(unit)
    return u ~= nil and u.isOtherPlayer or false
end
function UnitReaction(unit) local u = other(unit); return u and u.reaction or nil end
function UnitFactionGroup() return __player.faction end
RAID_CLASS_COLORS = {
    PALADIN = { r = 0.96, g = 0.55, b = 0.73 }, MAGE = { r = 0.25, g = 0.78, b = 0.92 },
    DRUID = { r = 1.00, g = 0.49, b = 0.04 }, PRIEST = { r = 1.00, g = 1.00, b = 1.00 },
    WARLOCK = { r = 0.53, g = 0.53, b = 0.93 },
}

-- Secret values (Forever runs the Midnight API): health and power are secret to addons, in and out of
-- combat. __secret() makes one. As in the client, arithmetic, ordering and math functions on them
-- fail. Lua 5.1 cannot make == or a truth test fail on a table, so those slip through here.
local SecretValue = {}
-- A secret can carry the value it stands for, which only the mock reads back (__reveal), for drawing what the client
-- would draw from it (a frame's alpha from a curve).
local secretValues = setmetatable({}, { __mode = "k" })
function __secret(v)
    local s = setmetatable({}, SecretValue)
    secretValues[s] = v
    return s
end
function issecretvalue(v) return getmetatable(v) == SecretValue end
function __reveal(v)
    if issecretvalue(v) then return secretValues[v] end
    return v
end

function GetTime() return __now end
floor = math.floor

C_Timer = {}
-- Strict like the real client: the callback must be a Lua function. Game API functions are C
-- functions there and get rejected, so the mock rejects them too.
local C_FUNCTIONS = {}
function C_Timer.After(d, fn)
    assert(type(d) == "number", "Usage: C_Timer.After(seconds, callback)")
    assert(type(fn) == "function" and not C_FUNCTIONS[fn], "bad argument #2 (Usage: C_Timer.After(seconds, callback))")
    __timers[#__timers + 1] = { at = __now + d, fn = fn }
end
function __markCFunctions()
    for _, name in ipairs({ "UnitHealth", "UnitHealthMax", "UnitPower", "UnitPowerMax", "Screenshot" }) do
        C_FUNCTIONS[_G[name]] = true
    end
end
function C_Timer.NewTicker(d, fn)
    local t = { cancelled = false }
    function t:Cancel() self.cancelled = true end
    local function tick()
        if t.cancelled then return end
        fn()
        C_Timer.After(d, tick)
    end
    C_Timer.After(d, tick)
    return t
end

UISpecialFrames = {}
function ButtonFrameTemplate_HidePortrait(f) f.portraitHidden = true end
function ButtonFrameTemplate_HideButtonBar(f) f.buttonBarHidden = true end
-- Forever's build.
__interface = 16001
function GetBuildInfo() return "1.0.0", "1", "Nov 1 2026", __interface end
NUM_CHAT_WINDOWS = 1
ChatFrame1 = NewRegion("Frame", nil)
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) __chat[#__chat + 1] = m end }
SlashCmdList = {}
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function strlower(s) return s:lower() end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function strsplit(sep, s, n)
    local out, start = {}, 1
    while true do
        if n and #out == n - 1 then out[#out + 1] = s:sub(start); break end
        local i = s:find(sep, start, true)
        if not i then out[#out + 1] = s:sub(start); break end
        out[#out + 1] = s:sub(start, i - 1)
        start = i + 1
    end
    return unpack(out)
end

function hooksecurefunc(t, method, fn)
    local orig = t[method]
    t[method] = function(...)
        local r = orig(...)
        fn(...)
        return r
    end
end

function Region:GetAlpha() return self.alpha end
function Region:GetDrawLayer() return self.layer, self.sub end
function Region:GetDebugName() return self.debugName or "?" end

function Region:SetUsingParentLevel(v) self.useParentLevel = v end
-- Atlases by name; __missingAtlases[name] makes one fail, as an atlas the client does not have.
__missingAtlases = {}
function Region:SetAtlas(name, useSize)
    assert(type(name) == "string", "SetAtlas needs an atlas name")
    if __missingAtlases[name] then return false end
    self.atlas, self.file, self.color = name, nil, nil
    return true
end
function SetPortraitTexture(tex, unit)
    assert(tex and tex.kind == "Texture", "SetPortraitTexture needs a texture")
    tex.portrait = unit
end
function UnitLevel() return 10 end
-- Screenshots: each call is counted; the test fires SCREENSHOT_SUCCEEDED itself.
__screenshots = 0
function Screenshot() __screenshots = __screenshots + 1 end
__cvars = { screenshotFormat = "jpg" }
function GetCVar(name) return __cvars[name] end
function SetCVar(name, value) __cvars[name] = tostring(value) end
-- The player frame's name text, first name and surname on Forever.
PlayerName = NewRegion("FontString", UIParent)
PlayerName.text = "Hotdog Hootsman"
function Region:SetEnabled(v) self.enabled = not not v end
function Region:IsEnabled() return self.enabled ~= false end
function Region:SetClipsChildren(v) self.clipsChildren = v end

-- A StatusBar: a value in a range and a fill texture. Values can be secrets, which the bar takes
-- and hands back as they are, like the client; SetValue takes an interpolation as on Forever.
local StatusBar = {}
function __makeStatusBar(b)
    b.min, b.max, b.value = 0, 1, 0
    b.fill = b:CreateTexture(nil, "ARTWORK")
    for k, fn in pairs(StatusBar) do b[k] = fn end
end
function StatusBar:SetMinMaxValues(lo, hi) self.min, self.max = lo, hi end
function StatusBar:GetMinMaxValues() return self.min, self.max end
function StatusBar:SetValue(v, interpolation) self.value, self.interpolation = v, interpolation end
function StatusBar:GetValue() return self.value end
function StatusBar:GetStatusBarTexture() return self.fill end
function StatusBar:SetStatusBarColor(r, g, b) self.barColor = { r, g, b } end
function StatusBar:GetStatusBarColor()
    local c = self.barColor or { 1, 1, 1 }
    return c[1], c[2], c[3], 1
end
function StatusBar:SetReverseFill(v) self.reverse = v end
function StatusBar:SetStatusBarTexture(t)
    assert(type(t) == "table" and t.kind == "Texture", "SetStatusBarTexture takes a texture here")
    self.fill = t
end
local function NewStatusBar(name, parent, w, h)
    local b = CreateFrame("StatusBar", name, parent)
    b.w, b.h, b.debugName = w, h, name
    return b
end

-- Forever's unit frames (Blizzard_UnitFrame/Mainline): the bars sit deep in each frame, and
-- UnitFrame_Initialize also keeps them as .healthbar and .manabar. 124x20 and 124x10, as on Forever.
local function UnitFrame(name, contentKey, mainKey)
    local f = CreateFrame("Frame", name, UIParent)
    local content = CreateFrame("Frame", nil, f)
    local main = CreateFrame("Frame", nil, content)
    f[contentKey], content[mainKey] = content, main
    main.HealthBarsContainer = CreateFrame("Frame", nil, main)
    main.HealthBarsContainer.HealthBar = NewStatusBar(name .. ".HealthBar", main.HealthBarsContainer, 124, 20)
    main.ManaBar = NewStatusBar(name .. ".ManaBar", main, 124, 10)
    -- The masks that shape the bars: the player's health mask is on the container, the rest on the bar.
    main.HealthBarsContainer.HealthBarMask = main.HealthBarsContainer:CreateMaskTexture()
    main.ManaBar.ManaBarMask = main.ManaBar:CreateMaskTexture()
    f.healthbar, f.manabar = main.HealthBarsContainer.HealthBar, main.ManaBar
    return f
end
PlayerFrame = UnitFrame("PlayerFrame", "PlayerFrameContent", "PlayerFrameContentMain")
-- The player's health-loss animation: a red bar beside the health bar, shown for a moment after damage
-- (AnimatedHealthLossMixin, which stores itself on the health bar).
do
    local container = PlayerFrame.healthbar.parent
    local loss = NewStatusBar("PlayerFrame.HealthBarAnimatedLoss", container, 124, 20)
    container.PlayerFrameHealthBarAnimatedLoss = loss
    PlayerFrame.healthbar.AnimatedLossBar = loss
    loss:Hide()
    -- The client's prediction of the player's own heals and others' (PlayerFrame.xml): bar segments with a Fill.
    for _, key in ipairs({ "MyHealPredictionBar", "OtherHealPredictionBar" }) do
        local segment = CreateFrame("Frame", nil, PlayerFrame.healthbar)
        segment.Fill = segment:CreateTexture(nil, "BORDER")
        PlayerFrame.healthbar[key] = segment
    end
end
TargetFrame = UnitFrame("TargetFrame", "TargetFrameContent", "TargetFrameContentMain")
FocusFrame = UnitFrame("FocusFrame", "TargetFrameContent", "TargetFrameContentMain")
-- The targets of target (TargetFrameMixin:CreateTargetofTarget): .HealthBar 70x11 and .ManaBar 78x7 under Camelot,
-- each with its mask on the bar.
local function TargetOfTarget(name, owner)
    local f = CreateFrame("Button", name, owner)
    f.HealthBar = NewStatusBar(name .. ".HealthBar", f, 70, 11)
    f.ManaBar = NewStatusBar(name .. ".ManaBar", f, 78, 7)
    f.HealthBar.HealthBarMask = f.HealthBar:CreateMaskTexture()
    f.ManaBar.ManaBarMask = f.ManaBar:CreateMaskTexture()
    owner.totFrame = f
    return f
end
TargetFrameToT = TargetOfTarget("TargetFrameToT", TargetFrame)
FocusFrameToT = TargetOfTarget("FocusFrameToT", FocusFrame)
-- The pet's frame (PetFrame.xml): named bars, and masks named after them.
PetFrame = CreateFrame("Button", "PetFrame", UIParent)
PetFrameHealthBar = NewStatusBar("PetFrameHealthBar", PetFrame, 70, 11)
PetFrameManaBar = NewStatusBar("PetFrameManaBar", PetFrame, 77, 7)
PetFrameHealthBarMask = PetFrameHealthBar:CreateMaskTexture()
PetFrameManaBarMask = PetFrameManaBar:CreateMaskTexture()
PetFrame.healthbar, PetFrame.manabar = PetFrameHealthBar, PetFrameManaBar
-- The target's portrait, on the frame's container (TargetFrame.xml).
TargetFrame.TargetFrameContainer = CreateFrame("Frame", nil, TargetFrame)
TargetFrame.TargetFrameContainer.Portrait = TargetFrame.TargetFrameContainer:CreateTexture(nil, "BACKGROUND")

-- The target: nil for none, else { guid, name, dead }. Its health is secret like the player's.
__target = nil
-- A nameplate's unit (__units.nameplateN, set by __showPlate) exists, has its guid and can be dead like the target.
local function plateUnit(unit)
    return type(unit) == "string" and unit:match("^nameplate%d+$") and __units[unit] or nil
end
function UnitExists(unit)
    if unit == "player" then return true end
    if plateUnit(unit) then return true end
    return unit == "target" and __target ~= nil
end
function UnitGUID(unit)
    if unit == "player" then return "Player-1-00000001" end
    if unit == "target" and __target then return __target.guid end
    local u = plateUnit(unit)
    if u then return u.guid end
end
function UnitIsDead(unit)
    local u = plateUnit(unit)
    if u then return u.dead or false end
    return unit == "target" and __target ~= nil and __target.dead or false
end
function UnitIsDeadOrGhost(unit)
    if unit == "player" then return __player.dead or false end
    return UnitIsDead(unit)
end
-- The target: friendly when __target.friendly is set; "player" when it is you.
function UnitIsUnit(a, b)
    if a == b then return true end
    local function me(u) return u == "player" or (u == "target" and __target ~= nil and __target.isPlayer) end
    return me(a) and me(b)
end
function UnitCanAssist(_, unit)
    if unit == "player" then return true end
    return unit == "target" and __target ~= nil and (__target.friendly or __target.isPlayer) or false
end
function UnitCanAttack(_, unit)
    if type(unit) == "string" and unit:match("^nameplate%d+$") then
        local u = __units[unit]
        return u ~= nil and not u.friendly and not u.isPlayer
    end
    return unit == "target" and __target ~= nil and not __target.friendly and not __target.isPlayer
end
function GetComboPoints() return 0 end
-- Wall-clock seconds, as the client's time(): moves with the mock's clock.
__epoch = 1800000000
function time() return __epoch + math.floor(__now) end
-- Temporary enchants (rogue poisons) on the weapons: __weapons.mainHand and offHand, true when coated. The client
-- answers hasMainHandEnchant, expiration, charges, enchantID, then the same for the off hand.
__weapons = { mainHand = false, offHand = false }
function GetWeaponEnchantInfo()
    return __weapons.mainHand, __weapons.mainHand and 1800000 or nil, 0, __weapons.mainHand and 7 or nil,
        __weapons.offHand, __weapons.offHand and 1800000 or nil, 0, __weapons.offHand and 7 or nil
end

-- Spells by ID: __spells[id] = { name, description }.
__spells = {}
C_Spell = {
    GetSpellName = function(id) return __spells[id] and __spells[id][1] end,
    GetSpellDescription = function(id) return __spells[id] and __spells[id][2] end,
    -- What each spell costs right now: __spellCosts[id] = { { type = 0, name = "MANA", cost = 65 } }, or nil if free.
    GetSpellPowerCost = function(id) return __spellCosts[id] end,
}
__spellCosts = {}
-- The player's auras by spell ID: __playerAuras[id] = { expirationTime = ... }. Forever may keep auras secret
-- (SecretWhenUnitAuraRestricted), so they are secret unless __aurasReadable is set.
__playerAuras, __aurasReadable = {}, false
-- The player's debuffs, in order: __playerDebuffs[i] = { name, spellId, auraInstanceID, duration, ... }. Each one is
-- secret unless __aurasReadable is set.
__playerDebuffs = {}
local function debuffAt(unit, i)
    assert(type(unit) == "string", "aura lookups need a unit")
    assert(type(i) == "number", "aura lookups need an index")
    local aura = unit == "player" and __playerDebuffs[i]
    if not aura then return nil end
    return __aurasReadable and aura or __secret()
end
C_UnitAuras = {
    GetPlayerAuraBySpellID = function(id)
        assert(type(id) == "number", "GetPlayerAuraBySpellID needs a spell ID")
        if not __aurasReadable then return __secret() end
        return __playerAuras[id]
    end,
    GetUnitAuras = function(unit, filter)
        assert(type(unit) == "string" and type(filter) == "string", "Usage: GetUnitAuras(unit, filter)")
        local list = {}
        if filter:find("HARMFUL") then
            for i = 1, #__playerDebuffs do list[i] = debuffAt(unit, i) end
        end
        return list
    end,
    GetAuraDataByIndex = function(unit, i, filter)
        if filter and not filter:find("HARMFUL") then return nil end
        return debuffAt(unit, i)
    end,
    GetDebuffDataByIndex = function(unit, i) return debuffAt(unit, i) end,
    -- A duration object widgets take; its numbers are secret like the aura's.
    GetAuraDuration = function(unit, id)
        assert(type(unit) == "string" and type(id) == "number", "Usage: GetAuraDuration(unit, auraInstanceID)")
        for _, aura in ipairs(__playerDebuffs) do
            if aura.auraInstanceID == id then
                return {
                    GetRemainingDuration = function() return __aurasReadable and aura.duration or __secret() end,
                    GetTotalDuration = function() return __aurasReadable and aura.duration or __secret() end,
                }
            end
        end
        error("GetAuraDuration: no aura with that instance ID")
    end,
}
-- Other addons loaded: __addons[name] = true.
__addons = {}
-- The addon's toc fields: the version is the toc's own @project-version@ until a build fills it in.
__addonVersion = "@project-version@"
C_AddOns = {
    IsAddOnLoaded = function(name) return __addons[name] or false end,
    GetAddOnMetadata = function(name, field)
        assert(type(name) == "string" and type(field) == "string", "Usage: GetAddOnMetadata(addon, field)")
        if name == "SmoothAnimatedBars" and field == "Version" then return __addonVersion end
    end,
}
__player.power = 0 -- UnitPowerType index: 0 mana, 1 rage, 3 energy
local POWER_TOKENS = { [0] = "MANA", [1] = "RAGE", [2] = "FOCUS", [3] = "ENERGY" }
function UnitPowerType() return __player.power, POWER_TOKENS[__player.power] end
function UnitHealth() return __secret() end
function UnitHealthMax() return __secret() end
function UnitPower() return __secret() end
function UnitPowerMax() return __secret() end
-- The client's own StatusBar smoothing (Forever).
Enum = { StatusBarInterpolation = { Immediate = 0, ExponentialEaseOut = 1 }, LuaCurveType = { Linear = 0, Step = 1 } }

-- Curves (C_CurveUtil): plain points, evaluated on a value the client keeps secret into another secret, which widgets
-- take (Region:SetAlpha). UnitPowerPercent evaluates one on the unit's share of its power, __powerPercent[unit]
-- (0..1, the mock's own; addons only ever get a secret).
local Curve = {}
Curve.__index = Curve
local function evaluate(c, x)
    local pts = c.points
    if #pts == 0 then return 0 end
    if x <= pts[1][1] then return pts[1][2] end
    for i = #pts, 1, -1 do
        local p = pts[i]
        if x >= p[1] then
            local q = pts[i + 1]
            if not q or c.type == Enum.LuaCurveType.Step then return p[2] end
            return p[2] + (q[2] - p[2]) * (x - p[1]) / (q[1] - p[1])
        end
    end
end
function Curve:SetType(t)
    assert(t == Enum.LuaCurveType.Linear or t == Enum.LuaCurveType.Step, "SetType: bad curve type")
    self.type = t
end
function Curve:AddPoint(x, y)
    assert(type(x) == "number" and type(y) == "number", "Usage: curve:AddPoint(x, y)")
    local pts = self.points
    pts[#pts + 1] = { x, y }
    table.sort(pts, function(a, b) return a[1] < b[1] end)
end
function Curve:Evaluate(x)
    if issecretvalue(x) then return __secret(evaluate(self, secretValues[x] or 0)) end
    assert(type(x) == "number", "Usage: curve:Evaluate(x)")
    return evaluate(self, x)
end
C_CurveUtil = {
    CreateCurve = function() return setmetatable({ points = {}, type = Enum.LuaCurveType.Linear }, Curve) end,
}
__powerPercent = {}
function UnitPowerPercent(unit, powerType, unmodified, curve)
    assert(type(unit) == "string", "Usage: UnitPowerPercent(unit [, powerType, unmodified, curve])")
    assert(curve == nil or getmetatable(curve) == Curve, "bad argument #4 to 'UnitPowerPercent' (curve expected)")
    local p = __powerPercent[unit] or 0
    return __secret(curve and evaluate(curve, p) or p)
end
PowerBarColor = { MANA = { r = 0, g = 0, b = 1 }, RAGE = { r = 1, g = 0, b = 0 }, ENERGY = { r = 1, g = 1, b = 0 } }

GameFontNormal = { GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end }
SystemFont_NamePlate = { GetFont = function() return "Fonts\\FRIZQT__.TTF", 9, "" end }
-- What the plates are laid out with (Blizzard_NamePlates.lua); the texts' height comes from here.
-- unitNameAnchorStyle: where the name goes (NamePlateConstants.NAME_ANCHOR_STYLES), above the bar unless set.
NamePlateConstants = { NAME_ANCHOR_STYLES = { InsideHealthBar = 1, AboveHealthBar = 2, CenteredAboveHealthBar = 3 } }
NamePlateSetupOptions = { healthBarFontHeight = 11, unitNameAnchorStyle = 2 }

__combat = false
function InCombatLockdown() return __combat end
function UnitAffectingCombat(unit) return unit == "player" and __combat or false end

GameTooltip = NewRegion("Frame", UIParent)
GameTooltip.shown = false
function GameTooltip:SetOwner(owner) self.owner, self.lines = owner, {} end
function GameTooltip:AddLine(text) self.lines[#self.lines + 1] = text end
function GameTooltip:AddDoubleLine(left, right) self.lines[#self.lines + 1] = left .. " = " .. right end
function GameTooltip:IsOwned(frame) return self.owner == frame end

-- Native Settings API, with the signatures of the forever branch of the game's UI source
-- (Blizzard_Settings.lua, Blizzard_SettingControls.lua), which Era and Anniversary share.
__settings = {}
Settings = {}
-- The settings panel, and the frame inside it that a canvas category's page is shown in.
__settingsPanel = NewRegion("Frame", UIParent)
__settingsPanel.shown = false
__settingsCanvas = NewRegion("Frame", __settingsPanel)
local Setting = {}
Setting.__index = Setting
function Setting:SetValueChangedCallback(fn) self.cb = fn end
function Setting:GetValue() return self.tbl[self.key] end
-- Like the client: no change, no callback. Writing the table directly then calling SetValue is a no-op.
function Setting:SetValue(v)
    if self.tbl[self.key] == v then return end
    self.tbl[self.key] = v
    if self.cb then self.cb(self, v) end
end

-- Initializers (ScrollBoxFactoryInitializerMixin): a row template and its data.
local Initializer = {}
Initializer.__index = Initializer
function Initializer:GetTemplate() return self.template end
function Initializer:InitFrame(frame) if frame.Init then frame:Init(self) end end
function Initializer:Resetter(frame) if frame.Release then frame:Release(self) end end
-- SettingsListElementInitializer:Indent: the row's label moves in, as for a setting under another.
function Initializer:Indent() self.data.indent = 30 end
local function NewInitializer(template, kind, data)
    return setmetatable({ template = template, kind = kind, data = data }, Initializer)
end
local function SettingData(setting, options, tooltip)
    return { setting = setting, name = setting.name, options = options or {}, tooltip = tooltip }
end

-- A vertical layout list: the game draws its rows on row frames it reuses for every category. On
-- Forever rows our code set up carried our taint into the Social page, whose protected
-- IsUserOAuthed was then blocked in our name, so anything added to one is flagged.
local function AddToSharedList() __sharedListTainted = true end
function Settings.RegisterVerticalLayoutCategory(name)
    local cat = { name = name }
    function cat:GetID() return self.name end
    return cat, { AddInitializer = AddToSharedList }
end
function Settings.RegisterInitializer() AddToSharedList() end
function Settings.CreateCheckbox() AddToSharedList() end
function Settings.CreateSlider() AddToSharedList() end
function Settings.CreateDropdown() AddToSharedList() end

function Settings.RegisterCanvasLayoutCategory(frame, name)
    assert(type(frame) == "table" and frame.kind == "Frame" and type(name) == "string", "bad RegisterCanvasLayoutCategory args")
    local cat = { name = name, frame = frame }
    function cat:GetID() return self.name end
    return cat
end
function Settings.RegisterAddOnSetting(cat, variable, key, tbl, vtype, name, default)
    assert(type(cat) == "table" and type(variable) == "string" and type(key) == "string"
        and type(tbl) == "table" and type(name) == "string", "bad RegisterAddOnSetting args for " .. tostring(key))
    assert(vtype == type(default), "type/default mismatch for " .. key)
    assert(not __settings[key], "duplicate setting " .. key)
    if tbl[key] == nil then tbl[key] = default end
    local s = setmetatable({ key = key, tbl = tbl, name = name, vtype = vtype }, Setting)
    __settings[key] = s
    return s
end
function Settings.CreateCheckboxInitializer(s, options, tooltip)
    assert(s.vtype == "boolean", "checkbox on non-boolean " .. s.key)
    return NewInitializer("SettingsCheckboxControlTemplate", "checkbox", SettingData(s, options, tooltip))
end
function Settings.CreateSliderOptions(lo, hi, step)
    local o = { min = lo, max = hi, step = step }
    function o:SetLabelFormatter(_, f) self.fmt = f end
    return o
end
function Settings.CreateSliderInitializer(s, o, tooltip)
    assert(s.vtype == "number" and o ~= nil, "slider on non-number or without options " .. s.key)
    assert(type(o.fmt(s:GetValue())) == "string", "slider formatter for " .. s.key)
    return NewInitializer("SettingsSliderControlTemplate", "slider", SettingData(s, o, tooltip))
end
-- The game calls getOptions each time the menu opens; tests call it the same way.
function Settings.CreateDropdownInitializer(s, getOptions, tooltip)
    assert(type(getOptions) == "function" and #getOptions() > 0, "dropdown without options " .. s.key)
    return NewInitializer("SettingsDropdownControlTemplate", "dropdown", SettingData(s, getOptions, tooltip))
end
-- Add returns the option table, which the menu passes to the option's onEnter on hover.
function Settings.CreateControlTextContainer()
    local c = { data = {} }
    function c:Add(value, label, tooltip)
        local data = { text = label, label = label, tooltip = tooltip, value = value }
        self.data[#self.data + 1] = data
        return data
    end
    function c:GetData() return self.data end
    return c
end
__menuOpen = false
local menuManager = {}
function menuManager:IsAnyMenuOpen()
    assert(self == menuManager, "IsAnyMenuOpen is a method of the menu manager")
    return __menuOpen
end
Menu = { GetManager = function() return menuManager end }
-- Menu.ModifyMenu (Blizzard_Menu/Menu.lua): callbacks by tag, run with (owner, rootDescription, contextData) as each
-- menu with that tag is built. __openUnitMenu builds one as UnitPopup_OpenMenu does and returns its elements.
__menuCallbacks = {}
function Menu.ModifyMenu(tag, callback)
    assert(type(tag) == "string" and type(callback) == "function", "Menu.ModifyMenu(tag, callback)")
    __menuCallbacks[tag] = __menuCallbacks[tag] or {}
    table.insert(__menuCallbacks[tag], callback)
end
function __openUnitMenu(which, contextData)
    local root = { elements = {} }
    local function add(kind, text, fn)
        local e = { kind = kind, text = text, onClick = fn }
        table.insert(root.elements, e)
        return e
    end
    function root:CreateDivider() return add("divider") end
    function root:CreateTitle(text) return add("title", text) end
    function root:CreateButton(text, fn) return add("button", text, fn) end
    for _, cb in ipairs(__menuCallbacks["MENU_UNIT_" .. which] or {}) do cb(contextData.ownerFrame, root, contextData) end
    -- As in the client: a unit with a secret identity gives the menu a title with a secret width, which the layout
    -- can measure only untainted, and anything an addon added taints it.
    if #root.elements > 0 and contextData.unit and __identitySecret[contextData.unit] then
        error("FrameUtil.lua:223: attempt to perform arithmetic on local 'frameLeft' (a secret number value, "
              .. "while execution tainted by 'SmoothAnimatedBars')")
    end
    return root.elements
end
function Settings.RegisterAddOnCategory(cat) __settingsCategory = cat end
-- Opening a canvas category puts its page in the panel and shows it (SettingsPanelMixin:DisplayLayout).
function Settings.OpenToCategory(id)
    __openedCategory = id
    local cat = __settingsCategory
    if cat and cat:GetID() == id and cat.frame then
        __settingsPanel:Show()
        cat.frame.parent = __settingsCanvas
        cat.frame:Show()
    end
end
-- Closing the panel hides the page, so the next open shows it afresh.
function __closeSettings()
    __settingsPanel.shown = false
    if __settingsCategory and __settingsCategory.frame then __settingsCategory.frame:Hide() end
end
MinimalSliderWithSteppersMixin = { Label = { Right = 1 } }
function CreateSettingsButtonInitializer(name, buttonText, buttonClick, tooltip, addSearchTags)
    assert(addSearchTags ~= nil, "CreateSettingsButtonInitializer needs addSearchTags")
    local data = { name = name, buttonText = buttonText, buttonClick = buttonClick, tooltip = tooltip }
    return NewInitializer("SettingButtonControlTemplate", "button", data)
end
function CreateSettingsListSectionHeaderInitializer(name, tooltip)
    return NewInitializer("SettingsListSectionHeaderTemplate", "header", { name = name, tooltip = tooltip })
end

-- The settings rows as drawn, in page order: each row frame and what its initializer holds.
function __settingsRows()
    local out = {}
    for _, r in ipairs(__regions) do
        local init = r.initializer
        if r.rowTemplate and init then
            local d = init.data
            local getOptions = type(d.options) == "function" and d.options or nil
            out[#out + 1] = {
                kind = init.kind, key = d.setting and d.setting.key, name = d.name, frame = r, indent = d.indent,
                onClick = d.buttonClick, getOptions = getOptions, options = getOptions and getOptions(),
            }
        end
    end
    return out
end

-- Nameplates (Blizzard_NamePlates, forever branch): each token's plate base frame gets a unit frame from the game's
-- pool when the plate shows (NamePlateBaseMixin:AcquireUnitFrame) and gives it back when it goes, so one health bar
-- shows mob after mob. The health bar is UnitFrame.HealthBarsContainer.healthBar, with no mask. Forbidden plates
-- (friendly plates in instances) are not handed to addons at all.
__plates, __platePool = {}, {}
local plateBases = {}
local function NewPlateUnitFrame()
    local uf = CreateFrame("Button", nil, UIParent)
    uf.HealthBarsContainer = CreateFrame("Frame", nil, uf)
    local hb = NewStatusBar("NamePlate.healthBar", uf.HealthBarsContainer, 110, 10)
    uf.HealthBarsContainer.healthBar = hb
    -- The bar's texts (TextStatusBar: health numbers, hidden unless the game's settings show them) and the name, in
    -- the plates' font object at the plates' text height, as Blizzard_NamePlateUnitFrame.lua sets them.
    for _, key in ipairs({ "Text", "LeftText", "RightText" }) do
        hb[key] = hb:CreateFontString(nil, "OVERLAY")
        hb[key]:SetFontObject(SystemFont_NamePlate)
        hb[key]:SetTextHeight(NamePlateSetupOptions.healthBarFontHeight)
        hb[key]:Hide()
    end
    hb.LeftText:SetPoint("RIGHT", hb, "RIGHT", -4, 0)
    hb.RightText:SetPoint("RIGHT", hb.LeftText, "LEFT", -2, 0)
    hb.Text:SetPoint("RIGHT", hb.RightText, "LEFT", 2, 0)
    uf.name = uf:CreateFontString(nil, "OVERLAY")
    uf.name:SetFontObject(SystemFont_NamePlate)
    uf.name:SetTextHeight(NamePlateSetupOptions.healthBarFontHeight)
    uf.name:SetPoint("BOTTOM", hb, "TOP", 0, 2)
    return uf
end
-- __showPlate(token, unit, opts): the unit goes into __units[token] ({ friendly, isOtherPlayer, color, reaction });
-- opts.forbidden makes the plate forbidden; opts.late hands out its unit frame only after NAME_PLATE_UNIT_ADDED.
function __showPlate(token, unit, opts)
    opts = opts or {}
    __units[token] = unit
    local base = plateBases[token] or CreateFrame("Frame", nil, UIParent)
    plateBases[token] = base
    base.forbidden = opts.forbidden
    local function acquire()
        local uf = table.remove(__platePool) or NewPlateUnitFrame()
        uf:SetParent(base)
        uf:Show()
        base.UnitFrame, base.unitToken = uf, token
        local hb = uf.HealthBarsContainer.healthBar
        hb:SetMinMaxValues(0, __secret())
        hb:SetValue(__secret())
        local c = unit.color or { 0.9, 0.1, 0.1 }
        hb:SetStatusBarColor(c[1], c[2], c[3])
    end
    __plates[token] = base
    if not opts.late then acquire() end
    __fire("NAME_PLATE_UNIT_ADDED", token)
    if opts.late then acquire() end
    return base
end
function __hidePlate(token)
    local base = __plates[token]
    __fire("NAME_PLATE_UNIT_REMOVED", token)
    if base.UnitFrame then
        base.UnitFrame:Hide()
        table.insert(__platePool, base.UnitFrame)
        base.UnitFrame = nil
    end
    base.unitToken, __plates[token], __units[token] = nil, nil, nil
end
C_NamePlate = {
    GetNamePlateForUnit = function(token)
        assert(type(token) == "string", "GetNamePlateForUnit needs a unit token")
        local base = __plates[token]
        if base and not base.forbidden then return base end
    end,
    GetNamePlates = function()
        local out = {}
        for _, base in pairs(__plates) do
            if not base.forbidden then out[#out + 1] = base end
        end
        return out
    end,
}

-- Where the player is: __zone, and __instance as GetInstanceInfo's type ("none", "party", "raid"...).
__zone, __instance = "Elwynn Forest", "none"
function GetRealZoneText() return __zone end
function GetInstanceInfo() return __zone, __instance end
date = os.date

-- The client's millisecond timer, its frame rate and the addon's memory.
function debugprofilestop() return os.clock() * 1000 end
__fps = 60
function GetFramerate() return __fps end
function UpdateAddOnMemoryUsage() end
function GetAddOnMemoryUsage(name)
    assert(type(name) == "string" or type(name) == "number", "GetAddOnMemoryUsage needs an addon")
    return collectgarbage("count")
end

__markCFunctions()

function __fire(event, ...)
    local unit = ...
    for _, f in ipairs(__frames) do
        local reg = f.events[event]
        if reg and (reg == true or reg == unit) and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
    end
end

function __step(dt)
    __now = __now + dt
    local due = {}
    for i = #__timers, 1, -1 do
        if __timers[i].at <= __now then
            due[#due + 1] = __timers[i]
            table.remove(__timers, i)
        end
    end
    for i = #due, 1, -1 do due[i].fn() end
    for _, f in ipairs(__frames) do
        if f.shown and f.scripts.OnUpdate then f.scripts.OnUpdate(f, dt) end
    end
end

function __load(path, name, ns)
    local chunk = assert(loadfile(path))
    chunk(name, ns)
end

-- Load every file listed in <dir>/<name>.toc, in order, sharing one addon namespace.
function __loadAddon(dir, name)
    local ns = {}
    for line in io.lines(dir .. "/" .. name .. ".toc") do
        line = line:gsub("%s+$", "")
        -- WhatsNewData.lua is written by the build (tools/whatsnew_data.py) and absent from the source; the client
        -- skips a toc file it cannot find, so the mock does for that one.
        local path = dir .. "/" .. line:gsub("\\", "/")
        local f = io.open(path, "rb")
        if f then f:close() end
        if line ~= "" and not line:find("^#") and (f or line ~= "WhatsNewData.lua") then
            __load(path, name, ns)
        end
    end
    return ns
end
