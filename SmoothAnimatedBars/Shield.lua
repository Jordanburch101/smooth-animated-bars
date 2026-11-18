-- The shield on the player frame's health bar (the shield setting): while an absorb is on the player (Power Word:
-- Shield, or any other), the last stretch of the health, as much as the shield will soak, turns into a barrier of light:
-- dark-gold glass with god rays and strands of light drifting through it, brightening toward a curved, crackling rim on
-- the health's front. A hit it soaks makes the rim flare and throw sparks, and when it breaks it shatters and the health
-- liquid flows back up to its front.
--
-- It is laid out as the DoT marker is (Marker.lua), as part of the health liquid: the health liquid ends where the shield
-- starts. Earlier builds, each seen in game: a wall of light past the health's front, where the game draws absorbs (it
-- read as an incoming heal); see-through glass over the health's end (the green showed through); and a golden liquid of
-- its own (the marker's way; in game its added light washed to cream, and lifting the health liquid a level over it, as
-- the marker does on the target, hid the player bar's text). The shield's size is secret, as health is, so the client
-- does every comparison:
--   * a hidden StatusBar of ours takes the game bar's (secret) value, so its fill ends where the health does;
--   * the game's heal prediction calculator (CreateUnitHealPredictionCalculator, UnitGetDetailedHealPrediction) gives
--     the shield, capped to the whole bar. A hidden "run" bar a bar wide, its right edge on the health's front, fills
--     from the right with it: its fill's left edge is where the shield starts. More shield than health runs past the
--     bar's left end, where the mask cuts it;
--   * the health liquid's front is moved onto the shield's start (Bars.Front). The shield is drawn in a pool from there
--     to the bar's end, cut by the bar's mask, laid out from the health's front (the mover), at the bar's level under
--     the game's text. Its glass is opaque, so its colour is its own whatever the health's.
-- Every layer is alpha blended, none added: the game draws added light stronger than the gallery's renderer, and
-- blended, the two agree. In game the shield first drew as a flat white, then cream, block: each layer's strength was a
-- vertex alpha that SetAlpha then overwrote (a texture has one alpha; see Tint). Judge the look at the game's size (about 1.3 px a unit), not the
-- gallery's 3: a rim or strands under a pixel wide vanish.
-- Whether there is a shield (shown, and its going up and breaking) is the game's own answer, read from its absorb bar
-- and glow (shown or not), readable on Forever (seen in game with /sab shield). Where they are secret, it shows for a
-- while after the player's own Power Word: Shield on themselves. A hit the shield soaked is UNIT_COMBAT's ABSORB on the player, whose
-- amount is secret but whose action is not. Nothing of the game's is changed but alphas: its own absorb fill and glow
-- show the same shield, so they are transparent while ours shows.

local _, ns = ...

local Shield = {}
ns.Shield = Shield

local MEDIA = "Interface\\AddOns\\SmoothAnimatedBars\\Media\\"
local FEED_EVERY = 0.05   -- seconds between reading the shield
local SPILL = 16          -- as Bars.lua: how far sparks fly above, below and past the end
-- How a shield ends, however it goes (broken, run out or taken off): it shatters. The glass strains (cracks, whitening,
-- a tremble) for SHATTER.strain, bursts into shards, and is gone by SHATTER.done, holding its last place (the ghost bar)
-- while the health flows up into it beneath: faded while the health was still flowing up, the empty bar showed between
-- them (seen in game). A shield that ran out or was taken off once dissolved instead (the glass brightening, then
-- fading out among rising lights); it was not liked, and the shatter was asked for every time.
local SHATTER = { strain = 0.28, gone = 0.15, wave = 0.6, done = 1.4 }
local SHARDS, STREAKS = 90, 60
-- Shards burst from the rim too, from RIM_BURST back, whatever the shield's size: from the glass alone, a nearly spent
-- shield (a sliver) threw almost none and its end was lost (seen in game).
local RIM_SHARDS, RIM_BURST = 26, 16
local CAST_SHOWS = 30     -- where the game will not say: seconds a shield shows after the player's own
local RIM_INSET = 3       -- how far behind the health's front the rim stands (the bar's mask ends about that far short)
local RIM_W = 14          -- the rim texture's width; its line is RIM_LINE across it (make_media.py)
local RIM_LINE = 0.70
local GLOW_W = 26         -- the halo around the rim
local NEAR_W = 26         -- the brighter sheen nearest the rim
local CRACKLE_FRAMES, CRACKLE_EVERY, CRACKLE_ALPHA = 4, 0.07, 0.45
local EDGE_SPAN = 16      -- ShieldEdge.tga is this many rim widths across, its crescent in the last (make_media.py)
local SPILL_W = 18        -- how far the shield's light reaches back over the health liquid
local SPILL_ALPHA = 0.55
local FADE_W, LEAD = 7, 3 -- the shield's body fades in over FADE_W, from LEAD back over the health's end, so the
                          -- health's waves show lapping into it. A band of a set colour before the body instead (a
                          -- clouding glass) showed as a strip with a step where the body began, in game, its colour
                          -- never quite the body's.
local FADE_SPAN = 32      -- ShieldFade.tga is this many fade widths across, its ramp in the first (make_media.py)
local SHEEN_ALPHA = 0.16  -- the warm sheen over the dark glass
local LAP_EVERY = 1.8     -- about how often the shield laps at the health's front, seconds
local LAP_KICK = 10       -- how hard (Liquid:Nudge; 45 every 0.8 s kept the health sloshing when idle, seen in game);
local PUSH_KICK = 50      -- a soaked hit pushes harder
local MOTES, SPARKS = 18, 48
local BEAMS, BEAM_LEN, BEAM_ALPHA = 6, 28, 0.6 -- god rays shed past the bar, out from the rim
local EMBER_EVERY = 0.22  -- seconds between the embers that drift off the rim while the shield holds
local MOTE_SPAN = 50      -- motes are born this far back from the rim (the shield is mostly short)

-- Colours, as in the mock the look was chosen from (white-hot core, gold glow, warm sheen on dark glass).
local CORE   = { 1.00, 1.00, 0.96 }
local GLOW   = { 1.00, 0.86, 0.52 }
local SHEEN  = { 1.00, 0.84, 0.50 }
local GLASS  = { 0.12, 0.09, 0.08 } -- the empty bar's own dark, measured on the captured frame art
local RAY    = { 1.00, 0.92, 0.72 }
local STRAND = { 1.00, 0.90, 0.62 }
local MOTE   = { 1.00, 0.95, 0.80 }
local SPARK  = { 1.00, 0.93, 0.74 }

local INTERPOLATION = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut
local CLAMP = Enum and Enum.UnitDamageAbsorbClampMode
local CLAMP_MAX = CLAMP and CLAMP.MaximumHealth or 2

local function Secret(v)
    return issecretvalue and issecretvalue(v) or false
end

local function Rand(a, b) return a + (b - a) * math.random() end

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
    AtParentLevel(bar, parent)
    local fill = bar:CreateTexture(nil, "BACKGROUND")
    fill:SetColorTexture(1, 1, 1, 1)
    bar:SetStatusBarTexture(fill)
    bar:GetStatusBarTexture():SetAlpha(0)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    return bar
end

local function MaskOf(bar)
    local mask = bar.HealthBarMask or bar:GetParent().HealthBarMask
    if type(mask) == "table" and mask.GetObjectType and mask:GetObjectType() == "MaskTexture" then return mask end
end

local function NewCalculator(mode)
    if not CreateUnitHealPredictionCalculator then return nil end
    local ok, calc = pcall(CreateUnitHealPredictionCalculator)
    if not ok or not calc then return nil end
    pcall(calc.SetDamageAbsorbClampMode, calc, mode)
    return calc
end

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------

local function Tex(frame, sublevel, file, blend, mask, wrap)
    local t = frame:CreateTexture(nil, "OVERLAY", nil, sublevel)
    if file and wrap then
        t:SetTexture(MEDIA .. file, wrap, wrap)
    elseif file then
        t:SetTexture(MEDIA .. file)
    else
        t:SetColorTexture(1, 1, 1, 1)
    end
    t:SetBlendMode(blend or "BLEND")
    if mask then t:AddMaskTexture(mask) end
    if t.SetSnapToPixelGrid then
        t:SetSnapToPixelGrid(false)
        t:SetTexelSnappingBias(0)
    end
    return t
end

-- A layer's colour and strength. The client keeps one alpha for a texture: SetVertexColor's fourth value and SetAlpha
-- set the same thing (in game the sheen's 0.16 became 1 when it was faded in, an opaque cream block over the glass; the
-- harness had multiplied them). So colours go in without alpha, strengths through SetAlpha, and the whole shield
-- fades by its mover's alpha (a frame's, which does multiply).
local function Tint(t, c, alpha)
    t:SetVertexColor(c[1], c[2], c[3])
    t:SetAlpha(alpha)
end

local function New(bar)
    local w, h = ns.Bars.Size(bar, 124, 20)
    local mask = MaskOf(bar)
    local m = { bar = bar, mask = mask, width = w, height = h, feed = FEED_EVERY, t = 0, castUntil = 0,
                flare = 0, flash = 0, push = 0, fade = 1, motes = {}, sparks = {} }
    m.calc = NewCalculator(CLAMP_MAX)

    -- Where the health ends, with the client's smoothing.
    m.proxy = HiddenBar(bar)
    m.proxy:SetAllPoints(bar)
    local edge = m.proxy:GetStatusBarTexture()

    -- From the bar's left edge, with room for the sparks above, below and past the end (as the marker's clip).
    m.clip = CreateFrame("Frame", nil, bar)
    AtParentLevel(m.clip, bar)
    m.clip:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, SPILL)
    m.clip:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", SPILL, -SPILL)
    m.clip:SetClipsChildren(true)
    m.clip:Hide()

    -- The shield, back from the rim (RIM_INSET short of the health's front): its fill's left edge is where the shield
    -- starts, and the health liquid's front. Measured from the health's front, a shield smaller than the inset started
    -- past the rim, and the health ran on past the shield (seen in game); from the rim, the health never passes it, and
    -- the least of shields keeps its rim. As the shield ends the run's inset goes back to nothing (RunInset) once the
    -- glass is gone, so the health reaches its front.
    m.run = HiddenBar(m.clip)
    m.run:SetReverseFill(true)
    m.run:SetPoint("TOPRIGHT", edge, "TOPRIGHT", -RIM_INSET, 0)
    m.run:SetPoint("BOTTOMRIGHT", edge, "BOTTOMRIGHT", -RIM_INSET, 0)
    m.run:SetWidth(w)
    m.inset = RIM_INSET
    m.start = m.run:GetStatusBarTexture()
    -- The same, held at its last size while the shield ends (Feed stops feeding it), so the glass keeps its place while
    -- the run drains and the health flows up beneath it. The body is laid from here; the health's front from m.start.
    m.ghost = HiddenBar(m.clip)
    m.ghost:SetReverseFill(true)
    m.ghost:SetPoint("TOPRIGHT", edge, "TOPRIGHT", -RIM_INSET, 0)
    m.ghost:SetPoint("BOTTOMRIGHT", edge, "BOTTOMRIGHT", -RIM_INSET, 0)
    m.ghost:SetWidth(w)
    m.hold = m.ghost:GetStatusBarTexture()

    -- The shield's pool, from its start; everything in it laid out from the health's front (the mover's right edge).
    m.pool = CreateFrame("Frame", nil, m.clip)
    AtParentLevel(m.pool, m.clip)
    m.pool:SetPoint("TOPLEFT", m.hold, "TOPLEFT", -LEAD, SPILL) -- from where it starts fading in (m.fadeIn)
    m.pool:SetPoint("BOTTOMRIGHT", m.clip, "BOTTOMRIGHT")
    m.pool:SetClipsChildren(true)
    m.mover = CreateFrame("Frame", nil, m.pool)
    AtParentLevel(m.mover, m.pool)
    m.mover:SetPoint("TOPRIGHT", edge, "TOPRIGHT")
    m.mover:SetPoint("BOTTOMRIGHT", edge, "BOTTOMRIGHT")
    m.mover:SetWidth(w)
    local mv = m.mover

    -- The body ends on the rim's crescent, not in a straight cut past it (seen in game: the glass and strands ran on
    -- past the rim's bowed top and bottom). The mask lies left of the rim's own right edge, EDGE_SPAN rims wide.
    m.edge = mv:CreateMaskTexture()
    m.edge:SetTexture(MEDIA .. "ShieldEdge", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    local rimRight = -RIM_INSET + (1 - RIM_LINE) * RIM_W
    m.edge:SetPoint("TOPRIGHT", mv, "TOPRIGHT", rimRight, 0)
    m.edge:SetPoint("BOTTOMRIGHT", mv, "BOTTOMRIGHT", rimRight, 0)
    m.edge:SetWidth(RIM_W * EDGE_SPAN)

    -- The body fades in from its back over the health's end (FADE_W from LEAD back), every layer at once, so it comes
    -- in with nothing of its own colour to match and no straight edge: the mask lies from there right, FADE_SPAN fades
    -- wide, its ramp in the first. The health liquid's front is on the shield's start itself, inside the fade, so its
    -- waves are seen lapping into the barrier (an opaque glass from the start hid them: in game the health ended stick
    -- straight and still); set past the start, it ran past the real health as the shield drained, and at full health
    -- the whole liquid slid right, leaving a gap at the bar's left end (seen in game).
    m.fadeIn = mv:CreateMaskTexture()
    m.fadeIn:SetTexture(MEDIA .. "ShieldFade", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    m.fadeIn:SetPoint("TOPLEFT", m.hold, "TOPLEFT", -LEAD, 0)
    m.fadeIn:SetPoint("BOTTOMLEFT", m.hold, "BOTTOMLEFT", -LEAD, 0)
    m.fadeIn:SetWidth(FADE_W * FADE_SPAN)

    -- Opaque dark glass, so the shield is its own colour whatever lies under it (see-through, the green showed
    -- through the gold), then a warm sheen, brighter toward the rim.
    m.glass = Tex(mv, -8, nil, "BLEND", mask)
    m.glass:SetAllPoints(mv)
    Tint(m.glass, GLASS, 1)
    m.sheen = Tex(mv, -7, nil, "BLEND", mask)
    m.sheen:SetAllPoints(mv)
    Tint(m.sheen, SHEEN, SHEEN_ALPHA)

    m.near = Tex(mv, -7, nil, "BLEND", mask)
    m.near:SetPoint("TOPRIGHT", mv, "TOPRIGHT", -RIM_INSET, 0)
    m.near:SetPoint("BOTTOMRIGHT", mv, "BOTTOMRIGHT", -RIM_INSET, 0)
    m.near:SetWidth(NEAR_W)
    m.near:SetGradient("HORIZONTAL", CreateColor(SHEEN[1], SHEEN[2], SHEEN[3], 0),
        CreateColor(SHEEN[1], SHEEN[2], SHEEN[3], 0.55))
    m.rays = {}
    for i = 1, 4 do
        local r = { tex = Tex(mv, -6, "Ray", "BLEND", mask), at = math.random() * (w + 40), speed = 4 + 5 * math.random(),
                    width = 8 + 6 * math.random(), alpha = 0.08 + 0.08 * math.random() }
        Tint(r.tex, RAY, r.alpha)
        r.tex:SetSize(r.width, h)
        m.rays[i] = r
    end
    m.strandsA = Tex(mv, -5, "Strands", "BLEND", mask, "REPEAT")
    m.strandsA:SetAllPoints(mv)
    Tint(m.strandsA, STRAND, 0.90)
    m.strandsB = Tex(mv, -5, "Strands", "BLEND", mask, "REPEAT")
    m.strandsB:SetAllPoints(mv)
    Tint(m.strandsB, STRAND, 0.45)

    -- The rim: a halo, the crescent, a second crescent for flares and the crackling filament, its line RIM_INSET in.
    local function AtRim(t, width)
        local x = -RIM_INSET + (1 - RIM_LINE) * width
        t:SetPoint("TOPRIGHT", mv, "TOPRIGHT", x, 0)
        t:SetPoint("BOTTOMRIGHT", mv, "BOTTOMRIGHT", x, 0)
        t:SetWidth(width)
    end
    m.halo = Tex(mv, -4, "Glow", "BLEND", mask)
    m.halo:SetPoint("CENTER", mv, "RIGHT", -RIM_INSET, 0)
    m.halo:SetSize(GLOW_W, h * 1.6)
    Tint(m.halo, GLOW, 0.35)
    m.rim = Tex(mv, -3, "Rim", "BLEND", mask)
    AtRim(m.rim, RIM_W)
    Tint(m.rim, CORE, 1)
    m.rimFlare = Tex(mv, -3, "Rim", "BLEND", mask)
    AtRim(m.rimFlare, RIM_W * 1.2)
    Tint(m.rimFlare, GLOW, 0)
    m.crackle = Tex(mv, -2, "RimCrackle", "BLEND", mask)
    AtRim(m.crackle, RIM_W)
    Tint(m.crackle, CORE, CRACKLE_ALPHA)

    -- Motes drifting in the shield, cut to it.
    for i = 1, MOTES do
        local t = Tex(mv, -2, "Mote", "BLEND", mask)
        t:Hide()
        m.motes[i] = { tex = t, life = 0, age = 1 }
    end
    -- A shattering shield's strain: glowing cracks spreading through the glass as it whitens. Shown only then.
    m.cracks = Tex(mv, -4, "Cracks", "BLEND", mask, "REPEAT")
    m.cracks:SetAllPoints(mv)
    m.cracks:SetTexCoord(0, w * 2.5 / 256, 0, 1) -- about its own size, as the strands are: stretched, it blurred
    Tint(m.cracks, CORE, 0)
    m.cracks:Hide()
    m.whiten = Tex(mv, -4, nil, "BLEND", mask)
    m.whiten:SetAllPoints(mv)
    Tint(m.whiten, GLOW, 0)
    m.whiten:Hide()
    local body = { m.glass, m.sheen, m.near, m.strandsA, m.strandsB, m.halo, m.cracks, m.whiten }
    for _, r in ipairs(m.rays) do body[#body + 1] = r.tex end
    for _, q in ipairs(m.motes) do body[#body + 1] = q.tex end
    for _, t in ipairs(body) do
        t:AddMaskTexture(m.edge)
        t:AddMaskTexture(m.fadeIn)
    end

    -- Where the health liquid meets the shield: the shield's light spills back over the health's last stretch, flaring
    -- when a hit is soaked, so the barrier is seen holding the health. Outside the pool (which starts at the shield),
    -- laid from the shield's start; faded through their frame. A mirrored crescent once stood where the glass turns
    -- opaque, the barrier's back face; in game it read as a stray C beside the health.
    m.contact = CreateFrame("Frame", nil, m.clip)
    AtParentLevel(m.contact, m.clip)
    m.contact:SetAllPoints(m.clip)
    -- The spill swells over the health's last stretch to where the body starts fading in, then fades out as the body
    -- comes in, so it has no edge anywhere: stopping at the shield's start, its brightest edge drew a straight line over
    -- the green, and running on to the body at its brightest, a step. It breathes and flares in a frame of its own.
    m.glow = CreateFrame("Frame", nil, m.contact)
    AtParentLevel(m.glow, m.contact)
    m.glow:SetAllPoints(m.contact)
    m.spill = Tex(m.glow, -6, nil, "BLEND", mask)
    m.spill:SetPoint("TOPRIGHT", m.start, "TOPLEFT", -LEAD, 0)
    m.spill:SetPoint("BOTTOMRIGHT", m.start, "BOTTOMLEFT", -LEAD, 0)
    m.spill:SetWidth(SPILL_W)
    m.spill:SetGradient("HORIZONTAL", CreateColor(SHEEN[1], SHEEN[2], SHEEN[3], 0),
        CreateColor(SHEEN[1], SHEEN[2], SHEEN[3], SPILL_ALPHA))
    m.spillOut = Tex(m.glow, -6, nil, "BLEND", mask)
    m.spillOut:SetPoint("TOPLEFT", m.start, "TOPLEFT", -LEAD, 0)
    m.spillOut:SetPoint("BOTTOMLEFT", m.start, "BOTTOMLEFT", -LEAD, 0)
    m.spillOut:SetWidth(FADE_W)
    m.spillOut:SetGradient("HORIZONTAL", CreateColor(SHEEN[1], SHEEN[2], SHEEN[3], SPILL_ALPHA),
        CreateColor(SHEEN[1], SHEEN[2], SHEEN[3], 0))

    -- Sparks and shards fly free of the shield and the mask, as the liquid's motes do: cut only to SPILL around the
    -- bar, from a point on the rim.
    m.origin = CreateFrame("Frame", nil, m.clip)
    AtParentLevel(m.origin, m.clip)
    m.origin:SetPoint("TOPRIGHT", edge, "TOPRIGHT", -RIM_INSET, 0)
    m.origin:SetPoint("BOTTOMRIGHT", edge, "BOTTOMRIGHT", -RIM_INSET, 0)
    m.origin:SetWidth(1)
    for i = 1, SPARKS do
        local t = Tex(m.origin, -3, "Spark", "BLEND")
        t:Hide()
        m.sparks[i] = { tex = t, life = 0, age = 1 }
    end
    m.rimShards = {}
    for i = 1, RIM_SHARDS do
        local t = Tex(m.origin, -3, "Shard", "BLEND")
        t:Hide()
        m.rimShards[i] = { tex = t, life = 0, age = 1 }
    end

    -- God rays the shield sheds past the bar: shafts from the rim's middle, fanned from straight up round to straight
    -- down, each coming and going on its own slow beat. Square, so SetRotation (inside the square) can aim them; free of
    -- the bar's mask and of any clipping (cut to SPILL around the bar, as the sparks are, they ended in a hard box), so
    -- they fade out on their own. Shown with the shield and faded with it through their frame.
    m.shed = CreateFrame("Frame", nil, bar)
    AtParentLevel(m.shed, bar)
    m.shed:SetAllPoints(m.origin)
    m.shed:Hide()
    m.beams = {}
    for i = 1, BEAMS do
        local tex = Tex(m.shed, -5, "Beam", "BLEND")
        tex:SetPoint("CENTER", m.origin, "CENTER")
        local len = Rand(BEAM_LEN * 0.7, BEAM_LEN * 1.15)
        tex:SetSize(2 * len, 2 * len)
        Tint(tex, RAY, 0)
        -- Spread from just short of straight up (-0.25) to just short of straight down (-pi + 0.25), out past the rim.
        local share = (i - 0.5) / BEAMS
        m.beams[i] = { tex = tex, angle = -0.25 - share * (math.pi - 0.5) + Rand(-0.12, 0.12),
                       phase = Rand(0, 2 * math.pi), speed = Rand(0.5, 1.1), sway = Rand(0.4, 0.8) }
    end

    -- How it ends (SHATTER): in a frame laid out as the body is but faded on its own, so what bursts from the glass
    -- starts where the glass was. Spawned along a whole bar back from the rim, a mask of the body's
    -- fade-in (but SPILL taller, for what flies up and down) keeps only those over the shield, so a bigger shield
    -- throws more, and fades out softly any that fly back over the health: in the pool, they were cut there in a hard
    -- line. Free of the bar's mask, to fly off.
    m.burst = CreateFrame("Frame", nil, m.clip)
    AtParentLevel(m.burst, m.clip)
    m.burst:SetPoint("TOPRIGHT", edge, "TOPRIGHT")
    m.burst:SetPoint("BOTTOMRIGHT", edge, "BOTTOMRIGHT")
    m.burst:SetWidth(w)
    m.burstFade = m.burst:CreateMaskTexture()
    m.burstFade:SetTexture(MEDIA .. "ShieldFade", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    m.burstFade:SetPoint("TOPLEFT", m.hold, "TOPLEFT", -LEAD, SPILL)
    m.burstFade:SetPoint("BOTTOMLEFT", m.hold, "BOTTOMLEFT", -LEAD, -SPILL)
    m.burstFade:SetWidth(FADE_W * FADE_SPAN)
    m.shards, m.streaks = {}, {}
    for i = 1, SHARDS do
        local t = Tex(m.burst, -1, "Shard", "BLEND", m.burstFade)
        t:Hide()
        m.shards[i] = { tex = t, life = 0, age = 1 }
    end
    for i = 1, STREAKS do
        local t = Tex(m.burst, -1, "Spark", "BLEND", m.burstFade)
        t:Hide()
        m.streaks[i] = { tex = t, life = 0, age = 1 }
    end
    -- The shockwave off the rim as it bursts, free of every clip.
    m.blast = CreateFrame("Frame", nil, bar)
    AtParentLevel(m.blast, bar)
    m.blast:SetAllPoints(m.origin)
    m.blast:Hide()
    m.wave = Tex(m.blast, -4, "Glow", "BLEND")
    m.wave:SetPoint("CENTER", m.origin, "CENTER")
    Tint(m.wave, CORE, 0)
    return m
end

--------------------------------------------------------------------------------
-- Particles
--------------------------------------------------------------------------------

local function Spawn(pool, p)
    for _, q in ipairs(pool) do
        if q.age >= q.life then
            for k, v in pairs(p) do q[k] = v end
            q.age = 0
            return q
        end
    end
end

-- A mote in the shield, x back from the rim (negative), y down from the bar's top.
local function Mote(m)
    Spawn(m.motes, { x = -RIM_INSET - Rand(0, MOTE_SPAN), y = -Rand(2, m.height - 2), vx = Rand(1.5, 5),
                     vy = Rand(0.7, 3), life = Rand(1.0, 2.0), size = Rand(2.5, 4.5), bright = 0.7, drag = 0.4,
                     gravity = 0, color = MOTE, spin = false })
end

-- A spark off the rim (y along it), flying out; shards scatter wider and fall.
local function Spark(m, shard)
    local h = m.height
    local y = -Rand(1, h - 1)
    local n = (y + h / 2) / (h / 2)
    local x = -0.3 * RIM_W * n * n -- along the crescent
    local p
    if shard then
        local a, sp = Rand(-math.pi, math.pi), Rand(13, 57)
        p = { x = x - Rand(0, 12) * math.random() ^ 2, y = y, vx = math.abs(math.cos(a)) * sp * 0.9 + 5,
              vy = math.sin(a) * sp, life = Rand(0.4, 0.9), size = Rand(5, 8), drag = 2.2, gravity = -47, bright = 1 }
    else
        p = { x = x, y = y, vx = Rand(17, 50), vy = Rand(-17, 23), life = Rand(0.25, 0.55), size = Rand(5, 7),
              drag = 3.5, gravity = -30, bright = 1 }
    end
    p.color, p.spin = SPARK, true
    Spawn(m.sparks, p)
end

-- An ember of light the holding shield lets off: from anywhere on the rim, out and up, slow, floating as it fades.
local function Ember(m)
    local h = m.height
    local y = -Rand(1, h - 1)
    local n = (y + h / 2) / (h / 2)
    Spawn(m.sparks, { x = -0.3 * RIM_W * n * n, y = y, vx = Rand(5, 22), vy = Rand(-6, 16), life = Rand(0.7, 1.4),
                      size = Rand(3, 5), drag = 1.2, gravity = 9, bright = 0.85, color = SPARK, spin = true })
end

-- A shard of the shattering glass, from anywhere along a bar back from the rim (the pool keeps those over the shield):
-- it flies out, mostly up, tumbling, and falls as it fades.
local function Shard(m)
    local c = ({ CORE, CORE, GLOW })[math.random(3)]
    Spawn(m.shards, { x = -RIM_INSET - Rand(0, m.width), y = -Rand(1, m.height - 1), vx = Rand(-22, 30),
                      vy = Rand(-14, 52), life = Rand(0.6, 1.1), size = Rand(7, 13), drag = 1.6, gravity = -95,
                      bright = 1, color = c, rot = Rand(0, 2 * math.pi), tumble = Rand(-14, 14) })
end

-- A shard from the rim's end of the shield, however little of it is left: flung out past the rim and up, tumbling.
local function RimShard(m)
    local c = ({ CORE, CORE, GLOW })[math.random(3)]
    Spawn(m.rimShards, { x = -Rand(0, RIM_BURST) * math.random(), y = -Rand(1, m.height - 1), vx = Rand(-15, 45),
                         vy = Rand(-18, 55), life = Rand(0.6, 1.1), size = Rand(7, 12), drag = 1.6, gravity = -95,
                         bright = 1, color = c, rot = Rand(0, 2 * math.pi), tumble = Rand(-14, 14) })
end

-- A streak of light flung from anywhere along the shattering glass, fast, falling off as it fades.
local function Streak(m)
    Spawn(m.streaks, { x = -RIM_INSET - Rand(0, m.width), y = -Rand(1, m.height - 1), vx = Rand(-35, 45),
                       vy = Rand(-25, 65), life = Rand(0.3, 0.65), size = Rand(6, 9), drag = 2.8, gravity = -45,
                       bright = 1, color = SPARK, spin = true })
end

local function StepPool(pool, frame, dt, t)
    for _, q in ipairs(pool) do
        if q.age < q.life then
            q.age = q.age + dt
            if q.age >= q.life then
                q.tex:Hide()
            else
                local k = math.exp(-q.drag * dt)
                q.vx = q.vx * k
                q.vy = q.vy * k + q.gravity * dt
                q.x, q.y = q.x + q.vx * dt, q.y + q.vy * dt
                local f = q.age / q.life
                local a = q.bright * (1 - f) ^ 1.3 * math.min(1, q.age / 0.08) * (0.75 + 0.25 * math.sin(9 * t + q.size))
                local tex = q.tex
                tex:ClearAllPoints()
                tex:SetPoint("CENTER", frame, "TOPRIGHT", q.x, q.y)
                tex:SetSize(q.size, q.size)
                tex:SetVertexColor(q.color[1], q.color[2], q.color[3], a)
                if q.tumble then
                    tex:SetRotation(q.rot + q.tumble * q.age)
                elseif q.spin then
                    tex:SetRotation(math.atan2(q.vy, q.vx) - math.pi / 2)
                end
                tex:Show()
            end
        end
    end
end

local function ClearPool(pool)
    for _, q in ipairs(pool) do
        q.age = q.life
        q.tex:Hide()
    end
end

--------------------------------------------------------------------------------
-- Reading the shield
--------------------------------------------------------------------------------

local function Absorbs(calc)
    if not calc then return nil end
    local ok = pcall(UnitGetDetailedHealPrediction, "player", nil, calc)
    if not ok then return nil end
    local ok2, amount = pcall(calc.GetDamageAbsorbs, calc)
    if not ok2 then return nil end
    return amount
end

-- The game's own absorb bar and glow on the health bar (Mainline PlayerFrame.xml), or nil.
local function GameParts(bar)
    local segment = bar.TotalAbsorbBar
    return type(segment) == "table" and segment or nil, type(bar.OverAbsorbGlow) == "table" and bar.OverAbsorbGlow or nil
end

-- Whether there is a shield, by the game's own bar and glow: true, false, or nil when the client will not say.
local function Exists(bar)
    local segment, glow = GameParts(bar)
    if not segment and not glow then return nil end
    local a = segment and segment:IsShown()
    local b = glow and glow:IsShown()
    if Secret(a) or Secret(b) then return nil end
    return (a or b) and true or false
end

-- For Soul.lua, which times Weakened Soul from shields going up, with or without the shield setting.
Shield.Exists = Exists
-- Where the rim stands, for what Soul.lua draws on it.
Shield.RIM = { inset = RIM_INSET, width = RIM_W, line = RIM_LINE }

-- Hidden while ours shows (0), back when it does not (1): the game's absorb fill, its tiled overlay and its glow.
local function GameAlpha(bar, alpha)
    local segment, glow = GameParts(bar)
    for _, region in ipairs({ segment and segment.Fill, segment and segment.TiledFillOverlay, glow }) do
        if type(region) == "table" and region.SetAlpha and region.GetAlpha then
            local now = region:GetAlpha()
            if Secret(now) or now ~= alpha then region:SetAlpha(alpha) end
        end
    end
end

-- snap: set at once, with no smoothing. A shield going up does: its hidden bars are fed only while it shows, so they
-- still hold the last shield's values (or nothing, after login), and eased from there the health's front and the glass
-- slid in from the bar's left end (a review caught it).
local function Feed(m, snap)
    local bar = m.bar
    local ease = not snap and INTERPOLATION
    m.proxy:SetMinMaxValues(bar:GetMinMaxValues())
    if ease then m.proxy:SetValue(bar:GetValue(), ease) else m.proxy:SetValue(bar:GetValue()) end
    local whole = m.ending and 0 or Absorbs(m.calc) -- an ending shield drains away, whatever is read meanwhile
    if whole == nil then return end
    m.run:SetMinMaxValues(bar:GetMinMaxValues())
    if ease then m.run:SetValue(whole, ease) else m.run:SetValue(whole) end
    if m.ending then return end -- the ghost holds the glass's last place
    m.ghost:SetMinMaxValues(bar:GetMinMaxValues())
    if ease then m.ghost:SetValue(whole, ease) else m.ghost:SetValue(whole) end
end

--------------------------------------------------------------------------------
-- Each frame
--------------------------------------------------------------------------------

-- How far short of the health's front the run is measured (m.inset, in units): RIM_INSET, from the rim, while there
-- is glass; nothing once an ending shield's glass is gone, so the health flows up to its front. Let through to the
-- health's front while the glass shows, the last units of green showed past the rim the moment the shield broke.
local function RunInset(m, inset)
    if math.abs(inset - m.inset) < 0.05 then return end
    m.inset = inset
    local edge = m.proxy:GetStatusBarTexture()
    m.run:SetPoint("TOPRIGHT", edge, "TOPRIGHT", -inset, 0)
    m.run:SetPoint("BOTTOMRIGHT", edge, "BOTTOMRIGHT", -inset, 0)
end

local function Hide(m)
    if not m.clip:IsShown() then return end
    m.clip:Hide()
    m.shed:Hide()
    m.blast:Hide()
    ClearPool(m.motes)
    ClearPool(m.sparks)
    ClearPool(m.shards)
    ClearPool(m.rimShards)
    ClearPool(m.streaks)
    ns.Bars.Front(m.bar, nil)
    GameAlpha(m.bar, 1)
    m.ending, m.endT, m.burstDone = nil, nil, nil
    m.cracks:Hide()
    m.whiten:Hide()
    RunInset(m, RIM_INSET)
end

-- The shield is going: it shatters.
local function BeginEnding(m)
    m.ending, m.endT, m.burstDone = "shatter", 0, nil
    m.cracks:Show()
    m.whiten:Show()
end

-- The shield came back while ending: it holds again.
local function CancelEnding(m)
    m.ending, m.endT, m.burstDone = nil, nil, nil
    m.cracks:Hide()
    m.whiten:Hide()
    m.blast:Hide()
    m.mover:ClearAllPoints()
    m.mover:SetPoint("TOPRIGHT", m.proxy:GetStatusBarTexture(), "TOPRIGHT")
    m.mover:SetPoint("BOTTOMRIGHT", m.proxy:GetStatusBarTexture(), "BOTTOMRIGHT")
    m.mover:SetWidth(m.width)
end

local function Show(m)
    if m.clip:IsShown() then return end
    m.feed = FEED_EVERY
    Feed(m, true)
    m.clip:Show()
    m.shed:Show()
    m.fade, m.flash, m.body = 1, 1, 1
    ns.Bars.Front(m.bar, m.start)
    ns.Bars.StirBar(m.bar)
end

local function Animate(m, dt)
    local t = m.t
    local w = m.width
    -- Strands scroll toward the rim; a texel is about a third of a unit across, the texture one bar high.
    local spanA, spanB = w * 3 / 256, w * 2.4 / 256
    local uA, vA = -t * 26 / 256, t * 3 / 64
    m.strandsA:SetTexCoord(uA, uA + spanA, vA, vA + 1)
    local uB, vB = 90 / 256 + t * 11 / 256, 21 / 64 - t * 2 / 64
    m.strandsB:SetTexCoord(uB + spanB, uB, vB, vB + 1)
    for _, r in ipairs(m.rays) do
        r.at = (r.at + r.speed * dt) % (w + 40)
        r.tex:ClearAllPoints()
        r.tex:SetPoint("CENTER", m.mover, "LEFT", r.at - 20, 0)
    end

    -- The body keeps its colour; only an ending shield fades it, all of it at once through the mover.
    m.mover:SetAlpha(m.body)

    m.rim:SetAlpha(math.min(1, 0.92 + 0.08 * math.sin(t * 17) + 0.6 * m.flash))
    m.rimFlare:SetAlpha(math.min(1, 1.4 * m.flare + 0.5 * m.flash))
    m.halo:SetAlpha(math.min(1, 0.35 + 0.4 * m.flare + 0.2 * m.flash))
    m.crackle:SetAlpha(math.min(1, CRACKLE_ALPHA * (1 + 1.2 * m.flare)))
    -- The meeting with the health liquid breathes slowly, and lights up as a soaked hit pushes on the health.
    m.contact:SetAlpha(m.fade)
    m.glow:SetAlpha(math.min(1, 0.7 + 0.08 * math.sin(t * 2.3) + 0.3 * m.push + 0.2 * m.flash))
    m.crackleIn = (m.crackleIn or 0) - dt
    if m.crackleIn <= 0 then
        m.crackleIn = CRACKLE_EVERY
        local f = math.random(CRACKLE_FRAMES)
        local top, bottom = (f - 1) / CRACKLE_FRAMES, f / CRACKLE_FRAMES
        if math.random() < 0.5 then top, bottom = bottom, top end -- flipped, for twice the shapes
        m.crackle:SetTexCoord(0, 1, top, bottom)
    end

    -- God rays off the rim, each swelling and fading on its own beat and swaying a little; a soaked hit lights them all.
    m.shed:SetAlpha(m.fade)
    local boost = 1 + 1.5 * m.flare + 0.8 * m.flash
    for _, b in ipairs(m.beams) do
        local pulse = math.max(0, math.sin(b.phase + t * b.speed))
        b.tex:SetRotation(b.angle + 0.1 * math.sin(t * b.sway + b.phase))
        b.tex:SetAlpha(math.min(1, BEAM_ALPHA * (0.25 + 0.75 * pulse * pulse) * boost))
    end

    -- Motes, a few a second, more just after the shield goes up; and embers drifting off the rim while it holds.
    m.moteIn = (m.moteIn or 0) - dt * (1 + 4 * m.flash)
    while m.moteIn <= 0 do
        m.moteIn = m.moteIn + 0.09
        if m.fade >= 1 then Mote(m) end
    end
    m.emberIn = (m.emberIn or 0) - dt
    while m.emberIn <= 0 do
        m.emberIn = m.emberIn + EMBER_EVERY * Rand(0.5, 1.5)
        if m.fade >= 1 then Ember(m) end
    end
    StepPool(m.motes, m.mover, dt, t)
    StepPool(m.sparks, m.origin, dt, t)
    StepPool(m.rimShards, m.origin, dt, t)
    StepPool(m.shards, m.burst, dt, t)
    StepPool(m.streaks, m.burst, dt, t)

    m.flare = math.max(0, m.flare - dt / 0.28)
    m.flash = math.max(0, m.flash - dt / 0.4)
    -- The push reaches the health a moment after the rim takes the hit, and shoves its front.
    if m.pushIn then
        m.pushIn = m.pushIn - dt
        if m.pushIn <= 0 then
            m.pushIn, m.push = nil, 1
            ns.Bars.Lap(m.bar, PUSH_KICK)
        end
    end
    m.push = math.max(0, m.push - dt / 0.6)
    -- While it holds, the shield laps at the health's front now and then, so the two are seen to touch.
    m.lapIn = (m.lapIn or 0) - dt
    if m.lapIn <= 0 then
        m.lapIn = LAP_EVERY * Rand(0.6, 1.4)
        if m.fade >= 1 then ns.Bars.Lap(m.bar, LAP_KICK * Rand(0.6, 1.3)) end
    end
end

-- The body's place, with a tremble (x, y) while a shattering shield strains.
local function Place(m, x, y)
    local edge = m.proxy:GetStatusBarTexture()
    m.mover:ClearAllPoints()
    m.mover:SetPoint("TOPRIGHT", edge, "TOPRIGHT", x, y)
    m.mover:SetPoint("BOTTOMRIGHT", edge, "BOTTOMRIGHT", x, y)
    m.mover:SetWidth(m.width)
end

-- A step of the shield's shattering (SHATTER), m.endT seconds in: the body's alpha (m.body), the rest's (m.fade), and
-- what bursts from it. True once it is over.
local function Ending(m, dt)
    local e = m.endT
    do
        local T = SHATTER
        if e < T.strain then
            -- Straining: cracks spread through the glass as it whitens and trembles, the rim blazing.
            local k = e / T.strain
            m.cracks:SetAlpha(math.min(1, k ^ 1.4))
            m.whiten:SetAlpha(0.45 * k * k)
            m.flare = math.max(m.flare, 0.6 + 0.4 * k)
            local amp = 0.9 * k
            Place(m, Rand(-amp, amp), Rand(-amp, amp) * 0.5)
            if math.random() < dt * 30 then Spark(m, false) end
            m.body, m.fade = 1, 1
        else
            if not m.burstDone then
                -- It bursts: shards fly from all along the glass, a flash, a shockwave off the rim, the rays blazing,
                -- and the health, already flowing up beneath, splashes.
                m.burstDone = true
                Place(m, 0, 0)
                for _ = 1, SHARDS do Shard(m) end
                for _ = 1, RIM_SHARDS do RimShard(m) end
                for _ = 1, STREAKS do Streak(m) end
                for _ = 1, 30 do Spark(m, true) end
                m.flare, m.flash = 1, 1
                m.blast:Show()
                ns.Bars.StirBar(m.bar)
                ns.Bars.Lap(m.bar, PUSH_KICK * 2)
            end
            -- The glass flashes white in its own shape as it goes (a flash of its own was a hard-edged box).
            local after = e - T.strain
            m.body = math.max(0, 1 - after / T.gone)
            m.whiten:SetAlpha(1)
            m.cracks:SetAlpha(1)
            local k = after / T.wave
            if k < 1 then
                m.wave:SetSize(30 + 140 * k, m.height * (1.4 + 2.6 * k))
                m.wave:SetAlpha(0.9 * (1 - k) ^ 1.6)
            elseif m.blast:IsShown() then
                m.blast:Hide()
            end
            m.fade = math.max(0, 1 - after / 0.5)
        end
        return e >= T.done
    end
end

local function Update(m, dt)
    local sight = ns.Bars.Sight(m.bar)
    if sight ~= "shown" then return Hide(m) end
    if not m.calc then return Hide(m) end
    local now = GetTime()

    -- Going up and going, where the game says (or, where it will not, for a while after the player's own cast).
    local exists = Exists(m.bar)
    m.exists = exists
    local holding = exists == true or (exists == nil and now < m.castUntil)
    if holding then
        if m.ending then CancelEnding(m) end
    elseif m.clip:IsShown() and not m.ending then
        BeginEnding(m)
    end
    if not holding and not m.ending then return Hide(m) end
    Show(m)
    -- Every frame, not only as it shows: a liquid built while the shield was up (the health bar's liquid turned on)
    -- starts on the health's edge, past the rim. Nothing is done when it is already there.
    ns.Bars.Front(m.bar, m.start)
    GameAlpha(m.bar, 0)

    local w, h = ns.Bars.Size(m.bar, m.width, m.height)
    if (w ~= m.width or h ~= m.height) and w >= 1 and h >= 1 then
        m.width, m.height = w, h
        m.run:SetWidth(w)
        m.ghost:SetWidth(w)
        m.mover:SetWidth(w)
        m.burst:SetWidth(w)
    end
    m.feed = m.feed + dt
    if m.feed >= FEED_EVERY then
        m.feed = 0
        Feed(m)
    end
    m.t = m.t + dt
    if m.ending then
        m.endT = m.endT + dt
        if Ending(m, dt) then return Hide(m) end
        -- The run drains and the health flows up under the glass, to the rim while the glass shows, then on to its
        -- front as the glass goes.
        local b = m.body
        RunInset(m, RIM_INSET * b * b * (3 - 2 * b))
    else
        m.body, m.fade = 1, 1
        RunInset(m, RIM_INSET)
    end
    Animate(m, dt)
end

--------------------------------------------------------------------------------
-- The driver, events and settings
--------------------------------------------------------------------------------

local player -- the shield on the player frame's health bar, once built
local driver
local probe = { absorbs = 0, hits = {}, casts = 0 }
local SHIELD_NAME -- Power Word: Shield in the client's language
local selfCast = {} -- castGUID -> true for the player's own Power Word: Shield sent at themselves

local function OnUpdate(_, elapsed)
    local dt = math.min(elapsed, 0.1)
    if dt <= 0 or not player or not player.live or player.err then return end
    local ok, err = pcall(Update, player, dt)
    if not ok then
        player.err = tostring(err)
        pcall(Hide, player)
        ns.Core.Print("Error in the shield, which is off until a reload: " .. player.err)
    end
end

local function OnEvent(_, event, unit, a1, a2, a3)
    if not player or not player.live or player.err then return end
    if event == "UNIT_COMBAT" then
        local action = a1
        if Secret(action) or type(action) ~= "string" then return end
        probe.hits[action] = (probe.hits[action] or 0) + 1
        if action == "ABSORB" then
            probe.absorbs = probe.absorbs + 1
            if player.clip:IsShown() then
                player.flare, player.pushIn = 1, 0.12
                for _ = 1, 10 do Spark(player, false) end
                ns.Bars.StirBar(player.bar)
            end
        end
    elseif event == "UNIT_SPELLCAST_SENT" then
        -- unit, target, castGUID, spellID: a shield the player sends at themselves (on anyone else, nothing shows here).
        local target, guid, spellID = a1, a2, a3
        if Secret(target) or Secret(guid) or Secret(spellID) or not SHIELD_NAME or not guid then return end
        local ok, name = pcall(C_Spell and C_Spell.GetSpellName or GetSpellInfo, spellID)
        if ok and name == SHIELD_NAME and target == UnitName("player") then selfCast[guid] = true end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local guid = a1
        if Secret(guid) or not guid or not selfCast[guid] then return end
        selfCast[guid] = nil
        probe.casts = probe.casts + 1
        player.castUntil = GetTime() + CAST_SHOWS -- shows it where the game will not say
    end
end

-- After the shield setting changes, and at login.
function Shield.Apply()
    local live = ns.Core.Get("shield") and true or false
    if live and not player then
        local bar = ns.Bars.Find("playerHealth")
        if type(bar) == "table" and bar.GetStatusBarTexture then player = New(bar) end
    end
    if not SHIELD_NAME then
        local ok, name = pcall(C_Spell and C_Spell.GetSpellName or GetSpellInfo, 17)
        if ok and type(name) == "string" then SHIELD_NAME = name end
    end
    if player then
        player.live = live
        if not live then Hide(player) end
    end
    if live and player and not driver then
        driver = CreateFrame("Frame")
        driver:SetScript("OnUpdate", OnUpdate)
        driver:SetScript("OnEvent", OnEvent)
    end
    if not driver then return end
    driver:SetShown(live)
    if live then
        driver:RegisterUnitEvent("UNIT_COMBAT", "player")
        driver:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
        driver:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    else
        driver:UnregisterAllEvents()
    end
end

-- After an effect toggle: nothing of the shield follows the liquid's effects.
function Shield.ApplyOptions() end

-- For the tests: the shield on the player frame (nil until built).
function Shield.State()
    return player
end

local function Describe(v)
    if v == nil then return "nil" end
    if Secret(v) then return "secret" end
    if type(v) == "number" then return string.format("%.1f", v) end
    return tostring(v)
end

-- A region's width as the client lays it out, or "secret" (anchored to a secret value).
local function Width(region)
    local ok, w = pcall(region.GetWidth, region)
    if not ok then return "error" end
    return Describe(w)
end

local function Level(frame)
    local ok, level = pcall(frame.GetFrameLevel, frame)
    return ok and Describe(level) or "?"
end

-- /sab shield test [off]: a magenta block where the shield lies, cut by the bar's mask as the shield is, to see in game
-- what the client lays out (none: the shield has no width).
function Shield.Test(on)
    if not player then return "Shield: the player frame's health bar was not found" end
    local m = player
    if not m.testBlock then
        m.testBlock = m.mover:CreateTexture(nil, "OVERLAY", nil, 7)
        m.testBlock:SetColorTexture(1, 0, 1, 1)
        m.testBlock:SetAllPoints(m.mover)
        if m.mask then m.testBlock:AddMaskTexture(m.mask) end
    end
    m.testBlock:SetShown(on)
    if not on then return "Shield test block off." end
    return "Shield test: magenta where the shield lies (it shows while a shield is up). /sab shield test off to stop."
end

-- For /sab shield: what the game lets the addon read about absorbs on the player, and what the shield is doing.
function Shield.Debug()
    local out = {}
    if not ns.Core.Get("shield") then out[1] = "Shield: off (Shield in the editor)" end
    out[#out + 1] = "Calculator: " .. (CreateUnitHealPredictionCalculator and "yes" or "missing")
        .. ", UnitGetDetailedHealPrediction: " .. (UnitGetDetailedHealPrediction and "yes" or "missing")
    if player then
        local m = player
        out[#out + 1] = string.format("Absorb (capped to the whole bar): %s", Describe(Absorbs(m.calc)))
        local segment, glow = GameParts(m.bar)
        out[#out + 1] = string.format("Game's absorb bar: %s, shown %s; over-absorb glow: %s, shown %s",
            segment and "found" or "not found", segment and Describe(segment:IsShown()) or "-",
            glow and "found" or "not found", glow and Describe(glow:IsShown()) or "-")
        out[#out + 1] = string.format("Shield: %s, a shield as the game says: %s%s%s",
            m.clip:IsShown() and "showing" or "hidden", Describe(Exists(m.bar)), m.ending and (", " .. m.ending) or "",
            m.err and (", error: " .. m.err) or "")
        out[#out + 1] = string.format("Layout: bar %s wide, level %s; shield level %s; its start %s back from the "
            .. "health's front", Width(m.bar), Level(m.bar), Level(m.clip), Width(m.start))
    else
        out[#out + 1] = "Shield: the player frame's health bar was not found"
    end
    local hits = {}
    for action, n in pairs(probe.hits) do hits[#hits + 1] = action .. " " .. n end
    table.sort(hits)
    out[#out + 1] = string.format("Hits on you since login: %s; Power Word: Shield (%s) casts: %d",
        #hits > 0 and table.concat(hits, ", ") or "none", SHIELD_NAME or "name not found", probe.casts)
    return out
end
