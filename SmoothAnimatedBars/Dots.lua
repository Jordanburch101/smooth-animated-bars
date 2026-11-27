-- Damage over time: tracks the player's DoTs on each mob and what they still have to deal, for the marker on
-- the target's health bar (Marker.lua). Off unless the dots setting is on; while off no event is registered.
--
-- Ported from DoesItDie 0.9.0 by Joe Greive (MIT licence, notice below), which worked
-- out on Forever what can be read and how ticks behave, with its tracking fixes up to 0.9.4: ticks matched by school
-- and timing when their amounts are hidden (bleeds kept on their schedule), real tick sizes learned from the damage
-- meter after combat, a DoT keeping the size it was cast with until it ticks, casts at the soft enemy over a corpse
-- and at the mouseover mob, and finishers judged by the combo points they spent. Its tracking is kept as it was, in its own words where
-- they still fit; its displays, options and nameplates are not ported, its other languages' spell text is read by
-- Locale*.lua (the rogue poisons and traps below read English only), and its trace goes to a short in-memory log
-- for /sab dots instead of the saved variables.
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
    ["Scorpid Poison"] = 2,
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

-- DoTs that stack on one mob, with their cap: each cast adds an application (DoesItDie 0.10.0, seen there in game on
-- Forever: a Lacerate recast kept the first cast's 3s beat through four recasts and refreshed the duration, while
-- restarting the schedule lost every tick and dropped it as "never ticked"). Each tick is taken as one application's
-- times the stacks (as in TBC; unverified on Forever), so sizes are learned per application (stackOnto, tickShape).
-- Forever's hunters have a Lacerate too (one bleed, no stacks), hence the class. The pet's Scorpid Poison stacks too
-- (onPetCast).
local STACKING_DOTS = { ["Lacerate"] = { cap = 5, class = "DRUID" }, ["Scorpid Poison"] = { cap = 5 } }

-- Rogue poisons coat a weapon and proc on its strikes, so no cast event says when one lands or on whom. Forever
-- keeps hit amounts secret but not their school (DoesItDie's saved log there: "HIT (amount hidden) school 8"), so
-- while the player's weapon carries a poison that deals damage over time, a Nature hit on a mob is taken as its
-- tick, and starts or keeps its DoT (onPoisonCombat). The numbers come from the coating's description, read when
-- it is applied, and are kept in the saved variables until it wears off. The estimate errs low: one stack, and a
-- refresh is only seen once the ticks run on past the end.
local POISON_LIFETIME = 30 * 60 -- seconds a coating lasts when its description does not say
local POISON_GRACE = 10         -- seconds after coating before the weapon's own word on it is taken
local POISON_CANDIDATE_KEEP = 10
-- Saved: dots, coating name -> { spellID, name, total, school, duration, coatedAt, expires } (time() seconds),
-- and directAt and directUntil, when the last coating that strikes at once (Instant Poison) was put on and wears
-- off. Its Nature hits look like a poison's ticks, so while it is on, a poison is only taken as on after two hits
-- a tick apart.
local poisonState = { dots = {}, directUntil = 0 }
local poisonCandidates = {} -- mob key -> when a Nature hit not yet confirmed as a poison's tick landed

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
    ["Lacerate"] = 1328617,     -- Forever's own ID (not in Classic Era)
    ["Scorpid Poison"] = 24583, -- the pet's; its rank varies with the pet
}
local NAME_TABLES = { KNOWN_TICK_INTERVALS, TICK_SHAPES, SCHOOL_BY_NAME, IGNORED_SPELLS, PROJECTILE_DOTS, TRAP_DOTS,
                      STACKING_DOTS }
-- The tables also answer to every registered language's names (Locale.lua).
ns.locale.addNames(NAME_TABLES)

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

-- issecretvalue takes any value without erroring (Bars.lua calls it directly), so it is called without a pcall: it
-- is asked a few dozen times an event.
local function isSecret(v)
    local f = issecretvalue
    if type(f) ~= "function" then return false end
    return f(v) and true or false
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

-- Forever's English text has non-breaking spaces (U+00A0) where plain ones would do: between sentences, in
-- Rip's "1 point \194\160: 57 damage over 12 sec." and in Instant Poison IV's "lasts for 30 \194\160minutes".
-- Lua's %s does not match them (two bytes in UTF-8, U+202F three), so the English patterns read a copy with
-- them made plain spaces. Thousands separators go too: the client writes "1,177" where Wowhead writes "1177" (a
-- heal over 999 went unread for this reason, Heals.lua).
local function plainSpaces(desc)
    desc = desc:gsub("\194\160", " "):gsub("\226\128\175", " ")
    local n
    repeat
        desc, n = desc:gsub("(%d),(%d%d%d)%f[^%d]", "%1%2")
    until n == 0
    return desc
end

-- Finishers (Rip, Rupture) list their DoT per combo point:
--   "1 point \194\160: 57 damage over 12 sec.\n \194\160 2 points: 90 damage over 12 sec. ..."   (Rip)
--   "1 point \194\160: 25 damage over 8 secs\n ... 5 points: 87 damage over 16 secs"            (Rupture)
-- Returns total, school, duration for the given points (clamped to the listed range), or nil if the
-- finisher has no per-point DoT (e.g. Eviscerate). Points with no line of their own take the nearest line
-- below, else the lowest: never a higher one, which would show more damage than the cast deals.
local function parseFinisher(desc, comboPoints)
    local byPoints, highest, lowest = {}, 0, nil
    for pointsText, amount, secs in desc:gmatch("(%d+) points?%s*:%s*(%d+) damage over (%d+%.?%d*) sec") do
        local points = tonumber(pointsText)
        byPoints[points] = { total = tonumber(amount), duration = tonumber(secs) }
        highest = math.max(highest, points)
        lowest = math.min(lowest or points, points)
    end
    if highest == 0 then return nil end
    local entry
    for points = math.max(1, math.min(comboPoints, highest)), 1, -1 do
        entry = byPoints[points]
        if entry then break end
    end
    entry = entry or byPoints[lowest]
    return entry.total, SCHOOL_MASKS.Physical, entry.duration
end

-- The last "<amount> <school> damage over <secs> sec" clause: total, school mask, duration.
local function lastOverTime(desc)
    local total, school, duration
    for amount, words, secs in desc:gmatch("(%d+)%s*([%a ]-)%s*damage over (%d+%.?%d*) sec") do
        total, school, duration = tonumber(amount), schoolFromWords(words), tonumber(secs)
    end
    return total, school, duration
end

-- Returns total damage, school mask, duration and (if the description states it) tick interval.
--   "... 10 Nature damage over 15 sec."  Takes the last such clause, so Immolate's
--       "11 Fire damage and then an additional 20 Fire damage over 15 sec" yields the periodic part.
--   "Transfers 15 health from the target to the caster every 3 sec. Lasts 30 sec."  (Siphon Life)
-- comboPoints is only used for finishers.
local function parseDot(desc, comboPoints)
    if type(desc) ~= "string" or isSecret(desc) then return nil end
    local text = plainSpaces(desc)
    if text:find("Finishing move") then return parseFinisher(text, comboPoints or 5) end
    -- Weapon enchants (rogue poisons) describe a proc DoT but aren't cast on the target (parseCoating).
    if text:find("[Cc]oats a weapon") then return nil end
    -- Heals over time: Forever's Renew reads "Heals the target of 830 damage over 15 sec".
    if text:find("^Heals") then return nil end
    -- Totems are never a DoT on the target: "Summons a Grounding Totem with 5 health ... every 10 seconds ...
    -- Lasts 45 sec." read as a drain.
    if text:find("^Summons") then return nil end

    local total, school, duration = lastOverTime(text)
    if total and duration > 0 then return total, school, duration end

    local amount, words, every = text:match("(%d+)%s*([%a ]-)%s*damage every (%d+%.?%d*) sec")
    if not amount then
        -- Drains: "Transfers 15 health from the target to the caster every 3 sec." (Siphon Life), "Transfers 10
        -- health every 1 second from the target to the caster." (Drain Life).
        amount, every = text:match("Transfers (%d+) health.-every (%d+%.?%d*) sec")
        words = ""
    end
    local lasts = text:match("[Ll]asts (%d+%.?%d*) sec")
    if amount and every and lasts then
        every, lasts = tonumber(every), tonumber(lasts)
        if every > 0 and lasts > 0 then
            return tonumber(amount) * math.floor(lasts / every + 0.5), schoolFromWords(words), lasts, every
        end
    end
    -- Not English DoT wording: try the other languages (Locale.lua).
    return ns.locale.parseDot(desc, comboPoints or 5)
end

-- A weapon coating's poison, from its description:
--   "Coats a weapon with poison that lasts for 30 min. Each strike has a 30% chance of poisoning the enemy for
--    36 Nature damage over 12 sec. Stacks up to 5 times on a single target."  (Deadly Poison)
-- Returns "dot", total, school, duration and the coating's lifetime in seconds; "direct" and the lifetime for one
-- that strikes at once ("instantly inflicts 19 to 25 Nature damage", Instant Poison); nil for anything else.
local function parseCoating(desc)
    if type(desc) ~= "string" or isSecret(desc) then return nil end
    local text = plainSpaces(desc)
    if not text:find("[Cc]oats a weapon") then return nil end
    local minutes = tonumber(text:match("[Ll]asts? for (%d+)%s*min"))
    local lifetime = minutes and minutes * 60 or POISON_LIFETIME
    local total, school, duration = lastOverTime(text)
    if total and duration > 0 and school == SCHOOL_MASKS.Nature then
        return "dot", total, school, duration, lifetime
    end
    if text:find("Nature damage") then return "direct", lifetime end
end

-- N from a combo builder's "Awards 1 combo point." (Sinister Strike) or "Awards 2 Combo Points." (Forever's
-- Mutilate), else the other languages' reading, else nil.
local function comboPointsAwarded(desc)
    if type(desc) ~= "string" or isSecret(desc) then return nil end
    local points = tonumber(plainSpaces(desc):match("[Aa]wards (%d+) [Cc]ombo [Pp]oint"))
    return points or ns.locale.comboPointsAwarded(desc)
end

---------------------------------------------------------------------------
-- DoT tracking
---------------------------------------------------------------------------

-- Best known average damage per tick: observed average of non-crit ticks, else learned from earlier casts,
-- else the description. Crits are one-offs, so they never raise the expectation for later ticks. For shaped
-- DoTs (TICK_SHAPES) ticks are stored divided by their factor, so this is the average tick, not the latest.
-- Before its own first readable tick a DoT keeps the size it was applied with (learnedAtApply): the store is shared
-- by every mob, so a size learned meanwhile must not move this one's marker. A DoT applied with nothing learned
-- still picks up a size learned since; a relearn drops the snapshot (dropSnapshots).
local function expectedTick(dot)
    if dot.normalTicks > 0 then return dot.tickSum / dot.normalTicks end
    return dot.learnedAtApply or (dot.tickKey and ticks[dot.tickKey]) or (dot.total / dot.totalTicks)
end

-- Which tick of the DoT (1 = first) lands around `when`.
local function tickNumberAt(dot, when)
    return math.max(1, math.floor((when - dot.appliedAt) / dot.interval + 0.5))
end

-- The factor for tick `number` (1 for evenly ticking DoTs). Shapes are stretched to the DoT's tick count. A stacking
-- DoT's ticks are times its stacks too, so its sizes are learned and tallied per application (STACKING_DOTS).
local function tickShape(dot, number)
    local stacks = dot.stacks or 1
    local shape = dot.shape
    if not shape then return stacks end
    local i = math.ceil(math.min(math.max(number, 1), dot.totalTicks) / dot.totalTicks * #shape)
    return shape[math.max(1, math.min(i, #shape))] * stacks
end

-- A doubtful DoT (an avoid right after the cast that may not have been its own) doesn't count toward the
-- marker until its first tick lands.
local function isWaiting(dot)
    return dot.ticksSeen == 0 and dot.doubtful or false
end

-- Real tick sizes from the game's damage meter (DoesItDie 0.9.1, refined in 0.9.3). Forever hides UNIT_COMBAT amounts
-- in combat, so ticks are matched on school and timing and teach no size, and the tooltip's numbers leave out spell
-- and attack power. After combat the damage meter's per-spell totals are readable, so each DoT's total over the ticks
-- counted this combat is its real average tick (shaped DoTs' ticks weighted by their factors). A spell's upfront hit
-- (Immolate) is in the same total: it's split off in the description's proportion. combatTally: learned-size key ->
-- what this combat counted (its casts' DoTs too); combatUntracked: spells cast at no known mob; combatReadable: keys a
-- readable tick taught this combat. The meter counts every mob, the tally only what was seen, so learnFromMeter only
-- learns when the two can match.
local tickWeights = {} -- learned-size key -> how many ticks its saved size stands for (saved)
local combatTally, combatUntracked, combatReadable = {}, {}, {}

-- This combat's tally, and a fresh one for the next (a new pull right after must not mix into it).
local function takeCombatTally()
    local counted = { keys = combatTally, untracked = combatUntracked, readable = combatReadable }
    combatTally, combatUntracked, combatReadable = {}, {}, {}
    return counted
end

local function tallyFor(dot)
    if not dot.tickKey then return nil end
    local t = combatTally[dot.tickKey]
    if not t then
        t = { spellID = dot.spellID, name = dot.name, factors = 0, ticks = 0,
              descTick = dot.total / dot.totalTicks, dots = {} }
        combatTally[dot.tickKey] = t
    end
    return t
end

-- direct nil: the description's upfront hit can't be told apart (another client language). Kept per cast
-- (dot.directPart) so an avoided cast's upfront hit, which never landed, isn't taken off the meter's total
-- (learnFromMeter; DoesItDie 0.10.0).
local function tallyCast(dot, direct)
    local t = tallyFor(dot)
    if not t then return end
    t.dots[#t.dots + 1] = dot
    if direct == nil then t.unclear = true else dot.directPart = direct end
end

local function tallyHiddenTick(dot, factor)
    local t = tallyFor(dot)
    if t then
        t.factors = t.factors + factor
        t.ticks = t.ticks + 1
    end
end

-- A running DoT that has not ticked yet keeps the size it was applied with (expectedTick). When the store is relearned
-- that snapshot is as wrong as the store was: drop it so the DoT follows the store again. key nil = every DoT.
local function dropSnapshots(key)
    for _, dots in pairs(dotsByTarget) do
        for _, dot in pairs(dots) do
            if dot.normalTicks == 0 and (key == nil or dot.tickKey == key) then dot.learnedAtApply = nil end
        end
    end
end

-- The upfront hit of a spell that also leaves a DoT: the damage named before the DoT's own clause, averaged for a
-- range. English: "11 Fire damage and then an additional 20 Fire damage over 15 sec" (Immolate), "19 damage and an
-- additional 39 damage over 9 sec" (Rake). German, before "sowie". 0 when there is none. nil for other languages: an
-- upfront hit can't be told apart there, and the damage meter would teach it to the DoT (learnFromMeter skips it).
local function upfrontIn(head, rangeWord, damageWord)
    local lo, hi = head:match("(%d+) " .. rangeWord .. " (%d+)")
    if lo then return (tonumber(lo) + tonumber(hi)) / 2 end
    return tonumber(head:match("(%d+)[^%d]-" .. damageWord)) or 0
end

local function parseDirectPart(desc)
    if type(desc) ~= "string" or isSecret(desc) then return nil end
    desc = plainSpaces(desc)
    if desc:find("damage") or desc:find("health") then
        -- The DoT's clause is the last "<n> ... damage over <n> sec" (not Wrack's "damage over time effects");
        -- what comes before it is the upfront part.
        local clauseAt
        for at in desc:gmatch("()%d+[%a ]-damage over %d") do clauseAt = at end
        if not clauseAt then return 0 end
        return upfrontIn(desc:sub(1, clauseAt - 1), "to", "damage")
    end
    if desc:find("chaden") then
        local head = desc:match("^(.-)%f[%a]sowie%f[%A]")
        if not head then return 0 end
        return upfrontIn(head, "bis", "[Ss]chaden")
    end
    return nil
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
local lastDotCast    -- { key, name, dot, previous, at, landedAt, comboRead }: DoT cast whose outcome isn't known yet
-- A finisher DoT dropped for an avoid, until the combo points say whose avoid it was (see removeAvoidedDot).
local FINISHER_CHECK_DELAY = 0.5
local finisherCheck  -- { cast, dot, replaced, action, at }
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
    return type(desc) == "string" and not isSecret(desc)
        and (desc:find("Finishing move") ~= nil or ns.locale.isFinisher(desc))
end

-- Blizzard's own Mouseover Cast (Options > Combat, no macro; DoesItDie 0.9.4): with it on and its key held (or none
-- set), a cast goes on the mob under the mouse whatever the target is, so names can't tell: in a pack every mob shares
-- the target's name. True only when the client says so plainly. The CVar and binding names are retail's, not yet
-- confirmed on Forever.
local function nativeMouseoverCast()
    local getCVar = (C_CVar and C_CVar.GetCVarBool) or GetCVarBool
    if not getCVar then return false end
    local ok, on = pcall(getCVar, "enableMouseoverCast")
    if not ok or isSecret(on) or not on then return false end
    if GetModifiedClick then
        local okKey, key = pcall(GetModifiedClick, "MOUSEOVERCAST")
        if okKey and key == "NONE" then return true end
    end
    if not IsModifiedClick then return false end
    local okHeld, held = pcall(IsModifiedClick, "MOUSEOVERCAST")
    return okHeld and not isSecret(held) and held == true
end

-- The mob a cast is going to. UNIT_SPELLCAST_SENT only names it, so a cast whose name matches the focus but not
-- the target (a /cast [@focus] macro) goes on the focus, one whose name matches the soft enemy goes on that, and one
-- whose name matches the mob under the mouse (a /cast [@mouseover] macro, without soft targeting) goes on that. A
-- same-named target wins. A unit whose GUID is secret can't be tracked, so that cast is skipped (false). A friendly
-- hard target never takes a cast, nor does a dead one (with action targeting the corpse of the last kill can stay
-- the target while the next mob is the soft enemy): the soft enemy is the cast's mob then.
local function sentTargetKey(targetName)
    local function nameOf(unit)
        local ok, name = pcall(UnitName, unit)
        if ok and type(name) == "string" and not isSecret(name) then return name end
    end
    -- An attackable, living mouseover mob takes a native mouseover cast, unless the cast names some other mob.
    if nativeMouseoverCast() then
        local okA, attackable = pcall(UnitCanAttack, "player", "mouseover")
        local okD, dead = pcall(UnitIsDeadOrGhost, "mouseover")
        local named = type(targetName) ~= "string" or isSecret(targetName) or targetName == ""
            or nameOf("mouseover") == targetName
        if okA and not isSecret(attackable) and attackable == true and not (okD and not isSecret(dead) and dead == true)
            and named then
            local key = unitKey("mouseover")
            if key then return key end
        end
    end
    local okAttack, attackable = pcall(UnitCanAttack, "player", "target")
    local okDead, dead = pcall(UnitIsDeadOrGhost, "target")
    local targetDead = okDead and not isSecret(dead) and dead == true
    local targetKey
    if (okAttack and not isSecret(attackable) and attackable == false) or targetDead then
        targetKey = unitKey("softenemy")
    else
        targetKey = unitKey("target")
    end
    if type(targetName) ~= "string" or isSecret(targetName) or targetName == "" then return targetKey end
    if not targetDead and nameOf("target") == targetName then return targetKey end
    if nameOf("focus") == targetName then return unitKey("focus") or false end
    if nameOf("softenemy") == targetName then return unitKey("softenemy") or false end
    if nameOf("mouseover") == targetName then return unitKey("mouseover") or false end
    return targetKey
end

local function onCastSent(spellID, castGUID, targetName)
    local now = GetTime()
    for guid, sent in pairs(sentTargets) do
        if now - sent.at > SENT_TARGET_SECONDS then sentTargets[guid] = nil end
    end
    local ok, _, desc = pcall(spellNameAndDescription, spellID)
    if castGUID and not isSecret(castGUID) then
        sentTargets[castGUID] = { key = sentTargetKey(targetName), at = now }
        -- A builder's points before it lands: an avoid right after it is judged by whether its point came
        -- (resolveFinisherCheck), as a finisher's is by whether its points went.
        if ok and comboPointsAwarded(desc) then sentTargets[castGUID].points = readComboPoints() end
    end
    if not ok or not isFinisherDescription(desc) then return end
    comboAtSend = readComboPoints()
end

-- The mob a cast went to: the target when it was sent, else (no send seen) the target now. Also the combo points
-- read when a builder was sent, if they could be.
local function castTargetKey(castGUID)
    local sent = castGUID and not isSecret(castGUID) and sentTargets[castGUID]
    if not sent then return unitKey("target") end
    sentTargets[castGUID] = nil
    return sent.key, sent.points
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
    -- Dealt nothing: its upfront hit isn't taken off the meter's total (learnFromMeter). Its missing ticks stop the
    -- meter learning only while the avoid may not have been its own (meterSkipReason): a spell avoided in its own
    -- school was; a bleed's may have been a white swing's (Garrote), and if it landed after all, ticking unseen, the
    -- meter would have damage the tally hasn't. Those are confirmed by their combo points (resolveFinisherCheck).
    dot.avoided = true
    if dot.school ~= SCHOOL_MASKS.Physical and spellSchool then dot.avoidConfirmed = true end
    if cast.previous then
        dots[cast.name] = cast.previous
        cast.previous.stackedInto = nil
        trace(string.format("AVOID %s right after %s recast; keeping the earlier one", action, cast.name))
    else
        dots[cast.name] = nil
        trace(string.format("AVOID %s right after %s; dropped", action, cast.name))
    end
    -- A cat's or rogue's white swing missing in that instant looks the same as the finisher missing (DoesItDie 0.9.4:
    -- a Rip that landed was dropped). A finisher that misses keeps its combo points, one that lands spends them, so a
    -- finisher whose points were read at send is judged again once they've settled.
    -- At the cap a builder's points can't rise, so it can't be told (DoesItDie 0.10.0 says so too): it stays dropped.
    if cast.awarded and not cast.builderFrom and cast.pointsAtSend and cast.pointsAtSend >= COMBO_CAP then
        trace(string.format("COMBO after %s's %s: already %d points, can't tell, stays dropped", cast.name, action,
            cast.pointsAtSend))
    end
    if cast.comboRead or cast.builderFrom then
        finisherCheck = { cast = cast, dot = dot, replaced = dots[cast.name], action = action,
                          at = GetTime() + FINISHER_CHECK_DELAY }
    end
    return true
end

-- The combo points after a dropped finisher: spent means it landed (the avoid was a white swing), so it's put back;
-- still there, unreadable, or the target changed (the points belong to the target) leaves it dropped. Not yet
-- confirmed in game that Forever keeps a missed finisher's combo points.
local function resolveFinisherCheck(now)
    local check = finisherCheck
    if not check or now < check.at then return end
    finisherCheck = nil
    local cast = check.cast
    if unitKey("target") ~= cast.key then
        trace("COMBO after " .. cast.name .. "'s " .. check.action .. ": target changed, stays dropped")
        return
    end
    local points = readComboPoints()
    -- A finisher that landed spent its points; a builder that landed (cast.builderFrom) gained its point.
    local had = cast.builderFrom or cast.comboRead
    local landed
    if cast.builderFrom then landed = points and points > had else landed = points and points < had end
    if not landed then
        -- Readable points say it missed for sure; unreadable ones leave it in doubt.
        if points then check.dot.avoidConfirmed = true end
        trace(string.format("COMBO after %s's %s: %s (had %d), it missed", cast.name, check.action,
            tostring(points or "unreadable"), had))
        return
    end
    local dots = dotsByTarget[cast.key]
    local current = dots and dots[cast.name]
    -- The DoT the recast replaced may have run out during the check, which still leaves its place free (DoesItDie
    -- 0.10.0: Rip and Rupture kept when their old DoT ran out just as a white swing missed).
    local expired = check.replaced and current == nil and now > check.replaced.expiresAt + TICK_MATCH_WINDOW
    if (current ~= check.replaced and not expired) or now >= check.dot.expiresAt then return end
    dotsByTarget[cast.key] = dots or {}
    dotsByTarget[cast.key][cast.name] = check.dot
    check.dot.avoided, check.dot.avoidConfirmed = nil, nil
    if cast.previous and check.dot.stacks then cast.previous.stackedInto = check.dot end
    -- The avoid took the builder's points off the count (onAvoided); it landed, so they're counted again.
    if cast.builderFrom and cast.awarded then countedPoints = math.min(COMBO_CAP, countedPoints + cast.awarded) end
    trace(string.format("COMBO after %s's %s: %d (had %d), %s: it landed, restored", cast.name, check.action,
        points, had, cast.builderFrom and "awarded" or "spent"))
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
        name = name,
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

-- A stacking DoT cast on a mob that already has it (STACKING_DOTS; DoesItDie 0.10.0): one more application, up to
-- `cap`, on the running tick rhythm. The refreshed duration counts from the latest tick slot, so a partial tick at the
-- very end isn't counted and the estimate errs low. The previous DoT's ticks carry over; it stays as the cast's
-- `previous`, so an avoided stack puts it back (removeAvoidedDot).
local function stackOnto(dot, previous, cap)
    local anchor = previous.firstTickAt or previous.appliedAt
    local slot = anchor + math.max(0, math.floor((dot.appliedAt - anchor) / previous.interval)) * previous.interval
    -- A tick for the next slot that already landed a little early stays in the past, so the refreshed schedule
    -- doesn't roll back and count it twice (DoesItDie 0.10.0).
    while dot.interval > 0 and previous.nextTickAt and slot + dot.interval < previous.nextTickAt - TICK_MATCH_WINDOW do
        slot = slot + dot.interval
    end
    -- And one due at the slot itself that hasn't come yet (it lands a moment after the recast): the schedule starts a
    -- slot earlier, so that tick is the new one's first rather than nobody's. Its refresh then counts from there,
    -- one tick short (errs low).
    if previous.nextTickAt and math.abs(previous.nextTickAt - slot) < TICK_MATCH_WINDOW and slot - dot.interval >= anchor then
        slot = slot - dot.interval
    end
    dot.stacks = math.min(cap, (previous.stacks or 1) + 1)
    dot.appliedAt, dot.nextTickAt, dot.expiresAt = slot, slot + dot.interval, slot + dot.duration
    if previous.firstTickAt then dot.firstTickAt, dot.lastTickIndex = slot, 0 end
    dot.ticksSeen, dot.tickSum, dot.normalTicks = previous.ticksSeen, previous.tickSum, previous.normalTicks
    dot.lastTickAt, dot.lastTickAmount = previous.lastTickAt, previous.lastTickAmount
    dot.lastTickShape, dot.lastTickCrit = previous.lastTickShape, previous.lastTickCrit
    dot.missed, dot.doubtful, dot.learnedAtApply = previous.missed, previous.doubtful, previous.learnedAtApply
    previous.stackedInto = dot -- its own ticks now count for this one (meterSkipReason)
end

-- Before 1.14.0 "1,002 Shadow damage" was read as 2 (the thousands separator), and DoesItDie found sizes learned for
-- such spells stayed wrong after its own fix (Bane of Agony rank 6). Which spells read 1000 or more depends on gear
-- (Forever's tooltips include spell power), so the first cast of each spell whose tooltip now does (the DoT, or the
-- upfront hit the meter learning takes off) forgets what was learned for it, every combo point count too, once, before
-- this cast reads it (DoesItDie 0.10.1). Spells under 1000 were read right and keep theirs.
function Dots.ForgetPreFix(spellID, total, desc)
    local done = Dots.overThousand
    if not done or done[spellID] or not total then return end
    if total < 1000 then
        local direct = parseDirectPart(desc)
        if not (type(direct) == "number" and direct >= 1000) then return end
    end
    done[spellID] = true
    local prefix, forgot = spellID .. "x", {}
    for key in pairs(ticks) do
        if key == spellID or (type(key) == "string" and key:sub(1, #prefix) == prefix) then forgot[#forgot + 1] = key end
    end
    for _, key in ipairs(forgot) do
        ticks[key], tickWeights[key] = nil, nil
        dropSnapshots(key)
    end
    trace(string.format("OVER 999 tooltip for spell %d (%d dmg): %s", spellID, total, #forgot > 0
        and ("forgot sizes learned under the old reading of its numbers: " .. #forgot) or "nothing learned to forget"))
end

-- The poison tracking can't be tried in game here, so it never raises an error: each way in runs through
-- poisonGuard, and an error turns it off until the next reload, with a line in /sab dots. The other DoTs carry on.
local poisonsBroken = false
local function poisonGuard(fn, ...)
    if poisonsBroken then return nil end
    local ok, result = pcall(fn, ...)
    if ok then return result end
    poisonsBroken = true
    trace("ERROR in the poison tracking, off until reload: " .. tostring(result))
    return nil
end

-- Wall-clock seconds for the saved coatings, from time(); GetTime() if the client gives none.
local function wallClock()
    if type(time) == "function" then
        local ok, now = pcall(time)
        if ok and type(now) == "number" and not isSecret(now) then return now end
    end
    return GetTime()
end

-- A saved coating that holds what the tracking needs (the saved variables may be from another version, or edited).
local function wellFormedPoison(poison)
    return type(poison) == "table" and type(poison.name) == "string" and type(poison.total) == "number"
        and poison.total > 0 and type(poison.school) == "number" and type(poison.duration) == "number"
        and poison.duration > 0 and type(poison.coatedAt) == "number" and type(poison.expires) == "number"
end

-- A poison put on a weapon: remember what it will do, until it wears off.
local function onCoating(spellID, name, desc)
    local kind, a, b, c, d = parseCoating(desc)
    if not kind then return end
    local now = wallClock()
    if kind == "direct" then
        poisonState.directAt, poisonState.directUntil = now, now + a
        trace("POISON " .. name .. " coated: strikes at once, so other poisons wait for a second tick")
        return
    end
    poisonState.dots[name] = { spellID = spellID, name = name, total = a, school = b, duration = c,
        coatedAt = now, expires = now + d }
    trace(string.format("POISON %s coated: %s dmg over %ss on a proc, for %s min", name, tostring(a), tostring(c),
        tostring(math.floor(d / 60 + 0.5))))
end

-- Whether the weapons carry a coating, by the game's own word: true, false, or nil when it can't be read.
local function weaponsCoated()
    if type(GetWeaponEnchantInfo) ~= "function" then return nil end
    local ok, main, _, _, _, off = pcall(GetWeaponEnchantInfo)
    if not ok or isSecret(main) or isSecret(off) then return nil end
    return (main or off) and true or false
end

-- Whether a coating is still on: within its lifetime, and not denied by the weapons (after a moment to update).
-- A weapon that still carries a coating keeps it past its lifetime, which may have run on while logged out.
local function coatingOn(coatedAt, expires, now)
    local coated = weaponsCoated()
    if coated == false and now - coatedAt > POISON_GRACE then return false end
    return now <= expires or coated == true
end

-- The poison with damage over time the weapons carry, the latest coated, or nil. Worn-off coatings are forgotten.
local function activePoison()
    local now, best = wallClock(), nil
    for name, poison in pairs(poisonState.dots) do
        if not wellFormedPoison(poison) then
            poisonState.dots[name] = nil
        elseif not coatingOn(poison.coatedAt, poison.expires, now) then
            poisonState.dots[name] = nil
            trace("POISON " .. tostring(name) .. " worn off")
        elseif not best or poison.coatedAt > best.coatedAt then
            best = poison
        end
    end
    return best
end

local function directPoisonOn()
    local now = wallClock()
    local untilAt = tonumber(poisonState.directUntil) or 0
    return untilAt > now and coatingOn(tonumber(poisonState.directAt) or 0, untilAt, now)
end

-- Returns the target key the DoT was applied to, or nil if the cast wasn't a tracked DoT.
local function onPlayerCast(spellID, castGUID)
    local key, pointsAtSend = castTargetKey(castGUID)
    local ok, name, desc = pcall(spellNameAndDescription, spellID)
    if not ok or not name or isSecret(name) then return end
    local awarded
    if type(desc) == "string" and not isSecret(desc) then
        awarded = comboPointsAwarded(desc)
        if awarded then onBuilderCast(key, awarded) end
        -- Only one Fire trap can be active: any new one (Explosive Trap too) replaces the armed one.
        if armedTrap and desc:find("Fire trap") then armedTrap = nil end
        if desc:find("[Cc]oats a weapon") then
            poisonGuard(onCoating, spellID, name, desc)
            return
        end
    end
    if IGNORED_SPELLS[name] then return end
    local isFinisher = isFinisherDescription(desc)
    local comboPoints, comboSource
    if isFinisher then comboPoints, comboSource = comboPointsForCast() end
    -- Unknown points: parse the lowest entry (errs low), and don't use or teach learned tick sizes.
    local total, school, duration, statedInterval = parseDot(desc, comboPoints or 1)
    if not total then
        if type(desc) == "string" and not isSecret(desc) and ns.locale.shouldLogUnread(spellID, desc) then
            trace(string.format("NOT READ %s (id %d): %s", name, spellID, desc))
        end
        return
    end
    Dots.ForgetPreFix(spellID, total, desc)
    -- A finisher's tick size depends on the points spent, so learned sizes are kept per point count.
    local tickKey = spellID
    if isFinisher then tickKey = comboPoints and (spellID .. "x" .. comboPoints) or nil end
    -- Unknown points: this cast's damage reaches the meter but no tally, so nothing is learned for the spell this fight.
    if not tickKey then combatUntracked[spellID] = true end

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

    if not key then
        combatUntracked[spellID] = true -- the damage meter still counts what this cast deals
        return
    end

    dotsByTarget[key] = dotsByTarget[key] or {}
    local previous = dotsByTarget[key][name]
    local dot = newDot(spellID, tickKey, name, total, school, duration, statedInterval, now)
    local stacking = STACKING_DOTS[name]
    if stacking and stacking.class then
        local okClass, _, class = pcall(UnitClass, "player")
        if not okClass or isSecret(class) or class ~= stacking.class then stacking = nil end
    end
    -- Only onto one still running: one that ran out stays on the books until housekeep drops it.
    if previous and stacking and now <= previous.expiresAt then stackOnto(dot, previous, stacking.cap) end
    dotsByTarget[key][name] = dot
    -- A builder that is a DoT (Garrote, Rake) below the cap: its point says whether it landed. Garrote opens from
    -- stealth and starts the white swings with it, so a swing's miss lands with the cast and dropped it (reported).
    lastDotCast = { key = key, name = name, dot = dot, previous = previous, at = now,
                    comboRead = isFinisher and comboSource == "read" and comboPoints or nil,
                    builderFrom = not isFinisher and awarded and pointsAtSend and pointsAtSend < COMBO_CAP
                        and pointsAtSend or nil, awarded = awarded, pointsAtSend = pointsAtSend }
    tallyCast(dot, isFinisher and 0 or parseDirectPart(desc)) -- a finisher's point table is no upfront hit
    local learned = tickKey and ticks[tickKey]
    trace(string.format("CAST %s (id %d)%s%s: %d dmg over %ss, school %d, tick every %ss, per-tick %s", name, spellID,
        isFinisher and string.format(" %s combo points (%s)", tostring(comboPoints or "?"), comboSource) or "",
        dot.stacks and string.format(" stack %d (ticks kept on the beat, next at %+.1fs)", dot.stacks,
            dot.nextTickAt - now) or "",
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
        combatReadable[dot.tickKey] = true -- the meter's total then holds ticks the tally didn't count
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
    if dot.tickKey then dropSnapshots(dot.tickKey) end -- other mobs' DoTs that haven't ticked must not keep the old size
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

-- The same first tick with its amount hidden, which is the usual case: a trap springs in combat, where UNIT_COMBAT's
-- amounts are secret, so springTrap never started one there (DoesItDie 0.10.0: "never tracked in combat"). With no
-- number to check, school and timing alone decide, as for a cast DoT's later ticks; another player's Fire hit in the
-- window can spring it on that mob instead. It goes in the tally, so the damage meter can teach the trap's real tick.
local function springTrapHidden(key, unit, school, now)
    local trap = armedTrap
    if not trap or school ~= trap.school then return false end
    if now > trap.expiresAt + trap.interval + TICK_MATCH_WINDOW then
        trace(string.format("TRAP %s expired after %.0fs with no first tick", trap.name, now - trap.placedAt))
        armedTrap = nil
        return false
    end
    if now < trap.placedAt + trap.interval - TICK_MATCH_WINDOW then return false end
    local dot = newDot(trap.spellID, trap.spellID, trap.name, trap.total, trap.school, trap.duration,
        trap.interval, now - trap.interval)
    armedTrap = nil
    dotsByTarget[key] = dotsByTarget[key] or {}
    dotsByTarget[key][trap.name] = dot
    tallyCast(dot, 0)
    -- No amount to record: this tick is counted by hand and anchors the rhythm, as a cast DoT's first hidden tick does.
    dot.ticksSeen = 1
    dot.lastTickAmount, dot.lastTickShape, dot.lastTickCrit = 0, 1, false
    local tickIndex = anchorTick(dot, 1, now)
    tallyHiddenTick(dot, 1)
    trace(string.format("TRAP %s sprung on %s (amount hidden): %.1fs after placing, tick %d/%d", trap.name, unit,
        now - trap.placedAt, tickIndex, dot.totalTicks))
    return true
end

-- A hit on a mob as a poison's tick (see POISON_LIFETIME): only its school is read, so it works with the amounts
-- secret. A Nature hit on the rhythm of the poison's DoT on the mob is its next tick; with none there, or past its
-- end (it was put on again meanwhile), it is the first tick of a new one (or, with a poison that strikes at once
-- also on, the second of two a tick apart). Hits off the rhythm, and those on the rhythm of the player's own
-- Nature spells, are left alone. Returns the mob's key when a poison's DoT starts.
local function onPoisonCombat(unit, action, school)
    if isSecret(action) or (action ~= "WOUND" and action ~= "ABSORB") then return end
    if isSecret(school) or school ~= SCHOOL_MASKS.Nature then return end
    local key = unitKey(unit)
    if not key then return end
    local poison = activePoison()
    if not poison then return end
    local now = GetTime()
    local dots = dotsByTarget[key]
    local dot = dots and dots[poison.name]
    -- The same hit arrives once per unit token showing the mob.
    if (dot and dot.lastTickAt == now) or poisonCandidates[key] == now then return end
    for _, other in pairs(dots or {}) do
        if not other.proc and other.school == school and distanceToExpectedTick(other, now) <= TICK_MATCH_WINDOW then
            return
        end
    end
    if dot and now <= dot.expiresAt + TICK_MATCH_WINDOW then
        local distance, index = distanceToExpectedTick(dot, now)
        if distance > TICK_MATCH_WINDOW_ANCHORED or index <= dot.lastTickIndex then return end
        dot.ticksSeen = dot.ticksSeen + 1
        local number = anchorTick(dot, index, now)
        trace(string.format("POISON %s tick on %s (%s/%s)", poison.name, tostring(unit), tostring(number),
            tostring(dot.totalTicks)))
        return
    end
    local interval = KNOWN_TICK_INTERVALS[poison.name] or DEFAULT_TICK_INTERVAL
    local first = now
    if directPoisonOn() then
        local seen = poisonCandidates[key]
        if not seen or math.abs(now - seen - interval) > TICK_MATCH_WINDOW then
            poisonCandidates[key] = now
            trace(string.format("POISON Nature hit on %s: %s, or a poison that strikes at once; waiting for a tick",
                unit, poison.name))
            return
        end
        first = seen
    end
    poisonCandidates[key] = nil
    local fresh = newDot(poison.spellID, nil, poison.name, poison.total, poison.school, poison.duration, interval,
        first - interval)
    fresh.proc = true
    fresh.seenAt = first -- the marker lists it from here, not from its proc, which came before the DoTs seen since
    fresh.ticksSeen = 1
    anchorTick(fresh, 1, first)
    if first ~= now then
        fresh.ticksSeen = 2
        anchorTick(fresh, 1, now)
    end
    dotsByTarget[key] = dotsByTarget[key] or {}
    dotsByTarget[key][poison.name] = fresh
    trace(string.format("POISON %s on %s%s: %s dmg over %ss, one stack", poison.name, tostring(unit),
        dot and " again" or "", tostring(poison.total), tostring(poison.duration)))
    return key
end

-- Returns the target key when this hit was the first tick of a DoT that was waiting for it (so the marker can
-- flash now that the DoT shows), else nil.
-- The same hit arrives once per unit token showing the mob (target, nameplateN, focus...) and must count once. But
-- two DoTs of one school can tick for the same amount in the same instant: those are two hits from the same token.
-- So within an instant each signature (mob, amount, school) remembers its token and the DoTs it fed.
local combatFrameAt
local combatFrameHits = {}

-- Within one instant, the record for a hit's signature: a repeat from the same token feeds another DoT, one from
-- another token is a copy (returns nil). See combatFrameHits above.
local function hitRecord(signature, unit, now)
    if combatFrameAt ~= now then
        combatFrameHits = {}
        combatFrameAt = now
    end
    local hit = combatFrameHits[signature]
    if hit then
        if hit.unit ~= unit then return nil end
    else
        hit = { unit = unit, fed = {} }
        combatFrameHits[signature] = hit
    end
    return hit
end

-- Forever keeps hit amounts secret in combat (seen in game: not one tick or hit amount readable in a whole session of
-- Rends), while the action and school stay readable (DoesItDie 0.9.1). So a hit is matched on school and timing alone:
-- one in a DoT's school, on its rhythm, in a slot not yet taken, is its tick. That keeps the DoT and anchors its
-- rhythm, but teaches no size: the estimate keeps the learned or description tick, and the damage meter teaches the
-- size after combat. A DoT is only dropped for missing ticks on a mob whose hits have shown a readable school since it
-- was applied (DoesItDie drops it on any mob in view): where the school is hidden too, no tick could be matched.
-- Physical bleeds can take a white hit landing in the window for a tick, so their hidden hits never move the rhythm:
-- they stay on the schedule from the cast (DoesItDie 0.9.2: anchoring on white hits let Rend's schedule drift earlier
-- with each one, until the marker ran out a tick before Rend did).
local amounts            -- nil until a hit is seen, then "readable" or "secret" (for /sab dots)
local schoolHitAt = {}   -- mob key -> when a hit with a readable school last landed on it
local SCHOOL_KEEP = 60   -- seconds a mob's last such hit is remembered

local function countHiddenTickOnSchedule(dot, index)
    dot.missed = 0
    dot.hiddenSlot = index
    local nextTickAt = dot.appliedAt + (index + 1) * dot.interval
    if nextTickAt > dot.nextTickAt then dot.nextTickAt = nextTickAt end
    return index
end

-- Returns the mob's key when a DoT waiting for its first tick now shows, else nil.
local function onHiddenAmountHit(key, unit, school)
    local dots = dotsByTarget[key]
    if not dots and not armedTrap then return end
    local now = GetTime()
    local hit = hitRecord(key .. ":hidden:" .. school, unit, now)
    if not hit then return end
    local best, bestName, bestDistance, bestIndex
    for name, dot in pairs(dots or {}) do
        if not hit.fed[name] and not dot.proc and dot.school == school then
            local distance, index = distanceToExpectedTick(dot, now)
            local window = dot.firstTickAt and TICK_MATCH_WINDOW_ANCHORED or TICK_MATCH_WINDOW
            local freshSlot
            if dot.firstTickAt then
                freshSlot = index > dot.lastTickIndex
            else
                freshSlot = index > (dot.hiddenSlot or 0)
            end
            if freshSlot and distance <= window and (not bestDistance or distance < bestDistance) then
                best, bestName, bestDistance, bestIndex = dot, name, distance, index
            end
        end
    end
    if not best then
        -- An armed trap springs in combat, where amounts are hidden: this is the only way its first tick comes.
        if springTrapHidden(key, unit, school, now) then return key end
        return
    end
    local wasWaiting = isWaiting(best)
    best.ticksSeen = best.ticksSeen + 1
    best.lastTickAmount, best.lastTickShape, best.lastTickCrit = 0, tickShape(best, tickNumberAt(best, now)), false
    best.offBeatCandidate = nil
    local tickIndex
    if school == SCHOOL_MASKS.Physical and not best.firstTickAt then
        tickIndex = countHiddenTickOnSchedule(best, bestIndex)
    else
        tickIndex = anchorTick(best, bestIndex, now)
    end
    hit.fed[bestName] = true
    tallyHiddenTick(best, best.lastTickShape)
    trace(string.format("TICK %s (amount hidden) on %s (tick %d/%d)%s", bestName, unit, tickIndex, best.totalTicks,
        wasWaiting and ", now shown" or ""))
    if wasWaiting then return key end
end

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
    local schoolKnown = not isSecret(school) and type(school) == "number"
    if schoolKnown then schoolHitAt[key] = GetTime() end
    if isSecret(amount) or type(amount) ~= "number" then
        if amounts ~= "secret" then
            amounts = "secret"
            trace("Hit amounts are secret here: ticks are matched by school and timing, and their sizes learned from"
                .. " the damage meter after combat")
        end
        if schoolKnown then return onHiddenAmountHit(key, unit, school) end
        return
    end
    if not schoolKnown then return end
    if amounts ~= "readable" then
        amounts = "readable"
        trace("Hit amounts are readable: ticks are matched and their sizes learned")
    end
    local isCrit = not isSecret(flag) and flag == "CRITICAL"
    if not dotsByTarget[key] and not armedTrap then return end
    local dots = dotsByTarget[key] or {}

    -- The same hit fires for target, nameplateN, softenemy...: handle it once (see combatFrameHits above).
    local now = GetTime()
    local hit = hitRecord(key .. ":" .. amount .. ":" .. school, unit, now)
    if not hit then return end
    local fed = hit.fed

    local best, bestName, bestDistance, bestIndex
    local zeroAbsorb = absorbed and amount == 0
    local candidates = 0
    for name, dot in pairs(dots) do
        if not fed[name] and not dot.proc and dot.school == school
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
            if not fed[name] and not dot.proc and dot.school == school then
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

-- DoTs that will go on ticking where the addon can't see (a table on Dots: this file is near Lua's 200 locals): the
-- damage meter counts those ticks and the tally does not, so learning from this fight would size the DoT too big (a
-- review caught it: one tick seen, five out of sight, saved at 1.7 times the real tick). dead: the mob died, so its
-- DoTs stop and the meter has no more of them either.
function Dots.LoseSight(dots, now, dead)
    if not dots or dead then return end
    for _, dot in pairs(dots) do
        if now < dot.expiresAt then dot.lostSight = true end
    end
end

local function housekeep(now)
    resolveFinisherCheck(now)
    for key, at in pairs(schoolHitAt) do
        if now - at > SCHOOL_KEEP then schoolHitAt[key] = nil end
    end
    for key, at in pairs(poisonCandidates) do
        if now - at > POISON_CANDIDATE_KEEP then poisonCandidates[key] = nil end
    end
    for key, dots in pairs(dotsByTarget) do
        for name, dot in pairs(dots) do
            local late = (dot.ticksSeen == 0 and dot.travel) or 0
            while dot.nextTickAt < now - TICK_MATCH_WINDOW - late and dot.nextTickAt <= dot.expiresAt do
                dot.nextTickAt = dot.nextTickAt + dot.interval
                -- A tick of a DoT already seen ticking, passing while the mob is out of view: the meter has it.
                if dot.ticksSeen > 0 and not dot.lostSight and not isObservable(key) then dot.lostSight = true end
                -- Only a tick that could have been seen counts as missed: the mob is in view, and its hits
                -- show their school.
                if dot.ticksSeen == 0 and isObservable(key) and (schoolHitAt[key] or -1) >= dot.appliedAt then
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
    if not dot.shape then return ticksLeft * expectedTick(dot) * (dot.stacks or 1) end
    local average, total = expectedTick(dot), 0
    for number = math.max(1, dot.totalTicks - ticksLeft + 1), dot.totalTicks do
        total = total + average * tickShape(dot, number)
    end
    return total
end

-- Remaining damage per DoT on a mob (by unitKey), oldest application first (a poison from when it was first seen).
-- DoTs still waiting for their first tick are left out. A DoT being cast on the mob replaces the one of the same
-- name it would refresh.
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
                    appliedAt = dot.seenAt or dot.appliedAt, damage = damage }
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
-- Tick sizes from the damage meter (DoesItDie 0.9.1 and 0.9.3; see the tally above)
---------------------------------------------------------------------------

local LEARN_MIN_FACTORS = 2                       -- at least two (average) ticks' worth this combat
local LEARN_RATIO_MIN, LEARN_RATIO_MAX = 0.5, 2.5 -- real vs description outside this: something else got mixed in
local LEARN_WEIGHT_CAP = 20                       -- older fights count as at most this many ticks, so gear catches up

-- Why a key isn't learned from this combat, or nil. "" skips quietly (nothing was counted).
local function meterSkipReason(key, t, counted, totals, keysPerSpell)
    if t.factors < LEARN_MIN_FACTORS then
        return t.ticks > 0 and string.format("only %d tick(s) counted", t.ticks) or ""
    end
    if counted.readable[key] then return "a readable tick already taught it" end
    if t.unclear then return "its upfront hit can't be told apart in this client's language" end
    -- Ticks of a DoT cast before this combat: the casts that fed the meter aren't in this tally. (A trap sprung with its
    -- amount hidden is in it, springTrapHidden.)
    if #t.dots == 0 then return "not cast this combat" end
    if counted.untracked[t.spellID] then return "a cast had no known target, so the meter has damage not counted here" end
    if counted.untracked.all then return "the addon was loaded mid-fight, so the meter has casts not counted here" end
    -- Not counted (DoesItDie 0.10.0): a cast surely avoided (it dealt nothing; it blocked learning for the whole fight;
    -- avoidConfirmed, see removeAvoidedDot) and a stack's earlier application (its ticks went on in the stack that
    -- replaced it).
    for _, dot in ipairs(t.dots) do
        -- A stack dropped for an avoid carries the earlier stacks' ticks seen, so the check below misses it.
        if dot.avoided and not dot.avoidConfirmed then
            return "a cast was dropped for an avoid that may have been a white swing's"
        end
        if dot.ticksSeen == 0 and not dot.avoidConfirmed and not dot.stackedInto then
            return "a cast's DoT never showed a tick (out of sight, or the mob died first)"
        end
        if dot.lostSight then return "a cast's DoT ticked out of sight, so the meter has ticks not counted here" end
    end
    if not totals[t.spellID] then return "no readable damage meter total" end
    if keysPerSpell[t.spellID] > 1 then return "several combo point sizes share one meter total" end
end

-- spells: the damage meter's per-spell rows for the combat that just ended ({ spellID, totalAmount }); counted: that
-- combat's tally (takeCombatTally). Learns a real average tick for every DoT whose ticks were counted, blended with the
-- saved size by tick count. Returns how many sizes were learned.
local function learnFromMeter(spells, counted)
    local totals = {}
    for _, sp in ipairs(spells or {}) do
        local id, amount = sp.spellID, sp.totalAmount
        if not isSecret(id) and not isSecret(amount) and type(amount) == "number" then totals[id] = amount end
    end
    local keysPerSpell = {}
    for _, t in pairs(counted.keys) do keysPerSpell[t.spellID] = (keysPerSpell[t.spellID] or 0) + 1 end
    local learned = 0
    for key, t in pairs(counted.keys) do
        local total, name = totals[t.spellID], t.name or tostring(t.spellID)
        local skip = meterSkipReason(key, t, counted, totals, keysPerSpell)
        if skip then
            if skip ~= "" then trace(string.format("LEARN %s skipped: %s", name, skip)) end
        else
            local direct = 0
            for _, dot in ipairs(t.dots) do
                if not dot.avoided and dot.directPart then direct = direct + dot.directPart end
            end
            local whole = direct + t.descTick * t.factors
            local ratio = whole > 0 and total / whole or 0
            if ratio ~= ratio or ratio < LEARN_RATIO_MIN or ratio > LEARN_RATIO_MAX then
                trace(string.format("LEARN %s skipped: meter %d over %d tick(s) is %.2fx the description", name,
                    total, t.ticks, ratio))
            else
                local tick = ratio * t.descTick
                local old, weight = ticks[key], math.min(tickWeights[key] or 0, LEARN_WEIGHT_CAP)
                if not old then weight = 0 end
                local blended = ((old or 0) * weight + tick * t.factors) / (weight + t.factors)
                ticks[key] = math.floor(blended * 10 + 0.5) / 10
                tickWeights[key] = weight + t.factors
                dropSnapshots(key)
                learned = learned + 1
                trace(string.format("LEARN %s: meter %d over %d tick(s)%s = %.1f per tick (description %.1f), saved %.1f",
                    name, total, t.ticks, direct > 0 and " minus upfront hit" or "", tick, t.descTick, ticks[key]))
            end
        end
    end
    return learned
end

-- The damage meter's per-spell totals for the combat that just ended, or nil and why ("wait" while it is still empty or
-- secret). Every table is checked before it's read (a row can be secret or off limits), all under one pcall.
local METER_TRIES, METER_RETRY_SECONDS = 20, 0.5

local function readableTable(v)
    if isSecret(v) or type(v) ~= "table" then return false end
    if type(canaccesstable) ~= "function" then return true end
    local ok, allowed = pcall(canaccesstable, v)
    return ok and allowed == true
end

local function meterSpellsNow()
    local DM = C_DamageMeter
    if type(DM) ~= "table" or type(DM.GetCombatSessionSourceFromType) ~= "function" then return nil, "no damage meter" end
    if type(DM.IsDamageMeterAvailable) == "function" then
        local okAvailable, available = pcall(DM.IsDamageMeterAvailable)
        if okAvailable and available == false then return nil, "switched off" end
    end
    local dmgType = Enum and Enum.DamageMeterType and Enum.DamageMeterType.DamageDone or 0
    local current = Enum and Enum.DamageMeterSessionType and Enum.DamageMeterSessionType.Current or 1
    local ok, spells, why = pcall(function()
        local src = DM.GetCombatSessionSourceFromType(current, dmgType, UnitGUID("player"))
        if not readableTable(src) or not readableTable(src.combatSpells) then return nil, "wait" end
        local list = src.combatSpells
        local n = #list
        if isSecret(n) or type(n) ~= "number" or n == 0 then return nil, "wait" end
        local rows = {}
        for i = 1, n do
            local sp = list[i]
            if readableTable(sp) then
                if isSecret(sp.totalAmount) or isSecret(sp.spellID) then return nil, "wait" end
                rows[#rows + 1] = { spellID = sp.spellID, totalAmount = sp.totalAmount }
            end
        end
        return rows
    end)
    if not ok then return nil, "unreadable" end
    return spells, why
end

local function learnAfterCombat(counted, triesLeft)
    if not enabled then return end
    if InCombatLockdown() then
        trace("LEARN skipped: a new fight started before the damage meter could be read")
        return
    end
    local spells, why = meterSpellsNow()
    if not spells and why == "wait" and triesLeft > 0 then
        C_Timer.After(METER_RETRY_SECONDS, function() learnAfterCombat(counted, triesLeft - 1) end)
        return
    end
    if not spells then
        trace("LEARN skipped: damage meter " .. (why == "wait" and "still empty or hidden" or tostring(why)))
        return
    end
    learnFromMeter(spells, counted)
end

-- Combat over: this combat's tally is taken (a new pull starts a fresh one) and learned from once the meter has it.
local function onCombatEnded()
    local counted = takeCombatTally()
    if next(counted.keys) == nil then return end
    C_Timer.After(METER_RETRY_SECONDS, function() learnAfterCombat(counted, METER_TRIES) end)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

-- fn(event): "changed" when the target's DoTs may have changed, "target" when the target did, "applied" when a
-- DoT lands on it, "crit" when a hit on it crits (anyone's).
local listeners = {}

local function notify(event)
    for _, fn in ipairs(listeners) do fn(event) end
end

-- The flag UNIT_COMBAT gives a hit on the target ("CRITICAL", "CRUSHING", "GLANCING" or ""), counted for /sab dots
-- whether or not its amount can be read. Forever keeps it readable (seen in game: BLOCK_REDUCED, and crits), unlike
-- the amount.
-- The event does not say whose hit it was, so a crit is anyone's. A hit reaches the addon under every token the mob
-- has (target, nameplate), so only the target's are counted. A crit tells the listeners "crit".
local flagCounts = {} -- "secret", or the flag ("none" for ""), -> hits
local function noteFlag(unit, action, flag)
    if isSecret(unit) or unit ~= "target" or isSecret(action) or action ~= "WOUND" then return end
    local key
    if isSecret(flag) then
        key = "secret"
    elseif type(flag) == "string" then
        key = flag == "" and "none" or flag
    else
        key = "none"
    end
    if not flagCounts[key] then
        trace(key == "secret" and "Hit flags on the target are secret: crits can't be seen"
            or ("Hit flag on the target readable: " .. key))
    end
    flagCounts[key] = (flagCounts[key] or 0) + 1
    if key == "CRITICAL" then notify("crit") end
end

-- For /sab dots: what the target's hit flags have shown since the last reload.
local function flagReport()
    if not next(flagCounts) then return "Hit flags on the target: not seen yet (hit your target, then /sab dots)" end
    local parts = {}
    for key, n in pairs(flagCounts) do
        if key ~= "secret" then parts[#parts + 1] = string.format("%s %d", key, n) end
    end
    table.sort(parts)
    local read = #parts > 0 and ("readable (" .. table.concat(parts, ", ") .. ")") or nil
    local hidden = flagCounts.secret and string.format("secret %d", flagCounts.secret) or nil
    return "Hit flags on the target: " .. (read and hidden and (read .. ", " .. hidden) or read or hidden)
end

local frame = CreateFrame("Frame")

-- Never register COMBAT_LOG_EVENT_UNFILTERED: Forever forbids it and shows a "blocked" popup.
local PLAYER_EVENTS = {
    "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_POWER_FREQUENT",
}
local EVENTS = { "PLAYER_TARGET_CHANGED", "UNIT_COMBAT", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
                 "PLAYER_REGEN_ENABLED" }

local function onEvent(_, event, ...)
    if event == "PLAYER_TARGET_CHANGED" then
        Dots.LoseSight(dotsByTarget.target, GetTime())
        dotsByTarget.target = nil -- only used when the target's GUID is secret
        resetComboCount()         -- combo points belong to the target they were built on
        dropCastInProgress("target changed")
        notify("target")

    elseif event == "PLAYER_REGEN_ENABLED" then
        onCombatEnded()

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
            if event == "NAME_PLATE_UNIT_REMOVED" then
                local ok, dead = pcall(UnitIsDeadOrGhost, token)
                Dots.LoseSight(dotsByTarget["plate:" .. token], GetTime(), ok and not isSecret(dead) and dead == true)
            end
            dotsByTarget["plate:" .. token] = nil
            notify("changed")
        end

    elseif event == "UNIT_COMBAT" then
        local unit, action, flag, _, school = ...
        local revealed = onUnitCombat(...)
        local poisoned = poisonGuard(onPoisonCombat, unit, action, school)
        local target = unitKey("target")
        if (revealed and revealed == target) or (poisoned and poisoned == target) then
            notify("changed")
            notify("applied")
        end
        noteFlag(unit, action, flag)
    end
end

-- Errors here are reported once each and the tracking carries on with the next event.
local reported = {}
frame:SetScript("OnEvent", ns.Timed("DoT tracking: events", function(...)
    local ok, err = pcall(onEvent, ...)
    if not ok and not reported[err] then
        reported[err] = true
        trace("ERROR " .. tostring(err))
        ns.Core.Print("Error in the DoT tracking (it carries on): " .. tostring(err))
    end
end))

-- The pet's DoTs (Scorpid Poison; DoesItDie 0.10.1): the pet casts them, so the player's cast path never sees them.
-- They come on a frame of their own (RegisterUnitEvent replaces the unit an event already listens to), each cast one
-- more stack (STACKING_DOTS). On the pet's target, else the player's; a mob with no readable key is skipped rather than
-- poisoned in the wrong place (and the fight teaches its size nothing, as for a player's cast). Pet casts don't go
-- through the avoid path: a dodged poison still adds a stack and refreshes the others, and as the stack carries their
-- ticks seen, missed ticks never drop it, so the estimate errs high for that duration (as in DoesItDie).
function Dots.PetCast(spellID)
    if isSecret(spellID) then return end
    local ok, name, desc = pcall(spellNameAndDescription, spellID)
    local stacking = ok and type(name) == "string" and not isSecret(name) and STACKING_DOTS[name]
    if not stacking or type(desc) ~= "string" or isSecret(desc) then return end
    local total, school, duration, statedInterval = parseDot(desc, 1)
    if not total then return end
    local okExists, exists = pcall(UnitExists, "pettarget")
    local key = unitKey((okExists and not isSecret(exists) and exists) and "pettarget" or "target")
    if not key then
        combatUntracked[spellID] = true -- the damage meter still counts what this cast deals
        return
    end
    local now = GetTime()
    dotsByTarget[key] = dotsByTarget[key] or {}
    local previous = dotsByTarget[key][name]
    local dot = newDot(spellID, spellID, name, total, school, duration, statedInterval, now)
    if previous and now <= previous.expiresAt then stackOnto(dot, previous, stacking.cap) end
    dotsByTarget[key][name] = dot
    tallyCast(dot, parseDirectPart(desc))
    if not previous or (previous.stacks or 1) < (dot.stacks or 1) then
        trace(string.format("PETDOT %s (id %d): stacks %d/%d", name, spellID, dot.stacks or 1, stacking.cap))
    end
    notify("changed")
    if key == unitKey("target") and not previous then notify("applied") end
end
Dots.petFrame = CreateFrame("Frame")
Dots.petFrame:SetScript("OnEvent", ns.Timed("DoT tracking: pet casts", function(_, _, _, _, spellID)
    local ok, err = pcall(Dots.PetCast, spellID)
    if not ok and not reported[err] then
        reported[err] = true
        trace("ERROR " .. tostring(err))
        ns.Core.Print("Error in the DoT tracking (it carries on): " .. tostring(err))
    end
end))

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
        db.dotTicks, db.dotTicksVersion, db.dotTickWeights = {}, TICKS_VERSION, {}
    end
    ticks = db.dotTicks
    -- How many ticks each saved size stands for, for blending what the damage meter teaches.
    if type(db.dotTickWeights) ~= "table" then db.dotTickWeights = {} end
    tickWeights = db.dotTickWeights
    -- The poisons on the weapons, kept across reloads (see POISON_LIFETIME).
    if type(db.dotPoisons) ~= "table" or type(db.dotPoisons.dots) ~= "table" then
        db.dotPoisons = { dots = {}, directUntil = 0 }
    end
    if type(db.dotPoisons.directUntil) ~= "number" then db.dotPoisons.directUntil = 0 end
    if type(db.dotPoisons.directAt) ~= "number" then db.dotPoisons.directAt = nil end
    poisonState = db.dotPoisons
    -- The spells already checked for sizes learned under the old reading of "1,002" (Dots.ForgetPreFix).
    if type(db.dotOverThousand) ~= "table" then db.dotOverThousand = {} end
    Dots.overThousand = db.dotOverThousand
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
        Dots.petFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "pet")
        if InCombatLockdown() or UnitAffectingCombat("player") then combatUntracked.all = true end
        trace("tracking on")
    else
        frame:UnregisterAllEvents()
        Dots.petFrame:UnregisterAllEvents()
        wipe(dotsByTarget)
        wipe(schoolHitAt)
        takeCombatTally()
        finisherCheck = nil
        wipe(poisonCandidates)
        castInProgress, lastDotCast, lastOutcome, armedTrap = nil, nil, nil, nil
        wipe(sentTargets)
        resetComboCount()
        trace("tracking off")
    end
end

function Dots.IsEnabled()
    return enabled
end

-- fn(event) for "changed", "target", "applied" and "crit" (see notify).
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

-- The same for the mob behind any unit token (a nameplate's), which may not be the target: DoTs are kept per mob.
function Dots.Unit(unit)
    housekeep(GetTime())
    local key = unitKey(unit)
    if not key or key == "target" then return 0, {} end -- "target" stands only for the current target
    local list = dotBreakdown(key)
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
    local poison = poisonGuard(activePoison)
    if poisonsBroken then
        out[#out + 1] = "Poison on the weapons: tracking off after an error (see below), back on after a reload"
    elseif poison then
        out[#out + 1] = string.format("Poison on the weapons: %s, %s dmg over %ss%s", poison.name,
            tostring(poison.total), tostring(poison.duration),
            poisonGuard(directPoisonOn) and " (and one that strikes at once)" or "")
    else
        out[#out + 1] = "Poison on the weapons: none with damage over time seen"
    end
    out[#out + 1] = flagReport()
    for i = math.max(1, #log - (n or 10) + 1), #log do out[#out + 1] = log[i] end
    return out
end

-- For the tests.
Dots.learnFromMeter = learnFromMeter
Dots.takeCombatTally = takeCombatTally
Dots.parseDirectPart = parseDirectPart
Dots.parseDot = parseDot
Dots.parseCoating = parseCoating
Dots.comboPointsAwarded = comboPointsAwarded
Dots.isFinisher = isFinisherDescription
