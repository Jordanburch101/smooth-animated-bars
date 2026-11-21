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
-- would draw over the liquid, so its fill is transparent while the marker shows; so is its bar for heals from others,
-- shown by the marker too (see below). Our frames are children of the bar, at the bar's level so the game's text stays on top.
-- The Personal Resource Display's bars get markers of their own, from the same heals, while their liquid shows. Their
-- liquid is raised over the bar as on a nameplate (Bars.lua, flat), so the marker goes one level above the bar, under
-- the health liquid two up, as the DoT marker on a plate does (Marker.lua): the levels put the heal liquid under the
-- health's front, so no seam is needed, and the plate mask and shading of the bar's liquid are the marker's too. Its
-- own prediction of the player's heals is a texture on the bar (healthBar.myHealPrediction), kept transparent the same
-- way.
-- Other addons' player bars (SmoothAnimatedBars.AddBar) get markers too, while their liquid shows and they fill from the
-- left (a bar filling from the right, Frames Forever's lost health, shows what is missing). Their liquid is raised a
-- level or more over the bar (Bars.lua, External.Raise), so the marker takes the same level and lies under it by
-- sublevels, with seams, as on the player frame. The addon's own heal prediction is its own and is left as it is.
-- The party frames' health bars get markers for the player's heals on each member (Heals.For), while the bar's liquid
-- shows: laid out as on the player frame (the bar's mask, under the liquid by sublevels, with seams), following the unit
-- the game puts on the bar, and updated at most PARTY_FPS times a second, as the party liquids are (Bars.lua). The
-- game's prediction of the player's heals there (MyHealPredictionBar) is hidden while the marker shows, as on the
-- player frame, and its bar for heals from others too (see below). The raid-style frames' health bars (raid frames and raid-style
-- party frames, the player's own among them) get them too, laid out for those frames (New, RAID_LAYERS): one heal
-- liquid, under the health liquid by draw layer, cut by masks rather than clip frames, and the button's own prediction
-- (myHealPrediction) hidden while it shows.
-- Other players' heals take the game's place too: what the game predicts others will heal the unit for (the heal
-- prediction calculator's amountFromOthers: in the modern client casts in progress, not heals over time; what Forever
-- counts is not yet known), secret, laid out by a hidden StatusBar after the player's own heals, as a liquid of its own (OTHERS_THEME)
-- under them. The amount cannot be compared, so it shows while the game shows its own bar for others' heals
-- (OtherHealPredictionBar, or the otherHealPrediction texture on raid-style frames and the Personal Resource Display,
-- which the game hides at nothing: CompactUnitFrameUtil_UpdateFillBar), and that bar's fill is transparent meanwhile.
-- A party or raid marker resting with nothing to show is woken by UNIT_HEAL_PREDICTION for its member.

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
-- Seconds other players' liquid stays after the game's bar for their heals goes (the heal landed, or the cast ended),
-- draining into the health as the client eases its hidden bar to nothing.
local OTHERS_LINGER = 0.5
-- A party or raid member's marker updates at most this often, as the party liquids do (Bars.lua, PARTY_FPS).
local PARTY_FPS = 20
-- Seconds between looks for party and raid health bars that have the liquid and no marker yet (the frames come and go).
local PARTY_LOOK_EVERY = 1

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
-- Other players' heals: one liquid for every healer but the player, whose classes the game does not tell apart, in a
-- silvery teal near the game's own bar for them, with Tidal's caustics and bubbles.
local OTHERS_THEME = "others"
local HEAL_THEMES = {
    others = { base = "tidal", over = {
        fillA = { 0.14, 0.36, 0.36 }, fillB = { 0.52, 0.84, 0.80 }, tip = { 0.90, 1.00, 0.97 },
        glow = { 0.56, 0.92, 0.86 }, swirlA = { 0.78, 0.96, 0.94 }, swirlB = { 0.56, 0.86, 0.86 },
        splashFrom = { 0.88, 1.00, 0.98 }, splashTo = { 0.40, 0.80, 0.78 },
    } },
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

-- The unit the game shows on a party bar (party1..4; the player in Edit Mode's preview, whose heals stay on the
-- player's own bars), or nil.
local function PartyUnit(bar)
    local unit = bar.unit
    if type(unit) ~= "string" or Secret(unit) or unit == "player" then return nil end
    return unit
end

-- Whether Edit Mode is open: its preview puts the player on every raid-style frame.
local function EditMode()
    local f = rawget(_G, "EditModeManagerFrame")
    if type(f) ~= "table" or type(f.IsEditModeActive) ~= "function" then return false end
    local ok, on = pcall(f.IsEditModeActive, f)
    return ok and on == true
end

-- The unit a raid-style frame's bar shows, as its liquid follows it (Bars.raid.Follow: the button's displayedUnit), or
-- nil (none yet, or Edit Mode's preview). The player's own frame among them shows the player's heals.
local function RaidUnit(bar)
    local b = ns.Bars.stateOf[bar]
    local unit = b and b.unit
    if type(unit) ~= "string" or Secret(unit) or EditMode() then return nil end
    return unit
end

-- The unit a group marker's bar shows now: a party frame's or a raid-style frame's.
local function GroupUnit(m)
    if m.party then return PartyUnit(m.bar) end
    if m.raid then return RaidUnit(m.bar) end
end

-- What the game predicts other players will heal unit for, secret, or nil where the client does not say: Forever's heal
-- prediction calculator, filled for the unit with the player as the healer (UnitGetDetailedHealPrediction), whose
-- amountFromOthers is everyone else's. One calculator, filled for one unit at a time; clamped to the whole bar (past the
-- bar's end the marker's clip cuts it). false once the client has none.
local othersCalc
local function OthersAmount(unit)
    if othersCalc == nil then
        othersCalc = false
        if CreateUnitHealPredictionCalculator then
            local ok, calc = pcall(CreateUnitHealPredictionCalculator)
            if ok and calc then
                local modes = Enum and Enum.UnitIncomingHealClampMode
                if modes and modes.MaximumHealth then pcall(calc.SetIncomingHealClampMode, calc, modes.MaximumHealth) end
                othersCalc = calc
            end
        end
    end
    if not othersCalc or type(unit) ~= "string" then return nil end
    if not pcall(UnitGetDetailedHealPrediction, unit, "player", othersCalc) then return nil end
    local ok, _, _, fromOthers = pcall(othersCalc.GetIncomingHeals, othersCalc)
    if ok then return fromOthers end
end

-- The game's own bar for others' heals on a marker's bar: the region it shows and hides (a segment with a Fill on the
-- player and party frames, a texture on raid-style frames and the Personal Resource Display), and what to make
-- transparent. nil when the bar has none.
local function GameOthers(m)
    local region = m.spec.othersPrediction or m.bar.OtherHealPredictionBar or m.bar.otherHealPrediction
    if type(region) ~= "table" or type(region.IsShown) ~= "function" then return nil end
    local fill = type(region.Fill) == "table" and region.Fill or region
    if not (fill.SetAlpha and fill.GetAlpha) then return nil end
    return region, fill
end

-- Whose heals a marker shows, as Heals.KeyOf: the player's, or the group member's on its bar now.
local function Owner(m)
    if not (m.party or m.raid) then return "player" end
    local unit = GroupUnit(m)
    return unit and ns.Heals.KeyOf(unit)
end

--------------------------------------------------------------------------------
-- One marker
--------------------------------------------------------------------------------

-- A raid-style frame's marker (spec.raid). The client sorts the textures of every frame at the button's level by draw
-- layer together, and a clipping frame is drawn outside that sorting (Bars.lua, Bars.raid): so no frame of the marker
-- clips, a square mask of ours cuts it to the bar (motes too, the frames touch) and another to the part past the
-- health's edge, and its one liquid draws in BACKGROUND 3..7, above the button's background (BACKGROUND 0) and under
-- the health liquid (BORDER -4..0), so the health's front lies over it with no seam; its motes join the health
-- liquid's in BORDER 2, 3. There is room there for one heal liquid, not two: every heal on the frame shares it, in the
-- first one's colour.
local RAID_LAYERS = { ARTWORK = { "BACKGROUND", 0 }, OVERLAY = { "BORDER", -1 } }
-- Other players' liquid lies under the player's: on the unit frames in BORDER 3..7, below the ARTWORK the player's heal
-- liquids and the health's use (their sublevels are spent: Liquid.lua's 3..7 shifted by UNDER), its own order kept; on
-- raid-style frames in BACKGROUND 1..5, over the button's background (BACKGROUND 0). There only the player's heal
-- liquid's tips and glow (BACKGROUND 6, 7) are sure to be over it: its body, clouds and swirls (3..5) tie with others'
-- in the few pixels others' pool reaches back under it, as there are no sublevels free between 0 and 3.
local OTHERS_LAYERS = { ARTWORK = { "BORDER", 0 } }
local OTHERS_RAID_LAYERS = { ARTWORK = { "BACKGROUND", -2 }, OVERLAY = { "BORDER", -1 } }

local function SquareMask(frame)
    local mask = frame:CreateMaskTexture()
    mask:SetTexture(ns.Bars.raid.MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    return mask
end

-- spec: { bar = the health bar, mask = its mask or nil, source = function() returning max (may be secret),
-- total, list (as Heals.Player's), visible = function() whether to show, raised = a flat bar's (one level up),
-- raid = a raid-style frame's (above), prediction = the game's prediction of the player's heals, where not on the bar,
-- tight = cut at the bar's own edges, no room for motes above and below (the editor's example raid, whose frames
-- touch, as its own liquid is) }.
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
    local spill = spec.tight and 0 or SPILL
    m.clip:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, spill)
    m.clip:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, -spill)
    m.clip:SetClipsChildren(not spec.raid)
    m.clip:Hide()
    if spec.raid then
        spec.mask = SquareMask(m.clip)
        spec.mask:SetAllPoints(bar)
    end

    -- One liquid: its run (a hidden bar from runFrom, a bar-width long, whose fill's right edge is where the liquid
    -- ends), the edge it starts from (from), and its pool and mover. layers: its layer map, if any.
    local function Make(runFrom, from, layers)
        local d = { value = 0, shown = 0, idle = 0 }
        d.run = HiddenBar(m.clip)
        AtParentLevel(d.run, m.clip)
        d.run:SetPoint("TOPLEFT", runFrom, "TOPRIGHT")
        d.run:SetPoint("BOTTOMLEFT", runFrom, "BOTTOMRIGHT")
        d.run:SetWidth(w)
        d.fill = d.run:GetStatusBarTexture()
        d.from = from
        d.pool = CreateFrame("Frame", nil, m.clip)
        AtParentLevel(d.pool, m.clip)
        d.pool:SetClipsChildren(not spec.raid)
        d.pool:Hide()
        d.mover = CreateFrame("Frame", nil, d.pool)
        AtParentLevel(d.mover, d.pool)
        d.mover:SetPoint("TOPRIGHT", d.fill, "TOPRIGHT")
        d.mover:SetPoint("BOTTOMRIGHT", d.fill, "BOTTOMRIGHT")
        d.mover:SetWidth(w)
        d.liquid = ns.Liquid.New(d.mover, math.max(w, 1) + ROOM, math.max(h, 1), ns.Themes.Get(DEFAULT_THEME),
            ns.Bars.EffectOptions(bar)) -- the bar's own effects, where it has its own
        if spec.raid then
            -- The pool's cut, as a mask (Layer places it): from a little under the edge it starts from to the bar's end.
            d.poolMask = SquareMask(m.clip)
        end
        if layers then d.liquid:SetLayerMap(layers) end
        if spec.mask then
            local free = {}
            if not spec.raid then
                for _, mote in ipairs(d.liquid.motes) do free[mote.tex] = true end
            end
            for _, t in ipairs(d.liquid.textures) do
                if not free[t] then t:AddMaskTexture(spec.mask) end
            end
            if d.poolMask then
                for _, mote in ipairs(d.liquid.motes) do free[mote.tex] = true end
                for _, t in ipairs(d.liquid.textures) do
                    if not free[t] then t:AddMaskTexture(d.poolMask) end
                end
            end
        end
        return d
    end

    -- The player's own heals: each liquid's run counts from the health's edge (a running total), and it starts from
    -- the health's edge or the end of the liquid before.
    for i = 1, spec.raid and 1 or LIQUIDS do
        m.liquids[i] = Make(edge, i == 1 and edge or m.liquids[i - 1].fill, spec.raid and RAID_LAYERS or nil)
    end
    -- Other players' heals, after the player's own: a run of their own from where the player's end.
    if spec.others then
        local last = m.liquids[#m.liquids].fill
        m.others = Make(last, last, spec.raid and OTHERS_RAID_LAYERS or OTHERS_LAYERS)
        m.others.others = true
        m.others.themeKey = OTHERS_THEME
        m.others.liquid:SetTheme(HealTheme(OTHERS_THEME))
    end

    -- The seams, made after the pools so they lie above them. Each is a bar wide, ending on the edge its liquid
    -- starts from, drawn from the front of the liquid before it. Liquid.lua's rows give the slice count. A raid-style
    -- frame's marker needs none (its layers order it) and has none.
    local all = { unpack(m.liquids) }
    if m.others then all[#all + 1] = m.others end
    m.all = all
    for _, d in ipairs(spec.raid and {} or all) do
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
-- A flat bar's marker one level above the bar, under its liquid two up (Bars.lua, RaisePlate). Looked at again with
-- each refresh, should the game move the bar.
-- An other addon's bar's marker (spec.up) takes the level of the bar's liquid, however many it is above the bar.
local function Raise(m)
    local up = m.spec.up and m.spec.up() or (m.spec.raised and 1)
    if not up then return end
    local ok, level = pcall(m.bar.GetFrameLevel, m.bar)
    if up > 0 and ok and type(level) == "number" and not Secret(level) then
        if level + up == m.raisedOn then return end
        m.raisedOn = level + up
        if m.clip.SetUsingParentLevel then m.clip:SetUsingParentLevel(false) end
        m.clip:SetFrameLevel(level + up)
    else
        m.raisedOn = nil
        AtParentLevel(m.clip, m.bar)
    end
end

-- While the health liquid's front is moved back off the health's edge (a shield, Shield.lua, between them), the heal
-- liquids meet the shield, not the health liquid: side by side from the health's edge, with no seam (a seam of the
-- health's colour on the health's edge painted green over the shield, seen in game).
local function Layer(m)
    local under = ns.Bars.IsLive(m.bar) and not ns.Bars.Moved(m.bar)
    if under == m.under then return end
    m.under = under
    for i, d in ipairs(m.all) do
        -- A raid-style frame's liquid, and others' anywhere, is ordered by its layer map, not by sublevels.
        d.liquid:SetSublevelOffset((under and not m.spec.raid and not d.others) and UNDER[i] or 0)
        d.pool:ClearAllPoints()
        d.pool:SetPoint("TOPLEFT", d.from, "TOPRIGHT", under and -OVERLAP or 0, SPILL)
        if under or i == #m.all then
            d.pool:SetPoint("BOTTOMRIGHT", m.clip, "BOTTOMRIGHT")
        else
            d.pool:SetPoint("BOTTOMRIGHT", d.fill, "BOTTOMRIGHT", 0, -SPILL)
        end
        if d.poolMask then
            d.poolMask:ClearAllPoints()
            d.poolMask:SetPoint("TOPLEFT", d.from, "TOPRIGHT", under and -OVERLAP or 0, 0)
            d.poolMask:SetPoint("BOTTOMRIGHT", m.bar, "BOTTOMRIGHT")
        end
    end
end

-- The game's prediction of the player's own heals: its fill, or nil. The player frame's is a bar with a Fill, the
-- Personal Resource Display's a texture on the bar, a raid-style frame's a texture on its button (spec.prediction).
local function GamePrediction(m)
    local bar = m.bar
    local own = bar.MyHealPredictionBar
    local fill = m.spec.prediction or (type(own) == "table" and own.Fill) or bar.myHealPrediction
    if type(fill) == "table" and fill.SetAlpha and fill.GetAlpha then return fill end
end

-- Hidden while ours shows (0), back when it does not (1). The game may reset it, so it is kept up each update. Another
-- addon's bar is its own: whatever prediction it draws is left alone, whatever its fields are called.
local function AlphaTo(region, alpha)
    local now = region:GetAlpha() -- a secret if the game set it from one, which cannot be compared
    if Secret(now) or now ~= alpha then region:SetAlpha(alpha) end
end

local function GameFill(m, alpha)
    if m.spec.external then return end
    local fill = GamePrediction(m)
    if fill then AlphaTo(fill, alpha) end
    if m.others then
        -- The game's bar for others' heals stays while the calculator gives nothing to show them by (m.othersBroken).
        local _, others = GameOthers(m)
        if others then AlphaTo(others, m.othersBroken and 1 or alpha) end
    end
end

-- Each seam, while its liquid shows under the liquid before it: that liquid's colour from just behind the heal
-- liquid's cut to that liquid's front as it stands, slice by slice, with a bright tip.
local function DrawSeams(m)
    local w, h = m.width, m.height
    for i, d in ipairs(m.all) do
        local s = d.seam
        -- The liquid before: the nearest one showing, else the health's.
        local before, health
        for j = i - 1, 1, -1 do
            if m.all[j].pool:IsShown() then
                before = m.all[j].liquid
                break
            end
        end
        if not before then before, health = ns.Bars.Liquid(m.bar), true end
        local show = (m.under and d.pool:IsShown() and before and not m.spec.raised) and true or false
        if s.mover:IsShown() ~= show then s.mover:SetShown(show) end
        if show then
            local r, g, b = before.gradC:GetRGBA()
            local tip = before.inflowTheme and before.inflowTheme.tip or before.theme.tip
            -- Another addon's bar whose colour is secret: its liquid is white under a tint in that colour (Bars.lua),
            -- which does not reach the seam, so the seam takes the secret colour itself (SetVertexColor takes secrets)
            -- and goes without its fade, whose gradient would need the colour as numbers.
            local secret = health and ns.Bars.SecretColor(m.bar)
            if secret then r, g, b, tip = secret[1], secret[2], secret[3], secret end
            local rowH = h / #s.rows
            if secret then
                if s.fade:IsShown() then s.fade:Hide() end
            else
                if not s.fade:IsShown() then s.fade:Show() end
                s.colorA:SetRGBA(r, g, b, 0)
                s.colorB:SetRGBA(r, g, b, 1)
                s.fade:SetGradient("HORIZONTAL", s.colorA, s.colorB)
                s.fade:ClearAllPoints()
                s.fade:SetPoint("TOPLEFT", s.mover, "TOPLEFT", w - OVERLAP - SEAM_FADE, 0)
                s.fade:SetSize(SEAM_FADE, h)
            end
            for row = 1, #s.rows do
                local width = math.max(0.5, OVERLAP + before:FrontOffset(row, #s.rows))
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

-- Kept up each frame while there is nothing to show, so done once; and a heal that started meanwhile (its splash,
-- landed and burst) is not saved up for when the bar shows again (the Personal Resource Display hidden, or the mana
-- under a druid's form in caster form).
local function Hide(m)
    m.landed, m.burst = false, nil
    m.othersWake = nil -- woken by others' heals but hidden, or with nothing to show: resting again
    if m.hidden then return end
    m.hidden = true
    GameFill(m, 1)
    m.chargeFor, m.released = nil, false
    ns.Bars.Inflow(m.bar, nil)
    if m.clip:IsShown() then
        m.clip:Hide()
        for _, d in ipairs(m.all) do
            d.pool:Hide()
            d.liquid:HideAll()
        end
    end
    m.othersAt = nil
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
local function Groups(list, n)
    local bySchool, groups = {}, {}
    for _, entry in ipairs(list) do
        local school = entry.school or 0
        local g = bySchool[school]
        if not g then
            g = groups[n]
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
    local landed, burst, calm = m.landed, m.burst, m.calm
    m.landed, m.burst, m.calm = false, nil, nil
    if not spec.visible() then return false end
    local max, total, list = spec.source()
    local groups = (list and #list > 0 and total > 0) and Groups(list, #m.liquids) or {}
    -- Other players' heals: while the game shows its bar for them (a secret answer counted as shown, the liquid then
    -- faded by it), and OTHERS_LINGER after, while their liquid drains into the health.
    local others, amount, shownBy, othersNow = m.others, nil, nil, false
    if others then
        local region = GameOthers(m)
        local ok, shown = false, nil
        if region then ok, shown = pcall(region.IsShown, region) end
        -- The calculator is asked only while the game's bar shows; giving nothing then, the game's bar is left showing.
        if ok and (Secret(shown) or shown) then
            amount = OthersAmount(spec.unit and spec.unit())
            m.othersBroken = amount == nil
        end
        if amount ~= nil then
            m.othersAt, othersNow = GetTime(), true
            if Secret(shown) then shownBy = shown end
        end
    end
    local othersWanted = m.othersAt ~= nil and GetTime() - m.othersAt < OTHERS_LINGER
    -- With nothing left on the way, the liquids still glide away into the health (a cast heal landing) before
    -- the marker hides.
    if #groups == 0 then
        local gliding = false
        for _, d in ipairs(m.liquids) do
            if m.clip:IsShown() and d.pool:IsShown() and d.shown > 0.5 then gliding = true end
        end
        if not gliding and not othersWanted then return false end
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
            -- A tick (less to come) ripples its liquid; not the ticks of a fade, all at once when it shows.
            if not landed and not calm and running + g.heal < d.value - 0.5 and d.pool:IsShown() then
                d.liquid:Splash(SPLASH_TICK, m.width - 8, m.width)
            end
            running = running + g.heal
        end
        d.value = running -- a liquid without a school of its own runs to the one before: no width
        d.run:SetMinMaxValues(0, max)
    end
    if m.fresh then
        m.fresh = false
        for _, d in ipairs(m.all) do
            d.shown = 0
            d.run:SetValue(0)
            d.liquid:Snap(m.width)
        end
        Feed(m, false)
    end
    -- Others' run takes the game's amount, eased by the client; once the game's bar has gone, nothing.
    if others then
        others.run:SetMinMaxValues(0, max)
        local goal = 0 -- never `othersNow and amount or 0`: that tests the secret's truth
        if othersNow then goal = amount end
        if INTERPOLATION then others.run:SetValue(goal, INTERPOLATION) else others.run:SetValue(goal) end
        -- Faded by the game's secret answer (its alpha is then a secret too, never compared: m.othersFaded says so).
        if shownBy ~= nil then
            m.othersFaded = pcall(others.pool.SetAlphaFromBoolean, others.pool, shownBy, 1, 0)
            if not m.othersFaded then others.pool:SetAlpha(1) end
        elseif m.othersFaded then
            m.othersFaded = false
            others.pool:SetAlpha(1)
        end
    end
    if not m.clip:IsShown() then
        m.clip:Show()
        m.hidden = false
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
    local othersArrived = false
    if others then
        if othersWanted and not others.pool:IsShown() then
            others.pool:Show()
            others.liquid:Snap(m.width)
            othersArrived = true
        elseif not othersWanted and others.pool:IsShown() then
            others.pool:Hide()
            others.liquid:HideAll()
        end
    end
    -- The liquid nearest the bar's front pours into it (Bars.Inflow): the player's first, else others' (not while the
    -- game's answer is secret: it may be faded out); while gliding away, nothing does.
    local first = m.liquids[1]
    local inflow = (#groups > 0 and first.pool:IsShown() and first.liquid)
        or (othersNow and shownBy == nil and others.liquid) or nil
    ns.Bars.Inflow(m.bar, inflow)
    -- A meal with a buff builds up in the bar's own liquid and lets go once, when the buff is reached. Only the player
    -- eats: a party member's bar has none.
    local progress, startedAt
    if not (m.party or m.raid) then progress, startedAt = ns.Heals.Charge(m.name) end
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
    -- Someone else starting a heal on the unit: their liquid splashes as it grows in, and the health stirs.
    if othersArrived then
        others.liquid:Splash(SPLASH_APPLIED, m.width - 8, m.width)
        ns.Bars.StirBar(m.bar)
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
    -- A group bar showing nothing while no heal goes anywhere has nothing to do, not even a look at the bar: a raid's
    -- dozens wait here, and so do raid markers left when Raid Frames Health is turned off.
    -- Others' heals on its member wake it (UNIT_HEAL_PREDICTION, othersWake).
    if (m.party or m.raid) and m.hidden and not ns.Heals.Busy() and not m.othersWake then return end
    local sight = ns.Bars.Sight(m.bar) -- a secret answer is taken as shown
    if sight == "hidden" then return Hide(m) end
    -- Faded out by another addon (an idle fade, or a unit frame addon's hidden game frame), and perhaps soon back: paused
    -- as it is, not hidden, which would forget a meal's release and play it again on every fade-in. Nothing is saved up
    -- for its return: no landing or burst, no ticks, and a buff reached meanwhile counts as let go.
    if sight == "faded" then
        m.landed, m.burst, m.calm = false, nil, true
        m.since = REFRESH_EVERY -- read again the moment it shows
        local progress, startedAt
        if not (m.party or m.raid) then progress, startedAt = ns.Heals.Charge(m.name) end
        if progress and progress >= 1 and not (m.released and m.chargeFor == startedAt) then
            m.chargeFor, m.released = startedAt, true
            ns.Bars.Sate(m.bar)
        end
        return
    end
    m.since = m.since + dt
    if m.since >= REFRESH_EVERY then
        m.since = 0
        -- A group bar the game has put another member on: the last member's heals go at once, not gliding into this
        -- one's health, and theirs grow in from nothing. A marker already hidden is left so: hiding it again would
        -- drop the splash of a heal that has just landed on the new member (Hide clears it).
        if m.party or m.raid then
            local who = Owner(m)
            if who ~= m.owner then
                m.owner = who
                if not m.hidden then Hide(m) end
            end
        end
        local w, h = ns.Bars.Size(m.bar, m.width, m.height)
        if (w ~= m.width or h ~= m.height) and w >= 1 and h >= 1 then
            m.width, m.height = w, h
            for _, d in ipairs(m.all) do
                d.run:SetWidth(w)
                d.mover:SetWidth(w)
                if d.seam then d.seam.mover:SetWidth(w) end
                d.liquid:SetSize(w + ROOM, h)
            end
        end
        if not Refresh(m) then return Hide(m) end
        Raise(m)
        Layer(m)
    end
    -- Nothing showing: nothing to keep up until the next read (a raid's dozens of markers mostly wait here).
    if not m.clip:IsShown() then return end
    m.feed = m.feed + dt
    if m.feed >= FEED_EVERY then
        m.feed = 0
        Feed(m, true)
    end
    GameFill(m, 0)

    for _, d in ipairs(m.all) do
        -- The running totals glide to the heals, so the liquids draw back smoothly as ticks land (others' is eased by
        -- the client).
        if not d.others and d.shown ~= d.value then
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
    if not m.spec.raid then DrawSeams(m) end
end

--------------------------------------------------------------------------------
-- The player frame's markers, and the driver
--------------------------------------------------------------------------------

local player  -- the marker on the player frame's health bar, once built
local mana    -- the one on its mana bar (drink)
local extra = {} -- the Personal Resource Display's, by bar: its health, its power bar and the mana under a form; and
                 -- other addons' player bars
local retired = {} -- other addons' markers replaced when their bar was added again as the other kind, never shown again
local previews = {} -- the preview frames' (Preview.lua), fed their example heals
local group = {} -- the party frames' and the raid-style frames' health bars', by bar
local MANA = Enum and Enum.PowerType and Enum.PowerType.Mana or 0
local driver
local lookIn = 0 -- seconds to the next look for party bars without a marker
local groupErr   -- an error building group markers, once reported

local function Each(fn)
    if player then fn(player) end
    if mana then fn(mana) end
    for _, m in pairs(extra) do fn(m) end
    for _, m in pairs(group) do fn(m) end
    for _, m in ipairs(previews) do fn(m) end
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

-- maxOf: where the bar's range does not hold the unit's real health or mana (another addon's bar, which may show a
-- percentage), the unit's maximum, secret or not; it only goes to our own bars' SetMinMaxValues.
local function SourceFor(m, read, maxOf)
    return function()
        local total, list = read()
        local max
        if maxOf then
            max = maxOf()
        else
            local _
            _, max = m.bar:GetMinMaxValues()
        end
        return max, total, list
    end
end

-- name: what the marker shows, "health" or "mana" (Heals.lua's resources); label: whose, for messages. external: for
-- another addon's bar, its mask and a function for its liquid's levels above the bar. opts: { raid = true and
-- prediction = the game's prediction of the player's heals on its button, for a raid-style frame's bar; tight = true;
-- others = a function giving the unit whose others' heals to show, with othersPrediction = the game's bar for them
-- where not on the bar }.
local function BuildOn(bar, name, read, visible, label, external, opts)
    if type(bar) ~= "table" or not bar.GetStatusBarTexture then return nil end
    local flatMask = ns.Bars.PlateMask(bar)
    local spec = { bar = bar, mask = flatMask or MaskOf(bar), visible = visible, raised = flatMask ~= nil }
    if external then spec.mask, spec.up, spec.external = external.mask, external.up, true end
    if opts and opts.raid then spec.mask, spec.raid, spec.prediction = nil, true, opts.prediction end
    if opts and opts.tight then spec.tight = true end
    if opts and opts.others then spec.others, spec.unit, spec.othersPrediction = true, opts.others, opts.othersPrediction end
    -- A raised marker shows only over the bar's own liquid: without it, the game's fill is at the bar's level, under
    -- the bar's dark background.
    if spec.raised then spec.visible = function() return ns.Bars.IsLive(bar) and visible() end end
    local m = New(spec)
    spec.source = SourceFor(m, read, external and external.max)
    m.name, m.label = name, label
    Raise(m)
    return m
end

local function Player() return "player" end

local function Build(key, read, visible)
    local name = key == "playerHealth" and "health" or "mana"
    return BuildOn(ns.Bars.Find(key), name, read, visible, name, nil,
        key == "playerHealth" and { others = Player } or nil)
end

-- The Personal Resource Display's markers, each built once its bar has the liquid (whose mask and level it takes),
-- so this is tried again with each Apply.
local function BuildDisplay()
    for _, key in ipairs({ "prdHealth", "prdPower" }) do
        for _, found in ipairs(ns.Bars.FindAll(key)) do
            local bar = found.bar
            if not extra[bar] and ns.Bars.PlateMask(bar) then
                if key == "prdHealth" then
                    extra[bar] = BuildOn(bar, "health", ns.Heals.Player, PlayerAlive,
                        "Personal Resource Display health", nil, { others = Player })
                else
                    -- The mana under a druid's form is only ever mana, shown in the form; the power bar while it
                    -- shows mana.
                    extra[bar] = BuildOn(bar, "mana", ns.Heals.Mana, found.manaOnly and PlayerAlive or ManaShown,
                        found.manaOnly and "Personal Resource Display mana" or "Personal Resource Display power")
                end
            end
        end
    end
end

-- Other addons' bars for the player (SmoothAnimatedBars.AddBar): a marker on each health bar, and on each power bar
-- while it shows mana. Each shows only while the bar is still added for the player, filling from the left, with the
-- liquid showing.
local function BuildExternal()
    for _, kind in ipairs({ "health", "power" }) do
        for _, bar in ipairs(ns.Bars.ExternalBars("player", kind)) do
            local want = kind == "health" and "health" or "mana"
            local had = extra[bar]
            -- Added again as the other kind: the old marker goes for good, a new one comes.
            if had and had.name ~= want then
                pcall(Hide, had)
                had.retired = true
                retired[#retired + 1] = had
                extra[bar] = nil
            end
            if not extra[bar] then
                local base = kind == "health" and PlayerAlive or ManaShown
                local function visible()
                    local unit, k, _, _, mirror = ns.Bars.External(bar)
                    return unit == "player" and k == kind and not mirror and ns.Bars.IsLive(bar) and base()
                end
                local _, _, _, mask = ns.Bars.External(bar)
                local function up() return (select(3, ns.Bars.External(bar))) or 1 end
                local function max()
                    if kind == "health" then return UnitHealthMax("player") end
                    return UnitPowerMax("player", MANA)
                end
                extra[bar] = BuildOn(bar, want, kind == "health" and ns.Heals.Player or ns.Heals.Mana, visible,
                    "other addon's " .. (kind == "health" and "health" or "power"), { mask = mask, up = up, max = max })
            end
        end
    end
end

-- The party frames' and the raid-style frames' health bars: a marker on each once it has the liquid (whose mask, layers
-- and effects it takes), following the member on the bar. The frames are made when they first show, and raid frames
-- are made on demand, so this is tried again now and then (OnUpdate).
local function BuildGroup()
    for _, kind in ipairs({ "party", "raid" }) do
        for _, found in ipairs(ns.Bars.FindAll(kind .. "Health")) do
            local bar = found.bar
            if not group[bar] and ns.Bars.Liquid(bar) then
                local m
                local function unit() return m and GroupUnit(m) end
                local function read()
                    local u = unit()
                    if not u then return 0, {} end
                    return ns.Heals.For(u)
                end
                local function visible()
                    local u = unit()
                    if not u or not ns.Bars.IsLive(bar) then return false end
                    local ok, dead = pcall(UnitIsDeadOrGhost, u)
                    return not (ok and not Secret(dead) and dead)
                end
                local opts = { others = unit }
                if kind == "raid" then
                    local b = ns.Bars.stateOf[bar]
                    local member = b and b.spot.member
                    local button = type(member) == "table" and member or nil
                    opts.raid, opts.prediction = true, button and button.myHealPrediction
                    opts.othersPrediction = button and button.otherHealPrediction
                end
                m = BuildOn(bar, "health", read, visible, kind .. " health", nil, opts)
                if m then
                    m[kind], m.every, m.wait = true, 1 / PARTY_FPS, 0
                    m.live = ns.Core.Get("heals") and true or false
                    group[bar] = m
                end
            end
        end
    end
end

-- BuildGroup, guarded: a failure is reported once and stops the building until a reload, so it can hold up neither
-- every marker's update each second (OnUpdate) nor the rest of Apply (heal tracking, the driver, the player's marker).
local function TryBuildGroup()
    if groupErr then return end
    local ok, err = pcall(BuildGroup)
    if not ok then
        groupErr = tostring(err)
        ns.Core.Print("Error building the party and raid heal markers, which are off until a reload: " .. groupErr)
    end
end

local function OnUpdate(_, elapsed)
    local dt = math.min(elapsed, 0.1)
    if dt <= 0 then return end
    lookIn = lookIn - dt
    if lookIn <= 0 then
        lookIn = PARTY_LOOK_EVERY
        TryBuildGroup()
    end
    Each(function(m)
        if not m.live or m.err or m.retired then return end
        local step = dt
        -- A party or raid member's marker at most PARTY_FPS times a second, a raid frame's at the raid liquids' rate
        -- (Bars.raid.Rate: slower the more show), with the time since its last update.
        if m.every then
            m.wait = m.wait + dt
            local every = m.every
            if m.raid then
                local fps = ns.Bars.raid.Rate()
                if type(fps) == "number" and fps > 0 then every = 1 / fps end
            end
            if m.wait < every then return end
            step, m.wait = math.min(m.wait, 0.1), 0
        end
        local ok, err = pcall(Update, m, step)
        if not ok then
            m.err = tostring(err)
            pcall(Hide, m)
            ns.Core.Print("Error in the " .. (m.label or m.name) .. " heal marker, which is off until a reload: "
                .. m.err)
        end
    end)
end

-- Others' heals on a group member: the game says when they change (UNIT_HEAL_PREDICTION), which wakes the member's
-- resting marker for a look at the game's bar. The player's own markers look every refresh anyway.
local predict = CreateFrame("Frame")
predict:SetScript("OnEvent", function(_, _, unit)
    if type(unit) ~= "string" or Secret(unit) then return end
    -- The event fires for nameplates, the target and the focus too: only a group bar's unit can be on one.
    if unit ~= "player" and not unit:match("^party%d") and not unit:match("^raid%d") then return end
    for _, m in pairs(group) do
        if m.hidden and GroupUnit(m) == unit then
            m.othersWake = true
            m.since = REFRESH_EVERY
        end
    end
end)

-- After the heals setting changes, and at login.
function HealMarker.Apply()
    local live = ns.Core.Get("heals") and true or false
    if live and not player then player = Build("playerHealth", ns.Heals.Player, PlayerAlive) end
    if live and not mana then mana = Build("playerPower", ns.Heals.Mana, ManaShown) end
    if live then
        BuildDisplay()
        BuildExternal()
        TryBuildGroup()
    end
    ns.Heals.Enable(live)
    if live then predict:RegisterEvent("UNIT_HEAL_PREDICTION") else predict:UnregisterAllEvents() end
    Each(function(m)
        m.live = live
        if not live then Hide(m) end
    end)
    local any = live and (player or mana or next(extra) or next(group) or previews[1]) and true or false
    if any and not driver then
        driver = CreateFrame("Frame")
        driver:SetScript("OnUpdate", OnUpdate)
    end
    if driver then driver:SetShown(any) end
end

-- A marker on a preview frame's health bar (Preview.lua, the editor's and the setup's), shown while the bar shows and
-- the heals setting is on. source: function() returning the heals still to come as Heals.Player does (total, list of
-- { school, heal }), in the bar's own range. Named "preview", so the player's real heals and meals never reach it.
-- tight: cut at the bar's edges (HealMarker New, spec.tight).
function HealMarker.Preview(bar, source, tight)
    local m = BuildOn(bar, "preview", source, function() return bar:IsVisible() end, "preview", nil,
        tight and { tight = true } or nil)
    if not m then return nil end
    previews[#previews + 1] = m
    HealMarker.Apply()
    return m
end

-- A heal just started on a preview's bar: its liquids and the health's splash, as a real one does.
function HealMarker.Landed(m)
    m.landed = true
    m.since = REFRESH_EVERY
end

-- After an effect toggle: clear what was just switched off.
function HealMarker.ApplyOptions()
    Each(function(m)
        for _, d in ipairs(m.all) do d.liquid:ApplyOptions() end
    end)
end

-- Each marker hears of the heals that went to whoever it shows: the player's, or its party member's.
ns.Heals.Listen(function(event, arg, who)
    Each(function(m) m.since = REFRESH_EVERY end) -- read again on the next frame
    if event == "applied" then
        local name = arg == "mana" and "mana" or "health"
        Each(function(m)
            if m.name == name and Owner(m) == (who or "player") then m.landed = true end
        end)
    elseif event == "landed" then
        Each(function(m)
            if m.name == "health" and Owner(m) == (who or "player") then m.burst = arg end
        end)
    end
end)

-- For the tests and the gallery: the markers on the player frame's health and mana bars (nil until built), the
-- Personal Resource Display's by bar, and the party and raid-style frames' by bar.
function HealMarker.State()
    return player, mana, extra, group
end

-- Others' heals on a marker, for /sab heals: whether the game shows its bar for them (and whether that answer is
-- readable), and whether the calculator answers.
local function OthersDebug(m)
    local region = GameOthers(m)
    local state = "no game bar"
    if region then
        local ok, shown = pcall(region.IsShown, region)
        state = not ok and "game bar unreadable" or Secret(shown) and "game bar secret"
            or (shown and "game bar shown" or "game bar hidden")
    end
    local amount = OthersAmount(m.spec.unit and m.spec.unit())
    return string.format(", others' heals: %s, calculator %s", state,
        amount == nil and "no answer" or Secret(amount) and "secret" or tostring(amount))
end

-- For /sab heals.
function HealMarker.Debug()
    if not ns.Core.Get("heals") then return { "Heal marker: off (Heal Marker in the editor)" } end
    local out = {}
    if not player then out[1] = "Heal marker: the player frame's health bar was not found" end
    Each(function(m)
        if m.name == "preview" then return end
        local shown = {}
        for _, d in ipairs(m.all) do
            if d.pool:IsShown() then shown[#shown + 1] = d.themeKey or DEFAULT_THEME end
        end
        local game = GamePrediction(m)
        local label = m.label or m.name
        if m.party or m.raid then label = label .. " on " .. (GroupUnit(m) or "no member") end
        out[#out + 1] = string.format("Heal marker (%s): on, %s, liquids %s%s, mask %s%s%s%s", label,
            m.clip:IsShown() and "showing" or "hidden", #shown > 0 and table.concat(shown, " then ") or "none",
            m.under and " under the bar's liquid" or " over the game's fill", m.spec.mask and "yes" or "no",
            m.name == "health" and (", game's own prediction " .. (not game and "not found"
                or Secret(game:GetAlpha()) and "secret" or game:GetAlpha() == 0 and "hidden" or "shown")) or "",
            m.others and OthersDebug(m) or "",
            m.err and (", error: " .. m.err) or "")
    end)
    return out
end
