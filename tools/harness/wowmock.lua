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
function Region:SetAllPoints()
    self.points = {}
    self:SetPoint("TOPLEFT")
    self:SetPoint("BOTTOMRIGHT")
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
function Region:GetVerticalScrollRange() return 0 end
function Region:SetAlpha(a) self.alpha = a end
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
function Region:RegisterEvent(e) self.events[e] = true end
function Region:UnregisterEvent(e) self.events[e] = nil end
function Region:IsEventRegistered(e) return self.events[e] end
function Region:SetTexture(file, wh, wv) self.file, self.wrap, self.wrapV, self.color = file, wh, wv or wh, nil end
function Region:SetColorTexture(r, g, b, a) self.file, self.color = "SOLID", { r, g, b, a or 1 } end
function Region:SetVertexColor(r, g, b, a) self.vc, self.grad = { r, g, b, a or 1 }, nil end
function Region:SetGradient(_, c1, c2)
    self.grad = { { c1:GetRGBA() }, { c2:GetRGBA() } }
end
function Region:SetBlendMode(m) self.blend = m end
function Region:SetTexCoord(l, r, t, b) self.tc = { l, r, t, b } end
function Region:SetRotation(rad) self.rotation = rad end
function Region:SetDrawLayer(layer, sub) self.layer, self.sub = layer, sub or 0 end
function Region:SetSnapToPixelGrid() end
function Region:SetTexelSnappingBias() end
function Region:SetFont(_, size) self.fontSize = size end
function Region:SetShadowColor() end
function Region:SetShadowOffset() end
function Region:SetTextColor() end
function Region:SetJustifyH() end
function Region:SetJustifyV() end
function Region:SetWordWrap() end
function Region:SetToplevel() end
function Region:SetChecked(v) self.checked = not not v end
function Region:GetChecked() return self.checked end
function Region:SetText(t) self.text = t end
function Region:SetFormattedText(fmt, ...) self.text = string.format(fmt, ...) end
function Region:GetStringWidth()
    local plain = (self.text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return #plain * (self.fontSize or 12) * 0.55
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

function CreateFrame(frameType, name, parent, template)
    assert(template == nil or ROW_TEMPLATES[template] or TEMPLATES[template], "unknown template " .. tostring(template))
    local f = NewRegion("Frame", parent, "BACKGROUND", 0)
    __frames[#__frames + 1] = f
    if name then _G[name] = f end
    if frameType == "StatusBar" then __makeStatusBar(f) end
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
function UnitName(unit) if unit == "player" then return __player.name, __player.surname end end
function GetRealmName() return __player.realm end
function UnitClass() return "Paladin", __player.class end
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
function __secret() return setmetatable({}, SecretValue) end
function issecretvalue(v) return getmetatable(v) == SecretValue end

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
    for _, name in ipairs({ "UnitHealth", "UnitHealthMax", "UnitPower", "UnitPowerMax" }) do
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
TargetFrame = UnitFrame("TargetFrame", "TargetFrameContent", "TargetFrameContentMain")
__player.power = 0 -- UnitPowerType index: 0 mana, 1 rage, 3 energy
local POWER_TOKENS = { [0] = "MANA", [1] = "RAGE", [2] = "FOCUS", [3] = "ENERGY" }
function UnitPowerType() return __player.power, POWER_TOKENS[__player.power] end
function UnitHealth() return __secret() end
function UnitHealthMax() return __secret() end
function UnitPower() return __secret() end
function UnitPowerMax() return __secret() end
-- The client's own StatusBar smoothing (Forever).
Enum = { StatusBarInterpolation = { Immediate = 0, ExponentialEaseOut = 1 } }
PowerBarColor = { MANA = { r = 0, g = 0, b = 1 }, RAGE = { r = 1, g = 0, b = 0 }, ENERGY = { r = 1, g = 1, b = 0 } }

GameFontNormal = { GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end }

__combat = false
function InCombatLockdown() return __combat end

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
                kind = init.kind, key = d.setting and d.setting.key, name = d.name, frame = r,
                onClick = d.buttonClick, getOptions = getOptions, options = getOptions and getOptions(),
            }
        end
    end
    return out
end

__markCFunctions()

function __fire(event, ...)
    for _, f in ipairs(__frames) do
        if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
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
        if line ~= "" and not line:find("^#") then
            __load(dir .. "/" .. line:gsub("\\", "/"), name, ns)
        end
    end
    return ns
end
