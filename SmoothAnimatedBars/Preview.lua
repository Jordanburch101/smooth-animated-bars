-- Preview player and target frames for the setup wizard: Forever's own unit frame art, rebuilt from
-- the atlases and layout of its PlayerFrame and TargetFrame (Blizzard_UnitFrame, Camelot overrides on
-- the Mainline XML), with bars of ours carrying the liquid. Their values are ours, so they play a short
-- loop of hits, heals and power changes, and the liquid follows the same settings as the real bars.
--
-- The layout and the pieces are shared with Capture.lua, which photographs the art for the gallery;
-- tools/harness/gallery.py repeats the numbers in LAYOUT.
--
-- Atlases are fetched by name, which Forever loads; game files by path are not used. If an atlas is
-- missing the piece is left out (a missing bar mask leaves the liquid uncut rather than hidden).

local _, ns = ...

local Preview = {}
ns.Preview = Preview

local QUESTION_MARK = 134400 -- INV_Misc_QuestionMark, the target's stand-in portrait

-- Forever's frames, 232 x 100, in frame units from the top-left (y down is negative).
-- Target: the health bar sits 3 above its container, which ends at the frame's left middle + (147, -9);
-- the mana bar hangs below the container's right end (+4, -1).
local LAYOUT = {
    player = {
        art = "UI-HUD-UnitFrame-Player-PortraitOn",
        portrait = { point = "TOPLEFT", x = 24, y = -19, size = 60, mask = "UI-HUD-UnitFrame-Player-Portrait-Mask" },
        circle = { point = "BOTTOMLEFT", x = 13, y = 7 },
        name = { point = "CENTER", x = 149, y = -37, w = 116 },
        health = { x = 87, y = -43, w = 124, h = 20, fillAtlas = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health",
                   maskAtlas = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health-Mask", maskX = -2, maskY = 6, maskH = 32 },
        power = { x = 87, y = -61, w = 124, h = 10,
                  maskAtlas = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Mana-Mask", maskX = -2, maskY = 2, maskW = 128 },
    },
    target = {
        art = "UI-HUD-UnitFrame-Target-PortraitOn",
        portrait = { point = "TOPRIGHT", x = -26, y = -19, size = 58, mask = "CircleMask" },
        circle = { point = "BOTTOMRIGHT", x = -13, y = 7 },
        banner = { atlas = "UI-HUD-UnitFrame-Target-PortraitOn-Type", x = -82, y = -26, color = { 0.8, 0.1, 0.1 } },
        name = { point = "TOPRIGHT", x = -91, y = -30, w = 117 },
        health = { x = 21, y = -41, w = 126, h = 20, fillAtlas = "UI-HUD-UnitFrame-Target-PortraitOn-Bar-Health",
                   maskAtlas = "UI-HUD-UnitFrame-Target-PortraitOn-Bar-Health-Mask", maskX = -1, maskY = 6 },
        power = { x = 17, y = -60, w = 134, h = 10, fillAtlas = "UI-HUD-UnitFrame-Target-PortraitOn-Bar-Mana",
                  maskAtlas = "UI-HUD-UnitFrame-Target-PortraitOn-Bar-Mana-Mask", maskX = -61, maskY = 3 },
    },
}
Preview.LAYOUT = LAYOUT

-- Values as fractions of the bar, looped: { seconds, player health, player power, target health,
-- target power }. A new target arrives at full health at the end of each loop.
local SCRIPT = {
    { 0.0, 1.00, 0.10, 1.00, 0.90 },
    { 1.2, 0.72, 0.30, 0.80, 0.90 },
    { 2.2, 0.72, 0.30, 0.55, 0.75 },
    { 3.0, 0.48, 0.55, 0.55, 0.75 },
    { 4.0, 0.48, 0.25, 0.25, 0.60 },
    { 5.0, 0.85, 0.25, 0.25, 0.60 },
    { 6.0, 0.85, 0.50, 0.00, 0.60 },
    { 7.2, 1.00, 0.10, 1.00, 0.90 },
}
local LOOP = 8.4
-- The target's DoTs at each row of SCRIPT, in points of its 210 health: { name, damage still to deal, school }
-- (Shadow 32, Fire 4). By the fifth row they will finish it, and the skull shows.
local DOTS = {
    {},
    { { "Corruption", 54, 32 } },
    { { "Corruption", 48, 32 }, { "Immolate", 40, 4 } },
    { { "Corruption", 42, 32 }, { "Immolate", 34, 4 } },
    { { "Corruption", 30, 32 }, { "Immolate", 28, 4 } },
    { { "Corruption", 30, 32 }, { "Immolate", 28, 4 } },
    {},
    {},
}

-- Scenes the frames can play instead (the editor's buttons): the fight above, the player taking a beating, being healed
-- back up, and spending power and getting it back. Each is rows as SCRIPT's, looped, with the DoTs only in the fight.
local SCENES = {
    fight = { rows = SCRIPT, dots = DOTS, loop = LOOP },
    damage = { loop = 6.0, rows = {
        { 0.0, 1.00, 0.60, 1.00, 0.90 },
        { 0.8, 0.82, 0.60, 1.00, 0.90 },
        { 1.6, 0.64, 0.60, 1.00, 0.90 },
        { 2.4, 0.47, 0.60, 1.00, 0.90 },
        { 3.2, 0.30, 0.60, 1.00, 0.90 },
        { 4.0, 0.15, 0.60, 1.00, 0.90 },
    } },
    -- A Renew (Holy, school 2) ticking the health back up, then a bandage (Nature-green) joining it, each shown ahead
    -- of the health by the heal marker while the heals setting is on: { school, health still to come of the 271 }.
    heal = { loop = 7.6, rows = {
        { 0.0, 0.30, 0.60, 1.00, 0.90 },
        { 0.6, 0.30, 0.60, 1.00, 0.90 },
        { 1.6, 0.42, 0.60, 1.00, 0.90 },
        { 2.6, 0.54, 0.60, 1.00, 0.90 },
        { 3.6, 0.66, 0.60, 1.00, 0.90 },
        { 4.6, 0.78, 0.60, 1.00, 0.90 },
        { 5.6, 0.90, 0.60, 1.00, 0.90 },
        { 6.6, 1.00, 0.60, 1.00, 0.90 },
    }, heals = {
        {},
        { { 2, 150 } },
        { { 2, 118 } },
        { { 2, 86 } },
        { { 2, 54 }, { "bandage", 60 } },
        { { 2, 22 }, { "bandage", 40 } },
        { { "bandage", 20 } },
        {},
    } },
    power = { loop = 6.4, rows = {
        { 0.0, 1.00, 1.00, 1.00, 1.00 },
        { 0.8, 1.00, 0.72, 1.00, 0.80 },
        { 1.6, 1.00, 0.45, 1.00, 0.60 },
        { 2.4, 1.00, 0.18, 1.00, 0.40 },
        { 3.4, 1.00, 0.40, 1.00, 0.55 },
        { 4.2, 1.00, 0.70, 1.00, 0.75 },
        { 5.0, 1.00, 1.00, 1.00, 1.00 },
    } },
}
Preview.SCENES = { "fight", "damage", "heal", "power" }

-- What each side of the frames can stand for: the frame whose settings its bars follow, its unit, and its name.
local SIDES = {
    player = { unit = "player" },
    prd    = { unit = "player", frame = "prd", name = "Personal Resource" },
    target = { unit = "target", name = "Your Target" },
    focus  = { unit = "focus", frame = "focus", name = "Your Focus" },
    pet    = { unit = "pet", frame = "pet", name = "Your Pet" },
    tot    = { unit = "targettarget", frame = "tot", name = "Target of Target" },
}

local function Atlas(tex, name, useSize)
    return tex.SetAtlas and tex:SetAtlas(name, useSize) and true or false
end

local function PowerInfo(unit)
    local index, token = UnitPowerType(unit)
    if (issecretvalue and (issecretvalue(index) or issecretvalue(token))) or not token then token = "MANA" end
    local info = PowerBarColor and PowerBarColor[token]
    return token, token == "MANA" and 350 or 100, info
end

--------------------------------------------------------------------------------
-- Pieces, each placed on a 232 x 100 frame f (shared with Capture.lua)
--------------------------------------------------------------------------------

function Preview.Portrait(f, which)
    local p = LAYOUT[which].portrait
    local portrait = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    portrait:SetSize(p.size, p.size)
    portrait:SetPoint(p.point, p.x, p.y)
    if which == "target" then
        portrait:SetTexture(QUESTION_MARK)
    elseif SetPortraitTexture then
        SetPortraitTexture(portrait, "player")
    end
    local mask = f:CreateMaskTexture()
    if Atlas(mask, p.mask) then
        if which == "target" then
            mask:SetPoint("TOPLEFT", portrait, "TOPLEFT", 0, -1)
            mask:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", -1, 0)
        else
            mask:SetAllPoints(portrait)
        end
        portrait:AddMaskTexture(mask)
    end
    return portrait
end

function Preview.Art(f, which)
    local art = f:CreateTexture(nil, "BACKGROUND", nil, 2)
    Atlas(art, LAYOUT[which].art, true)
    art:SetPoint("CENTER")
    return art
end

-- The target's name banner, tinted as for a hostile target.
function Preview.Banner(f)
    local b = LAYOUT.target.banner
    local banner = f:CreateTexture(nil, "BACKGROUND", nil, 3)
    if Atlas(banner, b.atlas, true) then
        banner:SetPoint("TOPRIGHT", b.x, b.y)
        banner:SetVertexColor(b.color[1], b.color[2], b.color[3])
    end
    return banner
end

function Preview.Circle(f, which)
    local c = LAYOUT[which].circle
    local circle = f:CreateTexture(nil, "OVERLAY")
    Atlas(circle, "UI-HUD-UnitFrame-SmallCircle", true)
    circle:SetPoint(c.point, c.x, c.y)
    return circle
end

-- A bar's mask, placed as the game places it, relative to rel's top-left at (x, y). False when the
-- client has no such atlas.
function Preview.PlaceMask(mask, spec, rel, x, y)
    if not Atlas(mask, spec.maskAtlas, true) then return false end
    mask:SetPoint("TOPLEFT", rel, "TOPLEFT", x + spec.maskX, y + spec.maskY)
    if spec.maskW then mask:SetWidth(spec.maskW) end
    if spec.maskH then mask:SetHeight(spec.maskH) end
    return true
end

--------------------------------------------------------------------------------
-- The preview frames
--------------------------------------------------------------------------------

-- A bar like the game's: its own fill (shown while the liquid is off), shaped by the game's mask
-- atlas, with its text above everything on top.
local function Bar(f, top, spec, setup)
    local bar = CreateFrame("StatusBar", nil, f)
    bar:SetSize(spec.w, spec.h)
    bar:SetPoint("TOPLEFT", spec.x, spec.y)
    local fill = bar:CreateTexture(nil, "ARTWORK")
    local fillAtlas = setup.fillAtlas or spec.fillAtlas
    if not (fillAtlas and Atlas(fill, fillAtlas)) then
        local c = setup.color or { 0, 1, 0 }
        fill:SetColorTexture(c[1], c[2], c[3], 1)
    end
    bar:SetStatusBarTexture(fill)
    bar:SetMinMaxValues(0, setup.max)
    bar:SetValue(setup.max)

    local mask = bar:CreateMaskTexture()
    if Preview.PlaceMask(mask, spec, bar, 0, 0) then
        fill:AddMaskTexture(mask)
        bar[setup.kind == "health" and "HealthBarMask" or "ManaBarMask"] = mask
    end

    bar.text = top:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
    bar.text:SetPoint("CENTER", bar, "CENTER", 0, 0)
    bar.max = setup.max
    bar.state = ns.Bars.Preview(bar, { key = setup.key, unit = setup.unit, kind = setup.kind, token = setup.token,
                                       frame = setup.frame, class = setup.class })
    return bar
end

-- Whether an example bar's whole frame has the liquid off (its health and power settings, "playerHealth" and
-- "playerPower", or a friendly nameplate's one): such a frame rests, full and still, instead of playing the scene.
local function Resting(bar)
    local key = bar.state and bar.state.spot and bar.state.spot.key
    if type(key) ~= "string" then return false end
    local frame = key:match("^(.-)Health$") or key:match("^(.-)Power$")
    if not frame then return not ns.Core.Get(key) end
    return not ns.Core.Get(frame .. "Health") and not ns.Core.Get(frame .. "Power")
end
Preview.Resting = Resting

local function SetFraction(bar, frac)
    if Resting(bar) then frac = 1 end
    local value = math.floor(frac * bar.max + 0.5)
    if value == bar.shownValue then return end
    bar.shownValue = value
    bar:SetValue(value)
    bar.text:SetText(value .. " / " .. bar.max)
    ns.Bars.Stir(bar.state)
end

-- The row of a scene t seconds into it, looped.
local function RowAt(scene, t)
    local at, found = t % scene.loop, scene.rows[1]
    for _, row in ipairs(scene.rows) do
        if row[1] <= at then found = row end
    end
    return found
end

-- A group's member i (party, raid, nameplates) in one of the frames' scenes, each a little behind the one before.
local function GroupRow(name, t, i)
    return RowAt(SCENES[name], t - i * 0.35)
end

-- The editor shows every example at once, and only the one being edited plays at full speed: the others' clocks run
-- at SLOW and their liquids idle at a lower rate (Bars.lua, spot.calm). holder.bars: the example's bars.
local SLOW = 0.35
function Preview.SetActive(holder, on)
    holder.speed = on and 1 or SLOW
    for _, bar in ipairs(holder.bars or {}) do
        if bar.state then bar.state.spot.calm = (not on) or nil end
    end
end

-- The frame: art at the bottom, then the bars and their liquid, then the text, the level circle and
-- the name above them, as the game layers them. as: which frame's settings its bars follow (SIDES), which by default.
local function Frame(parent, which, as)
    local L = LAYOUT[which]
    local side = SIDES[as or which]
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(232, 100)
    local top = CreateFrame("Frame", nil, f)
    top:SetAllPoints()
    top:SetFrameLevel(f:GetFrameLevel() + 10)

    f.portrait = Preview.Portrait(f, which)
    Preview.Art(f, which)
    if which == "target" then Preview.Banner(f) end

    local name = top:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    name:SetJustifyH("CENTER")
    name:SetSize(L.name.w, 12)
    if which == "target" then
        name:SetPoint(L.name.point, L.name.x, L.name.y)
    else
        name:SetPoint(L.name.point, f, "TOPLEFT", L.name.x, L.name.y)
    end
    if side.name then
        name:SetText(side.name)
    else
        -- The game's own name text, surname included on Forever.
        local shown = PlayerName and PlayerName.GetText and PlayerName:GetText()
        name:SetText(shown or (UnitName("player")))
    end

    local circle = Preview.Circle(top, which)
    local level = top:CreateFontString(nil, "OVERLAY", "WhiteLargeNumberFont")
    level:SetPoint("CENTER", circle, "CENTER", 0, -0.5)
    level:SetText(UnitLevel("player"))

    local token, powerMax, info
    if which == "target" then
        token, powerMax, info = "MANA", 350, PowerBarColor and PowerBarColor.MANA
    else
        token, powerMax, info = PowerInfo("player")
    end
    local key = as or which
    f.health = Bar(f, top, L.health, { key = key .. "Health", unit = side.unit, kind = "health", frame = side.frame,
        max = which == "target" and 210 or 271 })
    f.power = Bar(f, top, L.power, { key = key .. "Power", unit = side.unit, kind = "power", token = token,
        frame = side.frame, max = powerMax, color = info and { info.r, info.g, info.b } or { 0, 0, 1 },
        fillAtlas = which == "player" and info and info.atlas or nil })
    return f
end

-- Both frames side by side, playing a scene (the fight by default) while shown. sides: what each stands for, { left =
-- "player" or "prd", right = "target", "focus", "pet" or "tot" }, the player and the target by default.
function Preview.Create(parent, sides)
    sides = sides or {}
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(480, 100)
    local player, target = Frame(holder, "player", sides.left), Frame(holder, "target", sides.right)
    player:SetPoint("LEFT")
    target:SetPoint("RIGHT")

    -- The DoT marker on the target, shown while the dots setting is on.
    local dots = {}
    local marker = ns.Marker.Preview({
        bar = target.health, mask = target.health.HealthBarMask, iconHost = target, portrait = target.portrait,
        visible = function() return true end,
        source = function()
            local list, total = {}, 0
            for i, dot in ipairs(dots) do
                list[i] = { name = dot[1], damage = dot[2], school = dot[3] }
                total = total + dot[2]
            end
            return target.health.max, target.health.shownValue, total, list
        end,
    })

    -- The heal marker on the player's health, shown in the heal scene while the heals setting is on.
    local heals = {}
    local healer = ns.HealMarker.Preview(player.health, function()
        local list, total = {}, 0
        for i, heal in ipairs(heals) do
            list[i] = { school = heal[1], heal = heal[2] }
            total = total + heal[2]
        end
        return total, list
    end)

    local t, step, scene = 0, 0, SCENES.fight
    local function Play(i)
        local row = scene.rows[i]
        SetFraction(player.health, row[2])
        SetFraction(player.power, row[3])
        SetFraction(target.health, row[4])
        SetFraction(target.power, row[5])
        local now = scene.dots and scene.dots[i] or {}
        local landed = #now > #dots
        dots = now
        if landed then ns.Marker.Landed(marker) end
        local coming = scene.heals and scene.heals[i] or {}
        local applied = #coming > #heals
        heals = coming
        if applied and healer then ns.HealMarker.Landed(healer) end
    end
    Play(1)
    holder:SetScript("OnUpdate", function(_, elapsed)
        t = t + elapsed * (holder.speed or 1)
        if t >= scene.loop then t, step = t - scene.loop, 0 end
        while scene.rows[step + 1] and scene.rows[step + 1][1] <= t do
            step = step + 1
            Play(step)
        end
    end)
    -- Play another scene (Preview.SCENES) from its start.
    function holder.SetScene(_, name)
        if not SCENES[name] then return end
        scene, t, step = SCENES[name], 0, 1
        holder.scene = name
        Play(1)
    end
    holder.scene = "fight"
    holder.player, holder.target, holder.marker, holder.healer = player, target, marker, healer
    holder.bars = { player.health, player.power, target.health, target.power }
    return holder
end

-- One frame alone, in the target frame's art, standing for the focus, pet or target of target (SIDES), playing the
-- target's side of the frames' scenes while shown (the editor's screen, where each has a place of its own).
function Preview.CreateSingle(parent, as)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(232, 100)
    local f = Frame(holder, "target", as)
    f:SetPoint("TOPLEFT")
    local t = 0
    holder.scene = "fight"
    holder:SetScript("OnUpdate", function(_, elapsed)
        t = t + elapsed * (holder.speed or 1)
        local row = RowAt(SCENES[holder.scene], t)
        SetFraction(f.health, row[4])
        SetFraction(f.power, row[5])
    end)
    function holder.SetScene(_, name)
        if not SCENES[name] then return end
        holder.scene, t = name, 0
    end
    holder.target, holder.bars = f, { f.health, f.power }
    return holder
end

--------------------------------------------------------------------------------
-- The preview party (the setup's party step)
--------------------------------------------------------------------------------
-- Forever's party member frame (Mainline PartyFrameTemplates.xml, with Camelot's PartyMemberFrame.lua for the bars),
-- 120 x 53: its art at (1, -2), the portrait 37 across at (7, -6) in a circle, the name 55 wide at (48, -7). Health
-- 70 x 10 at (47, -20), its mask 30 left of and 3 above it; power 74 x 7 at (44, -31), its mask at (16, -26) of the
-- frame. Four of them in a row, each a class with its own power, following the party settings.

local PARTY = {
    art = "UI-HUD-UnitFrame-Party-PortraitOn",
    health = { x = 47, y = -20, w = 70, h = 10, fillAtlas = "UI-HUD-UnitFrame-Party-PortraitOn-Bar-Health",
               maskAtlas = "UI-HUD-UnitFrame-Party-PortraitOn-Bar-Health-Mask", maskX = -30, maskY = 3 },
    power = { x = 44, y = -31, w = 74, h = 7,
              maskAtlas = "UI-HUD-UnitFrame-Party-PortraitOn-Bar-Mana-Mask", maskX = 16 - 44, maskY = -26 + 31 },
}
Preview.PARTY = PARTY -- for /sab capture party (Capture.lua)
-- At Forever's own offsets the example's power bar and mask sat over the gold divider above the mana slot and its left
-- border (seen in game in the editor, and on the captured art: tools/harness/gallery.py, PARTY_POWER_SHIFT), though the
-- game's own fill does not. So the example's sit this much further right and down; the capture keeps the game's.
local PARTY_POWER_SHIFT = { 1.5, -1.9 }
local SHIFTED_POWER = setmetatable({ x = PARTY.power.x + PARTY_POWER_SHIFT[1], y = PARTY.power.y + PARTY_POWER_SHIFT[2] },
    { __index = PARTY.power })
-- The class icons, by file ID, where the client has no class icon atlas.
local CLASS_ICONS = { WARRIOR = 626008, PRIEST = 626004, MAGE = 626001, ROGUE = 626005 }

-- A party member's portrait on f: the class's icon in a circle, 37 across at (7, -6), as the game shows a member.
function Preview.PartyPortrait(f, class)
    local portrait = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    portrait:SetSize(37, 37)
    portrait:SetPoint("TOPLEFT", 7, -6)
    if not Atlas(portrait, "classicon-" .. class:lower()) then portrait:SetTexture(CLASS_ICONS[class] or QUESTION_MARK) end
    local mask = f:CreateMaskTexture()
    if Atlas(mask, "CircleMask") then
        mask:SetAllPoints(portrait)
        portrait:AddMaskTexture(mask)
    end
    return portrait
end

-- A party member frame's art on f, at (1, -2) and its own size; nil where the client has no such atlas.
function Preview.PartyArt(f)
    local art = f:CreateTexture(nil, "BACKGROUND", nil, 2)
    if Atlas(art, PARTY.art, true) then
        art:SetPoint("TOPLEFT", 1, -2)
        return art
    end
    art:Hide()
end
-- name, class, power type, most power
local MEMBERS = {
    { "Brannoc", "WARRIOR", "RAGE", 100 },
    { "Elisande", "PRIEST", "MANA", 300 },
    { "Corvin", "MAGE", "MANA", 320 },
    { "Tessaly", "ROGUE", "ENERGY", 100 },
}
-- Health and power as fractions, looped: { seconds, then each member's health and power }. The warrior takes the hits
-- and builds rage, the priest spends mana healing, the mage casting, the rogue's energy comes and goes.
local PARTY_SCRIPT = {
    { 0.0, 1.00, 0.10, 1.00, 0.90, 1.00, 1.00, 1.00, 1.00 },
    { 1.2, 0.70, 0.40, 1.00, 0.90, 0.90, 0.80, 1.00, 0.60 },
    { 2.2, 0.85, 0.55, 1.00, 0.75, 0.90, 0.65, 0.80, 0.40 },
    { 3.0, 0.55, 0.70, 1.00, 0.75, 0.90, 0.50, 0.80, 0.75 },
    { 4.0, 0.80, 0.30, 0.85, 0.60, 0.90, 0.50, 0.80, 0.35 },
    { 5.0, 0.80, 0.30, 0.85, 0.60, 0.65, 0.35, 0.60, 0.70 },
    { 6.0, 1.00, 0.20, 0.85, 0.45, 0.85, 0.35, 0.60, 1.00 },
    { 7.2, 1.00, 0.10, 1.00, 0.90, 1.00, 1.00, 1.00, 1.00 },
}

local function Member(holder, spec, as)
    local name, class, token, powerMax = unpack(spec)
    local f = CreateFrame("Frame", nil, holder)
    f:SetSize(120, 53)
    local top = CreateFrame("Frame", nil, f)
    top:SetAllPoints()
    top:SetFrameLevel(f:GetFrameLevel() + 10)

    Preview.PartyPortrait(f, class)
    Preview.PartyArt(f)

    local label = top:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetJustifyH("LEFT")
    label:SetSize(55, 12)
    label:SetPoint("TOPLEFT", 48, -7)
    label:SetText(name)

    local info = PowerBarColor and PowerBarColor[token]
    f.health = Bar(f, top, PARTY.health, { key = as .. "Health", frame = as, class = class, unit = "party1",
        kind = "health", max = 400 })
    f.power = Bar(f, top, SHIFTED_POWER, { key = as .. "Power", frame = as, class = class, unit = "party1",
        kind = "power", token = token, max = powerMax, color = info and { info.r, info.g, info.b } or { 0, 0, 1 },
        fillAtlas = info and info.atlas or nil })
    -- The game shows party bar text only with its status text setting; the examples are cleaner without.
    f.health.text:Hide()
    f.power.text:Hide()
    return f
end

-- The four members, in a row or (stacked) one under the other as the game shows them, playing their fight, or one of
-- the frames' scenes (SetScene), while shown. as: whose settings their bars follow, "party" by default.
function Preview.CreateParty(parent, as, stacked)
    local holder = CreateFrame("Frame", nil, parent)
    if stacked then holder:SetSize(120, 4 * 53 + 3 * 4) else holder:SetSize(4 * 120 + 3 * 10, 53) end
    local members = {}
    holder.bars = {}
    for i, spec in ipairs(MEMBERS) do
        members[i] = Member(holder, spec, as or "party")
        if stacked then
            members[i]:SetPoint("TOPLEFT", 0, -(i - 1) * 57)
        else
            members[i]:SetPoint("LEFT", (i - 1) * 130, 0)
        end
        holder.bars[#holder.bars + 1] = members[i].health
        holder.bars[#holder.bars + 1] = members[i].power
    end
    local t, step = 0, 0
    local function Play(i)
        local row = PARTY_SCRIPT[i]
        for n, m in ipairs(members) do
            SetFraction(m.health, row[2 * n])
            SetFraction(m.power, row[2 * n + 1])
        end
    end
    Play(1)
    holder.scene = "fight"
    holder:SetScript("OnUpdate", function(_, elapsed)
        t = t + elapsed * (holder.speed or 1)
        if holder.scene ~= "fight" then
            for n, m in ipairs(members) do
                local row = GroupRow(holder.scene, t, n)
                SetFraction(m.health, row[2])
                SetFraction(m.power, row[3])
            end
            return
        end
        if t >= LOOP then t, step = t - LOOP, 0 end
        while PARTY_SCRIPT[step + 1] and PARTY_SCRIPT[step + 1][1] <= t do
            step = step + 1
            Play(step)
        end
    end)
    function holder.SetScene(_, name)
        if not SCENES[name] then return end
        holder.scene, t, step = name, 0, 0
    end
    holder.members = members
    return holder
end

--------------------------------------------------------------------------------
-- The preview raid (the editor's raid section)
--------------------------------------------------------------------------------
-- The game's raid-style frames (CompactUnitFrameTemplate) as Edit Mode first lays them out: a button 98 x 44 with the
-- health bar 1 in from its edges and the power bar the bottom 8 of it, a dark background, the member's name top left.
-- Their art is the game's by path, so it is drawn here in solid colours. Ten members in two rows of five, each with
-- its class and power type, following the raid settings (raidHealth, raidPower and their colours).

local RAID_W, RAID_H, RAID_POWER_H, RAID_GAP = 98, 44, 8, 3
local RAIDERS = {
    { "Brannoc", "WARRIOR", "RAGE", 100 }, { "Elisande", "PRIEST", "MANA", 300 }, { "Corvin", "MAGE", "MANA", 320 },
    { "Tessaly", "ROGUE", "ENERGY", 100 }, { "Garrik", "PALADIN", "MANA", 280 }, { "Mirelle", "DRUID", "MANA", 300 },
    { "Vexa", "WARLOCK", "MANA", 310 }, { "Aldric", "PRIEST", "MANA", 290 }, { "Sorin", "MAGE", "MANA", 330 },
    { "Hadrek", "WARRIOR", "RAGE", 100 },
}
-- Each member's health and power walk these, each from its own place, a step every 0.9 seconds.
local RAID_HEALTH = { 1.00, 0.86, 0.70, 0.92, 0.55, 0.78, 1.00, 0.95 }
local RAID_POWER = { 0.80, 0.55, 0.35, 0.60, 0.90, 0.45, 0.70, 1.00 }
local RAID_STEP = 0.9

local function RaidBar(f, top, setup, y, h)
    local bar = CreateFrame("StatusBar", nil, f)
    bar:SetPoint("TOPLEFT", 1, y)
    bar:SetSize(RAID_W - 2, h)
    local fill = bar:CreateTexture(nil, "ARTWORK")
    fill:SetColorTexture(1, 1, 1, 1)
    bar:SetStatusBarTexture(fill)
    local c = setup.color
    bar:SetStatusBarColor(c[1], c[2], c[3])
    bar:SetMinMaxValues(0, setup.max)
    bar:SetValue(setup.max)
    bar.max = setup.max
    -- The game shows a raid frame's health text only with its setting; the example goes without.
    bar.text = top:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
    bar.text:Hide()
    bar.state = ns.Bars.Preview(bar, { key = setup.key, frame = "raid", class = setup.class, unit = "raid1",
                                       kind = setup.kind, token = setup.token, slow = true, raidLook = true })
    return bar
end

local function Raider(holder, spec)
    local name, class, token, powerMax = unpack(spec)
    local f = CreateFrame("Frame", nil, holder)
    f:SetSize(RAID_W, RAID_H)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.08, 0.08, 0.08, 0.9)
    local top = CreateFrame("Frame", nil, f)
    top:SetAllPoints()
    top:SetFrameLevel(f:GetFrameLevel() + 10)
    -- The game's thin dark border round each frame.
    for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" },
                            { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
        local t = top:CreateTexture(nil, "BORDER")
        t:SetColorTexture(0, 0, 0, 1)
        t:SetPoint(side[1])
        t:SetPoint(side[2])
        if side[1]:sub(1, 3) == side[2]:sub(1, 3) then t:SetHeight(1) else t:SetWidth(1) end
    end
    local colors = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS or {})[class]
    local info = PowerBarColor and PowerBarColor[token]
    f.health = RaidBar(f, top, { key = "raidHealth", class = class, kind = "health", max = 400,
        color = colors and { colors.r, colors.g, colors.b } or { 0, 0.8, 0 } }, -1, RAID_H - 2 - RAID_POWER_H)
    f.power = RaidBar(f, top, { key = "raidPower", class = class, kind = "power", token = token, max = powerMax,
        color = info and { info.r, info.g, info.b } or { 0, 0, 1 } }, -(RAID_H - 1 - RAID_POWER_H), RAID_POWER_H)
    local label = top:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", 4, -4)
    label:SetJustifyH("LEFT")
    label:SetText(name)
    return f
end

-- The ten members in two rows, their health and power moving while shown.
function Preview.CreateRaid(parent)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(5 * RAID_W + 4 * RAID_GAP, 2 * RAID_H + RAID_GAP)
    local members = {}
    holder.bars = {}
    for i, spec in ipairs(RAIDERS) do
        local m = Raider(holder, spec)
        local col, row = (i - 1) % 5, math.floor((i - 1) / 5)
        m:SetPoint("TOPLEFT", col * (RAID_W + RAID_GAP), -row * (RAID_H + RAID_GAP))
        members[i] = m
        holder.bars[#holder.bars + 1] = m.health
        holder.bars[#holder.bars + 1] = m.power
    end
    local t, step = 0, -1
    local function Play(n)
        for i, m in ipairs(members) do
            SetFraction(m.health, RAID_HEALTH[(n + i * 3) % #RAID_HEALTH + 1])
            SetFraction(m.power, RAID_POWER[(n + i * 5) % #RAID_POWER + 1])
        end
    end
    holder.scene = "fight"
    holder:SetScript("OnUpdate", function(_, elapsed)
        t = t + elapsed * (holder.speed or 1)
        if holder.scene ~= "fight" then
            for i, m in ipairs(members) do
                local row = GroupRow(holder.scene, t, i)
                SetFraction(m.health, row[2])
                SetFraction(m.power, row[3])
            end
            return
        end
        local n = math.floor(t / RAID_STEP)
        if n ~= step then
            step = n
            Play(n)
        end
    end)
    function holder.SetScene(_, name)
        if not SCENES[name] then return end
        holder.scene, t, step = name, 0, -1
    end
    Play(0)
    step = 0
    holder.members = members
    return holder
end

--------------------------------------------------------------------------------
-- The preview nameplates (the setup's nameplate step)
--------------------------------------------------------------------------------
-- Forever's own plate (Blizzard_NamePlates/Camelot), in its Normal style: a bar 13 high in the bronze background
-- (UI-HUD-CoolDownManager-Bar-BG, 2 left, 3 up, 6 right and 6 down of the bar, its atlas's own margin included), its
-- fill tinted with the unit's colour, the level box 5 right of the bar (28 wide, 3 above to 2 below), the name above.
-- The target has the yellow glow round the background and the level box's outline; the others the game's darkening.
-- The liquid follows the plate settings (plateHealth, plateFriendly, plateDots) and sits a level above the bar, as on
-- real plates.

local PLATE_W, PLATE_H = 150, 13
-- name, level, unit colour, colour setting it follows ("plate" or "friend"), on/off setting, targeted, place. The
-- left column leaves room for the kill icon left of the target's bar (Marker.lua), and the whole stays centred.
local PLATES = {
    { "Defias Pillager", 18, { 1, 0, 0 }, "plate", "plateHealth", true, 40, -24 },
    { "Defias Smuggler", 17, { 1, 0, 0 }, "plate", "plateHealth", false, 40, -70 },
    { "Mottled Boar", 16, { 1, 1, 0 }, "plate", "plateHealth", false, 280, -24 },
    { "Stormwind Guard", 25, { 0, 1, 0 }, "friend", "plateFriendly", false, 280, -70 },
}
-- Health as fractions, looped: { seconds, the target's, the second enemy's, the boar's, the guard's }.
local PLATE_SCRIPT = {
    { 0.0, 1.00, 0.90, 0.60, 1.00 },
    { 1.2, 0.80, 0.90, 0.60, 1.00 },
    { 2.2, 0.62, 0.70, 0.60, 0.92 },
    { 3.0, 0.62, 0.70, 0.48, 1.00 },
    { 4.0, 0.25, 0.55, 0.48, 1.00 },
    { 5.0, 0.25, 0.55, 0.48, 0.85 },
    { 6.0, 0.00, 0.40, 0.48, 1.00 },
    { 7.2, 1.00, 0.90, 0.60, 1.00 },
}
-- The target's DoTs at each row, in points of its 210 health, as on the frames' target (DOTS): by the fifth row
-- they will finish it, and the kill icon shows beside its plate.
local PLATE_DOTS = {
    {},
    { { "Corruption", 54, 32 } },
    { { "Corruption", 48, 32 }, { "Immolate", 40, 4 } },
    { { "Corruption", 42, 32 }, { "Immolate", 34, 4 } },
    { { "Corruption", 30, 32 }, { "Immolate", 28, 4 } },
    { { "Corruption", 30, 32 }, { "Immolate", 28, 4 } },
    {},
    {},
}

local function Plate(holder, top, spec)
    local name, level, color, frame, key, targeted, x, y = unpack(spec)
    local bar = CreateFrame("StatusBar", nil, holder)
    bar:SetSize(PLATE_W, PLATE_H)
    bar:SetPoint("TOPLEFT", x, y)
    local fill = bar:CreateTexture(nil, "ARTWORK")
    if not Atlas(fill, "UI-HUD-CoolDownManager-Bar") then fill:SetColorTexture(1, 1, 1, 1) end
    bar:SetStatusBarTexture(fill)
    bar:SetStatusBarColor(color[1], color[2], color[3])
    bar:SetMinMaxValues(0, 210)
    bar:SetValue(210)
    bar.max = 210

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    if Atlas(bg, "UI-HUD-CoolDownManager-Bar-BG") then
        bg:SetPoint("TOPLEFT", bar, "TOPLEFT", -2, 3)
        bg:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 6, -6)
    else
        bg:Hide()
    end
    if not targeted then
        local dark = bar:CreateTexture(nil, "OVERLAY")
        if Atlas(dark, "ui-hud-nameplates-deselected-overlay") then dark:SetAllPoints(bar) else dark:Hide() end
    end

    local box = CreateFrame("Frame", nil, holder)
    box:SetPoint("TOPLEFT", bar, "TOPRIGHT", 5, 3)
    box:SetPoint("BOTTOMLEFT", bar, "BOTTOMRIGHT", 5, -2)
    box:SetWidth(28)
    local boxArt = box:CreateTexture(nil, "BACKGROUND")
    if Atlas(boxArt, "ui-hud-nameplates-levelindicator") then boxArt:SetAllPoints() else boxArt:Hide() end
    local levelText = top:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    levelText:SetPoint("CENTER", box, "CENTER", 0, 0)
    levelText:SetText(level)

    if targeted then
        local glow = top:CreateTexture(nil, "OVERLAY")
        if Atlas(glow, "UI-HUD-CoolDownManager-Selected-yellow") then
            glow:SetPoint("TOPLEFT", bg, "TOPLEFT", -3, 2)
            glow:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", 0, 2)
        else
            glow:Hide()
        end
        local outline = top:CreateTexture(nil, "OVERLAY")
        if Atlas(outline, "ui-hud-nameplates-levelindicator-rectangle-selected") then
            outline:SetPoint("TOPLEFT", box, "TOPLEFT", -3, 3)
            outline:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 3, -4)
        else
            outline:Hide()
        end
    end

    local label = top:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("BOTTOM", bar, "TOP", 0, 3)
    label:SetText(name)

    bar.state = ns.Bars.Preview(bar, { key = key, frame = frame, unit = frame == "friend" and "player" or "target",
                                       kind = "health", plate = true })
    return bar
end

local function SetPlate(bar, frac)
    if Resting(bar) then frac = 1 end
    local value = math.floor(frac * bar.max + 0.5)
    if value == bar.shownValue then return end
    bar.shownValue = value
    bar:SetValue(value)
    ns.Bars.Stir(bar.state)
end

-- The four plates side by side in two rows, playing the loop while shown.
function Preview.CreatePlates(parent)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(480, 100)
    local top = CreateFrame("Frame", nil, holder)
    top:SetAllPoints()
    top:SetFrameLevel(holder:GetFrameLevel() + 10)
    local bars = {}
    for i, spec in ipairs(PLATES) do bars[i] = Plate(holder, top, spec) end

    local dots = {}
    local target = bars[1]
    local marker = ns.Marker.Preview({
        bar = target, mask = target.state.mask, iconHost = holder, plate = true,
        visible = function() return true end,
        source = function()
            local list, total = {}, 0
            for i, dot in ipairs(dots) do
                list[i] = { name = dot[1], damage = dot[2], school = dot[3] }
                total = total + dot[2]
            end
            return target.max, target.shownValue, total, list
        end,
    })

    local t, step = 0, 0
    local function Play(i)
        local row = PLATE_SCRIPT[i]
        for n, bar in ipairs(bars) do SetPlate(bar, row[n + 1]) end
        local landed = #PLATE_DOTS[i] > #dots
        dots = PLATE_DOTS[i]
        if landed then ns.Marker.Landed(marker) end
    end
    Play(1)
    holder.scene = "fight"
    holder:SetScript("OnUpdate", function(_, elapsed)
        t = t + elapsed * (holder.speed or 1)
        if holder.scene ~= "fight" then
            if #dots > 0 then dots = {} end
            for n, bar in ipairs(bars) do SetPlate(bar, GroupRow(holder.scene, t, n)[2]) end
            return
        end
        if t >= LOOP then t, step = t - LOOP, 0 end
        while PLATE_SCRIPT[step + 1] and PLATE_SCRIPT[step + 1][1] <= t do
            step = step + 1
            Play(step)
        end
    end)
    function holder.SetScene(_, name)
        if not SCENES[name] then return end
        holder.scene, t, step = name, 0, 0
    end
    holder.plates, holder.marker, holder.bars = bars, marker, bars
    return holder
end

--------------------------------------------------------------------------------
-- The preview Personal Resource Display (the editor's)
--------------------------------------------------------------------------------
-- The game's display (Blizzard_PersonalResourceDisplay): health over power, the plates' bronze bars, here at the sizes
-- the gallery takes for Edit Mode's defaults (gallery.py, PRD_W...), with the liquid flat and raised as on the real one.

local PRD_W, PRD_HEALTH_H, PRD_POWER_H, PRD_GAP = 200, 12, 10, 4

local function PrdBar(holder, y, h, setup)
    -- The bronze background on the holder, under the bar and its liquid.
    local bg = holder:CreateTexture(nil, "BACKGROUND")
    if Atlas(bg, "UI-HUD-CoolDownManager-Bar-BG") then
        bg:SetPoint("TOPLEFT", holder, "TOPLEFT", -2, y + 3)
        bg:SetSize(PRD_W + 8, h + 10)
    else
        bg:SetPoint("TOPLEFT", holder, "TOPLEFT", -1, y + 1)
        bg:SetSize(PRD_W + 2, h + 2)
        bg:SetColorTexture(0, 0, 0, 0.7)
    end
    local bar = CreateFrame("StatusBar", nil, holder)
    bar:SetSize(PRD_W, h)
    bar:SetPoint("TOPLEFT", 0, y)
    local fill = bar:CreateTexture(nil, "ARTWORK")
    if not Atlas(fill, "UI-HUD-CoolDownManager-Bar") then fill:SetColorTexture(1, 1, 1, 1) end
    bar:SetStatusBarTexture(fill)
    local c = setup.color
    bar:SetStatusBarColor(c[1], c[2], c[3])
    bar:SetMinMaxValues(0, setup.max)
    bar:SetValue(setup.max)
    bar.max = setup.max
    bar.text = holder:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
    bar.text:Hide()
    bar.state = ns.Bars.Preview(bar, { key = setup.key, frame = "prd", unit = "player", kind = setup.kind,
                                       token = setup.token, flat = true })
    return bar
end

-- The display's health and power, playing the frames' scenes (the fight by default) while shown.
function Preview.CreatePRD(parent)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(PRD_W, PRD_HEALTH_H + PRD_GAP + PRD_POWER_H)
    local token, powerMax, info = PowerInfo("player")
    local health = PrdBar(holder, 0, PRD_HEALTH_H, { key = "prdHealth", kind = "health", max = 271, color = { 0, 0.8, 0 } })
    local power = PrdBar(holder, -(PRD_HEALTH_H + PRD_GAP), PRD_POWER_H, { key = "prdPower", kind = "power",
        token = token, max = powerMax, color = info and { info.r, info.g, info.b } or { 0, 0, 1 } })
    local t = 0
    holder.scene = "fight"
    holder:SetScript("OnUpdate", function(_, elapsed)
        t = t + elapsed * (holder.speed or 1)
        local row = RowAt(SCENES[holder.scene], t)
        SetFraction(health, row[2])
        SetFraction(power, row[3])
    end)
    function holder.SetScene(_, name)
        if not SCENES[name] then return end
        holder.scene, t = name, 0
    end
    holder.health, holder.power, holder.bars = health, power, { health, power }
    return holder
end

--------------------------------------------------------------------------------
-- The preview breath bar (the editor's)
--------------------------------------------------------------------------------
-- The game's breath bar (Blizzard_MirrorTimer/Mainline MirrorTimer.xml, forever branch): a 195 x 13 bar in the casting
-- bar's text box, dark background and border (Capture.lua's BREATH_PIECES, as the timer frame lays them), its label in
-- the text box under it. It plays its own loop rather than the frames' scenes: breath running out, bubbles rising off
-- the front (Bars.mirror, as on the real bar), then filling back up at the surface.

local BREATH_W, BREATH_H, BREATH_MAX = 195, 13, 600
local BREATH_PIECES = {
    { "ui-castingbar-textbox", 0, 0, 195, 27, "BACKGROUND", 0 },
    { "ui-castingbar-background", -1, -1, 197, 15, "BACKGROUND", 1 },
    { "ui-castingbar-frame", -2, -2, 199, 17, "OVERLAY", 0 },
}
-- { seconds, fraction }: running out for 6.4 s, back up by 9.
local BREATH_LOOP = { { 0.0, 1.00 }, { 6.4, 0.28 }, { 9.0, 1.00 } }

local function BreathAt(t)
    local loop = BREATH_LOOP
    t = t % loop[#loop][1]
    for i = 2, #loop do
        local a, b = loop[i - 1], loop[i]
        if t <= b[1] then return a[2] + (b[2] - a[2]) * (t - a[1]) / (b[1] - a[1]) end
    end
    return loop[#loop][2]
end

function Preview.CreateBreath(parent)
    local holder = CreateFrame("Frame", nil, parent)
    -- From the border's top-left (2 out from the bar) to the text box's bottom (27 under the bar's top).
    holder:SetSize(BREATH_W + 4, 27 + 2)
    for _, piece in ipairs(BREATH_PIECES) do
        local tex = holder:CreateTexture(nil, piece[6], nil, piece[7])
        if Atlas(tex, piece[1]) then
            tex:SetPoint("TOPLEFT", 2 + piece[2], -(2 + piece[3]))
            tex:SetSize(piece[4], piece[5])
        elseif piece[1] == "ui-castingbar-background" then
            tex:SetPoint("TOPLEFT", 2 + piece[2], -(2 + piece[3]))
            tex:SetSize(piece[4], piece[5])
            tex:SetColorTexture(0, 0, 0, 0.7)
        else
            tex:Hide()
        end
    end
    local bar = CreateFrame("StatusBar", nil, holder)
    bar:SetSize(BREATH_W, BREATH_H)
    bar:SetPoint("TOPLEFT", 2, -2)
    local fill = bar:CreateTexture(nil, "ARTWORK")
    fill:SetColorTexture(1, 1, 1, 1)
    bar:SetStatusBarTexture(fill)
    local c = ns.Bars.mirror.Color()
    bar:SetStatusBarColor(c[1], c[2], c[3])
    bar:SetMinMaxValues(0, BREATH_MAX)
    bar:SetValue(BREATH_MAX)
    local label = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOP", bar, "BOTTOM", 0, -1)
    -- The game's own word for it (GlobalStrings), as the timer's label shows it.
    local word = rawget(_G, "BREATH_LABEL")
    label:SetText(type(word) == "string" and word or "Breath")
    bar.state = ns.Bars.Preview(bar, { key = "breath", frame = "breath", unit = "player", kind = "breath",
                                       bare = true, breath = true })
    local t = 0
    holder:SetScript("OnUpdate", function(_, elapsed)
        t = t + elapsed * (holder.speed or 1)
        -- Off, it rests full and still, as the other examples whose liquid is off.
        bar:SetValue(Resting(bar) and BREATH_MAX or BreathAt(t) * BREATH_MAX)
    end)
    holder.bar, holder.bars = bar, { bar }
    return holder
end
