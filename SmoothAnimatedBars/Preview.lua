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

local function SetFraction(bar, frac)
    local value = math.floor(frac * bar.max + 0.5)
    if value == bar.shownValue then return end
    bar.shownValue = value
    bar:SetValue(value)
    bar.text:SetText(value .. " / " .. bar.max)
    ns.Bars.Stir(bar.state)
end

-- The frame: art at the bottom, then the bars and their liquid, then the text, the level circle and
-- the name above them, as the game layers them.
local function Frame(parent, which)
    local L = LAYOUT[which]
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
        name:SetText("Your Target")
    else
        name:SetPoint(L.name.point, f, "TOPLEFT", L.name.x, L.name.y)
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
    local key = which == "target" and "target" or "player"
    f.health = Bar(f, top, L.health, { key = key .. "Health", unit = which, kind = "health",
        max = which == "target" and 210 or 271 })
    f.power = Bar(f, top, L.power, { key = key .. "Power", unit = which, kind = "power", token = token,
        max = powerMax, color = info and { info.r, info.g, info.b } or { 0, 0, 1 },
        fillAtlas = which == "player" and info and info.atlas or nil })
    return f
end

-- Both frames side by side, playing the loop while shown.
function Preview.Create(parent)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(480, 100)
    local player, target = Frame(holder, "player"), Frame(holder, "target")
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

    local t, step = 0, 0
    local function Play(i)
        local row = SCRIPT[i]
        SetFraction(player.health, row[2])
        SetFraction(player.power, row[3])
        SetFraction(target.health, row[4])
        SetFraction(target.power, row[5])
        local landed = #DOTS[i] > #dots
        dots = DOTS[i]
        if landed then ns.Marker.Landed(marker) end
    end
    Play(1)
    holder:SetScript("OnUpdate", function(_, elapsed)
        t = t + elapsed
        if t >= LOOP then t, step = t - LOOP, 0 end
        while SCRIPT[step + 1] and SCRIPT[step + 1][1] <= t do
            step = step + 1
            Play(step)
        end
    end)
    holder.player, holder.target, holder.marker = player, target, marker
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

local function Member(holder, spec)
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
    f.health = Bar(f, top, PARTY.health, { key = "partyHealth", frame = "party", class = class, unit = "party1",
        kind = "health", max = 400 })
    f.power = Bar(f, top, PARTY.power, { key = "partyPower", frame = "party", class = class, unit = "party1",
        kind = "power", token = token, max = powerMax, color = info and { info.r, info.g, info.b } or { 0, 0, 1 },
        fillAtlas = info and info.atlas or nil })
    -- The game shows party bar text only with its status text setting; the examples are cleaner without.
    f.health.text:Hide()
    f.power.text:Hide()
    return f
end

-- The four members in a row, playing the loop while shown.
function Preview.CreateParty(parent)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(4 * 120 + 3 * 10, 53)
    local members = {}
    for i, spec in ipairs(MEMBERS) do
        members[i] = Member(holder, spec)
        members[i]:SetPoint("LEFT", (i - 1) * 130, 0)
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
    holder:SetScript("OnUpdate", function(_, elapsed)
        t = t + elapsed
        if t >= LOOP then t, step = t - LOOP, 0 end
        while PARTY_SCRIPT[step + 1] and PARTY_SCRIPT[step + 1][1] <= t do
            step = step + 1
            Play(step)
        end
    end)
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
-- name, level, unit colour, colour setting it follows ("plate" or "friend"), on/off setting, targeted, place
local PLATES = {
    { "Defias Pillager", 18, { 1, 0, 0 }, "plate", "plateHealth", true, 14, -24 },
    { "Defias Smuggler", 17, { 1, 0, 0 }, "plate", "plateHealth", false, 14, -70 },
    { "Mottled Boar", 16, { 1, 1, 0 }, "plate", "plateHealth", false, 254, -24 },
    { "Stormwind Guard", 25, { 0, 1, 0 }, "friend", "plateFriendly", false, 254, -70 },
}
-- Health as fractions, looped: { seconds, the target's, the second enemy's, the boar's, the guard's }.
local PLATE_SCRIPT = {
    { 0.0, 1.00, 0.90, 0.60, 1.00 },
    { 1.2, 0.80, 0.90, 0.60, 1.00 },
    { 2.2, 0.62, 0.70, 0.60, 0.92 },
    { 3.0, 0.62, 0.70, 0.48, 1.00 },
    { 4.0, 0.40, 0.55, 0.48, 1.00 },
    { 5.0, 0.40, 0.55, 0.48, 0.85 },
    { 6.0, 0.18, 0.40, 0.48, 1.00 },
    { 7.2, 1.00, 0.90, 0.60, 1.00 },
}
-- The target's DoTs at each row, in points of its 210 health, as on the frames' target (DOTS).
local PLATE_DOTS = {
    {},
    { { "Corruption", 54, 32 } },
    { { "Corruption", 48, 32 }, { "Immolate", 40, 4 } },
    { { "Corruption", 42, 32 }, { "Immolate", 34, 4 } },
    { { "Corruption", 30, 32 }, { "Immolate", 28, 4 } },
    { { "Corruption", 30, 32 }, { "Immolate", 28, 4 } },
    { { "Corruption", 20, 32 } },
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
    holder:SetScript("OnUpdate", function(_, elapsed)
        t = t + elapsed
        if t >= LOOP then t, step = t - LOOP, 0 end
        while PLATE_SCRIPT[step + 1] and PLATE_SCRIPT[step + 1][1] <= t do
            step = step + 1
            Play(step)
        end
    end)
    holder.plates, holder.marker = bars, marker
    return holder
end
