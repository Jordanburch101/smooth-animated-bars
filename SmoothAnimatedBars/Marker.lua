-- The DoT marker on the target frame's health bar, and the kill icon on its portrait (the dots setting).
--
-- The marker is liquid eating into the health: the health the player's DoTs will still burn away turns into
-- liquid of the DoTs' own colour (Shadow, Fire, Plague for Nature, ...), one liquid per school, and the health
-- liquid draws back to where the target's health will end once they are done. If the health liquid is gone,
-- the DoTs will kill the target. The numbers come from Dots.lua; the target's health is secret, so, as for the
-- liquid (Bars.lua), the client does every comparison:
--   * a hidden StatusBar of ours takes the game bar's (secret) value, so its fill ends where the game's does;
--   * one hidden "run" StatusBar per DoT liquid, each one bar-width wide with its right edge on that fill's
--     edge, fills from the right on the bar's own (secret) range with a running total of the damage: the first
--     with the first school's, the second with both. Each fill's left edge is where that liquid ends; the
--     last one's is where the health will end;
--   * each DoT liquid hangs on the edge in front of it (the health's edge, or the first liquid's end) like the
--     health liquid does, in a clip frame starting a little before its own end. The health liquid's front is
--     moved onto the last end (Bars.Front). Each liquid is drawn under the one behind it (health over the
--     second, the second over the first), so they meet in wavy fronts, and nothing shows between them;
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
-- How far a DoT liquid reaches under the liquid behind it, so the waves never open a gap between them.
local OVERLAP = 6
-- Two DoT liquids, by school, oldest first: the first at the health's edge, the second behind it. Liquid.lua
-- draws in sublevels 3 to 7 of a layer (of -8 to 7), so there is room for the health liquid and two under it:
-- the second shifted down by 5 (to -2..2), the first by 10 (to -7..-3). A third school joins the second.
local LIQUIDS = 2
local UNDER = { -10, -5 }
local IDLE_FPS = 30
local ICON_ATLAS = "UI-HUD-UnitFrame-Target-HighLevelTarget_Icon"
local ICON_HEIGHT = 30
local LONG = 10000        -- the kill icon's bar: it starts sliding in ICON_HEIGHT / LONG short of lethal
local SPLASH_APPLIED, SPLASH_TICK = 0.6, 0.2

-- A DoT liquid's theme by its school (Dots.lua's masks).
local SCHOOL_THEMES = {
    [1] = "blood", [2] = "holy", [4] = "fire", [8] = "plague", [16] = "frost", [20] = "fire", [32] = "shadow",
    [64] = "arcane",
}
local DEFAULT_THEME = "shadow"

-- What a DoT liquid changes from its theme. Nature's, the poisons and stings, gives off the game's own poison skulls
-- (model frames, see Skulls below) amid glowing green motes, and the theme's own ambient particles (Plague's fumes)
-- stay alongside. Where no model frame can be made, the liquid throws up the addon's drawn skull (Skull.tga) itself:
-- its colours are its own, so the tint is near white, and it has no spin, as Liquid.lua starts a spinning mote at a
-- random angle and a skull stays upright.
local SKULL_FROM, SKULL_TO = { 1.00, 1.00, 1.00 }, { 0.80, 0.95, 0.60 }
local VENOM_FROM, VENOM_TO = { 0.80, 1.00, 0.40 }, { 0.30, 0.75, 0.10 }
-- Plague's own yellow-green is bright beside the health's green, so the DoT liquid takes a darker one.
local VENOM_DARK = {
    fillA = { 0.10, 0.15, 0.02 }, fillB = { 0.48, 0.60, 0.08 }, tip = { 0.78, 0.90, 0.40 }, glow = { 0.55, 0.80, 0.15 },
}
local DOT_LOOKS = {
    plague = {
        colors = VENOM_DARK,
        splashFrom = VENOM_FROM, splashTo = VENOM_TO,
        burst = { texture = "Glow", blend = "ADD", buoyancy = 18, drag = 1.6 },
        ambient = {
            { area = "liquid", rate = 2, energyRate = 4, texture = "Mote", blend = "ADD", size = { 5, 9 },
              life = { 1, 1.8 }, vx = { -3, 3 }, vy = { 6, 12 }, buoyancy = 4, drag = 0.5, twinkle = 3,
              from = VENOM_FROM, to = VENOM_TO },
        },
    },
}
local SPRITE_LOOKS = {
    plague = {
        colors = VENOM_DARK,
        splashFrom = SKULL_FROM, splashTo = SKULL_TO,
        burst = { texture = "Skull", blend = "BLEND", buoyancy = 12, drag = 2.2 },
        ambient = {
            { area = "liquid", rate = 1.3, energyRate = 3, texture = "Skull", blend = "BLEND", size = { 11, 15 },
              life = { 1.6, 2.4 }, vx = { -4, 4 }, vy = { 5, 10 }, buoyancy = 3, drag = 0.6, alpha = 0.9,
              from = SKULL_FROM, to = SKULL_TO },
        },
    },
}

local function Secret(v)
    return issecretvalue and issecretvalue(v) or false
end

--------------------------------------------------------------------------------
-- Skulls: the game's own poison skull rising off a Nature DoT's liquid
--------------------------------------------------------------------------------
-- A shared pool of model frames showing the game's skull (SPELLS/Skull.m2, by file ID; seen working in game), as the
-- game shows over a poisoned character: a few drift up while a Nature DoT runs, and a burst comes with each tick and
-- when one lands. Each pops in, swings its head, rises and fades. A skull hangs on the end of its liquid (the run
-- bar's fill): where that is on the bar comes from the target's secret health, so it is only anchored to, never
-- read. The frames sit just above the frame the marker belongs to, so they rise over it, under the kill icon.
local SKULL_MODEL = 166881
local SKULL_POOL = 16
local SKULL_SIZE = { 22, 30 }
local SKULL_LIFE = { 1.8, 2.6 }
local SKULL_RATE = 1.6                 -- a second, while a Nature DoT runs
local SKULL_TICK, SKULL_LANDED = 3, 6  -- in a burst
local SKULL_LEVEL = 10                 -- over the marker's frame (the kill icon is at 20)
local SKULL_STAGGER = 0.45             -- seconds over which a burst's skulls start

local skulls     -- the pool once made: { frame, active, ... }; false where no model frame can be made
local skullFade  -- the frame method that fades the model: SetModelAlpha, else SetAlpha

local function Rand(a, b) return a + math.random() * (b - a) end

-- Makes the pool the first time; false where no model frame can be made (the drawn skull stands in).
local function SkullPool()
    if skulls ~= nil then return skulls end
    skulls = false
    local pool = {}
    for i = 1, SKULL_POOL do
        local ok, f = pcall(CreateFrame, "PlayerModel", nil, UIParent)
        if not ok or type(f) ~= "table" or type(f.SetModel) ~= "function" or type(f.SetFacing) ~= "function" then
            return skulls
        end
        if not pcall(f.SetModel, f, SKULL_MODEL) then return skulls end
        f:Hide()
        pool[i] = { frame = f, active = false, age = 0, life = 1 }
    end
    skullFade = type(pool[1].frame.SetModelAlpha) == "function" and "SetModelAlpha" or "SetAlpha"
    skulls = pool
    return skulls
end

-- The look for a DoT liquid's key: green motes beside the model skulls, or the drawn skull where there are none.
local function LookFor(key)
    if SkullPool() then return DOT_LOOKS[key] end
    return SPRITE_LOOKS[key]
end

-- Sends count skulls up off liquid d of marker m: bursts follow the Sparkles setting, the steady ones Ambient.
local function EmitSkulls(m, d, count, steady)
    local pool = SkullPool()
    if not pool or not ns.Core.Get(steady and "ambient" or "sparkles") then return end
    local host = m.spec.iconHost
    local okStrata, strata = pcall(host.GetFrameStrata, host)
    for _ = 1, count do
        -- A free skull, else the one furthest through its life.
        local s, oldest
        for _, candidate in ipairs(pool) do
            if not candidate.active then
                s = candidate
                break
            end
            if not oldest or candidate.age / candidate.life > oldest.age / oldest.life then oldest = candidate end
        end
        s = s or oldest
        s.active, s.m, s.anchor = true, m, d.clampFill
        -- A burst's skulls start a moment apart (a negative age is a wait), so they come up one after another.
        s.age = steady and 0 or -Rand(0, SKULL_STAGGER)
        s.life, s.size = Rand(SKULL_LIFE[1], SKULL_LIFE[2]), Rand(SKULL_SIZE[1], SKULL_SIZE[2])
        s.x, s.y = Rand(2, 18), Rand(-4, 6)
        s.vx, s.rise = Rand(-12, 12), Rand(14, 40)
        s.facing, s.swing, s.phase = Rand(-0.3, 0.3), Rand(0.3, 0.6), Rand(0, 2 * math.pi)
        local f = s.frame
        if okStrata and type(strata) == "string" and not Secret(strata) then f:SetFrameStrata(strata) end
        if m.iconLevel then f:SetFrameLevel(m.iconLevel + SKULL_LEVEL) end
        f[skullFade](f, 0)
        f:SetSize(s.size * 0.6, s.size * 0.6)
        f:ClearAllPoints()
        f:SetPoint("CENTER", s.anchor, "LEFT", s.x, s.y)
        pcall(f.SetModel, f, SKULL_MODEL) -- again: a model frame may let its model go while hidden
        f:Show()
    end
end

local function HideSkull(s)
    s.active, s.m, s.anchor = false, nil, nil
    s.frame:Hide()
end

-- Moves every skull on.
local function UpdateSkulls(dt)
    if not skulls then return end
    for _, s in ipairs(skulls) do
        if s.active then
            s.age = s.age + dt
            local p = s.age / s.life
            if p >= 1 then
                HideSkull(s)
            elseif p > 0 then
                local f = s.frame
                -- Pops in a little big, settles, and shrinks a touch as it fades.
                local scale
                if p < 0.12 then
                    scale = 0.6 + 0.5 * p / 0.12
                elseif p < 0.25 then
                    scale = 1.1 - 0.1 * (p - 0.12) / 0.13
                else
                    scale = 1 - 0.15 * (p - 0.25) / 0.75
                end
                local alpha = math.min(1, p / 0.1) * (p > 0.6 and (1 - p) / 0.4 or 1)
                -- Rises fast at first and slows, drifting aside.
                local rise = s.rise * (1 - (1 - p) * (1 - p))
                local size = s.size * scale
                f:SetSize(size, size)
                f:ClearAllPoints()
                f:SetPoint("CENTER", s.anchor, "LEFT", s.x + s.vx * s.age, s.y + rise)
                f:SetFacing(s.facing + s.swing * math.sin(s.phase + s.age * 2.5))
                f[skullFade](f, alpha)
            end
        end
    end
end

local function ClearSkulls(m)
    if not skulls then return end
    for _, s in ipairs(skulls) do
        if s.active and s.m == m then HideSkull(s) end
    end
end

-- A DoT liquid's theme by key: the unit frames' version of the theme (Bars.Theme), with its look's changes.
local function DotTheme(key)
    local base = ns.Bars.Theme(key)
    local look = LookFor(key)
    if not look then return base end
    local t = setmetatable({}, { __index = base })
    for field, value in pairs(look) do
        if field ~= "colors" then t[field] = value end
    end
    for field, value in pairs(look.colors or {}) do t[field] = value end
    local ambient = {}
    for _, list in ipairs({ base.ambient or {}, look.ambient or {} }) do
        for _, emitter in ipairs(list) do ambient[#ambient + 1] = emitter end
    end
    t.ambient = ambient
    return t
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
    local w, h = ns.Bars.Size(bar, 1, 1)
    local m = { spec = spec, bar = bar, value = 0, since = REFRESH_EVERY, feed = 0, pulse = 0,
                width = w, height = h, fresh = true, liquids = {} }

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

    for i = 1, LIQUIDS do
        local d = { value = 0, shown = 0, idle = 0 }
        -- The running total up to this liquid: its fill's left edge is where this liquid ends.
        d.run = HiddenBar(m.clip)
        AtParentLevel(d.run, m.clip)
        d.run:SetPoint("TOPRIGHT", edge, "TOPRIGHT")
        d.run:SetPoint("BOTTOMRIGHT", edge, "BOTTOMRIGHT")
        d.run:SetWidth(w)
        if d.run.SetReverseFill then d.run:SetReverseFill(true) end
        d.fill = d.run:GetStatusBarTexture()
        -- Where this liquid ends, held inside the bar, for the skulls: a bar from the bar's left edge to the health's
        -- edge, filling back from the health's edge over the target's (secret) health with the same running total.
        -- Past the health it is full, so its fill's left edge never goes past the bar's.
        d.clamp = HiddenBar(m.clip)
        AtParentLevel(d.clamp, m.clip)
        d.clamp:SetPoint("TOPLEFT", bar, "TOPLEFT")
        d.clamp:SetPoint("BOTTOMRIGHT", edge, "BOTTOMRIGHT")
        if d.clamp.SetReverseFill then d.clamp:SetReverseFill(true) end
        d.clampFill = d.clamp:GetStatusBarTexture()
        -- The liquid hangs on the edge in front of it: the health's, or the end of the liquid before.
        d.front = i == 1 and edge or m.liquids[i - 1].fill
        d.pool = CreateFrame("Frame", nil, m.clip)
        AtParentLevel(d.pool, m.clip)
        d.pool:SetClipsChildren(true)
        d.pool:Hide()
        d.mover = CreateFrame("Frame", nil, d.pool)
        AtParentLevel(d.mover, d.pool)
        d.mover:SetPoint("TOPRIGHT", d.front, i == 1 and "TOPRIGHT" or "TOPLEFT")
        d.mover:SetPoint("BOTTOMRIGHT", d.front, i == 1 and "BOTTOMRIGHT" or "BOTTOMLEFT")
        d.mover:SetWidth(w)
        d.liquid = ns.Liquid.New(d.mover, math.max(w, 1) + ROOM, math.max(h, 1), ns.Themes.Get(DEFAULT_THEME),
            ns.Core.db)
        if spec.mask then
            local free = {}
            for _, mote in ipairs(d.liquid.motes) do free[mote.tex] = true end
            for _, t in ipairs(d.liquid.textures) do
                if not free[t] then t:AddMaskTexture(spec.mask) end
            end
        end
        m.liquids[i] = d
    end
    -- Where the health will end: the last running total's left edge.
    m.endFill = m.liquids[LIQUIDS].fill

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

-- Under the health liquid when it shows, each reaching OVERLAP under the liquid behind it, and the second
-- reaching ROOM over the first so its waves show. Over the game's own fill when it does not, each cut exactly
-- at its own ends, side by side.
local function Layer(m)
    local under = ns.Bars.IsLive(m.bar)
    if under == m.under then return end
    m.under = under
    for i, d in ipairs(m.liquids) do
        d.liquid:SetSublevelOffset(under and UNDER[i] or 0)
        d.pool:ClearAllPoints()
        d.pool:SetPoint("TOPLEFT", d.fill, "TOPLEFT", under and -OVERLAP or 0, SPILL)
        if i == 1 then
            d.pool:SetPoint("BOTTOMRIGHT", m.clip, "BOTTOMRIGHT")
        else
            d.pool:SetPoint("BOTTOMRIGHT", d.front, "BOTTOMLEFT", under and ROOM or 0, -SPILL)
        end
    end
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
        for _, d in ipairs(m.liquids) do
            d.pool:Hide()
            d.liquid:HideAll()
        end
        ns.Bars.Front(m.bar, nil)
    end
    m.window:Hide()
    ClearSkulls(m)
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

-- The DoTs by school, oldest first (the list is), as at most LIQUIDS groups { school, damage }: a school
-- after the last one with a liquid of its own joins that one.
local function Groups(list)
    local bySchool, groups = {}, {}
    for _, entry in ipairs(list) do
        local school = entry.school or 0
        local g = bySchool[school]
        if not g then
            g = groups[LIQUIDS]
            if not g then
                g = { school = school, damage = 0 }
                groups[#groups + 1] = g
            end
            bySchool[school] = g
        end
        g.damage = g.damage + entry.damage
    end
    return groups
end

-- Reads the DoTs and sets the bars' ranges and goals. False when there is nothing to show.
local function Refresh(m)
    local spec = m.spec
    local landed = m.landed
    m.landed = false
    if not spec.visible() then return false end
    local max, health, total, list = spec.source()
    if not list or #list == 0 or total <= 0 then return false end

    local groups = Groups(list)
    local running = 0
    for i, d in ipairs(m.liquids) do
        local g = groups[i]
        if g then
            local key = SCHOOL_THEMES[g.school] or DEFAULT_THEME
            if key ~= d.themeKey then
                d.themeKey = key
                d.liquid:SetTheme(DotTheme(key))
            end
            -- A tick (less to come) ripples its liquid.
            if not landed and running + g.damage < d.value - 0.5 and d.pool:IsShown() then
                d.liquid:Splash(SPLASH_TICK, m.width - 8, m.width)
                if key == "plague" then EmitSkulls(m, d, SKULL_TICK) end
            end
            running = running + g.damage
        end
        d.value = running -- a liquid without a school of its own runs to the one before: no width
        d.run:SetMinMaxValues(0, max)
        d.clamp:SetMinMaxValues(0, health)
    end
    m.killBar:SetMinMaxValues(0, health)
    m.killBar:SetValue(total)
    if m.fresh then
        m.fresh = false
        for _, d in ipairs(m.liquids) do
            d.shown = 0
            d.run:SetValue(0)
            d.clamp:SetValue(0)
            d.liquid:Snap(m.width)
        end
        Feed(m, false)
    end
    if not m.clip:IsShown() then
        m.clip:Show()
        Layer(m)
        ns.Bars.Front(m.bar, m.endFill)
    end
    for i, d in ipairs(m.liquids) do
        -- Shown while it has a school, or while it still glides away after losing one.
        local before = i > 1 and m.liquids[i - 1].shown or 0
        local wanted = groups[i] ~= nil or d.shown - before > 0.5
        if wanted and not d.pool:IsShown() then
            d.pool:Show()
            d.liquid:Snap(m.width)
        elseif not wanted and d.pool:IsShown() then
            d.pool:Hide()
            d.liquid:HideAll()
        end
    end
    -- A DoT landing stirs every liquid.
    if landed then
        for _, d in ipairs(m.liquids) do
            if d.pool:IsShown() then
                d.liquid:Splash(SPLASH_APPLIED, m.width - 8, m.width)
                if d.themeKey == "plague" then EmitSkulls(m, d, SKULL_LANDED) end
            end
        end
        ns.Bars.StirBar(m.bar)
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
        local w, h = ns.Bars.Size(m.bar, m.width, m.height)
        if (w ~= m.width or h ~= m.height) and w >= 1 and h >= 1 then
            m.width, m.height = w, h
            for _, d in ipairs(m.liquids) do
                d.run:SetWidth(w)
                d.mover:SetWidth(w)
                d.liquid:SetSize(w + ROOM, h)
            end
        end
        if not Refresh(m) then return Hide(m) end
        Layer(m)
    end
    if not m.clip:IsShown() then return end

    if m.window:IsShown() then
        m.pulse = (m.pulse + dt) % 1.4
        m.icon:SetAlpha(0.75 + 0.25 * math.cos(m.pulse / 1.4 * 2 * math.pi))
    end
    for _, d in ipairs(m.liquids) do
        -- The running totals glide to the damage, so the liquids behind draw back smoothly.
        if d.shown ~= d.value then
            d.shown = d.shown + (d.value - d.shown) * math.min(1, dt * GLIDE)
            if math.abs(d.value - d.shown) < math.max(0.05, d.value * 0.002) then d.shown = d.value end
            d.run:SetValue(d.shown)
            d.clamp:SetValue(d.shown)
        end
        if d.pool:IsShown() then
            -- Once settled only the idle wobble remains, so it drops to IDLE_FPS, as Bars.lua does.
            local step = dt
            if d.liquid:IsQuiet() and d.shown == d.value then
                d.idle = d.idle + dt
                step = d.idle >= 1 / IDLE_FPS and d.idle or nil
                if step then d.idle = 0 end
            else
                d.idle = 0
            end
            if step then d.liquid:Update(step, m.width) end
            if d.themeKey == "plague" then
                d.skullAcc = (d.skullAcc or 0) + dt * SKULL_RATE
                if d.skullAcc >= 1 then
                    d.skullAcc = d.skullAcc - 1
                    EmitSkulls(m, d, 1, true)
                end
            end
        end
    end
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
    -- The skulls likewise: an error turns them off until a reload, and the liquid carries on.
    local okSkulls, errSkulls = pcall(UpdateSkulls, dt)
    if not okSkulls and skulls then
        for _, sk in ipairs(skulls) do pcall(HideSkull, sk) end
        skulls = false
        ns.Core.Print("Error in the DoT marker's skulls, which are off until a reload: " .. tostring(errSkulls))
    end
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
    Each(function(m)
        for _, d in ipairs(m.liquids) do d.liquid:ApplyOptions() end
    end)
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
    local shown = {}
    for _, d in ipairs(target.liquids) do
        if d.pool:IsShown() then shown[#shown + 1] = d.themeKey or DEFAULT_THEME end
    end
    return { string.format("DoT marker: on, %s, liquids %s%s, mask %s, kill icon %s%s",
        target.clip:IsShown() and "showing" or "hidden", #shown > 0 and table.concat(shown, " then ") or "none",
        target.under and " under the health liquid" or " over the game's fill", target.spec.mask and "yes" or "no",
        not target.hasIcon and "missing (no atlas)" or ns.Core.Get("dotKillIcon") and "on" or "off",
        target.err and (", error: " .. target.err) or "") }
end
