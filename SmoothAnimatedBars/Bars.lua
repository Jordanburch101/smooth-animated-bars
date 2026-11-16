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
local PRD_W, PRD_H = 200, 10      -- the Personal Resource Display's bars, the same way (its width at 100%)
local PLATE_COLOR_EVERY = 0.5     -- seconds between looks at a plate's own colour (it greys once tapped)
local PLATE_MASK = "Interface\\AddOns\\SmoothAnimatedBars\\Media\\PlateMask"
-- The game's fill darkens toward its top and bottom edges; this darkens every plate liquid under it the same way.
local PLATE_SHADE_TEX = "Interface\\AddOns\\SmoothAnimatedBars\\Media\\PlateShade"
local TINT_PAST = 4               -- px the tint of a secret plate colour reaches past the health's edge (PlateColor)
local PLATE_WAIT = 1              -- how long a new plate may take to get its unit frame, seconds

-- The party frames' liquids: eight small bars (70x10 and 74x7) whose members' health and power change all through a
-- fight, so they were stirred every STIR_EVERY and never settled, each updating every frame. In a party in combat the
-- unit frames' liquids took 4.3 ms a frame (15% of it at 36 fps, /sab perf in game), and in the mock the party's eight
-- made more widget calls than the player's, target's and display's together. So they update at most PARTY_FPS times a
-- second, busy or not, as small as the plates' bars, and stir at most every PARTY_STIR_EVERY. (Their fronts, like every
-- short bar's, have fewer slices: Liquid.RowsFor.)
local PARTY_FPS = 20
local PARTY_STIR_EVERY = 1.2

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

-- Rage (the rageFury setting): as rage fills its bar the liquid turns furious, hotter, churning, crackling and spitting
-- sparks, its front trembling; full, it throbs, ready to burst, and spending rage lets it go. Rage is secret like the
-- rest, so the addon never knows how full the bar is. The fury is a second liquid over the bar's whose front is the bar
-- liquid's (Liquid:Follow), on a frame whose alpha the client sets from the rage itself: UnitPowerPercent evaluates a
-- curve on the unit's share of its power, and SetAlpha takes the secret it gives. The fury runs whenever a bar shows
-- rage, and shows only as far as the curve lets it.
local FURY_CURVE = { { 0, 0 }, { 0.5, 0 }, { 0.75, 0.3 }, { 0.95, 1 } } -- rage share -> how much of the fury shows
local READY_CURVE = { { 0, 0 }, { 0.97, 0 }, { 0.99, 1 } }               -- and of the full bar's throb
local FURY_EVERY = 0.05     -- seconds between asking the client for those
-- The fury's update rate, unless it is bursting. It was 30, but the fury is a second liquid on the bar and runs even
-- where its curve has faded it out (below half rage), which the addon cannot know: counted in the mock it was about
-- half of a rage bar's widget calls, nearly 40% of all in combat. Its churning flames read the same at 20.
local FURY_FPS = 20
local FURY_ENERGY = 0.5
local FURY_STORM = 1.2
local FURY_TREMBLE = 0.7    -- px of quick tremble on the fury's front
local FURY_SPARKS = 14      -- sparks a second off the top of the liquid
local READY_BEAT = 0.8      -- seconds between the full bar's throbs
local READY_SPARKS = 14     -- sparks spat from the front with each throb
local RELEASE_HOLD = 0.35   -- seconds the burst shows at the rage there was, before it fades
local RELEASE_FADE = 0.45
local RELEASE_BACK = 0.3    -- the fury fading back in at the rage that is left
local RELEASE_LAG = 0.3     -- how long ago the rage is read for the burst, s: it may be spent before the cast's event
local RELEASE_SPARKS = 40
local SPEND_SPARKS = 22     -- sparks off the bar's own liquid at every rage spend, whatever the rage
local SPEND_SPLASH = 0.35
local FURY_HOT = { 1.00, 0.42, 0.08 }   -- what the fury heats toward
local FURY_TIP = { 1.00, 0.95, 0.80 }   -- its white-hot front
local FURY_EMBER = { 0.85, 0.12, 0.00 }
local FURY_SPARK = { area = "surface", rate = FURY_SPARKS, texture = "Spark", blend = "ADD", orient = true, wander = 120,
                     size = { 9, 14 }, life = { 0.5, 1.0 }, vx = { -12, 12 }, vy = { 35, 75 }, buoyancy = 25, drag = 0.9,
                     twinkle = 9, from = FURY_TIP, to = FURY_EMBER }
local SPARK = { texture = "Spark", blend = "ADD", orient = true, wander = 90, buoyancy = 40, drag = 1.1 }

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

-- The texts inside a flat bar, which its raised liquid would cover (PlateTexts): a nameplate's (TextStatusBar) and the
-- Personal Resource Display's (PersonalResourceStatusBar, whose main text is TextString). The target frame's health bar
-- has the same keys (SetBarText puts its container's HealthBarText, LeftText and RightText on the bar), copied while its
-- liquid is raised over a DoT marker (Bars.SetOver).
local PLATE_TEXTS = { "Text", "LeftText", "RightText" }
local PRD_TEXTS = { "TextString", "LeftText", "RightText" }

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
    { key = "targetHealth", unit = "target", kind = "health", texts = PRD_TEXTS, find = function()
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
    -- The Personal Resource Display (Blizzard_PersonalResourceDisplay, forever branch): the player's bars in a frame of
    -- their own, shown when the game's Personal Resource Display option is on (the frame is there either way). Its bars
    -- are drawn with the nameplates' art (PersonalResourceStatusBar: UI-HUD-CoolDownManager-Bar on its bronze
    -- background) and have no mask, so they take the plates' look (flat: the plate mask and shading, a level above the
    -- bar, with copies of the bar's texts). The third is the mana a druid's forms take off the power bar
    -- (AlternatePowerBar, DruidAlternatePowerBarMixin); token says what it shows.
    { key = "prdHealth", frame = "prd", optional = true, flat = true, texts = PRD_TEXTS, unit = "player", kind = "health",
      label = "personal resource display health", find = function()
        return Path(rawget(_G, "PersonalResourceDisplayFrame"), "HealthBarsContainer", "healthBar")
    end },
    { key = "prdPower", frame = "prd", optional = true, flat = true, texts = PRD_TEXTS, unit = "player", kind = "power",
      label = "personal resource display power", find = function()
        return Path(rawget(_G, "PersonalResourceDisplayFrame"), "PowerBar")
    end },
    { key = "prdPower", frame = "prd", optional = true, flat = true, texts = PRD_TEXTS, unit = "player", kind = "power",
      token = "MANA", label = "personal resource display mana", find = function()
        -- Every class has the bar, but on Forever only a druid's is ever shown (SetupAlternatePowerBar; the priest's
        -- needs the Shadow spec, which Forever does not have), so no one else builds a liquid for it.
        local ok, _, class = pcall(UnitClass, "player")
        if not ok or Secret(class) or class ~= "DRUID" then return nil end
        return Path(rawget(_G, "PersonalResourceDisplayFrame"), "AlternatePowerBar")
    end },
}

-- The party frames (Blizzard_UnitFrame/Shared/PartyFrame.lua): a pool of four member buttons, named MemberFrame1..4 by
-- their place each time the party frame is shown, each with its health bar in a container that holds its mask (as the
-- player's) and its mana bar with the mask on it. The pool keeps the same four buttons but can put them in other places,
-- so each bar gets a spot of its own the first time it is found (AddPartySpots), and its liquid follows the unit the game
-- puts on the bar (bar.unit: party1..4, the pet's token in a vehicle, the player in Edit Mode's preview). Seen in game
-- with /sab party: health and power secret as the player's, the masks there, the class readable, in a dungeon in
-- combat too.
local PARTY_KINDS = { health = "partyHealth", power = "partyPower" }

local function PartyBar(i, kind)
    local f = Path(rawget(_G, "PartyFrame"), "MemberFrame" .. i)
    if kind == "health" then return Path(f, "HealthBarContainer", "HealthBar") end
    return Path(f, "ManaBar")
end

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
local partyEvents = {} -- event -> how many came for a party unit (party1..4, partypet1..4), for /sab party
local partyWaiting = false -- party bars wanted whose frames were not there: looked for again (LookForParty)
local partyBuilt = {}      -- party bar -> true, once it has its liquid
local LookForParty         -- below
local driver
-- Other addons' bars handed to us with SmoothAnimatedBars.AddBar: their bar -> its spot (bars[spot] is its state). A
-- removed bar keeps its spot and frames, hidden, for when it is added again.
local externals = {}
-- Their functions (below), in one table as the file is near Lua's limit of 200 locals. LOOK_EVERY: how often their
-- colour, fill direction and level are looked at; their colour can follow the health on a gradient, so more often than a
-- plate's. unitEvents: whether the unit events are registered (Bars.Apply), which a bar needs to be stirred.
local External = { LOOK_EVERY = 0.1, KINDS = { health = true, power = true }, unitEvents = false,
                   -- The most party and raid members' bars other addons can hand over (a party's health and power is 8):
                   -- each is a liquid of its own, and a raid frame's forty members would cost more than the game's
                   -- whole frame. The highest level above the bar an addon can ask for.
                   MAX_GROUP = 10, MAX_LEVEL = 20 }

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
-- The game tints its plate fill (UI-HUD-CoolDownManager-Bar, a grey ramp) with the plate's colour, so what shows is
-- that colour darkened: an enemy plate measured (165, 6, 3) in the middle of the bar in game. Taken at full strength
-- the liquid was a much brighter, pinkish red, so it takes the colour at the fill's brightness, in a theme with no
-- white in its fill (Themes.FromColor, deep): with the unit frames' white it showed (145, 45, 42) against the game's
-- (144, 0, 0) on the same plate. At 0.6 with the deep theme it measured (119, 37, 36) in game, its red too dark, so
-- 0.72 (the red scales with it), which measured (178, 55, 50): bright enough, but greyed. The fallback colour was
-- the unit frames' softer reaction red, (0.9, 0.15, 0.1), and is now the game's pure plate colours, with less white
-- still in the highlights, so 0.55. That measured (145, 52, 48): the red right, still grey. The bar's colour turned
-- out readable (1, 0, 0) in game, and with the effects off the liquid was pure red, (59 to 78, 0, 0): the grey came
-- from lightning and particles, drawn toward white whatever the theme. The deep theme now keeps them to its colour,
-- and with their white went some of the red: at 0.65 it measured pure, (86, 6, 6) near the bar's left end against the
-- game's (138, 0, 0), where the deep theme's fill was then at 60% of the colour. Its fill is now nearly flat, as the
-- game's is. But those plates had never had the deep theme: they followed a target on Class Color whose mobs show
-- Game Colour, and that fell back on the unit frames' theme (ThemeFor, PlateReaction). That theme at 0.68, effects
-- off, measured 90 at the bar's left end and 176 at its front for a fill of 0.29 and 0.73, about 255 on screen to
-- the unit, so the deep theme's nearly flat fill takes 0.57 to show the game's 138. The mock's render is not a
-- guide here: it draws the added light layers fainter.
local PLATE_SHADE = 0.57

-- In a battleground the game colours enemy players' plates by class from a class it keeps secret, so the bar's colour
-- comes back secret (GetStatusBarColor, SecretReturnsForAspect VertexColor) and the liquid showed plain hostile red.
-- Then the liquid is drawn white at the fill's brightness and a texture tinted with the secret colour multiplies it
-- (PlateTint): SetVertexColor takes a secret from addons, so the client does the colouring.
local WHITE = { 1, 1, 1 }

local GameColor

-- A flat bar's own colour (a nameplate's, the Personal Resource Display's). A nameplate's is taken at the fill's
-- brightness, in a deep theme (ThemeFor), to look like the game's plate. The Personal Resource Display's bars are the
-- same art, but taken that way they looked dull next to the player frame's liquid (seen in game), so they take their
-- colour at full strength in the unit frames' theme: its health the game's default colour or the player's class (an
-- Edit Mode setting), its power the power type's.
local function PlateColor(b)
    local bar = b.bar
    local c
    b.plateSecret = nil
    if bar.GetStatusBarColor then
        local ok, r, g, bl = pcall(bar.GetStatusBarColor, bar)
        if ok and Secret(r, g, bl) then
            b.plateSecret = { r, g, bl }
            c = WHITE
        elseif ok and type(r) == "number" then
            c = { r, g, bl }
        end
    end
    -- Where the bar's colour is kept from us, the colour the game gives a plate of that reaction, or the unit frames'.
    if not c then
        if b.spot.plate then
            c = ns.Themes.ReactionColor(b.unit, true) or { 1, 0, 0 }
        else
            c = GameColor(b, true)
        end
    end
    if not b.spot.plate then return c end
    return { c[1] * PLATE_SHADE, c[2] * PLATE_SHADE, c[3] * PLATE_SHADE }
end

-- The bar's own colour: health green (a flat bar's its own, unless unflat), or the game's colour for the unit's power
-- type (a preview bar, and the Personal Resource Display's mana under a druid's form, name their power type).
GameColor = function(b, unflat)
    if (b.spot.flat or b.spot.external) and not unflat then return PlateColor(b), "HEALTH" end
    if b.kind == "health" then return HEALTH_COLOR, "HEALTH" end
    local index, token
    if b.spot.token then
        token = b.spot.token
    else
        local ok
        ok, index, token = pcall(UnitPowerType, b.unit)
        if not ok then index, token = nil, nil end
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
-- Whether a plate's Class Color shows its mob's reaction (Class Color on Mobs: Reaction), which on a plate is the
-- plate's own colour: then it takes that, as deep as the game's, rather than the unit frames' softer reaction colours.
local function PlateReaction(b, choice)
    if not (b and b.spot.plate and choice == "class") or ns.Core.Get("mobClassColor") ~= "reaction" then return false end
    local ok, isPlayer = pcall(UnitIsPlayer, b.unit)
    return ok and not Secret(isPlayer) and not isPlayer
end

local function ThemeFor(b, choice)
    local Themes = ns.Themes
    local theme
    if b then b.fromGame = false end
    if choice == "game" or not Themes.list[choice] or PlateReaction(b, choice) then
        if b then b.fromGame = true end
        -- A nameplate's own colour stays as deep as the game's fill.
        theme = Themes.FromColor(GameColor(b), Themes.Get(Themes.default), b and b.spot.plate)
    else
        theme = Themes.Get(choice)
        if theme.Resolve then -- class and faction colours
            theme = theme:Resolve(b and b.unit, b and b.spot.preview, b and b.spot.class)
            if not theme then
                if b then b.fromGame = true end
                theme = Themes.FromColor(GameColor(b), Themes.Get(Themes.default), b and b.spot.plate)
            end
        end
    end
    return setmetatable({ physics = SmallPhysics(theme.physics) }, { __index = theme })
end

local function MixColor(a, b, t)
    return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
end

local function Merged(over, base)
    local t = {}
    for k, v in pairs(base or {}) do t[k] = v end
    for k, v in pairs(over) do t[k] = v end
    return t
end

-- The fury over a rage bar: the bar's own colours boiling over. Brighter all along and hotter toward a white-hot front,
-- flames licking up inside over a hot base, flickering like a fire, its core throbbing, lightning going off and sparks
-- spat off the top, with the theme's own particles as well.
local function FuryTheme(theme)
    local ambient = { FURY_SPARK }
    if type(theme.ambient) == "table" then
        for _, em in ipairs(theme.ambient) do ambient[#ambient + 1] = em end
    end
    local fl = theme.flicker or {}
    return setmetatable({
        fillA = MixColor(theme.fillA, theme.fillB, 0.3),
        fillB = MixColor(theme.fillB, FURY_HOT, 0.3),
        tip = FURY_TIP,
        glow = MixColor(theme.glow, FURY_HOT, 0.6),
        swirlA = MixColor(theme.swirlA, FURY_HOT, 0.7),
        swirlB = MixColor(theme.swirlB, FURY_EMBER, 0.5),
        splashFrom = FURY_TIP,
        splashTo = MixColor(theme.splashTo, FURY_EMBER, 0.5),
        swirl = { texture = "Flames", flow = { 0.05, -1 }, rise = 26, alpha = 1.4, pulse = 0.2, pulseRate = 1.3 },
        shade = { dark = 0.45, color = MixColor(theme.fillA, { 0, 0, 0 }, 0.75), hot = 0.3, hotColor = FURY_HOT },
        core = Merged({ alpha = 1.2, pulseRate = 1.3 }, theme.core),
        flicker = { amount = math.max(fl.amount or 0, 0.25), rate = math.max(fl.rate or 0, 9) },
        crackle = Merged({ rate = 1.2, energyRate = 7 }, theme.crackle),
        ambient = ambient,
    }, { __index = theme })
end

-- A bar's colour choice: its frame's, which can be to follow the player's (target, pet) or the target's (focus,
-- targets of target). A preview's bars are the player's or the target's.
local function ChoiceFor(b)
    -- Another addon's bar keeps the colour that addon gives it, unless it asked for one of ours (AddBar's theme).
    local ext = b.spot.external
    if ext then
        if ext.theme == "settings" then return ns.Core.ColorChoice(b.spot.frame, b.kind) end
        return ext.theme or "game"
    end
    return ns.Core.ColorChoice(b.spot.frame or (b.unit == "target" and "target" or "player"), b.kind)
end

local function ApplyColor(b, force)
    local choice = ChoiceFor(b)
    local own, token = GameColor(b)
    -- Power colours change with the power type only when the bar takes the game's colour, and Class Color with the
    -- unit's colour, falling back on the game's. A nameplate's own colour changes with the unit (tapped, hostile).
    local key = choice
    if b.spot.flat or b.spot.external then
        token = b.plateSecret and "secret" or string.format("%.3f,%.3f,%.3f", own[1], own[2], own[3])
    end
    if choice == "game" then
        key = "game:" .. token
    elseif choice == "class" then
        local c = ns.Themes.UnitColor(b.unit, b.spot.preview, b.spot.class)
        key = c and string.format("class:%.3f,%.3f,%.3f", c[1], c[2], c[3]) or ("class:none:" .. token)
    end
    if key ~= b.colorKey or force then
        b.colorKey = key
        b.liquid:SetTheme(ThemeFor(b, choice))
        if b.fury then b.fury.liquid:SetTheme(FuryTheme(b.liquid.theme)) end
    end
    -- A plate's secret colour goes onto its tint each time it is read, as it can change without our knowing.
    local tint = b.plateTint
    if tint then
        local secret = b.fromGame and b.plateSecret
        if secret then tint:SetVertexColor(secret[1], secret[2], secret[3]) end
        tint:SetShown(secret and true or false)
    end
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

-- A region's alpha made this, whatever it was. The game can set its own fill's alpha from a secret (seen on nameplates in
-- a battleground: "attempt to compare a secret number value"), and GetAlpha then answers with one
-- (SecretReturnsForAspect Alpha), which cannot be compared, so it is then set without looking.
local function AlphaTo(region, alpha)
    local now = region:GetAlpha()
    if Secret(now) or now ~= alpha then region:SetAlpha(alpha) end
end

-- How a bar can be seen: "shown", "hidden" (IsVisible says no) or "faded" (shown, but its effective alpha under 0.01;
-- not a local of its own, as the file is at Lua's 200). Addons hide frames with SetAlpha(0) too (Frames Forever hides the player frame so, and "immersion"
-- addons fade idle frames out), which IsVisible does not see, and a liquid there would run for nothing. IsVisible and
-- GetEffectiveAlpha can answer with secrets (SecretReturnsForAspect Shown, Alpha), taken as shown. GetEffectiveAlpha
-- is under pcall: Forever's docs mark it RequiresScriptObjectAlphaAccess, which may refuse some frames.
local function Sight(region)
    local v = region:IsVisible()
    if Secret(v) then return "shown" end
    if not v then return "hidden" end
    local ok, a = pcall(region.GetEffectiveAlpha, region)
    if not ok or Secret(a) or type(a) ~= "number" then return "shown" end
    return a < 0.01 and "faded" or "shown"
end

-- Whether one of our bars can be seen, as UpdateBar found it this frame (b.sight): asked again on every event and by
-- the markers, it would cost the same widget calls again.
local function Seen(b)
    return (b.sight or Sight(b.bar)) == "shown"
end

-- What the game draws in the bar that the liquid replaces: the fill, and on the player's health bar
-- the red bar of the health-loss animation. That one sits behind the game's fill, but once shown it
-- draws over the liquid at the same frame level, so it hides with the fill.
local function HideGameFill(bar, alpha, external)
    local fill = bar:GetStatusBarTexture()
    if fill then AlphaTo(fill, alpha) end
    if external then return end -- another addon's: only its fill
    local loss = bar.AnimatedLossBar
    local lossFill = type(loss) == "table" and loss.GetStatusBarTexture and loss:GetStatusBarTexture()
    if lossFill then AlphaTo(lossFill, alpha) end
end

local FuryOff -- the rage bar's fury going (below)

-- The game's fill shows while the liquid does not, and the other way round.
local function SetLive(b, live)
    if live == b.live then return end
    b.live = live
    b.sight = nil -- found again on its next update, not kept from before
    b.clip:SetShown(live and not b.away)
    if b.texts then b.texts.frame:SetShown(live) end
    if b.shadeFrame then b.shadeFrame:SetShown(live) end
    HideGameFill(b.bar, (live and not b.away) and 0 or 1, b.spot.external)
    if live then
        Feed(b, false)
        b.liquid:Snap(b.width) -- the liquid is always full on its frame
        -- Drawn on its first update: new, it counts as quiet, and waiting for the idle rate left the bar empty (the
        -- game's fill already hidden) for a moment after login or a setting, and on every gallery image's first frame.
        b.drawNow = true
    else
        b.liquid:HideAll()
        if b.fury then FuryOff(b) end
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

-- A nameplate's liquid sits one frame level above its bar, unlike the unit frames'. At the bar's own level the plate's
-- background (UI-HUD-CoolDownManager-Bar-BG, dark inside, with a shadow along its edges) draws over it, which made it
-- dark and shadowed; tried both ways in game, and above was much better. The plate's text inside the bar (health
-- numbers, the Large style's name) would be under it, so copies of it go above (PlateTexts). Where the client keeps
-- the bar's level secret it stays at the bar's level.
-- Two levels up, one over the plate's DoT liquids (Marker.lua, RaisePlateMarker, one up): at the same level the game
-- kept no fixed order between them, and with a DoT liquid on top its straight cut, under the health's front, showed
-- over it (seen in game, now and then).
-- The Personal Resource Display's bars are the same art on the same background, so their liquid is raised the same
-- way. They are built once, so the raise is looked at again now and then (UpdateBar), should the game move the bar.
local PLATE_RAISE = 2
local function RaisePlate(b)
    local clip = b.clip
    local ok, level = pcall(b.bar.GetFrameLevel, b.bar)
    local shade = b.shadeFrame
    if ok and type(level) == "number" and not Secret(level) then
        if level == b.raisedOn then return end
        b.raisedOn = level
        if clip.SetUsingParentLevel then clip:SetUsingParentLevel(false) end
        clip:SetFrameLevel(level + PLATE_RAISE)
        if shade then shade:SetFrameLevel(level + PLATE_RAISE + 1) end
        if b.texts then b.texts.frame:SetFrameLevel(level + PLATE_RAISE + 2) end
    else
        b.raisedOn = nil
        AtParentLevel(clip, b.bar)
    end
end

-- The plate's text inside the bar, which the raised liquid would cover: the health numbers (the bar's Text, LeftText
-- and RightText, shown by the game's nameplate settings) and the name where the style puts it inside the bar (Large).
-- Each is copied, text, font, colour and place, into a FontString of ours a level above the liquid, drawn exactly
-- over the game's own, which is left as it is. The texts may be secret; FontString:SetText takes them as they are.
-- The Personal Resource Display's bars (flat too) have their texts copied the same way (PRD_TEXTS).
local TEXT_EVERY = 0.1 -- seconds between copies; the game's health text changes no faster than the bar's value

-- Whether a region's centre is inside the bar (the name: inside in the Large style, above it in Normal).
local function Inside(region, bar)
    local ok, x, y = pcall(region.GetCenter, region)
    if not ok or type(x) ~= "number" or type(y) ~= "number" or Secret(x) or Secret(y) then return false end
    local ok2, left, bottom, width, height = pcall(bar.GetRect, bar)
    if not ok2 or type(left) ~= "number" or type(height) ~= "number" or Secret(left) or Secret(bottom)
        or Secret(width) or Secret(height) then
        return false
    end
    return x >= left and x <= left + width and y >= bottom and y <= bottom + height
end

-- Whether the game puts the plates' names inside the health bar, where the liquid would cover them: it does for its
-- Modern and Block styles (Blizzard_NamePlates.lua, GetUnitNameAnchorStyle) and says so in NamePlateSetupOptions. nil
-- when it does not say. Players saw names gone from Block and Large plates while the copy went by where the name sat
-- (Inside), so the game's own setting comes first.
local function NameInsideBar()
    local options = NamePlateSetupOptions
    local style = type(options) == "table" and options.unitNameAnchorStyle
    if type(style) ~= "number" or Secret(style) then return nil end
    local styles = type(NamePlateConstants) == "table" and NamePlateConstants.NAME_ANCHOR_STYLES
    local inside = type(styles) == "table" and styles.InsideHealthBar or 1
    return style == inside
end

-- The size the game draws its plate texts at: it gives them their font object and then SetTextHeight with this
-- (Blizzard_NamePlateUnitFrame.lua), which GetFont does not report.
local function PlateTextHeight()
    local options = NamePlateSetupOptions
    local h = type(options) == "table" and options.healthBarFontHeight
    if type(h) == "number" and not Secret(h) and h > 0 then return h end
end

-- plate: a nameplate's text, which the game draws at the plates' text height.
local function CopyFont(mine, theirs, plate)
    local ok, object = pcall(theirs.GetFontObject, theirs)
    local height = plate and PlateTextHeight()
    if ok and type(object) == "table" then
        if mine.fontObject ~= object then
            mine.fontObject, mine.textHeight, mine.lineHeight = object, nil, nil
            mine:SetFontObject(object)
        end
    else
        local okFont, path, size, flags = pcall(theirs.GetFont, theirs)
        local key = okFont and path and (path .. size .. (flags or ""))
        if key and mine.fontFrom ~= key then
            mine.textHeight, mine.lineHeight = nil, nil
            if mine:SetFont(path, size, flags) then mine.fontFrom = key end
        end
    end
    if height and mine.textHeight ~= height and mine.SetTextHeight then
        mine.textHeight, mine.lineHeight = height, nil
        mine:SetTextHeight(height)
    end
end

-- The game's last step for the name (Blizzard_NamePlateUnitFrame.lua, UpdateAnchors): its font height set to its own
-- line height, done to the copy as well so it is drawn as the game draws the name.
local function CopyNameHeight(mine)
    if mine.lineHeight or not (mine.GetLineHeight and mine.SetFontHeight) then return end
    local ok, h = pcall(mine.GetLineHeight, mine)
    if ok and type(h) == "number" and not Secret(h) and h > 0 then
        mine:SetFontHeight(h)
        mine.lineHeight = h
    end
end

-- shown: true, false, or a secret (IsShown and IsVisible can answer with one, SecretReturnsForAspect Shown). A secret
-- cannot be tested, and SetShown takes one only from untainted code, but SetAlphaFromBoolean takes one from addons
-- (SimpleRegionAPI), so the copy then shows and the client fades it in or out by the game's own answer.
local function CopyText(mine, theirs, shown, whole, plate)
    local secret = Secret(shown)
    if not secret and not shown then
        mine:Hide()
        return
    end
    CopyFont(mine, theirs, plate)
    if whole then CopyNameHeight(mine) end
    -- Each on its own, so one the client refuses cannot keep the rest from being copied.
    pcall(function() mine:SetTextColor(theirs:GetTextColor()) end)
    pcall(function() mine:SetShadowColor(theirs:GetShadowColor()) end)
    pcall(function() mine:SetShadowOffset(theirs:GetShadowOffset()) end)
    pcall(function() mine:SetJustifyH(theirs:GetJustifyH()) end)
    pcall(function() mine:SetJustifyV(theirs:GetJustifyV()) end)
    if whole then
        -- The name is one line, cut short to its width (wordwrap="false" in Blizzard_NamePlates.xml). The copy took
        -- wrapping from the game's name and wrapped a long name onto a second line in game, or, laid over the name's
        -- one-line box, cut it short there.
        mine:SetWordWrap(false)
        if mine.SetMaxLines then pcall(mine.SetMaxLines, mine, 1) end
    else
        -- Forever's FontString has no GetWordWrap; CanWordWrap answers.
        pcall(function() mine:SetWordWrap(theirs:CanWordWrap()) end)
    end
    -- The health texts are sized by their text, so a copy laid over their box would be cut short by any difference
    -- in width; it is pinned at the side its text is justified to instead. The name has a width of the game's (it is
    -- cut short to fit), so its copy takes the same left and right ends, its height left to its text, as the game lays
    -- out its own.
    local ok, justify = pcall(theirs.GetJustifyH, theirs)
    local point = whole and "ENDS" or (ok and (justify == "LEFT" or justify == "RIGHT") and justify) or "CENTER"
    if mine.over ~= theirs or mine.overPoint ~= point then
        mine.over, mine.overPoint = theirs, point
        mine:ClearAllPoints()
        if point == "ENDS" then
            mine:SetPoint("LEFT", theirs, "LEFT")
            mine:SetPoint("RIGHT", theirs, "RIGHT")
        else
            mine:SetPoint(point, theirs, point)
        end
    end
    mine:SetText(theirs:GetText())
    if secret then
        if not (mine.SetAlphaFromBoolean and pcall(mine.SetAlphaFromBoolean, mine, shown, 1, 0)) then
            mine:Hide()
            return
        end
        mine.fromBoolean = true
    elseif mine.fromBoolean then
        mine.fromBoolean = nil
        mine:SetAlpha(1)
    end
    mine:Show()
end

local function SyncPlateTexts(b)
    local t = b.texts
    if not t then return end
    local plate = b.spot.plate
    for i, key in ipairs(b.spot.texts or PLATE_TEXTS) do
        local theirs = b.bar[key]
        if type(theirs) == "table" and theirs.GetText then
            local ok, shown = pcall(theirs.IsShown, theirs)
            -- A secret answer goes on as it is; a truth test on it would raise an error in the client.
            if not ok then shown = false elseif not Secret(shown) then shown = shown == true end
            CopyText(t[i], theirs, shown, false, plate)
        end
    end
    local name = b.unitFrame and b.unitFrame.name
    if type(name) == "table" and name.GetText then
        local ok, shown = pcall(name.IsVisible, name)
        local inside = NameInsideBar()
        if inside == nil then inside = Inside(name, b.bar) end
        if not ok or not inside then shown = false elseif not Secret(shown) then shown = shown == true end
        CopyText(t.name, name, shown, true, plate)
    end
end

-- The copies' frame, built once per flat bar, a level above the liquid; not clipped, as the name is wider. up: its
-- levels above the bar (a flat bar's, over its shading, if nil). A bar raised over a DoT marker (Over.Raise) keeps its
-- copies while it is not, for the next time.
local function PlateTexts(b, up)
    if not b.texts and b.spareTexts then b.texts, b.spareTexts = b.spareTexts, nil end
    b.textsUp = up or PLATE_RAISE + 2
    if not b.texts then
        local frame = CreateFrame("Frame", nil, b.bar)
        frame:SetAllPoints(b.bar)
        local t = { frame = frame }
        -- A font of the game's to start from, so SetText never meets a string without one.
        for i in ipairs(b.spot.texts or PLATE_TEXTS) do
            t[i] = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        end
        t.name = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        for _, fs in pairs(t) do if fs ~= frame then fs:Hide() end end
        b.texts = t
    end
    local frame = b.texts.frame
    local ok, level = pcall(b.bar.GetFrameLevel, b.bar)
    if ok and type(level) == "number" and not Secret(level) then frame:SetFrameLevel(level + b.textsUp) end
    frame:SetShown(b.live)
    b.textIn = 0
end

-- A health bar a DoT marker lies on (Marker.lua: the target frame's, a preview's, another addon's target bar; set with
-- Bars.SetOver). The marker's liquids are drawn under the health liquid by sublevels, so that the health's wavy front
-- lies over them, but sublevels order textures within one frame only, and each liquid has frames of its own: at the
-- same frame level the game kept no fixed order between them. With a DoT liquid on top, its straight cut showed over
-- the health's front, for one DoT and not the next (seen in game on the target frame, as on the plates before
-- RaisePlate). So the health liquid goes a level above the bar, over the marker left at the bar's level, and copies of
-- the bar's texts a level above that, as on the plates. Where the client keeps the bar's level secret it stays at the
-- bar's level.
local Over = { RAISE = 1, bars = {} } -- bars: bar -> true while a DoT marker lies on it

function Over.Raise(b)
    local ok, level = pcall(b.bar.GetFrameLevel, b.bar)
    if not ok or type(level) ~= "number" or Secret(level) then
        b.raisedOn = nil
        AtParentLevel(b.clip, b.bar)
        return
    end
    if level == b.raisedOn then return end
    b.raisedOn = level
    if b.clip.SetUsingParentLevel then b.clip:SetUsingParentLevel(false) end
    b.clip:SetFrameLevel(level + Over.RAISE)
    if b.texts then b.texts.frame:SetFrameLevel(level + Over.RAISE + 1) end
end

-- After the marker came or went (Bars.SetOver), or the bar's liquid was built under one.
function Over.Apply(b)
    if b.spot.flat then return end -- a nameplate's and the Personal Resource Display's are over their markers already
    if b.spot.external then return External.Raise(b) end
    b.raisedOn = nil
    if Over.bars[b.bar] then
        PlateTexts(b, Over.RAISE + 1)
        Over.Raise(b)
        SyncPlateTexts(b)
    else
        AtParentLevel(b.clip, b.bar)
        if b.texts then
            b.texts.frame:Hide()
            b.spareTexts, b.texts = b.texts, nil
        end
    end
end

local function NewBar(spot, bar)
    local w, h = Size(bar, spot.plate and PLATE_W or spot.flat and PRD_W or 1,
        spot.plate and PLATE_H or spot.flat and PRD_H or 1)
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
    -- motes too, which would only clutter a crowd of plates. The Personal Resource Display is one frame, the player's
    -- own, so its motes fly free as on the unit frames; its plate mask cuts the waves.
    local spill = (spot.plate or (spot.external and not spot.external.spill)) and 0 or SPILL
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

    b.spill = spill
    b.liquid = ns.Liquid.New(mover, math.max(w, 1) + ROOM, math.max(h, 1), ns.Themes.Get(ns.Themes.default), ns.Core.db)
    -- The bar's mask cuts the liquid to the bar. Motes are left free to fly off the front. A nameplate's bar has no
    -- mask, and its bronze rim has cut corners that a square liquid would cover, so the liquid there takes a mask of
    -- the addon's own in the shape of the game's fill (PlateMask.tga, make_media.py). So do the Personal Resource
    -- Display's bars, the same art.
    if spot.flat then
        b.mask = clip:CreateMaskTexture()
        b.mask:SetTexture(PLATE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        b.mask:SetAllPoints(bar)
        -- The fill's shading, over the health liquid and the DoT liquids under it alike (RaisePlate puts it a level
        -- above the health). The mask itself is only the shape: fading the liquids let a DoT liquid under the health
        -- show through the health's faded edges, a brighter block behind its front.
        local shade = CreateFrame("Frame", nil, bar)
        shade:SetAllPoints(bar)
        local tex = shade:CreateTexture(nil, "ARTWORK")
        tex:SetTexture(PLATE_SHADE_TEX)
        tex:SetAllPoints(bar)
        -- PlateTint: the plate's colour when the game keeps it secret, multiplying the white liquid under it, from the
        -- bar's left edge to a little past the health's edge (the front wobbles about that far), in the same frame as
        -- the shading and under it.
        local tint = shade:CreateTexture(nil, "ARTWORK", nil, -1)
        tint:SetColorTexture(1, 1, 1, 1)
        tint:SetBlendMode("MOD")
        tint:SetPoint("TOPLEFT", bar, "TOPLEFT")
        tint:SetPoint("BOTTOMRIGHT", proxy:GetStatusBarTexture(), "BOTTOMRIGHT", TINT_PAST, 0)
        tint:AddMaskTexture(b.mask)
        tint:Hide()
        shade:Hide()
        b.shadeFrame, b.shadeTex, b.plateTint = shade, tex, tint
    elseif spot.external then
        -- Another addon's bar: the mask it hands us, if any; a plain rectangle needs none, the clip frame cuts it.
        local m = spot.external.mask
        if type(m) == "table" and m.GetObjectType and m:GetObjectType() == "MaskTexture" then b.mask = m end
        -- Its colour can be secret (a health gradient from the client's curves): then the liquid is drawn white and
        -- this, tinted with the secret colour, multiplies it, as on a battleground's plates (PlateColor). Over the
        -- liquid in its own frame, so it reaches nothing of the other addon's above the bar.
        local tint = mover:CreateTexture(nil, "OVERLAY", nil, 7)
        tint:SetColorTexture(1, 1, 1, 1)
        tint:SetBlendMode("MOD")
        if b.mask then tint:AddMaskTexture(b.mask) end
        tint:Hide()
        b.plateTint = tint
    else
        b.mask = BarMask(bar, spot.kind)
    end
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
    b.stirAt = now + ((b.spot.party or b.spot.slow) and PARTY_STIR_EVERY or STIR_EVERY)
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

-- Whether the bar is showing mana. A druid's forms put rage or energy on it, and the Personal Resource Display's mana
-- under the form shows nothing else.
local function OnMana(b)
    if b.spot.token then return b.spot.token == "MANA" end
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

-- Rage's fury (see FURY_CURVE at the top).
local MEDIA = "Interface\\AddOns\\SmoothAnimatedBars\\Media\\"
local curves -- { fury, ready }, or false where the client has no curves or no UnitPowerPercent

local function MakeCurve(points)
    local c = C_CurveUtil.CreateCurve()
    c:SetType(Enum.LuaCurveType.Linear)
    for _, p in ipairs(points) do c:AddPoint(p[1], p[2]) end
    return c
end

local function Curves()
    if curves == nil then
        local ok, fury, ready = pcall(function() return MakeCurve(FURY_CURVE), MakeCurve(READY_CURVE) end)
        curves = ok and type(UnitPowerPercent) == "function" and { fury = fury, ready = ready } or false
    end
    return curves or nil
end

-- Whether the bar shows rage: a warrior's, a druid's in Bear Form, a target's, the Personal Resource Display's (not its
-- mana under the form). Not yet a party member's: not tried.
local function ShowsRage(b)
    if b.kind ~= "power" or b.spot.plate or b.spot.preview or b.spot.party or b.spot.slow then return false end
    if b.spot.token then return b.spot.token == "RAGE" end
    local _, token = UnitPowerType(b.unit)
    return not Secret(token) and token == "RAGE"
end

local function NewFury(b)
    local f = { samples = {}, feed = 0, acc = 0, beat = 0, flash = 0, innerAlpha = 1 }
    -- Laid over the bar's liquid; frame takes the fury's alpha, inner the burst's fades, ready the full bar's throb.
    f.frame = CreateFrame("Frame", nil, b.mover)
    f.inner = CreateFrame("Frame", nil, f.frame)
    f.ready = CreateFrame("Frame", nil, f.inner)
    for _, frame in ipairs({ f.frame, f.inner, f.ready }) do
        AtParentLevel(frame, frame:GetParent())
        frame:SetAllPoints(frame:GetParent())
    end
    f.frame:SetAlpha(0)
    f.ready:SetAlpha(0)
    -- As many slices as the bar's liquid, whose front it follows slice by slice.
    f.liquid = ns.Liquid.New(f.inner, math.max(b.width, 1) + ROOM, math.max(b.height, 1), FuryTheme(b.liquid.theme),
        ns.Core.db, b.liquid.n)
    f.liquid:Follow(b.liquid, FURY_TREMBLE)
    -- The full bar's throb: a glow on the front at the bar's end and the whole liquid lighting up with it.
    f.wash = f.ready:CreateTexture(nil, "ARTWORK", nil, 6)
    f.wash:SetColorTexture(1, 1, 1, 1)
    f.wash:SetBlendMode("ADD")
    f.wash:SetAllPoints(f.ready)
    f.glow = f.ready:CreateTexture(nil, "ARTWORK", nil, 7)
    f.glow:SetTexture(MEDIA .. "Glow")
    f.glow:SetBlendMode("ADD")
    f.glow:SetPoint("CENTER", f.ready, b.mirror and "LEFT" or "RIGHT")
    if b.mirror then f.liquid:SetMirror(true) end
    if b.mask then
        local free = {}
        for _, m in ipairs(f.liquid.motes) do free[m.tex] = true end
        for _, t in ipairs(f.liquid.textures) do
            if not free[t] then t:AddMaskTexture(b.mask) end
        end
        f.wash:AddMaskTexture(b.mask)
        f.glow:AddMaskTexture(b.mask)
    end
    return f
end

-- The fury's colours, for the throb.
local function FuryColors(f)
    local theme = f.liquid.theme
    return theme.glow, theme.tip, theme.splashTo
end

-- Spending rage: the bar's own liquid throws hot sparks off its front, at any rage. The fury, as far as it showed,
-- bursts at the rage there was, then fades, and comes back in at what is left.
local function Release(b)
    local w, h = b.width, b.height
    local base = b.liquid
    local theme = base.theme
    local hot = MixColor(theme.tip, FURY_HOT, 0.5)
    base:Splash(SPEND_SPLASH, w - 8, w)
    for _ = 1, SPEND_SPARKS do
        base:EmitMote(w - Rand(0, 8), Rand(1, math.max(1, h - 1)), Rand(-20, 110), Rand(-30, 80), Rand(0.4, 0.9),
            Rand(7, 11), hot, FURY_EMBER, SPARK)
    end

    local f = b.fury
    local s = f and f.on and f.samples[1]
    if not s then return end
    f.frame:SetAlpha(s[2])
    f.ready:SetAlpha(s[3])
    f.held, f.releaseAt, f.flash = true, GetTime(), 1
    local liquid = f.liquid
    liquid:Splash(0.4, w - 8, w)
    liquid:Warm(0.7)
    liquid:Storm(2)
    local _, tip, to = FuryColors(f)
    local from = MixColor(tip, FURY_HOT, 0.5)
    for _ = 1, RELEASE_SPARKS do
        liquid:EmitMote(w - Rand(0, 12), Rand(1, math.max(1, h - 1)), Rand(-30, 130), Rand(-40, 90), Rand(0.5, 1.1),
            Rand(7, 12), from, to, SPARK)
    end
end

-- The player's casts are listened to only while the player's bar shows the fury, for the bursts.
local function ListenForSpends()
    local want = false
    for _, b in pairs(bars) do
        if b.unit == "player" and b.live and b.fury and b.fury.on then want = true end
    end
    if driver then
        if want then driver:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED") else driver:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED") end
    end
end

FuryOff = function(b)
    local f = b.fury
    if f and f.on then
        f.on = false
        f.frame:Hide()
        f.liquid:HideAll()
        ListenForSpends()
    end
end

local function Fury(b, dt, w, h)
    local c = ns.Core.Get("rageFury") and ShowsRage(b) and Curves()
    local f = b.fury
    if not c then
        FuryOff(b)
        return
    end
    if not f then
        f = NewFury(b)
        b.fury = f
    end
    if not f.on then
        f.on, f.held, f.releaseAt, f.feed = true, false, nil, 0
        f.frame:Show()
        f.liquid:Snap(w)
        ListenForSpends()
    end
    if w ~= f.liquid.width - ROOM or h ~= f.liquid.height then f.liquid:SetSize(w + ROOM, h) end
    local now = GetTime()

    -- How much shows, from the rage itself. The last RELEASE_LAG seconds of it are kept for a burst.
    f.feed = f.feed - dt
    if f.feed <= 0 then
        f.feed = FURY_EVERY
        local ok, fury = pcall(UnitPowerPercent, b.unit, nil, false, c.fury)
        local ok2, ready = pcall(UnitPowerPercent, b.unit, nil, false, c.ready)
        if ok and ok2 then
            local samples = f.samples
            samples[#samples + 1] = { now, fury, ready }
            while #samples > 1 and samples[2][1] <= now - RELEASE_LAG do table.remove(samples, 1) end
            if not f.held then
                f.frame:SetAlpha(fury)
                f.ready:SetAlpha(ready)
            end
        end
    end

    -- A burst holds at the rage there was and fades, then the fury comes back in at what is left.
    local inner, bursting = 1, f.releaseAt ~= nil
    if bursting then
        local age = now - f.releaseAt
        if age < RELEASE_HOLD + RELEASE_FADE then
            inner = min(1, 1 - (age - RELEASE_HOLD) / RELEASE_FADE)
        else
            if f.held then
                f.held = false
                local s = f.samples[#f.samples]
                if s then
                    f.frame:SetAlpha(s[2])
                    f.ready:SetAlpha(s[3])
                end
            end
            inner = min(1, (age - RELEASE_HOLD - RELEASE_FADE) / RELEASE_BACK)
            if inner >= 1 then f.releaseAt = nil end
        end
    end
    if inner ~= f.innerAlpha then
        f.innerAlpha = inner
        f.inner:SetAlpha(math.max(0, inner))
    end

    -- Always furious inside, and the full bar throbs like a heartbeat, two beats close together, each time spitting
    -- sparks from the front and making it tremble harder.
    local liquid = f.liquid
    liquid:Warm(FURY_ENERGY)
    liquid:Storm(FURY_STORM)
    f.beat = f.beat + dt
    if f.beat >= READY_BEAT then
        f.beat = f.beat - READY_BEAT
        local _, tip, to = FuryColors(f)
        for _ = 1, READY_SPARKS do
            liquid:EmitMote(w - Rand(0, 6), Rand(2, math.max(2, h - 2)), Rand(-10, 50), Rand(20, 80), Rand(0.4, 0.9),
                Rand(7, 11), tip, to, SPARK)
        end
    end
    local p = f.beat / READY_BEAT
    local throb = math.exp(-p * 10) + (p > 0.22 and 0.6 * math.exp(-(p - 0.22) * 10) or 0)
    f.flash = math.max(0, f.flash - dt / (RELEASE_HOLD + RELEASE_FADE))
    local glow = FuryColors(f)
    f.glow:SetVertexColor(glow[1], glow[2], glow[3])
    f.glow:SetSize(h * 7 * (1 + 0.3 * throb + 0.5 * f.flash), h * 2.4)
    f.glow:SetAlpha(min(1, 0.4 + 0.5 * throb + 0.4 * f.flash))
    f.wash:SetVertexColor(glow[1], glow[2], glow[3])
    f.wash:SetAlpha(min(1, 0.05 + 0.2 * throb + 0.2 * f.flash))
    liquid:SetTremble(FURY_TREMBLE * (1 + 1.5 * throb))

    f.acc = f.acc + dt
    if not bursting and f.acc < 1 / FURY_FPS then return end
    liquid:Update(f.acc, w)
    f.acc = 0
end

-- Whether a spell costs rage. A cost the client keeps secret counts.
local function CostsRage(spellID)
    local read = C_Spell and C_Spell.GetSpellPowerCost
    local ok, costs = pcall(read, spellID)
    if not ok or type(costs) ~= "table" then return false end
    for _, c in ipairs(costs) do
        if Secret(c.name, c.type) then return true end
        if c.name == "RAGE" or c.type == 1 then
            return Secret(c.cost) or (type(c.cost) == "number" and c.cost > 0)
        end
    end
    return false
end

-- A party bar's member offline: the game shows the bar full and grey (PartyMemberFrameMixin:UpdateOnlineStatus), which
-- says more than a full liquid would, so its own fill comes back until the member does.
local function SetAway(b, away)
    if away == (b.away or false) then return end
    b.away = away
    b.clip:SetShown(not away)
    HideGameFill(b.bar, away and 1 or 0)
    if away then
        b.liquid:HideAll()
    else
        Feed(b, false)
        b.liquid:Snap(b.width)
    end
end

local PARTY_CHECK_EVERY = 0.5 -- seconds between looks at whether a party member is online, and at their colour

-- A party bar follows the unit the game shows on it. Its colour is looked at again with each check: a member who has
-- just joined may not have their class or power type known yet (ApplyColor only re-themes when it changed).
local function PartyFollow(b, dt)
    local unit = b.bar.unit
    if type(unit) == "string" and not Secret(unit) and unit ~= b.unit then
        b.unit, b.checkIn = unit, 0
        ApplyColor(b)
        Feed(b, false)
    end
    b.checkIn = (b.checkIn or 0) - dt
    if b.checkIn > 0 then return end
    b.checkIn = PARTY_CHECK_EVERY
    -- Whether the member is online, asked of the member frame's unit as the game does (UpdateOnlineStatus): in a vehicle
    -- the bar shows the vehicle (partypetN), which is no player to be online.
    local member = b.spot.member
    local who = type(member) == "table" and member.unit
    if type(who) ~= "string" or Secret(who) then who = b.unit end
    local ok, connected = pcall(UnitIsConnected, who)
    SetAway(b, ok and not Secret(connected) and connected == false)
    if not b.away then ApplyColor(b) end
end

local function UpdateBar(b, dt)
    local bar = b.bar
    b.sight = Sight(bar)
    if b.sight ~= "shown" then
        b.unseen = true
        return
    end
    if b.spot.party then
        PartyFollow(b, dt)
        if b.away then return end
    end
    -- The game can swap or reset its fill textures; keep them hidden under the liquid.
    HideGameFill(bar, 0, b.spot.external)
    -- Back after being hidden (the Personal Resource Display shown in combat only, the mana under a druid's form, a
    -- frame with no unit): the liquid starts where the bar is, not easing over from where it was, and calm, not
    -- finishing a burst from before it was hidden.
    if b.unseen then
        b.unseen = nil
        Feed(b, false)
        b.liquid:Settle()
        if b.fury and b.fury.on then
            b.fury.liquid:Settle()
            b.fury.acc = 1 / FURY_FPS -- drawn again this frame too
        end
        -- Settled, it counts as quiet: drawn again now, not at the next idle update, or the bar shows nothing until then
        -- (its game fill is hidden).
        b.drawNow = true
        b.colorIn = 0 -- a flat bar's colour may have changed meanwhile (a druid shifting while it was hidden)
    end

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
    -- A flat bar's own colour can change under it (a plate once tapped, the Personal Resource Display's health with
    -- its class colour setting), and its texts are copies.
    if b.spot.flat then
        b.colorIn = (b.colorIn or 0) - dt
        if b.colorIn <= 0 then
            b.colorIn = PLATE_COLOR_EVERY
            ApplyColor(b)
            if not b.spot.plate and not b.spot.preview then RaisePlate(b) end
        end
        b.textIn = (b.textIn or 0) - dt
        if b.textIn <= 0 then
            b.textIn = TEXT_EVERY
            SyncPlateTexts(b)
        end
    elseif b.texts then
        -- Raised over a DoT marker (Over.Raise): its texts are copies too, and the bar's level is looked at again.
        b.textIn = (b.textIn or 0) - dt
        if b.textIn <= 0 then
            b.textIn = TEXT_EVERY
            Over.Raise(b)
            SyncPlateTexts(b)
        end
    end
    if b.spot.external then
        b.colorIn = (b.colorIn or 0) - dt
        if b.colorIn <= 0 then
            b.colorIn = External.LOOK_EVERY
            External.Look(b)
            if not b.live then return end -- turned vertical: dropped
        end
    end
    if b.spot.party or b.spot.slow then idleFps = PARTY_FPS end
    if b.spot.plate then
        idleFps = PLATE_IDLE_FPS
    else
        Inflow(b, dt, w, h)
        BuildUp(b, dt, w, h)
        if b.kind == "power" then
            local clock = debugprofilestop
            local t0 = clock and clock()
            Fury(b, dt, w, h)
            if t0 then b.furyMs = (b.furyMs or 0) + (clock() - t0) end
        end
    end

    -- Once settled only the idle wobble remains, so it drops to the idle rate. A party bar keeps to its rate busy too.
    if b.drawNow then
        b.drawNow, b.idle = nil, 0
    elseif b.spot.party or b.spot.slow or b.liquid:IsQuiet() then
        b.idle = b.idle + dt
        if b.idle < 1 / idleFps then return end
        dt, b.idle = b.idle, 0
    else
        b.idle = 0
    end
    b.liquid:Update(dt, w)
end

--------------------------------------------------------------------------------
-- Other addons' bars
--------------------------------------------------------------------------------

-- A bar that fills from the right (SetReverseFill): our hidden bar fills the same way, the liquid's frame ends on its
-- fill's left edge, the liquid is drawn mirrored, and the motes fly off to the left. force lays it all out again.
function External.SetMirror(b, on, force)
    on = on and true or false
    if on == (b.mirror or false) and not force then return end
    b.mirror = on
    b.proxy:SetReverseFill(on)
    local bar, clip, mover, fill, spill = b.bar, b.clip, b.mover, b.proxy:GetStatusBarTexture(), b.spill or 0
    clip:ClearAllPoints()
    mover:ClearAllPoints()
    if on then
        clip:SetPoint("TOPLEFT", bar, "TOPLEFT", -spill, spill)
        clip:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, -spill)
        mover:SetPoint("TOPLEFT", fill, "TOPLEFT")
        mover:SetPoint("BOTTOMLEFT", fill, "BOTTOMLEFT")
    else
        clip:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, spill)
        clip:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", spill, -spill)
        mover:SetPoint("TOPRIGHT", fill, "TOPRIGHT")
        mover:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT")
    end
    mover:SetWidth(b.width)
    local tint = b.plateTint
    if tint then
        tint:ClearAllPoints()
        if on then
            tint:SetPoint("TOPRIGHT", bar, "TOPRIGHT")
            tint:SetPoint("BOTTOMLEFT", fill, "BOTTOMLEFT", -TINT_PAST, 0)
        else
            tint:SetPoint("TOPLEFT", bar, "TOPLEFT")
            tint:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", TINT_PAST, 0)
        end
    end
    b.liquid:SetMirror(on)
    local f = b.fury
    if f then
        f.liquid:SetMirror(on)
        f.glow:ClearAllPoints()
        f.glow:SetPoint("CENTER", f.ready, on and "LEFT" or "RIGHT")
    end
    if b.live then
        Feed(b, false)
        b.liquid:Snap(b.width)
        b.drawNow = true
    end
end

-- One level above the bar by default (AddBar's level), as many as the addon asks for, or 0 for the bar's own level. At
-- the bar's own level the bar's background, a texture on the bar itself, drew over the liquid (seen in game on Frames
-- Forever's bars, dark at 80%: the liquid showed dim), as the plates' did. The addon's text and heal prediction on
-- frames higher up stay over it. A target health bar with the DoT marker on it has the marker at that level and its
-- liquid one more up, over the marker (Over.Raise says why).
function External.Raise(b)
    local up = b.spot.external.level or 1
    if Over.bars[b.bar] and b.spot.unit == "target" and b.spot.kind == "health" then up = up + Over.RAISE end
    if up <= 0 then
        b.raisedOn = nil
        AtParentLevel(b.clip, b.bar)
        return
    end
    local ok, level = pcall(b.bar.GetFrameLevel, b.bar)
    if not ok or type(level) ~= "number" or Secret(level) then return end
    if level + up == b.raisedOn then return end
    b.raisedOn = level + up
    if b.clip.SetUsingParentLevel then b.clip:SetUsingParentLevel(false) end
    b.clip:SetFrameLevel(level + up)
end

-- Its colour, which way it fills and its level, any of which the other addon can change at any time.
function External.Look(b)
    local okO, orientation = pcall(b.bar.GetOrientation, b.bar)
    if okO and not Secret(orientation) and orientation == "VERTICAL" then return External.Drop(b.spot) end
    local ok, reverse = pcall(b.bar.GetReverseFill, b.bar)
    if ok and not Secret(reverse) then External.SetMirror(b, reverse) end
    External.Raise(b)
    ApplyColor(b)
end

-- Whose colour settings a unit's bar takes when the other addon asks for ours (theme "settings").
function External.FrameOf(unit)
    if unit == "player" or unit == "vehicle" then return "player" end
    if unit == "pet" then return "pet" end
    if unit == "focus" then return "focus" end
    if unit == "targettarget" or unit == "focustarget" then return "tot" end
    if unit:match("^party") or unit:match("^raid") then return "party" end
    if unit:match("^nameplate") then return "plate" end
    return "target"
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
    if type(bar) == "table" and bar.GetStatusBarTexture and bar.GetValue then return bar, unitFrame end
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
    local bar, unitFrame = PlateBar(token)
    if not bar then return false end
    local b = plates[bar]
    -- The bar may still be on the books for a token whose removal came after its next use.
    if b and b.token and b.token ~= token and plateOf[b.token] == b then plateOf[b.token] = nil end
    if not plateOf[token] and CountSide(side) >= Cap(side) then return false end
    if not b then
        b = NewBar({ key = "plateHealth", frame = "plate", unit = token, kind = "health", plate = true, flat = true },
            bar)
        plates[bar] = b
    end
    b.token, b.unit, b.spot.unit, b.side = token, token, token, side
    b.spot.frame = side == "friend" and "friend" or "plate" -- whose colour setting it takes
    b.err, b.colorIn = nil, PLATE_COLOR_EVERY
    RaisePlate(b)
    b.unitFrame = unitFrame
    PlateTexts(b)
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
local perf = { done = {}, groups = {} }

-- The unit frames' share is split again by group (PerfGroup), each with its own count of liquids showing: the
-- Personal Resource Display and the party frames apart from the rest.
local PERF_GROUPS = { "prd", "party", "addon" }

local function PerfGroup(b)
    if b.spot.external then return "addon" end
    if b.spot.party then return "party" end
    if b.spot.flat and not b.spot.plate and not b.spot.preview then return "prd" end
end

local function PerfAdd(unitMs, plateMs, units, platesLive, groups)
    local second = math.floor(GetTime())
    local cur = perf.cur
    if not cur or cur.second ~= second then
        if cur then
            table.insert(perf.done, 1, cur)
            perf.done[PERF_SECONDS + 1] = nil
        end
        cur = { second = second, frames = 0, unitMs = 0, plateMs = 0, peak = 0, units = 0, plates = 0 }
        for _, g in ipairs(PERF_GROUPS) do cur[g .. "Ms"], cur[g] = 0, 0 end
        perf.cur = cur
    end
    cur.frames = cur.frames + 1
    cur.unitMs, cur.plateMs = cur.unitMs + unitMs, cur.plateMs + plateMs
    cur.peak = math.max(cur.peak, unitMs + plateMs)
    cur.units, cur.plates = math.max(cur.units, units), math.max(cur.plates, platesLive)
    for _, g in ipairs(PERF_GROUPS) do
        cur[g .. "Ms"] = cur[g .. "Ms"] + groups[g .. "Ms"]
        cur[g] = math.max(cur[g], groups[g])
    end
end

-- Each unit frame bar's time (and its fury's), moved into the second just ended. Its label names it in /sab perf.
local function PerfBars(cur)
    cur.bars = cur.bars or {}
    for _, b in pairs(bars) do
        if b.perfMs and b.perfMs > 0 then
            local label = b.spot.label or ((b.unit or "?") .. " " .. b.kind)
            local e = cur.bars[label] or { ms = 0, fury = 0 }
            e.ms, e.fury = e.ms + b.perfMs, e.fury + (b.furyMs or 0)
            cur.bars[label] = e
            b.perfMs, b.furyMs = 0, 0
        end
    end
end

local function RunBar(b, dt)
    if not b.live or b.err then return false end
    local ok, err = pcall(UpdateBar, b, dt)
    if not ok then
        b.err = tostring(err)
        pcall(SetLive, b, false)
        -- Another addon's bar may be added again and fail again: said once.
        if not b.reported then ns.Core.Print("Error in the " .. (b.spot.preview and "preview " or "") .. (b.spot.plate and "nameplate " or "")
            .. (b.spot.label or (b.unit .. " " .. b.kind)) .. " bar, which is back to the game's own: " .. b.err) end
        if b.spot.external then b.reported = true end
        if b.token then plateOf[b.token] = nil end
    end
    -- Counted for /sab perf only while it shows: a hidden frame's bar (no focus, no pet) costs next to nothing.
    return ok and Seen(b)
end

-- An error in one bar is kept for /sab debug and reported once, and that bar goes back to the
-- game's fill; the others carry on.
-- The game makes its party member frames when the party frame first shows (PartyFrameMixin:OnShow), which can come
-- after the group change that shows it, or with no group change at all (Edit Mode). So while a wanted party bar is
-- missing, the frames are looked for every PARTY_LOOK_EVERY out of combat, where the bars are built as at login.
local PARTY_LOOK_EVERY = 1
local partyLookIn = 0

local function PartyFramesNew()
    for kind, key in pairs(PARTY_KINDS) do
        if ns.Core.Get(key) then
            for i = 1, 4 do
                local bar = PartyBar(i, kind)
                if bar ~= nil and not partyBuilt[bar] then return true end
            end
        end
    end
    return false
end

LookForParty = function(dt)
    partyLookIn = partyLookIn - dt
    if partyLookIn > 0 then return end
    partyLookIn = PARTY_LOOK_EVERY
    if not InCombatLockdown() and PartyFramesNew() then Bars.Apply() end
end

local function OnUpdate(_, elapsed)
    local dt = min(elapsed, 0.1)
    if dt <= 0 then return end
    local clock = debugprofilestop
    local t0 = clock and clock()
    local units, live = 0, 0
    local groups = perf.groups
    for _, g in ipairs(PERF_GROUPS) do groups[g .. "Ms"], groups[g] = 0, 0 end
    for _, b in pairs(bars) do
        local g = clock and PerfGroup(b)
        local tb = clock and clock()
        local shows = RunBar(b, dt)
        if shows then units = units + 1 end
        if tb then
            local ms = clock() - tb
            b.perfMs = (b.perfMs or 0) + ms
            if g then
                groups[g .. "Ms"] = groups[g .. "Ms"] + ms
                if shows then groups[g] = groups[g] + 1 end
            end
        end
    end
    for _, b in ipairs(previews) do if RunBar(b, dt) then units = units + 1 end end
    local t1 = clock and clock()
    if next(pending) then TryPending() end
    for _, b in pairs(plates) do if RunBar(b, dt) then live = live + 1 end end
    if partyWaiting then LookForParty(dt) end
    if clock then
        PerfAdd(t1 - t0, clock() - t1, units, live, groups)
        PerfBars(perf.cur)
    end
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

local function OnEvent(_, event, unit, ...)
    if type(unit) == "string" and unit:match("^party") then partyEvents[event] = (partyEvents[event] or 0) + 1 end
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        if unit ~= "player" then return end
        local _, spellID = ...
        local spent
        for _, b in pairs(bars) do
            -- Not on a hidden bar (the display out of combat): its burst would wait there until the bar shows.
            if b.live and b.unit == "player" and b.fury and b.fury.on and Seen(b) then
                if spent == nil then spent = CostsRage(spellID) end
                if spent then Release(b) end
            end
        end
        return
    end
    if type(unit) == "string" and unit:match("^nameplate%d+$") then
        local pb = plateOf[unit]
        if pb and pb.live and STIR_EVENTS[event] == "health" then Stir(pb) end
        OnPlateEvent(event, unit)
        -- The same unit can be the target or focus as well, which the frames' own events cover.
        return
    end
    if event == "GROUP_ROSTER_UPDATE" then
        -- Someone joined or left: a party bar can show another member under the same token, and the party frames may
        -- only now be there to build on (built out of combat, as at login).
        -- Only when a member frame is there to build on: without the party frame (raid-style frames) every roster change
        -- in a raid or battleground would apply everything again.
        if partyWaiting and not InCombatLockdown() and PartyFramesNew() then Bars.Apply() end
        for _, b in pairs(bars) do
            if b.live and b.spot.slow then
                ApplyColor(b)
                Feed(b, false)
            elseif b.live and b.spot.party then
                b.checkIn = 0
                ApplyColor(b)
                Feed(b, false)
            end
        end
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
                    -- A flat bar's colour is the bar's, which the game sets in its own handler of this event, perhaps
                    -- after ours: it is read on the next update.
                    if b.kind == "power" then
                        if b.spot.flat then b.colorIn = 0 else ApplyColor(b) end
                    end
                elseif STIR_EVENTS[event] == b.kind and Seen(b) then
                    -- A bar of one power (the Personal Resource Display's mana under a form) stirs only with it. A
                    -- hidden bar is not stirred: a hidden party bar can still have the player on it from Edit Mode.
                    local token = ...
                    if not (b.spot.token and event == "UNIT_POWER_UPDATE" and type(token) == "string"
                        and not Secret(token) and token ~= b.spot.token) then
                        Stir(b)
                    end
                end
            end
        end
    end
end

local EVENTS = { "PLAYER_TARGET_CHANGED", "UNIT_DISPLAYPOWER", "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE",
                 "UNIT_MAXPOWER", "UNIT_TARGET", "UNIT_PET", "PLAYER_FOCUS_CHANGED", "GROUP_ROSTER_UPDATE" }
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

-- Every bar there is for an on/off setting: the Personal Resource Display's power is its power bar and the mana under
-- a druid's form. Each comes with whether it shows only mana.
function Bars.FindAll(key)
    local out = {}
    for _, spot in ipairs(SPOTS) do
        if spot.key == key then
            local bar = spot.find()
            if type(bar) == "table" and bar.GetStatusBarTexture then
                out[#out + 1] = { bar = bar, manaOnly = spot.token == "MANA" }
            end
        end
    end
    return out
end

local function IsBar(bar)
    return type(bar) == "table" and bar.GetStatusBarTexture and bar.GetValue and true or false
end

-- A spot for each party bar wanted and not yet built, wherever the pool has put it. Returns whether a member frame
-- was missing, to look again when the group changes.
local function AddPartySpots()
    local built, missing = partyBuilt, false
    for kind, key in pairs(PARTY_KINDS) do
        if ns.Core.Get(key) then
            for i = 1, 4 do
                local bar = PartyBar(i, kind)
                if bar == nil then
                    missing = true
                elseif IsBar(bar) and not built[bar] then
                    built[bar] = true
                    local spot = { key = key, frame = "party", optional = true, party = true, unit = "party" .. i,
                                   kind = kind, find = function() return bar end,
                                   member = Path(rawget(_G, "PartyFrame"), "MemberFrame" .. i) }
                    SPOTS[#SPOTS + 1] = spot
                    bars[spot] = NewBar(spot, bar)
                end
            end
        end
    end
    return missing
end

-- Show the liquid on the bars that are switched on, building each the first time it is wanted.
-- Returns how many of the game's bars are showing it and how many were wanted but not found.
function Bars.Apply()
    local live, missing = 0, 0
    local waiting = AddPartySpots()
    for _, spot in ipairs(SPOTS) do
        local want = Wanted(spot)
        local b = bars[spot]
        if want and not b then
            local bar = spot.find()
            if IsBar(bar) then
                b = NewBar(spot, bar)
                bars[spot] = b
                -- A flat bar's liquid goes above the bar, under copies of its texts, as on the plates.
                if spot.flat then
                    PlateTexts(b)
                    RaisePlate(b)
                elseif Over.bars[bar] then
                    Over.Apply(b) -- the DoT marker was there first
                end
            elseif not spot.optional then
                missing = missing + 1
            end
        end
        if b then
            SetLive(b, want and not b.err)
            if b.live then live = live + 1 end
        end
    end
    -- Other addons' bars (AddBar), on with their own setting.
    local allowed = ns.Core.Get("externalBars") and true or false
    for _, spot in pairs(externals) do
        local b = bars[spot]
        SetLive(b, allowed and not spot.removed and not b.err)
        if b.live then live = live + 1 end
    end
    partyWaiting = waiting
    -- Previews follow the same settings, so the wizard shows each choice on them.
    local any = live
    for _, b in ipairs(previews) do
        SetLive(b, ns.Core.Get(b.spot.key) and not b.err and true or false)
        if b.live then any = any + 1 end
    end
    local platesOn = PlatesWanted()
    if (any > 0 or platesOn or waiting) and not driver then
        driver = CreateFrame("Frame")
        driver:SetScript("OnUpdate", OnUpdate)
        driver:SetScript("OnEvent", OnEvent)
    end
    External.unitEvents = live > 0
    if driver then
        driver:SetShown(any > 0 or platesOn or waiting)
        for _, event in ipairs(EVENTS) do
            if live > 0 or (platesOn and BOTH[event]) or (waiting and event == "GROUP_ROSTER_UPDATE") then
                driver:RegisterEvent(event)
            else
                driver:UnregisterEvent(event)
            end
        end
        for _, event in ipairs(PLATE_EVENTS) do
            if platesOn then driver:RegisterEvent(event) else driver:UnregisterEvent(event) end
        end
        ApplyPlates()
    end
    return live, missing
end

-- The liquid on a bar of a preview frame. spec: { key = its on/off setting, unit, kind, token = power
-- type for a power bar, frame = whose colour setting it follows, class = the class it stands for }. Returns its
-- state, for Bars.Stir.
-- spec.plate makes it a nameplate's (the setup's nameplate step): the plate mask, a level above the bar as in game,
-- and spec.frame ("plate" or "friend") names whose colour setting it follows.
function Bars.Preview(bar, spec)
    spec.preview = true
    if spec.plate then spec.flat = true end
    local b = NewBar(spec, bar)
    if spec.plate then RaisePlate(b) end
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

-- Whether a DoT marker lies on a health bar (Marker.lua): its liquid goes a level above the marker, with copies of the
-- bar's texts above it (Over.Raise). A flat bar's is raised over its marker already; another addon's goes one level
-- above the addon's level (External.Raise). The bar may not have its liquid yet: Bars.Apply looks when it builds it.
function Bars.SetOver(bar, on)
    on = on and true or nil
    if Over.bars[bar] == on then return end
    Over.bars[bar] = on
    local b = StateFor(bar)
    if b then Over.Apply(b) end
end

-- The mask the liquid on a flat bar takes (a nameplate's, the Personal Resource Display's), for the markers' liquids
-- there (Marker.lua, HealMarker.lua); nil for any other bar.
function Bars.PlateMask(bar)
    local b = StateFor(bar)
    return b and b.spot.flat and b.mask or nil
end

-- For the tests: a plate bar's copies of its texts ({ frame, [1..3], name }), nil until it first had the liquid.
function Bars.PlateTexts(bar)
    local b = plates[bar]
    return b and b.texts
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
    return b and b.live and not b.err and not b.away or false
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
    elseif b.mirror then -- another addon's bar filling from the right (External.SetMirror)
        local fill = b.proxy:GetStatusBarTexture()
        mover:SetPoint("TOPLEFT", fill, "TOPLEFT")
        mover:SetPoint("BOTTOMLEFT", fill, "BOTTOMLEFT")
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
    if not b or not b.live or not b.inflow or not Seen(b) then return end
    b.charge, b.sated, b.flash = nil, true, 1
    local theme, w, h = b.inflow.theme, b.width, b.height
    for _ = 1, RELEASE_STARS do
        b.liquid:EmitMote(Rand(0, w), Rand(0, h), Rand(-30, 30), Rand(20, 70), Rand(0.9, 1.7), Rand(10, 18),
            theme.tip, theme.splashTo, STAR)
    end
    b.liquid:Splash(0.8, 0, w)
end

-- The buff was reached while the bar was faded out: no release to see, only the slow stars when it shows again.
function Bars.Sate(bar)
    local b = StateFor(bar)
    if b then b.charge, b.sated = nil, true end
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
    -- Not into a hidden bar (the mana under a druid's form in caster form, the display out of combat): the stars would
    -- wait there and burst out when it shows.
    if not b.live or b.inflow or not OnMana(b) or not Seen(b) then return end
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

-- Another addon's bar (SmoothAnimatedBars.AddBar, below). The liquid follows whatever the bar shows, as it does the
-- game's: our hidden bar takes its (secret) value, and its own fill is made transparent while the liquid shows. Its
-- colour is the bar's own unless the addon asks for a theme, so the addon's colour settings keep working.

local function IsMaskTexture(m)
    if type(m) ~= "table" or type(m.GetObjectType) ~= "function" then return false end
    local ok, kind = pcall(m.GetObjectType, m)
    return ok and kind == "MaskTexture"
end

-- What is wrong with AddBar's arguments, or nil. The public AddBar raises it as the caller's error. An unknown theme is
-- not wrong: it falls back to the bar's own colour, so a caller written for a theme added or renamed later still works.
function Bars.CheckAddBar(bar, unit, kind, options)
    local api = "SmoothAnimatedBars.AddBar: "
    if not IsBar(bar) then return api .. "bar must be a StatusBar" end
    if type(unit) ~= "string" or Secret(unit) or unit == "" then
        return api .. "unit must be a unit token such as \"player\""
    end
    if Secret(kind) or not External.KINDS[kind] then return api .. "kind must be \"health\" or \"power\"" end
    if options == nil then return nil end
    if type(options) ~= "table" then return api .. "options must be a table" end
    local theme, level, name = options.theme, options.level, options.name
    if theme ~= nil and (type(theme) ~= "string" or Secret(theme)) then return api .. "options.theme must be a string" end
    if level ~= nil and (type(level) ~= "number" or Secret(level) or level ~= math.floor(level) or level < 0
        or level > External.MAX_LEVEL) then
        return api .. "options.level must be a whole number from 0 to " .. External.MAX_LEVEL
    end
    if options.mask ~= nil and not IsMaskTexture(options.mask) then return api .. "options.mask must be a MaskTexture" end
    if options.spill ~= nil and type(options.spill) ~= "boolean" then return api .. "options.spill must be true or false" end
    if name ~= nil and (type(name) ~= "string" or Secret(name)) then return api .. "options.name must be a string" end
end

-- One of our own bars (the game's, a preview's, a nameplate's): it has its liquid already.
local function OwnBar(bar)
    for spot, b in pairs(bars) do
        if b.bar == bar and not spot.external then return true end
    end
    for _, b in ipairs(previews) do
        if b.bar == bar then return true end
    end
    return plates[bar] ~= nil
end

local function Vertical(bar)
    local ok, orientation = pcall(bar.GetOrientation, bar)
    return ok and not Secret(orientation) and orientation == "VERTICAL"
end

-- Whether AddBar declines a bar whatever its options (before the settings have loaded too).
function Bars.Declined(bar, unit)
    return OwnBar(bar) or Vertical(bar) or (type(unit) == "string" and unit:lower():match("^nameplate")) and true
        or false
end

-- How many party and raid members' bars other addons have handed over and not removed.
function External.CountGroup()
    local n = 0
    for _, spot in pairs(externals) do
        if not spot.removed and spot.slow then n = n + 1 end
    end
    return n
end

-- The driver and the unit events, for a bar that goes live between Applies. Bars.Apply would also build the game's
-- party bars, which it does only out of combat.
function External.Wake()
    if not driver then
        driver = CreateFrame("Frame")
        driver:SetScript("OnUpdate", OnUpdate)
        driver:SetScript("OnEvent", OnEvent)
    end
    driver:Show()
    if not External.unitEvents then
        for _, event in ipairs(EVENTS) do driver:RegisterEvent(event) end
        External.unitEvents = true
    end
end

-- Off, the bar's own fill back, its spot kept for when it is added again.
function External.Drop(spot)
    spot.removed = true
    local b = bars[spot]
    SetLive(b, false)
    if b.fury then FuryOff(b) end
end

-- True when the bar is taken (it shows the liquid, or will once the player allows other addons' bars), false when it
-- is declined: vertical, one of this addon's own, a nameplate's, or past the cap on group members' bars. Calling it
-- again with the same arguments does nothing, so an addon can call it whenever it updates its frame.
function Bars.AddBar(bar, unit, kind, options)
    local bad = Bars.CheckAddBar(bar, unit, kind, options)
    if bad then error(bad, 2) end
    options = options or {}
    unit = unit:lower()
    if OwnBar(bar) then return false end
    local spot = externals[bar]
    local added = spot and not spot.removed
    -- The liquid only runs along a bar; a bar turned vertical since loses it.
    if Vertical(bar) or unit:match("^nameplate") then
        if added then External.Drop(spot) end
        return false
    end
    local theme = options.theme
    if theme ~= nil and theme ~= "settings" and theme ~= "game" and not ns.Themes.list[theme] then theme = nil end
    local level, spill, name = options.level or 1, options.spill and true or false, options.name
    local slow = (unit:match("^party") or unit:match("^raid")) and true or nil
    if slow and not (added and spot.slow) and External.CountGroup() >= External.MAX_GROUP then
        if added then External.Drop(spot) end
        return false
    end

    local ext = spot and spot.external
    if added and spot.unit == unit and spot.kind == kind and ext.theme == theme and ext.level == level
        and ext.spill == spill and ext.name == name and not bars[spot].err then
        return true
    end

    local b
    local new = not spot
    if new then
        spot = { key = "externalBars", optional = true, external = { mask = options.mask }, unit = unit, kind = kind }
        b = NewBar(spot, bar)
        bars[spot] = b
        externals[bar] = spot
        ext = spot.external
    else
        b = bars[spot]
    end
    local unitChanged = new or not added or spot.unit ~= unit or spot.kind ~= kind
    local themeChanged = new or ext.theme ~= theme
    local spillChanged = new or ext.spill ~= spill
    if not new and spot.kind ~= kind and b.fury then FuryOff(b) end
    ext.theme, ext.level, ext.spill, ext.name = theme, level, spill, name
    spot.unit, spot.kind, spot.removed, spot.slow = unit, kind, nil, slow
    b.unit, b.kind, b.err = unit, kind, nil
    spot.frame = External.FrameOf(unit)
    spot.label = (name or "addon") .. " " .. unit .. " " .. kind
    if spillChanged then
        b.spill = spill and SPILL or 0
        local ok, reverse = pcall(bar.GetReverseFill, bar)
        External.SetMirror(b, ok and not Secret(reverse) and reverse, true)
    end
    External.Raise(b)
    if unitChanged or themeChanged then
        b.colorIn = 0
        ApplyColor(b, true)
    end
    -- Before the player is in the world, Bars.Apply and HealMarker.Apply at login pick it up, in their usual order.
    if not ns.Core.ready then return true end
    -- A player's bar gets the heal marker (heals, bandages, food and drink pouring in), a target's health bar the DoT
    -- marker.
    if unit == "player" and unitChanged and ns.HealMarker then ns.HealMarker.Apply() end
    if unit == "target" and kind == "health" and unitChanged and ns.Marker then ns.Marker.Apply() end
    if not ns.Core.Get("externalBars") then return true end
    External.Wake()
    SetLive(b, true)
    if b.live and unitChanged then
        Feed(b, false)
        b.liquid:Snap(b.width)
        b.drawNow = true
    end
    return true
end

-- The bar back to its own fill. It can be added again later.
function Bars.RemoveBar(bar)
    local spot = externals[bar]
    if not spot or spot.removed then return false end
    External.Drop(spot)
    -- With no other addon's bar left showing, let Bars.Apply stop the driver and events if nothing else needs them.
    for _, other in pairs(externals) do
        if not other.removed and bars[other].live then return true end
    end
    if ns.Core.ready and not InCombatLockdown() then Bars.Apply() end
    return true
end

-- Whether an error on another addon's bar has been reported; with set, that it now has. One report a bar, whether it
-- came from adding it (SmoothAnimatedBars.lua) or from its update (RunBar).
function Bars.Reported(bar, set)
    local spot = externals[bar]
    local b = spot and bars[spot]
    if not b then return false end
    if set then b.reported = true end
    return b.reported or false
end

-- Whether the player allows other addons' bars (the externalBars setting).
function Bars.ExternalsAllowed()
    return ns.Core.Get("externalBars") and true or false
end

-- Another addon's bar, if added and not removed: its unit, kind, levels above the bar, mask and whether it fills from
-- the right (for the heal marker on it, HealMarker.lua).
function Bars.External(bar)
    local spot = externals[bar]
    if not spot or spot.removed then return nil end
    local ext, b = spot.external, bars[spot]
    return spot.unit, spot.kind, ext.level or 1, b.mask, b.mirror or false
end

-- The secret colour another addon's bar shows through its tint, as { r, g, b }, or nil when its colour is readable or
-- not its own (the heal marker's seam takes it, HealMarker.lua).
function Bars.SecretColor(bar)
    local spot = externals[bar]
    local b = spot and bars[spot]
    return b and b.fromGame and b.plateSecret or nil
end

-- The other addons' bars added for a unit and kind, in no particular order (the mana build-up's, ManaRule.lua).
function Bars.ExternalBars(unit, kind)
    local out = {}
    for bar, spot in pairs(externals) do
        if not spot.removed and spot.unit == unit and spot.kind == kind then out[#out + 1] = bar end
    end
    return out
end

-- Whether another addon's bar has been handed to us and not removed.
function Bars.HasBar(bar)
    local spot = externals[bar]
    return spot ~= nil and not spot.removed
end

-- A region's width and height, or the fallbacks while the client keeps them secret (for the markers).
Bars.Size = Size

-- How a bar can be seen ("shown", "hidden" or "faded"; see Sight), for the markers: as UpdateBar found it this frame
-- when the bar has a live liquid, else asked now.
function Bars.Sight(bar)
    local b = StateFor(bar)
    if b and b.live and b.sight then return b.sight end
    return Sight(bar)
end

-- The Liquid on a bar, if it has one (the heal marker's seam follows its front; also for the tests).
function Bars.Liquid(bar)
    local b = StateFor(bar)
    return b and b.liquid
end

-- The fury's liquid on a rage bar, once built.
function Bars.FuryLiquid(bar)
    local b = StateFor(bar)
    return b and b.fury and b.fury.liquid
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
    Each(function(b)
        b.liquid:ApplyOptions()
        if b.fury then b.fury.liquid:ApplyOptions() end
    end)
end

local function YesNo(v) return v and "yes" or "no" end

-- Everything that decides whether a bar shows the liquid, for /sab debug.
function Bars.Debug()
    local out = { "smoothing: " .. YesNo(INTERPOLATION) }
    for _, spot in ipairs(SPOTS) do
        local b = bars[spot]
        local label = (spot.label or ((b and b.unit or spot.unit) .. " " .. spot.kind))
            .. (b and b.away and " (offline)" or "")
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
                label, name, math.floor(b.width + 0.5), math.floor(b.height + 0.5),
                -- Hidden and faded out told apart: a frame hidden by the game or reparented, or one another addon faded.
                ({ shown = "yes", hidden = "no", faded = "no (faded out)" })[Sight(bar)],
                YesNo(Secret(bar:GetValue())), YesNo(b.mask), YesNo(b.live),
                fill and (Secret(fill:GetAlpha()) and "secret" or tostring(fill:GetAlpha())) or "none", shown, #b.liquid.textures,
                b.err and (", error: " .. b.err) or "")
        end
    end
    -- Other addons' bars (SmoothAnimatedBars.AddBar).
    local listed = 0
    for bar, spot in pairs(externals) do
        local b = bars[spot]
        listed = listed + 1
        out[#out + 1] = string.format("%s (other addon's, %dx%d): %s, live %s, level +%d, %s%s%s", spot.label,
            math.floor(b.width + 0.5), math.floor(b.height + 0.5), spot.removed and "removed" or "added", YesNo(b.live),
            spot.external.level or 1, b.mirror and "fills from the right" or "fills from the left",
            b.plateSecret and ", colour secret" or "", b.err and (", error: " .. b.err) or "")
    end
    out[#out + 1] = string.format("other addons' bars: %s, %d handed over", ns.Core.Get("externalBars") and "allowed"
        or "off", listed)
    out[#out + 1] = string.format("rage fury: %s, curves %s", ns.Core.Get("rageFury") and "on" or "off",
        YesNo(Curves()))
    out[#out + 1] = string.format("enemy nameplates: %s, %d with the liquid (at most %d); friendly: %s, %d (at most %d); "
        .. "%d built, %d waiting", ns.Core.Get("plateHealth") and "on" or "off", CountSide("enemy"), MAX_PLATES,
        ns.Core.Get("plateFriendly") and "on" or "off", CountSide("friend"), MAX_FRIENDLY, Count(plates), Count(pending))
    return out
end

--------------------------------------------------------------------------------
-- Party frames (/sab party)
--------------------------------------------------------------------------------

-- /sab party reports what the game lets the addon read about the party frames, the liquid on them aside: PartyFrame (Blizzard_UnitFrame/Shared/PartyFrame.lua) keeps a pool of four PartyMemberFrameTemplate
-- buttons, named MemberFrame1..4 by their place each time it is shown. Each has HealthBarContainer.HealthBar, its mask
-- on the container as on the player's, and ManaBar, its mask on the bar, and its unit in .unit, which the game changes
-- (the pet's token in a vehicle, "player" in Edit Mode's preview). Raid-style party frames are CompactPartyFrame's,
-- CompactUnitFrames with flat bars. Only widgets are asked, nothing of the game's own Lua is called.

local function Show(v)
    if Secret(v) then return "secret" end
    if type(v) == "number" then return string.format("%.4g", v) end
    return tostring(v)
end

local function Pack(...) return { n = select("#", ...), ... } end

-- What fn answers, every value through Show: "none" if there is no such function, "error" if it throws.
local function Ask(fn, ...)
    if type(fn) ~= "function" then return "none" end
    local r = Pack(pcall(fn, ...))
    if not r[1] then return "error" end
    local parts = {}
    for i = 2, r.n do parts[#parts + 1] = Show(r[i]) end
    return #parts > 0 and table.concat(parts, " ") or "nothing"
end

local function Call(obj, method, ...)
    if type(obj) ~= "table" then return "none" end
    return Ask(obj[method], obj, ...)
end

local function Has(v) return type(v) == "table" and "yes" or "no" end

local function BarReport(label, bar, kind)
    if type(bar) ~= "table" or not bar.GetValue then return label .. ": not found" end
    local okFill, fill = pcall(bar.GetStatusBarTexture, bar)
    local okMask, mask = pcall(BarMask, bar, kind)
    local line = string.format("%s (%s): liquid %s, size %s x %s, value %s, range %s, colour %s, level %s, visible %s, "
        .. "mask %s, fill alpha %s, bar.unit %s", label, Call(bar, "GetDebugName"), YesNo(Bars.IsLive(bar)),
        Call(bar, "GetWidth"), Call(bar, "GetHeight"),
        Call(bar, "GetValue"), Call(bar, "GetMinMaxValues"), Call(bar, "GetStatusBarColor"), Call(bar, "GetFrameLevel"),
        Call(bar, "IsVisible"), okMask and (mask and "yes" or "no") or "error", okFill and Call(fill, "GetAlpha") or "error",
        Show(bar.unit))
    if kind == "health" then
        line = line .. string.format(", heal prediction mine %s others %s, temp max loss %s, loss bar %s",
            Has(bar.MyHealPredictionBar), Has(bar.OtherHealPredictionBar), Has(Path(bar:GetParent(), "TempMaxHealthLoss")),
            Has(bar.AnimatedLossBar))
    end
    return line
end

-- What the game says of a unit; nothing is compared, so secret answers show as "secret".
local function UnitReport(unit)
    return string.format("exists %s, connected %s, player %s, class %s, power type %s, health %s of %s, can attack %s",
        Ask(rawget(_G, "UnitExists"), unit), Ask(rawget(_G, "UnitIsConnected"), unit), Ask(rawget(_G, "UnitIsPlayer"), unit),
        Ask(rawget(_G, "UnitClass"), unit), Ask(rawget(_G, "UnitPowerType"), unit), Ask(rawget(_G, "UnitHealth"), unit),
        Ask(rawget(_G, "UnitHealthMax"), unit), Ask(rawget(_G, "UnitCanAttack"), "player", unit))
end

-- Where a region sits in a member frame: "x,y wxh" from the frame's top-left (y down), with its atlas; for matching the
-- gallery's party art (/sab capture party) to the game's own layout. "?" where the client will not say.
local function Placed(region, frame)
    if type(region) ~= "table" or not region.GetLeft then return "none" end
    local ok, l, t, fl, ft, w, h = pcall(function()
        return region:GetLeft(), region:GetTop(), frame:GetLeft(), frame:GetTop(), region:GetWidth(), region:GetHeight()
    end)
    local atlas = region.GetAtlas and select(2, pcall(region.GetAtlas, region)) or nil
    local where = "?"
    if ok and type(l) == "number" and type(fl) == "number" and not Secret(l) and not Secret(t) and not Secret(fl)
        and not Secret(ft) and not Secret(w) and not Secret(h) then
        where = string.format("%.1f,%.1f %.1fx%.1f", l - fl, ft - t, w, h)
    end
    return where .. (type(atlas) == "string" and (" " .. atlas) or "")
end

local function MemberReport(out, label, frame, health, power)
    out[#out + 1] = string.format("  layout: art %s; health %s, its mask %s; power %s, its mask %s",
        Placed(frame.Texture, frame), Placed(Path(frame, "HealthBarContainer"), frame),
        Placed(Path(frame, "HealthBarContainer", "HealthBarMask"), frame), Placed(frame.ManaBar, frame),
        Placed(Path(frame, "ManaBar", "ManaBarMask"), frame))
    out[#out + 1] = string.format("%s: shown %s, visible %s, layoutIndex %s, unit %s, unitToken %s, overrideUnit %s, "
        .. "displayedUnit %s", label, Call(frame, "IsShown"), Call(frame, "IsVisible"), Show(frame.layoutIndex),
        Show(frame.unit), Show(frame.unitToken), Show(frame.overrideUnit), Show(frame.displayedUnit))
    local unit = frame.unit
    if type(unit) == "string" and not Secret(unit) then out[#out + 1] = "  " .. unit .. ": " .. UnitReport(unit) end
    out[#out + 1] = "  " .. BarReport("health", health, "health")
    out[#out + 1] = "  " .. BarReport("power", power, "power")
end

function Bars.PartyDebug()
    local out = {}
    out[#out + 1] = string.format("in group %s, members %s, in combat %s", Ask(rawget(_G, "IsInGroup")),
        Ask(rawget(_G, "GetNumSubgroupMembers")), Ask(rawget(_G, "InCombatLockdown")))
    local party = rawget(_G, "PartyFrame")
    out[#out + 1] = "PartyFrame: " .. (type(party) == "table"
        and string.format("shown %s, visible %s", Call(party, "IsShown"), Call(party, "IsVisible")) or "none")
    if type(party) == "table" then
        for i = 1, 4 do
            local f = party["MemberFrame" .. i]
            if type(f) == "table" then
                MemberReport(out, "MemberFrame" .. i, f, Path(f, "HealthBarContainer", "HealthBar"), f.ManaBar)
                out[#out + 1] = "  pet " .. BarReport("health", Path(f, "PetFrame", "HealthBar"), "health")
            else
                out[#out + 1] = "MemberFrame" .. i .. ": none"
            end
        end
    end
    local compact = rawget(_G, "CompactPartyFrame")
    out[#out + 1] = "CompactPartyFrame (raid-style): " .. (type(compact) == "table"
        and string.format("shown %s, visible %s", Call(compact, "IsShown"), Call(compact, "IsVisible")) or "none")
    if type(compact) == "table" then
        for i = 1, 5 do
            local f = rawget(_G, "CompactPartyFrameMember" .. i) or Path(compact, "memberUnitFrames", i)
            if type(f) == "table" then MemberReport(out, "CompactPartyFrameMember" .. i, f, f.healthBar, f.powerBar) end
        end
    end
    local seen = {}
    for event, n in pairs(partyEvents) do seen[#seen + 1] = event .. " " .. n end
    table.sort(seen)
    out[#out + 1] = "events for party units since /reload: " .. (#seen > 0 and table.concat(seen, ", ") or "none")
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
    -- Of which: the display's and the party's, where there were any.
    for _, group in ipairs({ { "prd", "  of which the Personal Resource Display" }, { "party", "  of which the party" },
                          { "addon", "  of which other addons' bars" } }) do
        local g, label = group[1], group[2]
        local ms, n = 0, 0
        for _, s in ipairs(perf.done) do ms, n = ms + (s[g .. "Ms"] or 0), math.max(n, s[g] or 0) end
        if n > 0 then out[#out + 1] = Line(label, ms, n) end
    end
    out[#out + 1] = Line("nameplates", plateMs, platesLive)
    if platesLive > 0 then
        out[#out + 1] = string.format("  that is %.3f ms a frame per nameplate", plateMs / frames / platesLive)
    end
    -- The costliest unit frame bars, each with its fury's share (party members' bars by their unit).
    local byBar = {}
    for _, s in ipairs(perf.done) do
        for label, e in pairs(s.bars or {}) do
            local t = byBar[label] or { label = label, ms = 0, fury = 0 }
            t.ms, t.fury = t.ms + e.ms, t.fury + e.fury
            byBar[label] = t
        end
    end
    local list = {}
    for _, t in pairs(byBar) do list[#list + 1] = t end
    table.sort(list, function(a, b) return a.ms > b.ms end)
    for i = 1, math.min(6, #list) do
        local t = list[i]
        out[#out + 1] = string.format("  %s: %.3f ms a frame%s", t.label, t.ms / frames,
            t.fury > 0 and string.format(" (its rage fury %.3f)", t.fury / frames) or "")
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
                       plates = s.plates, prdMs = s.prdMs, prd = s.prd, partyMs = s.partyMs, party = s.party,
                       addonMs = s.addonMs, addon = s.addon, bars = s.bars }
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
