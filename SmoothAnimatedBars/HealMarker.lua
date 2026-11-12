-- The heal marker on the player frame's health bar (the heals setting): the health the player's own heals
-- over time, bandages and heals being cast on themselves will still bring back, as liquid of the heal's own
-- colour ahead of the health (Holy for priest and paladin heals, Nature for druid and shaman heals and for
-- bandages), one liquid per school. The numbers come from Heals.lua; the player's health is secret, so, as for
-- the DoT marker (Marker.lua), the client does every comparison:
--   * a hidden StatusBar of ours takes the game bar's (secret) value, so its fill ends where the game's does;
--   * one hidden "run" StatusBar per heal liquid, each one bar-width wide with its left edge on that fill's edge,
--     fills on the bar's own (secret) range with a running total of the heals: the first with the first
--     school's, the second with both. Each fill's right edge is where that liquid ends;
--   * each heal liquid ends on its run's edge, in a pool that starts on the edge before it (the health's, or the
--     first liquid's end) and is cut at the bar's end, so healing past full health never shows. The liquid
--     nearer the health is drawn over the one past it, and the health liquid over both, so they meet in wavy
--     fronts.
--   * seen in game, the heal liquid can draw over the liquid before it despite its lower sublevels, hiding that
--     liquid's front and showing its own straight cut. So a seam of the liquid before's colour lies above it on
--     the edge, following that liquid's front slice by slice, whichever of the two the client draws on top.
-- Nothing of the game's is changed but one texture's alpha: the player frame's own prediction for heals the
-- player casts (healthBar.MyHealPredictionBar, a flat teal bar) shows the same heals, and at the bar's level
-- would draw over the liquid, so its fill is transparent while the marker shows. Heals from others keep the
-- game's bar. Our frames are children of the bar, at the bar's level so the game's text stays on top.

local _, ns = ...

local HealMarker = {}
ns.HealMarker = HealMarker

local REFRESH_EVERY = 0.1 -- seconds between reading the heals
local FEED_EVERY = 0.05   -- seconds between handing the game bar's value to our hidden bar
local GLIDE = 6           -- how fast the marker eases to a new value (higher is snappier)
local ROOM = 10           -- as Bars.lua: room past the front for the waves
local SPILL = 16          -- as Bars.lua: how far motes can fly above and below
-- How far a heal liquid reaches back under the liquid before it, so the waves never open a gap between them.
local OVERLAP = 6
-- Two heal liquids, by school, oldest first. Liquid.lua draws in sublevels 3 to 7 of a layer (of -8 to 7):
-- the health liquid there, the first heal liquid shifted down by 5 (to -2..2), the second by 10 (to -7..-3).
local LIQUIDS = 2
local UNDER = { -5, -10 }
local IDLE_FPS = 30
-- The seam (DrawSeams): how far its colour fades out behind the liquid's cut, and its bright tip's width, px.
local SEAM_FADE, SEAM_TIP = 10, 1.2
local SPLASH_APPLIED, SPLASH_TICK = 0.6, 0.2
-- A cast heal landing: a burst of its theme's own particles (leaves for Nature, sparks for Holy) twice over, which
-- also charges the theme's lightning, as its liquid pours into the health.
local SPLASH_LANDED, LANDED_BURSTS = 1.2, 2

-- A heal liquid's look by its school (Heals.lua's: Holy 2, Nature 8, "bandage", and "food" and "drink" for eating
-- and drinking, Honey on the health and Nagrand on the mana, as they are).
local SCHOOL_THEMES = { [2] = "holy", [8] = "nature", bandage = "bandage", food = "honey", drink = "nagrand" }
local DEFAULT_THEME = "holy"
-- The Nature theme's greens are the health liquid's own (the game's green), so next to it a Nature heal could
-- not be told apart: it is a paler spring green here.
local SPRING = {
    fillA = { 0.50, 0.80, 0.22 }, fillB = { 0.86, 1.00, 0.50 }, tip = { 0.96, 1.00, 0.80 },
    glow = { 0.86, 1.00, 0.50 },
}
local PLUS_FROM, PLUS_TO = { 0.45, 1.00, 0.35 }, { 0.80, 1.00, 0.60 }
-- Each heal look: the theme it starts from (Themes.lua) and what it changes. Nature keeps the theme's leaves;
-- bandages throw up green pluses like the ones the game shows over a healed character instead, a few with each
-- tick, and send a few rising while they run.
local HEAL_THEMES = {
    nature = { base = "nature", over = SPRING },
    bandage = { base = "nature", over = SPRING, extra = {
        splashFrom = PLUS_FROM, splashTo = PLUS_TO,
        burst = { texture = "Plus", blend = "BLEND", buoyancy = 30, drag = 1.6 },
        ambient = {
            { area = "liquid", rate = 1.5, energyRate = 4, texture = "Plus", blend = "BLEND", size = { 6, 9 },
              life = { 1, 1.8 }, vx = { -3, 3 }, vy = { 8, 16 }, buoyancy = 6, drag = 0.5,
              from = PLUS_FROM, to = PLUS_TO },
        },
    } },
}

-- A heal liquid's theme by key: the unit frames' version of its base theme (Bars.Theme), with its changes.
local function HealTheme(key)
    local look = HEAL_THEMES[key]
    if not look then return ns.Bars.Theme(key) end
    local t = setmetatable({}, { __index = ns.Bars.Theme(look.base) })
    for _, changes in ipairs({ look.over or {}, look.extra or {} }) do
        for field, value in pairs(changes) do t[field] = value end
    end
    return t
end

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

-- The bar's mask: on the container around the player's health bar on Forever, on the mana bar itself.
local function MaskOf(bar)
    local mask = bar.HealthBarMask or bar.ManaBarMask or bar:GetParent().HealthBarMask
    if type(mask) == "table" and mask.GetObjectType and mask:GetObjectType() == "MaskTexture" then return mask end
end

--------------------------------------------------------------------------------
-- One marker
--------------------------------------------------------------------------------

-- spec: { bar = the health bar, mask = its mask or nil, source = function() returning max (may be secret),
-- total, list (as Heals.Player's), visible = function() whether to show }.
local function New(spec)
    local bar = spec.bar
    local w, h = ns.Bars.Size(bar, 1, 1)
    local m = { spec = spec, bar = bar, value = 0, since = REFRESH_EVERY, feed = 0, width = w, height = h,
                fresh = true, liquids = {} }

    -- Where the game's fill ends, with the client's smoothing.
    m.proxy = HiddenBar(bar)
    m.proxy:SetAllPoints(bar)
    local edge = m.proxy:GetStatusBarTexture()

    -- The bar's length, with room for the motes above and below: healing past the bar's end is cut off.
    m.clip = CreateFrame("Frame", nil, bar)
    AtParentLevel(m.clip, bar)
    m.clip:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, SPILL)
    m.clip:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, -SPILL)
    m.clip:SetClipsChildren(true)
    m.clip:Hide()

    for i = 1, LIQUIDS do
        local d = { value = 0, shown = 0, idle = 0 }
        -- The running total up to this liquid: its fill's right edge is where this liquid ends.
        d.run = HiddenBar(m.clip)
        AtParentLevel(d.run, m.clip)
        d.run:SetPoint("TOPLEFT", edge, "TOPRIGHT")
        d.run:SetPoint("BOTTOMLEFT", edge, "BOTTOMRIGHT")
        d.run:SetWidth(w)
        d.fill = d.run:GetStatusBarTexture()
        -- The edge the liquid starts from: the health's, or the end of the liquid before.
        d.from = i == 1 and edge or m.liquids[i - 1].fill
        d.pool = CreateFrame("Frame", nil, m.clip)
        AtParentLevel(d.pool, m.clip)
        d.pool:SetClipsChildren(true)
        d.pool:Hide()
        d.mover = CreateFrame("Frame", nil, d.pool)
        AtParentLevel(d.mover, d.pool)
        d.mover:SetPoint("TOPRIGHT", d.fill, "TOPRIGHT")
        d.mover:SetPoint("BOTTOMRIGHT", d.fill, "BOTTOMRIGHT")
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

    -- The seams, made after the pools so they lie above them. Each is a bar wide, ending on the edge its liquid
    -- starts from, drawn from the front of the liquid before it. Liquid.lua's rows give the slice count.
    for _, d in ipairs(m.liquids) do
        local s = { rows = {}, tips = {}, colorA = CreateColor(1, 1, 1, 0), colorB = CreateColor(1, 1, 1, 1) }
        s.mover = CreateFrame("Frame", nil, m.clip)
        AtParentLevel(s.mover, m.clip)
        s.mover:SetPoint("TOPRIGHT", d.from, "TOPRIGHT")
        s.mover:SetPoint("BOTTOMRIGHT", d.from, "BOTTOMRIGHT")
        s.mover:SetWidth(w)
        s.mover:Hide()
        local function Solid()
            local t = s.mover:CreateTexture(nil, "ARTWORK", nil, 7)
            t:SetColorTexture(1, 1, 1, 1)
            if spec.mask then t:AddMaskTexture(spec.mask) end
            return t
        end
        s.fade = Solid()
        for i = 1, #d.liquid.pos do
            s.rows[i], s.tips[i] = Solid(), Solid()
        end
        d.seam = s
    end
    return m
end

-- Under the health liquid when it shows, each reaching OVERLAP back under the liquid before it. Over the
-- game's own fill when it does not, each cut exactly at its own ends, side by side.
local function Layer(m)
    local under = ns.Bars.IsLive(m.bar)
    if under == m.under then return end
    m.under = under
    for i, d in ipairs(m.liquids) do
        d.liquid:SetSublevelOffset(under and UNDER[i] or 0)
        d.pool:ClearAllPoints()
        d.pool:SetPoint("TOPLEFT", d.from, "TOPRIGHT", under and -OVERLAP or 0, SPILL)
        if under or i == LIQUIDS then
            d.pool:SetPoint("BOTTOMRIGHT", m.clip, "BOTTOMRIGHT")
        else
            d.pool:SetPoint("BOTTOMRIGHT", d.fill, "BOTTOMRIGHT", 0, -SPILL)
        end
    end
end

-- The game's prediction of the player's own heals: its fill, or nil.
local function GamePrediction(bar)
    local own = bar.MyHealPredictionBar
    local fill = type(own) == "table" and own.Fill
    if type(fill) == "table" and fill.SetAlpha and fill.GetAlpha then return fill end
end

-- Hidden while ours shows (0), back when it does not (1). The game may reset it, so it is kept up each update.
local function GameFill(m, alpha)
    local fill = GamePrediction(m.bar)
    if not fill then return end
    local now = fill:GetAlpha() -- a secret if the game set it from one, which cannot be compared
    if Secret(now) or now ~= alpha then fill:SetAlpha(alpha) end
end

-- Each seam, while its liquid shows under the liquid before it: that liquid's colour from just behind the heal
-- liquid's cut to that liquid's front as it stands, slice by slice, with a bright tip.
local function DrawSeams(m)
    local w, h = m.width, m.height
    for i, d in ipairs(m.liquids) do
        local s = d.seam
        local before
        if i == 1 then
            before = ns.Bars.Liquid(m.bar)
        elseif m.liquids[i - 1].pool:IsShown() then
            before = m.liquids[i - 1].liquid
        end
        local show = (m.under and d.pool:IsShown() and before) and true or false
        if s.mover:IsShown() ~= show then s.mover:SetShown(show) end
        if show then
            local r, g, b = before.gradC:GetRGBA()
            local tip = before.inflowTheme and before.inflowTheme.tip or before.theme.tip
            local rowH = h / #s.rows
            s.colorA:SetRGBA(r, g, b, 0)
            s.colorB:SetRGBA(r, g, b, 1)
            s.fade:SetGradient("HORIZONTAL", s.colorA, s.colorB)
            s.fade:ClearAllPoints()
            s.fade:SetPoint("TOPLEFT", s.mover, "TOPLEFT", w - OVERLAP - SEAM_FADE, 0)
            s.fade:SetSize(SEAM_FADE, h)
            for row = 1, #s.rows do
                local width = math.max(0.5, OVERLAP + before:FrontOffset(row))
                local t, y = s.rows[row], -(row - 1) * rowH
                t:SetVertexColor(r, g, b, 1)
                t:ClearAllPoints()
                t:SetPoint("TOPLEFT", s.mover, "TOPLEFT", w - OVERLAP, y)
                t:SetSize(width, rowH)
                local bright = s.tips[row]
                bright:SetVertexColor(tip[1], tip[2], tip[3], 0.8)
                bright:ClearAllPoints()
                bright:SetPoint("TOPLEFT", s.mover, "TOPLEFT", w - OVERLAP + width, y)
                bright:SetSize(SEAM_TIP, rowH)
            end
        end
    end
end

local function Hide(m)
    GameFill(m, 1)
    m.chargeFor, m.released = nil, false
    ns.Bars.Inflow(m.bar, nil)
    if m.clip:IsShown() then
        m.clip:Hide()
        for _, d in ipairs(m.liquids) do
            d.pool:Hide()
            d.liquid:HideAll()
        end
    end
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

-- The heals by school, oldest first (the list is), as at most LIQUIDS groups { school, heal }: a school after
-- the last one with a liquid of its own joins that one.
local function Groups(list)
    local bySchool, groups = {}, {}
    for _, entry in ipairs(list) do
        local school = entry.school or 0
        local g = bySchool[school]
        if not g then
            g = groups[LIQUIDS]
            if not g then
                g = { school = school, heal = 0 }
                groups[#groups + 1] = g
            end
            bySchool[school] = g
        end
        g.heal = g.heal + entry.heal
    end
    return groups
end

-- Reads the heals and sets the bars' ranges and goals. False when there is nothing to show.
local function Refresh(m)
    local spec = m.spec
    local landed, burst = m.landed, m.burst
    m.landed, m.burst = false, nil
    if not spec.visible() then return false end
    local max, total, list = spec.source()
    local groups = (list and #list > 0 and total > 0) and Groups(list) or {}
    -- With nothing left on the way, the liquids still glide away into the health (a cast heal landing) before
    -- the marker hides.
    if #groups == 0 then
        local gliding = false
        for _, d in ipairs(m.liquids) do
            if m.clip:IsShown() and d.pool:IsShown() and d.shown > 0.5 then gliding = true end
        end
        if not gliding then return false end
        total = 0
    end
    local running = 0
    for i, d in ipairs(m.liquids) do
        local g = groups[i]
        if g then
            local key = SCHOOL_THEMES[g.school] or DEFAULT_THEME
            if key ~= d.themeKey then
                d.themeKey = key
                d.liquid:SetTheme(HealTheme(key))
            end
            -- A tick (less to come) ripples its liquid.
            if not landed and running + g.heal < d.value - 0.5 and d.pool:IsShown() then
                d.liquid:Splash(SPLASH_TICK, m.width - 8, m.width)
            end
            running = running + g.heal
        end
        d.value = running -- a liquid without a school of its own runs to the one before: no width
        d.run:SetMinMaxValues(0, max)
    end
    if m.fresh then
        m.fresh = false
        for _, d in ipairs(m.liquids) do
            d.shown = 0
            d.run:SetValue(0)
            d.liquid:Snap(m.width)
        end
        Feed(m, false)
    end
    if not m.clip:IsShown() then
        m.clip:Show()
        Layer(m)
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
    -- The liquid nearest the bar's front pours into it (Bars.Inflow); while gliding away, nothing does.
    local first = m.liquids[1]
    ns.Bars.Inflow(m.bar, #groups > 0 and first.pool:IsShown() and first.liquid or nil)
    -- A meal with a buff builds up in the bar's own liquid and lets go once, when the buff is reached.
    local progress, startedAt = ns.Heals.Charge(m.name)
    if progress and #groups > 0 then
        if startedAt ~= m.chargeFor then m.chargeFor, m.released = startedAt, false end
        if progress < 1 then
            ns.Bars.Charge(m.bar, progress)
        elseif not m.released then
            m.released = true
            ns.Bars.Release(m.bar)
            if first.pool:IsShown() then first.liquid:Splash(SPLASH_APPLIED, m.width - 8, m.width) end
        end
    elseif m.chargeFor then
        m.chargeFor, m.released = nil, false
        ns.Bars.Charge(m.bar, nil)
    end
    -- A cast heal landing bursts the liquid of its school, which now glides into the health.
    if burst then
        local key = SCHOOL_THEMES[burst] or DEFAULT_THEME
        local target
        for _, d in ipairs(m.liquids) do
            if not target and d.pool:IsShown() and d.themeKey == key then target = d end
        end
        if target then
            for _ = 1, LANDED_BURSTS do target.liquid:Splash(SPLASH_LANDED, m.width - 8, m.width) end
            ns.Bars.StirBar(m.bar)
        end
    end
    -- A heal starting stirs every heal liquid, and the health's.
    if landed then
        for _, d in ipairs(m.liquids) do
            if d.pool:IsShown() then d.liquid:Splash(SPLASH_APPLIED, m.width - 8, m.width) end
        end
        ns.Bars.StirBar(m.bar)
    end
    m.value = total
    return true
end

local function Update(m, dt)
    local visible = m.bar:IsVisible() -- a secret answer is taken as visible
    if not Secret(visible) and not visible then return Hide(m) end
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
                d.seam.mover:SetWidth(w)
                d.liquid:SetSize(w + ROOM, h)
            end
        end
        if not Refresh(m) then return Hide(m) end
        Layer(m)
    end
    if not m.clip:IsShown() then return end
    GameFill(m, 0)

    for _, d in ipairs(m.liquids) do
        -- The running totals glide to the heals, so the liquids draw back smoothly as ticks land.
        if d.shown ~= d.value then
            d.shown = d.shown + (d.value - d.shown) * math.min(1, dt * GLIDE)
            if math.abs(d.value - d.shown) < math.max(0.05, d.value * 0.002) then d.shown = d.value end
            d.run:SetValue(d.shown)
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
        end
    end
    DrawSeams(m)
end

--------------------------------------------------------------------------------
-- The player frame's markers, and the driver
--------------------------------------------------------------------------------

local player  -- the marker on the player frame's health bar, once built
local mana    -- the one on its mana bar (drink)
local driver

local function Each(fn)
    if player then fn(player) end
    if mana then fn(mana) end
end

local function PlayerAlive()
    local ok, dead = pcall(UnitIsDeadOrGhost, "player")
    return not (ok and not Secret(dead) and dead)
end

-- The mana marker shows only while the power bar shows mana (not in cat or bear form).
local function ManaShown()
    if not PlayerAlive() then return false end
    local ok, _, token = pcall(UnitPowerType, "player")
    if not ok or Secret(token) or token == nil then return true end
    return token == "MANA"
end

local function SourceFor(m, read)
    return function()
        local total, list = read()
        local _, max = m.bar:GetMinMaxValues()
        return max, total, list
    end
end

local function Build(key, read, visible)
    local bar = ns.Bars.Find(key)
    if type(bar) ~= "table" or not bar.GetStatusBarTexture then return nil end
    local spec = { bar = bar, mask = MaskOf(bar), visible = visible }
    local m = New(spec)
    spec.source = SourceFor(m, read)
    m.name = key == "playerHealth" and "health" or "mana"
    return m
end

local function OnUpdate(_, elapsed)
    local dt = math.min(elapsed, 0.1)
    if dt <= 0 then return end
    Each(function(m)
        if not m.live or m.err then return end
        local ok, err = pcall(Update, m, dt)
        if not ok then
            m.err = tostring(err)
            pcall(Hide, m)
            ns.Core.Print("Error in the " .. m.name .. " heal marker, which is off until a reload: " .. m.err)
        end
    end)
end

-- After the heals setting changes, and at login.
function HealMarker.Apply()
    local live = ns.Core.Get("heals") and true or false
    if live and not player then player = Build("playerHealth", ns.Heals.Player, PlayerAlive) end
    if live and not mana then mana = Build("playerPower", ns.Heals.Mana, ManaShown) end
    ns.Heals.Enable(live)
    Each(function(m)
        m.live = live
        if not live then Hide(m) end
    end)
    local any = live and (player or mana) and true or false
    if any and not driver then
        driver = CreateFrame("Frame")
        driver:SetScript("OnUpdate", OnUpdate)
    end
    if driver then driver:SetShown(any) end
end

-- After an effect toggle: clear what was just switched off.
function HealMarker.ApplyOptions()
    Each(function(m)
        for _, d in ipairs(m.liquids) do d.liquid:ApplyOptions() end
    end)
end

ns.Heals.Listen(function(event, arg)
    Each(function(m) m.since = REFRESH_EVERY end) -- read again on the next frame
    if event == "applied" then
        local m = arg == "mana" and mana or player
        if m then m.landed = true end
    elseif event == "landed" and player then
        player.burst = arg
    end
end)

-- For the tests and the gallery: the markers on the player frame's health and mana bars (nil until built).
function HealMarker.State()
    return player, mana
end

-- For /sab heals.
function HealMarker.Debug()
    if not ns.Core.Get("heals") then return { "Heal marker: off (Heal Marker in the settings)" } end
    if not player then return { "Heal marker: the player frame's health bar was not found" } end
    local out = {}
    Each(function(m)
        local shown = {}
        for _, d in ipairs(m.liquids) do
            if d.pool:IsShown() then shown[#shown + 1] = d.themeKey or DEFAULT_THEME end
        end
        local game = GamePrediction(m.bar)
        out[#out + 1] = string.format("Heal marker (%s): on, %s, liquids %s%s, mask %s%s%s", m.name,
            m.clip:IsShown() and "showing" or "hidden", #shown > 0 and table.concat(shown, " then ") or "none",
            m.under and " under the bar's liquid" or " over the game's fill", m.spec.mask and "yes" or "no",
            m.name == "health" and (", game's own prediction " .. (not game and "not found"
                or Secret(game:GetAlpha()) and "secret" or game:GetAlpha() == 0 and "hidden" or "shown")) or "",
            m.err and (", error: " .. m.err) or "")
    end)
    return out
end
