-- Damage over time: tracks the player's DoTs on each mob and what they still have to deal, for the marker on
-- the target's health bar (Marker.lua). Off unless the dots setting is on; while off no event is registered.
--
-- Ported from DoesItDie 0.9.0 by Joe Greive (MIT licence, notice below), which worked
-- out on Forever what can be read and how ticks behave. Its tracking is kept as it was, in its own words where
-- they still fit; its displays, options, nameplates and other languages are not ported (English spell text
-- only), and its trace goes to a short in-memory log for /sab dots instead of the saved variables.
--
-- On Forever the target's health is secret and the combat log is closed to addons, so addon code can never
-- compare "health vs DoT damage" itself. What stays readable:
--   * our own casts (UNIT_SPELLCAST_*) and spell descriptions -> which DoT, base damage, duration
--   * UNIT_COMBAT damage amounts on units -> actual tick sizes (already include resists/reductions)
-- The numbers here are plain; the comparison with health is left to StatusBars (Marker.lua).
--
-- MIT License
--
-- Copyright (c) 2026 Joe Greive
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
-- documentation files (the "Software"), to deal in the Software without restriction, including without
-- limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the
-- Software, and to permit persons to whom the Software is furnished to do so, subject to the following
-- conditions:
--
-- The above copyright notice and this permission notice shall be included in all copies or substantial portions
-- of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED
-- TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
-- THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
-- CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
-- DEALINGS IN THE SOFTWARE.

local _, ns = ...

local Dots = {}
ns.Dots = Dots

local DEFAULT_TICK_INTERVAL = 3
-- Seconds either side of an expected tick time. Observed on Forever: the first tick lands within ~0.1s of one
-- interval after the cast, and later ticks within ~0.1s of the first tick's rhythm. Tight windows keep melee
-- auto-attacks (same Physical school as bleeds, similar size, ~1s rhythm) from passing as ticks.
local TICK_MATCH_WINDOW = 0.45
local TICK_MATCH_WINDOW_ANCHORED = 0.25
local MISSED_TICKS_BEFORE_DROP = 2  -- a DoT that never ticks was resisted/immune
-- Projectile DoTs start when the projectile lands, not on the cast event: their first tick may be this much
-- later than one interval after the cast.
local PROJECTILE_TRAVEL = 1.5
local PROJECTILE_DOTS = {
    ["Serpent Sting"] = true, ["Fireball"] = true, ["Pyroblast"] = true, ["Frostfire Bolt"] = true,
}
-- Once a DoT's tick size is known, same-school hits further off than this are someone else's (the Imp's
-- Firebolt next to Immolate, white hits next to Rip). The minimum slack of 1 covers rounding (3 vs 4).
local TICK_AMOUNT_TOLERANCE = 0.25
-- Check for the first tick against a size learned on an earlier cast (gear/AP may have changed a little).
local FIRST_TICK_AMOUNT_TOLERANCE = 0.3
-- A crit tick is 1.5-2x a normal one; anything else flagged as a crit (white-hit crits) isn't this DoT.
local CRIT_MIN_RATIO, CRIT_MAX_RATIO = 1.3, 2.3
local TICKS_VERSION = 1  -- bump to discard learned tick sizes from older, buggier versions

-- Tick intervals that differ from the 3s default and aren't stated in the description.
local KNOWN_TICK_INTERVALS = {
    ["Insect Swarm"] = 2,
    ["Curse of Agony"] = 2,
    ["Bane of Agony"] = 2, -- Forever's name for Curse of Agony
    ["Fireball"] = 2,
    ["Holy Fire"] = 2,
    ["Rip"] = 2,
    ["Rupture"] = 2,
}

-- DoTs whose ticks aren't even: each tick is the average tick times its factor (factors average 1, so the
-- tooltip total still holds). Agony is back-loaded on Forever: ticks 3,3,3,3 then 6,6,... then 9s.
local TICK_SHAPES = {}
do
    local agony = { 0.5, 0.5, 0.5, 0.5, 1, 1, 1, 1, 1.5, 1.5, 1.5, 1.5 }
    TICK_SHAPES["Bane of Agony"] = agony
    TICK_SHAPES["Curse of Agony"] = agony
end

-- Descriptions that don't name their school.
local SCHOOL_BY_NAME = {
    ["Siphon Life"] = 32, ["Corruption"] = 32, ["Fireball"] = 4, ["Pyroblast"] = 4,
}

-- Read like DoTs but aren't one on the current target: ground/area effects, channels, traps, and
-- delayed damage (Wyvern Sting only starts after the sleep).
local IGNORED_SPELLS = {
    ["Rain of Fire"] = true, ["Hellfire"] = true, ["Blizzard"] = true, ["Flamestrike"] = true,
    ["Consecration"] = true, ["Hurricane"] = true, ["Volley"] = true,
    ["Drain Life"] = true, ["Drain Soul"] = true, ["Drain Mana"] = true, ["Health Funnel"] = true,
    ["Mind Flay"] = true, ["Arcane Missiles"] = true, ["Starshards"] = true,
    ["Explosive Trap"] = true, ["Wyvern Sting"] = true,
}

-- Traps that put a DoT on the first enemy to walk in. Placing one only arms it (the trap, not the player, casts
-- the DoT when it springs, so no cast event says when or on whom); the DoT starts on the mob that takes the
-- first plausible unmatched tick of its school while it's armed. See springTrap.
local TRAP_DOTS = { ["Immolation Trap"] = true }

-- One spell ID per entry of the name-keyed tables above (Classic rank 1; all ranks share the name). At login
-- the tables also get the name this client reports for it, which covers Forever's own renames.
local SPELL_IDS = {
    ["Insect Swarm"] = 5570, ["Curse of Agony"] = 980, ["Fireball"] = 133, ["Holy Fire"] = 14914,
    ["Rip"] = 1079, ["Rupture"] = 1943, ["Siphon Life"] = 18265,
    ["Rain of Fire"] = 5740, ["Hellfire"] = 1949, ["Blizzard"] = 10, ["Flamestrike"] = 2120,
    ["Consecration"] = 26573, ["Hurricane"] = 16914, ["Volley"] = 1510,
    ["Drain Life"] = 689, ["Drain Soul"] = 1120, ["Drain Mana"] = 5138, ["Health Funnel"] = 755,
    ["Mind Flay"] = 15407, ["Arcane Missiles"] = 5143, ["Starshards"] = 10797,
    ["Immolation Trap"] = 13795, ["Explosive Trap"] = 13813, ["Wyvern Sting"] = 19386,
    ["Serpent Sting"] = 1978, ["Pyroblast"] = 11366, ["Corruption"] = 172,
}
local NAME_TABLES = { KNOWN_TICK_INTERVALS, TICK_SHAPES, SCHOOL_BY_NAME, IGNORED_SPELLS, PROJECTILE_DOTS, TRAP_DOTS }

local SCHOOL_MASKS = {
    Physical = 1, Holy = 2, Fire = 4, Nature = 8, Frost = 16, Shadow = 32, Arcane = 64,
    Frostfire = 4 + 16, -- Forever's Frostfire Bolt: combined schools report as the OR of their masks
}

local MAX_TRACE_LINES = 200

local ticks = {}            -- learned average tick sizes, saved: spellID (or "spellIDxN" for finishers) -> size
local dotsByTarget = {}     -- targetKey -> { [spellName] = dot }
local warnedSecretGuid = false
local log = {}              -- the last MAX_TRACE_LINES trace lines, for /sab dots
local enabled = false

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function trace(msg)
    log[#log + 1] = string.format("%.1f %s", GetTime(), msg)
    if #log > MAX_TRACE_LINES then table.remove(log, 1) end
end

local function isSecret(v)
    if type(issecretvalue) ~= "function" then return false end
    local ok, r = pcall(issecretvalue, v)
    return ok and r or false
end

-- The nameplate token ("nameplate3") of the mob behind `unit`, or nil (no plate, plates off, or unreadable).
-- Creature GUIDs are secret in Forever's instances, but a mob keeps its nameplate token from
-- NAME_PLATE_UNIT_ADDED to NAME_PLATE_UNIT_REMOVED, so the token stands in for the GUID while the plate is up;
-- the nameplate events drop its DoTs before the token goes to another mob.
local function plateTokenFor(unit)
    if type(unit) == "string" and unit:match("^nameplate%d+$") then return unit end
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return nil end
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    if not ok or not plate or isSecret(plate) or type(plate) ~= "table" then return nil end
    local token = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
    if type(token) ~= "string" or isSecret(token) or not token:match("^nameplate%d+$") then return nil end
    return token
end

-- Stable key for the mob behind a unit token, or nil if the unit can't be tracked: its GUID when readable (open
-- world); "plate:nameplateN" when the GUID is secret (instances) and the mob has a nameplate; "target" as the last
-- resort (secret GUID, no plate: only the current target is tracked, and target changes drop its DoTs).
local function unitKey(unit)
    local ok, guid = pcall(UnitGUID, unit)
    if ok and guid ~= nil and not isSecret(guid) then return guid end
    local token = plateTokenFor(unit)
    if token then
        if warnedSecretGuid ~= "plate" then
            warnedSecretGuid = "plate"
            trace("Mob GUIDs are secret here (instance?); tracking each mob by its nameplate instead")
        end
        return "plate:" .. token
    end
    if unit ~= "target" or not (ok and isSecret(guid)) then return nil end
    if warnedSecretGuid ~= "target" then
        warnedSecretGuid = "target"
        trace("Target GUID is secret and it has no nameplate; tracking DoTs on the current target only")
    end
    return "target"
end

local function spellNameAndDescription(spellID)
    local name, desc
    if C_Spell and C_Spell.GetSpellName then
        name = C_Spell.GetSpellName(spellID)
    elseif GetSpellInfo then
        name = GetSpellInfo(spellID)
    end
    local descFn = (C_Spell and C_Spell.GetSpellDescription) or GetSpellDescription
    if descFn then desc = descFn(spellID) end
    return name, desc
end

local function schoolFromWords(words)
    local school = SCHOOL_MASKS.Physical
    for word in words:gmatch("%a+") do
        if SCHOOL_MASKS[word] then school = SCHOOL_MASKS[word] end
    end
    return school
end

-- Finishers (Rip, Rupture) list their DoT per combo point:
--   "1 point : 243 damage over 12 sec. 2 points: 396 damage over 12 sec. ..."   (Rip; note the stray space)
--   "1 point: 25 damage over 8 secs\n ... 5 points: 87 damage over 16 secs"      (Rupture)
-- Returns total, school, duration for the given points (clamped to the listed range), or nil if the
-- finisher has no per-point DoT (e.g. Eviscerate).
local function parseFinisher(desc, comboPoints)
    local byPoints, highest = {}, 0
    for pointsText, amount, secs in desc:gmatch("(%d+) points?%s*:%s*(%d+) damage over (%d+%.?%d*) sec") do
        local points = tonumber(pointsText)
        byPoints[points] = { total = tonumber(amount), duration = tonumber(secs) }
        highest = math.max(highest, points)
    end
    if highest == 0 then return nil end
    local entry = byPoints[math.max(1, math.min(comboPoints, highest))] or byPoints[highest]
    return entry.total, SCHOOL_MASKS.Physical, entry.duration
end

-- Returns total damage, school mask, duration and (if the description states it) tick interval.
--   "... 10 Nature damage over 15 sec."  Takes the last such clause, so Immolate's
--       "11 Fire damage and then an additional 20 Fire damage over 15 sec" yields the periodic part.
--   "Transfers 15 health from the target to the caster every 3 sec. Lasts 30 sec."  (Siphon Life)
-- comboPoints is only used for finishers.
local function parseDot(desc, comboPoints)
    if type(desc) ~= "string" or isSecret(desc) then return nil end
    if desc:find("Finishing move") then return parseFinisher(desc, comboPoints or 5) end
    -- Weapon enchants (rogue poisons) describe a proc DoT but aren't cast on the target.
    if desc:find("[Cc]oats a weapon") then return nil end
    -- Heals over time: Forever's Renew reads "Heals the target of 830 damage over 15 sec".
    if desc:find("^Heals") then return nil end

    local total, school, duration
    for amount, words, secs in desc:gmatch("(%d+)%s*([%a ]-)%s*damage over (%d+%.?%d*) sec") do
        total, school, duration = tonumber(amount), schoolFromWords(words), tonumber(secs)
    end
    if total and duration > 0 then return total, school, duration end

    local amount, words, every = desc:match("(%d+)%s*([%a ]-)%s*damage every (%d+%.?%d*) sec")
    if not amount then
        amount, every = desc:match("(%d+) health.-every (%d+%.?%d*) sec")
        words = ""
    end
    local lasts = desc:match("[Ll]asts (%d+%.?%d*) sec")
    if amount and every and lasts then
        every, lasts = tonumber(every), tonumber(lasts)
        if every > 0 and lasts > 0 then
            return tonumber(amount) * math.floor(lasts / every + 0.5), schoolFromWords(words), lasts, every
        end
    end
end

---------------------------------------------------------------------------
-- DoT tracking
---------------------------------------------------------------------------

-- Best known average damage per tick: observed average of non-crit ticks, else learned from earlier casts,
-- else the description. Crits are one-offs, so they never raise the expectation for later ticks. For shaped
-- DoTs (TICK_SHAPES) ticks are stored divided by their factor, so this is the average tick, not the latest.
local function expectedTick(dot)
    if dot.normalTicks > 0 then return dot.tickSum / dot.normalTicks end
    return (dot.tickKey and ticks[dot.tickKey]) or (dot.total / dot.totalTicks)
end

-- Which tick of the DoT (1 = first) lands around `when`.
local function tickNumberAt(dot, when)
    return math.max(1, math.floor((when - dot.appliedAt) / dot.interval + 0.5))
end

-- The factor for tick `number` (1 for evenly ticking DoTs). Shapes are stretched to the DoT's tick count.
local function tickShape(dot, number)
    local shape = dot.shape
    if not shape then return 1 end
    local i = math.ceil(math.min(math.max(number, 1), dot.totalTicks) / dot.totalTicks * #shape)
    return shape[math.max(1, math.min(i, #shape))]
end

-- A doubtful DoT (an avoid right after the cast that may not have been its own) doesn't count toward the
-- marker until its first tick lands.
local function isWaiting(dot)
    return dot.ticksSeen == 0 and dot.doubtful or false
end

-- Combo points, for finishers. By UNIT_SPELLCAST_SUCCEEDED they're already spent, so they're read when the
-- cast is sent. They can be unreadable in combat on Forever, so they're also counted here: builders say
-- "Awards N combo point(s)" in their tooltips; a dodge/parry/miss right after takes them back; a finisher or a
-- target change resets the count. If neither source knows, finishers assume the lowest entry, so the estimate
-- errs low (no false kill icon) and nothing is learned from that cast.
local COMBO_CAP = 5
local COMBO_CACHE_SECONDS = 3
local comboAtSend, lastComboPoints, lastComboAt = nil, nil, 0
local countedPoints = 0

-- Cast outcomes. UNIT_COMBAT reports a dodge/parry/miss/resist/immune on the target, but not which attack it
-- belongs to. A cast's own result arrives almost at once, so the first outcome on the target right after a cast
-- decides: a hit means it landed, an avoid means it didn't. Results can also arrive just before the cast event,
-- hence the short look-back.
local OUTCOME_WINDOW = 0.4
local OUTCOME_LOOKBACK = 0.25
-- A bleed's own avoid arrives with the cast (same frame in Forever's logs); the player's white swings are
-- avoided all the time, so for a Physical DoT only an avoid this close to the cast is taken as its own. Seen in
-- game with Rend: swings parried or dodged a moment after the cast dropped Rends that had landed.
local PHYSICAL_OUTCOME_WINDOW = 0.2
local AVOIDED_ACTIONS = {
    MISS = true, DODGE = true, PARRY = true, EVADE = true, IMMUNE = true, DEFLECT = true, RESIST = true, REFLECT = true,
}
-- Spells can't be dodged or parried: next to a spell DoT, these were someone's melee (usually the pet's).
local MELEE_ONLY_AVOIDS = { DODGE = true, PARRY = true, DEFLECT = true }
local lastBuilder    -- { key, points, at }: builder whose outcome isn't known yet
-- A DoT with a direct part (Rake, Immolate) gets two results: the direct part can hit while the DoT itself is
-- IMMUNE. So a cast whose direct part hit stays pending (landedAt) for the rest of its window, and only an
-- IMMUNE can still remove its DoT.
local lastDotCast    -- { key, name, dot, previous, at, landedAt }: DoT cast whose outcome isn't known yet
local lastOutcome    -- { key, avoided, action, school, at, immune }: most recent outcome on a mob
local armedTrap      -- see TRAP_DOTS
-- The mob each cast was aimed at, by cast GUID, taken when the cast is sent: a player who tabs to the next mob
-- straight away has changed target by the time UNIT_SPELLCAST_SUCCEEDED comes.
local sentTargets = {} -- castGUID -> { key, at }
local SENT_TARGET_SECONDS = 10

-- The combo points the game's own display shows (ComboFrame, a lit ComboPointN.Highlight per point), for when the
-- number itself is secret. 0 when the frame is hidden, nil if unreadable.
local function displayedComboPoints()
    local frame = _G.ComboFrame
    if type(frame) ~= "table" or type(frame.IsShown) ~= "function" then return nil end
    local ok, shown = pcall(frame.IsShown, frame)
    if not ok or isSecret(shown) then return nil end
    if not shown then return 0 end
    local count = 0
    for index = 1, 12 do
        local point = _G["ComboPoint" .. index]
        local highlight = type(point) == "table" and point.Highlight
        if type(highlight) ~= "table" or type(highlight.GetAlpha) ~= "function" then break end
        local okV, visible = pcall(point.IsShown, point)
        local okA, alpha = pcall(highlight.GetAlpha, highlight)
        if not okV or not okA or isSecret(visible) or isSecret(alpha) then return nil end
        if type(alpha) ~= "number" then return nil end
        if visible and alpha > 0.5 then count = count + 1 end
    end
    return count
end

local function readComboPoints()
    local best
    local function consider(ok, points)
        if ok and type(points) == "number" and not isSecret(points) then best = math.max(best or 0, points) end
    end
    if GetComboPoints then consider(pcall(GetComboPoints, "player", "target")) end
    if UnitPower and Enum and Enum.PowerType and Enum.PowerType.ComboPoints then
        consider(pcall(UnitPower, "player", Enum.PowerType.ComboPoints))
    end
    -- Only when neither API gave a number: the display is read by appearance, so it must never raise a
    -- readable count (too many points would mean a too-high estimate, a false kill icon).
    if best == nil then consider(true, displayedComboPoints()) end
    return best
end

local function rememberComboPoints()
    local points = readComboPoints()
    if points and points > 0 then lastComboPoints, lastComboAt = points, GetTime() end
end

local function isFinisherDescription(desc)
    return type(desc) == "string" and not isSecret(desc) and desc:find("Finishing move") ~= nil
end

-- The mob a cast is going to. UNIT_SPELLCAST_SENT only names it, so a cast whose name matches the focus but not
-- the target (a /cast [@focus] macro) goes on the focus, and one whose name matches the soft enemy goes on that.
-- A same-named target wins. A focus or soft enemy whose GUID is secret can't be tracked, so that cast is skipped
-- (false). A friendly hard target never takes a cast: with one selected, the soft enemy is the cast's mob.
local function sentTargetKey(targetName)
    local okAttack, attackable = pcall(UnitCanAttack, "player", "target")
    local targetKey
    if okAttack and not isSecret(attackable) and attackable == false then
        targetKey = unitKey("softenemy")
    else
        targetKey = unitKey("target")
    end
    if type(targetName) ~= "string" or isSecret(targetName) or targetName == "" then return targetKey end
    local function nameOf(unit)
        local ok, name = pcall(UnitName, unit)
        if ok and type(name) == "string" and not isSecret(name) then return name end
    end
    if nameOf("target") == targetName then return targetKey end
    if nameOf("focus") == targetName then return unitKey("focus") or false end
    if nameOf("softenemy") == targetName then return unitKey("softenemy") or false end
    return targetKey
end

local function onCastSent(spellID, castGUID, targetName)
    local now = GetTime()
    for guid, sent in pairs(sentTargets) do
        if now - sent.at > SENT_TARGET_SECONDS then sentTargets[guid] = nil end
    end
    if castGUID and not isSecret(castGUID) then
        sentTargets[castGUID] = { key = sentTargetKey(targetName), at = now }
    end
    local ok, _, desc = pcall(spellNameAndDescription, spellID)
    if not ok or not isFinisherDescription(desc) then return end
    comboAtSend = readComboPoints()
end

-- The mob a cast went to: the target when it was sent, else (no send seen) the target now.
local function castTargetKey(castGUID)
    local sent = castGUID and not isSecret(castGUID) and sentTargets[castGUID]
    if not sent then return unitKey("target") end
    sentTargets[castGUID] = nil
    return sent.key
end

-- An avoid on `key` that arrived just before the cast event, or nil. With includeImmune, also an IMMUNE
-- followed by a hit (a DoT's direct part landed, the DoT didn't).
local function avoidJustBefore(key, includeImmune)
    if not lastOutcome or lastOutcome.key ~= key then return nil end
    local now = GetTime()
    if lastOutcome.avoided and now - lastOutcome.at <= OUTCOME_LOOKBACK then return lastOutcome end
    local immune = includeImmune and lastOutcome.immune
    if immune and now - immune.at <= OUTCOME_LOOKBACK then return immune end
end

local function onBuilderCast(key, points)
    if avoidJustBefore(key) then return end
    countedPoints = math.min(COMBO_CAP, countedPoints + points)
    lastBuilder = { key = key, points = points, at = GetTime() }
end

-- A DoT cast whose result was avoided isn't on the target: drop it. A recast replaced a DoT that is still
-- ticking, so that one is put back. Spell DoTs are different: the pet and other players' melee miss all the
-- time, and their ticks are told apart from melee by school. So an avoid that can't be the spell's is ignored,
-- and one that might not be makes a new DoT wait for its first tick instead of dropping it.
-- Returns false if the avoid was ignored, so the cast's own outcome may still come.
local function removeAvoidedDot(cast, action, school)
    local dot = cast.dot
    local dots = dotsByTarget[cast.key]
    if not dots or dots[cast.name] ~= dot then return true end
    local spellSchool = type(school) == "number" and not isSecret(school) and school == dot.school
    if dot.school ~= SCHOOL_MASKS.Physical and not spellSchool then
        if MELEE_ONLY_AVOIDS[action] then return false end
        if not cast.previous then
            dot.doubtful = true
            trace(string.format("AVOID %s right after %s: may be someone else's, waiting for its first tick",
                action, cast.name))
            return true
        end
    end
    if cast.previous then
        dots[cast.name] = cast.previous
        trace(string.format("AVOID %s right after %s recast; keeping the earlier one", action, cast.name))
    else
        dots[cast.name] = nil
        trace(string.format("AVOID %s right after %s; dropped", action, cast.name))
    end
    return true
end

local function onAvoided(key, action, school)
    local now = GetTime()
    lastOutcome = { key = key, avoided = true, action = action, school = school, at = now }
    if lastBuilder and lastBuilder.key == key then
        if now - lastBuilder.at <= OUTCOME_WINDOW then
            countedPoints = math.max(0, countedPoints - lastBuilder.points)
        end
        lastBuilder = nil
    end
    if lastDotCast and lastDotCast.key == key then
        local window = lastDotCast.dot.school == SCHOOL_MASKS.Physical and PHYSICAL_OUTCOME_WINDOW or OUTCOME_WINDOW
        if now - lastDotCast.at > window then
            lastDotCast = nil
        elseif lastDotCast.landedAt then
            -- Its direct part hit: other avoids are someone else's, but the DoT itself may be immune.
            if action == "IMMUNE" and removeAvoidedDot(lastDotCast, action, school) then lastDotCast = nil end
        elseif removeAvoidedDot(lastDotCast, action, school) then
            lastDotCast = nil
        end
    end
end

-- A hit on a mob: the pending casts on it landed. For a spell DoT only a hit in its school says so.
local function onHit(key, school)
    local now = GetTime()
    local prior = lastOutcome
    lastOutcome = { key = key, avoided = false, at = now }
    if prior and prior.key == key and prior.action == "IMMUNE" and now - prior.at <= OUTCOME_LOOKBACK then
        lastOutcome.immune = prior
    end
    if lastBuilder and lastBuilder.key == key then lastBuilder = nil end
    -- UNIT_COMBAT can hand out a secret school; never compare it.
    local schoolKnown = not isSecret(school)
    if lastDotCast and lastDotCast.key == key and not lastDotCast.landedAt
        and (lastDotCast.dot.school == SCHOOL_MASKS.Physical
            or (schoolKnown and lastDotCast.dot.school == school)) then
        lastDotCast.landedAt = now
    end
end

local function resetComboCount()
    countedPoints, lastBuilder = 0, nil
    lastComboPoints, lastComboAt = nil, 0
end

-- Returns points and where they came from, or nil and "unknown".
local function comboPointsForCast()
    local points, source = comboAtSend, "read"
    if not (points and points > 0) then
        if lastComboPoints and GetTime() - lastComboAt <= COMBO_CACHE_SECONDS then
            points, source = lastComboPoints, "cached"
        elseif countedPoints > 0 then
            points, source = countedPoints, "counted"
        else
            points, source = nil, "unknown"
        end
    end
    comboAtSend = nil
    resetComboCount()
    return points, source
end

-- A DoT as it stands the moment it's applied, before any tick.
local function newDot(spellID, tickKey, name, total, school, duration, statedInterval, now)
    local interval = statedInterval or KNOWN_TICK_INTERVALS[name] or DEFAULT_TICK_INTERVAL
    return {
        spellID = spellID,
        tickKey = tickKey,
        -- The size learned before this cast: a same-slot collision is judged against it.
        learnedAtApply = tickKey and ticks[tickKey] or nil,
        school = SCHOOL_BY_NAME[name] or school,
        total = total,
        duration = duration,
        interval = interval,
        totalTicks = math.max(1, math.floor(duration / interval + 0.5)),
        shape = TICK_SHAPES[name],
        travel = PROJECTILE_DOTS[name] and PROJECTILE_TRAVEL or nil,
        appliedAt = now,
        expiresAt = now + duration,
        nextTickAt = now + interval,
        tickSum = 0,        -- non-crit ticks only
        normalTicks = 0,
        ticksSeen = 0,      -- including crits
        missed = 0,
    }
end

-- Returns the target key the DoT was applied to, or nil if the cast wasn't a tracked DoT.
local function onPlayerCast(spellID, castGUID)
    local key = castTargetKey(castGUID)
    local ok, name, desc = pcall(spellNameAndDescription, spellID)
    if not ok or not name or isSecret(name) then return end
    if type(desc) == "string" and not isSecret(desc) then
        local awarded = tonumber(desc:match("Awards (%d+) combo point"))
        if awarded then onBuilderCast(key, awarded) end
        -- Only one Fire trap can be active: any new one (Explosive Trap too) replaces the armed one.
        if armedTrap and desc:find("Fire trap") then armedTrap = nil end
    end
    if IGNORED_SPELLS[name] then return end
    local isFinisher = isFinisherDescription(desc)
    local comboPoints, comboSource
    if isFinisher then comboPoints, comboSource = comboPointsForCast() end
    -- Unknown points: parse the lowest entry (errs low), and don't use or teach learned tick sizes.
    local total, school, duration, statedInterval = parseDot(desc, comboPoints or 1)
    if not total then return end
    -- A finisher's tick size depends on the points spent, so learned sizes are kept per point count.
    local tickKey = spellID
    if isFinisher then tickKey = comboPoints and (spellID .. "x" .. comboPoints) or nil end

    local now = GetTime()
    if TRAP_DOTS[name] then
        local interval = statedInterval or KNOWN_TICK_INTERVALS[name] or DEFAULT_TICK_INTERVAL
        school = SCHOOL_BY_NAME[name] or school
        local lifetime = tonumber(desc:match("[Tt]rap will exist for (%d+) min"))
        armedTrap = { spellID = spellID, name = name, total = total, school = school, duration = duration,
            interval = interval, placedAt = now, expiresAt = now + (lifetime or 1) * 60 }
        trace(string.format("TRAP %s armed: %d dmg over %ss", name, total, duration))
        return
    end

    if not key then return end

    dotsByTarget[key] = dotsByTarget[key] or {}
    local previous = dotsByTarget[key][name]
    local dot = newDot(spellID, tickKey, name, total, school, duration, statedInterval, now)
    dotsByTarget[key][name] = dot
    lastDotCast = { key = key, name = name, dot = dot, previous = previous, at = now }
    local learned = tickKey and ticks[tickKey]
    trace(string.format("CAST %s (id %d)%s: %d dmg over %ss, school %d, tick every %ss, per-tick %s", name, spellID,
        isFinisher and string.format(" %s combo points (%s)", tostring(comboPoints or "?"), comboSource) or "",
        total, duration, dot.school, dot.interval, learned and ("learned " .. learned) or "from description"))
    local avoided = avoidJustBefore(key, true)
    if avoided and removeAvoidedDot(lastDotCast, avoided.action, avoided.school) then
        lastDotCast = nil
        if dotsByTarget[key] and dotsByTarget[key][name] == dot then return key, isWaiting(dot) end
        return nil
    end
    return key, isWaiting(dot)
end

-- Estimate during casting: a DoT with a cast time shows from UNIT_SPELLCAST_START, with the estimate its cast
-- would make. It's kept out of dotsByTarget, so ticks never match it, and it stands in for a DoT of the same name
-- that the cast would refresh. On success onPlayerCast takes over. A failed or interrupted cast, or a target
-- change, just drops it. STOP ends every cast, successful or not, and may come just before SUCCEEDED, so a
-- stopped cast is only dropped if no success follows shortly.
local CAST_STOP_GRACE = 0.5
local CAST_MAX_SECONDS = 15 -- a lost end event never leaves an estimate behind
local castInProgress -- { key, name, dot, castGUID, spellID, startedAt, stoppedAt }

local function sameCast(cast, castGUID, spellID)
    if cast.castGUID and castGUID ~= nil and not isSecret(castGUID) then return castGUID == cast.castGUID end
    return not isSecret(spellID) and spellID == cast.spellID
end

local function dropCastInProgress(reason)
    if not castInProgress then return end
    trace("CASTING " .. castInProgress.name .. " " .. reason .. "; estimate removed")
    castInProgress = nil
end

-- Returns the target key when a DoT now shows for the cast.
local function onCastStart(castGUID, spellID)
    castInProgress = nil
    if isSecret(spellID) then return end
    local ok, name, desc = pcall(spellNameAndDescription, spellID)
    if not ok or not name or isSecret(name) or IGNORED_SPELLS[name] or isFinisherDescription(desc) then return end
    local total, school, duration, statedInterval = parseDot(desc, 1)
    if not total then return end
    local sent = castGUID and not isSecret(castGUID) and sentTargets[castGUID]
    local key
    if sent then key = sent.key else key = unitKey("target") end
    if not key then return end
    local now = GetTime()
    local dot = newDot(spellID, spellID, name, total, school, duration, statedInterval, now)
    dot.provisional = true
    castInProgress = { key = key, name = name, dot = dot, spellID = spellID, startedAt = now,
        castGUID = not isSecret(castGUID) and castGUID or nil }
    return key
end

local function onCastSucceeded(castGUID, spellID)
    if castInProgress and sameCast(castInProgress, castGUID, spellID) then castInProgress = nil end
end

-- Returns true when the estimate was removed.
local function onCastEnded(event, castGUID, spellID)
    if not castInProgress or not sameCast(castInProgress, castGUID, spellID) then return end
    if event == "UNIT_SPELLCAST_STOP" then
        castInProgress.stoppedAt = castInProgress.stoppedAt or GetTime()
        return
    end
    dropCastInProgress(event == "UNIT_SPELLCAST_INTERRUPTED" and "interrupted" or "failed")
    return true
end

-- Seconds between now and the nearest expected tick time, and that tick's index. Anchored on the first tick
-- once seen (ticks keep its rhythm), else on the cast. Using the nearest multiple of the interval means one
-- missed tick doesn't lose the DoT.
local function distanceToExpectedTick(dot, now)
    local anchor = dot.firstTickAt or dot.appliedAt
    if not dot.firstTickAt and dot.travel then
        -- Still in flight: the DoT started anywhere up to `travel` seconds after the cast.
        local late = now - (anchor + dot.interval)
        if late > 0 then anchor = anchor + math.min(late, dot.travel) end
    end
    local k = math.max(1, math.floor((now - anchor) / dot.interval + 0.5))
    return math.abs(now - (anchor + k * dot.interval)), k
end

local function plausibleTickAmount(dot, amount, isCrit, number)
    local known, tolerance
    if dot.normalTicks > 0 then
        known, tolerance = dot.tickSum / dot.normalTicks, TICK_AMOUNT_TOLERANCE
    else
        known, tolerance = dot.tickKey and ticks[dot.tickKey], FIRST_TICK_AMOUNT_TOLERANCE
    end
    if not known then return true end
    known = known * tickShape(dot, number)
    if isCrit then
        return amount >= known * CRIT_MIN_RATIO - 1 and amount <= known * CRIT_MAX_RATIO + 1
    end
    return math.abs(amount - known) <= math.max(1, known * tolerance)
end

-- Tick size to judge a same-slot collision by: the average of the DoT's earlier ticks, or with fewer than two
-- ticks the size learned before this cast, else the description's per-tick share.
local function referenceTickSize(dot)
    if dot.normalTicks > 1 then
        return (dot.tickSum - dot.lastTickAmount / dot.lastTickShape) / (dot.normalTicks - 1)
    end
    return dot.learnedAtApply or (dot.total / dot.totalTicks)
end

local function saveLearnedTick(dot)
    if dot.tickKey and dot.normalTicks > 0 then
        ticks[dot.tickKey] = math.floor(dot.tickSum / dot.normalTicks * 10 + 0.5) / 10
    end
end

-- Moves a DoT's tick bookkeeping to the tick in slot `index` that landed at `now`.
local function anchorTick(dot, index, now)
    dot.missed = 0
    if dot.firstTickAt then
        dot.lastTickIndex = index
    else
        dot.firstTickAt, dot.lastTickIndex = now, 0
        -- A projectile DoT started when it landed: count its ticks from there.
        if dot.travel then dot.appliedAt = now - index * dot.interval end
    end
    dot.lastTickAt = now
    dot.nextTickAt = now + dot.interval
    -- Re-anchor expiry on the observed tick: ticks arrive slightly after their nominal time, and an expiry
    -- based on the cast event would otherwise cut off the final tick.
    local tickIndex = math.max(1, math.floor((now - dot.appliedAt) / dot.interval + 0.5))
    dot.expiresAt = now + (dot.totalTicks - tickIndex) * dot.interval
    return tickIndex
end

-- Two same-school hits in one tick slot (Shadow Bolt landing with a Corruption tick): the first one was taken
-- as the tick. If this one is closer to the expected size, it was the real tick.
local SAME_SLOT_SECONDS = 0.2
local function trySwapSameSlot(dot, name, amount, isCrit, now)
    if isCrit or amount <= 0 or dot.lastTickCrit or not dot.lastTickAt
        or dot.lastTickAmount <= 0 or now - dot.lastTickAt > SAME_SLOT_SECONDS then
        return false
    end
    local factor = dot.lastTickShape
    local reference = referenceTickSize(dot) * factor
    if math.abs(amount - reference) >= math.abs(dot.lastTickAmount - reference) then return false end
    trace(string.format("SWAP %s tick: %d was another hit, %d is the tick", name, dot.lastTickAmount, amount))
    dot.tickSum = dot.tickSum + (amount - dot.lastTickAmount) / factor
    dot.lastTickAmount = amount
    saveLearnedTick(dot)
    return true
end

-- A learned size that's wrong rejects every real tick. Hits rejected only on size, but landing on the DoT's
-- rhythm in two consecutive slots and agreeing with each other, are the real ticks: relearn from them.
local function tryRelearn(dot, name, amount, isCrit, index, distance, now)
    local window = dot.firstTickAt and TICK_MATCH_WINDOW_ANCHORED or TICK_MATCH_WINDOW
    local freshSlot = not dot.firstTickAt or index > dot.lastTickIndex
    if isCrit or amount <= 0 or not freshSlot or distance > window then return false end
    local previous = dot.offBeatCandidate
    local factor = tickShape(dot, tickNumberAt(dot, now))
    local average = amount / factor
    dot.offBeatCandidate = { index = index, amount = amount, average = average, at = now }
    if not previous or index ~= previous.index + 1
        or math.abs(average - previous.average) > math.max(1, previous.average * TICK_AMOUNT_TOLERANCE) then
        return false
    end
    trace(string.format("RELEARN %s: ticks of %d and %d on its rhythm didn't fit %.1f/tick", name,
        previous.amount, amount, expectedTick(dot)))
    dot.offBeatCandidate = nil
    dot.tickSum, dot.normalTicks = previous.average + average, 2
    dot.ticksSeen = dot.ticksSeen + 2
    dot.lastTickAmount, dot.lastTickShape, dot.lastTickCrit = amount, factor, false
    saveLearnedTick(dot)
    if not dot.firstTickAt then
        dot.firstTickAt, dot.lastTickIndex = previous.at, 0
        index = 1
    end
    anchorTick(dot, index, now)
    return true
end

-- Counts a hit as the DoT's tick in slot `index`. Returns the tick's number (1 = first) and shape factor.
local function recordTick(dot, amount, isCrit, index, now)
    local factor = tickShape(dot, tickNumberAt(dot, now))
    dot.ticksSeen = dot.ticksSeen + 1
    dot.lastTickAmount, dot.lastTickShape, dot.lastTickCrit = amount, factor, isCrit
    dot.offBeatCandidate = nil
    if not isCrit and amount > 0 then
        dot.tickSum = dot.tickSum + amount / factor
        dot.normalTicks = dot.normalTicks + 1
        saveLearnedTick(dot)
    end
    return anchorTick(dot, index, now), factor
end

-- An armed trap's first tick: an unmatched hit of its school and size on any mob, at least one tick interval
-- after the trap was placed. Starts the DoT there, as tick 1. Without a learned size the description's share is
-- only a rough guide, so the range is wide (0.5-2.5x).
local function springTrap(key, unit, amount, school, isCrit, now)
    local trap = armedTrap
    if not trap or school ~= trap.school then return false end
    if now > trap.expiresAt + trap.interval + TICK_MATCH_WINDOW then armedTrap = nil; return false end
    if now < trap.placedAt + trap.interval - TICK_MATCH_WINDOW then return false end
    local dot = newDot(trap.spellID, trap.spellID, trap.name, trap.total, trap.school, trap.duration,
        trap.interval, now - trap.interval)
    if ticks[trap.spellID] then
        if not plausibleTickAmount(dot, amount, isCrit, 1) then return false end
    else
        local share = trap.total / dot.totalTicks
        local low, high = share * 0.5, share * 2.5
        if isCrit then low, high = low * CRIT_MIN_RATIO, high * CRIT_MAX_RATIO end
        if amount < low or amount > high then return false end
    end
    armedTrap = nil
    dotsByTarget[key] = dotsByTarget[key] or {}
    dotsByTarget[key][trap.name] = dot
    recordTick(dot, amount, isCrit, 1, now)
    trace(string.format("TRAP %s sprung on %s: first tick %d", trap.name, unit, amount))
    return true
end

-- Returns the target key when this hit was the first tick of a DoT that was waiting for it (so the marker can
-- flash now that the DoT shows), else nil.
-- The same hit arrives once per unit token showing the mob (target, nameplateN, focus...) and must count once. But
-- two DoTs of one school can tick for the same amount in the same instant: those are two hits from the same token.
-- So within an instant each signature (mob, amount, school) remembers its token and the DoTs it fed.
local combatFrameAt
local combatFrameHits = {}
-- Forever keeps hit amounts secret (seen in game: not one tick or hit amount readable in a whole session of
-- Rends), and a tick that can't be read can't be matched. So a DoT is only judged by its missing ticks on a mob
-- whose hits have shown readable amounts since it was applied; otherwise it runs for its whole duration.
local amounts             -- nil until a hit is seen, then "readable" or "secret" (for /sab dots)
local readableHitAt = {}  -- mob key -> when a hit with a readable amount last landed on it
local READABLE_KEEP = 60  -- seconds a mob's last readable hit is remembered
local function onUnitCombat(unit, action, flag, amount, school)
    if isSecret(action) then return end
    -- A fully absorbed tick still landed: it proves the DoT is on and keeps its rhythm, so ABSORB matches like
    -- WOUND, but a 0 never feeds tick sizes. With two DoTs it could be, it's ignored.
    local absorbed = action == "ABSORB"
    if not AVOIDED_ACTIONS[action] and action ~= "WOUND" and not absorbed then return end
    local key = unitKey(unit)
    if not key then return end
    if AVOIDED_ACTIONS[action] then return onAvoided(key, action, school) end
    onHit(key, school)
    if isSecret(amount) or isSecret(school) or type(amount) ~= "number" then
        if amounts ~= "secret" then
            amounts = "secret"
            trace("Hit amounts are secret here: ticks can't be seen, so DoTs run on their tooltip numbers for their"
                .. " whole duration")
        end
        return
    end
    if amounts ~= "readable" then
        amounts = "readable"
        trace("Hit amounts are readable: ticks are matched and their sizes learned")
    end
    readableHitAt[key] = GetTime()
    local isCrit = not isSecret(flag) and flag == "CRITICAL"
    if not dotsByTarget[key] and not armedTrap then return end
    local dots = dotsByTarget[key] or {}

    local now = GetTime()
    if combatFrameAt ~= now then
        combatFrameHits = {}
        combatFrameAt = now
    end
    local signature = key .. ":" .. amount .. ":" .. school
    local hit = combatFrameHits[signature]
    if hit then
        if hit.unit ~= unit then return end
    else
        hit = { unit = unit, fed = {} }
        combatFrameHits[signature] = hit
    end
    local fed = hit.fed

    local best, bestName, bestDistance, bestIndex
    local zeroAbsorb = absorbed and amount == 0
    local candidates = 0
    for name, dot in pairs(dots) do
        if not fed[name] and dot.school == school
            and (zeroAbsorb or plausibleTickAmount(dot, amount, isCrit, tickNumberAt(dot, now))) then
            local distance, index = distanceToExpectedTick(dot, now)
            local window = dot.firstTickAt and TICK_MATCH_WINDOW_ANCHORED or TICK_MATCH_WINDOW
            -- Each tick slot takes one hit: a second hit near an already-matched tick is someone else's.
            local freshSlot = not dot.firstTickAt or index > dot.lastTickIndex
            if freshSlot and distance <= window then
                candidates = candidates + 1
                if not bestDistance or distance < bestDistance then
                    best, bestName, bestDistance, bestIndex = dot, name, distance, index
                end
            end
        end
    end
    if zeroAbsorb and candidates ~= 1 then return end
    if not best then
        -- Not a tick as things stand; it may still correct one (same-slot swap, or a wrong learned size).
        for name, dot in pairs(dots) do
            if not fed[name] and dot.school == school then
                local distance, index = distanceToExpectedTick(dot, now)
                local wasWaiting = isWaiting(dot)
                if trySwapSameSlot(dot, name, amount, isCrit, now) then
                    fed[name] = true
                    return
                end
                if tryRelearn(dot, name, amount, isCrit, index, distance, now) then
                    fed[name] = true
                    return wasWaiting and key or nil
                end
            end
        end
        if springTrap(key, unit, amount, school, isCrit, now) then return key end
        return
    end

    local wasWaiting = isWaiting(best)
    local tickIndex, factor = recordTick(best, amount, isCrit, bestIndex, now)
    fed[bestName] = true
    trace(string.format("TICK %s %d%s on %s (tick %d/%d, expecting %.1f)", bestName, amount,
        isCrit and " CRIT" or "", unit, tickIndex, best.totalTicks, expectedTick(best) * factor))
    if wasWaiting then return key end
end

-- Whether hits on a mob reach the addon right now. UNIT_COMBAT only reports unit tokens (the target, focus and
-- visible nameplates), so a mob you tabbed away from ticks unseen; its DoTs must not be dropped as "never ticked".
local function isObservable(key)
    if unitKey("target") == key or unitKey("focus") == key then return true end
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if UnitExists(unit) and unitKey(unit) == key then return true end
    end
    return false
end

local function housekeep(now)
    for key, at in pairs(readableHitAt) do
        if now - at > READABLE_KEEP then readableHitAt[key] = nil end
    end
    for key, dots in pairs(dotsByTarget) do
        for name, dot in pairs(dots) do
            local late = (dot.ticksSeen == 0 and dot.travel) or 0
            while dot.nextTickAt < now - TICK_MATCH_WINDOW - late and dot.nextTickAt <= dot.expiresAt do
                dot.nextTickAt = dot.nextTickAt + dot.interval
                -- Only a tick that could have been seen counts as missed: the mob is in view, and its hits
                -- have readable amounts.
                if dot.ticksSeen == 0 and isObservable(key) and (readableHitAt[key] or -1) >= dot.appliedAt then
                    dot.missed = dot.missed + 1
                end
            end
            if now > dot.expiresAt + TICK_MATCH_WINDOW then
                dots[name] = nil
                trace("EXPIRE " .. name)
            elseif dot.ticksSeen == 0 and dot.missed >= MISSED_TICKS_BEFORE_DROP then
                dots[name] = nil
                trace("DROP " .. name .. " never ticked (resisted or immune?)")
            end
        end
        if next(dots) == nil then dotsByTarget[key] = nil end
    end
    if castInProgress then
        if castInProgress.stoppedAt and now - castInProgress.stoppedAt > CAST_STOP_GRACE then
            dropCastInProgress("stopped without succeeding")
        elseif now - castInProgress.startedAt > CAST_MAX_SECONDS then
            dropCastInProgress("never finished")
        end
    end
end

local function remainingDamage(dot)
    if dot.nextTickAt > dot.expiresAt + dot.interval / 2 then return 0 end
    local ticksLeft = math.floor((dot.expiresAt - dot.nextTickAt) / dot.interval + 0.5) + 1
    if not dot.shape then return ticksLeft * expectedTick(dot) end
    local average, total = expectedTick(dot), 0
    for number = math.max(1, dot.totalTicks - ticksLeft + 1), dot.totalTicks do
        total = total + average * tickShape(dot, number)
    end
    return total
end

-- Remaining damage per DoT on a mob (by unitKey), oldest application first. DoTs still waiting for their first
-- tick are left out. A DoT being cast on the mob replaces the one of the same name it would refresh.
local function dotBreakdown(key)
    local dots = key and dotsByTarget[key]
    local cast = key and castInProgress and castInProgress.key == key and castInProgress or nil
    local list = {}
    if not dots and not cast then return list end
    for name, dot in pairs(dots or {}) do
        if not isWaiting(dot) and not (cast and name == cast.name) then
            local damage = remainingDamage(dot)
            if damage > 0 then
                list[#list + 1] = { name = name, spellID = dot.spellID, school = dot.school,
                    appliedAt = dot.appliedAt, damage = damage }
            end
        end
    end
    if cast then
        list[#list + 1] = { name = cast.name, spellID = cast.spellID, school = cast.dot.school,
            appliedAt = cast.dot.appliedAt, damage = remainingDamage(cast.dot), provisional = true }
    end
    table.sort(list, function(a, b) return a.appliedAt < b.appliedAt end)
    return list
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

-- fn(event): "changed" when the target's DoTs may have changed, "target" when the target did, "applied" when a
-- DoT lands on it.
local listeners = {}

local function notify(event)
    for _, fn in ipairs(listeners) do fn(event) end
end

local frame = CreateFrame("Frame")

-- Never register COMBAT_LOG_EVENT_UNFILTERED: Forever forbids it and shows a "blocked" popup.
local PLAYER_EVENTS = {
    "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_POWER_FREQUENT",
}
local EVENTS = { "PLAYER_TARGET_CHANGED", "UNIT_COMBAT", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED" }

local function onEvent(_, event, ...)
    if event == "PLAYER_TARGET_CHANGED" then
        dotsByTarget.target = nil -- only used when the target's GUID is secret
        resetComboCount()         -- combo points belong to the target they were built on
        dropCastInProgress("target changed")
        notify("target")

    elseif event == "UNIT_SPELLCAST_SENT" then
        local _, targetName, castGUID, spellID = ...
        onCastSent(spellID, castGUID, targetName)

    elseif event == "UNIT_POWER_FREQUENT" then
        local _, powerType = ...
        if not isSecret(powerType) and powerType == "COMBO_POINTS" then rememberComboPoints() end

    elseif event == "UNIT_SPELLCAST_START" then
        local _, castGUID, spellID = ...
        if onCastStart(castGUID, spellID) then notify("changed") end

    elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_FAILED"
        or event == "UNIT_SPELLCAST_INTERRUPTED" then
        local _, castGUID, spellID = ...
        if onCastEnded(event, castGUID, spellID) then notify("changed") end

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local _, castGUID, spellID = ...
        onCastSucceeded(castGUID, spellID)
        local appliedTo, waiting = onPlayerCast(spellID, castGUID)
        notify("changed")
        -- A DoT waiting for its first tick isn't drawn yet; it flashes when that tick lands instead.
        if appliedTo and not waiting and appliedTo == unitKey("target") then notify("applied") end

    elseif event == "NAME_PLATE_UNIT_ADDED" or event == "NAME_PLATE_UNIT_REMOVED" then
        -- A plate token goes to the next mob that gets a plate: DoTs keyed by it belonged to the old one.
        local token = ...
        if type(token) == "string" and not isSecret(token) and dotsByTarget["plate:" .. token] then
            dotsByTarget["plate:" .. token] = nil
            notify("changed")
        end

    elseif event == "UNIT_COMBAT" then
        local revealed = onUnitCombat(...)
        if revealed and revealed == unitKey("target") then
            notify("changed")
            notify("applied")
        end
    end
end

-- Errors here are reported once each and the tracking carries on with the next event.
local reported = {}
frame:SetScript("OnEvent", function(...)
    local ok, err = pcall(onEvent, ...)
    if not ok and not reported[err] then
        reported[err] = true
        trace("ERROR " .. tostring(err))
        ns.Core.Print("Error in the DoT tracking (it carries on): " .. tostring(err))
    end
end)

local namesAdded = false
-- The client's own names for the spells in the name-keyed tables (Forever renames a few).
local function addClientNames()
    if namesAdded or not (C_Spell and C_Spell.GetSpellName) then return end
    namesAdded = true
    for englishName, spellID in pairs(SPELL_IDS) do
        local ok, name = pcall(C_Spell.GetSpellName, spellID)
        if ok and type(name) == "string" and not isSecret(name) and name ~= "" and name ~= englishName then
            for _, tbl in ipairs(NAME_TABLES) do
                if tbl[englishName] ~= nil and tbl[name] == nil then tbl[name] = tbl[englishName] end
            end
        end
    end
end

---------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------

-- The learned tick sizes live in the saved variables, discarded when TICKS_VERSION changes.
function Dots.Load(db)
    if db.dotTicksVersion ~= TICKS_VERSION or type(db.dotTicks) ~= "table" then
        db.dotTicks, db.dotTicksVersion = {}, TICKS_VERSION
    end
    ticks = db.dotTicks
end

-- Tracking on or off. Off forgets every DoT and listens to nothing.
function Dots.Enable(on)
    on = on and true or false
    if on == enabled then return end
    enabled = on
    if on then
        addClientNames()
        for _, event in ipairs(EVENTS) do frame:RegisterEvent(event) end
        for _, event in ipairs(PLAYER_EVENTS) do frame:RegisterUnitEvent(event, "player") end
        trace("tracking on")
    else
        frame:UnregisterAllEvents()
        wipe(dotsByTarget)
        wipe(readableHitAt)
        castInProgress, lastDotCast, lastOutcome, armedTrap = nil, nil, nil, nil
        wipe(sentTargets)
        resetComboCount()
        trace("tracking off")
    end
end

function Dots.IsEnabled()
    return enabled
end

-- fn(event) for "changed", "target" and "applied" (see notify).
function Dots.Listen(fn)
    listeners[#listeners + 1] = fn
end

-- What the target's DoTs still have to deal: the total (rounded) and the per-DoT list, oldest first, each
-- { name, spellID, school, damage }. Housekeeping runs first, so expired DoTs are gone.
function Dots.Target()
    housekeep(GetTime())
    local list = dotBreakdown(unitKey("target"))
    local total = 0
    for _, entry in ipairs(list) do total = total + entry.damage end
    return math.floor(total + 0.5), list
end

-- For /sab dots: the estimate on the target, then the last `n` trace lines.
function Dots.Debug(n)
    local total, list = Dots.Target()
    local parts = {}
    for _, entry in ipairs(list) do
        parts[#parts + 1] = string.format("%s %d", entry.name, math.floor(entry.damage + 0.5))
    end
    local learned = 0
    for _ in pairs(ticks) do learned = learned + 1 end
    local out = { string.format("DoTs: tracking %s, target %d left (%s), %d tick sizes learned, hit amounts %s",
        enabled and "on" or "off", total, #parts > 0 and table.concat(parts, ", ") or "none", learned,
        amounts or "not seen yet") }
    for i = math.max(1, #log - (n or 10) + 1), #log do out[#out + 1] = log[i] end
    return out
end

-- For the tests.
Dots.parseDot = parseDot
