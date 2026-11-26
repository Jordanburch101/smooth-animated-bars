-- Weakened Soul on the player frame's health bar (the weakenedSoul setting): for the 15 seconds after a Power Word:
-- Shield lands on the player, when no other can, the health liquid's front is ashen. Ash from the shattered shield
-- settles into it as dark specks, which heat to embers, then gold, and are drawn into a crescent forming on the front
-- (the shield's rim, coming back), pulsing faster as the wait runs out. When it is over the crescent flashes white-hot
-- with short rays and stars: the player can be shielded again. While a shield still holds, the same plays out quietly
-- in its glass: the rim starts ashen and warms, embers rise in the glass, and at the end light sweeps across it.
-- Mocked up out of the game (an earlier ring at the release looked generic; ash over the breaking glass, a grey block).
--
-- Auras are secret in combat (GetPlayerAuraBySpellID answered "none" in combat, see Heals.lua), so the wait is timed:
-- it starts when a shield goes up, as the game's own absorb display says (Shield.Exists), unless the player's own cast
-- of another spell that absorbs damage (Ice Barrier, a protection potion) went off just before. That covers any
-- priest's shield, not only the player's own. Out of combat the debuff itself is read, which starts, corrects or ends
-- the wait. Where the game's absorb display is secret, the player's own Power Word: Shield cast on themselves starts it.
-- Not yet seen in game: any of it.
--
-- Everything is anchored to the health liquid's own front (Bars.Mover) or the health's edge (Bars.Edge), which the client
-- moves, so it follows the health without reading it.

local _, ns = ...

local Soul = {}
ns.Soul = Soul

local MEDIA = "Interface\\AddOns\\SmoothAnimatedBars\\Media\\"
local WEAKENED_SOUL = 6788      -- the debuff (Forever's tooltip: 15 seconds)
local SHIELD_SPELL = 17         -- Power Word: Shield, rank 1, for its name in the client's language
local SECONDS = 15
local ATTRIBUTE = 0.5           -- a shield this soon after the player's own cast of another absorb is that spell's
local AURA_EVERY = 1            -- seconds between reading the debuff out of combat
local RELEASE = 0.9             -- the release's flash, seconds
local RELEASE_DONE = 1.6        -- and everything it threw is gone by then

local ASH_W, ASH_ALPHA = 22, 0.72 -- the ashen stretch back from the front, and how grey at the front
local ASH_DIM = 0.25            -- and how much darker
local SPECKS, SPECK_MAX = 16, 18
local FALLING = 32              -- light ash from the burst
local GLASS_EMBERS = 14
local BEAMS, BEAM_LEN = 6, 26
local STARS = 26

local ASH       = { 0.58, 0.56, 0.53 }
local ASH_DARK  = { 0.27, 0.26, 0.25 }
local ASH_LIGHT = { 0.77, 0.75, 0.71 }
local EMBER     = { 0.92, 0.43, 0.16 }
local GOLD      = { 1.00, 0.84, 0.47 }
local WHITE     = { 1.00, 0.97, 0.88 }
local BLACK     = { 0, 0, 0 }
-- The liquid's own particles: gold drawn into the front, and the release's stars (as Bars.lua's).
local GATHER = { texture = "Mote", blend = "ADD", mode = "attract", drag = 1.8 }
local STAR = { texture = "Star", blend = "ADD", buoyancy = 30, drag = 1.6, spin = { -2, 2 } }

local function Secret(v)
    return issecretvalue and issecretvalue(v) or false
end

local function Rand(a, b) return a + (b - a) * math.random() end

local function Smooth(a, b, x)
    local k = math.min(1, math.max(0, (x - a) / (b - a)))
    return k * k * (3 - 2 * k)
end

local function Lerp(a, b, k)
    return { a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k }
end

-- Ash, then embers, then gold, as the soul recovers (p, 0..1).
local function Warmth(p)
    if p < 0.55 then return Lerp(ASH, EMBER, Smooth(0.15, 0.55, p)) end
    return Lerp(EMBER, GOLD, Smooth(0.55, 1, p))
end

local function AtParentLevel(frame, parent)
    if frame.SetUsingParentLevel then
        frame:SetUsingParentLevel(true)
    else
        frame:SetFrameLevel(parent:GetFrameLevel())
    end
end

local function MaskOf(bar)
    local mask = bar.HealthBarMask or bar:GetParent().HealthBarMask
    if type(mask) == "table" and mask.GetObjectType and mask:GetObjectType() == "MaskTexture" then return mask end
end

local function Tex(frame, sublevel, file, mask)
    local t = frame:CreateTexture(nil, "OVERLAY", nil, sublevel)
    if file then t:SetTexture(MEDIA .. file) else t:SetColorTexture(1, 1, 1, 1) end
    t:SetBlendMode("BLEND")
    if mask then t:AddMaskTexture(mask) end
    if t.SetSnapToPixelGrid then
        t:SetSnapToPixelGrid(false)
        t:SetTexelSnappingBias(0)
    end
    return t
end

-- A texture has one alpha (Shield.lua, Tint): colour without it, strength through SetAlpha.
local function Tint(t, c, alpha)
    t:SetVertexColor(c[1], c[2], c[3])
    t:SetAlpha(alpha)
end

local function Gradient(t, c, from, to)
    t:SetGradient("HORIZONTAL", CreateColor(c[1], c[2], c[3], from), CreateColor(c[1], c[2], c[3], to))
end

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------

-- Drawn on bar, the shield's going up read on source (the game's player health bar: bar itself, or the game's bar a
-- taller frame of ours stands in for).
local function New(bar, source)
    local w, h = ns.Bars.Size(bar, 124, 20)
    local mask = MaskOf(bar)
    local s = { bar = bar, source = source or bar, mask = mask, width = w, height = h, specks = {}, falling = {}, embers = {}, beams = {},
                phase = 0, ashIn = 0, auraIn = 0 }
    -- Free of any clip, at the bar's level under the game's text; what lies on the liquid is cut by the bar's mask.
    s.frame = CreateFrame("Frame", nil, bar)
    AtParentLevel(s.frame, bar)
    s.frame:SetAllPoints(bar)
    s.frame:Hide()

    -- The ashen front: grey laid over the liquid's last stretch, strongest at the front, and darker, a little past it
    -- too (the front's waves stand out past its edge). Faded as a whole by its frame.
    s.ash = CreateFrame("Frame", nil, s.frame)
    AtParentLevel(s.ash, s.frame)
    s.ash:SetAllPoints(s.frame)
    s.grey = Tex(s.ash, -6, nil, mask)
    Gradient(s.grey, ASH, 0, ASH_ALPHA)
    s.past = Tex(s.ash, -6, nil, mask)
    Gradient(s.past, ASH, ASH_ALPHA, 0)
    s.dim = Tex(s.ash, -7, nil, mask)
    Gradient(s.dim, BLACK, 0, ASH_DIM)

    -- Ash lodged in the front: each a speck and a glow of its own, which heat up one by one.
    for i = 1, SPECK_MAX do
        local q = { tex = Tex(s.frame, -4, "Mote", mask), glow = Tex(s.frame, -5, "Glow", mask) }
        q.tex:Hide()
        q.glow:Hide()
        s.specks[i] = q
    end
    -- The crescent forming on the front, its halo, and the release's flash.
    s.crescent = Tex(s.frame, -3, "Rim", mask)
    s.halo = Tex(s.frame, -5, "Glow", mask)
    s.flash = Tex(s.frame, -2, "Rim", mask)
    s.flashHalo = Tex(s.frame, -3, "Glow", mask)
    for _, t in ipairs({ s.crescent, s.halo, s.flash, s.flashHalo }) do t:Hide() end

    -- Light ash out of a shattering shield, drifting down free of the bar; and the release's short rays.
    for i = 1, FALLING do
        local t = Tex(s.frame, -1, "Mote")
        t:Hide()
        s.falling[i] = { tex = t, life = 0, age = 1 }
    end
    for i = 1, BEAMS do
        local t = Tex(s.frame, -8, "Beam")
        local len = Rand(BEAM_LEN * 0.6, BEAM_LEN)
        t:SetSize(2 * len, 2 * len)
        t:Hide()
        s.beams[i] = { tex = t, angle = -0.25 - (i - 0.5) / BEAMS * (math.pi - 0.5) + Rand(-0.15, 0.15) }
    end
    return s
end

-- What is drawn in the shield's own glass, made there the first time it is needed (the shield is built by Shield.lua).
-- Kept by shield (s.glassBy), as the shield has one per bar it is drawn on (Shield.lua, Follow): going back to one
-- made before takes its parts again, and the other's are hidden.
local function GlassParts(s, m)
    if s.glassFor == m then return s.glass end
    local old = s.glass
    if old then
        for _, t in ipairs({ old.ashen, old.warm, old.sweep }) do t:Hide() end
        for _, q in ipairs(old.embers) do
            q.age = q.life
            q.tex:Hide()
        end
    end
    s.glassBy = s.glassBy or {}
    if s.glassBy[m] then
        s.glassFor, s.glass = m, s.glassBy[m]
        return s.glass
    end
    local rim = ns.Shield.RIM
    local mv = m.mover
    local g = { embers = {}, mover = mv }
    local function AtRim(t)
        local x = -rim.inset + (1 - rim.line) * rim.width
        t:SetPoint("TOPRIGHT", mv, "TOPRIGHT", x, 0)
        t:SetPoint("BOTTOMRIGHT", mv, "BOTTOMRIGHT", x, 0)
        t:SetWidth(rim.width)
    end
    -- Over the rim (Shield.lua's are -3 and -2): ashen, then warm.
    g.ashen = Tex(mv, -1, "Rim", m.mask)
    AtRim(g.ashen)
    g.warm = Tex(mv, -1, "Rim", m.mask)
    AtRim(g.warm)
    -- Embers rising in the glass and the release's sweep, cut to the glass as its body is.
    for i = 1, GLASS_EMBERS do
        local t = Tex(mv, -2, "Mote", m.mask)
        t:AddMaskTexture(m.edge)
        t:AddMaskTexture(m.fadeIn)
        t:Hide()
        g.embers[i] = { tex = t, life = 0, age = 1 }
    end
    g.sweep = Tex(mv, -2, "Glow", m.mask)
    g.sweep:AddMaskTexture(m.edge)
    g.sweep:AddMaskTexture(m.fadeIn)
    for _, t in ipairs({ g.ashen, g.warm, g.sweep }) do t:Hide() end
    s.glassBy[m] = g
    s.glassFor, s.glass = m, g
    return g
end

--------------------------------------------------------------------------------
-- Timing
--------------------------------------------------------------------------------

local player -- Soul drawn now: on the player frame's health bar, or a taller frame's of ours in its place
local souls = {} -- by the bar each is drawn on
local gameBar -- the player frame's health bar, once found
local driver
-- What a switch of bars carries over: the wait and what was read of it (the release is played again on the new bar).
local CARRIED = { "startAt", "endAt", "rel", "test", "auraSeen", "auraIn", "exists", "live", "err" }
local SHIELD_NAME
local probe = { started = {}, skipped = 0, aura = "not read yet" }
local lastCast -- the player's last cast: { name, at, absorbs }
local selfShield = {} -- castGUID -> true for the player's own Power Word: Shield sent at themselves

local function Start(s, now, seconds, why, test)
    s.startAt, s.endAt, s.rel, s.relAt, s.test = now - (SECONDS - seconds), now + seconds, nil, nil, test
    s.auraSeen = nil
    s.ashIn, s.phase, s.burstSeen = 0, 0, nil
    for _, q in ipairs(s.specks) do q.on = false end
    probe.started[#probe.started + 1] = why
    if #probe.started > 5 then table.remove(probe.started, 1) end
end

local function Stop(s)
    s.startAt, s.endAt, s.rel, s.relAt, s.test = nil, nil, nil, nil, nil
end

-- A shield went up on the player.
local function ShieldUp(s, now)
    if s.endAt and now < s.endAt then return end -- no Power Word: Shield lands during Weakened Soul
    if lastCast and now - lastCast.at < ATTRIBUTE and lastCast.name ~= SHIELD_NAME and lastCast.absorbs then
        probe.skipped = probe.skipped + 1 -- the player's own Ice Barrier or potion
        return
    end
    Start(s, now, SECONDS, "a shield went up")
end

-- Out of combat the debuff can be read: it starts the wait (one missed, or from before a reload), corrects its end,
-- or ends one that was not Weakened Soul after all. In combat it answers nothing to be trusted.
local function ReadAura(s, now)
    if s.test or InCombatLockdown() or UnitAffectingCombat("player") then return end
    local api = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
    if not api then probe.aura = "no API"; return end
    local ok, aura = pcall(api, WEAKENED_SOUL)
    if not ok or Secret(aura) then probe.aura = "secret"; return end
    if type(aura) ~= "table" then
        probe.aura = "none"
        -- "None" is only believed of a debuff that was read before (Heals.lua's rule: the client has answered "none"
        -- for an aura that was on the player). Gone near the end is the wait running out a moment before the timer
        -- (it starts on the shield going up, a little late): let go as if it had. Gone well before was taken off.
        if s.endAt and not s.rel and s.auraSeen then
            if s.endAt - now < 1.5 then s.rel = now else Stop(s) end
        end
        return
    end
    local expires, duration = aura.expirationTime, aura.duration
    if Secret(expires) or type(expires) ~= "number" or expires <= now then probe.aura = "unreadable"; return end
    probe.aura = string.format("%.1f s left", expires - now)
    s.auraSeen = true
    if not s.endAt or s.rel then
        Start(s, now, expires - now, "read out of combat")
    elseif math.abs(s.endAt - expires) > 0.3 then
        s.endAt = expires
        s.startAt = expires - ((type(duration) == "number" and not Secret(duration) and duration > 0) and duration or SECONDS)
    end
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

local function Lodge(s, n)
    local h = s.height
    for _, q in ipairs(s.specks) do
        if n <= 0 then return end
        if not q.on then
            n = n - 1
            q.on, q.a = true, 0
            q.dx, q.dy = -Rand(1, 16), Rand(-(h / 2 - 2.5), h / 2 - 2.5)
            q.lag, q.go, q.ph, q.size = Rand(0.3, 0.6), Rand(0.78, 0.95), Rand(0, 6.28), Rand(2.6, 3.8)
        end
    end
end

local function Lodged(s)
    local n = 0
    for _, q in ipairs(s.specks) do if q.on then n = n + 1 end end
    return n
end

local function HideSpecks(s)
    for _, q in ipairs(s.specks) do
        q.on = false
        q.tex:Hide()
        q.glow:Hide()
    end
end

local function Fall(s, edge)
    local h = s.height
    for _, q in ipairs(s.falling) do
        if q.age >= q.life then
            q.x, q.y = -Rand(3, 19), Rand(-h / 2, h / 2)
            q.vx, q.vy = Rand(-10, 14), Rand(-2, 14)
            q.age, q.life, q.size, q.ph = 0, Rand(1.2, 2.2), Rand(1.8, 3), Rand(0, 6.28)
            q.anchor = edge
            return
        end
    end
end

local function StepFalling(s, dt, t)
    for _, q in ipairs(s.falling) do
        if q.age < q.life then
            q.age = q.age + dt
            if q.age >= q.life then
                q.tex:Hide()
            else
                local k = math.exp(-1.4 * dt)
                q.vx = q.vx * k
                q.vy = q.vy * k - 10 * dt
                q.x = q.x + (q.vx + 3 * math.sin(q.age * 5 + q.ph)) * dt
                q.y = q.y + q.vy * dt
                local f = q.age / q.life
                q.tex:ClearAllPoints()
                q.tex:SetPoint("CENTER", q.anchor, "RIGHT", q.x, q.y)
                q.tex:SetSize(q.size, q.size)
                Tint(q.tex, ASH_LIGHT, 0.85 * math.min(1, q.age / 0.12) * (1 - f))
                q.tex:Show()
            end
        end
    end
end

-- Anchors a texture's crescent (Rim.tga) with its line x past the region's right edge.
local function AtLine(t, region, x, width)
    local rim = ns.Shield.RIM
    local off = x + (1 - rim.line) * width
    t:ClearAllPoints()
    t:SetPoint("TOPRIGHT", region, "TOPRIGHT", off, 0)
    t:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", off, 0)
    t:SetWidth(width)
end

local function HideFront(s)
    s.ash:Hide()
    s.crescent:Hide()
    s.halo:Hide()
    for _, q in ipairs(s.specks) do
        q.tex:Hide()
        q.glow:Hide()
    end
end

local function HideGlass(s)
    local g = s.glass
    if not g then return end
    g.ashen:Hide()
    g.warm:Hide()
    g.sweep:Hide()
    for _, q in ipairs(g.embers) do
        q.age = q.life
        q.tex:Hide()
    end
end

-- The front while the wait runs, no glass over it: ashen, with specks heating up and a crescent forming.
local function Front(s, dt, t, p, pulse, front)
    local liquid = ns.Bars.Liquid(s.bar)
    s.ashIn = math.min(1, s.ashIn + dt / 0.6)
    local ash = 0.95 * (1 - Smooth(0.4, 0.95, p)) * Smooth(0, 1, s.ashIn)
    s.ash:SetAlpha(ash)
    if not s.ash:IsShown() or s.ashOn ~= front then
        s.ashOn = front
        s.grey:ClearAllPoints()
        s.grey:SetPoint("TOPRIGHT", front, "TOPRIGHT")
        s.grey:SetPoint("BOTTOMRIGHT", front, "BOTTOMRIGHT")
        s.grey:SetWidth(ASH_W)
        s.dim:ClearAllPoints()
        s.dim:SetAllPoints(s.grey)
        s.past:ClearAllPoints()
        s.past:SetPoint("TOPLEFT", front, "TOPRIGHT")
        s.past:SetPoint("BOTTOMLEFT", front, "BOTTOMRIGHT")
        s.past:SetWidth(2)
        s.ash:Show()
    end

    if Lodged(s) == 0 and p < 0.75 then Lodge(s, SPECKS - 2) end
    s.fleckIn = (s.fleckIn or 0) - dt * (1.2 + 3 * p)
    if s.fleckIn <= 0 then
        s.fleckIn = 1
        if p < 0.75 then Lodge(s, 1) end
    end
    local w, h = s.width, s.height
    for _, q in ipairs(s.specks) do
        if q.on then
            local x = q.dx + 0.4 * math.sin(t * 1.3 + q.ph)
            local y = q.dy + 0.5 * math.sin(t * 0.9 + q.ph * 2)
            if p >= q.go then
                -- Drawn into the crescent, as gold.
                q.on = false
                q.tex:Hide()
                q.glow:Hide()
                if liquid then liquid:EmitMote(w + x, h / 2 + y, 0, 0, 0.8, q.size * 2, GOLD, GOLD, GATHER) end
            else
                q.a = math.min(1, q.a + dt / 0.4)
                local heat = Smooth(q.lag, q.lag + 0.35, p)
                local flick = 0.7 + 0.3 * math.sin(t * 17 + q.ph)
                local c = heat <= 0 and ASH_DARK or Lerp(ASH_DARK, Lerp(EMBER, GOLD, Smooth(0.5, 1, heat * p)),
                    math.min(1, heat * 2))
                q.tex:ClearAllPoints()
                q.tex:SetPoint("CENTER", front, "RIGHT", x, y)
                q.tex:SetSize(q.size, q.size)
                Tint(q.tex, c, q.a * (0.9 + 0.1 * heat) * (heat > 0 and flick or 1))
                q.tex:Show()
                if heat > 0 then
                    q.glow:ClearAllPoints()
                    q.glow:SetPoint("CENTER", front, "RIGHT", x, y)
                    q.glow:SetSize(q.size * 3, q.size * 3)
                    Tint(q.glow, EMBER, 0.3 * heat * flick * q.a)
                    q.glow:Show()
                else
                    q.glow:Hide()
                end
            end
        end
    end

    -- The crescent: faint and slow at first, then brighter and quicker; gold gathering into it near the end.
    local form = Smooth(0.25, 1, p)
    local c = Warmth(p)
    if form > 0 then
        AtLine(s.crescent, front, -0.6, 12)
        Tint(s.crescent, Lerp(c, WHITE, 0.25 * form), math.min(1, 0.85 * form ^ 1.3 * pulse))
        s.crescent:Show()
        s.halo:ClearAllPoints()
        s.halo:SetPoint("CENTER", front, "RIGHT", -1.5, 0)
        s.halo:SetSize(16, h * 1.5)
        Tint(s.halo, c, math.min(1, 0.35 * form ^ 1.5 * pulse))
        s.halo:Show()
    else
        s.crescent:Hide()
        s.halo:Hide()
    end
    if liquid then
        if p > 0.6 then
            liquid:Warm(0.6 * (p - 0.6) / 0.4)
            s.gatherAcc = (s.gatherAcc or 0) + dt * 14 * (p - 0.6) / 0.4
            while s.gatherAcc >= 1 do
                s.gatherAcc = s.gatherAcc - 1
                local a, d = Rand(0, 2 * math.pi), Rand(14, 24)
                liquid:EmitMote(w + math.cos(a) * d, h / 2 + math.sin(a) * d * 0.6, -math.sin(a) * 20,
                    math.cos(a) * 20, Rand(0.8, 1.2), Rand(5, 8), c, GOLD, GATHER)
            end
        end
    end
end

local function StepEmbers(s, g, dt, t, p)
    local rim = ns.Shield.RIM
    local h = s.height
    s.emberAcc = (s.emberAcc or 0) + dt * (6 + 16 * p)
    while s.emberAcc >= 1 do
        s.emberAcc = s.emberAcc - 1
        for _, q in ipairs(g.embers) do
            if q.age >= q.life then
                q.x, q.y = -rim.inset - Rand(2, 40), -Rand(2, h - 1.5)
                q.vx, q.vy = Rand(-2, 2), Rand(1, 5)
                q.age, q.life, q.size, q.ph = 0, Rand(0.9, 1.6), Rand(2, 3), Rand(0, 6.28)
                break
            end
        end
    end
    local c = Warmth(p)
    local ember = Smooth(0.25, 0.7, p)
    for _, q in ipairs(g.embers) do
        if q.age < q.life then
            q.age = q.age + dt
            if q.age >= q.life then
                q.tex:Hide()
            else
                q.x = q.x + (q.vx + 2 * math.sin(q.age * 5 + q.ph)) * dt
                q.y = q.y + q.vy * dt
                local f = q.age / q.life
                local flick = 0.75 + 0.25 * math.sin(t * 23 + q.ph)
                q.tex:ClearAllPoints()
                q.tex:SetPoint("CENTER", g.mover, "TOPRIGHT", q.x, q.y)
                q.tex:SetSize(q.size, q.size)
                Tint(q.tex, Lerp(ASH_DARK, c, ember), math.min(1, q.age / 0.12) * (1 - f) * (0.6 + 0.4 * ember) * flick)
                q.tex:Show()
            end
        end
    end
end

-- Under a shield that still holds: its rim ashen and warming, embers in its glass.
local function Glass(s, m, dt, t, p, pulse)
    local g = GlassParts(s, m)
    Tint(g.ashen, ASH, 0.8 * (1 - Smooth(0, 0.9, p)))
    g.ashen:Show()
    Tint(g.warm, Warmth(p), math.min(1, 0.55 * Smooth(0.3, 1, p) * pulse))
    g.warm:Show()
    StepEmbers(s, g, dt, t, p)
end

-- The release: the crescent white-hot with short rays and stars from the front, or the rim, a sweep of light across
-- the glass first if a shield still holds. k is seconds since.
local function Release(s, k, at, x, glass)
    local h = s.height
    if k < RELEASE then
        local a = (1 - k / RELEASE) ^ 1.6
        AtLine(s.flash, at, x, 12 + 6 * k / RELEASE)
        Tint(s.flash, WHITE, a)
        s.flash:Show()
        s.flashHalo:ClearAllPoints()
        s.flashHalo:SetPoint("CENTER", at, "RIGHT", x - 1, 0)
        s.flashHalo:SetSize(30, h * 2)
        Tint(s.flashHalo, GOLD, 0.6 * a)
        s.flashHalo:Show()
        for _, b in ipairs(s.beams) do
            b.tex:ClearAllPoints()
            b.tex:SetPoint("CENTER", at, "RIGHT", x, 0)
            b.tex:SetRotation(b.angle)
            Tint(b.tex, WHITE, 0.7 * a)
            b.tex:Show()
        end
    else
        s.flash:Hide()
        s.flashHalo:Hide()
        for _, b in ipairs(s.beams) do b.tex:Hide() end
    end
    local g = s.glass
    if glass and g then
        -- The rim's ashen and warm crescents give way to the flash; the embers are spent.
        g.ashen:Hide()
        g.warm:Hide()
        for _, q in ipairs(g.embers) do
            q.age = q.life
            q.tex:Hide()
        end
    end
    if glass and g and k < 0.45 then
        local rim = ns.Shield.RIM
        g.sweep:ClearAllPoints()
        g.sweep:SetPoint("CENTER", g.mover, "RIGHT", -rim.inset - 60 * (1 - k / 0.45), 0)
        g.sweep:SetSize(18, h * 1.6)
        Tint(g.sweep, Lerp(GOLD, WHITE, 0.4), 0.6)
        g.sweep:Show()
    elseif g then
        g.sweep:Hide()
    end
end

local function LetGo(s, at, x, glass)
    local liquid = ns.Bars.Liquid(s.bar)
    if liquid and not glass then
        local w, h = s.width, s.height
        for _ = 1, STARS do
            local a, speed = Rand(0, 2 * math.pi), Rand(30, 110)
            liquid:EmitMote(w - Rand(0, 4), h / 2 + Rand(-h / 3, h / 3), math.cos(a) * speed,
                math.sin(a) * speed * 0.7 + 15, Rand(0.6, 1.1), Rand(8, 13), WHITE, GOLD, STAR)
        end
        liquid:Ripple(0.5)
        liquid:Warm(0.8)
    end
    s.relAt, s.relX, s.relGlass = at, x, glass
end

local function HideAll(s)
    s.frame:Hide()
    HideFront(s)
    HideSpecks(s)
    HideGlass(s)
    for _, q in ipairs(s.falling) do
        q.age = q.life
        q.tex:Hide()
    end
end

local function Update(s, dt)
    local now = GetTime()
    local bar = s.bar
    -- Going up, as the game's absorb display says; where it is secret, the player's own shield on themselves says.
    local exists = ns.Shield.Exists(s.source)
    if exists == true and s.exists == false then ShieldUp(s, now) end
    s.exists = exists
    s.auraIn = s.auraIn - dt
    if s.auraIn <= 0 then
        s.auraIn = AURA_EVERY
        ReadAura(s, now)
    end
    if s.endAt and not s.rel and now >= s.endAt then
        s.rel = now -- it is over: the release, if anyone sees it
    end
    if s.rel and now - s.rel >= RELEASE_DONE then
        Stop(s)
    end
    if not s.endAt or ns.Bars.Sight(bar) ~= "shown" then
        if s.frame:IsShown() then HideAll(s) end
        return
    end

    local w, h = ns.Bars.Size(bar, s.width, s.height)
    if w >= 1 and h >= 1 then s.width, s.height = w, h end
    s.t = (s.t or 0) + dt
    local t = s.t
    s.frame:Show()

    local m = ns.Shield.State()
    -- Only the shield on the bar this is drawn on: for a frame while the two switch bars (each in its own OnUpdate)
    -- the other may still be on the old one.
    if m and m.bar ~= bar then m = nil end
    local shown = m and m.clip:IsShown()
    local glass = shown and not m.ending
    -- The ash comes only once a shattering shield's glass is gone: over the breaking glass it was a grey block.
    local breaking = shown and m.ending and (not m.burstDone or (m.endT or 0) < 0.75)
    local front = ns.Bars.Mover(bar) or bar:GetStatusBarTexture()
    local edge = ns.Bars.Edge(bar) or bar:GetStatusBarTexture()

    -- The shattering shield leaves ash: light ash drifting down off it, and some lodged in the front.
    if shown and m.ending and m.burstDone and not s.burstSeen and not s.rel then
        s.burstSeen = true
        for _ = 1, FALLING do Fall(s, edge) end
        HideSpecks(s)
        Lodge(s, SPECKS)
    end
    StepFalling(s, dt, t)

    if s.rel then
        local k = now - s.rel
        if not s.relAt then
            if glass then LetGo(s, edge, -ns.Shield.RIM.inset - 0.6, true) else LetGo(s, front, -0.6, false) end
        end
        HideFront(s)
        HideSpecks(s)
        if not s.relGlass then HideGlass(s) end
        Release(s, k, s.relAt, s.relX, s.relGlass)
        return
    end

    local p = math.min(1, math.max(0, (now - s.startAt) / (s.endAt - s.startAt)))
    s.phase = (s.phase + dt / (0.9 + (0.2 - 0.9) * p)) % 1
    local pulse = 0.6 + 0.4 * math.cos(2 * math.pi * s.phase)
    if glass then
        HideFront(s)
        s.ashIn = 0
        Glass(s, m, dt, t, p, pulse)
    elseif breaking then
        HideFront(s)
        HideGlass(s)
    else
        HideGlass(s)
        Front(s, dt, t, p, pulse, front)
    end
end

--------------------------------------------------------------------------------
-- The driver, events and settings
--------------------------------------------------------------------------------

-- The bar Weakened Soul is drawn on now: our taller player frame's while it shows in place of the game's
-- (TallFrames.lua), else the game's, as the shield's (Shield.lua).
local function Follow()
    local bar = ns.TallFrames and ns.TallFrames.PlayerHealth() or gameBar
    if not bar or (player and player.bar == bar) then return end
    local s = souls[bar]
    if not s then
        s = New(bar, gameBar)
        souls[bar] = s
    end
    if player then
        for _, k in ipairs(CARRIED) do s[k] = player[k] end
        s.relAt = nil
        pcall(HideAll, player)
    end
    player = s
end

local function OnUpdate(_, elapsed)
    local dt = math.min(elapsed, 0.1)
    if dt <= 0 or not player or not player.live or player.err then return end
    Follow()
    local ok, err = pcall(Update, player, dt)
    if not ok then
        player.err = tostring(err)
        pcall(HideAll, player)
        ns.Core.Print("Error in Weakened Soul, which is off until a reload: " .. player.err)
    end
end

local function SpellName(id)
    local ok, name = pcall(C_Spell and C_Spell.GetSpellName or GetSpellInfo, id)
    return ok and type(name) == "string" and not Secret(name) and name or nil
end

-- Whether a spell's description says it absorbs damage (English only: in other languages such a spell is taken for
-- Power Word: Shield in combat, until the debuff is read out of it).
local function Absorbs(id)
    if not (C_Spell and C_Spell.GetSpellDescription) then return false end
    local ok, text = pcall(C_Spell.GetSpellDescription, id)
    return ok and type(text) == "string" and not Secret(text) and text:lower():find("absorb") ~= nil
end

local function OnEvent(_, event, unit, a1, a2, a3)
    if not player or not player.live or player.err then return end
    SHIELD_NAME = SHIELD_NAME or SpellName(SHIELD_SPELL)
    if event == "UNIT_SPELLCAST_SENT" then
        -- unit, target, castGUID, spellID: the player's own shield, at themselves.
        local target, guid, id = a1, a2, a3
        if Secret(target) or Secret(guid) or Secret(id) then return end
        if SHIELD_NAME and SpellName(id) == SHIELD_NAME and target == UnitName("player") and guid then
            selfShield[guid] = true
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local guid, id = a1, a2
        if Secret(id) then return end
        local name = SpellName(id)
        if not name then return end
        lastCast = { name = name, at = GetTime(), absorbs = name ~= SHIELD_NAME and Absorbs(id) }
        if not Secret(guid) and guid and selfShield[guid] then
            selfShield[guid] = nil
            -- Only where the game's absorb display will not say; where it does, the shield going up starts it.
            if player.exists == nil and not (player.endAt and GetTime() < player.endAt) then
                Start(player, GetTime(), SECONDS, "your own shield on yourself")
            end
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        player.auraIn = 0
    end
end

-- After the setting changes, and at login.
function Soul.Apply()
    local live = ns.Core.Get("weakenedSoul") and true or false
    if live and not player then
        local bar = ns.Bars.Find("playerHealth")
        if type(bar) == "table" and bar.GetStatusBarTexture then
            gameBar = bar
            player = New(bar)
            souls[bar] = player
        end
    end
    SHIELD_NAME = SHIELD_NAME or SpellName(SHIELD_SPELL)
    if player then
        if live and not player.live then player.exists = nil end
        player.live = live
        if not live then
            Stop(player)
            HideAll(player)
        end
    end
    if live and player and not driver then
        driver = CreateFrame("Frame")
        driver:SetScript("OnUpdate", ns.Timed("Weakened Soul", OnUpdate))
        driver:SetScript("OnEvent", ns.Timed("Weakened Soul: events", OnEvent))
    end
    if not driver then return end
    driver:SetShown(live)
    if live then
        driver:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
        driver:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        driver:RegisterEvent("PLAYER_REGEN_ENABLED")
    else
        driver:UnregisterAllEvents()
    end
end

-- For the tests: Soul on the player frame (nil until built).
function Soul.State()
    return player
end

-- /sab soul test: the wait as if a shield had just gone up on you, to see it without one.
function Soul.Test()
    if not player then return "Weakened Soul: off, or the player frame's health bar was not found" end
    Start(player, GetTime(), SECONDS, "/sab soul test", true)
    return "Weakened Soul test: 15 seconds of the wait on your health bar."
end

-- For /sab soul: what it saw and what it is doing.
function Soul.Debug()
    local out = {}
    if not ns.Core.Get("weakenedSoul") then out[1] = "Weakened Soul: off (Weakened Soul in the editor)" end
    if not player then
        out[#out + 1] = "Weakened Soul: the player frame's health bar was not found"
        return out
    end
    local s = player
    local now = GetTime()
    local state = "idle"
    if s.rel then
        state = "letting go"
    elseif s.endAt then
        state = string.format("%.1f s left", s.endAt - now)
    end
    out[#out + 1] = string.format("Weakened Soul: %s; a shield as the game says: %s%s", state,
        s.exists == nil and "can't tell" or tostring(s.exists), s.err and (", error: " .. s.err) or "")
    out[#out + 1] = string.format("Started by: %s; shields put down to your own other absorbs: %d; the debuff out of "
        .. "combat: %s", #probe.started > 0 and table.concat(probe.started, ", ") or "nothing yet", probe.skipped,
        probe.aura)
    return out
end
