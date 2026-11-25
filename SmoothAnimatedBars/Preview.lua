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

-- Forever's frames, in frame units from the top-left (y down is negative), each 232 x 100 unless its size says.
-- Target: the health bar sits 3 above its container, which ends at the frame's left middle + (147, -9);
-- the mana bar hangs below the container's right end (+4, -1). The focus is the target's template.
-- The small frames, the pet's (Mainline PetFrame.xml) and the targets of target (TargetFrame.xml's
-- TargetofTargetFrameTemplate), are one art at 120 x 49, laid out alike once Camelot's PetFrame.lua and TargetFrame.lua
-- have moved their bars: the portrait 37 across at (5, 5), the name beside it, health 70 x 11 from the frame's middle
-- right, power under it 3 to the left (77 wide on the pet, 78 on the targets of target), with the party frame's masks.
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
    tot = {
        size = { 120, 49 },
        art = "UI-HUD-UnitFrame-TargetofTarget-PortraitOn",
        portrait = { point = "TOPLEFT", x = 5, y = -5, size = 37, mask = "CircleMask" },
        name = { point = "TOPLEFT", x = 44, y = -6, w = 68 },
        -- The masks' places from the anchors (health -28, 3; power -27, 4) left the part they let through 1.4 above the
        -- art's slots and the power's 2 left of its own, under the gold divider (seen in the editor), as on the party
        -- frame (PARTY_POWER_SHIFT, by eye there); the game keeps its fill in the slot. So each is centred on its slot,
        -- measured on the game's sheet: health x 46..114, y 19..28; power x 46..114, y 31..36.
        health = { x = 45, y = -17.5, w = 70, h = 11, fillAtlas = "UI-HUD-UnitFrame-TargetofTarget-PortraitOn-Bar-Health",
                   maskAtlas = "UI-HUD-UnitFrame-Party-PortraitOn-Bar-Health-Mask", maskX = -28, maskY = 2.1 },
        power = { x = 42, y = -29.5, w = 78, h = 7, fillAtlas = "UI-HUD-UnitFrame-TargetofTarget-PortraitOn-Bar-Mana",
                  maskAtlas = "UI-HUD-UnitFrame-Party-PortraitOn-Bar-Mana-Mask", maskX = -26.1, maskY = 3.6 },
    },
}
LAYOUT.focus = LAYOUT.target
LAYOUT.pet = setmetatable({ power = setmetatable({ w = 77 }, { __index = LAYOUT.tot.power }) }, { __index = LAYOUT.tot })
Preview.LAYOUT = LAYOUT

-- A layout's frame size.
local function SizeOf(L)
    local size = L.size
    if size then return size[1], size[2] end
    return 232, 100
end

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

-- A rogue's combo points on the target at each row of SCRIPT (Preview.Create's combo): built up, and spent by the
-- finisher that takes the power at the fifth row. A scene with one number keeps it throughout.
local POINTS = { 0, 1, 3, 5, 0, 1, 0, 0 }

-- Scenes the frames can play instead (the editor's buttons): the fight above, the player taking a beating, being healed
-- back up, and spending power and getting it back. Each is rows as SCRIPT's, looped, with the DoTs only in the fight.
local SCENES = {
    fight = { rows = SCRIPT, dots = DOTS, points = POINTS, loop = LOOP },
    damage = { loop = 6.0, points = 3, rows = {
        { 0.0, 1.00, 0.60, 1.00, 0.90 },
        { 0.8, 0.82, 0.60, 1.00, 0.90 },
        { 1.6, 0.64, 0.60, 1.00, 0.90 },
        { 2.4, 0.47, 0.60, 1.00, 0.90 },
        { 3.2, 0.30, 0.60, 1.00, 0.90 },
        { 4.0, 0.15, 0.60, 1.00, 0.90 },
    } },
    -- A Renew (Holy, school 2) ticking the health back up, then a bandage (Nature-green) joining it, each shown ahead
    -- of the health by the heal marker while the heals setting is on: { school, health still to come of the 271 }.
    heal = { loop = 7.6, points = 2, rows = {
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
    power = { loop = 6.4, points = { 0, 1, 3, 5, 5, 0, 0 }, rows = {
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
    party  = { unit = "party1", frame = "party", name = "" },
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
-- Pieces, each placed on a frame f of its layout's size (shared with Capture.lua)
--------------------------------------------------------------------------------

function Preview.Portrait(f, which)
    local p = LAYOUT[which].portrait
    local portrait = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    portrait:SetSize(p.size, p.size)
    portrait:SetPoint(p.point, p.x, p.y)
    if which ~= "player" then
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
    local L = LAYOUT[which]
    local art = f:CreateTexture(nil, "BACKGROUND", nil, 2)
    Atlas(art, L.art, true)
    if L.artAt then art:SetPoint("TOPLEFT", L.artAt[1], -L.artAt[2]) else art:SetPoint("CENTER") end
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
-- Taller bars (/sab tall, a test): the frame art cut into slices of the game's own atlas and laid out again, each
-- bar's slot stretched by repeating a band from its middle, the portrait ring cut out and put back over the panel.
--------------------------------------------------------------------------------
-- In frame units from the frame's top-left (y down), measured on the capture (branding/art): a mirrored art's (the
-- target's, portrait on the right) x from the frame's right edge, so all read as the player's. ring: the portrait ring's centre and outer radius. top,
-- bottom: the panel's edges. health, power: a row in the middle of each slot and how far either side of it the band
-- repeated to stretch it reaches. clean: where the panel is free of the ring (to the atlas's far end). The ring hides
-- the panel's end, which the capture never shows, so it is drawn again from the dark block beside the ring (from
-- strip to clean): its top border (top to stripTop), a band (stripMid) stretched down the middle, its bottom border
-- (stripBottom to bottom), each carried on under the ring by its first column stretched. opaque: where each bar's mask
-- lets the liquid through, from the bar's top, measured on the captured masks: the slot, inside the art's borders.
local TALL = {
    player = { ring = { 53.62, 50.26, 33.76 }, top = 25.6, bottom = 74.6, health = { 53, 2.5 }, power = { 66.5, 2 },
               clean = 88, strip = 82.5, stripTop = 30, stripMid = { 30, 32 }, stripBottom = 70.5,
               opaque = { health = { 3.75, 16.88 }, power = { 2.24, 10.19 } } },
    target = { ring = { 53.62, 50.26, 33.15 }, top = 23.6, bottom = 72.4, health = { 51, 2.5 }, power = { 64.75, 2 },
               clean = 87.5, strip = 82.5, stripTop = 28.5, stripMid = { 29, 31 }, stripBottom = 68, mirror = true,
               opaque = { health = { 3.61, 16.75 }, power = { 1.11, 9.05 } } },
}
-- The small frames' art (LAYOUT.tot, the pet's too) was measured on the game's own sheet rather than a capture:
-- uiunitframec60.blp, from github.com/Adrestie/mod-forever-ui (data/art/interface/foreverui/hud), its atlas at the
-- coordinates in that repo's UIAtlas_04_unit_frames.lua, generated from the Forever client (1.60.1); the same sheet
-- gives the player's and target's measurements above within a few tenths. Its masks are the party frame's, so their
-- opaque bands are the party capture's (branding/art/party-*-mask.png), where LAYOUT.tot puts the masks.
TALL.tot = { ring = { 23, 23, 21.7 }, top = 3.6, bottom = 39, health = { 23.5, 1.5 }, power = { 33.5, 1 },
             clean = 46, strip = 41, stripTop = 6, stripMid = { 6.5, 8.5 }, stripBottom = 36,
             opaque = { health = { 1.20, 11.01 }, power = { 0.51, 7.56 } } }
TALL.focus, TALL.pet = TALL.target, TALL.tot
Preview.TALL = TALL -- for the real frames (TallFrames.lua)
-- The ring keeps its size while it covers the panel's end above and below by this much, and grows past that.
local TALL_COVER = 2

-- An atlas's place on a frame (232 x 100 unless w and h say) that centres it at its own size (Preview.Art), or puts
-- its top-left at at ({ x, y }), and its texture coordinates.
local function AtlasPlace(name, w, h, at)
    w, h = w or 232, h or 100
    local get = C_Texture and C_Texture.GetAtlasInfo
    local ok, info = pcall(get or error, name)
    if not (ok and type(info) == "table" and info.width and info.height and info.width > 0 and info.height > 0) then
        return nil
    end
    return { name = name, w = info.width, h = info.height, x0 = at and at[1] or w / 2 - info.width / 2,
             y0 = at and at[2] or h / 2 - info.height / 2,
             l = info.leftTexCoord or 0, r = info.rightTexCoord or 1, t = info.topTexCoord or 0,
             b = info.bottomTexCoord or 1, file = info.file or info.filename }
end
Preview.AtlasPlace = AtlasPlace

-- A texture for the next slice on host (the frame itself for its art, a glow's frame for a glow): its slices are kept
-- (host.slices, host.sliceUsed of them in use) and reused each time the frame is laid out again, in host.layer
-- (BACKGROUND unless it says) at sublevel 0.
local function SliceTexture(host)
    host.slices = host.slices or {}
    host.sliceUsed = host.sliceUsed + 1
    local tex = host.slices[host.sliceUsed]
    if not tex then
        tex = host:CreateTexture(nil, host.layer or "BACKGROUND", nil, 0)
        host.slices[host.sliceUsed] = tex
    end
    return tex
end

-- The part of atlas A from (sx0, sy0) to (sx1, sy1) drawn from (dx0, dy0) to (dx1, dy1) on f, in frame units, on the
-- texture Take() gives; whatever of it lies past the atlas is left out (and then Take is not called). The slice is the
-- atlas's file (by ID) with texture coordinates, as FlareUI slices Forever's unit frame art: in game SetAtlas and then
-- SetTexCoord drew nothing at all (seen in the editor, every slice and the ring missing).
local function Slice(f, A, Take, sx0, sx1, sy0, sy1, dx0, dx1, dy0, dy1)
    local kx, ky = (dx1 - dx0) / (sx1 - sx0), (dy1 - dy0) / (sy1 - sy0)
    local ax1, ay1 = A.x0 + A.w, A.y0 + A.h
    if sx0 < A.x0 then dx0, sx0 = dx0 + (A.x0 - sx0) * kx, A.x0 end
    if sx1 > ax1 then dx1, sx1 = dx1 - (sx1 - ax1) * kx, ax1 end
    if sy0 < A.y0 then dy0, sy0 = dy0 + (A.y0 - sy0) * ky, A.y0 end
    if sy1 > ay1 then dy1, sy1 = dy1 - (sy1 - ay1) * ky, ay1 end
    if sx1 - sx0 < 0.01 or sy1 - sy0 < 0.01 or dx1 - dx0 < 0.01 or dy1 - dy0 < 0.01 then return nil end
    local tex = Take()
    if not (A.file and tex:SetTexture(A.file) ~= false) then return nil end
    tex:ClearAllPoints()
    tex:Show()
    local u, v = A.r - A.l, A.b - A.t
    tex:SetTexCoord(A.l + (sx0 - A.x0) / A.w * u, A.l + (sx1 - A.x0) / A.w * u,
                    A.t + (sy0 - A.y0) / A.h * v, A.t + (sy1 - A.y0) / A.h * v)
    tex:SetSize(dx1 - dx0, dy1 - dy0)
    tex:SetPoint("TOPLEFT", f, "TOPLEFT", dx0, -dy0)
    return tex
end

-- A glow over the art (the game's in-combat and status flashes) has the art's outline but no panel of its own beside the
-- ring, and spreads past the ring's edge by about this much.
local GLOW_PAD = 4

-- Atlas A (its place on f in frame units) laid out on f as frame art of layout which with the health slot dh taller and
-- the power slot dp, its textures on host (f itself for the art). A glow (glow true) is laid out the same way, with
-- no panel's end drawn under the ring, and its ring cut wider (GLOW_PAD) but not past where the panel begins. Returns
-- how it placed things.
local function Lay(f, host, which, dh, dp, A, glow)
    local g, L = TALL[which], LAYOUT[which]
    local W, H = SizeOf(L)
    host.sliceUsed = 0
    local function Take() return SliceTexture(host) end
    local D = dh + dp
    local mirror = g.mirror
    -- x as measured (a mirrored art's from its right edge) to the frame's, for a span x0..x1.
    local function X(x0, x1)
        if mirror then return W - x1, W - x0 end
        return x0, x1
    end
    local function Piece(take, sx0, sx1, sy0, sy1, dx0, dx1, dy0, dy1)
        local a, b = X(sx0, sx1)
        local c, d = X(dx0, dx1)
        return Slice(f, A, take, a, b, sy0, sy1, c, d, dy0, dy1)
    end
    local cx, cy, R = g.ring[1], g.ring[2], g.ring[3]
    local ncy = cy + D / 2
    local s = math.max(1, (math.max(ncy - g.top, g.bottom + D - ncy) + TALL_COVER) / R)
    local ncx = cx + R - R * s -- the ring's side by the bars stays where it was

    -- The panel clear of the ring, row by row: as it is down to the health slot's middle, a band from there repeated
    -- for dh, the rest down to the power slot's middle dh lower, its band for dp, and the rest D lower.
    local far = mirror and (W - A.x0) or (A.x0 + A.w) -- the atlas's far end, as measured
    local rows = {}
    local function band(y, half, at, d)
        local done = 0
        while done < d - 0.01 do
            local n = math.min(2 * half, d - done)
            rows[#rows + 1] = { y - half, y - half + n, at + done, at + done + n }
            done = done + n
        end
    end
    local yh, yp = g.health[1], g.power[1]
    rows[#rows + 1] = { A.y0, yh, A.y0, yh }
    band(yh, g.health[2], yh, dh)
    rows[#rows + 1] = { yh, yp, yh + dh, yp + dh }
    band(yp, g.power[2], yp + dh, dp)
    rows[#rows + 1] = { yp, A.y0 + A.h, yp + D, A.y0 + A.h + D }
    for _, r in ipairs(rows) do Piece(Take, g.clean, far, r[1], r[2], g.clean, far, r[3], r[4]) end

    -- The panel's end, under the ring: the dark block's top border, middle and bottom border, each carried on to the
    -- ring's centre by its first column.
    if not glow then
        local strips = {
            { g.top, g.stripTop, g.top, g.stripTop },
            { g.stripMid[1], g.stripMid[2], g.stripTop, g.stripBottom + D },
            { g.stripBottom, g.bottom, g.stripBottom + D, g.bottom + D },
        }
        for _, r in ipairs(strips) do
            Piece(Take, g.strip, g.clean, r[1], r[2], g.strip, g.clean, r[3], r[4])
            Piece(Take, g.strip, g.strip + 0.5, r[1], r[2], ncx, g.strip, r[3], r[4])
        end
    end
    for i = host.sliceUsed + 1, #host.slices do host.slices[i]:Hide() end

    -- The ring, cut out of the atlas by a circle, centred on the panel again and grown by s; a glow's no further right
    -- than where the panel begins, which its rows above carry.
    local half = R + (glow and GLOW_PAD or 0.5)
    local right = glow and math.min(cx + half, g.clean) or cx + half
    host.ringTex = host.ringTex or host:CreateTexture(nil, host.layer or "BACKGROUND", nil, glow and 1 or 2)
    local ring = Piece(function() return host.ringTex end, cx - half, right, cy - half, cy + half,
        ncx - half * s, ncx + (right - cx) * s, ncy - half * s, ncy + half * s)
    host.ringTex:SetShown(ring ~= nil)
    if host.ringMask == nil then
        -- Asked of the client first: FlareUI does not trust SetAtlas's answer on Forever either.
        host.ringMask = false
        if AtlasPlace("CircleMask") then
            local mask = host:CreateMaskTexture()
            mask:SetAtlas("CircleMask")
            host.ringTex:AddMaskTexture(mask)
            host.ringMask = mask
        end
    end
    if host.ringMask then
        local x0 = X(ncx - half * s, ncx + half * s)
        host.ringMask:ClearAllPoints()
        host.ringMask:SetSize(2 * half * s, 2 * half * s)
        host.ringMask:SetPoint("TOPLEFT", f, "TOPLEFT", x0, -(ncy - half * s))
    end
    local circled = ring ~= nil and host.ringMask and true or false

    -- Where a point near the ring (in the frame's units, y down) goes: with the ring, grown about its centre.
    local function Moved(x, y)
        local mx = mirror and W - x or x
        mx = ncx + (mx - cx) * s
        return mirror and W - mx or mx, ncy + (y - cy) * s
    end
    -- How far the grown ring reaches past the frame's edges (left, top, right, bottom), which the frame's own size does
    -- not take in: it grows out from the bars' side.
    local rx0 = X(ncx - half * s, ncx + half * s)
    local rx1 = rx0 + 2 * half * s
    local over = { math.max(0, -rx0), math.max(0, -(ncy - half * s)), math.max(0, rx1 - W),
                   math.max(0, ncy + half * s - (H + D)) }
    return { scale = s, ring = ring ~= nil, circled = circled, atlas = A, Moved = Moved, over = over }
end

-- The frame art on f (its layout's size, dh + dp taller) with the health slot dh taller and the power slot dp, the
-- panel at BACKGROUND 0, the ring at 2 (the portrait, at 1, between them). Returns how it placed things, or nil when the
-- art is not measured (TALL) or the client does not say where the atlas's pixels are (then nothing is drawn). Called
-- again, it lays the same textures out anew.
function Preview.TallArt(f, which, dh, dp)
    local L = LAYOUT[which]
    if not (TALL[which] and L) then return nil end
    local W, H = SizeOf(L)
    local A = AtlasPlace(L.art, W, H, L.artAt)
    if not A then return nil end
    return Lay(f, f, which, dh, dp, A, false)
end

-- A glow of the game's (atlas, its top-left at x0, y0 on the game's frame, as on ours) laid out over a taller frame f
-- as its art is, on a frame of its own over the art (OVERLAY, under the bars), kept by key for the next layout. Returns
-- that frame, its textures in .slices and .ringTex, or nil when f is not taller or the client has no such atlas.
function Preview.TallGlow(f, key, atlas, x0, y0)
    if not (f.tall and f.tallBy) then return nil end
    local place = AtlasPlace(atlas)
    if not place then return nil end
    place.x0, place.y0 = x0, y0
    f.glows = f.glows or {}
    local host = f.glows[key]
    if not host then
        host = CreateFrame("Frame", nil, f)
        host:SetAllPoints(f)
        host.layer = "OVERLAY"
        f.glows[key] = host
    end
    Lay(f, host, f.which, f.tallBy[1], f.tallBy[2], place, true)
    return host
end

-- A bar's layout made taller: health dh, power dp and dh lower, and its mask stretched with it. The mask is mostly
-- transparent margin round its slot, so stretched evenly its slot grew less than the bar and the liquid stopped short of
-- the art's borders above and below (seen in game). So it is stretched and moved until the part it lets through (opaque)
-- starts where it did and is d taller, as the art's slot is.
local function TallSpec(spec, kind, dh, dp, which)
    local d = kind == "health" and dh or dp
    local out = setmetatable({ h = spec.h + d, y = kind == "power" and spec.y - dh or spec.y }, { __index = spec })
    local m = spec.maskAtlas and AtlasPlace(spec.maskAtlas)
    local maskH = spec.maskH or (m and m.h)
    local band = TALL[which] and TALL[which].opaque[kind]
    if maskH and band then
        -- From the bar's top (y down) the mask starts at -maskY; its band at o0..o1, a share a..b of its height.
        local o0, o1 = band[1], band[2]
        local a = (o0 + spec.maskY) / maskH
        local grown = maskH * (o1 - o0 + d) / (o1 - o0)
        out.maskH = grown
        out.maskY = a * grown - o0
    elseif maskH then
        out.maskH = maskH + d
    end
    return out
end

--------------------------------------------------------------------------------
-- The preview frames
--------------------------------------------------------------------------------

-- A bar like the game's: its own fill (shown while the liquid is off), shaped by the game's mask
-- atlas, with its text above everything on top. setup.live: a bar of a real frame of ours (TallFrames.lua), filled from
-- the game's and handed to the liquid there, with a left and a right text as well; not a preview.
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
    bar.fill = fill
    if setup.live then
        bar.left = top:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
        bar.right = top:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
        return bar
    end
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

-- The row of a scene t seconds into it, looped, and its place in the scene.
local function RowAt(scene, t)
    local at, found, index = t % scene.loop, scene.rows[1], 1
    for i, row in ipairs(scene.rows) do
        if row[1] <= at then found, index = row, i end
    end
    return found, index
end

-- A group's member i (party, raid, nameplates) in one of the frames' scenes, each a little behind the one before.
local function GroupRow(name, t, i)
    return RowAt(SCENES[name], t - i * 0.35)
end

-- The heals a group's member i has on the way in a scene (the heal scene's), t seconds into it, as the player's are.
local function GroupHeals(name, t, i)
    local scene = SCENES[name]
    if not (scene and scene.heals) then return {} end
    local _, index = RowAt(scene, t - i * 0.35)
    return scene.heals[index] or {}
end

-- A group example's members show the player's heals on each in the heal scene, as the real frames do: the scene's heals,
-- given in points of the player's 271 health, at the same share of the member's, while key (the frames' health
-- setting) gives them the liquid. tight: cut at the bar's edges, for frames that touch. Returns Heal(member, heals) to
-- hand a member the heals coming now.
local function GroupHealers(members, key, tight)
    for _, m in ipairs(members) do
        m.heals = {}
        local scale = m.health.max / 271
        m.healer = ns.HealMarker.Preview(m.health, function()
            local list, total = {}, 0
            for k, heal in ipairs(m.heals) do
                list[k] = { school = heal[1], heal = heal[2] * scale }
                total = total + list[k].heal
            end
            return total, list
        end, tight)
    end
    return function(m, coming)
        if not ns.Core.Get(key) then coming = {} end
        local applied = #coming > #m.heals
        m.heals = coming
        if applied and m.healer then ns.HealMarker.Landed(m.healer) end
    end
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

-- The combo points round an example target's portrait, a rogue's (asked for in the editor), as the game lays them out
-- (Camelot ComboFrame.lua: from this angle in these steps, this far out in a dot's own units, the last dot lit first),
-- in dots of its own template. Nothing for other classes, or where the client has no such template.
local COMBO = { x = 2, y = 2, radius = 66, start = -10, step = 21, scale = 0.6, max = 5 }

local function LayoutCombo(f)
    local c = f.combo
    local s = f.tall and f.tall.scale or 1
    c.host:SetPoint("CENTER", f.portrait, "CENTER", COMBO.x * s, COMBO.y * s)
    for _, p in ipairs(c.points) do p:SetScale(COMBO.scale * s) end -- a scaled frame's offsets are in its own units
end

local function AddCombo(f)
    local okClass, _, class = pcall(UnitClass, "player")
    if not okClass or class ~= "ROGUE" then return end
    local ok, combo = pcall(function()
        local host = CreateFrame("Frame", nil, f.top)
        host:SetSize(1, 1)
        host:SetFrameLevel(f.top:GetFrameLevel() + 2)
        host:Hide()
        local points = {}
        for i = 1, COMBO.max do
            local p = CreateFrame("Frame", nil, host, "RogueComboPointTemplate")
            local a = math.rad(COMBO.start + (i - 1) * COMBO.step)
            p:SetPoint("CENTER", host, "CENTER", math.cos(a) * COMBO.radius, math.sin(a) * COMBO.radius)
            p:Setup()
            points[i] = p
        end
        return { host = host, points = points, n = 0 }
    end)
    if not ok then return end
    f.combo = combo
    -- Shown again, each dot is as it should be at once: one hidden halfway through its animation would stay so.
    combo.host:SetScript("OnShow", function()
        for i, p in ipairs(combo.points) do
            p.isFull = nil
            p:SetActiveNoAnimation(i > COMBO.max - combo.n)
        end
    end)
    LayoutCombo(f)
end

-- n points on f's target; none hides them, as the game does.
local function SetCombo(f, n)
    local c = f.combo
    if not c or n == c.n then return end
    if n == 0 then
        c.n = 0
        c.host:Hide()
        return
    end
    c.host:Show()
    c.n = n
    for i, p in ipairs(c.points) do p:SetActive(i > COMBO.max - n) end
end

-- The frame: art at the bottom, then the bars and their liquid, then the text, the level circle and
-- the name above them, as the game layers them. as: which frame's settings its bars follow (SIDES), which by default.
-- Preview.SetFrameTall lays it out again with taller bars. live: a real frame of ours (Preview.LiveFrame).
local function Frame(parent, which, as, live)
    local L = LAYOUT[which]
    local side = SIDES[as or which]
    local f = CreateFrame("Frame", nil, parent)
    local top = CreateFrame("Frame", nil, f)
    top:SetAllPoints()
    top:SetFrameLevel(f:GetFrameLevel() + 10)

    f:SetSize(SizeOf(L))
    f.which = which
    f.portrait = Preview.Portrait(f, which)
    f.art = Preview.Art(f, which)
    if L.banner then f.banner = Preview.Banner(f) end

    local name = top:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.nameText, f.top = name, top
    name:SetJustifyH("CENTER")
    name:SetSize(L.name.w, 12)
    if which == "player" then
        name:SetPoint(L.name.point, f, "TOPLEFT", L.name.x, L.name.y)
    else
        name:SetPoint(L.name.point, L.name.x, L.name.y)
    end
    if side.name then
        name:SetText(side.name)
    else
        -- The game's own name text, surname included on Forever.
        local shown = PlayerName and PlayerName.GetText and PlayerName:GetText()
        name:SetText(shown or (UnitName("player")))
    end

    -- The level in its circle; the small frames have none.
    if L.circle then
        local circle = Preview.Circle(top, which)
        f.circle = circle
        local level = top:CreateFontString(nil, "OVERLAY", "WhiteLargeNumberFont")
        f.levelText = level
        level:SetPoint("CENTER", circle, "CENTER", 0, -0.5)
        level:SetText(UnitLevel("player"))
    end

    local token, powerMax, info
    if which == "player" then
        token, powerMax, info = PowerInfo("player")
    else
        token, powerMax, info = "MANA", 350, PowerBarColor and PowerBarColor.MANA
    end
    local key = as or which
    f.health = Bar(f, top, L.health, { key = key .. "Health", unit = side.unit, kind = "health", frame = side.frame,
        max = which == "player" and 271 or 210, live = live })
    f.power = Bar(f, top, L.power, { key = key .. "Power", unit = side.unit, kind = "power", token = token,
        frame = side.frame, max = powerMax, color = info and { info.r, info.g, info.b } or { 0, 0, 1 },
        fillAtlas = which == "player" and info and info.atlas or nil, live = live })
    return f
end

-- A frame of ours on the real game frame gf, in layout which (LAYOUT), standing for frame as (SIDES: "player",
-- "target", "focus", "pet" or "tot"), drawn as the examples are but with bars that are not previews: TallFrames.lua
-- fills them from the game's, hands them to the liquid and copies the game's name, level and portrait onto it. Laid
-- out with Preview.SetFrameTall.
function Preview.LiveFrame(gf, which, as)
    return Frame(gf, which, as, true)
end

-- Lays a frame of Frame's out with its health bar dh taller and its power bar dp (0 and 0: the game's frame, its own
-- art). Taller, the art is slices of the game's atlas (Preview.TallArt), the portrait and level circle
-- going with the ring and the bars' masks stretched with them; with no atlas info from the client it stays the game's
-- size. f.tall: how the art was laid out, or nil.
function Preview.SetFrameTall(f, dh, dp)
    local which, L = f.which, LAYOUT[f.which]
    dh, dp = dh or 0, dp or 0
    local tall = (dh ~= 0 or dp ~= 0) and Preview.TallArt(f, which, dh, dp) or nil
    if not tall then
        dh, dp = 0, 0
        for _, tex in ipairs(f.slices or {}) do tex:Hide() end
        if f.ringTex then f.ringTex:Hide() end
        for _, host in pairs(f.glows or {}) do host:Hide() end
    end
    f.tall, f.tallBy = tall, tall and { dh, dp } or nil
    if f.art then f.art:SetShown(not tall) end
    local W, H = SizeOf(L)
    f:SetSize(W, H + dh + dp)
    local function Moved(x, y)
        if tall then return tall.Moved(x, y) end
        return x, y
    end
    local s = tall and tall.scale or 1
    -- The portrait and the level circle, by their centres (the same places Preview.Portrait and Preview.Circle give).
    local p = L.portrait
    local fromRight = p.point:find("RIGHT") ~= nil
    local x, y = Moved(fromRight and W + p.x - p.size / 2 or p.x + p.size / 2, -p.y + p.size / 2)
    f.portrait:ClearAllPoints()
    f.portrait:SetSize(p.size * s, p.size * s)
    f.portrait:SetPoint("CENTER", f, "TOPLEFT", x, -y)
    if f.circle then
        local w, h = f.circle:GetSize()
        w, h = w or 0, h or 0
        local c = L.circle
        x, y = Moved(c.point:find("RIGHT") and W + c.x - w / 2 or c.x + w / 2, H - c.y - h / 2)
        f.circle:ClearAllPoints()
        f.circle:SetPoint("CENTER", f, "TOPLEFT", x, -y)
    end
    -- The bars and their masks.
    for _, kind in ipairs({ "health", "power" }) do
        local bar = f[kind]
        local spec = tall and TallSpec(L[kind], kind, dh, dp, which) or L[kind]
        bar:ClearAllPoints()
        bar:SetSize(spec.w, spec.h)
        bar:SetPoint("TOPLEFT", spec.x, spec.y)
        local mask = bar[kind == "health" and "HealthBarMask" or "ManaBarMask"]
        if mask then
            mask:ClearAllPoints()
            Preview.PlaceMask(mask, spec, bar, 0, 0)
        end
    end
    if f.combo then LayoutCombo(f) end
    return tall ~= nil
end

-- Both frames side by side, playing a scene (the fight by default) while shown. sides: what each stands for, { left =
-- "player" or "prd", right = "target", "focus", "pet" or "tot" }, the player and the target by default. holder:SetTall
-- makes their bars taller. combo: a rogue's combo points on the target too.
function Preview.Create(parent, sides, combo)
    sides = sides or {}
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(480, 100)
    local player, target = Frame(holder, "player", sides.left), Frame(holder, "target", sides.right)
    -- By their tops: a taller frame grows down, as its bars do.
    player:SetPoint("TOPLEFT")
    target:SetPoint("TOPRIGHT")
    if combo then AddCombo(target) end

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
        local points = scene.points
        if type(points) == "table" then points = points[i] end
        SetCombo(target, not Resting(target.health) and points or 0)
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
    -- Each frame's bars taller: tall = { player = { dh, dp }, target = { dh, dp } }, a frame left out as the game's. The
    -- holder takes the taller frame's height.
    function holder.SetTall(_, tall)
        tall = tall or {}
        local height = 100
        for _, which in ipairs({ "player", "target" }) do
            local t = tall[which] or {}
            local f = holder[which]
            Preview.SetFrameTall(f, t[1], t[2])
            height = math.max(height, f:GetHeight())
        end
        holder:SetHeight(height)
    end
    holder.scene = "fight"
    holder.player, holder.target, holder.marker, holder.healer = player, target, marker, healer
    holder.bars = { player.health, player.power, target.health, target.power }
    return holder
end

-- /sab tall: a window of the player and target frames with the bars taller, health and power this tall (the game's
-- are 20 and 10), playing the fight, to see in game how the art laid out again from slices of the atlas looks. nil
-- hides it. Returns lines for chat: what the client said about the atlas, and how the ring was placed.
local tallTest
function Preview.TallTest(health, power)
    if tallTest then tallTest:Hide() end
    tallTest = nil
    if not health then return { "Bar Height test hidden." } end
    local dh, dp = health - 20, power - 10
    local win = CreateFrame("Frame", nil, UIParent)
    win:SetSize(520, 100 + dh + dp + 40)
    win:SetPoint("TOP", UIParent, "TOP", 0, -140)
    win:SetFrameStrata("HIGH")
    win:SetMovable(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    local bg = win:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.06, 0.09, 0.85)
    local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -8)
    title:SetText(string.format("Bar Height: health %d, power %d. Drag to move; /sab tall off to close.", health, power))
    local holder = Preview.Create(win)
    holder:SetTall({ player = { dh, dp }, target = { dh, dp } })
    holder:SetPoint("BOTTOM", 0, 6)
    tallTest = win

    local lines = {}
    for _, which in ipairs({ "player", "target" }) do
        local f = holder[which]
        local A = AtlasPlace(LAYOUT[which].art)
        if not A then
            lines[#lines + 1] = which .. ": the client gave no atlas info for " .. LAYOUT[which].art
                .. " (C_Texture.GetAtlasInfo), so the frame is shown at the game's size."
        else
            lines[#lines + 1] = string.format("%s: atlas %s %gx%g, coords %.4f %.4f %.4f %.4f, file %s", which, A.name, A.w,
                A.h, A.l, A.r, A.t, A.b, tostring(A.file))
        end
        if f.tall then
            lines[#lines + 1] = string.format("%s: portrait %s (x%.2f)%s", which,
                f.tall.scale > 1 and "grown to cover the panel's end" or "at its own size", f.tall.scale,
                f.tall.circled and "" or "; no CircleMask atlas, so the ring is cut square")
        end
    end
    return lines
end

-- One frame alone, standing for the focus (in the target frame's art, its template), the pet or the target of target
-- (in theirs, the small frames' LAYOUT.tot), playing the target's side of the frames' scenes while shown (the
-- editor's screen, where each has a place of its own).
function Preview.CreateSingle(parent, as)
    local art = (as == "pet" or as == "tot") and as or "target"
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(SizeOf(LAYOUT[art]))
    local f = Frame(holder, art, as)
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
    -- The frame's bars taller: tall = { dh, dp }. The holder takes the frame's height.
    function holder.SetTall(_, tall)
        tall = tall or {}
        Preview.SetFrameTall(f, tall[1], tall[2])
        holder:SetHeight(f:GetHeight())
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
-- The party member frame as a layout of its own (TallFrames.lua's real party frames, and the example's members laid out
-- taller): the art at (1, 2), the power bar shifted as above, and the health mask 0.4 lower. Its art is the small
-- frames' (TALL.tot) pixel for pixel, on the game's party sheet (uipartyframec60.blp, from mod-forever-ui as there), so
-- its measurements are theirs 1 right and 2 down. Measured on that sheet, the slots are x 47..115, health y 21..30 and
-- power y 33..38; the shift above, set by eye, centres the power mask's opaque part within a unit of that (0.9 right
-- and 1.9 down measured), and the health mask is centred on its slot (0.4 down). The masks' opaque bands are the party
-- capture's (branding/art/party-*-mask.png) from each bar's top.
LAYOUT.party = {
    size = { 120, 53 }, artAt = { 1, 2 }, art = PARTY.art,
    portrait = { point = "TOPLEFT", x = 7, y = -6, size = 37, mask = "CircleMask" },
    name = { point = "TOPLEFT", x = 48, y = -7, w = 55 },
    health = setmetatable({ maskY = PARTY.health.maskY - 0.4 }, { __index = PARTY.health }),
    power = SHIFTED_POWER,
}
TALL.party = { ring = { 24, 25, 21.7 }, top = 5.6, bottom = 41, health = { 25.5, 1.5 }, power = { 35.5, 1 },
               clean = 47, strip = 42, stripTop = 8, stripMid = { 8.5, 10.5 }, stripBottom = 38,
               opaque = { health = { 0.53, 10.51 }, power = { -0.89, 6.16 } } }

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
    f.which = "party" -- LAYOUT.party, for Preview.SetFrameTall
    local top = CreateFrame("Frame", nil, f)
    top:SetAllPoints()
    top:SetFrameLevel(f:GetFrameLevel() + 10)

    f.portrait = Preview.PartyPortrait(f, class)
    f.art = Preview.PartyArt(f)

    local label = top:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetJustifyH("LEFT")
    label:SetSize(55, 12)
    label:SetPoint("TOPLEFT", 48, -7)
    label:SetText(name)

    local info = PowerBarColor and PowerBarColor[token]
    f.health = Bar(f, top, LAYOUT.party.health, { key = as .. "Health", frame = as, class = class, unit = "party1",
        kind = "health", max = 400 })
    f.power = Bar(f, top, LAYOUT.party.power, { key = as .. "Power", frame = as, class = class, unit = "party1",
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
    local Heal = (as or "party") == "party" and GroupHealers(members, "partyHealth") or function() end
    local t, step = 0, 0
    local function Play(i)
        local row = PARTY_SCRIPT[i]
        for n, m in ipairs(members) do
            SetFraction(m.health, row[2 * n])
            SetFraction(m.power, row[2 * n + 1])
            Heal(m, {})
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
                Heal(m, GroupHeals(holder.scene, t, n))
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
    -- Every member's bars taller: tall = { dh, dp }, each member growing down as the real ones do, the stack or row
    -- laid out again round them.
    function holder.SetTall(_, tall)
        tall = tall or {}
        local y, height = 0, 0
        for i, m in ipairs(members) do
            Preview.SetFrameTall(m, tall[1], tall[2])
            if stacked then
                m:ClearAllPoints()
                m:SetPoint("TOPLEFT", 0, -y)
                y = y + m:GetHeight() + 4
            end
            height = math.max(height, m:GetHeight())
        end
        if stacked then holder:SetHeight(y - 4) else holder:SetHeight(height) end
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
    local Heal = GroupHealers(members, "raidHealth", true) -- the frames touch: no motes over the next one
    local t, step = 0, -1
    local function Play(n)
        for i, m in ipairs(members) do
            SetFraction(m.health, RAID_HEALTH[(n + i * 3) % #RAID_HEALTH + 1])
            SetFraction(m.power, RAID_POWER[(n + i * 5) % #RAID_POWER + 1])
            Heal(m, {})
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
                Heal(m, GroupHeals(holder.scene, t, i))
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
