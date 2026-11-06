-- The liquid in the default player and target frames' health and power bars.
--
-- Forever keeps health and power secret from addons, in and out of combat: UnitHealth, UnitPower and
-- the bars' own GetValue all return secret values, which can be handed to the game's widgets but
-- never compared or used in arithmetic. So the liquid never knows how full a bar is. Instead:
--   * a hidden StatusBar of ours takes the game bar's (secret) value each update, with the client's
--     own smoothing, so its invisible fill eases to wherever the game's fill is;
--   * the liquid is drawn on a frame one bar-width wide whose right edge is anchored to that fill's
--     right edge. The liquid is always "full" on that frame, so its front sits on the fill's edge and
--     the client moves it there;
--   * the game's own bar mask (HealthBarMask / ManaBarMask) shapes the liquid to the bar, and a clip
--     frame that starts at the bar's left edge keeps the motes from showing left of the bar while
--     they fly off the front.
-- With no numbers the liquid cannot tell a gain from a loss, so any change to the bar stirs it.
--
-- The game's frames are only read and drawn on: our frames are children of the bars, the bar's own
-- fill texture is made transparent while the liquid shows, and its mask is added to our textures.
-- Nothing is hooked and no field is written onto a game frame.

local _, ns = ...

local min = math.min

local Bars = {}
ns.Bars = Bars

local IDLE_FPS = 30
local FEED_EVERY = 0.05  -- seconds between handing the game bar's value to our hidden bar
local STIR_EVERY = 0.4   -- at most one stir this often per bar
local STIR = 0.15        -- splash intensity of a stir
-- Room past the front, so the waves can bulge beyond the fill's edge instead of being clamped there
-- as at the end of a bar. Past the bar's end the mask cuts them off.
local ROOM = 10
local SPILL = 16         -- how far motes can fly above, below and past the end of a bar, px

local HEALTH_COLOR = { 0.10, 0.90, 0.10 }
-- PowerBarColor's values, for when the client has no PowerBarColor.
local POWER_COLORS = {
    MANA = { 0, 0, 1 }, RAGE = { 1, 0, 0 }, FOCUS = { 1, 0.5, 0.25 }, ENERGY = { 1, 1, 0 },
    RUNIC_POWER = { 0, 0.82, 1 },
}

local function Secret(...)
    if not issecretvalue then return false end
    for i = 1, select("#", ...) do
        if issecretvalue((select(i, ...))) then return true end
    end
    return false
end

-- A child of a game frame by its parentKey path, or nil.
local function Path(frame, ...)
    for i = 1, select("#", ...) do
        if type(frame) ~= "table" then return nil end
        frame = frame[(select(i, ...))]
    end
    return frame
end

-- UnitFrame_Initialize stores each unit frame's bars as .healthbar and .manabar; the paths are where
-- Forever's PlayerFrame.xml and TargetFrame.xml put them. key is the bar's on/off setting.
local SPOTS = {
    { key = "playerHealth", unit = "player", kind = "health", find = function()
        return Path(PlayerFrame, "healthbar") or (PlayerFrame_GetHealthBar and PlayerFrame_GetHealthBar())
            or Path(PlayerFrame, "PlayerFrameContent", "PlayerFrameContentMain", "HealthBarsContainer", "HealthBar")
    end },
    { key = "playerPower", unit = "player", kind = "power", find = function()
        return Path(PlayerFrame, "manabar") or (PlayerFrame_GetManaBar and PlayerFrame_GetManaBar())
            or Path(PlayerFrame, "PlayerFrameContent", "PlayerFrameContentMain", "ManaBarArea", "ManaBar")
    end },
    { key = "targetHealth", unit = "target", kind = "health", find = function()
        return Path(TargetFrame, "healthbar")
            or Path(TargetFrame, "TargetFrameContent", "TargetFrameContentMain", "HealthBarsContainer", "HealthBar")
    end },
    { key = "targetPower", unit = "target", kind = "power", find = function()
        return Path(TargetFrame, "manabar") or Path(TargetFrame, "TargetFrameContent", "TargetFrameContentMain", "ManaBar")
    end },
}

-- The mask that shapes a bar: on the bar (target health, both mana bars) or on the container
-- around it (player health).
local function BarMask(bar, kind)
    local key = kind == "health" and "HealthBarMask" or "ManaBarMask"
    local mask = Path(bar, key) or Path(bar:GetParent(), key)
    if type(mask) == "table" and mask.GetObjectType and mask:GetObjectType() == "MaskTexture" then return mask end
end

local bars = {} -- spot -> bar state, for the bars built so far
local driver

local INTERPOLATION = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut

--------------------------------------------------------------------------------
-- Colours
--------------------------------------------------------------------------------

-- The bar's own colour: health green, or the game's colour for the unit's power type.
local function GameColor(b)
    if b.kind == "health" then return HEALTH_COLOR, "HEALTH" end
    local index, token = UnitPowerType(b.unit)
    if Secret(index, token) then return POWER_COLORS.MANA, "MANA" end
    local c = PowerBarColor and (PowerBarColor[token] or PowerBarColor[index])
    if c and c.r then return { c.r, c.g, c.b }, token end
    return POWER_COLORS[token] or POWER_COLORS.MANA, token or "MANA"
end

-- A theme's movement scaled down for bars a dozen pixels high.
local function SmallPhysics(physics)
    local p = {}
    for k, v in pairs(physics or {}) do p[k] = v end
    p.amplitude = (p.amplitude or 10) * 0.3
    p.crest = (p.crest or 7) * 0.35
    p.ambient = (p.ambient or 1) * 0.5
    p.slosh = (p.slosh or 0.18) * 0.45
    return p
end

-- The theme for a bar's colour choice: "game" for the bar's own colour, or a theme key.
local function ThemeFor(b, choice)
    local Themes = ns.Themes
    local theme
    if choice == "game" or not Themes.list[choice] then
        theme = Themes.FromColor(GameColor(b), Themes.Get(Themes.default))
    else
        theme = Themes.Get(choice)
        if theme.Resolve then theme = theme:Resolve() end -- class and faction colours
    end
    return setmetatable({ physics = SmallPhysics(theme.physics) }, { __index = theme })
end

local function ApplyColor(b, force)
    local choice = ns.Core.Get(b.kind == "health" and "healthColor" or "powerColor")
    local _, token = GameColor(b)
    -- Power colours change with the power type only when the bar takes the game's colour.
    local key = choice == "game" and (choice .. ":" .. token) or choice
    if key == b.colorKey and not force then return end
    b.colorKey = key
    b.liquid:SetTheme(ThemeFor(b, choice))
end

--------------------------------------------------------------------------------
-- One bar
--------------------------------------------------------------------------------

-- Our hidden bar takes the game bar's range and value as they are, secret or not.
local function Feed(b, smooth)
    local bar, proxy = b.bar, b.proxy
    proxy:SetMinMaxValues(bar:GetMinMaxValues())
    if smooth and INTERPOLATION then
        proxy:SetValue(bar:GetValue(), INTERPOLATION)
    else
        proxy:SetValue(bar:GetValue())
    end
end

-- The game's fill shows while the liquid does not, and the other way round.
local function SetLive(b, live)
    if live == b.live then return end
    b.live = live
    b.clip:SetShown(live)
    local fill = b.bar:GetStatusBarTexture()
    if fill then fill:SetAlpha(live and 0 or 1) end
    if live then
        Feed(b, false)
        b.liquid:Snap(b.width) -- the liquid is always full on its frame
    else
        b.liquid:HideAll()
    end
end

-- At the bar's own frame level, so the game's text (a higher draw layer at that level) stays above.
local function AtParentLevel(frame, parent)
    if frame.SetUsingParentLevel then
        frame:SetUsingParentLevel(true)
    else
        frame:SetFrameLevel(parent:GetFrameLevel())
    end
end

local function NewBar(spot, bar)
    local w, h = bar:GetWidth(), bar:GetHeight()
    local b = { spot = spot, unit = spot.unit, kind = spot.kind, bar = bar, width = w, height = h, live = false,
                idle = 0, feed = 0, stirAt = 0 }

    -- The hidden bar: its fill is never drawn, only anchored to.
    local proxy = CreateFrame("StatusBar", nil, bar)
    proxy:SetAllPoints(bar)
    local track = proxy:CreateTexture(nil, "BACKGROUND")
    track:SetColorTexture(1, 1, 1, 1)
    proxy:SetStatusBarTexture(track)
    proxy:GetStatusBarTexture():SetAlpha(0)
    proxy:SetMinMaxValues(0, 1)
    proxy:SetValue(0)
    b.proxy = proxy

    local clip = CreateFrame("Frame", nil, bar)
    AtParentLevel(clip, bar)
    clip:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, SPILL)
    clip:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", SPILL, -SPILL)
    clip:SetClipsChildren(true)
    clip:Hide()
    b.clip = clip

    -- One bar-width wide, ending at the fill's edge.
    local mover = CreateFrame("Frame", nil, clip)
    AtParentLevel(mover, clip)
    local fill = proxy:GetStatusBarTexture()
    mover:SetPoint("TOPRIGHT", fill, "TOPRIGHT")
    mover:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT")
    mover:SetWidth(w)
    b.mover = mover

    b.liquid = ns.Liquid.New(mover, math.max(w, 1) + ROOM, math.max(h, 1), ns.Themes.Get(ns.Themes.default), ns.Core.db)
    -- The bar's mask cuts the liquid to the bar. Motes are left free to fly off the front.
    b.mask = BarMask(bar, spot.kind)
    if b.mask then
        local free = {}
        for _, m in ipairs(b.liquid.motes) do free[m.tex] = true end
        for _, t in ipairs(b.liquid.textures) do
            if not free[t] then t:AddMaskTexture(b.mask) end
        end
    end
    ApplyColor(b, true)
    return b
end

-- A change we cannot measure: ripple the front and throw a few motes off it.
local function Stir(b)
    local now = GetTime()
    if now < b.stirAt then return end
    b.stirAt = now + STIR_EVERY
    b.liquid:Splash(STIR, b.width - 8, b.width)
end

local function UpdateBar(b, dt)
    local bar = b.bar
    if not bar:IsVisible() then return end
    -- The game can swap or reset its fill texture; keep it hidden under the liquid.
    local fill = bar:GetStatusBarTexture()
    if fill and fill:GetAlpha() > 0 then fill:SetAlpha(0) end

    b.feed = b.feed + dt
    if b.feed >= FEED_EVERY then
        b.feed = 0
        Feed(b, true)
    end

    local w, h = bar:GetWidth(), bar:GetHeight()
    if w < 1 or h < 1 then return end
    if w ~= b.width or h ~= b.height then
        b.width, b.height = w, h
        b.mover:SetWidth(w)
        b.liquid:SetSize(w + ROOM, h)
    end

    -- Once settled only the idle wobble remains, so it drops to IDLE_FPS.
    if b.liquid:IsQuiet() then
        b.idle = b.idle + dt
        if b.idle < 1 / IDLE_FPS then return end
        dt, b.idle = b.idle, 0
    else
        b.idle = 0
    end
    b.liquid:Update(dt, w)
end

--------------------------------------------------------------------------------
-- Driver
--------------------------------------------------------------------------------

-- An error in one bar is kept for /sab debug and reported once, and that bar goes back to the
-- game's fill; the others carry on.
local function OnUpdate(_, elapsed)
    local dt = min(elapsed, 0.1)
    if dt <= 0 then return end
    for _, b in pairs(bars) do
        if b.live and not b.err then
            local ok, err = pcall(UpdateBar, b, dt)
            if not ok then
                b.err = tostring(err)
                pcall(SetLive, b, false)
                ns.Core.Print("Error in the " .. b.unit .. " " .. b.kind .. " bar, which is back to the game's own: "
                    .. b.err)
            end
        end
    end
end

local STIR_EVENTS = { UNIT_HEALTH = "health", UNIT_MAXHEALTH = "health", UNIT_POWER_UPDATE = "power",
                      UNIT_MAXPOWER = "power" }

local function OnEvent(_, event, unit)
    for _, b in pairs(bars) do
        if b.live then
            if event == "PLAYER_TARGET_CHANGED" then
                if b.unit == "target" then
                    ApplyColor(b)
                    Feed(b, false)
                end
            elseif b.unit == unit then
                if event == "UNIT_DISPLAYPOWER" then -- druid forms
                    if b.kind == "power" then ApplyColor(b) end
                elseif STIR_EVENTS[event] == b.kind then
                    Stir(b)
                end
            end
        end
    end
end

local EVENTS = { "PLAYER_TARGET_CHANGED", "UNIT_DISPLAYPOWER", "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE",
                 "UNIT_MAXPOWER" }

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

-- Show the liquid on the bars that are switched on, building each the first time it is wanted.
-- Returns how many bars are showing it and how many were wanted but not found.
function Bars.Apply()
    local live, missing = 0, 0
    for _, spot in ipairs(SPOTS) do
        local want = ns.Core.Get(spot.key) and true or false
        local b = bars[spot]
        if want and not b then
            local bar = spot.find()
            if type(bar) == "table" and bar.GetStatusBarTexture and bar.GetValue then
                b = NewBar(spot, bar)
                bars[spot] = b
            else
                missing = missing + 1
            end
        end
        if b then
            SetLive(b, want and not b.err)
            if b.live then live = live + 1 end
        end
    end
    if live > 0 and not driver then
        driver = CreateFrame("Frame")
        driver:SetScript("OnUpdate", OnUpdate)
        driver:SetScript("OnEvent", OnEvent)
    end
    if driver then
        driver:SetShown(live > 0)
        for _, event in ipairs(EVENTS) do
            if live > 0 then driver:RegisterEvent(event) else driver:UnregisterEvent(event) end
        end
    end
    return live, missing
end

-- After a colour choice changes, or once the player is known (class and faction themes).
function Bars.ApplyColors()
    for _, b in pairs(bars) do ApplyColor(b, true) end
end

-- After an effect toggle: clear what was just switched off.
function Bars.ApplyOptions()
    for _, b in pairs(bars) do b.liquid:ApplyOptions() end
end

local function YesNo(v) return v and "yes" or "no" end

-- Everything that decides whether a bar shows the liquid, for /sab debug.
function Bars.Debug()
    local out = { "smoothing: " .. YesNo(INTERPOLATION) }
    for _, spot in ipairs(SPOTS) do
        local b = bars[spot]
        local label = spot.unit .. " " .. spot.kind
        if not b then
            out[#out + 1] = label .. ": " .. (ns.Core.Get(spot.key) and "not found" or "off")
        else
            local bar = b.bar
            local fill = bar:GetStatusBarTexture()
            local shown = 0
            for _, t in ipairs(b.liquid.textures) do
                if t:IsShown() then shown = shown + 1 end
            end
            local name = bar.GetDebugName and bar:GetDebugName() or "?"
            out[#out + 1] = string.format("%s (%s, %dx%d): visible %s, value secret %s, mask %s, live %s, "
                .. "game fill alpha %s, liquid textures shown %d/%d%s",
                label, name, math.floor(b.width + 0.5), math.floor(b.height + 0.5), YesNo(bar:IsVisible()),
                YesNo(Secret(bar:GetValue())), YesNo(b.mask), YesNo(b.live),
                fill and tostring(fill:GetAlpha()) or "none", shown, #b.liquid.textures,
                b.err and (", error: " .. b.err) or "")
        end
    end
    return out
end
