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

-- Enemy nameplates (the plateHealth setting). There can be a crowd of them, so they idle slower, and past MAX_PLATES
-- the rest keep the game's own fill until a plate with the liquid goes.
local MAX_PLATES = 15
local MAX_FRIENDLY = 10           -- friendly plates apart, so a city full of players cannot take the enemies' slots
local PLATE_IDLE_FPS = 20
local PLATE_W, PLATE_H = 110, 10  -- a plate's bar, until the client says (its size can be secret)
local PLATE_COLOR_EVERY = 0.5     -- seconds between looks at a plate's own colour (it greys once tapped)
local PLATE_WAIT = 1              -- how long a new plate may take to get its unit frame, seconds

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
-- Nameplates: the game keeps a pool of plate unit frames and hands them from mob to mob, so a liquid is built once
-- per plate health bar and follows whichever unit the bar shows.
local plates = {}   -- plate health bar -> bar state
local plateOf = {}  -- nameplate token -> bar state, while the liquid is on it
local pending = {}  -- nameplate token -> time it was added, while waiting for its unit frame or a free slot
local driver

-- Every bar state, the game's, the previews' and the nameplates'.
local function Each(fn)
    for _, b in pairs(bars) do fn(b) end
    for _, b in ipairs(previews) do fn(b) end
    for _, b in pairs(plates) do fn(b) end
end

local INTERPOLATION = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut

--------------------------------------------------------------------------------
-- Colours
--------------------------------------------------------------------------------

-- A nameplate's own colour: the one the game gave its bar (red, yellow, grey once tapped), else the unit's reaction.
local function PlateColor(b)
    local bar = b.bar
    if bar.GetStatusBarColor then
        local ok, r, g, bl = pcall(bar.GetStatusBarColor, bar)
        if ok and type(r) == "number" and not Secret(r, g, bl) then return { r, g, bl } end
    end
    return ns.Themes.ReactionColor(b.unit) or { 0.90, 0.15, 0.10 }
end

-- The bar's own colour: health green (a nameplate's its own), or the game's colour for the unit's power type (a
-- preview bar names its power type).
local function GameColor(b)
    if b.spot.plate then return PlateColor(b), "HEALTH" end
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
    local own, token = GameColor(b)
    -- Power colours change with the power type only when the bar takes the game's colour, and Class Color with the
    -- unit's colour, falling back on the game's. A nameplate's own colour changes with the unit (tapped, hostile).
    local key = choice
    if b.spot.plate then token = string.format("%.3f,%.3f,%.3f", own[1], own[2], own[3]) end
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
    local w, h = Size(bar, spot.plate and PLATE_W or 1, spot.plate and PLATE_H or 1)
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
    -- A nameplate's bar has no mask, so the clip frame is the bar itself: it cuts the waves at the bar's end, and the
    -- motes too, which would only clutter a crowd of plates.
    local spill = spot.plate and 0 or SPILL
    clip:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, spill)
    clip:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", spill, -spill)
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

    local idleFps = IDLE_FPS
    if b.spot.plate then
        idleFps = PLATE_IDLE_FPS
        b.colorIn = (b.colorIn or 0) - dt
        if b.colorIn <= 0 then
            b.colorIn = PLATE_COLOR_EVERY
            ApplyColor(b)
        end
    else
        Inflow(b, dt, w, h)
        BuildUp(b, dt, w, h)
    end

    -- Once settled only the idle wobble remains, so it drops to the idle rate.
    if b.liquid:IsQuiet() then
        b.idle = b.idle + dt
        if b.idle < 1 / idleFps then return end
        dt, b.idle = b.idle, 0
    else
        b.idle = 0
    end
    b.liquid:Update(dt, w)
end

--------------------------------------------------------------------------------
-- Driver
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Nameplates
--------------------------------------------------------------------------------

-- Enemy plates (plateHealth) and friendly ones (plateFriendly), each switched on by itself.
local function PlatesWanted()
    return (ns.Core.Get("plateHealth") or ns.Core.Get("plateFriendly")) and true or false
end

local function Count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

-- The health bar of a nameplate token's plate, once the game has given the plate its unit frame for that token; nil
-- for none yet, and always for a forbidden plate (friendly plates in instances), which addons cannot get at.
local function PlateBar(token)
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return nil end
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, token)
    if not ok or type(plate) ~= "table" then return nil end
    local unitFrame = plate.UnitFrame
    if type(unitFrame) ~= "table" or plate.unitToken ~= token then return nil end
    local bar = Path(unitFrame, "HealthBarsContainer", "healthBar") or Path(unitFrame, "healthBar")
    if type(bar) == "table" and bar.GetStatusBarTexture and bar.GetValue then return bar end
end

-- Whether the player can attack the unit: true, false, or nil when the client will not say.
local function IsEnemy(token)
    local ok, can = pcall(UnitCanAttack, "player", token)
    if not ok or Secret(can) then return nil end
    return can == true
end

-- Which liquid a plate gets: "enemy", "friend", or nil for none (that side switched off, the player's own plate, or
-- a unit the client will not say about).
local function Side(token)
    local ok, me = pcall(UnitIsUnit, token, "player")
    if ok and not Secret(me) and me then return nil end
    local enemy = IsEnemy(token)
    if enemy == nil then return nil end
    if enemy then return ns.Core.Get("plateHealth") and "enemy" or nil end
    return ns.Core.Get("plateFriendly") and "friend" or nil
end

-- How many plates of a side have the liquid, and how many may.
local function CountSide(side)
    local n = 0
    for _, b in pairs(plateOf) do
        if b.side == side then n = n + 1 end
    end
    return n
end
local function Cap(side)
    return side == "enemy" and MAX_PLATES or MAX_FRIENDLY
end

local function DetachPlate(token)
    pending[token] = nil
    local b = plateOf[token]
    if not b then return end
    plateOf[token] = nil
    SetLive(b, false)
    b.token = nil
    -- A DoT marker may have moved the front back; the next mob on this bar starts at its own health.
    if b.front then
        b.front = nil
        local fill = b.proxy:GetStatusBarTexture()
        b.mover:ClearAllPoints()
        b.mover:SetPoint("TOPRIGHT", fill, "TOPRIGHT")
        b.mover:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT")
    end
end

-- Put the liquid on a plate. True when done or not wanted (a side switched off, the player's own plate), false to try
-- again later.
local function AttachPlate(token)
    local side = Side(token)
    if not side then return true end
    local bar = PlateBar(token)
    if not bar then return false end
    local b = plates[bar]
    -- The bar may still be on the books for a token whose removal came after its next use.
    if b and b.token and b.token ~= token and plateOf[b.token] == b then plateOf[b.token] = nil end
    if not plateOf[token] and CountSide(side) >= Cap(side) then return false end
    if not b then
        b = NewBar({ key = "plateHealth", frame = "plate", unit = token, kind = "health", plate = true }, bar)
        plates[bar] = b
    end
    b.token, b.unit, b.spot.unit, b.side = token, token, token, side
    b.spot.frame = side == "friend" and "friend" or "plate" -- whose colour setting it takes
    b.err, b.colorIn = nil, PLATE_COLOR_EVERY
    plateOf[token] = b
    ApplyColor(b, true)
    if b.live then Feed(b, false); b.liquid:Snap(b.width) else SetLive(b, true) end
    return true
end

-- New plates wait here for their unit frame (the game may set it up after our event) or for a free slot.
local function TryPending()
    local now = GetTime()
    for token, at in pairs(pending) do
        if AttachPlate(token) then
            pending[token] = nil
        elseif now - at > PLATE_WAIT and not PlateBar(token) then
            pending[token] = nil -- no unit frame came: a forbidden plate, or gone again
        end
    end
end

-- Every plate showing now, for turning the setting on mid-session.
local function ScanPlates()
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
    local ok, list = pcall(C_NamePlate.GetNamePlates)
    if not ok or type(list) ~= "table" then return end
    local now = GetTime()
    for _, plate in pairs(list) do
        local token = type(plate) == "table" and plate.unitToken
        if type(token) == "string" and not plateOf[token] then pending[token] = now end
    end
end

local function ApplyPlates()
    if PlatesWanted() then
        -- A side just switched off lets its plates go.
        for token, b in pairs(plateOf) do
            if Side(token) ~= b.side then DetachPlate(token) end
        end
        ScanPlates()
        TryPending()
    else
        for token in pairs(plateOf) do DetachPlate(token) end
        wipe(pending)
    end
end

--------------------------------------------------------------------------------
-- Timing (/sab perf)
--------------------------------------------------------------------------------

-- What the liquid costs: the time our updates take each frame, kept in one-second buckets over the last PERF_SECONDS,
-- for the unit frames (with the previews) and the nameplates apart. debugprofilestop is the client's millisecond
-- timer. Only this file's updates are timed; the DoT and heal markers run their own.
local PERF_SECONDS = 10
local perf = { done = {} }

local function PerfAdd(unitMs, plateMs, units, platesLive)
    local second = math.floor(GetTime())
    local cur = perf.cur
    if not cur or cur.second ~= second then
        if cur then
            table.insert(perf.done, 1, cur)
            perf.done[PERF_SECONDS + 1] = nil
        end
        cur = { second = second, frames = 0, unitMs = 0, plateMs = 0, peak = 0, units = 0, plates = 0 }
        perf.cur = cur
    end
    cur.frames = cur.frames + 1
    cur.unitMs, cur.plateMs = cur.unitMs + unitMs, cur.plateMs + plateMs
    cur.peak = math.max(cur.peak, unitMs + plateMs)
    cur.units, cur.plates = math.max(cur.units, units), math.max(cur.plates, platesLive)
end

local function RunBar(b, dt)
    if not b.live or b.err then return false end
    local ok, err = pcall(UpdateBar, b, dt)
    if not ok then
        b.err = tostring(err)
        pcall(SetLive, b, false)
        ns.Core.Print("Error in the " .. (b.spot.preview and "preview " or "") .. (b.spot.plate and "nameplate " or "")
            .. b.unit .. " " .. b.kind .. " bar, which is back to the game's own: " .. b.err)
        if b.token then plateOf[b.token] = nil end
    end
    -- Counted for /sab perf only while it shows: a hidden frame's bar (no focus, no pet) costs next to nothing.
    return ok and b.bar:IsVisible() and true or false
end

-- An error in one bar is kept for /sab debug and reported once, and that bar goes back to the
-- game's fill; the others carry on.
local function OnUpdate(_, elapsed)
    local dt = min(elapsed, 0.1)
    if dt <= 0 then return end
    local clock = debugprofilestop
    local t0 = clock and clock()
    local units, live = 0, 0
    for _, b in pairs(bars) do if RunBar(b, dt) then units = units + 1 end end
    for _, b in ipairs(previews) do if RunBar(b, dt) then units = units + 1 end end
    local t1 = clock and clock()
    if next(pending) then TryPending() end
    for _, b in pairs(plates) do if RunBar(b, dt) then live = live + 1 end end
    if clock then PerfAdd(t1 - t0, clock() - t1, units, live) end
end

local STIR_EVENTS = { UNIT_HEALTH = "health", UNIT_MAXHEALTH = "health", UNIT_POWER_UPDATE = "power",
                      UNIT_MAXPOWER = "power" }
-- Events that put another unit on a bar: its colour and value start afresh. No unit events come for a target of
-- target, so those bars follow their value without being stirred.
local NEW_UNIT = { PLAYER_TARGET_CHANGED = { target = true, targettarget = true },
                   PLAYER_FOCUS_CHANGED = { focus = true, focustarget = true } }
local TARGET_OF = { target = "targettarget", focus = "focustarget" }

local function OnPlateEvent(event, unit)
    if event == "NAME_PLATE_UNIT_ADDED" then
        if PlatesWanted() then
            pending[unit] = GetTime()
            TryPending()
        end
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        DetachPlate(unit)
        if next(pending) then TryPending() end -- a slot may be free now
    elseif event == "UNIT_FACTION" then -- a mob turning hostile or friendly
        if PlatesWanted() then
            DetachPlate(unit)
            pending[unit] = GetTime()
            TryPending()
        end
    end
end

local function OnEvent(_, event, unit)
    if type(unit) == "string" and unit:match("^nameplate%d+$") then
        local pb = plateOf[unit]
        if pb and pb.live and STIR_EVENTS[event] == "health" then Stir(pb) end
        OnPlateEvent(event, unit)
        -- The same unit can be the target or focus as well, which the frames' own events cover.
        return
    end
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
local PLATE_EVENTS = { "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UNIT_FACTION" }
local BOTH = { UNIT_HEALTH = true, UNIT_MAXHEALTH = true } -- the frames' events that the plates use too

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
    local platesOn = PlatesWanted()
    if (any > 0 or platesOn) and not driver then
        driver = CreateFrame("Frame")
        driver:SetScript("OnUpdate", OnUpdate)
        driver:SetScript("OnEvent", OnEvent)
    end
    if driver then
        driver:SetShown(any > 0 or platesOn)
        for _, event in ipairs(EVENTS) do
            if live > 0 or (platesOn and BOTH[event]) then driver:RegisterEvent(event) else driver:UnregisterEvent(event) end
        end
        for _, event in ipairs(PLATE_EVENTS) do
            if platesOn then driver:RegisterEvent(event) else driver:UnregisterEvent(event) end
        end
        ApplyPlates()
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
    return plates[bar]
end

-- The enemy nameplates showing the liquid: token -> their health bar (for the DoT marker on them, Marker.lua).
function Bars.Plates()
    local out = {}
    for token, b in pairs(plateOf) do
        if b.live and not b.err and b.side == "enemy" then out[token] = b.bar end
    end
    return out
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
    out[#out + 1] = string.format("enemy nameplates: %s, %d with the liquid (at most %d); friendly: %s, %d (at most %d); "
        .. "%d built, %d waiting", ns.Core.Get("plateHealth") and "on" or "off", CountSide("enemy"), MAX_PLATES,
        ns.Core.Get("plateFriendly") and "on" or "off", CountSide("friend"), MAX_FRIENDLY, Count(plates), Count(pending))
    return out
end

local function Memory()
    local update = rawget(_G, "UpdateAddOnMemoryUsage") or (C_AddOns and C_AddOns.UpdateAddOnMemoryUsage)
    local get = rawget(_G, "GetAddOnMemoryUsage") or (C_AddOns and C_AddOns.GetAddOnMemoryUsage)
    if not (update and get) then return nil end
    local ok = pcall(update)
    local ok2, kb = pcall(get, "SmoothAnimatedBars")
    if ok and ok2 and type(kb) == "number" then return kb end
end

-- What the liquid has cost over the last few seconds, for /sab perf.
function Bars.Perf()
    local out = {}
    if not debugprofilestop then return { "The client has no timer (debugprofilestop) to measure with." } end
    local frames, unitMs, plateMs, peak, units, platesLive = 0, 0, 0, 0, 0, 0
    for _, s in ipairs(perf.done) do
        frames, unitMs, plateMs = frames + s.frames, unitMs + s.unitMs, plateMs + s.plateMs
        peak, units, platesLive = math.max(peak, s.peak), math.max(units, s.units), math.max(platesLive, s.plates)
    end
    if frames == 0 then return { "Nothing measured yet: give it a few seconds with the liquid showing." } end
    local fps = GetFramerate and GetFramerate() or 0
    local budget = fps > 0 and 1000 / fps or nil
    local function Line(label, ms, n)
        local avg = ms / frames
        return string.format("%s: %d liquid%s, %.3f ms a frame%s", label, n, n == 1 and "" or "s", avg,
            budget and string.format(" (%.1f%% of the frame at %d fps)", 100 * avg / budget, fps + 0.5) or "")
    end
    out[#out + 1] = string.format("Over the last %d s (%d frames):", #perf.done, frames)
    out[#out + 1] = Line("unit frames", unitMs, units)
    out[#out + 1] = Line("nameplates", plateMs, platesLive)
    if platesLive > 0 then
        out[#out + 1] = string.format("  that is %.3f ms a frame per nameplate", plateMs / frames / platesLive)
    end
    out[#out + 1] = string.format("slowest frame: %.2f ms", peak)
    local textures = 0
    Each(function(b) if b.live then textures = textures + #b.liquid.textures end end)
    out[#out + 1] = string.format("textures in live liquids: %d", textures)
    local kb = Memory()
    if kb then out[#out + 1] = string.format("addon memory: %.0f KB", kb) end
    out[#out + 1] = "Only the liquid's updates are timed, not the client drawing it: compare fps with the setting on and off."
    return out
end

-- The same as Bars.Perf's lines, plus each second measured (newest first), for the saved log (/sab perf). nil when
-- nothing has been measured.
function Bars.PerfSnapshot()
    if not debugprofilestop or #perf.done == 0 then return nil end
    local seconds = {}
    for i, s in ipairs(perf.done) do
        seconds[i] = { frames = s.frames, unitMs = s.unitMs, plateMs = s.plateMs, peak = s.peak, units = s.units,
                       plates = s.plates }
    end
    local textures = 0
    Each(function(b) if b.live then textures = textures + #b.liquid.textures end end)
    return { seconds = seconds, textures = textures, fps = GetFramerate and GetFramerate() or nil, memoryKB = Memory(),
             platesOn = PlatesWanted(), maxPlates = MAX_PLATES, plateIdleFps = PLATE_IDLE_FPS }
end

-- Forget what was measured, so the next /sab perf covers only what comes after.
function Bars.PerfReset()
    perf.cur, perf.done = nil, {}
end
