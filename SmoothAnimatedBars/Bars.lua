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

-- Inflow (Bars.Inflow): while something is on the way into a bar, its particles drift back from the front into
-- the bar's liquid, and the front ripples where the two meet.
local INFLOW_RATE = 12         -- motes per second
local INFLOW_RIPPLE_EVERY = 0.5
local INFLOW_RIPPLE = 0.12
local INFLOW_MIX = 0.35        -- how far the front's tip, glow and colour turn toward the incoming liquid's

-- The build-up to a food's buff (Bars.Charge, Bars.Release), all in the bar's own liquid, so it shows at full
-- health too, when what is on the way lies past the bar's end.
local CHARGE_RATE = 24         -- motes per second more at the top of the build-up
local CHARGE_MIX = 0.4         -- how much further the bar turns toward the incoming colour
local CHARGE_ENERGY = 0.7
local RELEASE_STARS = 40
local FLASH_SECONDS = 1.2      -- the bar's flash of the incoming colour at the release fades over this
local SATED_RATE = 3           -- stars per second once the buff is reached, until the meal ends
local STAR = { texture = "Star", blend = "ADD", buoyancy = 30, drag = 1.6, spin = { -2, 2 } }

-- The wait before mana regenerates (ManaRule.lua): the liquid gathers energy, motes pulled into its front, which holds
-- still, turns pale and pulses faster while lightning starts up. It lets go in stars and a flash, less than a meal's
-- release, which stays the big one.
local BUILD_ENERGY = 1.2
local BUILD_RATE = 34               -- motes per second at the top of the build-up
local BUILD_GATHER = { texture = "Mote", blend = "ADD", mode = "attract", drag = 1.8 }
local BUILD_BEAT = { 0.7, 0.16 }    -- seconds between the pale front's pulses, from slowest to fastest
local BUILD_PULSE = 0.3             -- how much of its paleness each pulse takes away and gives back
local BUILD_STORM_FROM = 0.6        -- how far through the wait the lightning starts up
local BUILD_STORM = 1.4             -- its charge at the end of the wait
local BUILD_TINT = 0.55             -- how far the front turns pale at the top of the build-up
local BUILD_PALE = 0.5              -- how far that pale colour is from the liquid's tip toward white
local BUILD_STARS = 30
local BUILD_SPLASH = 0.85
local BUILD_FLASH_SECONDS = 0.9
local BUILD_STEADY_IN = 0.15        -- the front is holding still this far through the wait
local BUILD_STEADY_SECONDS = 2.5    -- and eases off over this after it

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

-- A region's width and height, or the fallbacks while the client keeps them secret: seen in game on the target's
-- health bar, whose size then cannot be compared.
local function Size(region, w0, h0)
    local w, h = region:GetWidth(), region:GetHeight()
    if Secret(w, h) then return w0, h0 end
    return w, h
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
    -- The small frames (frame: whose colour settings they take): the pet's (PetFrame.xml, named bars), the focus
    -- (the target's template) and the two targets of target (TargetFrameMixin:CreateTargetofTarget), which share
    -- their settings. They are optional: a client without one is not reported.
    { key = "petHealth", frame = "pet", optional = true, unit = "pet", kind = "health", find = function()
        return rawget(_G, "PetFrameHealthBar") or Path(rawget(_G, "PetFrame"), "healthbar")
    end },
    { key = "petPower", frame = "pet", optional = true, unit = "pet", kind = "power", find = function()
        return rawget(_G, "PetFrameManaBar") or Path(rawget(_G, "PetFrame"), "manabar")
    end },
    { key = "totHealth", frame = "tot", optional = true, unit = "targettarget", kind = "health", find = function()
        return Path(rawget(_G, "TargetFrameToT"), "HealthBar") or Path(TargetFrame, "totFrame", "HealthBar")
    end },
    { key = "totPower", frame = "tot", optional = true, unit = "targettarget", kind = "power", find = function()
        return Path(rawget(_G, "TargetFrameToT"), "ManaBar") or Path(TargetFrame, "totFrame", "ManaBar")
    end },
    { key = "focusHealth", frame = "focus", optional = true, unit = "focus", kind = "health", find = function()
        local f = rawget(_G, "FocusFrame")
        return Path(f, "healthbar")
            or Path(f, "TargetFrameContent", "TargetFrameContentMain", "HealthBarsContainer", "HealthBar")
    end },
    { key = "focusPower", frame = "focus", optional = true, unit = "focus", kind = "power", find = function()
        local f = rawget(_G, "FocusFrame")
        return Path(f, "manabar") or Path(f, "TargetFrameContent", "TargetFrameContentMain", "ManaBar")
    end },
    { key = "totHealth", frame = "tot", optional = true, unit = "focustarget", kind = "health", find = function()
        return Path(rawget(_G, "FocusFrameToT"), "HealthBar") or Path(rawget(_G, "FocusFrame"), "totFrame", "HealthBar")
    end },
    { key = "totPower", frame = "tot", optional = true, unit = "focustarget", kind = "power", find = function()
        return Path(rawget(_G, "FocusFrameToT"), "ManaBar") or Path(rawget(_G, "FocusFrame"), "totFrame", "ManaBar")
    end },
}

-- Whether a spot is switched on.
local function Wanted(spot)
    return ns.Core.Get(spot.key) and true or false
end

-- The mask that shapes a bar: on the bar (target health, both mana bars), on the container around it (player
-- health), or named after the bar (the pet's, PetFrameHealthBarMask).
local function BarMask(bar, kind)
    local key = kind == "health" and "HealthBarMask" or "ManaBarMask"
    local name = bar.GetName and bar:GetName()
    local mask = Path(bar, key) or Path(bar:GetParent(), key) or (name and rawget(_G, name .. "Mask"))
    if type(mask) == "table" and mask.GetObjectType and mask:GetObjectType() == "MaskTexture" then return mask end
end

local bars = {}     -- spot -> bar state, for the game's bars built so far
local previews = {} -- bar states on the setup wizard's preview frames
local driver

-- Every bar state, the game's and the previews'.
local function Each(fn)
    for _, b in pairs(bars) do fn(b) end
    for _, b in ipairs(previews) do fn(b) end
end

local INTERPOLATION = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut

--------------------------------------------------------------------------------
-- Colours
--------------------------------------------------------------------------------

-- The bar's own colour: health green, or the game's colour for the unit's power type (a preview
-- bar names its power type).
local function GameColor(b)
    if b.kind == "health" then return HEALTH_COLOR, "HEALTH" end
    local index, token
    if b.spot.token then
        token = b.spot.token
    else
        index, token = UnitPowerType(b.unit)
    end
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
        if theme.Resolve then -- class and faction colours
            theme = theme:Resolve(b and b.unit, b and b.spot.preview)
                or Themes.FromColor(GameColor(b), Themes.Get(Themes.default))
        end
    end
    return setmetatable({ physics = SmallPhysics(theme.physics) }, { __index = theme })
end

-- A bar's colour choice: its frame's, which can be to follow the player's (target, pet) or the target's (focus,
-- targets of target). A preview's bars are the player's or the target's.
local function ChoiceFor(b)
    return ns.Core.ColorChoice(b.spot.frame or (b.unit == "target" and "target" or "player"), b.kind)
end

local function ApplyColor(b, force)
    local choice = ChoiceFor(b)
    local _, token = GameColor(b)
    -- Power colours change with the power type only when the bar takes the game's colour, and Class Color with the
    -- unit's colour, falling back on the game's.
    local key = choice
    if choice == "game" then
        key = "game:" .. token
    elseif choice == "class" then
        local c = ns.Themes.UnitColor(b.unit, b.spot.preview)
        key = c and string.format("class:%.3f,%.3f,%.3f", c[1], c[2], c[3]) or ("class:none:" .. token)
    end
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

-- What the game draws in the bar that the liquid replaces: the fill, and on the player's health bar
-- the red bar of the health-loss animation. That one sits behind the game's fill, but once shown it
-- draws over the liquid at the same frame level, so it hides with the fill.
local function HideGameFill(bar, alpha)
    local fill = bar:GetStatusBarTexture()
    if fill and fill:GetAlpha() ~= alpha then fill:SetAlpha(alpha) end
    local loss = bar.AnimatedLossBar
    local lossFill = type(loss) == "table" and loss.GetStatusBarTexture and loss:GetStatusBarTexture()
    if lossFill and lossFill:GetAlpha() ~= alpha then lossFill:SetAlpha(alpha) end
end

-- The game's fill shows while the liquid does not, and the other way round.
local function SetLive(b, live)
    if live == b.live then return end
    b.live = live
    b.clip:SetShown(live)
    HideGameFill(b.bar, live and 0 or 1)
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
    local w, h = Size(bar, 1, 1)
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

-- The incoming liquid's burst style, slowed to drift: little lift, little drag, so the motes keep moving back.
local function InflowStyle(source)
    local burst = source.burst
    if source.inflowFor ~= burst then
        local style = {}
        for k, v in pairs(burst) do style[k] = v end
        style.buoyancy = (burst.buoyancy or 0) * 0.2
        style.drag = 0.4
        source.inflowFor, source.inflowStyle = burst, style
    end
    return source.inflowStyle
end

local function Rand(lo, hi)
    return lo + (hi - lo) * math.random()
end

local function Inflow(b, dt, w, h)
    local source = b.inflow
    if not source then return end
    local charge = b.charge or 0
    b.inflowAcc = (b.inflowAcc or 0) + dt * (INFLOW_RATE + CHARGE_RATE * charge)
    local theme = source.theme
    while b.inflowAcc >= 1 do
        b.inflowAcc = b.inflowAcc - 1
        b.liquid:EmitMote(w - math.random() * 3, 2 + math.random() * math.max(0, h - 4), -(25 + math.random() * 25),
            (math.random() - 0.5) * 8, 1.0 + math.random() * 0.7, 7 + math.random() * 4 + charge * 4,
            theme.splashFrom, theme.splashTo, InflowStyle(source))
    end
    b.rippleIn = (b.rippleIn or 0) - dt
    if b.rippleIn <= 0 then
        b.rippleIn = INFLOW_RIPPLE_EVERY * (1 - 0.6 * charge)
        b.liquid:Ripple(INFLOW_RIPPLE + 0.35 * charge)
    end
    if charge > 0 then
        b.liquid:Warm(CHARGE_ENERGY * charge)
        if math.random() < dt * 10 * charge then b.liquid:EmitBubble(Rand(4, math.max(4, w - 4))) end
    end
    -- Once the buff is reached, slow stars drift up along the bar until the meal ends.
    if b.sated then
        b.satedAcc = (b.satedAcc or 0) + dt * SATED_RATE
        while b.satedAcc >= 1 do
            b.satedAcc = b.satedAcc - 1
            b.liquid:EmitMote(Rand(0, w), Rand(2, math.max(2, h - 2)), Rand(-4, 4), Rand(6, 16), Rand(1.2, 2),
                Rand(7, 11), theme.tip, theme.splashTo, STAR)
        end
    end
    -- The front's colour follows: further with the build-up, furthest in the release's flash.
    b.flash = math.max(0, (b.flash or 0) - dt / FLASH_SECONDS)
    local mix = INFLOW_MIX + CHARGE_MIX * charge + (b.sated and CHARGE_MIX * 0.5 or 0)
    mix = math.min(1, mix + (1 - mix) * b.flash)
    if math.abs(mix - (b.inflowMix or INFLOW_MIX)) > 0.02 then
        b.inflowMix = mix
        b.liquid:SetInflow(b.inflowTheme, mix)
    end
end

-- Whether the bar is showing mana. A druid's forms put rage or energy on it.
local function OnMana(b)
    local _, token = UnitPowerType(b.unit)
    return Secret(token) or token == "MANA"
end

-- The pale colours the front turns toward as it builds up, a theme for Liquid:SetInflow, made from the liquid's own.
local function BuildTint(b)
    local theme = b.liquid.theme
    if b.tintFor ~= theme then
        local t, k = theme.tip, BUILD_PALE
        local pale = { t[1] + (1 - t[1]) * k, t[2] + (1 - t[2]) * k, t[3] + (1 - t[3]) * k }
        b.tintFor, b.tint = theme, { tip = pale, glow = pale, fillB = pale }
    end
    return b.tint
end

local function BuildUp(b, dt, w, h)
    if not b.waited then return end
    local progress = b.waitProgress
    -- What is pouring in takes the bar over, as does a power other than mana.
    if progress and (b.inflow or not OnMana(b)) then progress = nil end

    local steady = math.max(progress and min(1, progress / BUILD_STEADY_IN) or 0,
        (b.buildSteady or 0) - dt / BUILD_STEADY_SECONDS)
    if steady ~= (b.buildSteady or 0) then
        b.buildSteady = steady
        b.liquid:SetSteady(steady)
    end

    local mix = 0
    if progress then
        local charge = progress * progress
        local liquid = b.liquid
        -- The front pulses paler, faster toward the end.
        local beat = BUILD_BEAT[1] + (BUILD_BEAT[2] - BUILD_BEAT[1]) * charge
        b.buildPhase = ((b.buildPhase or 0) + dt / beat) % 1
        mix = BUILD_TINT * charge * (1 - BUILD_PULSE * (0.5 + 0.5 * math.cos(b.buildPhase * 2 * math.pi)))
        liquid:Warm(BUILD_ENERGY * charge)
        if progress > BUILD_STORM_FROM then
            liquid:Storm(BUILD_STORM * (progress - BUILD_STORM_FROM) / (1 - BUILD_STORM_FROM))
        end
        -- Motes from around the front, pulled into it from further off as it builds.
        local theme = liquid.theme
        b.buildAcc = (b.buildAcc or 0) + dt * BUILD_RATE * charge
        while b.buildAcc >= 1 do
            b.buildAcc = b.buildAcc - 1
            local a, d = Rand(0, 2 * math.pi), Rand(18, 26 + 24 * charge)
            liquid:EmitMote(w + math.cos(a) * d, h / 2 + math.sin(a) * d * 0.6, -math.sin(a) * 30, math.cos(a) * 30,
                Rand(0.8, 1.2), Rand(6, 10) + charge * 5, theme.splashFrom, theme.splashTo, BUILD_GATHER)
        end
    end

    -- The front's colour: pale as it builds up, then the release's flash fading. Whatever pours in has the tint.
    if b.inflow then
        b.buildMix, b.buildFlash = 0, 0
    else
        b.buildFlash = math.max(0, (b.buildFlash or 0) - dt / BUILD_FLASH_SECONDS)
        mix = math.max(mix, b.buildFlash)
        local was = b.buildMix or 0
        if math.abs(mix - was) > 0.02 or (mix == 0 and was > 0) then
            b.buildMix = mix
            b.liquid:SetInflow(mix > 0 and BuildTint(b) or nil, mix)
        end
    end
end

local function UpdateBar(b, dt)
    local bar = b.bar
    if not bar:IsVisible() then return end
    -- The game can swap or reset its fill textures; keep them hidden under the liquid.
    HideGameFill(bar, 0)

    b.feed = b.feed + dt
    if b.feed >= FEED_EVERY then
        b.feed = 0
        Feed(b, true)
    end

    local w, h = Size(bar, b.width, b.height)
    if w < 1 or h < 1 then return end
    if w ~= b.width or h ~= b.height then
        b.width, b.height = w, h
        b.mover:SetWidth(w)
        b.liquid:SetSize(w + ROOM, h)
    end

    Inflow(b, dt, w, h)
    BuildUp(b, dt, w, h)

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
    Each(function(b)
        if b.live and not b.err then
            local ok, err = pcall(UpdateBar, b, dt)
            if not ok then
                b.err = tostring(err)
                pcall(SetLive, b, false)
                ns.Core.Print("Error in the " .. (b.spot.preview and "preview " or "") .. b.unit .. " " .. b.kind
                    .. " bar, which is back to the game's own: " .. b.err)
            end
        end
    end)
end

local STIR_EVENTS = { UNIT_HEALTH = "health", UNIT_MAXHEALTH = "health", UNIT_POWER_UPDATE = "power",
                      UNIT_MAXPOWER = "power" }
-- Events that put another unit on a bar: its colour and value start afresh. No unit events come for a target of
-- target, so those bars follow their value without being stirred.
local NEW_UNIT = { PLAYER_TARGET_CHANGED = { target = true, targettarget = true },
                   PLAYER_FOCUS_CHANGED = { focus = true, focustarget = true } }
local TARGET_OF = { target = "targettarget", focus = "focustarget" }

local function OnEvent(_, event, unit)
    local fresh = NEW_UNIT[event]
    local other = event == "UNIT_TARGET" and TARGET_OF[unit] or (event == "UNIT_PET" and unit == "player" and "pet")
    for _, b in pairs(bars) do
        if b.live then
            if (fresh and fresh[b.unit]) or (other and b.unit == other) then
                ApplyColor(b)
                Feed(b, false)
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
                 "UNIT_MAXPOWER", "UNIT_TARGET", "UNIT_PET", "PLAYER_FOCUS_CHANGED" }

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

-- The player's or the target's bar for its on/off setting ("playerHealth"...), or nil if it is not there.
function Bars.Find(key)
    for _, spot in ipairs(SPOTS) do
        if spot.key == key then return spot.find() end
    end
end

-- Show the liquid on the bars that are switched on, building each the first time it is wanted.
-- Returns how many of the game's bars are showing it and how many were wanted but not found.
function Bars.Apply()
    local live, missing = 0, 0
    for _, spot in ipairs(SPOTS) do
        local want = Wanted(spot)
        local b = bars[spot]
        if want and not b then
            local bar = spot.find()
            if type(bar) == "table" and bar.GetStatusBarTexture and bar.GetValue then
                b = NewBar(spot, bar)
                bars[spot] = b
            elseif not spot.optional then
                missing = missing + 1
            end
        end
        if b then
            SetLive(b, want and not b.err)
            if b.live then live = live + 1 end
        end
    end
    -- Previews follow the same settings, so the wizard shows each choice on them.
    local any = live
    for _, b in ipairs(previews) do
        SetLive(b, ns.Core.Get(b.spot.key) and not b.err and true or false)
        if b.live then any = any + 1 end
    end
    if any > 0 and not driver then
        driver = CreateFrame("Frame")
        driver:SetScript("OnUpdate", OnUpdate)
        driver:SetScript("OnEvent", OnEvent)
    end
    if driver then
        driver:SetShown(any > 0)
        for _, event in ipairs(EVENTS) do
            if live > 0 then driver:RegisterEvent(event) else driver:UnregisterEvent(event) end
        end
    end
    return live, missing
end

-- The liquid on a bar of a preview frame. spec: { key = its on/off setting, unit, kind, token = power
-- type for a power bar }. Returns its state, for Bars.Stir.
function Bars.Preview(bar, spec)
    spec.preview = true
    local b = NewBar(spec, bar)
    previews[#previews + 1] = b
    Bars.Apply()
    return b
end

-- A preview bar's value changed.
function Bars.Stir(b)
    if b.live then Stir(b) end
end

-- The state of the liquid on a bar, the game's or a preview's, if it has one.
local function StateFor(bar)
    for _, b in pairs(bars) do
        if b.bar == bar then return b end
    end
    for _, b in ipairs(previews) do
        if b.bar == bar then return b end
    end
end

-- Whether a bar is showing the liquid (and not the game's own fill).
function Bars.IsLive(bar)
    local b = StateFor(bar)
    return b and b.live and not b.err or false
end

-- Where a bar's liquid ends: on the left edge of region (the DoT marker's span, Marker.lua), or with nil
-- back on the bar's own fill edge.
function Bars.Front(bar, region)
    local b = StateFor(bar)
    if not b or b.front == region then return end
    b.front = region
    local mover = b.mover
    mover:ClearAllPoints()
    if region then
        mover:SetPoint("TOPRIGHT", region, "TOPLEFT")
        mover:SetPoint("BOTTOMRIGHT", region, "BOTTOMLEFT")
    else
        local fill = b.proxy:GetStatusBarTexture()
        mover:SetPoint("TOPRIGHT", fill, "TOPRIGHT")
        mover:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT")
    end
    mover:SetWidth(b.width)
end

-- Something is on the way into a bar (HealMarker.lua): source is the incoming Liquid, whose particles then drift
-- back into the bar's liquid from its front, which ripples; nil stops it.
function Bars.Inflow(bar, source)
    local b = StateFor(bar)
    if not b then return end
    b.inflow = source
    local theme = source and source.theme or nil
    if theme ~= b.inflowTheme then
        b.inflowTheme = theme
        b.liquid:SetInflow(theme, b.inflowMix or INFLOW_MIX)
    end
    if not source then
        b.charge, b.sated, b.flash, b.inflowMix = nil, nil, nil, nil
    end
end

-- The build-up to a food's buff while something pours in: progress 0..1, or nil when there is none.
function Bars.Charge(bar, progress)
    local b = StateFor(bar)
    if b then b.charge = progress end
end

-- The buff is reached: the build-up lets go in stars along the whole bar, a splash and a flash of the incoming
-- colour, and slow stars keep rising until the meal ends.
function Bars.Release(bar)
    local b = StateFor(bar)
    if not b or not b.live or not b.inflow then return end
    b.charge, b.sated, b.flash = nil, true, 1
    local theme, w, h = b.inflow.theme, b.width, b.height
    for _ = 1, RELEASE_STARS do
        b.liquid:EmitMote(Rand(0, w), Rand(0, h), Rand(-30, 30), Rand(20, 70), Rand(0.9, 1.7), Rand(10, 18),
            theme.tip, theme.splashTo, STAR)
    end
    b.liquid:Splash(0.8, 0, w)
end

-- The wait before mana regenerates: progress 0..1, or nil when it is called off.
function Bars.Wait(bar, progress)
    local b = StateFor(bar)
    if not b then return end
    b.waitProgress = progress
    if progress then b.waited = true end
end

-- The wait ran its course: the build-up lets go.
function Bars.WaitOver(bar)
    local b = StateFor(bar)
    if not b then return end
    b.waitProgress = nil
    if not b.live or b.inflow or not OnMana(b) then return end
    local w, h, liquid = b.width, b.height, b.liquid
    local theme = liquid.theme
    b.buildFlash, b.buildPhase, b.buildAcc = 1, 0, 0
    -- Stars thrown out from the front in every direction, faster than a meal's, which rise along the bar.
    for _ = 1, BUILD_STARS do
        local a, speed = Rand(0, 2 * math.pi), Rand(30, 130)
        liquid:EmitMote(w - Rand(0, 10), Rand(0, h), math.cos(a) * speed, math.sin(a) * speed * 0.7 + 15,
            Rand(0.7, 1.3), Rand(9, 16), theme.tip, theme.splashTo, STAR)
    end
    liquid:Splash(BUILD_SPLASH, w - 8, w)
    liquid:Warm(BUILD_ENERGY)
end

-- A region's width and height, or the fallbacks while the client keeps them secret (for the markers).
Bars.Size = Size

-- The Liquid on a bar, if it has one (the heal marker's seam follows its front; also for the tests).
function Bars.Liquid(bar)
    local b = StateFor(bar)
    return b and b.liquid
end

-- Stir a bar's liquid, as a change to its value does.
function Bars.StirBar(bar)
    local b = StateFor(bar)
    if b and b.live then Stir(b) end
end

-- A theme by key, with its movement scaled down for the unit frames' small bars.
function Bars.Theme(key)
    return ThemeFor(nil, key)
end

-- After a colour choice changes, or once the player is known (class and faction themes).
function Bars.ApplyColors()
    Each(function(b) ApplyColor(b, true) end)
end

-- After an effect toggle: clear what was just switched off.
function Bars.ApplyOptions()
    Each(function(b) b.liquid:ApplyOptions() end)
end

local function YesNo(v) return v and "yes" or "no" end

-- Everything that decides whether a bar shows the liquid, for /sab debug.
function Bars.Debug()
    local out = { "smoothing: " .. YesNo(INTERPOLATION) }
    for _, spot in ipairs(SPOTS) do
        local b = bars[spot]
        local label = spot.unit .. " " .. spot.kind
        if not b then
            out[#out + 1] = label .. ": " .. (Wanted(spot) and "not found" or "off")
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
