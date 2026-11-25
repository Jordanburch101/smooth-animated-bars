-- Taller player and target bars (the playerHealthHeight, playerPowerHeight, targetHealthHeight and targetPowerHeight
-- settings). At the game's heights (20 and 10) nothing here runs and the game's frames are only read and drawn on, as
-- everywhere else. With a height changed, a frame of ours is drawn in place of the game's: Preview.lua's frame (the
-- game's own atlas cut into slices and laid out again, Preview.TallArt) as a child of the game's frame, grown upward
-- from its bottom edge so nothing the game hangs below the frames (the target's auras, its cast bar, the target of
-- target, the pet frame) is covered; a target whose auras the game puts on top (Edit Mode's Buffs on Top) grows down
-- instead (SPEC.down).
--
-- The game's pieces it redraws are faded to alpha 0 while it shows, and given their alpha back when it goes: the frame
-- art, the portrait, the health and power bars (with their texts, heal prediction and absorbs), the name, the level and
-- the icons round the portrait. Nothing is hooked, nothing is written onto a game frame, nothing is moved: the faded
-- bars keep the mouse, and the game keeps updating them. Ours copy from them:
--   * the bars' values (secret: handed from the game's bar to ours, never compared), every frame, and ours go to the
--     liquid through Bars.AddBar with the frame's own settings (as an adaptor hands another addon's bars);
--   * the bars' texts, the name, the level and the target's banner colour, every POLL seconds;
--   * the icons round the portrait (the target's elite dragon, the high level skull, raid target, leader, PvP...): each
--     game texture's atlas or file, colour and shown state, drawn where the moved ring puts it;
--   * the portrait, with SetPortraitTexture, when it changes;
--   * the flashes and the status glow, laid out as the art is (Preview.TallGlow);
--   * the game's segments on its bars (heal predictions, absorbs, the mana cost) and the glows at the health bar's
--     ends, under the game's keys on our bars, so the heal marker and the shield find them there.
-- Still left as the game's, where they were: see docs/TALLER_BARS_GOALS.md.

local _, ns = ...

local TallFrames = {}
ns.TallFrames = TallFrames

local POLL = 0.1
local OPTIONS_NAME = "Smooth Animated Bars"

local function Secret(v) return issecretvalue ~= nil and issecretvalue(v) end

-- A readable number, or nil.
local function Number(v)
    if type(v) == "number" and not Secret(v) then return v end
end

local function Path(t, ...)
    for i = 1, select("#", ...) do
        if type(t) ~= "table" then return nil end
        t = t[(select(i, ...))]
    end
    return t
end

-- The pieces found, in a list without holes (ipairs stops at the first nil, and a client can lack any of them).
local function Found(...)
    local out = {}
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if type(v) == "table" then out[#out + 1] = v end
    end
    return out
end

-- A game bar's centre, left and right texts: on the bar as SetBarText puts them (TextStatusBar), else where the XML has
-- them (the power bar's ManaBarText, the player's health texts on its container, the pet's named after its bar).
local function BarTexts(game)
    local parent = game.GetParent and game:GetParent()
    local ok, name = pcall(game.GetName, game)
    local function Named(suffix)
        return ok and type(name) == "string" and rawget(_G, name .. suffix) or nil
    end
    return game.TextString or game.ManaBarText or game.CenterText or Path(parent, "HealthBarText") or Named("Text"),
        game.LeftText or Path(parent, "LeftText") or Named("TextLeft"),
        game.RightText or Path(parent, "RightText") or Named("TextRight")
end

-- What each frame is made of on Forever (Blizzard_UnitFrame: Mainline's XML with Camelot's overrides). Each frame's
-- spec: the settings it follows (prefix: playerHealthHeight...), its art (Preview.LAYOUT and TALL, so frames with the
-- same art share their measurements), the frame of ours it stands for (as, Preview's SIDES), its unit, and how to find
-- its pieces on the game's frame gf: its bars, name and level, the pieces faded and redrawn by ours (fade), the ones
-- faded and drawn by ours where its moved ring puts them (carry), and whether it grows down rather than up (down).

-- The target's template: the target and the focus.
local function TargetLike(global, unit, prefix)
    return {
        prefix = prefix, art = "target", as = prefix, unit = unit,
        frame = function() return rawget(_G, global) end,
        health = function(gf) return Path(gf, "healthbar") end,
        power = function(gf) return Path(gf, "manabar") end,
        name = function(gf) return Path(gf, "TargetFrameContent", "TargetFrameContentMain", "Name") end,
        level = function(gf) return Path(gf, "TargetFrameContent", "TargetFrameContentMain", "LevelText") end,
        banner = function(gf) return Path(gf, "TargetFrameContent", "TargetFrameContentMain", "ReputationColor") end,
        -- With Edit Mode's Buffs on Top the game anchors the auras above its art (TargetFrameMixin:
        -- AnchorAuraContainer, BOTTOMLEFT on the FrameTexture's TOPLEFT), where growing up would cover them: then the
        -- frame grows down instead, over the cast bar's and the target of target's top edge rather than the auras.
        down = function(gf) return gf.buffsOnTop == true end,
        -- The dead and unconscious texts are on its health bars' container, centred on the bar.
        extraTexts = function(gf)
            local c = Path(gf, "TargetFrameContent", "TargetFrameContentMain", "HealthBarsContainer")
            return Found(Path(c, "DeadText"), Path(c, "UnconsciousText"))
        end,
        -- The art's container (art, portrait, flash, elite dragon) and the main content (bars, name, level, banner)
        -- faded whole.
        fade = function(gf)
            return Found(Path(gf, "TargetFrameContainer"), Path(gf, "TargetFrameContent", "TargetFrameContentMain"))
        end,
        glows = function(gf) return { { Path(gf, "TargetFrameContainer", "Flash"), true } } end,
        carry = function(gf)
            local c = Path(gf, "TargetFrameContent", "TargetFrameContentContextual")
            return Found(Path(gf, "TargetFrameContainer", "BossPortraitFrameTexture"), Path(c, "HighLevelTexture"),
                Path(c, "RaidTargetIcon"), Path(c, "BossIcon"), Path(c, "QuestIcon"), Path(c, "LeaderIcon"),
                Path(c, "GuideIcon"), Path(c, "PvpIcon"), Path(c, "PvpBackgroundIcon"), Path(c, "PrestigePortrait"),
                Path(c, "PrestigeBadge"))
        end,
    }
end

-- The targets of target (TargetofTargetFrameTemplate, its pieces on the frame itself). Small frames grow down: the
-- target's sits over the target frame's bottom right corner, and nothing hangs below it.
local function TargetOfTarget(global, unit)
    return {
        prefix = "tot", art = "tot", as = "tot", unit = unit,
        frame = function() return rawget(_G, global) end,
        health = function(gf) return Path(gf, "HealthBar") end,
        power = function(gf) return Path(gf, "ManaBar") end,
        name = function(gf) return Path(gf, "Name") end,
        down = function() return true end,
        extraTexts = function(gf) return Found(Path(gf, "HealthBar", "DeadText"), Path(gf, "HealthBar", "UnconsciousText")) end,
        fade = function(gf)
            return Found(Path(gf, "FrameTexture"), Path(gf, "Portrait"), Path(gf, "HealthBar"), Path(gf, "ManaBar"),
                Path(gf, "Name"))
        end,
        carry = function() return {} end,
    }
end

local SPEC = {
    player = {
        prefix = "player", art = "player", as = "player", unit = "player",
        frame = function() return rawget(_G, "PlayerFrame") end,
        health = function(gf) return Path(gf, "healthbar") end,
        power = function(gf) return Path(gf, "manabar") end,
        name = function() return rawget(_G, "PlayerName") end,
        level = function() return rawget(_G, "PlayerLevelText") end,
        -- The art's container and the main content (art, portrait, flash, bars, name, level, status glow) faded whole:
        -- the game pulses the status glow's own alpha every frame (PlayerFrame_OnUpdate), which ours copies.
        fade = function(gf)
            return Found(Path(gf, "PlayerFrameContainer"), Path(gf, "PlayerFrameContent", "PlayerFrameContentMain"),
                rawget(_G, "PlayerPVPTimerText"))
        end,
        -- Texts the game anchors to an icon ours carries: the PvP timer, left of the PvP badge (Camelot PlayerFrame.lua).
        follow = function(gf)
            return { { rawget(_G, "PlayerPVPTimerText"),
                       Path(gf, "PlayerFrameContent", "PlayerFrameContentMain", "PvpBackgroundIcon"), "RIGHT", "LEFT", 2, 0 } }
        end,
        -- The hit numbers over the portrait (CombatFeedback), in the main content, so faded with it: 1 below the
        -- portrait's middle (PlayerFrame.xml).
        hit = function(gf)
            return Path(gf, "PlayerFrameContent", "PlayerFrameContentMain", "HitIndicator", "HitText"), "CENTER", 0, -1
        end,
        -- The aggro flash (the threat indicator) and the status glow (rest, combat), drawn by ours laid out as its art.
        glows = function(gf)
            return { { Path(gf, "PlayerFrameContainer", "FrameFlash"), true },
                     { Path(gf, "PlayerFrameContent", "PlayerFrameContentMain", "StatusTexture"), true } }
        end,
        carry = function(gf)
            local c = Path(gf, "PlayerFrameContent", "PlayerFrameContentContextual")
            local main = Path(gf, "PlayerFrameContent", "PlayerFrameContentMain")
            return Found(Path(c, "AttackIcon"), Path(c, "PlayerPortraitCornerIcon"), Path(c, "LeaderIcon"),
                Path(c, "GuideIcon"), Path(c, "RoleIcon"), Path(c, "PVPIcon"), Path(c, "PrestigePortrait"),
                Path(c, "PrestigeBadge"), Path(main, "PvpBackgroundIcon"))
        end,
        -- In a vehicle the game's frame shows the vehicle, with art of its own, and with a druid's extra mana bar it
        -- takes another art (AlternatePowerFrameTexture) with the bar in its own area: both left to the game.
        usable = function(gf)
            if not (gf.unit == nil or gf.unit == "player") then return false end
            for _, region in ipairs({ Path(gf, "PlayerFrameContainer", "AlternatePowerFrameTexture"),
                                      rawget(_G, "PlayerFrameAlternatePowerBarArea") }) do
                local ok, shown = pcall(function() return region:IsShown() end)
                if ok and shown == true then return false end
            end
            return true
        end,
        down = function() return false end,
    },
    target = TargetLike("TargetFrame", "target", "target"),
    focus = TargetLike("FocusFrame", "focus", "focus"),
    -- The pet's (Mainline PetFrame.xml, its pieces global): it hangs under the player frame, so it grows down.
    pet = {
        prefix = "pet", art = "pet", as = "pet", unit = "pet",
        frame = function() return rawget(_G, "PetFrame") end,
        health = function() return rawget(_G, "PetFrameHealthBar") end,
        power = function() return rawget(_G, "PetFrameManaBar") end,
        name = function() return rawget(_G, "PetName") end,
        down = function() return true end,
        -- The hit numbers are faded by the frame they share with the name alone (PetFrame.xml): the game sets their
        -- own alpha each frame.
        fade = function(gf)
            local hit = rawget(_G, "PetHitIndicator")
            local holder = type(hit) == "table" and hit:GetParent() or nil
            if holder == gf then holder = nil end
            return Found(rawget(_G, "PetFrameTexture"), rawget(_G, "PetPortrait"), rawget(_G, "PetFrameHealthBar"),
                rawget(_G, "PetFrameManaBar"), rawget(_G, "PetName"), rawget(_G, "PetFrameFlash"), holder)
        end,
        -- From the portrait's top left corner, as the game's. Not copied where its frame cannot be faded.
        hit = function(gf)
            local hit = rawget(_G, "PetHitIndicator")
            if type(hit) ~= "table" or hit:GetParent() == gf then return nil end
            return hit, "TOPLEFT", 0, 0
        end,
        glows = function() return { { rawget(_G, "PetFrameFlash"), false } } end,
        carry = function() return {} end,
        -- In a vehicle the pet frame shows the player: left to the game.
        usable = function(gf) return gf.unit == nil or gf.unit == "pet" end,
    },
    tot = TargetOfTarget("TargetFrameToT", "targettarget"),
    focustot = TargetOfTarget("FocusFrameToT", "focustarget"),
}
-- The player's combo points, dots round the target's portrait (Camelot ComboFrame.lua, parented to TargetFrame).
SPEC.target.combo = function() return rawget(_G, "ComboFrame") end
local ORDER = { "player", "target", "focus", "pet", "tot", "focustot" }

-- A party member's frame (Mainline PartyFrameTemplates.xml, laid out by Camelot's PartyMemberFrame.lua "Player" art).
-- The game pools four of these buttons and hands them between PartyFrame.MemberFrame1..4 (PartyFrame.lua), so a
-- member's state is kept by its button (state.party) and its unit is read from the button each look. Members grow
-- down: the game stacks them 10 apart (26 with party pets), which the sliders' range stays within.
local PARTY = {
    prefix = "party", art = "party", as = "party",
    unitOf = function(gf)
        local unit = gf.unit
        if type(unit) ~= "string" or Secret(unit) or not unit:find("^party%d$") then return nil end
        return unit
    end,
    health = function(gf) return Path(gf, "HealthBarContainer", "HealthBar") end,
    power = function(gf) return Path(gf, "ManaBar") end,
    name = function(gf) return Path(gf, "Name") end,
    down = function() return true end,
    fade = function(gf)
        return Found(Path(gf, "Texture"), Path(gf, "Portrait"), Path(gf, "HealthBarContainer"), Path(gf, "ManaBar"),
            Path(gf, "Name"), Path(gf, "Flash"))
    end,
    glows = function(gf) return { { Path(gf, "Flash"), false } } end,
    carry = function(gf)
        local o = Path(gf, "PartyMemberOverlay")
        return Found(Path(o, "LeaderIcon"), Path(o, "GuideIcon"), Path(o, "PVPIcon"), Path(o, "RoleIcon"),
            Path(o, "Disconnect"))
    end,
    -- In a vehicle the button shows the vehicle's art (VehicleTexture) and unit: left to the game.
    usable = function(gf)
        local vehicle = Path(gf, "VehicleTexture")
        local ok, shown = pcall(function() return vehicle and vehicle:IsShown() end)
        return not (ok and shown == true)
    end,
}

-- The party's member buttons the game has in use now.
local function PartyMembers()
    local out, seen = {}, {}
    local party = rawget(_G, "PartyFrame")
    for i = 1, 4 do
        local gf = Path(party, "MemberFrame" .. i)
        if type(gf) == "table" and not seen[gf] then
            seen[gf] = true
            out[#out + 1] = gf
        end
    end
    return out, seen
end

local state = { party = {} }
for _, key in ipairs(ORDER) do state[key] = {} end
local driver, ticker

-- The heights asked for by a frame's settings (prefix), as how much taller than the game's each bar is. Small frames
-- start from their own bars' heights.
local BASE = { tot = { 11, 7 }, pet = { 11, 7 }, party = { 10, 7 } }
local function Heights(spec)
    local get = ns.Core.Get
    local base = BASE[spec.art] or { 20, 10 }
    local dh = (tonumber(get(spec.prefix .. "HealthHeight")) or base[1]) - base[1]
    local dp = (tonumber(get(spec.prefix .. "PowerHeight")) or base[2]) - base[2]
    return math.max(0, dh), math.max(0, dp)
end
TallFrames.BASE = BASE

local function AnyTall()
    for _, key in ipairs(ORDER) do
        local dh, dp = Heights(SPEC[key])
        if dh ~= 0 or dp ~= 0 then return true end
    end
    local dh, dp = Heights(PARTY)
    return dh ~= 0 or dp ~= 0
end

--------------------------------------------------------------------------------
-- Copying from the game's frame
--------------------------------------------------------------------------------

-- A game FontString's text, colour and whether it shows onto ours; all may be secret (a target's name in an instance),
-- and are only handed on.
-- ownAlpha: the text's own alpha copied too, for a text we never fade ourselves (the bars' texts, whose frames we fade):
-- Health Bar Text Forever fades the game's bar texts to alpha 0 and draws its own, and our copies showed the game's
-- again (seen in game, the target's "3,040 / 3,040" with that addon's percentage gone).
local function CopyText(src, dst, ownAlpha)
    if not (src and dst) then return end
    if not dst.fontCopied then
        dst.fontCopied = true
        pcall(function() dst:SetFontObject(src:GetFontObject()) end)
    end
    pcall(function() dst:SetText(src:GetText()) end)
    -- The colour only: its alpha is the text's own alpha, 0 on a game text we faded (seen in game: the name and level
    -- copies drew invisible).
    pcall(function()
        local r, g, b = src:GetTextColor()
        dst:SetTextColor(r, g, b)
    end)
    if ownAlpha then
        -- May be secret, which SetAlpha takes.
        local ok, a = pcall(src.GetAlpha, src)
        if ok and (Secret(a) or type(a) == "number") then pcall(dst.SetAlpha, dst, a) end
    end
    local ok, shown = pcall(src.IsShown, src)
    if not ok then return end
    if Secret(shown) then
        dst:Show()
        dst:SetAlphaFromBoolean(shown)
    else
        dst:SetShown(shown and true or false)
    end
end

-- How big the game draws a hit's number, as a share of its usual size (CombatFeedback_OnCombatEvent): worked out from the
-- hit, whose action and flag are readable, as a FontString does not say what SetTextHeight gave it. Second: true where
-- that is the word's size ("Absorb"), and a number's (some got through) is the usual.
local function HitSize(action, flag)
    if Secret(action) or Secret(flag) then return 1 end
    if action == "IMMUNE" then return 0.5 end
    if action == "BLOCK" then return 0.75 end
    if action == "WOUND" then
        if flag == "CRITICAL" or flag == "CRUSHING" then return 1.5 end
        if flag == "GLANCING" then return 0.75 end
        if flag == "ABSORB" or flag == "BLOCK" or flag == "RESIST" then return 0.75, true end
    elseif (action == "HEAL" or action == "ENERGIZE") and flag == "CRITICAL" then
        return 1.5
    end
    return 1
end

-- The game's hit number (a damage amount is secret, only handed on) onto ours, each frame while it shows: the game sets
-- its colour with each hit and its alpha each frame (CombatFeedback_OnUpdate). Asked whether it is visible, as the game
-- asks: an addon that hides the numbers' frame hides ours. It goes with the portrait, at the game's own size whatever
-- the ring's (asked for: not grown with it).
local function CopyHit(st)
    local src, dst = st.hit[1], st.hit[2]
    local ok, shown = pcall(src.IsVisible, src)
    if not ok or (not Secret(shown) and not shown) then
        if dst:IsShown() then dst:Hide() end
        return
    end
    CopyText(src, dst)
    if Secret(shown) then return end
    local scale = st.f.tall and st.f.tall.scale or 1
    local size = st.hitSize or 1
    -- A number's text is secret and a word's is not, unless a text once secret stays so: told by having read one since.
    local okText, text = pcall(src.GetText, src)
    if okText and Secret(text) then
        st.hitSecret = true
        if st.hitWord and st.hitClears then size = 1 end
    elseif okText and st.hitSecret then
        st.hitClears = true
    end
    local h = (Number(st.gf.feedbackFontHeight) or 30) * size
    if dst.hitHeight ~= h then
        dst.hitHeight = h
        dst:SetTextHeight(h)
    end
    if dst.hitScale ~= scale then
        dst.hitScale = scale
        dst:SetPoint(st.hit[3], st.f.portrait, st.hit[3], st.hit[4] * scale, st.hit[5] * scale)
    end
    pcall(function() dst:SetAlpha(src:GetAlpha()) end)
end

-- The combo points, drawn round our ring by dots of the game's own template (RogueComboPointTemplate), lit as the
-- game's are. The game's dots are faded, not their frame: the frame fades itself in (UIFrameFadeIn sets its alpha each
-- frame), while nothing of the game's sets a dot's own alpha, only its textures'. Left alone while another addon has
-- moved the points off the portrait, and where the client has no such template.
local function BuildCombo(st)
    local cf = st.spec.combo and st.spec.combo()
    if type(cf) ~= "table" or type(cf.ComboPoints) ~= "table" then return end
    local ok, combo = pcall(function()
        -- In the game's own strata and level for them, over the portrait and the level circle.
        local host = CreateFrame("Frame", nil, st.f)
        host:SetSize(1, 1)
        host:SetFrameStrata(cf:GetFrameStrata())
        host:SetFrameLevel(cf:GetFrameLevel())
        host:Hide()
        local points = {}
        for i, game in ipairs(cf.ComboPoints) do
            local p = CreateFrame("Frame", nil, host, "RogueComboPointTemplate")
            p:Setup()
            p:Hide()
            points[i] = { game = game, ours = p }
        end
        return { frame = cf, host = host, points = points }
    end)
    if ok then st.combo = combo end
end

-- The game's dots faded (0) or given back (1).
local function FadeCombo(c, alpha)
    for _, p in ipairs(c and c.points or {}) do pcall(p.game.SetAlpha, p.game, alpha) end
end

-- Their places, each poll: as the game lays its own out (which moves with the PvP icon), grown with the ring.
local function LayoutCombo(st)
    local c = st.combo
    local okAt, _, rel, _, x0, y0 = pcall(c.frame.GetPoint, c.frame, 1)
    c.on = okAt and rel ~= nil and rel == Path(st.gf, "TargetFrameContainer", "Portrait")
        and c.frame:GetParent() == st.gf
    if not c.on then
        c.host:Hide()
        FadeCombo(c, 1)
        return
    end
    local s = st.f.tall and st.f.tall.scale or 1
    c.host:SetPoint("CENTER", st.f.portrait, "CENTER", (x0 or 0) * s, (y0 or 0) * s)
    for _, p in ipairs(c.points) do
        local ok, _, _, _, x, y = pcall(p.game.GetPoint, p.game, 1)
        p.placed = ok and Number(x) ~= nil and Number(y) ~= nil
        if p.placed then
            p.ours:SetScale((Number(p.game:GetScale()) or 1) * s) -- a scaled frame's offsets are in its own units
            p.ours:SetPoint("CENTER", c.host, "CENTER", x, y)
        end
    end
    FadeCombo(c, 0)
end

-- Lit and shown as the game's are, each frame. A dot that lights or goes out does so with the game's animation only
-- while the game's own plays it (a new target's points change at once).
local function MirrorCombo(c)
    if not c.on then return end
    local shown = c.frame:IsShown()
    if Secret(shown) then
        c.host:Show()
        c.host:SetAlphaFromBoolean(shown)
    elseif not shown then
        if c.host:IsShown() then c.host:Hide() end
        return
    else
        c.host:Show()
        c.host:SetAlpha(c.frame:GetAlpha())
    end
    for _, p in ipairs(c.points) do
        local game, ours = p.game, p.ours
        local has = game:IsShown()
        has = p.placed and (Secret(has) or has) and true or false
        if has ~= ours:IsShown() then ours:SetShown(has) end
        local full = game.isFull
        if Secret(full) then
            -- Lit or not without knowing which, with no animation.
            p.full = nil
            ours.IconUncharged:SetAlphaFromBoolean(full, 1, 0)
            ours.BGActive:SetAlphaFromBoolean(full, 1, 0)
            ours.BGInactive:SetAlphaFromBoolean(full, 0, 1)
        elseif has and full ~= nil and p.full ~= full then
            p.full = full
            local anim = game[full and "unchargedEmptyToUnchargedFull" or "unchargedFullToUnchargedEmpty"]
            if anim and anim:IsPlaying() then
                ours:SetActive(full)
            else
                ours:SetActiveNoAnimation(full)
            end
        end
    end
end

-- Where a point on the game's frame (frame units from its top-left, y down) is on ours: round the portrait it goes with
-- the ring, moved and grown (Preview.TallArt's Moved); above the health slot's middle it stays with the name row, below
-- the power slot's middle it is the frames' growth lower, with the power row, and between them the health's growth.
local function Place(st, x, y)
    local g = ns.Preview.TALL[st.spec.art]
    local cx, cy, R = g.ring[1], g.ring[2], g.ring[3]
    if g.mirror then cx = (st.f:GetWidth() or 232) - cx end
    local tall = st.f.tall
    if tall and (x - cx) ^ 2 + (y - cy) ^ 2 <= (R + 14) ^ 2 then
        local nx, ny = tall.Moved(x, y)
        return nx, ny, tall.scale
    end
    if y < g.health[1] then return x, y, 1 end
    if y < g.power[1] then return x, y + st.dh, 1 end
    return x, y + st.dh + st.dp, 1
end

-- How many of the game frame's units one of region's is. A region with a scale of its own (the player's PvP badge,
-- PlayerPvpBackgroundIconTemplate's scale="0.8") answers its place and size in its own units: taken as the frame's,
-- the badge was drawn far up and right of the frame (seen in game).
local function ScaleTo(region, gf)
    local ok, a, b = pcall(function() return region:GetEffectiveScale(), gf:GetEffectiveScale() end)
    a, b = ok and Number(a), ok and Number(b)
    if a and b and a > 0 and b > 0 then return a / b end
    return 1
end

-- A game texture drawn by ours: its atlas (or file and texture coordinates), colour and shown state, at the place it
-- has on the game's frame moved as Place says. Read each poll: the game moves and swaps these (an elite's dragon, a raid
-- target's icon).
local function CopyTexture(st, src, dst)
    local gf = st.gf
    local ok = pcall(function()
        local atlas = src.GetAtlas and src:GetAtlas()
        if atlas and not Secret(atlas) and atlas ~= "" then
            if dst.atlas ~= atlas then
                dst:SetAtlas(atlas)
                dst.atlas = atlas
            end
        else
            dst.atlas = nil
            dst:SetTexture(src:GetTexture())
            dst:SetTexCoord(src:GetTexCoord())
        end
        local r, g, b = src:GetVertexColor()
        dst:SetVertexColor(r, g, b)
        local left, top, w, h = src:GetLeft(), src:GetTop(), src:GetWidth(), src:GetHeight()
        local fl, ft = gf:GetLeft(), gf:GetTop()
        if not (left and top and w and h and fl and ft) or Secret(left) or Secret(top) or Secret(w) or Secret(h) then
            dst:Hide()
            return
        end
        local k = ScaleTo(src, gf)
        left, top, w, h = left * k, top * k, w * k, h * k
        local x, y, s = Place(st, left - fl + w / 2, ft - top + h / 2)
        dst:ClearAllPoints()
        dst:SetSize(w * s, h * s)
        dst:SetPoint("CENTER", st.f, "TOPLEFT", x, -y)
        local shown = src:IsShown()
        if Secret(shown) then
            dst:Show()
            dst:SetAlphaFromBoolean(shown)
        else
            dst:SetShown(shown and true or false)
        end
    end)
    if not ok then dst:Hide() end
end

-- A game glow drawn by ours (Preview.TallGlow): laid out again when our frame's heights, the glow's atlas or its place on
-- the game's frame change, and given its colour and blend mode.
local function CopyGlow(st, glow)
    local src, gf = glow.src, st.gf
    pcall(function()
        local atlas = src:GetAtlas()
        local left, top, fl, ft = src:GetLeft(), src:GetTop(), gf:GetLeft(), gf:GetTop()
        if not atlas or Secret(atlas) or not (left and top and fl and ft) or Secret(left) or Secret(top) then return end
        local k = ScaleTo(src, gf)
        local x0, y0 = left * k - fl, ft - top * k
        local key = table.concat({ atlas, math.floor(x0 * 10 + 0.5), math.floor(y0 * 10 + 0.5), st.dh, st.dp }, ",")
        if glow.key ~= key then
            glow.key = key
            glow.host = ns.Preview.TallGlow(st.f, glow.i, atlas, x0, y0)
        end
        local host = glow.host
        if not host then return end
        local r, g, b = src:GetVertexColor()
        local mode = src:GetBlendMode()
        for _, tex in ipairs(host.slices or {}) do
            tex:SetVertexColor(r, g, b)
            tex:SetBlendMode(mode)
        end
        if host.ringTex then
            host.ringTex:SetVertexColor(r, g, b)
            host.ringTex:SetBlendMode(mode)
        end
    end)
end

-- A glow's shown state and alpha, each frame: the game pulses some (the player's status glow). A glow whose parent
-- we faded keeps its own alpha to copy; one we faded itself shows at full strength.
local function GlowAlpha(glow)
    local host = glow.host
    if not host then return end
    local ok, shown = pcall(glow.src.IsShown, glow.src)
    if not ok then return end
    if Secret(shown) then
        host:Show()
        host:SetAlphaFromBoolean(shown)
        return
    end
    host:SetShown(shown and true or false)
    if shown and glow.parentFaded then
        local okAlpha, alpha = pcall(glow.src.GetAlpha, glow.src)
        if okAlpha and alpha ~= nil then host:SetAlpha(alpha) end
    end
end

--------------------------------------------------------------------------------
-- The game's segments on its bars
--------------------------------------------------------------------------------

-- The game's heal prediction (its own and others'), heal absorb and absorb segments on a health bar, and the player's
-- mana cost prediction on the power bar (StatusBarOverlaySegmentTemplate, Shared/UnitFrame.xml), each found on the
-- bar (its parentKey) or on the frame (UnitFrame_Initialize keeps them there; the pet's have only global names). They
-- are children of the game's bar, so they were faded with it. Ours copy them onto our bar under the same keys, so the
-- heal marker (HealMarker.lua) and the shield (Shield.lua) find and hide them there as they do on the game's.
local SEGMENTS = {
    health = { { "MyHealPredictionBar", "myHealPredictionBar" }, { "OtherHealPredictionBar", "otherHealPredictionBar" },
               { "HealAbsorbBar", "healAbsorbBar" }, { "TotalAbsorbBar", "totalAbsorbBar" } },
    power = { { "ManaCostPredictionBar", "myManaCostPredictionBar" } },
}
-- The glows at the health bar's ends (UnitFrame_Initialize anchors them): more absorb than missing health, 7 in from
-- the right end; more heal absorb than health, 7 in from the left. The bar's height, 16 wide (OverAbsorbGlowTemplate).
local GLOWS = { { "OverAbsorbGlow", "overAbsorbGlow", "RIGHT", -7 }, { "OverHealAbsorbGlow", "overHealAbsorbGlow", "LEFT", 7 } }
local SQUARE = "Interface\\AddOns\\SmoothAnimatedBars\\Media\\Square"

-- A game texture's look on ours: its atlas, or its file (tiled, or with its texture coordinates), its colour and blend
-- mode. Its alpha is left alone: the heal marker and the shield set it on ours as they do on the game's.
local function Look(src, dst, tile)
    -- The colour only when it changes (a secret one once): whether the client keeps a texture's alpha when it is given
    -- a colour without one is not known, and the heal marker and the shield set that alpha on ours. Its alpha is not
    -- copied: the game's may be the heal marker's 0 from before the frame grew (its marker pauses on the faded bar).
    local okColor, r, g, b = pcall(src.GetVertexColor, src)
    if okColor then
        if Secret(r) or Secret(g) or Secret(b) then
            if dst.colorSecret ~= true then
                dst.colorSecret = true
                pcall(dst.SetVertexColor, dst, r, g, b)
            end
        elseif dst.colorSecret ~= false or dst.cr ~= r or dst.cg ~= g or dst.cb ~= b then
            dst.colorSecret, dst.cr, dst.cg, dst.cb = false, r, g, b
            pcall(dst.SetVertexColor, dst, r, g, b)
        end
    end
    local okMode, mode = pcall(src.GetBlendMode, src)
    if okMode and type(mode) == "string" and mode ~= dst.blendCopied then
        dst.blendCopied = mode
        pcall(dst.SetBlendMode, dst, mode)
    end
    local okAtlas, atlas = pcall(src.GetAtlas, src)
    if okAtlas and atlas and not Secret(atlas) and atlas ~= "" then
        if dst.atlas ~= atlas and pcall(dst.SetAtlas, dst, atlas) then dst.atlas, dst.file = atlas, nil end
        return
    end
    local okFile, file = pcall(src.GetTexture, src)
    if okFile and file ~= nil and not Secret(file) and dst.file ~= file then
        if tile then pcall(dst.SetTexture, dst, file, "REPEAT", "REPEAT") else pcall(dst.SetTexture, dst, file) end
        dst.atlas, dst.file = nil, file
        -- A tiled overlay's coordinates come from the segment's (secret) width: ours tiles by its own size instead. A
        -- file's coordinates are taken with it (a shadow's are flipped).
        if not tile then pcall(function() dst:SetTexCoord(src:GetTexCoord()) end) end
    end
end

-- A game region's shown state onto ours. A secret one shows ours faded by it, which only a region nobody else fades
-- may take (alphaFree): the shield sets the absorb overlay's alpha.
local function Mirror(src, dst, alphaFree)
    local ok, shown = pcall(src.IsShown, src)
    if not ok then return end
    if Secret(shown) then
        if dst.mirrored ~= "secret" then
            dst.mirrored = "secret"
            dst:Show()
        end
        if alphaFree then dst:SetAlphaFromBoolean(shown) end
        return
    end
    shown = shown and true or false
    if dst.mirrored ~= shown then
        if dst.mirrored == "secret" and alphaFree then dst:SetAlpha(1) end
        dst.mirrored = shown
        dst:SetShown(shown)
    end
end

-- A copy of the game's segment src on our bar: a frame a level above the bar and its liquid (the game's draw over its
-- fill), under our texts. The game shows a stretch of a bar-wide fill through a mask (FillMask) from the fill's edge,
-- its width from the (secret) amount; ours shows the same fill through a mask over a box laid on the game's mask: as
-- wide and as far along (our bars are the game's width), but our bar's height. Its overlays (the absorb's tiled lines,
-- the heal absorb's shadows) go on the box, as the game's go on its mask.
local function NewSegment(bar, src)
    local seg = CreateFrame("Frame", nil, bar)
    seg:SetAllPoints(bar)
    seg:Hide()
    -- The game's segment it copies: whether it shows may be secret, which ours can only fade by, so the heal marker asks
    -- the game's (HealMarker.lua, GameOthers).
    seg.MirrorOf = src
    seg.box = CreateFrame("Frame", nil, seg)
    local clip = seg:CreateMaskTexture()
    clip:SetTexture(SQUARE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    clip:SetAllPoints(seg.box)
    local slot = bar.HealthBarMask or bar.ManaBarMask
    local function Tex(sublevel, cut)
        local t = seg:CreateTexture(nil, "ARTWORK", nil, sublevel)
        if cut then t:AddMaskTexture(clip) end
        if slot then t:AddMaskTexture(slot) end
        return t
    end
    seg.Fill = Tex(1, true)
    seg.Fill:SetAllPoints(bar)
    seg.overlays = {}
    if type(src.TiledFillOverlay) == "table" then
        local t = Tex(2)
        t:SetAllPoints(seg.box)
        pcall(t.SetHorizTile, t, true)
        pcall(t.SetVertTile, t, true)
        seg.TiledFillOverlay = t
        seg.overlays[#seg.overlays + 1] = { src = src.TiledFillOverlay, dst = t, tile = true }
    end
    for _, side in ipairs({ "LeftShadow", "RightShadow" }) do
        if type(src[side]) == "table" then
            local t = Tex(2)
            -- The game's have no size of their own: a width of 0 (the file not loaded yet) takes the file's 8.
            local ok, w = pcall(src[side].GetWidth, src[side])
            w = ok and Number(w) or 0
            if w <= 0 then w = 8 end
            if side == "LeftShadow" then
                t:SetPoint("TOPLEFT", seg.box, "TOPLEFT")
                t:SetPoint("BOTTOMLEFT", seg.box, "BOTTOMLEFT")
            else
                t:SetPoint("TOPLEFT", seg.box, "TOPRIGHT", -8, 0)
                t:SetPoint("BOTTOMLEFT", seg.box, "BOTTOMRIGHT", -8, 0)
            end
            t:SetWidth(w)
            seg[side] = t
            seg.overlays[#seg.overlays + 1] = { src = src[side], dst = t, alphaFree = true }
        end
    end
    return seg
end

-- A copy of a glow at the bar's end: a texture in a frame of its own, which shows as the game's does.
local function NewGlow(bar, src, side, x)
    local host = CreateFrame("Frame", nil, bar)
    host:SetAllPoints(bar)
    host:Hide()
    local t = host:CreateTexture(nil, "ARTWORK", nil, 3)
    if side == "RIGHT" then
        t:SetPoint("TOPLEFT", bar, "TOPRIGHT", x, 0)
        t:SetPoint("BOTTOMLEFT", bar, "BOTTOMRIGHT", x, 0)
    else
        t:SetPoint("TOPRIGHT", bar, "TOPLEFT", x, 0)
        t:SetPoint("BOTTOMRIGHT", bar, "BOTTOMLEFT", x, 0)
    end
    local ok, w = pcall(src.GetWidth, src)
    t:SetWidth(ok and Number(w) or 16)
    -- Cut by the bar's slot as the game cuts its own (PlayerFrame.xml, TargetFrame.xml): 9 of its 16 lie past the bar's
    -- end, over the frame's gold art.
    local slot = bar.HealthBarMask
    if slot then t:AddMaskTexture(slot) end
    return host, t
end

-- Copies of the game's segments and glows onto our bars, as st.segments: { src, game (its bar), bar (ours), seg or
-- host and tex }.
local function BuildSegments(st)
    st.segments = {}
    for kind, list in pairs(SEGMENTS) do
        local game, ours = st.bars[kind], st.f[kind]
        for _, keys in ipairs(list) do
            local src = Path(game, keys[1]) or Path(st.gf, keys[2])
            if type(src) == "table" and type(src.Fill) == "table" and src.IsShown then
                local seg = NewSegment(ours, src)
                ours[keys[1]] = seg
                st.segments[#st.segments + 1] = { src = src, game = game, bar = ours, seg = seg }
            end
        end
    end
    local game, ours = st.bars.health, st.f.health
    for _, g in ipairs(GLOWS) do
        local src = Path(game, g[1]) or Path(st.gf, g[2])
        if type(src) == "table" and src.IsShown and src.GetTexture then
            local host, tex = NewGlow(ours, src, g[3], g[4])
            ours[g[1]] = tex
            st.segments[#st.segments + 1] = { src = src, game = game, bar = ours, host = host, tex = tex }
        end
    end
end

-- Lays a segment's box on the game's mask, moved by how far our bar is from the game's and as tall as ours: again only
-- when that changes.
local function Box(s)
    local mask = s.src.FillMask
    if type(mask) ~= "table" then return end
    local ok, dx, dy, h = pcall(function()
        local gl, gt = Number(s.game:GetLeft()), Number(s.game:GetTop())
        local ol, ot, oh = Number(s.bar:GetLeft()), Number(s.bar:GetTop()), Number(s.bar:GetHeight())
        if not (gl and gt and ol and ot and oh) then return nil end
        return ol - gl, ot - gt, oh
    end)
    if not ok or not dx then return end
    local key = string.format("%.1f,%.1f,%.1f", dx, dy, h)
    if s.boxKey == key then return end
    s.boxKey = key
    local box = s.seg.box
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT", mask, "TOPLEFT", dx, dy)
    box:SetPoint("BOTTOMRIGHT", mask, "TOPRIGHT", dx, dy - h)
end

-- Each poll: the segments' looks and places.
local function CopySegments(st)
    for _, s in ipairs(st.segments) do
        if s.seg then
            Look(s.src.Fill, s.seg.Fill)
            for _, o in ipairs(s.seg.overlays) do Look(o.src, o.dst, o.tile) end
            Box(s)
        else
            Look(s.src, s.tex)
        end
    end
end

-- Each frame: shown as the game's are (the game shows and hides them as heals and absorbs come and go).
local function MirrorSegments(st)
    for _, s in ipairs(st.segments) do
        if s.seg then
            Mirror(s.src, s.seg, true)
            for _, o in ipairs(s.seg.overlays) do Mirror(o.src, o.dst, o.alphaFree) end
        else
            Mirror(s.src, s.host, true)
        end
    end
end

-- A text on our bar where the game's is on its bar: the same point and offset from the bar (or its container).
local function PlaceText(src, dst, bar)
    local ok, point, _, relPoint, x, y = pcall(src.GetPoint, src, 1)
    if not ok or type(point) ~= "string" or Secret(point) or Secret(x) or Secret(y) then
        point, relPoint, x, y = "CENTER", "CENTER", 0, 0
    end
    dst:ClearAllPoints()
    dst:SetPoint(point, bar, relPoint or point, x or 0, y or 0)
end

local function Fade(list, alpha)
    for _, region in ipairs(list) do
        if region and region.SetAlpha then pcall(region.SetAlpha, region, alpha) end
    end
end

--------------------------------------------------------------------------------
-- Our frame
--------------------------------------------------------------------------------

local function Portrait(st)
    if st.f and st.unit and SetPortraitTexture then pcall(SetPortraitTexture, st.f.portrait, st.unit) end
end

-- Whether an event changes who a frame shows, and so its portrait: a new target or focus (and with it their targets),
-- a unit's new target (UNIT_TARGET for "target" is a new target of target: no portrait event comes for that, seen in
-- game as a target of target showing the one before's face), the party's roster, or a unit's own portrait.
local function Changes(st, event, unit)
    local u = st.unit
    if not u then return false end
    if event == "PLAYER_TARGET_CHANGED" then return u == "target" or u == "targettarget" end
    if event == "PLAYER_FOCUS_CHANGED" then return u == "focus" or u == "focustarget" end
    if event == "UNIT_TARGET" then return type(unit) == "string" and u == unit .. "target" end
    if event == "GROUP_ROSTER_UPDATE" then return u:find("^party") ~= nil end
    return unit == u
end

-- Our frame on the game's: by its bottom edge, so it grows upward, or by its top when it grows down (SPEC.down).
local function Anchor(st)
    local down = st.spec.down(st.gf) and true or false
    if st.f.down == down then return end
    st.f.down = down
    st.f:ClearAllPoints()
    if down then
        st.f:SetPoint("TOPLEFT", st.gf, "TOPLEFT", 0, 0)
    else
        st.f:SetPoint("BOTTOMLEFT", st.gf, "BOTTOMLEFT", 0, 0)
    end
end

local function Build(st)
    local f = ns.Preview.LiveFrame(st.gf, st.spec.art, st.spec.as)
    st.f = f
    Anchor(st)
    -- The game's bars' texts, onto ours.
    st.texts, st.textCopy, st.others = {}, {}, {}
    for _, kind in ipairs({ "health", "power" }) do
        local game, ours = st.bars[kind], f[kind]
        local centre, left, right = BarTexts(game)
        for _, p in ipairs({ { centre, ours.text }, { left, ours.left }, { right, ours.right } }) do
            if type(p[1]) == "table" and p[1].GetText then
                PlaceText(p[1], p[2], ours)
                st.texts[#st.texts + 1] = { p[1], p[2], true }
                st.textCopy[p[1]] = p[2]
            else
                p[2]:Hide()
            end
        end
    end
    for _, src in ipairs(st.spec.extraTexts and st.spec.extraTexts(st.gf) or {}) do
        if src.GetText then
            local dst = f.top:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            dst:SetPoint("CENTER", f.health, "CENTER", 0, 0)
            st.texts[#st.texts + 1] = { src, dst }
        end
    end
    -- The icons round the portrait, each on our frame's top layer, above its art and bars.
    st.carried = {}
    for _, src in ipairs(st.spec.carry(st.gf)) do
        if src.GetObjectType and src:GetObjectType() == "Texture" then
            local ok, layer, sub = pcall(src.GetDrawLayer, src)
            local dst = f.top:CreateTexture(nil, ok and layer or "OVERLAY", nil, ok and sub or 0)
            dst:Hide()
            st.carried[#st.carried + 1] = { src, dst }
        end
    end
    -- Texts beside a carried icon, anchored to our copy of it as the game's are to its own.
    for _, t in ipairs(st.spec.follow and st.spec.follow(st.gf) or {}) do
        local src, icon = t[1], t[2]
        local iconCopy
        for _, p in ipairs(st.carried) do
            if p[1] == icon then iconCopy = p[2] end
        end
        if type(src) == "table" and src.GetText and iconCopy then
            local dst = f.top:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            dst:SetPoint(t[3], iconCopy, t[4], t[5], t[6])
            st.texts[#st.texts + 1] = { src, dst }
        end
    end
    -- The hit numbers, over our portrait where the game's are over its own.
    local hitSrc, at, hx, hy
    if st.spec.hit then hitSrc, at, hx, hy = st.spec.hit(st.gf) end
    if type(hitSrc) == "table" and hitSrc.GetText then
        local dst = f.top:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        pcall(dst.SetDrawLayer, dst, "OVERLAY", 7) -- over the icons round the portrait, as the game's (a level up)
        dst:Hide()
        st.hit = { hitSrc, dst, at, hx, hy }
        local hits = CreateFrame("Frame")
        hits:RegisterUnitEvent("UNIT_COMBAT", st.unit)
        hits:SetScript("OnEvent", function(_, _, _, action, flag) st.hitSize, st.hitWord = HitSize(action, flag) end)
    end
    -- The game's glows over the art.
    st.glows = {}
    for i, g in ipairs(st.spec.glows and st.spec.glows(st.gf) or {}) do
        if type(g[1]) == "table" and g[1].GetAtlas then
            st.glows[#st.glows + 1] = { src = g[1], parentFaded = g[2], i = i }
        end
    end
    local glows = st.glows
    BuildCombo(st)
    BuildSegments(st)
    f:SetScript("OnUpdate", function()
        for _, glow in ipairs(glows) do GlowAlpha(glow) end
        MirrorSegments(st)
        if st.hit then CopyHit(st) end
        if st.combo and not st.combo.err then
            local ok, err = pcall(MirrorCombo, st.combo)
            if not ok then
                -- The game's own dots come back, where the game has them.
                st.combo.err = tostring(err)
                st.combo.host:Hide()
                FadeCombo(st.combo, 1)
            end
        end
        -- The bars' values every frame, handed from the game's bars to ours (secret, never read).
        for kind, game in pairs(st.bars) do
            local ours = f[kind]
            pcall(function()
                ours:SetMinMaxValues(game:GetMinMaxValues())
                ours:SetValue(game:GetValue())
            end)
        end
    end)
end

-- Its bars handed to the liquid with the frame's own settings (playerHealth... and its colour and effects).
local function Hand(st)
    for _, kind in ipairs({ "health", "power" }) do
        local bar = st.f[kind]
        local key = st.spec.as .. (kind == "health" and "Health" or "Power")
        local options = { theme = "settings", level = 0, spill = true, name = OPTIONS_NAME,
                          mask = bar[kind == "health" and "HealthBarMask" or "ManaBarMask"] }
        -- Who it shows, as the game puts it on its bars (UnitFrame_SetUnit): the heal marker reads a party bar's unit.
        bar.unit = st.unit
        -- Game Colour on it is the game's, as on the frame it stands for (Bars.lua, GameColor).
        ns.Bars.tall[bar] = true
        local ok, err = pcall(ns.Bars.AddBar, bar, st.unit, kind, options, key)
        if not ok and not st.reported then
            st.reported = true
            ns.Core.Print("Bar Height: " .. tostring(err))
        end
    end
    -- The heal marker on our bars as on the game's, built once each bar has its liquid. A player's bar handed over
    -- asks for it itself (Bars.AddBar); a party member's is asked for here, until it has one.
    local health = st.f.health
    if st.which == "party" and ns.HealMarker and ns.HealMarker.Has and not ns.HealMarker.Has(health) then
        pcall(ns.HealMarker.Apply)
    end
end

-- Texts other addons put on the game's bars (Health Bar Text Forever: bar:CreateFontString on each, the target of
-- target's too, where the game has none), faded with the bars under ours (seen in game: that addon's text gone from a
-- taller target of target). Each is copied onto our bar, found as they come (an addon may add its own after ours is
-- built), placed as theirs is against our copy of the game text it hangs on (that addon puts its side texts on the
-- game's LeftText and RightText) or else our bar, in its own font and size (it sets 8 on the small frames).
function TallFrames.OtherTexts(st)
    for kind, game in pairs(st.bars) do
        local ours = st.f[kind]
        local ok, regions = pcall(function() return { game:GetRegions() } end)
        if ok and ours and ours.text then
            for _, r in ipairs(regions) do
                local okType, objType = pcall(r.GetObjectType, r)
                if okType and objType == "FontString" and not st.textCopy[r] then
                    local dst = st.others[r]
                    if not dst then
                        dst = ours.text:GetParent():CreateFontString(nil, "OVERLAY", "TextStatusBarText")
                        dst.fontCopied = true
                        st.others[r] = dst
                        local okP, point, rel, relPoint, x, y = pcall(r.GetPoint, r, 1)
                        if not okP or type(point) ~= "string" or Secret(point) or Secret(x) or Secret(y) then
                            point, rel, relPoint, x, y = "CENTER", nil, "CENTER", 0, 0
                        end
                        local to = (rel ~= nil and st.textCopy[rel]) or ours
                        dst:SetPoint(point, to, relPoint or point, x or 0, y or 0)
                    end
                    pcall(function() dst:SetFont(r:GetFont()) end)
                    CopyText(r, dst, true)
                end
            end
        end
    end
end

-- The copies from the game's frame, each poll while ours shows.
local function Copy(st)
    local f = st.f
    for _, p in ipairs(st.texts) do CopyText(p[1], p[2], p[3]) end
    TallFrames.OtherTexts(st)
    local nameSrc = st.spec.name(st.gf)
    CopyText(nameSrc, f.nameText)
    -- A new name the game shows is a new face too, whatever event was missed (a secret name is never compared).
    local okName, name = pcall(function() return nameSrc:GetText() end)
    if okName and type(name) == "string" and not Secret(name) and name ~= st.lastName then
        st.lastName = name
        Portrait(st)
    end
    if st.spec.level then CopyText(st.spec.level(st.gf), f.levelText) end
    if f.banner and st.spec.banner then
        local src = st.spec.banner(st.gf)
        if src then
            pcall(function()
                local r, g, b = src:GetVertexColor()
                f.banner:SetVertexColor(r, g, b)
            end)
        end
    end
    for _, p in ipairs(st.carried) do CopyTexture(st, p[1], p[2]) end
    for _, glow in ipairs(st.glows) do CopyGlow(st, glow) end
    CopySegments(st)
    if st.combo and not st.combo.err then LayoutCombo(st) end
    -- With the liquid off, our bars show a fill as the game's does: its texture and colour.
    for kind, game in pairs(st.bars) do
        local ours = f[kind]
        if not ns.Bars.IsLive(ours) then
            pcall(function()
                local tex = game:GetStatusBarTexture()
                local atlas = tex and tex:GetAtlas()
                if atlas and not Secret(atlas) and atlas ~= "" and ours.fillAtlas ~= atlas then
                    ours.fill:SetAtlas(atlas)
                    ours.fillAtlas = atlas
                end
                local r, g, b = game:GetStatusBarColor()
                ours.fill:SetVertexColor(r, g, b)
            end)
        end
    end
    -- What the game fades or restores of its own (a raid target icon shown anew) stays faded while ours shows.
    Fade(st.faded, 0)
    for _, p in ipairs(st.carried) do pcall(p[1].SetAlpha, p[1], 0) end
end

local function Show(st, dh, dp)
    if not st.f then Build(st) end
    Anchor(st)
    local changed = st.dh ~= dh or st.dp ~= dp or not st.shown
    st.dh, st.dp = dh, dp
    if changed then
        if not ns.Preview.SetFrameTall(st.f, dh, dp) then return false end
    end
    if not st.shown then
        st.shown = true
        st.faded = st.spec.fade(st.gf)
        st.f:Show()
    end
    -- Handed over again, with its portrait, whenever the button's unit changes (a party member's moved).
    if st.handed ~= st.unit then
        st.handed = st.unit
        Portrait(st)
        Hand(st)
    end
    Copy(st)
    return true
end

local function HideOurs(st)
    if not st.shown then return end
    st.shown = false
    st.dh, st.dp, st.handed = nil, nil, nil
    Fade(st.faded or {}, 1)
    for _, p in ipairs(st.carried or {}) do pcall(p[1].SetAlpha, p[1], 1) end
    FadeCombo(st.combo, 1)
    for _, kind in ipairs({ "health", "power" }) do pcall(ns.Bars.RemoveBar, st.f[kind]) end
    st.f:Hide()
end

-- Whether a frame wants ours, and how much taller its bars are.
local function Wanted(st)
    local dh, dp = Heights(st.spec)
    if dh == 0 and dp == 0 then return false end
    -- Only an art that has been measured (Preview.TALL) can be laid out taller.
    if not ns.Preview.TALL[st.spec.art] then return false end
    local gf = st.button or st.spec.frame()
    if not gf then return false end
    st.unit = st.spec.unitOf and st.spec.unitOf(gf) or st.spec.unit
    if not st.unit then return false end
    local health, power = st.spec.health(gf), st.spec.power(gf)
    if not (health and power) then return false end
    if st.spec.usable and not st.spec.usable(gf) then return false end
    local L = ns.Preview.LAYOUT[st.spec.art]
    if not ns.Preview.AtlasPlace(L.art, L.size and L.size[1], L.size and L.size[2], L.artAt) then return false end
    st.gf, st.bars = gf, { health = health, power = power }
    return true, dh, dp
end

-- One frame's look: shown taller, or the game's given back.
local function LookAt(st, inUse)
    local want, dh, dp = false, 0, 0
    if inUse ~= false then want, dh, dp = Wanted(st) end
    if want and not st.f and InCombatLockdown() then want = false end -- built out of combat, as children of secure frames
    local ok, err = pcall(function()
        if want then
            if not Show(st, dh, dp) then HideOurs(st) end
        else
            HideOurs(st)
        end
    end)
    if not ok and not st.reported then
        st.reported = true
        ns.Core.Print("Bar Height: " .. tostring(err))
    end
end

local function Look()
    if not (ns.Core.ready and ns.Preview and ns.Preview.SetFrameTall) then return end
    for _, key in ipairs(ORDER) do
        local st = state[key]
        st.which, st.spec = key, SPEC[key]
        LookAt(st)
    end
    -- The party: each button the game has had in use, taller while it is in use now.
    local members, inUse = PartyMembers()
    for _, gf in ipairs(members) do
        state.party[gf] = state.party[gf] or { which = "party", spec = PARTY, button = gf }
    end
    for gf, st in pairs(state.party) do LookAt(st, inUse[gf] or false) end
    -- Nothing taller any more: stop looking.
    if not AnyTall() and ticker then
        ticker:Cancel()
        ticker = nil
    end
end
TallFrames.Look = Look

-- After a height setting changes, and at PLAYER_ENTERING_WORLD (SmoothAnimatedBars.lua): look now, and every POLL
-- seconds while any bar is taller.
function TallFrames.Apply()
    if not ns.Core.ready then return end
    if not driver then
        driver = CreateFrame("Frame")
        for _, event in ipairs({ "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "UNIT_TARGET", "UNIT_PORTRAIT_UPDATE",
                                 "GROUP_ROSTER_UPDATE" }) do
            driver:RegisterEvent(event)
        end
        driver:SetScript("OnEvent", function(_, event, unit)
            for _, key in ipairs(ORDER) do
                local st = state[key]
                if st.shown and Changes(st, event, unit) then Portrait(st) end
            end
            for _, st in pairs(state.party) do
                if st.shown and Changes(st, event, unit) then Portrait(st) end
            end
        end)
    end
    Look()
    if AnyTall() and not ticker then ticker = C_Timer.NewTicker(POLL, Look) end
end
TallFrames.Start = TallFrames.Apply

-- For /sab debug and the tests: each frame's state.
function TallFrames.State()
    return state
end

-- Every frame's state, the party members' too.
local function EachState(fn)
    for _, key in ipairs(ORDER) do fn(state[key]) end
    for _, st in pairs(state.party) do fn(st) end
end

-- Our bars, built or not shown: { bar, kind, which ("player", "party"...) }. For the heal marker, which builds on each
-- as on the game's bars (its party markers read the unit off the bar, as there).
function TallFrames.Bars()
    local out = {}
    EachState(function(st)
        if st.f then
            for _, kind in ipairs({ "health", "power" }) do
                out[#out + 1] = { bar = st.f[kind], kind = kind, which = st.which }
            end
        end
    end)
    return out
end

-- Whether a bar is one of ours.
function TallFrames.Owns(bar)
    local found = false
    EachState(function(st)
        if st.f and (st.f.health == bar or st.f.power == bar) then found = true end
    end)
    return found
end

-- Our player frame's health bar while it shows in place of the game's, else nil: the shield and Weakened Soul are
-- drawn on it then.
function TallFrames.PlayerHealth()
    local st = state.player
    return st.shown and st.f and st.f.health or nil
end
