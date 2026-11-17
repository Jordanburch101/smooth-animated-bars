-- The editor: every setting beside live examples of every frame, in a window of our own. /sab opens it, as do the
-- settings page's Open Editor and the unit frames' menus (at that frame).
--
--   * Tabs along the top: Frames, Effects, Combat and Other Addons, with Run Setup and What's New beside them.
--   * On the left a screen of examples where the game puts them (Preview.lua): the player and target frames, the party
--     stacked, nameplates, the Personal Resource Display, raid frames, the breath bar, and the focus, pet and target of
--     target. Clicking
--     one edits it: a gold outline round it, and frames whose liquid is off are dimmed. Scenes (fight, damage, healing,
--     power) play on every
--     example at once; only the one being edited plays at full speed (Preview.SetActive).
--   * On the right the inspector: for a frame, a card per bar (on/off, what it shows, its colour) that opens a drawer
--     with two tabs. Colour: follow another frame's colour, or pick a theme from its tiles; hovering a tile tries it on
--     every bar it would reach (Core.Try) until the mouse leaves. Effects: the global effects, or the bar's own
--     (Core.SetEffect), each bar apart. For the other tabs, their settings.
-- Every change goes through the settings (Core.SetSetting, so the game's registered settings follow) and shows at once
-- on the examples and the real frames.
--
-- Built from the game's window, button and check button templates and plain frames; colours are SetColorTexture and
-- never game files by path (see the project rules about Forever). Pages are built the first time they show.

local _, ns = ...

local Editor = {}
ns.Editor = Editor

local W, H = 1180, 630
local INSPECT_W = 330
local STAGE_W = W - INSPECT_W - 12 - 12 - 8  -- 818
local LIST_W = INSPECT_W - 20 - 18           -- the inspector's scrolled list, beside its scroll bar
local GOLD = { 1, 0.82, 0 }
local EDGE = { 0.32, 0.30, 0.36 }
local MUTED = { 0.66, 0.64, 0.60 }

local function Get(key) return ns.Core.Get(key) end

--------------------------------------------------------------------------------
-- What there is to edit
--------------------------------------------------------------------------------

-- A frame's two bars: on/off setting, colour setting, whose colour ("frame", Core.ColorChoice's).
local function TwoBars(frame, prefix, healthColor, powerColor)
    return {
        { on = prefix .. "Health", color = healthColor, frame = frame, kind = "health", label = "Health" },
        { on = prefix .. "Power", color = powerColor, frame = frame, kind = "power", label = "Power" },
    }
end

-- same: what following is called on the frame's bars ("same" in its colour setting), and whose it follows; mobs: the
-- Core function saying when Class Color on Mobs matters there; rows: on/off settings with what they do.
local FRAMES = {
    player = { label = "Player", desc = "Liquid in your own health and power bars.",
               bars = TwoBars("player", "player", "healthColor", "powerColor") },
    target = { label = "Target", desc = "Liquid in your target's bars. Class Color shows a targeted player's class.",
               same = "Same as Yours", whose = "your", mobs = "TargetUsesClass",
               bars = TwoBars("target", "target", "targetHealthColor", "targetPowerColor") },
    focus = { label = "Focus", desc = "Liquid in your focus's bars.", same = "Same as Target", whose = "your target's",
              mobs = "TargetUsesClass", bars = TwoBars("focus", "focus", "focusHealthColor", "focusPowerColor") },
    pet = { label = "Pet", desc = "Liquid in your pet's bars. With Class Color your pet takes your class.",
            same = "Same as Yours", whose = "your", bars = TwoBars("pet", "pet", "petHealthColor", "petPowerColor") },
    tot = { label = "Target of Target", desc = "Liquid in your target's target's and your focus's target's bars.",
            same = "Same as Target", whose = "your target's", mobs = "TargetUsesClass",
            bars = TwoBars("tot", "tot", "totHealthColor", "totPowerColor") },
    party = { label = "Party", desc = "Liquid in your party members' bars. While a member is offline the game's grey "
                  .. "bar comes back. Class Color shows each member's class.",
              same = "Same as Yours", whose = "your",
              bars = TwoBars("party", "party", "partyHealthColor", "partyPowerColor") },
    raid = { label = "Raid", desc = "Liquid in the raid frames, and the party's in raid style. The game's names, icons, "
                 .. "heal prediction and shields stay on top. Game Colour takes the raid frames' own colours.",
             same = "Same as Party", whose = "your party's",
             bars = TwoBars("raid", "raid", "raidHealthColor", "raidPowerColor") },
    prd = { label = "Personal Resource", desc = "The extra bars the game shows with its Personal Resource Display "
                .. "option on, placed with Edit Mode, with a druid's mana under them in a form.",
            same = "Same as Yours", whose = "your", bars = TwoBars("prd", "prd", "prdHealthColor", "prdPowerColor") },
    plates = { label = "Nameplates", desc = "Liquid in nameplates' health bars: the first 15 enemies in a crowd, and up "
                   .. "to 10 friends. Friendly nameplates in dungeons are locked to addons.",
               mobs = "PlatesUseClass",
               bars = {
                   { on = "plateHealth", color = "plateHealthColor", frame = "plate", kind = "health",
                     label = "Enemy Nameplates", same = "Same as Target", whose = "your target's" },
                   { on = "plateFriendly", color = "plateFriendlyColor", frame = "friend", kind = "health",
                     label = "Friendly Nameplates", same = "Same as Enemy Nameplates", whose = "the enemy nameplates'" },
               },
               rows = {
                   { key = "plateDots", label = "Your DoTs on Nameplates",
                     desc = "The DoT marker on every mob carrying your damage over time.",
                     shown = function() return Get("plateHealth") end },
                   { key = "plateKillIcon", label = "Kill Icon on Nameplates",
                     desc = "The game's skull beside a nameplate when your DoTs will finish that mob off.",
                     shown = function() return Get("plateHealth") and Get("plateDots") end },
               } },
    breath = { label = "Breath and Fatigue", desc = "Liquid in the bars the game shows while you hold your breath under "
                   .. "water, and out in open sea. Feign Death keeps the game's own bar. The example shows the open card.",
               bars = {
                   { on = "breath", color = "breathColor", frame = "breath", kind = "breath", label = "Breath Bar",
                     same = "Same as Your Power", whose = "your" },
                   { on = "fatigue", color = "fatigueColor", frame = "breath", kind = "fatigue", label = "Fatigue Bar",
                     same = "Same as Your Power", whose = "your" },
               },
               rows = {
                   { key = "breathBubbles", label = "Bubbles While Holding Breath",
                     desc = "Bubbles escape from the breath bar's front and float up while your breath runs out, not "
                         .. "while it comes back. With the Bubbles effect on.",
                     shown = function() return Get("breath") end },
                   { key = "fatigueDrips", label = "Drips While Fatigued",
                     desc = "Drops gather under the fatigue bar's front and fall while fatigue runs out, not while it "
                         .. "comes back.",
                     shown = function() return Get("fatigue") end },
               } },
}

-- The other tabs: their settings.
local TABS = {
    { id = "frames", label = "Frames" },
    { id = "effects", label = "Effects",
      desc = "What moves inside every liquid. A bar can have its own: open its card under Frames.",
      rows = {
          { key = "waves", label = "Liquid Waves", desc = "A wobbling front that ripples when the bar changes." },
          { key = "swirl", label = "Magic Swirl", desc = "Glowing veins, clouds and light drifting inside the liquid." },
          { key = "bubbles", label = "Bubbles", desc = "Bubbles rising through the liquid." },
          { key = "sparkles", label = "Sparkles", desc = "Motes thrown off the front when the bar changes." },
          { key = "ambient", label = "Theme Particles",
            desc = "Embers, snow, spores, stars and the like from themes that have them." },
          { key = "lightning", label = "Lightning",
            desc = "Faint flashes that build into a storm when the bar changes a lot." },
      } },
    { id = "combat", label = "Combat",
      desc = "Markers on your bars for what is still to come, and how your mana and rage behave.",
      rows = {
          { key = "dots", label = "DoT Marker",
            desc = "The health your damage over time will still burn away, as a liquid of its own on your target." },
          { key = "dotKillIcon", label = "Kill Icon",
            desc = "The game's skull on your target's portrait when your DoTs will finish it off." },
          { key = "heals", label = "Heal Marker",
            desc = "Your heals over time, bandages, food and drink, ahead of your health and mana. Play Healing." },
          { key = "manaBuild", label = "Mana Regen Build-Up",
            desc = "Your mana bar builds up through the five seconds after a spell, and lets go in stars." },
          { key = "rageFury", label = "Rage Fury",
            desc = "Your rage bar grows more furious as it fills, and bursts in sparks when you spend it." },
      } },
    { id = "addons", label = "Other Addons",
      desc = "Unit frame addons can hand their health and power bars to Smooth Animated Bars.",
      rows = {
          { key = "externalBars", label = "Other Addons' Bars",
            desc = "Liquid in their bars. They keep the colours you set in that addon, unless it offers a theme from here." },
          { key = "externalColors", label = "Your Colours on Their Bars",
            desc = "Their bars take the colour you pick here for the frame each one stands for, Game Colour too: green "
                .. "health, and power in its own colour.",
            shown = function() return Get("externalBars") end },
      } },
}
local TAB_BY_ID = {}
for _, t in ipairs(TABS) do TAB_BY_ID[t.id] = t end
-- Sections the editor opened at before it had tabs (and the unit menus' older names), and where they are now.
local ALIASES = { dots = "combat", heals = "combat", mana = "combat", fury = "combat" }

-- The colour choices in groups, as Themes.lua lays them out; a theme not named here goes in the last group.
local THEME_GROUPS = {
    { "Basics", { "game", "class", "faction", "luxthos", "prismatic" } },
    { "Colours", { "arcane", "fel", "holy", "blood", "ember", "tidal", "plague", "midnight", "sunset" } },
    { "Outland", { "zangarmarsh", "netherstorm", "hellfire", "nagrand" } },
    { "Elements", { "fire", "frost", "honey", "lava", "cosmic", "nature", "void", "shadow" } },
}
local MOBS = { { "reaction", "Reaction" }, { "game", "Game Colour" }, { "class", "Mob's Class" }, { "own", "Your Class" } }
local SCENE_LABELS = { fight = "Fight", damage = "Damage", heal = "Healing", power = "Power" }
local EFFECT_LABELS = { waves = "Waves", swirl = "Magic Swirl", bubbles = "Bubbles", sparkles = "Sparkles",
                        ambient = "Theme Particles", lightning = "Lightning" }

-- Every setting a frame or tab has a control for.
local function Keys(f)
    local keys = {}
    for _, bar in ipairs(f.bars or {}) do
        keys[#keys + 1] = bar.on
        keys[#keys + 1] = bar.color
    end
    if f.mobs then keys[#keys + 1] = "mobClassColor" end
    for _, row in ipairs(f.rows or {}) do keys[#keys + 1] = row.key end
    return keys
end

local function FrameOn(f)
    for _, bar in ipairs(f.bars) do
        if Get(bar.on) then return true end
    end
    return false
end

--------------------------------------------------------------------------------
-- Colours of the choices, for swatches and tiles
--------------------------------------------------------------------------------

local function PowerColor()
    local _, token = UnitPowerType("player")
    if (issecretvalue and issecretvalue(token)) or not token then token = "MANA" end
    local c = PowerBarColor and PowerBarColor[token]
    return c and { c.r, c.g, c.b } or { 0, 0, 1 }
end

-- The two ends of a choice's fill: the game's own colour for the bar, or the theme's fill as it shows on your frame.
local function Ends(choice, frame, kind)
    if choice == "game" and frame == "raid" and kind == "health" then
        -- The raid frames' own colour: class colours with the game's setting for them, else the colour it sets.
        local getCVar = (C_CVar and C_CVar.GetCVar) or rawget(_G, "GetCVar")
        local ok, byClass = pcall(getCVar, "raidFramesDisplayClassColor")
        if ok and byClass == "1" then return Ends("class", frame, kind) end
        local okHex, hex = pcall(getCVar, "raidFramesHealthBarColor")
        local c = okHex and ns.Bars.raid.Hex(hex)
        if c then return { c[1] * 0.45, c[2] * 0.45, c[3] * 0.45 }, c end
    end
    if choice == "game" then
        local c
        if frame == "plate" then c = { 1, 0, 0 }
        elseif frame == "friend" then c = { 0, 1, 0 }
        elseif kind == "health" then c = { 0, 0.8, 0 }
        elseif frame == "player" or frame == "pet" or frame == "prd" then c = PowerColor()
        elseif frame == "breath" then c = ns.Bars.mirror.Color(kind)
        else c = { 0, 0, 1 } end
        return { c[1] * 0.45, c[2] * 0.45, c[3] * 0.45 }, c
    end
    local theme = ns.Themes.Get(choice)
    if theme.Colors then
        local a, b = theme:Colors(0, 1)
        return a, b
    end
    if theme.Resolve then theme = theme:Resolve("player", true) or theme end
    return theme.fillA, theme.fillB
end

local function Paint(tex, choice, frame, kind)
    local a, b = Ends(choice, frame, kind)
    tex:SetColorTexture(1, 1, 1, 1)
    if CreateColor and tex.SetGradient then
        tex:SetGradient("HORIZONTAL", CreateColor(a[1], a[2], a[3], 1), CreateColor(b[1], b[2], b[3], 1))
    else
        tex:SetColorTexture(b[1], b[2], b[3], 1)
    end
end

-- A colour tile: a still of the theme's liquid, built from the layers Liquid.lua draws it with: its fill, its clouds
-- and veins (the theme's own textures, in its colours), the glow and bright line of its front on the right, and the
-- particles it throws (snow for Frost, sparks for Fire, leaves for Nature...), a couple of them over the top. Still, so
-- a drawer of tiles costs nothing while it is open.
local TILE_W, TILE_H, TILE_GAP, TILES_PER_ROW = 40, 20, 4, 6
local MEDIA = "Interface\\AddOns\\SmoothAnimatedBars\\Media\\"
-- Particles too small or too soft to read at a tile's size, where a theme has nothing better.
local FAINT = { Mote = true, Glow = true, Wisp = true }

local function TileTheme(choice, frame, kind)
    local a, b = Ends(choice, frame, kind)
    local theme
    if choice == "game" then
        theme = ns.Themes.FromColor(b, ns.Themes.Get(ns.Themes.default))
    else
        theme = ns.Themes.Get(choice)
        if theme.Resolve then theme = theme:Resolve("player", true) or theme end
    end
    return theme, a, b
end

-- The particle a theme shows best at a tile's size: its own ambient particles, else what it throws, else none.
local function TileParticle(theme)
    local ambient = type(theme.ambient) == "table" and theme.ambient or {}
    for _, em in ipairs(ambient) do
        if em.texture and not FAINT[em.texture] then return em.texture, em.blend end
    end
    local burst = type(theme.burst) == "table" and theme.burst
    if burst and burst.texture and not FAINT[burst.texture] then return burst.texture, burst.blend end
end

local function Layer(tile, sub, file, blend, color, alpha)
    local t = tile:CreateTexture(nil, "ARTWORK", nil, sub)
    t:SetTexture(MEDIA .. file)
    t:SetPoint("TOPLEFT", 2, -2)
    t:SetPoint("BOTTOMRIGHT", -2, 2)
    t:SetBlendMode(blend)
    t:SetVertexColor(color[1], color[2], color[3], alpha)
    return t
end

-- Paints tile (a button TILE_W x TILE_H) as choice's liquid on a bar of this frame and kind.
local function PaintTile(tile, choice, frame, kind)
    local theme, a, b = TileTheme(choice, frame, kind)
    tile.swatch = tile:CreateTexture(nil, "ARTWORK", nil, 0)
    tile.swatch:SetPoint("TOPLEFT", 2, -2)
    tile.swatch:SetPoint("BOTTOMRIGHT", -2, 2)
    tile.swatch:SetColorTexture(1, 1, 1, 1)
    if CreateColor and tile.swatch.SetGradient then
        tile.swatch:SetGradient("HORIZONTAL", CreateColor(a[1], a[2], a[3], 1), CreateColor(b[1], b[2], b[3], 1))
    else
        tile.swatch:SetColorTexture(b[1], b[2], b[3], 1)
    end
    local clouds = type(theme.clouds) == "table" and theme.clouds or {}
    local swirl = type(theme.swirl) == "table" and theme.swirl or {}
    local light = theme.swirlB or b
    local veins = theme.swirlA or b
    -- Each texture at the scale Liquid.lua draws it on a bar (its DrawLayer calls): a vein texture repeats every 256 px
    -- across and 64 down, the second veins at 0.7 of that, the clouds at their scale (0.55) and the light ones 1.4 times
    -- that. Mapping a whole slice of a texture into the tile squeezed it (seen in game).
    local w, h = TILE_W - 4, TILE_H - 4
    local function Span(layer, k, u, v)
        layer:SetTexCoord(u, u + w * k / 256, v, v + h * k / 64)
    end
    local cs = clouds.scale or 0.55
    local dark = Layer(tile, 1, clouds.texture or "Nebula", "BLEND", { 0, 0, 0 }, (clouds.dark or 0.55) * 0.6)
    Span(dark, cs, 0.1, 0.2)
    local wisps = Layer(tile, 2, clouds.texture or "Nebula", "ADD", light, (clouds.light or 0.25) * 1.2)
    Span(wisps, cs * 1.4, 0.5, 0.55)
    -- Veins, two layers as on a bar, as bright as the theme makes them.
    local vein = Layer(tile, 3, swirl.texture or "Swirl", "ADD", veins, math.min(0.8, 0.45 * (swirl.alpha or 1)))
    Span(vein, 1, 0.2, 0.3)
    local vein2 = Layer(tile, 3, swirl.texture or "Swirl", "ADD", light, math.min(0.6, 0.3 * (swirl.alpha or 1)))
    Span(vein2, 0.7, 0.6, 0.1)
    -- The front: a glow and a bright line along the tile's right edge.
    local glowColor = theme.glow or b
    local glow = tile:CreateTexture(nil, "ARTWORK", nil, 4)
    glow:SetTexture(MEDIA .. "Glow")
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(glowColor[1], glowColor[2], glowColor[3], 0.7)
    glow:SetSize(14, TILE_H)
    glow:SetPoint("RIGHT", -2, 0)
    local tipColor = theme.tip or b
    local tip = tile:CreateTexture(nil, "ARTWORK", nil, 5)
    tip:SetColorTexture(tipColor[1], tipColor[2], tipColor[3], 0.85)
    tip:SetWidth(1)
    tip:SetPoint("TOPRIGHT", -2, -2)
    tip:SetPoint("BOTTOMRIGHT", -2, 2)
    -- Its particles.
    local file, blend = TileParticle(theme)
    if file then
        local from, to = theme.splashFrom or tipColor, theme.splashTo or b
        for i, spot in ipairs({ { 10, -3, 10, from }, { 24, -8, 8, to } }) do
            local p = tile:CreateTexture(nil, "OVERLAY", nil, i)
            p:SetTexture(MEDIA .. file)
            p:SetBlendMode(blend or "ADD")
            p:SetVertexColor(spot[4][1], spot[4][2], spot[4][3], 0.95)
            p:SetSize(spot[3], spot[3])
            p:SetPoint("TOPLEFT", spot[1], spot[2])
        end
        tile.particle = file
    end
end

local function ChoiceName(choice, bar, f)
    if choice == "same" then return bar.same or f.same or "Same" end
    if choice == "game" then return "Game Colour" end
    return ns.Themes.Get(choice).name
end

--------------------------------------------------------------------------------
-- Building blocks
--------------------------------------------------------------------------------

local frame, ui, current, tab
local Refresh, Layout

local function Font(parent, template, text, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", template)
    fs:SetText(text or "")
    if justify then fs:SetJustifyH(justify) end
    return fs
end

local function Muted(fs)
    fs:SetTextColor(MUTED[1], MUTED[2], MUTED[3])
    return fs
end

local function Button(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

-- A 1 px outline of solid colour around a frame, its edges returned to recolour.
local function Outline(f, color, alpha)
    local edges = {}
    for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" },
                            { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
        local t = f:CreateTexture(nil, "BORDER")
        t:SetColorTexture(color[1], color[2], color[3], alpha or 1)
        t:SetPoint(side[1])
        t:SetPoint(side[2])
        if side[1]:sub(1, 3) == side[2]:sub(1, 3) then t:SetHeight(1) else t:SetWidth(1) end
        edges[#edges + 1] = t
    end
    return edges
end

local function Recolor(edges, color, alpha)
    for _, t in ipairs(edges) do t:SetColorTexture(color[1], color[2], color[3], alpha or 1) end
end

local function Shade(f, alpha)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, alpha)
    return bg
end

-- Every change goes into the settings, through their registered settings, and the window follows.
local function Set(key, value)
    ns.Core.SetSetting(key, value)
    Refresh()
end

-- A chip: a small button with a name, outlined in gold while picked.
local function Chip(parent, w, h, text, onClick)
    local c = CreateFrame("Button", nil, parent)
    c:SetSize(w, h)
    c.bg = Shade(c, 0.55)
    local hl = c:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    c.edges = Outline(c, EDGE)
    c.text = Font(c, "GameFontHighlightSmall", text, "CENTER")
    c.text:SetPoint("LEFT", 4, 0)
    c.text:SetPoint("RIGHT", -4, 0)
    c.text:SetWordWrap(false)
    c:SetScript("OnClick", onClick)
    function c.SetPicked(_, on)
        c.picked = on and true or false
        Recolor(c.edges, on and GOLD or EDGE)
        c.bg:SetColorTexture(on and 0.16 or 0, on and 0.12 or 0, on and 0.02 or 0, 0.55)
        if on then c.text:SetTextColor(GOLD[1], GOLD[2], GOLD[3]) else c.text:SetTextColor(1, 1, 1) end
    end
    return c
end

-- A tab along the top: the character sheet's title plaque (atlas UI-Character-Info-Title) with the name in gold, as
-- Road to Sixty's mode switch has it; the picked one in full colour with its name in white, the others faded and grey.
local function Tab(parent, w, text, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, 28)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    if not (b.bg.SetAtlas and b.bg:SetAtlas("UI-Character-Info-Title")) then b.bg:SetColorTexture(0.14, 0.11, 0.06, 0.9) end
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)
    b.text = Font(b, "GameFontNormal", text, "CENTER")
    b.text:SetPoint("CENTER", 0, 1)
    b:SetScript("OnClick", onClick)
    function b.SetPicked(_, on)
        b.picked = on and true or false
        if b.bg.SetDesaturated then b.bg:SetDesaturated(not on) end
        b.bg:SetAlpha(on and 1 or 0.7)
        if on then b.text:SetTextColor(1, 1, 1) else b.text:SetTextColor(GOLD[1], GOLD[2], GOLD[3]) end
    end
    return b
end

-- A check box from the game's template with a label beside it; onClick decides what a click does.
local function Check(parent, label, onClick, template)
    local b = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    b:SetSize(24, 24)
    b:SetScript("OnClick", onClick)
    if label then
        b.label = Font(parent, template or "GameFontHighlightSmall", label, "LEFT")
        b.label:SetPoint("LEFT", b, "RIGHT", 2, 0)
    end
    return b
end

--------------------------------------------------------------------------------
-- The inspector: a frame's cards and drawers
--------------------------------------------------------------------------------


-- The Colour tab of a bar's drawer: follow another frame's colour, or a theme from the tiles, each tried on the bars
-- while the mouse is on it.
local function ColourPane(drawer, bar, f)
    local p = CreateFrame("Frame", nil, drawer)
    local y = 4
    if bar.same or f.same then
        local whose = bar.whose or f.whose
        p.follow = Check(p, "Follow " .. whose .. " " .. (bar.kind == "health" and "health" or "power") .. " colour",
            function()
                if Get(bar.color) == "same" then
                    -- Keep showing what it showed: the followed colour, now its own.
                    Set(bar.color, ns.Core.SameChoice(bar.frame, bar.kind) or "game")
                else
                    Set(bar.color, "same")
                end
            end)
        p.follow:SetPoint("TOPLEFT", 4, -y)
        y = y + 28
    end
    p.tiles = {}
    p.tileFrame = CreateFrame("Frame", nil, p)
    p.tileFrame:SetPoint("TOPLEFT", 0, -y)
    p.tileFrame:SetPoint("TOPRIGHT", 0, -y)
    local listed, groups = {}, {}
    for _, g in ipairs(THEME_GROUPS) do
        for _, key in ipairs(g[2]) do listed[key] = true end
    end
    for i, g in ipairs(THEME_GROUPS) do
        local keys = {}
        for _, key in ipairs(g[2]) do
            if key == "game" or ns.Themes.list[key] then keys[#keys + 1] = key end
        end
        if i == #THEME_GROUPS then
            for _, key in ipairs(ns.Themes.order) do
                if not listed[key] then keys[#keys + 1] = key end
            end
        end
        groups[i] = { g[1], keys }
    end
    local ty = 0
    for _, g in ipairs(groups) do
        local head = Muted(Font(p.tileFrame, "GameFontNormalSmall", g[1]:upper(), "LEFT"))
        head:SetPoint("TOPLEFT", 6, -ty)
        ty = ty + 13
        for n, key in ipairs(g[2]) do
            local col, line = (n - 1) % TILES_PER_ROW, math.floor((n - 1) / TILES_PER_ROW)
            local t = CreateFrame("Button", nil, p.tileFrame)
            t:SetSize(TILE_W, TILE_H)
            t:SetPoint("TOPLEFT", 6 + col * (TILE_W + TILE_GAP), -(ty + line * (TILE_H + TILE_GAP)))
            PaintTile(t, key, bar.frame, bar.kind)
            t.edges = Outline(t, { 0, 0, 0 })
            t.key, t.name = key, ChoiceName(key, bar, f)
            t:SetScript("OnEnter", function()
                if p.following then return end
                ui.trying = t.name
                ns.Core.Try(bar.color, key)
                p.trying:SetText("Trying " .. t.name .. ": click to keep it")
                p.trying:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
            end)
            t:SetScript("OnLeave", function()
                ui.trying = nil
                ns.Core.Try(nil)
                p.trying:SetText(p.picked or "")
                Muted(p.trying)
            end)
            t:SetScript("OnClick", function()
                if p.following then return end
                ui.trying = nil
                ns.Core.Try(nil)
                Set(bar.color, key)
            end)
            p.tiles[key] = t
        end
        ty = ty + math.ceil(#g[2] / TILES_PER_ROW) * (TILE_H + TILE_GAP) + 4
    end
    p.tileFrame:SetHeight(ty)
    p.trying = Muted(Font(p, "GameFontHighlightSmall", "", "LEFT"))
    p.trying:SetPoint("TOPLEFT", 6, -(y + ty + 2))
    p.height = y + ty + 20
    p:SetHeight(p.height)
    return p
end

-- The Effects tab: the global effects, or this bar's own.
local function EffectsPane(drawer, bar)
    local p = CreateFrame("Frame", nil, drawer)
    p.global = Check(p, "Use the global effects", function()
        local key = bar.on
        -- Both apply the effects once and refresh the editor.
        if ns.Core.db.effects and ns.Core.db.effects[key] then
            ns.Core.ClearEffects(key)
        else
            ns.Core.OwnEffects(key)
        end
    end)
    p.global:SetPoint("TOPLEFT", 4, -4)
    p.fx = {}
    for i, effect in ipairs(ns.Core.EFFECTS) do
        local col, line = (i - 1) % 2, math.floor((i - 1) / 2)
        local c = Check(p, EFFECT_LABELS[effect], function()
            ns.Core.SetEffect(bar.on, effect, not ns.Core.Effect(bar.on, effect)) -- refreshes the editor
        end)
        c:SetPoint("TOPLEFT", 4 + col * 140, -(34 + line * 24))
        p.fx[effect] = c
    end
    p.height = 34 + 3 * 24 + 6
    p:SetHeight(p.height)
    return p
end

-- A bar's card: its on/off box, its name, what it shows, its colour; opening its drawer under it.
local function Card(page, bar, f)
    local c = CreateFrame("Frame", nil, page)
    c.bg = Shade(c, 0.35)
    c.edges = Outline(c, EDGE)
    c.check = Check(c, nil, function() Set(bar.on, not Get(bar.on)) end)
    c.check:SetPoint("TOPLEFT", 8, -10)
    c.header = CreateFrame("Button", nil, c)
    c.header:SetPoint("TOPLEFT", 38, 0)
    c.header:SetPoint("TOPRIGHT", 0, 0)
    c.header:SetHeight(44)
    local hl = c.header:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.04)
    c.label = Font(c.header, "GameFontNormal", bar.label, "LEFT")
    c.label:SetPoint("TOPLEFT", 0, -9)
    c.summary = Muted(Font(c.header, "GameFontHighlightSmall", "", "LEFT"))
    c.summary:SetPoint("TOPLEFT", 0, -25)
    c.summary:SetWidth(LIST_W - 38 - 58)
    c.summary:SetWordWrap(false)
    c.swatch = c.header:CreateTexture(nil, "ARTWORK")
    c.swatch:SetSize(40, 10)
    c.swatch:SetPoint("RIGHT", -10, 0)
    c.header:SetScript("OnClick", function()
        page.open = page.open ~= bar and bar or nil
        Refresh()
    end)

    -- The drawer: tabs, then the tab's pane.
    c.drawer = CreateFrame("Frame", nil, c)
    c.drawer:SetPoint("TOPLEFT", 0, -44)
    c.drawer:SetPoint("TOPRIGHT", 0, -44)
    local rule = c.drawer:CreateTexture(nil, "BORDER")
    rule:SetColorTexture(EDGE[1], EDGE[2], EDGE[3], 1)
    rule:SetPoint("TOPLEFT", 6, 0)
    rule:SetPoint("TOPRIGHT", -6, 0)
    rule:SetHeight(1)
    c.tabs = {}
    for i, name in ipairs({ "colour", "effects" }) do
        local t = Chip(c.drawer, 72, 20, name == "colour" and "Colour" or "Effects", function()
            page.pane = name
            Refresh()
        end)
        t:SetPoint("TOPLEFT", 8 + (i - 1) * 76, -6)
        c.tabs[name] = t
    end
    -- Anchored by both top corners: a "RIGHT" point would also pin the pane's vertical middle to the drawer's, which
    -- in game gave it a negative height, and nothing in it drew (seen: an empty drawer).
    c.colour = ColourPane(c.drawer, bar, f)
    c.colour:SetPoint("TOPLEFT", 0, -32)
    c.colour:SetPoint("TOPRIGHT", 0, -32)
    c.effects = EffectsPane(c.drawer, bar)
    c.effects:SetPoint("TOPLEFT", 0, -32)
    c.effects:SetPoint("TOPRIGHT", 0, -32)
    c.bar = bar
    return c
end

-- An on/off setting's row: the box, its name and what it does.
local function OptionRow(page, row)
    local r = CreateFrame("Frame", nil, page)
    r.check = Check(r, nil, function() Set(row.key, not Get(row.key)) end)
    r.check:SetPoint("TOPLEFT", 6, -6)
    r.label = Font(r, "GameFontNormal", row.label, "LEFT")
    r.label:SetPoint("TOPLEFT", 36, -10)
    r.desc = Muted(Font(r, "GameFontHighlightSmall", row.desc, "LEFT"))
    r.desc:SetPoint("TOPLEFT", 36, -26)
    r.desc:SetWidth(LIST_W - 44)
    r.desc:SetWordWrap(true)
    r.height = math.max(40, 32 + r.desc:GetStringHeight())
    r:SetHeight(r.height)
    Shade(r, 0.35)
    Outline(r, EDGE)
    r.row = row
    return r
end

-- Class Color on Mobs: one choice of four, shown while a bar here shows Class Color.
local function MobRow(page)
    local r = CreateFrame("Frame", nil, page)
    r.height = 74
    r:SetHeight(r.height)
    Font(r, "GameFontNormal", "Class Color on Mobs", "LEFT"):SetPoint("TOPLEFT", 6, -4)
    r.chips = {}
    -- Two to a line, wide enough for their names.
    for i, mob in ipairs(MOBS) do
        local col, line = (i - 1) % 2, math.floor((i - 1) / 2)
        local c = Chip(r, 136, 20, mob[2], function() Set("mobClassColor", mob[1]) end)
        c:SetPoint("TOPLEFT", 6 + col * 142, -(24 + line * 24))
        r.chips[mob[1]] = c
    end
    return r
end

local function BuildPage(id)
    local page = CreateFrame("Frame", nil, ui.list)
    page:SetPoint("TOPLEFT")
    page:SetWidth(LIST_W)
    page.items, page.cards, page.rows = {}, {}, {}
    local f = FRAMES[id] or TAB_BY_ID[id]
    for i, bar in ipairs(f.bars or {}) do
        page.cards[i] = Card(page, bar, f)
        page.items[#page.items + 1] = page.cards[i]
    end
    page.open = f.bars and f.bars[1] or nil
    page.pane = "colour"
    if f.mobs then
        page.mob = MobRow(page)
        page.items[#page.items + 1] = page.mob
    end
    for _, row in ipairs(f.rows or {}) do
        local r = OptionRow(page, row)
        page.rows[row.key] = r
        page.items[#page.items + 1] = r
    end
    return page
end

--------------------------------------------------------------------------------
-- The screen: the examples, where the game puts them
--------------------------------------------------------------------------------

-- Each example: how to build it (Preview.lua), where it goes on the screen (from its top-left), and at what scale. Laid
-- out on one grid, measured on a screenshot of the editor and agreed on a mockup (canvas board F): a 20 px margin; the
-- player, target and focus along the top, the focus flush right; under them the pet (left edges with the player's),
-- the target of target (right edges with the focus's) and between them the Personal Resource Display; then the party
-- down the left, and beside it the nameplates on the party's top line with the raid frames under them. The breath bar
-- (added after) sits in the gap between the pet and the Personal Resource Display, level with the display's bars.
local EXAMPLES = {
    -- 490 wide rather than 480, so the outlines round the player and the target are 20 px apart, as on the mockup.
    frames = { make = function(p) return ns.Preview.Create(p) end, x = 21, y = 38, width = 490 },
    focus = { make = function(p) return ns.Preview.CreateSingle(p, "focus") end, x = 617, y = 38, scale = 0.8 },
    pet = { make = function(p) return ns.Preview.CreateSingle(p, "pet") end, x = 21, y = 169, scale = 0.6 },
    tot = { make = function(p) return ns.Preview.CreateSingle(p, "tot") end, x = 664, y = 169, scale = 0.6 },
    prd = { make = function(p) return ns.Preview.CreatePRD(p) end, x = 357, y = 186 },
    party = { make = function(p) return ns.Preview.CreateParty(p, "party", true) end, x = 21, y = 270 },
    plates = { make = function(p) return ns.Preview.CreatePlates(p) end, x = 242, y = 270 },
    raid = { make = function(p) return ns.Preview.CreateRaid(p) end, x = 233, y = 406 },
    breath = { make = function(p) return ns.Preview.CreateBreath(p) end, x = 184, y = 186, scale = 0.75 },
}
-- Which example a frame is edited on, and each example's frames' place on the screen.
local EXAMPLE_OF = { player = "frames", target = "frames", focus = "focus", pet = "pet", tot = "tot", party = "party",
                     plates = "plates", prd = "prd", raid = "raid", breath = "breath" }
local SCREEN = { "player", "target", "tot", "pet", "focus", "party", "plates", "prd", "raid", "breath" }

local function Example(key)
    local e = ui.examples[key]
    if not e then
        local spec = EXAMPLES[key]
        e = spec.make(ui.stage)
        if spec.scale then e:SetScale(spec.scale) end
        if spec.width then e:SetWidth(spec.width) end
        local s = spec.scale or 1
        e:SetPoint("TOPLEFT", ui.stage, "TOPLEFT", spec.x / s, -spec.y / s)
        if e.SetScene and ui.scene then e:SetScene(ui.scene) end
        ui.examples[key] = e
    end
    return e
end

-- The frame a spot on the screen covers.
local function Region(id)
    if id == "player" or id == "target" then
        local e = ui.examples.frames
        return e and (id == "player" and e.player or e.target)
    end
    return ui.examples[EXAMPLE_OF[id]]
end

-- A spot on the screen to click: outlined in gold while edited, dimmed while its liquid is off, with its name above.
local function Hotspot(id)
    local h = CreateFrame("Button", nil, ui.stage)
    h:SetFrameLevel(ui.stage:GetFrameLevel() + 40)
    h.dim = h:CreateTexture(nil, "BACKGROUND")
    h.dim:SetAllPoints()
    h.dim:SetColorTexture(0, 0, 0, 0.55)
    local hl = h:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.82, 0, 0.07)
    -- Solid gold while edited; the others dashed (as in the mockup), faint, to show they can be clicked.
    h.edges = Outline(h, GOLD)
    h.dashes = {}
    h.tag = h:CreateTexture(nil, "ARTWORK")
    h.tag:SetColorTexture(0.05, 0.05, 0.07, 0.6)
    h.name = Font(h, "GameFontNormalSmall", "", "LEFT")
    h.name:SetPoint("BOTTOMLEFT", h, "TOPLEFT", 6, 3)
    h.tag:SetPoint("BOTTOMLEFT", h, "TOPLEFT", 0, 0)
    h.tag:SetHeight(16)
    h:SetScript("OnClick", function() Editor.Show(id) end)
    h.id = id
    return h
end

-- A dashed outline round a frame of w x h: dashes of solid colour along each edge.
local DASH, GAP = 6, 4
local function Dash(h, w, height)
    local function Piece(x, y, dw, dh)
        local t = h:CreateTexture(nil, "BORDER")
        t:SetColorTexture(0.78, 0.60, 0.29, 0.45)
        t:SetPoint("TOPLEFT", x, -y)
        t:SetSize(dw, dh)
        h.dashes[#h.dashes + 1] = t
    end
    for x = 0, w - 1, DASH + GAP do
        Piece(x, 0, math.min(DASH, w - x), 1)
        Piece(x, height - 1, math.min(DASH, w - x), 1)
    end
    for y = 0, height - 1, DASH + GAP do
        Piece(0, y, 1, math.min(DASH, height - y))
        Piece(w - 1, y, 1, math.min(DASH, height - y))
    end
end

local function PlaceHotspots()
    for _, id in ipairs(SCREEN) do
        local h, r = ui.hots[id], Region(id)
        if r then
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", r, "TOPLEFT", -4, 4)
            h:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 4, -4)
            h:Show()
            if not h.dashes[1] then
                -- Its size on the screen: the frame's at its example's scale, and the margin.
                local scale = EXAMPLES[EXAMPLE_OF[id]].scale or 1
                Dash(h, math.floor(r:GetWidth() * scale + 8), math.floor(r:GetHeight() * scale + 8))
            end
        else
            h:Hide()
        end
    end
end

--------------------------------------------------------------------------------
-- Showing and refreshing
--------------------------------------------------------------------------------

-- Places the inspector's rows, the open card's drawer in it, and sizes the scrolled list.
function Layout()
    local page = ui.pages[current]
    if not page then return end
    local y = 0
    for _, item in ipairs(page.items) do
        local shown = true
        if item == page.mob then shown = ns.Core[FRAMES[current].mobs]() end
        if item.row and item.row.shown then shown = item.row.shown() and true or false end
        if shown then
            local height = item.height
            if item.bar then
                local open = page.open == item.bar and Get(item.bar.on)
                item.drawer:SetShown(open and true or false)
                height = 44
                if open then
                    local pane = page.pane == "effects" and item.effects or item.colour
                    item.colour:SetShown(pane == item.colour)
                    item.effects:SetShown(pane == item.effects)
                    height = 44 + 32 + pane.height + 4
                    item.drawer:SetHeight(height - 44)
                end
            end
            item:ClearAllPoints()
            item:SetPoint("TOPLEFT", 0, -y)
            item:SetPoint("TOPRIGHT", 0, -y)
            item:SetHeight(height)
            item:Show()
            y = y + height + 6
        else
            item:Hide()
        end
    end
    page:SetHeight(math.max(1, y))
    ui.list:SetHeight(math.max(1, y))
end

-- What a bar's card says it shows: its colour and its effects.
local function Summary(bar, f)
    if not Get(bar.on) then return "Off: the game's own bar" end
    local own = ns.Core.db.effects and ns.Core.db.effects[bar.on]
    local fx = "global effects"
    if own then
        local off = {}
        for _, effect in ipairs(ns.Core.EFFECTS) do
            if not ns.Core.Effect(bar.on, effect) then off[#off + 1] = "no " .. EFFECT_LABELS[effect]:lower() end
        end
        fx = "own effects" .. (#off > 0 and (": " .. table.concat(off, ", ")) or "")
    end
    return ChoiceName(Get(bar.color), bar, f) .. " · " .. fx
end

local function RefreshCards(page, f)
    for _, c in ipairs(page.cards) do
        local bar = c.bar
        local on = Get(bar.on) and true or false
        local open = on and page.open == bar
        c.check:SetChecked(on)
        c.summary:SetText(Summary(bar, f))
        Paint(c.swatch, ns.Core.ColorChoice(bar.frame, bar.kind) or "game", bar.frame, bar.kind)
        c.swatch:SetAlpha(on and 1 or 0.3)
        Recolor(c.edges, open and GOLD or EDGE)
        for name, t in pairs(c.tabs) do t:SetPicked(name == page.pane) end
        -- Colour.
        local p = c.colour
        local choice = Get(bar.color)
        p.following = choice == "same"
        if p.follow then p.follow:SetChecked(p.following) end
        p.tileFrame:SetAlpha(p.following and 0.3 or 1)
        for key, t in pairs(p.tiles) do
            local picked = not p.following and choice == key
            t.picked = picked
            Recolor(t.edges, picked and GOLD or { 0, 0, 0 })
        end
        p.picked = p.following and ("Following: " .. ChoiceName(ns.Core.SameChoice(bar.frame, bar.kind) or "game", bar, f))
            or ChoiceName(choice, bar, f)
        if not ui.trying then
            p.trying:SetText(p.picked)
            Muted(p.trying)
        end
        -- Effects.
        local e = c.effects
        local own = ns.Core.db.effects and ns.Core.db.effects[bar.on] ~= nil
        e.global:SetChecked(not own)
        for effect, box in pairs(e.fx) do
            box:SetChecked(ns.Core.Effect(bar.on, effect) and true or false)
            box:SetEnabled(own)
            box.label:SetAlpha(own and 1 or 0.45)
        end
    end
end

function Refresh()
    if not (frame and frame:IsShown()) then return end
    -- The tabs, and the screen: who is edited, who is off.
    for id, t in pairs(ui.tabs) do t:SetPicked(id == tab) end
    for _, id in ipairs(SCREEN) do
        local h = ui.hots[id]
        local edited = tab == "frames" and current == id
        for _, t in ipairs(h.edges) do t:SetShown(edited) end
        for _, t in ipairs(h.dashes) do t:SetShown(not edited) end
        h.name:SetText(FRAMES[id].label)
        if edited then h.name:SetTextColor(GOLD[1], GOLD[2], GOLD[3]) else h.name:SetTextColor(1, 1, 1) end
        h.tag:SetWidth(h.name:GetStringWidth() + 12)
        h.off = not FrameOn(FRAMES[id])
        h.dim:SetShown(h.off)
    end

    local page = ui.pages[current]
    local f = FRAMES[current] or TAB_BY_ID[current]
    if page.cards then RefreshCards(page, f) end
    -- The breath and fatigue example shows the bar whose card is open.
    if current == "breath" and page.open and ui.examples.breath then ui.examples.breath:SetKind(page.open.kind) end
    if page.mob then
        for key, chip in pairs(page.mob.chips) do chip:SetPicked(Get("mobClassColor") == key) end
    end
    for key, r in pairs(page.rows) do r.check:SetChecked(Get(key) and true or false) end
    Layout()
end
Editor.Refresh = function() Refresh() end

-- Which examples play at full speed: the one being edited, or the frames' for the other tabs.
local function Activate(key)
    for k, e in pairs(ui.examples) do ns.Preview.SetActive(e, k == key) end
end

-- Edits a frame ("player", "party"...) or opens a tab ("effects", "combat", "addons").
function Editor.Show(id)
    id = ALIASES[id] or id
    if not FRAMES[id] and not (TAB_BY_ID[id] and id ~= "frames") then id = "player" end
    ns.Core.Try(nil)
    ui.trying = nil
    current = id
    tab = FRAMES[id] and "frames" or id
    if FRAMES[id] then ui.lastFrame = id end
    Activate(FRAMES[id] and EXAMPLE_OF[id] or "frames")
    if not ui.pages[id] then ui.pages[id] = BuildPage(id) end
    for k, page in pairs(ui.pages) do page:SetShown(k == id) end
    local f = FRAMES[id] or TAB_BY_ID[id]
    ui.kicker:SetText(FRAMES[id] and "EDITING" or "")
    ui.title:SetText(f.label)
    ui.desc:SetText(f.desc or "")
    ui.scroll:SetVerticalScroll(0)
    Refresh()
end

-- The shown frame's or tab's settings back to their defaults; a frame's bars follow the global effects again.
local function Defaults()
    local defaults = ns.Core.Defaults()
    local f = FRAMES[current] or TAB_BY_ID[current]
    for _, key in ipairs(Keys(f)) do
        if Get(key) ~= defaults[key] then ns.Core.SetSetting(key, defaults[key]) end
    end
    for _, bar in ipairs(f.bars or {}) do ns.Core.ClearEffects(bar.on) end
    Refresh()
end

-- Plays a scene on every example that has scenes.
local function PlayScene(name)
    ui.scene = name
    for _, e in pairs(ui.examples) do
        if e.SetScene then e:SetScene(name) end
    end
    for n, chip in pairs(ui.scenes) do chip:SetPicked(n == name) end
end

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------

-- The game's own window, as the setup's (Wizard.lua): metal border, dark background, gold title.
local function Window()
    local ok, f = pcall(CreateFrame, "Frame", "SmoothAnimatedBarsEditor", UIParent, "ButtonFrameTemplate")
    if not ok then
        f = CreateFrame("Frame", "SmoothAnimatedBarsEditor", UIParent)
        Shade(f, 0.96):SetColorTexture(0.06, 0.06, 0.08, 0.96)
        Outline(f, EDGE)
        local close = Button(f, "Close", 80, function() f:Hide() end)
        close:SetPoint("TOPRIGHT", -8, -8)
        return f
    end
    if ButtonFrameTemplate_HidePortrait then ButtonFrameTemplate_HidePortrait(f) end
    if ButtonFrameTemplate_HideButtonBar then ButtonFrameTemplate_HideButtonBar(f) end
    if f.Inset then f.Inset:Hide() end
    if f.Bg then
        f.Bg:SetPoint("TOPLEFT", 6, -21)
        if f.TopTileStreaks then f.TopTileStreaks:SetPoint("TOPLEFT", 6, -21) end
    end
    return f
end

local function Build()
    frame = Window()
    frame:SetSize(W, H)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()
    -- Escape closes it like the game's windows; a colour being tried goes with it.
    table.insert(UISpecialFrames, "SmoothAnimatedBarsEditor")
    frame:SetScript("OnHide", function() ns.Core.Try(nil) end)
    frame:SetScript("OnShow", function() ns.Bars.WakePreviews() end)
    if frame.SetTitle then
        frame:SetTitle("Smooth Animated Bars")
    elseif frame.TitleText then
        frame.TitleText:SetText("Smooth Animated Bars")
    end
    ui = { tabs = {}, pages = {}, examples = {}, hots = {}, scenes = {}, scene = "fight" }

    -- The tabs along the top, with the setup and the changelog on the right.
    local x = 14
    for _, t in ipairs(TABS) do
        local chip = Tab(frame, 104, t.label, function()
            if t.id == "frames" then
                Editor.Show(FRAMES[current] and current or ui.lastFrame or "player")
            else
                Editor.Show(t.id)
            end
        end)
        chip:SetPoint("TOPLEFT", x, -28)
        ui.tabs[t.id] = chip
        x = x + 108
    end
    ui.whatsNew = Button(frame, "What's New", 100, function() ns.WhatsNew.Open() end)
    ui.whatsNew:SetPoint("TOPRIGHT", -14, -31)
    ui.setup = Button(frame, "Run Setup", 100, function()
        frame:Hide()
        ns.Wizard.Open()
    end)
    ui.setup:SetPoint("RIGHT", ui.whatsNew, "LEFT", -6, 0)

    -- The screen, its frames, and the scenes under it.
    ui.stage = CreateFrame("Frame", nil, frame)
    ui.stage:SetPoint("TOPLEFT", 12, -62)
    ui.stage:SetPoint("BOTTOMLEFT", 12, 50)
    ui.stage:SetWidth(STAGE_W)
    ui.stage:SetClipsChildren(true)
    -- A dusky blue backdrop, lighter toward the top, as behind the frames in game.
    local backdrop = ui.stage:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAllPoints()
    backdrop:SetColorTexture(1, 1, 1, 1)
    if CreateColor and backdrop.SetGradient then
        backdrop:SetGradient("VERTICAL", CreateColor(0.06, 0.07, 0.10, 1), CreateColor(0.16, 0.19, 0.26, 1))
    else
        backdrop:SetColorTexture(0.10, 0.12, 0.16, 1)
    end
    Outline(ui.stage, EDGE)
    Muted(Font(ui.stage, "GameFontHighlightSmall", "Click a frame to change it.", "RIGHT")):SetPoint("TOPRIGHT", -8, -6)
    for key in pairs(EXAMPLES) do Example(key) end
    for _, id in ipairs(SCREEN) do ui.hots[id] = Hotspot(id) end
    PlaceHotspots()

    local play = Muted(Font(frame, "GameFontNormalSmall", "PLAY", "LEFT"))
    play:SetPoint("BOTTOMLEFT", 16, 24)
    local last
    for _, name in ipairs(ns.Preview.SCENES) do
        local chip = Tab(frame, 90, SCENE_LABELS[name] or name, function() PlayScene(name) end)
        if last then chip:SetPoint("LEFT", last, "RIGHT", 4, 0) else chip:SetPoint("LEFT", play, "RIGHT", 10, 0) end
        ui.scenes[name] = chip
        last = chip
    end
    Muted(Font(frame, "GameFontHighlightSmall", "on every frame at once", "LEFT")):SetPoint("LEFT", last, "RIGHT", 10, 0)
    ui.scenes.fight:SetPicked(true)

    -- The inspector.
    local side = CreateFrame("Frame", nil, frame)
    side:SetPoint("TOPRIGHT", -12, -62)
    side:SetPoint("BOTTOMRIGHT", -12, 50)
    side:SetWidth(INSPECT_W)
    Shade(side, 0.45)
    Outline(side, EDGE)
    ui.kicker = Muted(Font(side, "GameFontNormalSmall", "", "LEFT"))
    ui.kicker:SetPoint("TOPLEFT", 10, -10)
    ui.title = Font(side, "GameFontNormalLarge", "", "LEFT")
    ui.title:SetPoint("TOPLEFT", 10, -24)
    ui.desc = Muted(Font(side, "GameFontHighlightSmall", "", "LEFT"))
    ui.desc:SetPoint("TOPLEFT", ui.title, "BOTTOMLEFT", 0, -5)
    ui.desc:SetWidth(INSPECT_W - 20)
    ui.desc:SetWordWrap(true)
    ui.scroll = CreateFrame("ScrollFrame", nil, side)
    ui.scroll:SetPoint("TOPLEFT", ui.desc, "BOTTOMLEFT", 0, -10)
    ui.scroll:SetPoint("BOTTOMRIGHT", -24, 8)
    ui.list = CreateFrame("Frame", nil, ui.scroll)
    ui.list:SetSize(LIST_W, 1)
    ui.scroll:SetScrollChild(ui.list)
    if ScrollUtil and ScrollUtil.InitScrollFrameWithScrollBar then
        local bar = CreateFrame("EventFrame", nil, side, "MinimalScrollBar")
        ScrollUtil.InitScrollFrameWithScrollBar(ui.scroll, bar)
        bar:SetPoint("TOPLEFT", ui.scroll, "TOPRIGHT", 6, -2)
        bar:SetPoint("BOTTOMLEFT", ui.scroll, "BOTTOMRIGHT", 6, 2)
    else
        ui.scroll:EnableMouseWheel(true)
        ui.scroll:SetScript("OnMouseWheel", function(self, delta)
            local offset = self:GetVerticalScroll() - delta * 40
            self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), offset)))
        end)
    end

    ui.close = Button(frame, "Close", 100, function() frame:Hide() end)
    ui.close:SetPoint("BOTTOMRIGHT", -14, 16)
    ui.defaults = Button(frame, "Defaults", 100, Defaults)
    ui.defaults:SetPoint("RIGHT", ui.close, "LEFT", -8, 0)
end

-- Opens the editor at a frame ("player", "party"...) or a tab ("effects", "combat", "addons"), else where it was left.
-- Nothing in it is protected, so it opens in combat too.
function Editor.Open(section)
    if not frame then Build() end
    local scale = math.min(1, (UIParent:GetHeight() - 40) / H, (UIParent:GetWidth() - 40) / W)
    frame:SetScale(scale)
    frame:Show()
    Editor.Show(section or current or "player")
    return true
end

function Editor.Close()
    if frame then frame:Hide() end
end

-- For the tests: the window, its controls and what is shown; every setting the editor has a control for; the frames
-- and tabs it can show.
function Editor.State()
    return { frame = frame, ui = ui, section = current, tab = tab }
end

function Editor.Keys()
    local keys, seen = {}, {}
    local function Add(f)
        for _, key in ipairs(Keys(f)) do
            if not seen[key] then
                seen[key] = true
                keys[#keys + 1] = key
            end
        end
    end
    for _, f in pairs(FRAMES) do Add(f) end
    for _, t in ipairs(TABS) do Add(t) end
    return keys
end

function Editor.Sections()
    local ids = {}
    for _, id in ipairs({ "player", "target", "focus", "pet", "tot", "party", "raid", "prd", "plates", "breath" }) do
        ids[#ids + 1] = id
    end
    for _, t in ipairs(TABS) do
        if t.id ~= "frames" then ids[#ids + 1] = t.id end
    end
    return ids
end
