-- The DoT marker on the target frame's health bar, and the kill icon on its portrait (the dots setting).
--
-- The marker is a second liquid eating into the health: the health the player's DoTs will still burn away
-- turns into a liquid of the DoTs' own colour (Void for Shadow, Fire for Fire, ...), and the health liquid
-- draws back to where the target's health will end once they are done. If the health liquid is gone, the DoTs
-- will kill the target. The numbers come from Dots.lua; the target's health is secret, so, as for the liquid
-- (Bars.lua), the client does every comparison:
--   * a hidden StatusBar of ours takes the game bar's (secret) value, so its fill ends where the game's does;
--   * a hidden "span" StatusBar one bar-width wide has its right edge on that fill's edge and fills from the
--     right, on the bar's own (secret) range, with the DoTs' damage: its fill's left edge is where the health
--     will end;
--   * the DoT liquid hangs on the health's edge like the health liquid does, in a clip frame starting at the
--     span's left edge. The health liquid's front is moved onto that edge (Bars.Front) and the DoT liquid is
--     drawn under it, so the two meet in the health liquid's wavy front, and nothing shows between them;
--   * the kill icon rides the fill edge of a very long StatusBar whose range is the target's (secret) health and
--     whose value is the damage, inside a window the icon's size: it slides into view only as the damage reaches
--     the health, in the last icon-width of a bar LONG wide.
-- Nothing of the game's is changed: our frames are children of the bar and the target frame, at the bar's level
-- so the game's text stays on top, and the kill icon just above the target frame. The icon is the game's own:
-- the skull the target frame shows for a target far above your level.
--
-- The idea comes from DoesItDie (see Dots.lua).

local _, ns = ...

local Marker = {}
ns.Marker = Marker

local REFRESH_EVERY = 0.1 -- seconds between reading the DoTs
local FEED_EVERY = 0.05   -- seconds between handing the game bar's value to our hidden bar
local GLIDE = 6           -- how fast the marker eases to a new value (higher is snappier)
local ROOM = 10           -- as Bars.lua: room past the front for the waves
local SPILL = 16          -- as Bars.lua: how far motes can fly above, below and past the end
-- How far the DoT liquid reaches under the health liquid, so its waves never open a gap between them.
local OVERLAP = 6
-- Under the health liquid: its textures use sublevels 3 to 7, so these end up at -5 to -1.
local UNDER = -8
local IDLE_FPS = 30
local ICON_ATLAS = "UI-HUD-UnitFrame-Target-HighLevelTarget_Icon"
local ICON_HEIGHT = 30
local LONG = 10000        -- the kill icon's bar: it starts sliding in ICON_HEIGHT / LONG short of lethal
local SPLASH_APPLIED, SPLASH_TICK = 0.6, 0.2

-- The DoT liquid's theme by the school of the DoT with the most damage still to deal (Dots.lua's masks).
local SCHOOL_THEMES = {
    [1] = "blood", [2] = "holy", [4] = "fire", [8] = "plague", [16] = "frost", [20] = "fire", [32] = "void",
    [64] = "arcane",
}
local DEFAULT_THEME = "void"

local function Secret(v)
    return issecretvalue and issecretvalue(v) or false
end

local function AtParentLevel(frame, parent)
    if frame.SetUsingParentLevel then
        frame:SetUsingParentLevel(true)
    else
        frame:SetFrameLevel(parent:GetFrameLevel())
    end
end

-- A StatusBar whose fill is never drawn, only anchored to.
local function HiddenBar(parent)
    local bar = CreateFrame("StatusBar", nil, parent)
    local fill = bar:CreateTexture(nil, "BACKGROUND")
    fill:SetColorTexture(1, 1, 1, 1)
    bar:SetStatusBarTexture(fill)
    bar:GetStatusBarTexture():SetAlpha(0)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    return bar
end

local INTERPOLATION = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut

-- The game's skull on a texture of ours, at ICON_HEIGHT with the atlas's proportions. False if the client
-- has no such atlas. Also used by Capture.lua for the gallery.
function Marker.KillIcon(texture)
    if not (texture.SetAtlas and texture:SetAtlas(ICON_ATLAS, true)) then return false end
    local w, h = texture:GetSize()
    if type(w) ~= "number" or type(h) ~= "number" or Secret(w) or Secret(h) or w <= 0 or h <= 0 then
        w, h = 1, 1
    end
    texture:SetSize(ICON_HEIGHT * w / h, ICON_HEIGHT)
    return true
end

--------------------------------------------------------------------------------
-- One marker
--------------------------------------------------------------------------------

-- spec: { bar = the health bar, mask = its mask or nil, iconHost = the frame the kill icon belongs to,
-- portrait = the region it sits on, source = function() returning max, health, total, list (max and health
-- may be secret; list as Dots.Target's), visible = function() whether the target is there }.
local function New(spec)
    local bar = spec.bar
    local w, h = bar:GetWidth(), bar:GetHeight()
    local m = { spec = spec, bar = bar, shown = 0, value = 0, since = REFRESH_EVERY, feed = 0, idle = 0, pulse = 0,
                width = w, height = h, fresh = true }

    -- Where the game's fill ends, with the client's smoothing.
    m.proxy = HiddenBar(bar)
    m.proxy:SetAllPoints(bar)
    local edge = m.proxy:GetStatusBarTexture()

    -- From the bar's left edge, with room for the motes above, below and past the end (as Bars.lua's clip).
    m.clip = CreateFrame("Frame", nil, bar)
    AtParentLevel(m.clip, bar)
    m.clip:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, SPILL)
    m.clip:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", SPILL, -SPILL)
    m.clip:SetClipsChildren(true)
    m.clip:Hide()

    -- The span of the health the DoTs will burn: its fill's left edge is where the health will end.
    m.span = HiddenBar(m.clip)
    AtParentLevel(m.span, m.clip)
    m.span:SetPoint("TOPRIGHT", edge, "TOPRIGHT")
    m.span:SetPoint("BOTTOMRIGHT", edge, "BOTTOMRIGHT")
    m.span:SetWidth(w)
    if m.span.SetReverseFill then m.span:SetReverseFill(true) end
    m.spanFill = m.span:GetStatusBarTexture()

    -- The DoT liquid, cut off at the span's left edge (less the overlap under the health liquid).
    m.pool = CreateFrame("Frame", nil, m.clip)
    AtParentLevel(m.pool, m.clip)
    m.pool:SetClipsChildren(true)
    m.mover = CreateFrame("Frame", nil, m.pool)
    AtParentLevel(m.mover, m.pool)
    m.mover:SetPoint("TOPRIGHT", edge, "TOPRIGHT")
    m.mover:SetPoint("BOTTOMRIGHT", edge, "BOTTOMRIGHT")
    m.mover:SetWidth(w)
    m.liquid = ns.Liquid.New(m.mover, math.max(w, 1) + ROOM, math.max(h, 1), ns.Themes.Get(DEFAULT_THEME), ns.Core.db)
    if spec.mask then
        local free = {}
        for _, mote in ipairs(m.liquid.motes) do free[mote.tex] = true end
        for _, t in ipairs(m.liquid.textures) do
            if not free[t] then t:AddMaskTexture(spec.mask) end
        end
    end

    -- The kill icon.
    local host = spec.iconHost
    m.window = CreateFrame("Frame", nil, host)
    m.window:SetPoint("CENTER", spec.portrait or host, "CENTER")
    m.window:SetClipsChildren(true)
    m.window:Hide()
    m.killBar = HiddenBar(m.window)
    m.killBar:SetPoint("RIGHT", m.window, "RIGHT")
    m.icon = m.killBar:CreateTexture(nil, "OVERLAY")
    m.hasIcon = Marker.KillIcon(m.icon)
    m.icon:SetPoint("RIGHT", m.killBar:GetStatusBarTexture(), "RIGHT")
    local iw, ih = m.icon:GetSize()
    m.window:SetSize(iw, ih)
    m.killBar:SetSize(LONG, ih)
    return m
end

-- Under the health liquid when it shows, reaching OVERLAP under its front; over the game's own fill, cut at
-- the span's edge, when it does not.
local function Layer(m)
    local under = ns.Bars.IsLive(m.bar)
    if under == m.under then return end
    m.under = under
    m.liquid:SetSublevelOffset(under and UNDER or 0)
    m.pool:ClearAllPoints()
    m.pool:SetPoint("TOPLEFT", m.spanFill, "TOPLEFT", under and -OVERLAP or 0, SPILL)
    m.pool:SetPoint("BOTTOMRIGHT", m.clip, "BOTTOMRIGHT")
end

-- Just above the frame the icon belongs to. Some of the game's frames report a secret level on Forever.
local function RaiseIcon(m)
    local ok, level = pcall(m.spec.iconHost.GetFrameLevel, m.spec.iconHost)
    if ok and type(level) == "number" and not Secret(level) and level ~= m.iconLevel then
        m.iconLevel = level
        m.window:SetFrameLevel(level + 20)
        m.killBar:SetFrameLevel(level + 21)
    end
end

local function Hide(m)
    if m.clip:IsShown() then
        m.clip:Hide()
        m.liquid:HideAll()
        ns.Bars.Front(m.bar, nil)
    end
    m.window:Hide()
    m.fresh = true -- grows in again next time
end

local function Feed(m, smooth)
    local bar, proxy = m.bar, m.proxy
    proxy:SetMinMaxValues(bar:GetMinMaxValues())
    if smooth and INTERPOLATION then
        proxy:SetValue(bar:GetValue(), INTERPOLATION)
    else
        proxy:SetValue(bar:GetValue())
    end
end

local function ThemeFor(list)
    local top
    for _, entry in ipairs(list) do
        if not top or entry.damage > top.damage then top = entry end
    end
    return top and SCHOOL_THEMES[top.school] or DEFAULT_THEME
end

-- Reads the DoTs and sets the bars' ranges and goal. False when there is nothing to show.
local function Refresh(m)
    local spec = m.spec
    local landed = m.landed
    m.landed = false
    if not spec.visible() then return false end
    local max, health, total, list = spec.source()
    if not list or #list == 0 or total <= 0 then return false end

    local key = ThemeFor(list)
    if key ~= m.themeKey then
        m.themeKey = key
        m.liquid:SetTheme(ns.Bars.Theme(key))
    end
    m.span:SetMinMaxValues(0, max)
    m.killBar:SetMinMaxValues(0, health)
    m.killBar:SetValue(total)
    if m.fresh then
        m.fresh = false
        m.shown = 0
        m.span:SetValue(0)
        Feed(m, false)
        m.liquid:Snap(m.width)
    end
    if not m.clip:IsShown() then
        m.clip:Show()
        Layer(m)
        ns.Bars.Front(m.bar, m.spanFill)
    end
    -- A DoT landing stirs both liquids; a tick (less to come) ripples the DoT liquid.
    if landed then
        m.liquid:Splash(SPLASH_APPLIED, m.width - 8, m.width)
        ns.Bars.StirBar(m.bar)
    elseif total < m.value then
        m.liquid:Splash(SPLASH_TICK, m.width - 8, m.width)
    end
    m.value = total
    m.window:SetShown(m.hasIcon and ns.Core.Get("dotKillIcon") and true or false)
    RaiseIcon(m)
    return true
end

local function Update(m, dt)
    if not m.bar:IsVisible() then return Hide(m) end
    m.feed = m.feed + dt
    if m.feed >= FEED_EVERY then
        m.feed = 0
        Feed(m, true)
    end
    m.since = m.since + dt
    if m.since >= REFRESH_EVERY then
        m.since = 0
        local w, h = m.bar:GetWidth(), m.bar:GetHeight()
        if (w ~= m.width or h ~= m.height) and w >= 1 and h >= 1 then
            m.width, m.height = w, h
            m.span:SetWidth(w)
            m.mover:SetWidth(w)
            m.liquid:SetSize(w + ROOM, h)
        end
        if not Refresh(m) then return Hide(m) end
        Layer(m)
    end
    if not m.clip:IsShown() then return end

    -- The span glides to the damage, so the health liquid draws back smoothly.
    if m.shown ~= m.value then
        m.shown = m.shown + (m.value - m.shown) * math.min(1, dt * GLIDE)
        if math.abs(m.value - m.shown) < math.max(0.05, m.value * 0.002) then m.shown = m.value end
        m.span:SetValue(m.shown)
    end
    if m.window:IsShown() then
        m.pulse = (m.pulse + dt) % 1.4
        m.icon:SetAlpha(0.75 + 0.25 * math.cos(m.pulse / 1.4 * 2 * math.pi))
    end
    -- Once settled only the idle wobble remains, so it drops to IDLE_FPS, as Bars.lua does.
    if m.liquid:IsQuiet() and m.shown == m.value then
        m.idle = m.idle + dt
        if m.idle < 1 / IDLE_FPS then return end
        dt, m.idle = m.idle, 0
    else
        m.idle = 0
    end
    m.liquid:Update(dt, m.width)
end

-- A DoT landed: splash on the next read, which shows it.
local function Landed(m)
    m.landed = true
    m.since = REFRESH_EVERY
end

--------------------------------------------------------------------------------
-- The target frame's marker, and the driver
--------------------------------------------------------------------------------

local target      -- the marker on the target frame, once built
local previews = {}
local driver
local stepAside   -- DoesItDie is loaded: it draws its own marker, so ours stays off
local told

local function TargetHealthBar()
    local tf = TargetFrame
    local main = tf and tf.TargetFrameContent and tf.TargetFrameContent.TargetFrameContentMain
    return (tf and tf.healthbar) or (main and main.HealthBarsContainer and main.HealthBarsContainer.HealthBar)
end

local function TargetPortrait()
    local tf = TargetFrame
    return (tf and tf.TargetFrameContainer and tf.TargetFrameContainer.Portrait) or (tf and tf.portrait)
end

local function TargetThere()
    if not UnitExists("target") then return false end
    local ok, dead = pcall(UnitIsDead, "target")
    if ok and not Secret(dead) and dead then return false end
    return true
end

local function TargetSource()
    local total, list = ns.Dots.Target()
    local _, max = target.bar:GetMinMaxValues()
    return max, UnitHealth("target"), total, list
end

local function Each(fn)
    if target then fn(target) end
    for _, m in ipairs(previews) do fn(m) end
end

-- An error in a marker is reported once and that marker stays hidden; the liquid carries on.
local function OnUpdate(_, elapsed)
    local dt = math.min(elapsed, 0.1)
    if dt <= 0 then return end
    Each(function(m)
        if m.live and not m.err then
            local ok, err = pcall(Update, m, dt)
            if not ok then
                m.err = tostring(err)
                pcall(Hide, m)
                ns.Core.Print("Error in the DoT marker, which is off until a reload: " .. m.err)
            end
        end
    end)
end

local function OtherAddOn()
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    return loaded and loaded("DoesItDie") and true or false
end

-- The bar's mask: on the bar on Forever's target frame, on the container around it on the player's.
local function MaskOf(bar)
    local mask = bar.HealthBarMask or bar:GetParent().HealthBarMask
    if type(mask) == "table" and mask.GetObjectType and mask:GetObjectType() == "MaskTexture" then return mask end
end

-- After the dots or dotKillIcon setting changes, and at login.
function Marker.Apply()
    local want = ns.Core.Get("dots") and true or false
    stepAside = want and OtherAddOn()
    if stepAside and not told then
        told = true
        ns.Core.Print("DoesItDie is loaded and draws its own DoT marker, so this one stays off. "
            .. "Turn DoesItDie off to use it.")
    end
    local live = want and not stepAside
    if live and not target then
        local bar = TargetHealthBar()
        if type(bar) == "table" and bar.GetStatusBarTexture and TargetFrame then
            target = New({ bar = bar, mask = MaskOf(bar), iconHost = TargetFrame, portrait = TargetPortrait(),
                           source = TargetSource, visible = TargetThere })
        end
    end
    ns.Dots.Enable(live)
    if target then
        target.live = live
        if not live then Hide(target) end
    end
    local any = live and target
    for _, m in ipairs(previews) do
        m.live = want
        if not want then Hide(m) end
        any = any or want
    end
    if any and not driver then
        driver = CreateFrame("Frame")
        driver:SetScript("OnUpdate", OnUpdate)
    end
    if driver then driver:SetShown(any and true or false) end
end

-- After an effect toggle: clear what was just switched off.
function Marker.ApplyOptions()
    Each(function(m) m.liquid:ApplyOptions() end)
end

-- A marker on a preview frame's health bar, fed plain numbers by source.
function Marker.Preview(spec)
    spec.mask = spec.mask or MaskOf(spec.bar)
    local m = New(spec)
    previews[#previews + 1] = m
    Marker.Apply()
    return m
end

-- A DoT just landed on a preview's target.
function Marker.Landed(m)
    Landed(m)
end

ns.Dots.Listen(function(event)
    if not target then return end
    if event == "applied" then
        Landed(target)
    else
        -- Read again on the next frame; another target's DoTs grow in from nothing.
        if event == "target" and target.clip:IsShown() then Hide(target) end
        target.since = REFRESH_EVERY
    end
end)

-- For the tests: the target frame's marker (nil until built) and the previews'.
function Marker.State()
    return target, previews
end

-- For /sab dots.
function Marker.Debug()
    if not ns.Core.Get("dots") then return { "DoT marker: off (DoT Marker in the settings)" } end
    if stepAside then return { "DoT marker: off while DoesItDie is loaded" } end
    if not target then return { "DoT marker: the target frame's health bar was not found" } end
    return { string.format("DoT marker: on, %s, liquid %s%s, mask %s, kill icon %s%s",
        target.clip:IsShown() and "showing" or "hidden", target.themeKey or DEFAULT_THEME,
        target.under and " under the health liquid" or " over the game's fill", target.spec.mask and "yes" or "no",
        not target.hasIcon and "missing (no atlas)" or ns.Core.Get("dotKillIcon") and "on" or "off",
        target.err and (", error: " .. target.err) or "") }
end
