-- Preview player and target frames for the setup wizard: Forever's own unit frame art, rebuilt from
-- the atlases and layout of its PlayerFrame and TargetFrame (Blizzard_UnitFrame, Camelot overrides on
-- the Mainline XML), with bars of ours carrying the liquid. Their values are ours, so they play a short
-- loop of hits, heals and power changes, and the liquid follows the same settings as the real bars.
--
-- Atlases are fetched by name, which Forever loads; game files by path are not used. If an atlas is
-- missing the piece is left out (a missing bar mask leaves the liquid uncut rather than hidden).

local _, ns = ...

local Preview = {}
ns.Preview = Preview

local QUESTION_MARK = 134400 -- INV_Misc_QuestionMark, the target's stand-in portrait

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

local function Atlas(tex, name, useSize)
    return tex.SetAtlas and tex:SetAtlas(name, useSize) and true or false
end

local function PowerInfo(unit)
    local index, token = UnitPowerType(unit)
    if (issecretvalue and (issecretvalue(index) or issecretvalue(token))) or not token then token = "MANA" end
    local info = PowerBarColor and PowerBarColor[token]
    return token, token == "MANA" and 350 or 100, info
end

-- A bar like the game's: its own fill (shown while the liquid is off), shaped by the game's mask
-- atlas, with its text above everything on top.
local function Bar(f, top, spec)
    local bar = CreateFrame("StatusBar", nil, f)
    bar:SetSize(spec.w, spec.h)
    bar:SetPoint("TOPLEFT", spec.x, spec.y)
    local fill = bar:CreateTexture(nil, "ARTWORK")
    if not (spec.fillAtlas and Atlas(fill, spec.fillAtlas)) then
        local c = spec.color or { 0, 1, 0 }
        fill:SetColorTexture(c[1], c[2], c[3], 1)
    end
    bar:SetStatusBarTexture(fill)
    bar:SetMinMaxValues(0, spec.max)
    bar:SetValue(spec.max)

    local mask = bar:CreateMaskTexture()
    if Atlas(mask, spec.maskAtlas, true) then
        mask:SetPoint("TOPLEFT", bar, "TOPLEFT", spec.maskX, spec.maskY)
        if spec.maskW then mask:SetWidth(spec.maskW) end
        if spec.maskH then mask:SetHeight(spec.maskH) end
        fill:AddMaskTexture(mask)
        bar[spec.kind == "health" and "HealthBarMask" or "ManaBarMask"] = mask
    end

    bar.text = top:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
    bar.text:SetPoint("CENTER", bar, "CENTER", 0, 0)
    bar.max = spec.max
    bar.state = ns.Bars.Preview(bar, { key = spec.key, unit = spec.unit, kind = spec.kind, token = spec.token })
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
local function Frame(parent, isTarget)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(232, 100)
    local top = CreateFrame("Frame", nil, f)
    top:SetAllPoints()
    top:SetFrameLevel(f:GetFrameLevel() + 10)

    local portrait = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    local portraitMask = f:CreateMaskTexture()
    if isTarget then
        portrait:SetSize(58, 58)
        portrait:SetPoint("TOPRIGHT", -26, -19)
        portrait:SetTexture(QUESTION_MARK)
        if Atlas(portraitMask, "CircleMask") then
            portraitMask:SetPoint("TOPLEFT", portrait, "TOPLEFT", 0, -1)
            portraitMask:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", -1, 0)
            portrait:AddMaskTexture(portraitMask)
        end
    else
        portrait:SetSize(60, 60)
        portrait:SetPoint("TOPLEFT", 24, -19)
        if SetPortraitTexture then SetPortraitTexture(portrait, "player") end
        if Atlas(portraitMask, "UI-HUD-UnitFrame-Player-Portrait-Mask") then
            portraitMask:SetAllPoints(portrait)
            portrait:AddMaskTexture(portraitMask)
        end
    end

    local art = f:CreateTexture(nil, "BACKGROUND", nil, 2)
    Atlas(art, isTarget and "UI-HUD-UnitFrame-Target-PortraitOn" or "UI-HUD-UnitFrame-Player-PortraitOn", true)
    art:SetPoint("CENTER")

    local name = top:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    name:SetJustifyH("CENTER")
    if isTarget then
        -- The name banner, tinted as for a hostile target.
        local banner = f:CreateTexture(nil, "BACKGROUND", nil, 3)
        if Atlas(banner, "UI-HUD-UnitFrame-Target-PortraitOn-Type", true) then
            banner:SetPoint("TOPRIGHT", -82, -26)
            banner:SetVertexColor(0.8, 0.1, 0.1)
        end
        name:SetSize(117, 12)
        name:SetPoint("TOPRIGHT", -82 - 9, -30)
        name:SetText("Your Target")
    else
        name:SetSize(116, 12)
        name:SetPoint("CENTER", f, "TOPLEFT", 149, -37)
        -- The game's own name text, surname included on Forever.
        local shown = PlayerName and PlayerName.GetText and PlayerName:GetText()
        name:SetText(shown or (UnitName("player")))
    end

    local circle = top:CreateTexture(nil, "OVERLAY")
    Atlas(circle, "UI-HUD-UnitFrame-SmallCircle", true)
    if isTarget then circle:SetPoint("BOTTOMRIGHT", -13, 7) else circle:SetPoint("BOTTOMLEFT", 13, 7) end
    local level = top:CreateFontString(nil, "OVERLAY", "WhiteLargeNumberFont")
    level:SetPoint("CENTER", circle, "CENTER", 0, -0.5)
    level:SetText(UnitLevel("player"))

    local token, powerMax, info = PowerInfo(isTarget and "target" or "player")
    if isTarget then token, powerMax, info = "MANA", 350, PowerBarColor and PowerBarColor.MANA end
    local power = info and { info.r, info.g, info.b } or { 0, 0, 1 }
    local unit = isTarget and "target" or "player"
    if isTarget then
        -- The health bar sits 3 px above its container, which ends at the frame's left middle + (147, -9);
        -- the mana bar hangs below the container's right end.
        f.health = Bar(f, top, { key = "targetHealth", unit = unit, kind = "health", x = 21, y = -41, w = 126, h = 20,
            max = 210, fillAtlas = "UI-HUD-UnitFrame-Target-PortraitOn-Bar-Health",
            maskAtlas = "UI-HUD-UnitFrame-Target-PortraitOn-Bar-Health-Mask", maskX = -1, maskY = 6 })
        f.power = Bar(f, top, { key = "targetPower", unit = unit, kind = "power", token = token, x = 17, y = -60,
            w = 134, h = 10, max = powerMax, color = power, fillAtlas = "UI-HUD-UnitFrame-Target-PortraitOn-Bar-Mana",
            maskAtlas = "UI-HUD-UnitFrame-Target-PortraitOn-Bar-Mana-Mask", maskX = -61, maskY = 3 })
    else
        f.health = Bar(f, top, { key = "playerHealth", unit = unit, kind = "health", x = 87, y = -43, w = 124, h = 20,
            max = 271, fillAtlas = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health",
            maskAtlas = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health-Mask", maskX = -2, maskY = 6, maskH = 32 })
        f.power = Bar(f, top, { key = "playerPower", unit = unit, kind = "power", token = token, x = 87, y = -61,
            w = 124, h = 10, max = powerMax, color = power, fillAtlas = info and info.atlas,
            maskAtlas = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Mana-Mask", maskX = -2, maskY = 2, maskW = 128 })
    end
    return f
end

-- Both frames side by side, playing the loop while shown.
function Preview.Create(parent)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(480, 100)
    local player, target = Frame(holder, false), Frame(holder, true)
    player:SetPoint("LEFT")
    target:SetPoint("RIGHT")
    local t, step = 0, 0
    local function Play(i)
        local row = SCRIPT[i]
        SetFraction(player.health, row[2])
        SetFraction(player.power, row[3])
        SetFraction(target.health, row[4])
        SetFraction(target.power, row[5])
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
    holder.player, holder.target = player, target
    return holder
end
