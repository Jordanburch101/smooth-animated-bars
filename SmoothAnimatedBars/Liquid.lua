-- Liquid rendering: a wobbling front, swirling magic inside, bubbles, lightning and glowing motes.
-- Positions are in bar units (pixels before the bar's scale), from the parent frame's left edge.
-- How the liquid moves and what it throws off comes from the theme; see Themes.lua.
-- Ported from Smooth Experience Bar without its experience bar parts (glass, quest and rested XP,
-- level-ups).

local _, ns = ...

-- Timing every part of the addon for /sab perf (SmoothAnimatedBars.lua, PartsReport): each update, event handler and
-- ticker is wrapped by ns.Timed with the name of its part, and while ns.Timing.on its time is added up. Off, a wrapper
-- only tests the flag. Here, in the first file that runs code, as every part sets its scripts at load. The game's own
-- profiler counted about twice what /sab perf's liquid timing did (seen in game): the rest was in these parts.
local Timing = { on = false, ms = {}, calls = {} }
ns.Timing = Timing
local profileClock = debugprofilestop

local function TimedDone(part, t0, ...)
    Timing.ms[part] = (Timing.ms[part] or 0) + (profileClock() - t0)
    Timing.calls[part] = (Timing.calls[part] or 0) + 1
    return ...
end

-- A step's time since t0 added to the part's, and the clock now (Liquid:Update's steps).
local function Lap(part, t0)
    local now = profileClock()
    Timing.ms[part] = (Timing.ms[part] or 0) + now - t0
    Timing.calls[part] = (Timing.calls[part] or 0) + 1
    return now
end

function ns.Timed(part, fn)
    if not profileClock then return fn end
    return function(...)
        if not Timing.on then return fn(...) end
        return TimedDone(part, profileClock(), fn(...))
    end
end

local exp, min, max, abs, sin, cos, sqrt, floor, random, pi =
    math.exp, math.min, math.max, math.abs, math.sin, math.cos, math.sqrt, math.floor, math.random, math.pi
local atan2 = math.atan2 or math.atan

local MEDIA = "Interface\\AddOns\\SmoothAnimatedBars\\Media\\"
local SWIRL_W, SWIRL_H = 256, 64

-- Show and hide the liquid's textures only when that changes: Draw asks for every slice, cap and layer each update,
-- and on eight quiet party bars a third of the widget calls a frame were Show and Hide on textures already so (counted
-- in the mock). The state is kept on our own textures; nothing else shows or hides them.
local function On(t)
    if not t.sabShown then
        t.sabShown = true
        t:Show()
    end
end

local function Off(t)
    if t.sabShown ~= false then
        t.sabShown = false
        t:Hide()
    end
end

-- The same for what a texture is given each update: every widget call costs (about 1.9 microseconds in game, against a
-- few hundredths for the Lua here), and player and target in combat made about 1300 a frame (tools/harness/bench.py).
-- Sizes and texture coordinates are set again only when they change at all. Alpha and colours change a little every
-- update (pulses, slow colour drifts, energy dying away), so they are set again once they have moved by COLOR_STEP, half
-- of one 8-bit step: less than the screen can show (tools/harness/samelook.py checks the look is unchanged).
local COLOR_STEP = 0.5 / 255

local function Alpha(t, a)
    local was = t.sabA
    if not was or a - was > COLOR_STEP or was - a > COLOR_STEP then
        t.sabA = a
        t:SetAlpha(a)
    end
end

local function Color(t, r, g, b)
    local c = t.sabC
    if not c then
        c = {}
        t.sabC = c
    elseif abs(r - c[1]) <= COLOR_STEP and abs(g - c[2]) <= COLOR_STEP and abs(b - c[3]) <= COLOR_STEP then
        return
    end
    c[1], c[2], c[3] = r, g, b
    t:SetVertexColor(r, g, b)
    -- A texture has one alpha, which SetVertexColor's fourth value sets too; given none, it may be put back to 1, so the
    -- next Alpha sets it again rather than trusting what it set last.
    t.sabA = nil
end

-- Colour and alpha both: one SetVertexColor with the alpha as its fourth value when the colour moved, else SetAlpha
-- alone when the alpha did (a mote's, both changing over its life).
local function Look(t, r, g, b, a)
    local c = t.sabC
    if not c or abs(r - c[1]) > COLOR_STEP or abs(g - c[2]) > COLOR_STEP or abs(b - c[3]) > COLOR_STEP then
        if not c then
            c = {}
            t.sabC = c
        end
        c[1], c[2], c[3] = r, g, b
        t.sabA = a
        t:SetVertexColor(r, g, b, a)
    else
        Alpha(t, a)
    end
end

local function Width(t, w)
    if t.sabW ~= w then
        t.sabW = w
        t:SetWidth(w)
    end
end

-- A texture always placed by the same point (rows, tips, the glow) is moved only when its offsets change. SetMirror,
-- which changes those points, forgets them.
local function Place(t, point, rel, relPoint, x, y)
    if t.sabX ~= x or t.sabY ~= y then
        t.sabX, t.sabY = x, y
        t:SetPoint(point, rel, relPoint, x, y)
    end
end

local function Coords(t, l, r, top, bottom)
    if t.sabL ~= l or t.sabR ~= r or t.sabT ~= top or t.sabB ~= bottom then
        t.sabL, t.sabR, t.sabT, t.sabB = l, r, top, bottom
        t:SetTexCoord(l, r, top, bottom)
    end
end

local CFG = {
    rows        = 15,      -- most horizontal slices that make up the liquid front (Liquid.RowsFor)
    rowPx       = 1.25,    -- a slice for every this many px of height, down to minRows
    minRows     = 6,
    step        = 1 / 120, -- fixed physics step
    energyDecay = 0.8,     -- per second
    bubbles     = 36,      -- pool sizes
    bolts       = 4,
    boltRows    = 8,       -- arc variants stacked in Bolt.tga
    motes       = 64,
    edgeW       = 6,       -- width of the bright line texture along the front, px
    edgeCore    = 0.7,     -- where the line sits across Edge.tga (EDGE_CORE in make_media.py)
}

-- Defaults for the theme tables of the same name. A theme only lists what it changes.
local PHYSICS = {
    amplitude = 10,   -- how far the front can bulge or dip, px
    stiffness = 90,   -- spring pulling each slice back to rest
    damping   = 3.5,
    coupling  = 900,  -- how strongly neighbouring slices pull on each other (wave speed)
    slosh     = 0.18, -- front displacement per px/s change in fill speed
    ambient   = 1.0,  -- idle wobble, px
    crest     = 7,    -- how far the top of the front leans ahead of the bottom while pouring fast, px
}

local SWIRL = {
    texture = "Swirl",
    flow    = { 1, 0 }, -- drift direction of the veins (u toward the front, v upward)
    alpha   = 1,        -- multiplier on the swirl brightness
    pulse   = 0,        -- extra brightness that throbs at pulseRate Hz
    pulseRate = 0.5,
    rise    = 0,        -- steady climb of the veins, px/s, on top of the flow (flames)
}

-- Unsteady light, like a fire's: the whole liquid brightens and dims at random, about rate times a second.
local FLICKER = {
    amount = 0,  -- how far the brightness swings, 0..1
    rate   = 6,
}

-- Light that changes with height: a dark layer from the top (smoke over a fire) and a bright one from the bottom
-- (its hot base), both mapped once over the bar's height.
local SHADE = {
    dark     = 0,           -- alpha of the dark layer
    color    = { 0, 0, 0 },
    hot      = 0,           -- alpha of the bright layer; it flickers with the liquid
    hotColor = nil,         -- defaults to the tip colour
}

-- Slow clouds behind the veins for depth: dark pockets and light wisps, larger and slower than the veins.
local CLOUDS = {
    texture = "Nebula",
    dark    = 0.55, -- alpha of the darkening layer
    light   = 0.25, -- alpha of the light layer, tinted swirlB
    scale   = 0.55, -- texture repeats per SWIRL_W px; lower = bigger clouds
}

-- Light from inside the liquid: a soft band through the middle in the theme's glow colour.
local CORE = {
    alpha     = 1,   -- multiplier on the core brightness
    pulseRate = 0.2, -- Hz
}

-- Lightning in the clouds inside the liquid: long arcs that flash in a few quick strokes, drift with the
-- swirl and light up the clouds around them. Some flashes are sheet lightning, a glow with no arc.
-- At rest there are only faint sheet flashes; changes to the bar build up charge, and the more charge, the more
-- often it flashes and the bigger and brighter the flashes get.
local CRACKLE = {
    rate       = 0.08,         -- faint flashes per second at rest
    energyRate = 5,            -- extra per second at full charge
    alpha      = 0.9,          -- arc brightness at the peak of a stroke
    glow       = 0.7,          -- the bloom it lights in the clouds
    sheet      = 0.3,          -- share of flashes that are glow only
    strokes    = { 2, 4 },
    length     = { 5, 10 },    -- in bar heights
    color      = nil,          -- arc tint; defaults to swirlB. Arcs are mostly white, the bloom takes the colour
}

local BUBBLES = {
    texture = "Bubble",
    blend   = "BLEND",
    rate    = 0.5,          -- per second when calm
    energyRate = 14,        -- extra per second at full energy
    rise    = { 12, 26 },   -- px/s
    size    = { 3, 6 },
    alpha   = 0.45,
    drift   = 1,            -- slow drifters anywhere in the liquid, per second per unit of rate
    splash  = 1,            -- multiplier on the bubbles a change stirs up (0 for none)
}

-- Motes thrown off when the bar changes.
-- mode "throw" flings them out of the front; "attract" spawns them around it and pulls them in.
local BURST = {
    texture  = "Mote",
    blend    = "ADD",
    mode     = "throw",
    buoyancy = 20,   -- px/s^2 upward
    drag     = 1.8,
    spin     = nil,  -- { min, max } rad/s
    twinkle  = nil,  -- Hz
    wander   = nil,  -- px/s^2 of sideways sway, each mote at its own pace (sparks in hot air)
    orient   = nil,  -- true: turn the texture's top along the flight, so a spark's tail trails behind it
}

local STEADY_DAMPING = 20 -- more damping on a steady front at its steadiest, so what moves it dies out (Liquid:SetSteady)

local function Rand(a, b)
    return a + (b - a) * random()
end

local function RandRange(r, default)
    if not r then return default end
    return Rand(r[1], r[2])
end

local function Lerp(a, b, t)
    return a + (b - a) * t
end

-- The same colour turned dh of the way round the colour wheel (0..1), keeping saturation and brightness.
local function HueShift(c, dh)
    local r, g, b = c[1], c[2], c[3]
    local hi, lo = max(r, g, b), min(r, g, b)
    local d = hi - lo
    if d < 0.001 then return { r, g, b } end
    local h
    if hi == r then h = ((g - b) / d) % 6
    elseif hi == g then h = (b - r) / d + 2
    else h = (r - g) / d + 4 end
    h = (h / 6 + dh) % 1 * 6
    local i, f = floor(h), h - floor(h)
    local p, q, u = lo, hi - d * f, lo + d * f
    if i == 0 then return { hi, u, p }
    elseif i == 1 then return { q, hi, p }
    elseif i == 2 then return { p, hi, u }
    elseif i == 3 then return { p, q, hi }
    elseif i == 4 then return { u, p, hi } end
    return { hi, p, q }
end

local function Merge(defaults, over)
    local t = {}
    for k, v in pairs(defaults) do t[k] = v end
    if over then
        for k, v in pairs(over) do t[k] = v end
    end
    return t
end

local Liquid = {}
Liquid.__index = Liquid
ns.Liquid = Liquid

-- opts holds the user toggles (waves, swirl, bubbles, sparkles, ambient, lightning) and is read live.
-- How many slices make up the front of a liquid this many px high: one per CFG.rowPx, from CFG.minRows to CFG.rows.
-- Each slice is nine textures redrawn every update (its row, its bright edge and a cap of each inside layer), and on
-- the unit frames' bars, 7 to 12 px high, fifteen were under a pixel each. Counted in the mock, eight on a 10 px bar
-- (power bars, the Personal Resource Display) cut the bar's widget calls by about a third, and drawn at six times the
-- size the front looked the same. A 20 px bar (the player's and target's health) keeps fifteen. Every liquid of a
-- height takes the same count: the bar's own, its Rage Fury and the markers' liquids on it, whose fronts are matched
-- slice by slice (Follow, FrontOffset).
-- Animation Frame Rate (animationFps, asked for): at most this many updates a second for a liquid that is moving, or
-- every frame at UNLIMITED_FPS, the default. A moving liquid is otherwise drawn every frame, so its cost per second grows
-- with the frame rate (at 124 fps a fight with the player and target took about a fifth of each frame, seen in game).
-- Where the liquid is on the bar never waits: the client lays it out from the game's bar every frame. Only what moves
-- inside it (waves, swirl, particles) steps at the cap.
local UNLIMITED_FPS = 150
Liquid.UNLIMITED_FPS = UNLIMITED_FPS
local busyStep = 0 -- seconds between a moving liquid's updates, 0 for every frame

function Liquid.SetFrameRate(fps)
    fps = tonumber(fps)
    busyStep = (fps and fps >= 10 and fps < UNLIMITED_FPS) and 1 / fps or 0
end

-- For a liquid that is moving, after dt more seconds: how far to update it now, or nil to wait for a later frame. Due
-- within half a frame of its step, so 60 at 124 fps is every other frame, not every third.
function Liquid:Due(dt)
    if busyStep == 0 then
        self.busyAcc = 0
        return dt
    end
    local acc = (self.busyAcc or 0) + dt
    if acc < busyStep - dt * 0.5 then
        self.busyAcc = acc
        return nil
    end
    self.busyAcc = 0
    return acc
end

function Liquid.RowsFor(height)
    return math.max(CFG.minRows, math.min(CFG.rows, math.floor(height / CFG.rowPx)))
end

-- rows: how many slices make up the front, Liquid.RowsFor(height) unless given.
function Liquid.New(parent, width, height, theme, opts, rows)
    local self = setmetatable({}, Liquid)
    self.parent, self.width, self.height, self.opts = parent, width, height, opts
    self.n = rows or Liquid.RowsFor(height)
    self.rowH = height / self.n
    self.textures = {} -- every texture made here, for HideAll and masks
    -- Anchors and the x direction: from the parent's left edge, or its right edge when mirrored (SetMirror).
    self.aTL, self.aBL, self.aL, self.sx = "TOPLEFT", "BOTTOMLEFT", "LEFT", 1
    self.drawLayers = {} -- texture -> { layer, sublevel } as made, for SetSublevelOffset

    local function Tex(layer, sublevel, file, blend, wrap)
        local t = parent:CreateTexture(nil, layer, nil, sublevel)
        self.textures[#self.textures + 1] = t
        self.drawLayers[t] = { layer, sublevel }
        if not file then
            t:SetColorTexture(1, 1, 1, 1) -- solid; tinted with vertex colours and gradients
        elseif wrap then
            t:SetTexture(file, wrap, wrap)
        else
            t:SetTexture(file)
        end
        if blend then t:SetBlendMode(blend) end
        if t.SetSnapToPixelGrid then
            t:SetSnapToPixelGrid(false)
            t:SetTexelSnappingBias(0)
        end
        Off(t)
        return t
    end

    self.body = Tex("ARTWORK", 3)

    self.rows, self.tips, self.pos, self.vel = {}, {}, {}, {}
    self.lean, self.leanShape = 0, {}
    for i = 1, self.n do
        self.leanShape[i] = 0.55 - ((i - 1) / (self.n - 1)) ^ 1.3 -- row 1 is the top
    end
    for i = 1, self.n do
        local row = Tex("ARTWORK", 3)
        row:SetHeight(self.rowH)
        self.rows[i] = row

        self.tips[i] = Tex("ARTWORK", 6, MEDIA .. "Edge", "ADD")
        self.pos[i], self.vel[i] = 0, 0
    end
    self:LayoutTips()

    -- Textures that fill the inside of the liquid. Each is one texture up to the rearmost point of the
    -- front plus a cap per slice carrying it on to that slice's end, so nothing spills into a dip.
    local function Layer(sublevel, file, blend)
        -- r, g, b, stamp: its colour and a count of its changes (LayerColor); drawn: the alpha its textures have
        local layer = { main = Tex("ARTWORK", sublevel, MEDIA .. file, blend, "REPEAT"), caps = {}, u = 0, v = 0,
                        r = -1, g = -1, b = -1, stamp = 0 }
        for i = 1, self.n do
            layer.caps[i] = Tex("ARTWORK", sublevel, MEDIA .. file, blend, "REPEAT")
        end
        return layer
    end
    self.ends = {}
    self.cloudDark = Layer(4, "Nebula", "BLEND")
    self.cloudLight = Layer(5, "Nebula", "ADD")
    self.core = Layer(5, "Core", "ADD")
    self.swirlA = Layer(5, "Swirl", "ADD")
    self.swirlB = Layer(5, "Swirl", "ADD")
    self.cloudLight.u, self.swirlB.u = 0.5, 0.37
    -- The hot base is added light, so its order among the other added layers does not matter. The dark layer
    -- lies over the veins so flames fade as they rise.
    self.shadeHot = Layer(5, "Ramp", "ADD")
    self.shadeDark = Layer(6, "Ramp", "BLEND")
    self.shadeHot.v = 1 -- read bottom to top: the ramp's opaque end at the bottom
    self.layers = { self.cloudDark, self.cloudLight, self.core, self.swirlA, self.swirlB, self.shadeHot, self.shadeDark }

    self.bolts = {}
    for i = 1, CFG.bolts do
        self.bolts[i] = { tex = Tex("ARTWORK", 5, MEDIA .. "Bolt", "ADD"), glow = Tex("ARTWORK", 5, MEDIA .. "Glow", "ADD"),
                          active = false }
    end

    self.glow = Tex("ARTWORK", 7, MEDIA .. "Glow", "ADD")
    self.glow:SetSize(36, height * 1.7)

    -- liveBubbles, liveMotes: the pool entries in flight, in the order they were let go (UpdateParticles).
    self.bubbles, self.liveBubbles = {}, {}
    for i = 1, CFG.bubbles do
        self.bubbles[i] = { tex = Tex("OVERLAY", 3, MEDIA .. "Bubble"), active = false }
    end

    self.motes, self.moteNext, self.liveMotes = {}, 1, {}
    for i = 1, CFG.motes do
        self.motes[i] = { tex = Tex("OVERLAY", 4, MEDIA .. "Mote", "ADD"), active = false, file = "Mote", blend = "ADD" }
    end

    self.gradA, self.gradB, self.gradC = CreateColor(1, 1, 1, 1), CreateColor(1, 1, 1, 1), CreateColor(1, 1, 1, 1)
    -- The three gradient colours as last given to the body and slices, and a count that goes up whenever they change:
    -- a texture whose gradStamp is not the liquid's is given them again (Draw).
    self.gradNow, self.gradStamp = { -1, -1, -1, -1, -1, -1, -1, -1, -1 }, 0
    self.t, self.acc, self.energy, self.fizzAcc, self.driftAcc, self.crackleAcc = 0, 0, 0, 0, 0, 0
    self.edge, self.speed, self.back = 0, 0, 0
    self.flowX, self.flowY, self.storm, self.charge = 0, 0, 0, 0
    self.steady = 0
    self.flick, self.flickV, self.flickGoal, self.flickNext = 1, 0, 0, 0
    self.mixColor = { 1, 1, 1 }
    self.ambientAcc = {}
    self:Anchor()
    self:SetTheme(theme)
    return self
end

-- The textures laid along the parent's edge once, rather than each update.
function Liquid:Anchor()
    local tl, bl = self.aTL, self.aBL
    for _, t in ipairs({ self.body, self.cloudDark.main, self.cloudLight.main, self.core.main, self.swirlA.main,
                         self.swirlB.main, self.shadeHot.main, self.shadeDark.main }) do
        t:ClearAllPoints()
        t:SetPoint(tl)
        t:SetPoint(bl)
    end
    self:AnchorCaps()
end

-- Each layer's cap for a slice runs from the far end of the layer's main texture to the far end of that slice of the front
-- (a cap shows only where the slice does, and ends where it ends: Draw's ends), so the client lays it out as the main's
-- and the slice's widths change: placing and sizing the caps by hand cost two calls per cap every update (about 380 a
-- frame for player and target in combat). Laid out again when the slices' height changes (SetSize) or the liquid is
-- mirrored (SetMirror, via Anchor).
function Liquid:AnchorCaps()
    local rowH = self.rowH
    local from, to, far = self.aTL, self.mirror and "TOPLEFT" or "TOPRIGHT", self.mirror and "BOTTOMLEFT" or "BOTTOMRIGHT"
    for _, layer in ipairs(self.layers) do
        for i, cap in ipairs(layer.caps) do
            cap:ClearAllPoints()
            cap:SetPoint(from, layer.main, to, 0, -(i - 1) * rowH)
            cap:SetPoint(far, self.rows[i], far, 0, 0)
        end
    end
end

-- Mirrored, the liquid fills from the parent's right edge and its front faces left: for a bar that fills from the right
-- (SetReverseFill, another addon's bars through SmoothAnimatedBars.AddBar). Everything is still worked out from the
-- filled end, x growing toward the front; only where it is drawn changes.
function Liquid:SetMirror(on)
    on = on and true or false
    if on == (self.mirror or false) then return end
    self.mirror = on
    if on then
        self.aTL, self.aBL, self.aL, self.sx = "TOPRIGHT", "BOTTOMRIGHT", "RIGHT", -1
    else
        self.aTL, self.aBL, self.aL, self.sx = "TOPLEFT", "BOTTOMLEFT", "LEFT", 1
    end
    -- A point of another name would be added to the old one, not replace it.
    for _, t in ipairs(self.textures) do
        t:ClearAllPoints()
        t.sabX, t.sabY = nil, nil
    end
    self.gradStamp = self.gradStamp + 1 -- the gradients run the other way
    self:Anchor()
    self:LayoutTips()
    self:HideAll()
end

function Liquid:SetTheme(theme)
    self.theme = theme
    self.phys = Merge(PHYSICS, theme.physics)
    self.swirl = Merge(SWIRL, theme.swirl)
    self.clouds = Merge(CLOUDS, theme.clouds)
    self.coreStyle = Merge(CORE, theme.core)
    self.crackle = Merge(CRACKLE, theme.crackle)
    self.flicker = Merge(FLICKER, theme.flicker)
    self.shade = Merge(SHADE, theme.shade)
    self:LayerColor(self.shadeDark, self.shade.color)
    self:LayerColor(self.shadeHot, self.shade.hotColor or theme.tip)
    -- A third vein colour a little round the wheel from the first; the light clouds drift between it and
    -- swirlB, and the dark pockets take a deep shifted tint, so the inside mixes related colours.
    -- A theme can set both (Themes.FromColor's deep themes for nameplates keep to their own hue).
    self.veinC = theme.swirlC or HueShift(theme.swirlA, 0.18)
    local deep = theme.deepColor or HueShift(theme.fillA, -0.12)
    self.deep = { deep[1] * 0.3, deep[2] * 0.3, deep[3] * 0.3 }
    -- Room for extra light before the liquid washes out to white. A colour that is already bright in
    -- two channels (pale violet, gold) saturates fast, so stirs and lightning add less to it.
    local fb = theme.fillB
    local mid = fb[1] + fb[2] + fb[3] - max(fb[1], fb[2], fb[3]) - min(fb[1], fb[2], fb[3])
    self.headroom = 1 - 1.2 * max(0, mid - 0.3)
    self.bubbleStyle = Merge(BUBBLES, theme.bubbles)
    self.burst = Merge(BURST, theme.burst)
    self.ambient = nil
    if theme.ambient then
        self.ambient = {}
        for i, em in ipairs(theme.ambient) do
            self.ambient[i] = Merge(BURST, em)
        end
    end
    self.ambientAcc = {}
    self.accent = nil

    local tc = theme.tip
    for _, tip in ipairs(self.tips) do
        Color(tip, tc[1], tc[2], tc[3])
    end
    self:LayerTexture(self.swirlA, self.swirl.texture)
    self:LayerTexture(self.swirlB, self.swirl.texture)
    self:LayerTexture(self.cloudDark, self.clouds.texture)
    self:LayerTexture(self.cloudLight, self.clouds.texture)
    self:LayerColor(self.swirlA, theme.swirlA)
    self:LayerColor(self.swirlB, theme.swirlB)
    self:LayerColor(self.cloudDark, self.deep)
    self:LayerColor(self.cloudLight, theme.swirlB)
    self:LayerColor(self.core, theme.glow)
    Color(self.glow, theme.glow[1], theme.glow[2], theme.glow[3])

    -- Bubbles take on some of the veins' colour so they belong to the liquid.
    local bs, bc, vc = self.bubbleStyle, theme.bubble, theme.swirlA
    for _, b in ipairs(self.bubbles) do
        b.tex:SetTexture(MEDIA .. bs.texture)
        b.tex:SetBlendMode(bs.blend)
        b.tex.sabC = nil -- set again after SetTexture, whatever it was
        Color(b.tex, Lerp(bc[1], vc[1], 0.5), Lerp(bc[2], vc[2], 0.5), Lerp(bc[3], vc[3], 0.5))
    end
    -- Particles from the previous theme would look out of place.
    for _, m in ipairs(self.motes) do
        m.active = false
        Off(m.tex)
    end
    for _, b in ipairs(self.bolts) do
        b.active = false
        Off(b.tex)
        Off(b.glow)
    end
    -- Whatever is pouring in keeps tinting the front.
    if self.inflowTheme then self:SetInflow(self.inflowTheme, self.inflowMix) end
end

-- A texture given a new file has everything it is given each update set again, whatever SetTexture keeps.
local function Fresh(t)
    t.sabA, t.sabC, t.sabL, t.sabR, t.sabT, t.sabB, t.layerStamp = nil, nil, nil, nil, nil, nil, nil
end

function Liquid:LayerTexture(layer, name)
    local file = MEDIA .. name
    layer.main:SetTexture(file, "REPEAT", "REPEAT")
    Fresh(layer.main)
    for _, cap in ipairs(layer.caps) do
        cap:SetTexture(file, "REPEAT", "REPEAT")
        Fresh(cap)
    end
end

-- A layer's colour is kept on the layer and given to its textures as they are drawn (DrawLayer), together with their
-- alpha in one call: each texture takes the layer's colour if it changed since (its layerStamp is not the layer's
-- stamp) with the alpha in one SetVertexColor (a texture has one alpha, which its fourth value sets), or the alpha alone.
-- It counts as changed once it has moved by COLOR_STEP, as Color does.
function Liquid:LayerColor(layer, c)
    local r, g, b = c[1], c[2], c[3]
    local lr, lg, lb = layer.r, layer.g, layer.b
    if r - lr > COLOR_STEP or lr - r > COLOR_STEP or g - lg > COLOR_STEP or lg - g > COLOR_STEP
        or b - lb > COLOR_STEP or lb - b > COLOR_STEP then
        layer.r, layer.g, layer.b = r, g, b
        layer.stamp = layer.stamp + 1
    end
end

-- A layer hidden whole stays hidden until DrawLayer shows it again (nothing else shows its textures; HideAll only hides
-- more), so hiding it again is skipped (allOff): a layer whose alpha is 0 (the shading on most themes) was hidden texture
-- by texture every update.
local function HideLayer(layer)
    if layer.allOff then return end
    local main = layer.main
    if main.sabShown ~= false then
        main.sabShown = false
        main:Hide()
    end
    local caps = layer.caps
    for i = 1, #caps do
        local cap = caps[i]
        if cap.sabShown ~= false then
            cap.sabShown = false
            cap:Hide()
        end
    end
    layer.allOff = true
end

-- ku, kv: texture units per px across and down. Caps use the same mapping as the main texture,
-- so each continues it without a seam.
function Liquid:DrawLayer(layer, ku, kv, alpha)
    local back = self.back
    if back < 1 or alpha <= 0.002 then
        HideLayer(layer)
        return
    end
    -- The alpha the layer's textures are drawn at, moved once alpha has moved by COLOR_STEP.
    local drawn = layer.drawn
    if not drawn or alpha - drawn > COLOR_STEP or drawn - alpha > COLOR_STEP then
        drawn = alpha
        layer.drawn = alpha
    end
    local u, v, main, stamp = layer.u, layer.v, layer.main, layer.stamp
    -- The caps' look (colour, alpha, shown) in one test a cap: layer.key goes up whenever any of them may have changed
    -- for a cap since the last draw, which the main texture tells, as it is drawn and hidden whenever the caps are and
    -- given the same colour and alpha: a new colour (stamp), a new alpha, hidden meanwhile (HideLayer, HideAll), or a new
    -- file (Fresh). A cap whose sabKey is the layer's key has them already; the loop below clears it when it hides one.
    local key = layer.key
    if main.layerStamp ~= stamp or main.sabA ~= drawn or not main.sabShown then
        key = (key or 0) + 1
        layer.key = key
    end
    -- Width, Coords, LayerLook and On written out: the same tests and calls in the same order.
    if main.sabW ~= back then
        main.sabW = back
        main:SetWidth(back)
    end
    local m = self.mirror
    local ub = u + back * ku
    local vh = v + self.height * kv
    local l, r = u, ub
    if m then l, r = ub, u end
    if main.sabL ~= l or main.sabR ~= r or main.sabT ~= v or main.sabB ~= vh then
        main.sabL = l
        main.sabR = r
        main.sabT = v
        main.sabB = vh
        main:SetTexCoord(l, r, v, vh)
    end
    if main.layerStamp ~= stamp then
        main.layerStamp = stamp
        main.sabA = drawn
        main:SetVertexColor(layer.r, layer.g, layer.b, drawn)
    elseif main.sabA ~= drawn then
        main.sabA = drawn
        main:SetAlpha(drawn)
    end
    if not main.sabShown then
        main.sabShown = true
        main:Show()
    end
    layer.allOff = false
    -- Each slice's offsets down the texture, (i - 1) * rowH and the slice's bottom, times kv: the same products each
    -- update until the slices' height or the layer's scale changes.
    local rowH, caps = self.rowH, layer.caps
    local ty, tb = layer.ty, layer.tb
    if layer.tyKv ~= kv or layer.tyRowH ~= rowH then
        ty, tb = ty or {}, tb or {}
        for i = 1, #caps do
            local y = (i - 1) * rowH
            ty[i], tb[i] = y * kv, (y + rowH) * kv
        end
        layer.ty, layer.tb, layer.tyKv, layer.tyRowH = ty, tb, kv, rowH
    end
    -- The caps are the addon's busiest loop (seven layers a liquid, a cap a slice, every update), so Coords, LayerLook,
    -- On and Off are written out here: the same tests and the same calls, without four function calls a cap. Each cap is
    -- laid between the main texture's far end and its slice's (AnchorCaps): only its coordinates change. A loop for each
    -- direction, so no cap tests which it is.
    local ends, cr, cg, cb = self.ends, layer.r, layer.g, layer.b
    if m then
        for i = 1, #caps do
            local cap, e = caps[i], ends[i]
            if e and e - back >= 0.5 then
                local cl, top, bottom = u + e * ku, v + ty[i], v + tb[i]
                if cap.sabL ~= cl or cap.sabR ~= ub or cap.sabT ~= top or cap.sabB ~= bottom then
                    cap.sabL = cl
                    cap.sabR = ub
                    cap.sabT = top
                    cap.sabB = bottom
                    cap:SetTexCoord(cl, ub, top, bottom)
                end
                if cap.sabKey ~= key then
                    if cap.layerStamp ~= stamp then
                        cap.layerStamp = stamp
                        cap.sabA = drawn
                        cap:SetVertexColor(cr, cg, cb, drawn)
                    elseif cap.sabA ~= drawn then
                        cap.sabA = drawn
                        cap:SetAlpha(drawn)
                    end
                    if not cap.sabShown then
                        cap.sabShown = true
                        cap:Show()
                    end
                    cap.sabKey = key
                end
            elseif cap.sabShown ~= false then
                cap.sabShown = false
                cap.sabKey = nil
                cap:Hide()
            end
        end
    else
        for i = 1, #caps do
            local cap, e = caps[i], ends[i]
            if e and e - back >= 0.5 then
                local cr2, top, bottom = u + e * ku, v + ty[i], v + tb[i]
                if cap.sabL ~= ub or cap.sabR ~= cr2 or cap.sabT ~= top or cap.sabB ~= bottom then
                    cap.sabL = ub
                    cap.sabR = cr2
                    cap.sabT = top
                    cap.sabB = bottom
                    cap:SetTexCoord(ub, cr2, top, bottom)
                end
                if cap.sabKey ~= key then
                    if cap.layerStamp ~= stamp then
                        cap.layerStamp = stamp
                        cap.sabA = drawn
                        cap:SetVertexColor(cr, cg, cb, drawn)
                    elseif cap.sabA ~= drawn then
                        cap.sabA = drawn
                        cap:SetAlpha(drawn)
                    end
                    if not cap.sabShown then
                        cap.sabShown = true
                        cap:Show()
                    end
                    cap.sabKey = key
                end
            elseif cap.sabShown ~= false then
                cap.sabShown = false
                cap.sabKey = nil
                cap:Hide()
            end
        end
    end
end

-- Each slice's line is 1.5 slices tall so they overlap their neighbours on the
-- textures' ramps. The first and last drop their outer ramp so they stay inside the bar.
-- It hangs on its slice's far end, its core edgeCore across it half a pixel inside the end, so the client moves it with
-- the slice (placing it by hand was a SetPoint per slice every update). Mirrored, its right edge goes where its left would.
function Liquid:LayoutTips()
    local rowH, n = self.rowH, self.n
    local to = self.mirror and "TOPLEFT" or "TOPRIGHT"
    for i, tip in ipairs(self.tips) do
        local top, h, v0, v1 = rowH * 0.25, rowH * 1.5, 0, 1
        if i == 1 then
            top, h, v0 = 0, rowH * 1.25, 1 / 3
        elseif i == n then
            h, v1 = rowH * 1.25, 2 / 3
        end
        tip:SetSize(CFG.edgeW, h)
        if self.mirror then tip:SetTexCoord(1, 0, v0, v1) else tip:SetTexCoord(0, 1, v0, v1) end
        tip:ClearAllPoints()
        tip:SetPoint(self.aTL, self.rows[i], to, -(0.5 + CFG.edgeCore * CFG.edgeW) * self.sx, top)
    end
end

function Liquid:SetSize(width, height)
    self.width, self.height = width, height
    self.rowH = height / self.n
    for i = 1, self.n do
        self.rows[i]:SetHeight(self.rowH)
    end
    self:AnchorCaps()
    self:LayoutTips()
    self.glow:SetSize(36, height * 1.7)
end

-- Moves every texture this many sublevels down (negative) or up within its draw layer, so a second liquid
-- at the same frame level can lie under or over another. 0 puts them back as made.
function Liquid:SetSublevelOffset(offset)
    if offset == (self.offset or 0) then return end
    self.offset = offset
    self:Restack()
end

-- Moves the textures into other draw layers: map = { ARTWORK = { "BORDER", -7 }, ... } puts each layer named there
-- into another, its sublevels shifted by that much (their order kept), on top of SetSublevelOffset. nil puts them back.
-- For a bar whose frame's own textures share the bar's frame level: the client sorts the textures of every frame at a
-- level by draw layer together, so the liquid has to sit below what the game draws over its fill (the raid frames:
-- Bars.lua, RAID_LAYERS).
function Liquid:SetLayerMap(map)
    self.layerMap = map
    self:Restack()
end

function Liquid:Restack()
    local offset, map = self.offset or 0, self.layerMap
    for _, t in ipairs(self.textures) do
        local d = self.drawLayers[t]
        local layer, sub = d[1], d[2] + offset
        local m = map and map[layer]
        if m then layer, sub = m[1], sub + m[2] end
        t:SetDrawLayer(layer, max(-8, min(7, sub)))
    end
end

function Liquid:SetOptions(opts)
    self.opts = opts
    self:ApplyOptions()
end

-- Clear anything a toggle just switched off.
function Liquid:ApplyOptions()
    local opts = self.opts
    if not opts.waves then
        for i = 1, self.n do self.pos[i], self.vel[i] = 0, 0 end
    end
    if not opts.bubbles then
        for _, b in ipairs(self.bubbles) do
            b.active = false
            Off(b.tex)
        end
    end
    if not opts.lightning then
        for _, b in ipairs(self.bolts) do
            b.active = false
            Off(b.tex)
            Off(b.glow)
        end
        self.storm = 0
    end
    for _, m in ipairs(self.motes) do
        if m.active and ((m.ambient and not opts.ambient) or (not m.ambient and not opts.sparkles)) then
            m.active = false
            Off(m.tex)
        end
    end
end

--------------------------------------------------------------------------------
-- Events from the bar
--------------------------------------------------------------------------------

-- Jump the front without sloshing, e.g. on load or when a level wraps back to 0.
function Liquid:Snap(edge)
    self.edge, self.speed, self.back = edge, 0, edge
end

-- Colours for burst motes; themes with animated colours tint them with the current accent.
function Liquid:BurstColors(from, to)
    if self.accent then return from, self.accent end
    return from, to
end

-- A small push on the front alone, a ripple from a random point with no splash (no energy, charge or motes): a shield
-- lapping at the health's front (Shield.lua, through Bars.Lap).
function Liquid:Nudge(kick)
    if not self.opts.waves or self.leader then return end
    local n = self.n
    local centre = random(1, n)
    kick = kick * (1 - self.steady)
    for i = 1, n do
        local d = (i - centre) / n
        self.vel[i] = self.vel[i] + kick * exp(-d * d * 8)
    end
end

-- A gain or a stir. intensity 0..1; motes fly from fromX..toX.
function Liquid:Splash(intensity, fromX, toX)
    self.energy = min(1.5, self.energy + 0.08 + intensity * 0.9)
    -- Lightning charge: one small gain barely registers, a run of them or a big one builds a storm.
    self.charge = min(2, self.charge + 0.1 + intensity * 1.2)

    -- Ripple out from a random point on the front (a follower's front is its leader's).
    if self.opts.waves and not self.leader then
        local n = self.n
        local centre = random(1, n)
        local kick = (40 + 160 * intensity) * (1 - self.steady)
        for i = 1, n do
            local d = (i - centre) / n
            self.vel[i] = self.vel[i] + kick * exp(-d * d * 8)
        end
    end

    local h, theme, style = self.height, self.theme, self.burst
    local from, to = self:BurstColors(theme.splashFrom, theme.splashTo)
    for _ = 1, floor(1 + intensity * 18) do
        local s = 0.5 + intensity
        local life, size = Rand(0.5, 1.1) + intensity * 0.4, Rand(8, 14) * (0.7 + 0.5 * intensity)
        if style.mode == "attract" then
            local a, d = Rand(0, 2 * pi), Rand(25, 60) * (0.7 + 0.5 * intensity)
            self:EmitMote(fromX + cos(a) * d, h / 2 + sin(a) * d * 0.6, -sin(a) * 30, cos(a) * 30,
                life + 0.6, size, from, to, style)
        else
            self:EmitMote(Rand(fromX - 6, max(fromX, toX)), Rand(2, h - 2),
                Rand(-20, 60) * s, Rand(10, 70) * s, life, size, from, to, style)
        end
    end
    for _ = 1, floor(intensity * 8 * self.bubbleStyle.splash) do
        self:EmitBubble(Rand(max(4, fromX - 40), max(4, fromX - 2)))
    end
end

local function Mix(a, b, t)
    return { Lerp(a[1], b[1], t), Lerp(a[2], b[2], t), Lerp(a[3], b[3], t) }
end

-- Something pours into this liquid (Bars.Inflow): its front tip, glow and the front of its body take on that
-- theme's colours by mix (0..1). nil stops it.
function Liquid:SetInflow(theme, mix)
    self.inflowTheme, self.inflowMix = theme, mix or 0
    local own = self.theme
    local tip = theme and Mix(own.tip, theme.tip, self.inflowMix) or own.tip
    local glow = theme and Mix(own.glow, theme.glow, self.inflowMix) or own.glow
    for _, t in ipairs(self.tips) do Color(t, tip[1], tip[2], tip[3]) end
    Color(self.glow, glow[1], glow[2], glow[3])
end

-- Keep the liquid at least this lively (its energy: brighter veins and glow, livelier waves) for now.
function Liquid:Warm(level)
    if level > self.energy then self.energy = level end
end

-- Keep the lightning at least this charged for now (0..2; it starts up above about 0.3).
function Liquid:Storm(level)
    if level > self.charge then self.charge = level end
end

-- How little the front moves for all the energy in the liquid, 0..1: a build-up stays lively inside while its front
-- holds (Bars.lua).
function Liquid:SetSteady(level)
    self.steady = level
end

-- Draw this liquid's front where another's is, so the two lie over each other as one (Bars.lua's fury over the rage
-- bar's liquid): its waves are the leader's, and it only adds a quick tremble of its own, tremble px. nil lets it
-- move by itself again.
function Liquid:Follow(leader, tremble)
    self.leader, self.tremble = leader, tremble or 0
    if not leader then
        for i = 1, self.n do self.pos[i], self.vel[i] = 0, 0 end
    end
end

function Liquid:SetTremble(tremble)
    self.tremble = tremble
end

-- The idle wobble's size, px: livelier with energy, unless the front is holding steady.
function Liquid:Wobble()
    if self.leader then return self.leader:Wobble() + self.tremble end
    return self.phys.ambient * (0.6 + self.energy * (1 - self.steady))
end

-- How far slice i of the front (1 = top) stands past the liquid's edge right now, px.
-- The slice of this liquid at the same height as slice i of a front of n slices (another liquid's): liquids of
-- different heights, or made with different counts, are matched by where the slice sits.
function Liquid:SliceAt(i, n)
    if not n or n == self.n then return i end
    return max(1, min(self.n, floor((i - 0.5) * self.n / n) + 1))
end

-- n: how many slices i counts in, if not this liquid's (a seam drawn along it by a liquid of another count).
-- The waves are simulated as ever and drawn scaled by the Wave Intensity effect (opts.intensity, 1 at 100%), so every
-- way the front moves (ripples, sloshing, the lean while pouring, the idle wobble) grows or calms together.
-- SliceAt and, for a liquid of its own, Wobble are written out (the heal marker's seam asks for every slice each frame).
function Liquid:FrontOffset(i, n)
    local sn = self.n
    if n and n ~= sn then i = max(1, min(sn, floor((i - 0.5) * sn / n) + 1)) end
    local t, opts, leader = self.t, self.opts, self.leader
    if leader then
        -- The leader's offset is scaled already; the tremble is this liquid's own, scaled as Draw's cut expects (at 0%
        -- an unscaled tremble shook the fury over a flat bar and dented it past its body's end, a review found).
        local tr = opts.waves and self.tremble * (opts.intensity or 1) or 0
        return leader:FrontOffset(i, sn) + tr * (0.6 * sin(t * 37 + i * 1.7) + 0.4 * sin(t * 53 - i * 2.9))
    end
    local wobble = opts.waves and self.phys.ambient * (0.6 + self.energy * (1 - self.steady)) or 0
    return (self.pos[i] + wobble * (sin(t * 2.3 + i * 0.6) + 0.5 * sin(t * 3.7 - i * 1.1))) * (opts.intensity or 1)
end

-- A ripple along the front only: no motes, no bubbles, no lightning charge. intensity 0..1.
function Liquid:Ripple(intensity)
    if not self.opts.waves or self.leader then return end
    local n = self.n
    local centre = random(1, n)
    local kick = (40 + 160 * intensity) * (1 - self.steady)
    for i = 1, n do
        local d = (i - centre) / n
        self.vel[i] = self.vel[i] + kick * exp(-d * d * 8)
    end
end

-- Hide everything the liquid draws, e.g. while its bar shows the game's own fill. The next Update
-- shows what it needs again; particles in flight are dropped.
function Liquid:HideAll()
    for _, t in ipairs(self.textures) do Off(t) end
    for _, b in ipairs(self.bubbles) do b.active = false end
    for _, m in ipairs(self.motes) do m.active = false end
    for _, b in ipairs(self.bolts) do b.active = false end
end

-- Calm, with nothing in flight: for a liquid shown again after its frame was hidden, which stops its updates, so what
-- was flying then would otherwise carry on where it stopped. The next Update draws it again.
function Liquid:Settle()
    self:HideAll()
    self.energy, self.charge = 0, 0
    for i = 1, self.n do self.pos[i], self.vel[i] = 0, 0 end
end

-- Nothing visible is moving beyond the idle wobble and slow ambient particles, so the caller
-- can lower the update rate.
function Liquid:IsQuiet()
    if self.energy > 0.02 then return false end
    for i = 1, self.n do
        if abs(self.vel[i]) > 1 or abs(self.pos[i]) > 0.3 then return false end
    end
    for _, m in ipairs(self.motes) do
        if m.active and not m.ambient then return false end
    end
    return true
end

--------------------------------------------------------------------------------
-- Particles
--------------------------------------------------------------------------------

-- from/to are the colours the mote fades between over its life; style is a BURST-like table.
-- The pool's next mote is taken whether it is in flight or not (the oldest goes first), and listed in liveMotes once
-- while it is (UpdateParticles walks only those).
function Liquid:EmitMote(x, y, vx, vy, life, size, from, to, style, ambient)
    if ambient then
        if not self.opts.ambient then return end
    elseif not self.opts.sparkles then
        return
    end
    local motes, at = self.motes, self.moteNext
    local m = motes[at]
    self.moteNext = at % #motes + 1
    m.x, m.y, m.vx, m.vy, m.age, m.life, m.size = x, y, vx, vy, 0, life, size
    local r1, g1, b1, r2, g2, b2 = from[1], from[2], from[3], to[1], to[2], to[3]
    m.r1, m.g1, m.b1, m.r2, m.g2, m.b2 = r1, g1, b1, r2, g2, b2
    -- The colour's change over the mote's life, for UpdateParticles' Lerp (r1 + (r2 - r1) * p, the same sum).
    m.dr, m.dg, m.db = r2 - r1, g2 - g1, b2 - b1
    m.style, m.ambient = style, ambient
    -- RandRange and Rand written out: the same sums (Rand(0, 2 * pi) is 0 + (2 * pi - 0) * random(), which is
    -- 2 * pi * random() exactly), the same random numbers in the same order.
    local spin = style.spin
    if spin then
        m.spin = spin[1] + (spin[2] - spin[1]) * random()
    else
        m.spin = 0
    end
    m.rot = 2 * pi * random()
    m.phase = 2 * pi * random()
    m.wf = 3 + 4 * random() -- wander pace, rad/s (Rand(3, 7))
    if style.orient then m.rot = atan2(-vx, vy) end
    local tex = m.tex
    -- A new mote: its first update sets its colour and alpha whatever the last one's were (the colour's table kept and
    -- marked stale, not made again: a new one for every mote was garbage).
    tex.sabA = nil
    if tex.sabC then tex.sabC[1] = -1 end
    if m.file ~= style.texture then
        m.file = style.texture
        tex:SetTexture(MEDIA .. style.texture)
    end
    if m.blend ~= style.blend then
        m.blend = style.blend
        tex:SetBlendMode(style.blend)
    end
    if tex.SetRotation then tex:SetRotation((spin or style.orient) and m.rot * self.sx or 0) end
    m.active = true
    if not m.listed then
        m.listed = true
        local live = self.liveMotes
        live[#live + 1] = m
    end
    On(tex)
end

-- Continuous particles from a theme's `ambient` list (embers, snow, spores, stars...).
-- area: "liquid" anywhere in the liquid, "surface" along its top, "front" at the liquid front,
-- "vapour" off the top of the liquid just behind the front,
-- "above" over the bar so they can drift down onto it,
-- "drip" hanging from the bottom of the liquid, mostly close behind the front (within em.reach px), to fall off it.
function Liquid:EmitAmbient(em, edge)
    local w, h = self.width, self.height
    local x, y
    if em.area == "drip" then
        if edge < 8 then return end
        x, y = edge - 3 - Rand(0, min(edge - 6, em.reach or 60)) * random(), Rand(0, 2)
    elseif em.area == "front" then
        if edge < 4 or edge > w - 2 then return end
        x, y = Rand(edge - 6, edge + 1), Rand(2, h - 2)
    elseif em.area == "surface" then
        if edge < 8 then return end
        x, y = Rand(2, edge - 2), Rand(h - 5, h)
    elseif em.area == "vapour" then
        if edge < 16 or edge > w - 2 then return end
        x, y = Rand(edge - 14, edge - 2), Rand(h - 4, h)
    elseif em.area == "above" then
        x, y = Rand(0, min(w, edge + 40)), Rand(h + 4, h + 14)
    else
        if edge < 8 then return end
        x, y = Rand(2, edge - 4), Rand(2, h - 2)
    end
    local from, to = em.from or self.theme.splashFrom, em.to or self.theme.splashTo
    if self.accent then to = self.accent end
    self:EmitMote(x, y, RandRange(em.vx, 0), RandRange(em.vy, 0), RandRange(em.life, 1.5),
        RandRange(em.size, 8), from, to, em, true)
end

-- Fizz rises from the bottom, mostly small. Drifters start anywhere in the liquid and rise slowly.
-- Both are carried along by the swirl and circle in small eddies.
function Liquid:EmitBubble(x, drifter)
    if not self.opts.bubbles then return end
    local bs = self.bubbleStyle
    local s1, s2 = bs.size[1], bs.size[2]
    -- The first bubble of the pool not in flight, listed in liveBubbles once while it is.
    local pool = self.bubbles
    for i = 1, #pool do
        local b = pool[i]
        if not b.active then
            if drifter then
                b.x, b.y = x, Rand(3, self.height * 0.6)
                b.vx, b.vy = Rand(-1, 2), Rand(bs.rise[1] * 0.25, bs.rise[1] * 0.5)
                b.size = Rand(s1 * 0.8, s2 * 0.9)
                b.phase, b.freq, b.sway = Rand(0, 6.28), Rand(1.2, 2.4), 2.5
            else
                b.x, b.y = x, Rand(2, 6)
                b.vx, b.vy = Rand(2, 8), Rand(bs.rise[1], bs.rise[2])
                b.size = random() < 0.6 and Rand(s1 * 0.5, s1 * 0.8) or Rand(s1 * 0.8, s2 * 0.8)
                b.phase, b.freq, b.sway = Rand(0, 6.28), Rand(3, 6), 1.5
            end
            b.age, b.pop = 0, nil
            b.active = true
            if not b.listed then
                b.listed = true
                local live = self.liveBubbles
                live[#live + 1] = b
            end
            On(b.tex)
            return
        end
    end
end

-- A flash somewhere inside the liquid, clear of the front. Arcs keep Bolt.tga's proportions, so they
-- run several bar heights long rather than being squeezed. With little charge it is a faint glow only;
-- with more it gets longer, brighter and fires more strokes.
function Liquid:EmitBolt()
    if not self.opts.lightning then return end
    local cr, back, h = self.crackle, self.back, self.height
    local p = min(1, self.charge / 1.2)
    local l1, l2 = cr.length[1], cr.length[2]
    local w = min(Rand(l1, l1 + (l2 - l1) * max(0.3, p)) * h, back - 12)
    if w < h * 2 then return end
    local bolts = self.bolts
    for i = 1, #bolts do
        local b = bolts[i]
        if not b.active then
            b.x, b.w = Rand(4, back - 8 - w), w
            local s1, s2 = cr.strokes[1], cr.strokes[2]
            b.strokes = p < 0.25 and random(1, 2) or random(s1, floor(Lerp(s1, s2, p) + 0.5))
            b.next, b.flash = 0, 0
            b.power = 0.35 + 0.65 * p
            b.sheet = p < 0.25 or random() < cr.sheet
            -- The arc is nearly white with a hint of colour; the bloom carries the cloud's colour.
            -- A theme with pure light (nameplates' deep themes) keeps both to its colour.
            local c = cr.color or self.accent or self.theme.swirlB
            local g = self.veinC
            local wa, wg = 0.6, 0.35
            if self.theme.pureLight then wa, wg = 0, 0 end
            -- A sheet flash's arc is never shown (UpdateBolts), so it is not tinted.
            if not b.sheet then
                b.tex:SetVertexColor(Lerp(c[1], 1, wa), Lerp(c[2], 1, wa), Lerp(c[3], 1, wa))
            end
            b.glow:SetVertexColor(Lerp(g[1], 1, wg), Lerp(g[2], 1, wg), Lerp(g[3], 1, wg))
            b.active = true
            if not b.sheet then On(b.tex) end
            On(b.glow)
            return
        end
    end
end

-- Each stroke flashes bright and dies away fast, with a new arc shape and the bloom somewhere new along
-- it. Arcs ride the swirl. self.storm is how much lightning is lit, which brightens the clouds and core.
-- What the liquid gives each update is looked up once, at the first bolt in flight (most updates have none), and the
-- stroke's fade, the same for every bolt, worked out once. A sheet flash's arc texture is never shown (EmitBolt), so it
-- is not sized, placed or faded; a bolt let go hides it, and one let go again as an arc gets all of that, and its first
-- stroke's arc, in the update that lets it go. Sizes are set again only when they change (b.tw, b.th, b.gw, b.gh).
function Liquid:UpdateBolts(dt)
    local bolts = self.bolts
    local storm = 0
    local fade, cr, back, h, parent, flowX, lightning, aTL, aL, sx, arcH, arcY
    for i = 1, #bolts do
        local b = bolts[i]
        if b.active then
            if not fade then
                fade = exp(-dt / 0.07)
                cr, back, h, parent, flowX = self.crackle, self.back, self.height, self.parent, self.flowX
                lightning, aTL, aL, sx = self.opts.lightning, self.aTL, self.aL, self.sx
                arcH, arcY = h * 0.9, -h * 0.05
            end
            local sheet, tex, glow = b.sheet, b.tex, b.glow
            local strokes = b.strokes
            local nextAt = b.next - dt
            if nextAt <= 0 and strokes > 0 then
                strokes = strokes - 1
                b.strokes = strokes
                b.flash = Rand(0.7, 1)
                b.at = Rand(0.25, 0.75)
                nextAt = Rand(0.07, 0.22)
                -- RollBolt: one of Bolt.tga's arcs, flipped at random (the same random numbers whether it is drawn).
                local k, n = random(0, CFG.boltRows - 1), CFG.boltRows
                local u0, u1 = 0, 1
                local v0, v1 = k / n, (k + 1) / n
                if random() < 0.5 then u0, u1 = 1, 0 end
                if random() < 0.5 then v0, v1 = v1, v0 end
                if not sheet then tex:SetTexCoord(u0, u1, v0, v1) end
            end
            b.next = nextAt
            local flash = b.flash * fade
            b.flash = flash
            local x = b.x + flowX * dt
            -- Keep clear of the front: slide back first, and only shorten if there is no room.
            local over = x + b.w - (back - 2)
            if over > 0 then x = max(2, x - over) end
            b.x = x
            local w = min(b.w, back - 2 - x)
            if (strokes == 0 and flash < 0.03) or w < h * 2 or not lightning then
                b.active = false
                if tex.sabShown ~= false then
                    tex.sabShown = false
                    tex:Hide()
                end
                if glow.sabShown ~= false then
                    glow.sabShown = false
                    glow:Hide()
                end
            else
                local lit = flash * b.power
                if not sheet then
                    if b.tw ~= w or b.th ~= arcH then
                        b.tw, b.th = w, arcH
                        tex:SetSize(w, arcH)
                    end
                    tex:SetPoint(aTL, parent, aTL, x * sx, arcY)
                    tex:SetAlpha(min(1, cr.alpha * lit))
                end
                local gw = w * (sheet and 0.8 or 0.6)
                local gx = max(x + gw / 2, min(x + w - gw / 2, x + w * b.at))
                if b.gw ~= gw or b.gh ~= h then
                    b.gw, b.gh = gw, h
                    glow:SetSize(gw, h)
                end
                glow:SetPoint("CENTER", parent, aL, gx * sx, 0)
                glow:SetAlpha(min(1, cr.glow * lit * (sheet and 1.3 or 1)))
                storm = storm + lit
            end
        end
    end
    if not (storm < 1) then storm = 1 end -- min(1, storm)
    self.storm = storm
end

-- Only the bubbles and motes in flight are walked (liveBubbles, liveMotes; a liquid's pools hold 100, and walking them
-- all every update was a third of this function's Lua), in the order they were let go: each moves and draws only its
-- own texture, so the order does not change what is drawn. One let go elsewhere (HideAll, ApplyOptions, SetTheme only
-- clear active) leaves the list here. Alpha, Look, Off and Lerp are written out: the same tests, sums and calls.
function Liquid:UpdateParticles(dt)
    local liveB, liveM = self.liveBubbles, self.liveMotes
    local nb, nm = #liveB, #liveM
    if nb == 0 and nm == 0 then return end
    local parent, h, edge, t = self.parent, self.height, self.edge, self.t
    local bl, sx = self.aBL, self.sx

    if nb > 0 then
        local bubbleAlpha = self.bubbleStyle.alpha
        local fx, fy, carry = self.flowX, self.flowY, self.speed * 0.3
        local kept = 0
        for i = 1, nb do
            local b = liveB[i]
            if b.active then
                local tex = b.tex
                local pop = b.pop
                local a -- the bubble's alpha, if it is drawn
                if pop then
                    pop = pop + dt
                    b.pop = pop
                    local p = pop / 0.15
                    if p >= 1 then
                        b.active = false
                        if tex.sabShown ~= false then
                            tex.sabShown = false
                            tex:Hide()
                        end
                    else
                        local s = b.size * (1 + p)
                        tex:SetSize(s, s)
                        a = bubbleAlpha * (1 - p)
                    end
                else
                    local age = b.age + dt
                    b.age = age
                    local x = b.x + (b.vx + fx + carry) * dt
                    local y = b.y + (b.vy + fy) * dt
                    b.x, b.y = x, y
                    -- Fades in, and grows a little on the way up as the pressure drops.
                    local size = b.size * (1 + 0.25 * y / h)
                    if y >= h - size * 0.5 or x > edge - 2 then
                        b.pop, b.size = 0, size -- the pop grows from here
                    end
                    tex:SetSize(size, size)
                    local f = age / 0.25 -- min(1, age / 0.25)
                    if not (f < 1) then f = 1 end
                    a = bubbleAlpha * f
                end
                if a then
                    local was = tex.sabA
                    if not was or a - was > COLOR_STEP or was - a > COLOR_STEP then
                        tex.sabA = a
                        tex:SetAlpha(a)
                    end
                end
                -- Placed even as it goes, as ever.
                local ph, sway = b.phase + t * b.freq, b.sway
                tex:SetPoint("CENTER", parent, bl, (b.x + sin(ph) * sway) * sx, b.y + cos(ph) * sway * 0.6)
            end
            if b.active then
                kept = kept + 1
                liveB[kept] = b
            else
                b.listed = false
            end
        end
        for i = kept + 1, nb do liveB[i] = nil end
    end

    if nm > 0 then
        local rotates = liveM[1].tex.SetRotation
        local halfH = h / 2
        -- What a mote's style gives it, worked out again only when a mote's style is not the last one's (a liquid's
        -- motes mostly share one): the same values, from the same sums.
        local last, drag, attract, lift, wander, grow, twinkle, orient, styleAlpha
        local kept = 0
        for i = 1, nm do
            local m = liveM[i]
            if m.active then
                local st = m.style
                if st ~= last then
                    last = st
                    drag = exp(-(st.drag or 1.8) * dt)
                    attract = st.mode == "attract"
                    lift = (st.buoyancy or 20) * dt
                    wander, grow, orient, styleAlpha = st.wander, st.grow, st.orient, st.alpha or 1
                    twinkle = st.twinkle
                    if twinkle then twinkle = t * twinkle * 2 * pi end
                end
                local tex = m.tex
                local age = m.age + dt
                m.age = age
                local p = age / m.life
                local done = p >= 1
                local vx, vy = m.vx, m.vy
                if not done then
                    if attract then
                        -- Pulled toward the middle of the liquid front, faster as they close in.
                        local dx, dy = edge - m.x, halfH - m.y
                        local d = sqrt(dx * dx + dy * dy)
                        if d < 4 then
                            done = true
                        else
                            local pull = 500 + 4000 / (d + 10)
                            vx = (vx + dx / d * pull * dt) * drag
                            vy = (vy + dy / d * pull * dt) * drag
                            m.vx, m.vy = vx, vy
                        end
                    else
                        vx = vx * drag
                        vy = vy * drag + lift
                        if wander then
                            vx = vx + wander * sin(m.phase + age * m.wf) * dt
                        end
                        m.vx, m.vy = vx, vy
                    end
                end
                if done then
                    m.active = false
                    if tex.sabShown ~= false then
                        tex.sabShown = false
                        tex:Hide()
                    end
                else
                    local x, y = m.x + vx * dt, m.y + vy * dt
                    m.x, m.y = x, y
                    local size, alpha
                    if m.ambient then
                        -- Lingering particles: fade in, hold, fade out (min(1, p / 0.2, (1 - p) / 0.3)).
                        size = m.size * (1 - 0.2 * p)
                        alpha = 1
                        local fade = p / 0.2
                        if fade < alpha then alpha = fade end
                        fade = (1 - p) / 0.3
                        if fade < alpha then alpha = fade end
                    else
                        -- Bursts flare and die away.
                        size = m.size * (1 - 0.5 * p)
                        alpha = (p < 0.1 and p / 0.1 or 1) * (1 - p) ^ 1.5
                    end
                    if grow then
                        size = m.size * min(1, 0.3 + 0.7 * p / 0.2) * (1 - 0.3 * p)
                    end
                    if twinkle then
                        alpha = alpha * (0.55 + 0.45 * sin(m.phase + twinkle))
                    end
                    if orient and rotates then
                        -- Rotation is counter-clockwise from straight up.
                        local rot = atan2(-vx, vy)
                        m.rot = rot
                        tex:SetRotation(rot * sx)
                    elseif m.spin ~= 0 and rotates then
                        local rot = m.rot + m.spin * dt
                        m.rot = rot
                        tex:SetRotation(rot * sx)
                    end
                    tex:SetSize(size, size)
                    -- Look: one SetVertexColor with the alpha when the colour moved by COLOR_STEP, else the alpha alone.
                    local r, g, b, a = m.r1 + m.dr * p, m.g1 + m.dg * p, m.b1 + m.db * p, alpha * styleAlpha
                    local c = tex.sabC
                    if not c or r - c[1] > COLOR_STEP or c[1] - r > COLOR_STEP or g - c[2] > COLOR_STEP
                        or c[2] - g > COLOR_STEP or b - c[3] > COLOR_STEP or c[3] - b > COLOR_STEP then
                        if not c then
                            c = {}
                            tex.sabC = c
                        end
                        c[1], c[2], c[3] = r, g, b
                        tex.sabA = a
                        tex:SetVertexColor(r, g, b, a)
                    else
                        local was = tex.sabA
                        if not was or a - was > COLOR_STEP or was - a > COLOR_STEP then
                            tex.sabA = a
                            tex:SetAlpha(a)
                        end
                    end
                    tex:SetPoint("CENTER", parent, bl, x * sx, y)
                end
            end
            if m.active then
                kept = kept + 1
                liveM[kept] = m
            else
                m.listed = false
            end
        end
        for i = kept + 1, nm do liveM[i] = nil end
    end
end

--------------------------------------------------------------------------------
-- Simulation and drawing
--------------------------------------------------------------------------------

function Liquid:Simulate(dt)
    if self.leader then return end
    local pos, vel, n, phys = self.pos, self.vel, self.n, self.phys
    local lean, shape = self.lean, self.leanShape
    local k, d, c, limit = phys.stiffness, phys.damping + STEADY_DAMPING * self.steady, phys.coupling, phys.amplitude * 1.2
    local s = CFG.step

    -- At most 16 steps a frame: room for a 20 fps party liquid at double Animation Speed (plain arithmetic, no widget
    -- calls; 8 held it back to 1.33 times).
    self.acc = min(self.acc + dt, s * 16)
    while self.acc >= s do
        self.acc = self.acc - s
        -- Springs and neighbour coupling act on the offset from the lean, so the front holds the lean's
        -- shape and ripples run over it as usual. One pass: each slice's offset is worked out once and carried to the
        -- next (qa above, q this one, qb below, from positions not yet moved this step), and the slice is moved as soon
        -- as its speed is known. The same sums in the same order as two passes, a third of the Lua work.
        local q = pos[1] - lean * shape[1]
        local qa = q -- the top slice has none above: its own
        for i = 1, n do
            local qb = i < n and pos[i + 1] - lean * shape[i + 1] or q
            local v = vel[i] + (-k * q - d * vel[i] + c * (qa + qb - 2 * q)) * s
            local p = pos[i] + v * s
            if p > limit then
                p, v = limit, 0
            elseif p < -limit then
                p, v = -limit, 0
            end
            pos[i], vel[i] = p, v
            qa, q = q, qb
        end
    end
end

-- dt is real time. The bar's fill speed and the lean are measured in it, as the edge follows the game's bar; everything
-- the liquid does on its own runs on its own clock, dt scaled by the Animation Speed effect (opts.speed, 1 at 100%).
function Liquid:Update(dt, edge)
    local lap = Timing.on and profileClock and profileClock()
    local opts = self.opts
    local waves = opts.waves
    local real = dt
    dt = dt * (opts.speed or 1)
    local t = self.t + dt
    self.t = t

    -- The liquid's inertia: speeding up drags the front back, slowing down sloshes it forward.
    local speed = (edge - self.edge) / real
    local dv = speed - self.speed
    self.edge = edge
    self.speed = speed
    if dv ~= 0 and waves and not self.leader then
        local kick = -dv * self.phys.slosh
        local n, vel = self.n, self.vel
        for i = 1, n do
            vel[i] = vel[i] + kick * sin(pi * (i - 0.5) / n)
        end
    end
    -- Pouring fast, the front leans: the top runs ahead and the bottom drags. The lean moves where the
    -- springs pull the front, so when the pour slows it rocks back and settles by itself. min(1, max(0, speed) / 250)
    -- written out.
    local leanTo = 0
    if waves then
        local p = speed
        if not (p > 0) then p = 0 end
        p = p / 250
        if not (p < 1) then p = 1 end
        leanTo = self.phys.crest * p
    end
    local lean = self.lean
    self.lean = lean + (leanTo - lean) * (1 - exp(-14 * real))

    -- Themes that stir themselves (Shadow's slow swells) do it here, before the physics step.
    local theme = self.theme
    if theme.Animate then theme:Animate(self, t, dt) end

    self:Simulate(dt)
    self.energy = self.energy * exp(-CFG.energyDecay * dt)

    -- What the liquid throws off: each accumulator counted in a local and stored once (the emitters do not read them).
    local bs, energy = self.bubbleStyle, self.energy
    local rate = bs.rate
    local acc = self.fizzAcc + dt * (rate + energy * bs.energyRate)
    while acc >= 1 do
        acc = acc - 1
        if edge > 16 then self:EmitBubble(Rand(4, edge - 8)) end
    end
    self.fizzAcc = acc
    acc = self.driftAcc + dt * rate * bs.drift
    while acc >= 1 do
        acc = acc - 1
        if edge > 24 then self:EmitBubble(Rand(4, edge - 14), true) end
    end
    self.driftAcc = acc

    local cr = self.crackle
    local charge = self.charge * exp(-0.5 * dt)
    self.charge = charge
    -- max(0, charge - 0.3) ^ 1.3, without the power when it is 0 ^ 1.3 (0): the same sum.
    local over = charge - 0.3
    acc = self.crackleAcc + dt * (cr.rate + cr.energyRate * (over > 0 and over ^ 1.3 or 0))
    while acc >= 1 do
        acc = acc - 1
        self:EmitBolt()
    end
    self.crackleAcc = acc

    local ambient = self.ambient
    if ambient and self.opts.ambient then
        local accs = self.ambientAcc
        for i = 1, #ambient do
            local em = ambient[i]
            acc = (accs[i] or 0) + dt * (em.rate + (em.energyRate or 0) * energy)
            while acc >= 1 do
                acc = acc - 1
                self:EmitAmbient(em, edge)
            end
            accs[i] = acc
        end
    end

    if lap then lap = Lap("all liquids > waves and what they throw", lap) end
    self:Draw(dt)
    if lap then lap = Lap("all liquids > drawing", lap) end
    self:UpdateBolts(dt)
    self:UpdateParticles(dt)
    if lap then Lap("all liquids > lightning, bubbles, motes", lap) end
end

-- Draw is the liquid's busiest code after its caps (DrawLayer), so the helpers it used a slice (Place, Width, Alpha, On,
-- Off, min, max, abs, FrontOffset) are written out in it: the same tests and calls, and the same sums in the same order,
-- so every texture gets exactly what it got from them.
function Liquid:Draw(dt)
    local parent, w, h, amp = self.parent, self.width, self.height, self.phys.amplitude
    local edge, energy, t = self.edge, self.energy, self.t
    local opts, theme, leader = self.opts, self.theme, self.leader
    local waves, intensity = opts.waves, opts.intensity or 1
    local S = COLOR_STEP
    local wobble = 0
    if waves then
        if leader then
            wobble = self:Wobble()
        else
            wobble = self.phys.ambient * (0.6 + energy * (1 - self.steady))
        end
    end
    -- The body stops behind the deepest dent Simulate and the wobble allow (as FrontOffset scales them), so no slice of
    -- the front ever falls behind it and flattens into the body's straight end.
    local base = edge - (amp * 1.2 + wobble * 1.5) * intensity - 0.5
    if not (base > 0) then base = 0 end

    local fa1, fa2, fa3, fb1, fb2, fb3
    if theme.Colors then
        -- Animated themes pick their colours each frame from time and progress.
        local fa, fb, accent = theme:Colors(t, w > 0 and edge / w or 0)
        fa1, fa2, fa3, fb1, fb2, fb3 = fa[1], fa[2], fa[3], fb[1], fb[2], fb[3]
        self.accent = accent
        if accent then
            Color(self.glow, accent[1], accent[2], accent[3])
            self:LayerColor(self.swirlA, accent)
            self:LayerColor(self.core, accent)
        end
    else
        local fa, fb = theme.fillA, theme.fillB
        fa1, fa2, fa3, fb1, fb2, fb3 = fa[1], fa[2], fa[3], fb[1], fb[2], fb[3]
        local inflow = self.inflowTheme
        if inflow then
            -- Mix(fb, inflow.fillB, mix), without a table each update.
            local ib, mix = inflow.fillB, self.inflowMix
            fb1, fb2, fb3 = fb1 + (ib[1] - fb1) * mix, fb2 + (ib[2] - fb2) * mix, fb3 + (ib[3] - fb3) * mix
        end
    end

    -- Flicker: a smoothed random walk to a new brightness a few times a second, with a waver on top.
    local fl, k = self.flicker, 1
    if fl.amount > 0 then
        self.flickNext = self.flickNext - dt
        if self.flickNext <= 0 then
            self.flickNext, self.flickGoal = Rand(0.5, 1.5) / fl.rate, Rand(-1, 1)
        end
        self.flickV = self.flickV + (self.flickGoal - self.flickV) * (1 - exp(-fl.rate * 2.5 * dt))
        k = 1 + fl.amount * (0.65 * self.flickV + 0.35 * sin(t * fl.rate * 4.6 + sin(t * 1.7) * 2))
    end
    self.flick = k

    -- Gradient stretched over the whole fill, like the WeakAura; the body stops where the front begins.
    -- The colours change a little every update (the cut behind the front moves with the wobble, a flicker), so they are
    -- given to the body and slices again once one has moved by COLOR_STEP, as Color does. min(1, x) is x below 1, else 1.
    local tb = edge > 0 and base / edge or 0
    local g = self.gradNow
    local ar, ag, ab = fa1 * k, fa2 * k, fa3 * k
    if not (ar < 1) then ar = 1 end
    if not (ag < 1) then ag = 1 end
    if not (ab < 1) then ab = 1 end
    local br, bg, bb = (fa1 + (fb1 - fa1) * tb) * k, (fa2 + (fb2 - fa2) * tb) * k, (fa3 + (fb3 - fa3) * tb) * k
    if not (br < 1) then br = 1 end
    if not (bg < 1) then bg = 1 end
    if not (bb < 1) then bb = 1 end
    local cr, cg, cb = fb1 * k, fb2 * k, fb3 * k
    if not (cr < 1) then cr = 1 end
    if not (cg < 1) then cg = 1 end
    if not (cb < 1) then cb = 1 end
    -- The middle colour first: it moves with the cut behind the front, the others only with a flicker or a theme's.
    local g4, g5, g6 = g[4], g[5], g[6]
    if br - g4 > S or g4 - br > S or bg - g5 > S or g5 - bg > S or bb - g6 > S or g6 - bb > S
        or ar - g[1] > S or g[1] - ar > S or ag - g[2] > S or g[2] - ag > S or ab - g[3] > S or g[3] - ab > S
        or cr - g[7] > S or g[7] - cr > S or cg - g[8] > S or g[8] - cg > S or cb - g[9] > S or g[9] - cb > S then
        g[1] = ar
        g[2] = ag
        g[3] = ab
        g[4] = br
        g[5] = bg
        g[6] = bb
        g[7] = cr
        g[8] = cg
        g[9] = cb
        self.gradA:SetRGBA(ar, ag, ab, 1)
        self.gradB:SetRGBA(br, bg, bb, 1)
        self.gradC:SetRGBA(cr, cg, cb, 1)
        self.gradStamp = self.gradStamp + 1
    end
    local stamp = self.gradStamp

    local body, mirror = self.body, self.mirror
    if base >= 0.5 then
        if body.gradStamp ~= stamp then
            body.gradStamp = stamp
            if mirror then
                body:SetGradient("HORIZONTAL", self.gradB, self.gradA)
            else
                body:SetGradient("HORIZONTAL", self.gradA, self.gradB)
            end
        end
        if body.sabW ~= base then
            body.sabW = base
            body:SetWidth(base)
        end
        if not body.sabShown then
            body.sabShown = true
            body:Show()
        end
    elseif body.sabShown ~= false then
        body.sabShown = false
        body:Hide()
    end

    local e1 = energy -- min(1, energy)
    if not (e1 < 1) then e1 = 1 end
    local tipAlpha = (0.25 + 0.5 * e1) * k
    local rowH, back, ends, n = self.rowH, edge, self.ends, self.n
    local rows, tips, pos, vel = self.rows, self.tips, self.pos, self.vel
    local gradB, gradC = self.gradB, self.gradC
    local aTL, x = self.aTL, base * self.sx
    -- Each slice's offset down the bar, -(i - 1) * rowH, kept until the slices' height changes.
    local rowY = self.rowY
    if self.rowYH ~= rowH then
        rowY = rowY or {}
        for i = 1, n do rowY[i] = -(i - 1) * rowH end
        self.rowY, self.rowYH = rowY, rowH
    end
    -- What the slices' tests share: where the liquid ends in a slice dented past the body is the body's end, if it shows.
    local edgeOn, edgeOff = edge >= 0.5, edge < 0.5
    local baseEnd = base >= 0.5 and base
    -- A follower (the fury) draws its leader's front, FrontOffset's sum for the leader worked out here with what it
    -- shares across slices (the leader's wobble, the tremble's size), when its leader has no leader of its own.
    local direct = leader and not leader.leader
    local lpos, lvel, lt, ln, lwob, lint, tr
    if direct then
        local lopts = leader.opts
        lpos, lvel, lt, ln = leader.pos, leader.vel, leader.t, leader.n
        lwob = lopts.waves and leader:Wobble() or 0
        lint = lopts.intensity or 1
        tr = waves and self.tremble * intensity or 0
    end
    for i = 1, n do
        local row, tip = rows[i], tips[i]
        local off, j
        if not leader then
            off = (pos[i] + wobble * (sin(t * 2.3 + i * 0.6) + 0.5 * sin(t * 3.7 - i * 1.1))) * intensity
        elseif direct then
            -- The leader's slice at this one's height (SliceAt).
            j = i
            if ln ~= n then j = max(1, min(ln, floor((i - 0.5) * ln / n) + 1)) end
            off = (lpos[j] + lwob * (sin(lt * 2.3 + j * 0.6) + 0.5 * sin(lt * 3.7 - j * 1.1))) * lint
                + tr * (0.6 * sin(t * 37 + i * 1.7) + 0.4 * sin(t * 53 - i * 2.9))
        else
            off = self:FrontOffset(i)
        end
        local right = edge + off -- min(w, edge + off)
        if not (right < w) then right = w end
        local rw = right - base
        -- Where the liquid visibly ends in this slice: a slice dented past the body shows the body's end.
        local vis = edgeOn and (rw >= 0.5 and right or baseEnd) or nil
        ends[i] = vis
        if vis and vis < back then back = vis end
        if edgeOff or rw < 0.5 then
            if row.sabShown ~= false then
                row.sabShown = false
                row:Hide()
            end
            if tip.sabShown ~= false then
                tip.sabShown = false
                tip:Hide()
            end
        else
            local y = rowY[i]
            if row.gradStamp ~= stamp then
                row.gradStamp = stamp
                if mirror then
                    row:SetGradient("HORIZONTAL", gradC, gradB)
                else
                    row:SetGradient("HORIZONTAL", gradB, gradC)
                end
            end
            if row.sabX ~= x or row.sabY ~= y then
                row.sabX = x
                row.sabY = y
                row:SetPoint(aTL, parent, aTL, x, y)
            end
            if row.sabW ~= rw then
                row.sabW = rw
                row:SetWidth(rw)
            end
            if not row.sabShown then
                row.sabShown = true
                row:Show()
            end
            if right < w - 1 then
                -- The tip hangs on the slice's end (LayoutTips).
                -- A moving slice glows brighter, as much as Wave Intensity lets it move.
                local v
                if not leader then
                    v = vel[i]
                elseif direct then
                    v = lvel[j]
                else
                    v = leader.vel[leader:SliceAt(i, n)]
                end
                if v < 0 then v = -v end
                local a = tipAlpha + v * 0.01 * intensity
                if not (a < 1) then a = 1 end
                local was = tip.sabA
                if not was or a - was > S or was - a > S then
                    tip.sabA = a
                    tip:SetAlpha(a)
                end
                if not tip.sabShown then
                    tip.sabShown = true
                    tip:Show()
                end
            elseif tip.sabShown ~= false then
                tip.sabShown = false
                tip:Hide()
            end
        end
    end

    if not (back > 0) then back = 0 end -- max(0, back)
    self.back = back

    -- Inside the liquid, back to front: dark cloud pockets, light wisps and the glowing core, then the
    -- magic veins. All drift with the theme's flow, faster and brighter with energy and fill speed.
    local swirlA, swirlB, cloudDark, cloudLight, core = self.swirlA, self.swirlB, self.cloudDark, self.cloudLight, self.core
    if back >= 1 and opts.swirl then
        local sw, cl, co = self.swirl, self.clouds, self.coreStyle
        local speed = self.speed -- max(0, speed)
        if not (speed > 0) then speed = 0 end
        local flow = 0.015 + 0.12 * energy + speed / 2000
        local fu, fv = sw.flow[1], sw.flow[2]
        -- A rising texture moves up the screen as its v grows; swirlB rises a little slower, for depth.
        local rise = sw.rise / SWIRL_H
        swirlA.u = (swirlA.u - flow * fu * dt) % 1
        swirlA.v = (swirlA.v + (rise - flow * fv) * dt) % 1
        swirlB.u = (swirlB.u - flow * fu * 0.6 * dt) % 1
        swirlB.v = (swirlB.v + (0.03 + rise * 0.5 - flow * fv * 0.6) * dt) % 1
        cloudDark.u = (cloudDark.u - (0.004 + flow * fu * 0.3) * dt) % 1
        cloudDark.v = (cloudDark.v + (0.008 - flow * fv * 0.3) * dt) % 1
        cloudLight.u = (cloudLight.u - (0.006 + flow * fu * 0.45) * dt) % 1
        cloudLight.v = (cloudLight.v - (0.012 + flow * fv * 0.45) * dt) % 1
        core.u = (core.u - (0.01 + flow * 0.3) * dt) % 1
        -- How fast the veins move on screen, px/s with y up, so bubbles can ride along with them.
        self.flowX, self.flowY = flow * fu * SWIRL_W, sw.rise - flow * fv * SWIRL_H

        -- The light clouds and the second veins trade between swirlB and the third colour, out of step (LayerColor
        -- written out, the colour Lerp's).
        local mix, vb, vcol = 0.5 + 0.5 * sin(t * 2 * pi / 9), theme.swirlB, self.veinC
        local vb1, vb2, vb3, vc1, vc2, vc3 = vb[1], vb[2], vb[3], vcol[1], vcol[2], vcol[3]
        local r, gg, b = vb1 + (vc1 - vb1) * mix, vb2 + (vc2 - vb2) * mix, vb3 + (vc3 - vb3) * mix
        local lr, lg, lb = cloudLight.r, cloudLight.g, cloudLight.b
        if r - lr > S or lr - r > S or gg - lg > S or lg - gg > S or b - lb > S or lb - b > S then
            cloudLight.r, cloudLight.g, cloudLight.b = r, gg, b
            cloudLight.stamp = cloudLight.stamp + 1
        end
        mix = 1 - mix
        r, gg, b = vb1 + (vc1 - vb1) * mix, vb2 + (vc2 - vb2) * mix, vb3 + (vc3 - vb3) * mix
        lr, lg, lb = swirlB.r, swirlB.g, swirlB.b
        if r - lr > S or lr - r > S or gg - lg > S or lg - gg > S or b - lb > S or lb - b > S then
            swirlB.r, swirlB.g, swirlB.b = r, gg, b
            swirlB.stamp = swirlB.stamp + 1
        end

        local cs = cl.scale
        self:DrawLayer(cloudDark, cs / SWIRL_W, cs / SWIRL_H, cl.dark)
        -- Lightning lights the clouds from inside.
        local room = self.headroom
        local storm = self.storm * room
        local a = cl.light * (1 + energy * room + storm * 1.2)
        if not (a < 1) then a = 1 end
        self:DrawLayer(cloudLight, cs * 1.4 / SWIRL_W, cs * 1.4 / SWIRL_H, a)
        local glow = 0.2 + 0.07 * sin(t * co.pulseRate * 2 * pi) + 0.3 * e1 * room + 0.15 * storm
        a = glow * co.alpha * k
        if not (a < 1) then a = 1 end
        self:DrawLayer(core, 0.5 / SWIRL_W, 1 / h, a)

        local pulse = sw.pulse * (0.5 + 0.5 * sin(t * sw.pulseRate * 2 * pi))
        local swa = sw.alpha
        a = (0.12 + 0.3 * energy * room + pulse) * swa * k
        if not (a < 1) then a = 1 end
        self:DrawLayer(swirlA, 1 / SWIRL_W, 1 / SWIRL_H, a)
        a = (0.08 + 0.22 * energy * room + 0.05 * sin(t * 1.3) + pulse * 0.6) * swa * k
        if not (a < 1) then a = 1 end
        self:DrawLayer(swirlB, 0.7 / SWIRL_W, 0.7 / SWIRL_H, a)
    else
        self.flowX, self.flowY = 0, 0
        HideLayer(cloudDark)
        HideLayer(cloudLight)
        HideLayer(core)
        HideLayer(swirlA)
        HideLayer(swirlB)
    end

    -- Height shading is part of the colour, so it stays when the swirl is off. The hot base burns brighter
    -- with energy; DrawLayer hides a layer whose alpha is 0.
    local sh = self.shade
    local a = sh.hot * k * k * (1 + 0.5 * e1)
    if not (a < 1) then a = 1 end
    self:DrawLayer(self.shadeHot, 0, -1 / h, a)
    self:DrawLayer(self.shadeDark, 0, 1 / h, sh.dark * (1 - 0.3 * e1))

    local glowTex = self.glow
    if edge > 1 and edge < w - 1 then
        -- Place, Alpha and On written out.
        local gx = edge * self.sx
        if glowTex.sabX ~= gx or glowTex.sabY ~= 0 then
            glowTex.sabX = gx
            glowTex.sabY = 0
            glowTex:SetPoint("CENTER", parent, self.aL, gx, 0)
        end
        a = (0.12 + 0.55 * energy) * k
        if not (a < 1) then a = 1 end
        local was = glowTex.sabA
        if not was or a - was > S or was - a > S then
            glowTex.sabA = a
            glowTex:SetAlpha(a)
        end
        if not glowTex.sabShown then
            glowTex.sabShown = true
            glowTex:Show()
        end
    elseif glowTex.sabShown ~= false then
        glowTex.sabShown = false
        glowTex:Hide()
    end
end
