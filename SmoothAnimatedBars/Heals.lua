-- Healing on the way: the player's own heals over time and bandages, and heals they are casting, on themselves and on
-- their party or raid, with what each will still restore, for the heal markers on the player's, the party's and the
-- raid frames' health bars (HealMarker.lua). Off unless the heals setting is on; while off no event is registered.
--
-- Who a heal goes to comes from UNIT_SPELLCAST_SENT's target name, matched against the player's and each group
-- member's name, or with no name from the target. A member's heals are kept by their GUID (by name where that is
-- secret), so they stay with the member when the group's tokens move round. Anyone else's heals are not kept.
--
-- As for the DoTs (Dots.lua), everything here is the player's own and readable on Forever: the casts
-- (UNIT_SPELLCAST_*, the channel events for bandages) and the spell descriptions. Heals from anyone else are
-- left out: their size depends on the healer's gear, which no description tells. The player's health stays
-- secret, so the numbers here are plain and the comparison with health is left to StatusBars.
--
-- No tick is seen (the combat log is closed to addons), so a heal over time runs on its description: the same
-- share each tick, every 3 seconds (bandages every second), for its stated duration. Where the client lets the
-- player's own auras be read, a heal over time whose aura is gone is dropped and its expiry follows the aura's.
--
-- Eating and drinking ("Restores 61 health over 18 sec.", "... mana ...") are tracked the same way, health for
-- the health bar's marker and mana for the mana bar's. They last only while the player sits, which no API tells,
-- so they end when the player starts moving, casts anything else, or (out of combat, once seen) their aura goes.

local _, ns = ...

local Heals = {}
ns.Heals = Heals

local TICK_INTERVAL = 3       -- Renew, Rejuvenation, Regrowth
local CHANNEL_INTERVAL = 1    -- bandages
local AURA_GRACE = 0.5        -- seconds after a cast before a missing aura counts
local CHANNEL_AFTER = 1       -- a channel's own UNIT_SPELLCAST_SUCCEEDED comes this soon after its start
local AURA_EVERY = 0.5        -- seconds between looking at the auras while heals run
local SENT_SECONDS = 10
-- STOP ends every cast and comes just before SUCCEEDED, so a stopped cast is only dropped if no success follows.
local CAST_STOP_GRACE = 0.5
local MAX_TRACE_LINES = 100

local SCHOOLS = { Holy = 2, Nature = 8 }
-- The school a heal's liquid takes: by the healer's class; bandages have their own, whoever applies them.
local CLASS_SCHOOLS = { PRIEST = 2, PALADIN = 2, DRUID = 8, SHAMAN = 8 }
local BANDAGE_SCHOOL = "bandage" -- a look of its own (HealMarker.lua): Nature's colours, with pluses
-- Food and drink have looks of their own too. Their ticks are taken as every 3 seconds (not seen in game yet).
local FOOD_SCHOOL, DRINK_SCHOOL = "food", "drink"
local REST_INTERVAL = 3

-- key (who it goes to, "|", the spell's name, with "|mana" for drink) -> heal { who, spellID, name, total, duration,
-- interval, appliedAt, expiresAt, channel, school, resource ("health" or "mana"), rest (food or drink) }
local heals = {}
local casting           -- { who, spellID, castGUID, name, amount, school }: a heal being cast on the player or a member
local sentTo = {}       -- castGUID -> { who (nil for someone not kept), at, name }
-- Everyone a heal can be kept for besides the player: the party, then the raid (whose units include the party's and the
-- player's own, the same people by GUID).
local GROUP = { "party1", "party2", "party3", "party4" }
for i = 1, 40 do GROUP[#GROUP + 1] = "raid" .. i end
local log = {}
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

local function readable(ok, v)
    return ok and v ~= nil and not isSecret(v)
end

local function spellNameAndDescription(spellID)
    if isSecret(spellID) then return nil end
    local name, desc
    if C_Spell and C_Spell.GetSpellName then
        name = C_Spell.GetSpellName(spellID)
    elseif GetSpellInfo then
        name = GetSpellInfo(spellID)
    end
    local descFn = (C_Spell and C_Spell.GetSpellDescription) or GetSpellDescription
    if descFn then desc = descFn(spellID) end
    if isSecret(name) or isSecret(desc) then return nil end
    return name, desc
end

-- What a heal's description promises, or nil if it is not a heal:
--   "Heals the target of 830 damage over 15 sec."                      (Forever's Renew)
--   "Heals the target for 32 over 12 sec."                              (Rejuvenation)
--   "Heals a friendly target for 93 to 107 and another 98 over 21 sec." (Regrowth: direct, then over time)
--   "Heals 66 damage over 6 sec."                                       (a bandage, First Aid)
--   "Heals a friendly target for 193 to 237."                           (Flash Heal: direct only)
--   "A slow casting spell that heals a single target for 819 to 920."   (Greater Heal)
--   "A powerful prayer that heals the target and their party for 179 to 191." (Prayer of Healing: the target's share)
--   "Instantly heals the caster for 146 to 181."                        (Desperate Prayer)
-- Returns the amount over time and its duration (nil, nil if none) and the direct amount (0 if none). A
-- direct heal counts its lowest roll, so the marker errs short rather than promising too much.
-- Read nowhere, in any language: Tranquility (the party, every 2 sec while channelled) and food restoring a share of
-- health each second.
local function parseHeal(desc)
    if type(desc) ~= "string" or isSecret(desc) then return nil end
    if not (desc:find("^Heal") or desc:find("heals a single target for") or desc:find("heals the caster for")
            or desc:find("heals the target and their party for")) then
        return nil
    end
    local over, duration
    for amount, secs in desc:gmatch("(%d+)[%a ]-over (%d+%.?%d*) sec") do
        over, duration = tonumber(amount), tonumber(secs)
    end
    local direct = tonumber(desc:match("for (%d+) to %d+") or desc:match("for (%d+)%.") or "") or 0
    if not (over and duration and duration > 0) then over, duration = nil, nil end
    if not over and direct <= 0 then return nil end
    return over, duration, direct
end

-- What food or drink restores, or nil if the description is neither:
--   "Restores 61 health over 18 sec. Must remain seated while eating."
--   "Restores 151 mana over 18 sec. Must remain seated while drinking."
--   "Restores 294 health and 294 mana over 18 sec. ..."              (food and drink in one)
--   "... If you spend at least 10 seconds eating you will become well fed ..."    (food with a buff)
--   "... If you eat for 10 seconds will also increase your Agility by 10 ..."     (another wording of it)
-- Returns health, mana (each nil if not restored), the duration, and the seconds to the buff (nil if none).
local function parseRest(desc)
    if type(desc) ~= "string" or isSecret(desc) or not desc:find("^Restores") then return nil end
    -- Any unit after the seconds: an item left untranslated keeps the English text with the client's unit ("21초").
    local duration = tonumber(desc:match("over (%d+%.?%d*)") or "")
    if not duration or duration <= 0 then return nil end
    local health = tonumber(desc:match("(%d+) health") or "")
    local mana = tonumber(desc:match("(%d+) mana") or "")
    if not health and not mana then return nil end
    return health, mana, duration, tonumber(desc:match("at least (%d+) sec") or desc:match("eat for (%d+) sec") or "")
end

-- The readers the rest of this file uses: the English ones, then every other language's (Locale.lua, as the DoTs
-- are read), on the text with its non-breaking spaces made plain (Wowhead's have them; %s does not match them) and
-- English thousands separators dropped: the client writes "Heals a friendly target for 1,177 to 1,309." (reported:
-- Holy Light rank 8, the first rank over 999, showed nothing while the lower ranks worked; Wowhead's text has no
-- commas, so the cases never had one). Korean and Chinese write the comma too; the other languages' "1.177" and
-- "1 177" are joined by their readers (Locale.lua, `joinThousands`). Repeated until none is left, as one pass joins
-- only every other group of "1,234,567".
local function plain(desc)
    if type(desc) ~= "string" or isSecret(desc) then return nil end
    desc = desc:gsub("\194\160", " "):gsub("\226\128\175", " ")
    local n
    repeat
        desc, n = desc:gsub("(%d),(%d%d%d)%f[^%d]", "%1%2")
    until n == 0
    return desc
end

local function readHeal(desc)
    desc = plain(desc)
    if not desc then return nil end
    local over, duration, direct = parseHeal(desc)
    if over or (direct and direct > 0) then return over, duration, direct end
    if ns.locale then return ns.locale.parseHeal(desc) end
end

local function readRest(desc)
    desc = plain(desc)
    if not desc then return nil end
    local health, mana, duration, fed = parseRest(desc)
    if health or mana then return health, mana, duration, fed end
    if ns.locale then return ns.locale.parseRest(desc) end
end

-- A cast whose description talks of healing but reads as no heal: its text goes to the trace once, so /sab heals
-- shows the wording to teach the readers. In another language, any text with a number that nothing read.
local unread = {}
local function noteUnread(name, desc)
    if unread[name] or type(desc) ~= "string" then return end
    local english = not ns.locale or ns.locale.looksEnglish(desc)
    if english and not desc:lower():find("heal") then return end
    if not english and not desc:find("[0-9]") then return end
    unread[name] = true
    trace(string.format("UNREAD %s: %q", name, desc))
end

local function playerSchool()
    local ok, _, class = pcall(UnitClass, "player")
    if not readable(ok, class) then return SCHOOLS.Holy end
    return CLASS_SCHOOLS[class] or SCHOOLS.Holy
end

-- A realm as it stands in "Name-Realm": without its spaces. Nothing (since client build 71037 GetRealmName gives "")
-- is no realm.
local function realmPart(realm)
    if type(realm) ~= "string" or isSecret(realm) then return nil end
    realm = realm:gsub(" ", "")
    if realm == "" then return nil end
    return realm
end

-- Whether a sent target name is the player's: the first name alone, or with Forever's surname (UnitName's
-- second value, which the player frame shows), or with the realm ("Name-Realm"). loose: also any "Name-..." when
-- the player's realm cannot be read (exact readings are tried for the whole group first, so a member from another
-- realm with the player's first name is theirs).
local function isPlayerName(targetName, loose)
    local ok, me, surname = pcall(UnitName, "player")
    if not readable(ok, me) or type(me) ~= "string" or me == "" then return false end
    if targetName == me then return true end
    if type(surname) == "string" and not isSecret(surname) and surname ~= ""
        and targetName == me .. " " .. surname then
        return true
    end
    local shown = PlayerName and PlayerName.GetText and select(2, pcall(PlayerName.GetText, PlayerName))
    if type(shown) == "string" and not isSecret(shown) and targetName == shown then return true end
    local okRealm, realm = pcall(GetRealmName)
    realm = okRealm and realmPart(realm)
    if realm and targetName == me .. "-" .. realm then return true end
    return loose and not realm and targetName:sub(1, #me + 1) == me .. "-"
end

-- Whether a sent target name is a group member's: the name alone, or with their realm ("Name-Realm") or the second
-- value UnitName gives (a realm, or on Forever perhaps a surname); a member UnitName gives no realm for is from the
-- player's own. loose: also any "Name-...", only where the player's realm cannot be read (as isPlayerName), so a heal
-- on someone outside the group from another realm is never taken for a member's of the same first name.
local function isUnitName(unit, targetName, loose)
    local ok, name, second = pcall(UnitName, unit)
    if not readable(ok, name) or type(name) ~= "string" or name == "" then return false end
    if targetName == name then return true end
    local okRealm, realm = pcall(GetRealmName)
    realm = okRealm and realmPart(realm)
    if type(second) == "string" and not isSecret(second) and second ~= "" then
        if targetName == name .. "-" .. (realmPart(second) or "") or targetName == name .. " " .. second then
            return true
        end
    elseif realm and targetName == name .. "-" .. realm then
        return true
    end
    return loose and not realm and targetName:sub(1, #name + 1) == name .. "-"
end

local function exists(unit)
    local ok, there = pcall(UnitExists, unit)
    return readable(ok, there) and there and true or false
end

-- Who a unit's heals are kept under: "player" for the player (their own raid unit too), else the unit's GUID, its name
-- where the GUID is secret, or nil when neither can be read (no heal is kept for them).
local function keyOf(unit)
    if unit == "player" then return "player" end
    if not exists(unit) then return nil end
    local okMe, isMe = pcall(UnitIsUnit, unit, "player")
    if readable(okMe, isMe) and isMe then return "player" end
    local ok, guid = pcall(UnitGUID, unit)
    if readable(ok, guid) and type(guid) == "string" and guid ~= "" then
        -- UnitIsUnit may answer with a secret (Forever's docs: SecretWhenUnitComparisonRestricted); the GUID says too.
        local okMine, mine = pcall(UnitGUID, "player")
        if readable(okMine, mine) and guid == mine then return "player" end
        return guid
    end
    local okName, name = pcall(UnitName, unit)
    if readable(okName, name) and type(name) == "string" and name ~= "" then return "name:" .. name end
end

-- Who's who in the group now: keys (keyOf) to units, for a pass over many heals.
local function unitMap()
    local map = {}
    for _, unit in ipairs(GROUP) do
        if exists(unit) then
            local key = keyOf(unit)
            if key and not map[key] then map[key] = unit end
        end
    end
    return map
end

-- The group unit whose heals are kept under who, as the group stands now: from units (unitMap) if given, else by a
-- search of the group.
local function unitOf(who, units)
    if who == "player" then return "player" end
    if units then return units[who] end
    for _, unit in ipairs(GROUP) do
        if exists(unit) and keyOf(unit) == who then return unit end
    end
end

-- The group's units to search: none when neither party1 nor raid1 exists (no group: the client fills both from 1), so
-- a cast sent alone does not ask after 44 units twice (about 3500 instructions a cast, by tools/harness/events.py).
local NO_GROUP = {}
local function members()
    if not exists("party1") and not exists("raid1") then return NO_GROUP end
    return GROUP
end

-- Who a cast sent at targetName goes to: "player", a group member's key (keyOf), or nil for anyone else. A named target
-- is known only by name; with no name the cast goes to the target if the player can help it, else to the player.
-- The second value names the group unit, for the trace.
local function recipient(targetName)
    -- A name the client keeps secret says nothing of whose it is (a mouseover or click-cast heal could be on anyone):
    -- not kept, rather than taken for the target's or the player's.
    if isSecret(targetName) then return nil end
    if type(targetName) == "string" and targetName ~= "" then
        -- Exact readings first, the player's then each member's; then the loose "Name-..." ones in the same order.
        local group = members()
        for _, loose in ipairs({ false, true }) do
            if isPlayerName(targetName, loose) then return "player" end
            for _, unit in ipairs(group) do
                if exists(unit) and isUnitName(unit, targetName, loose) then return keyOf(unit), unit end
            end
        end
        return nil
    end
    if not UnitExists("target") then return "player" end
    local okMe, isMe = pcall(UnitIsUnit, "target", "player")
    if readable(okMe, isMe) and isMe then return "player" end
    for _, unit in ipairs(members()) do
        if exists(unit) then
            local ok, same = pcall(UnitIsUnit, "target", unit)
            if readable(ok, same) and same then return keyOf(unit), unit end
        end
    end
    local okHelp, help = pcall(UnitCanAssist, "player", "target")
    if readable(okHelp, help) and help then return nil end
    return "player"
end

local function onSent(targetName, castGUID)
    local now = GetTime()
    for guid, sent in pairs(sentTo) do
        if now - sent.at > SENT_SECONDS then sentTo[guid] = nil end
    end
    if castGUID ~= nil and not isSecret(castGUID) then
        local who, unit = recipient(targetName)
        sentTo[castGUID] = { who = who, unit = unit, at = now,
            name = isSecret(targetName) and "(secret)" or tostring(targetName) }
    end
end

-- Who a cast went to (as recipient): as it was sent, else (no send seen) by the target now. The second value says how
-- it was decided, for the trace.
local function wentTo(castGUID)
    local sent = castGUID ~= nil and not isSecret(castGUID) and sentTo[castGUID]
    if sent then return sent.who, "sent at " .. sent.name .. (sent.unit and (" (" .. sent.unit .. ")") or "") end
    return recipient(nil), "no send seen"
end

-- Who for the trace: "you", or the group unit they are now.
local function whom(who)
    if who == "player" then return "you" end
    return unitOf(who) or "a group member"
end

local function sameCast(cast, castGUID, spellID)
    if cast.castGUID and castGUID ~= nil and not isSecret(castGUID) then return castGUID == cast.castGUID end
    return not isSecret(spellID) and spellID == cast.spellID
end

local function newHeal(spellID, total, duration, interval, now, channel, school, who)
    return { spellID = spellID, total = total, duration = duration, interval = interval,
             ticks = math.max(1, math.floor(duration / interval + 0.5)), appliedAt = now,
             expiresAt = now + duration, channel = channel, school = school, resource = "health",
             who = who or "player" }
end

local function keyFor(who, name)
    return who .. "|" .. name
end

-- What a heal over time still has to restore: its share for each tick not yet landed.
local function remaining(heal, now)
    local done = math.floor((now - heal.appliedAt) / heal.interval + 0.05)
    local left = heal.ticks - done
    if heal.expiresAt and now >= heal.expiresAt then left = 0 end
    -- The aura says how long it really has: never more ticks than fit before then.
    if heal.auraEnds then
        left = math.min(left, math.max(0, math.floor((heal.auraEnds - now) / heal.interval + 0.95)))
    end
    if left <= 0 then return 0 end
    return heal.total / heal.ticks * math.min(left, heal.ticks)
end

---------------------------------------------------------------------------
-- Auras, where readable
---------------------------------------------------------------------------

-- auraState: for the player's own lookup and the group's, nil until checked, then "readable" or "secret" (/sab heals).
local auraState, auraCheckedAt = {}, -math.huge

-- A heal's aura on whoever it went to: true, expirationTime when found; false when readably gone; nil when the client
-- does not say. The player's by spell ID; a party member's by name, the player's own (Forever's
-- GetAuraDataBySpellName, which like the player's lookup needs the aura not to be secret).
local function healAura(heal, units)
    local unit = unitOf(heal.who, units)
    if not unit then return nil end
    local kind = unit == "player" and "player" or "group"
    local ok, aura
    if unit == "player" then
        local get = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
        if type(get) ~= "function" then return nil end
        ok, aura = pcall(get, heal.spellID)
    else
        local get = C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName
        if type(get) ~= "function" or type(heal.name) ~= "string" then return nil end
        ok, aura = pcall(get, unit, heal.name, "HELPFUL|PLAYER")
    end
    -- Each lookup's state apart (in combat the player's may answer "none" while a member's is secret): traced as it
    -- changes, so the two cannot flood /sab heals by turns.
    local whose = kind == "player" and "yours" or "group members'"
    if not ok or isSecret(aura) then
        if auraState[kind] ~= "secret" then
            auraState[kind] = "secret"
            trace("Auras (" .. whose .. ") are secret here: heals run on their descriptions")
        end
        return nil
    end
    if auraState[kind] ~= "readable" then
        auraState[kind] = "readable"
        trace("Auras (" .. whose .. ") are readable: heals follow them")
    end
    if aura == nil then return false end
    local ends = type(aura) == "table" and aura.expirationTime
    if type(ends) ~= "number" or isSecret(ends) or ends <= 0 then ends = nil end
    return true, ends
end

-- Whether the unit a heal went to is in sight, where its auras can be read: a member out of range answers "none" for
-- an aura still on them. The player always is; a member when UnitIsVisible says so.
local function inSight(who, units)
    local unit = unitOf(who, units)
    if unit == "player" then return true end
    if not unit then return false end
    local ok, seen = pcall(UnitIsVisible, unit)
    return readable(ok, seen) and seen and true or false
end

local function inCombat()
    local ok, fighting = pcall(UnitAffectingCombat, "player")
    if readable(ok, fighting) then return fighting and true or false end
    return InCombatLockdown() and true or false
end

-- Follows the aura's expiry, and drops a heal over time whose aura is gone (dispelled, cancelled). Seen in game:
-- in combat the lookup said "none" for a Rejuvenation that was on the player, dropping it each time. So "none"
-- only counts for an aura that was found for this heal before, and only out of combat; otherwise the heal runs
-- its full time.
local function checkAuras(now)
    auraCheckedAt = now
    local units -- who's who in the group, found once for the pass and only if a member has a heal
    for name, heal in pairs(heals) do
        if not heal.channel and now - heal.appliedAt >= AURA_GRACE then
            if heal.who ~= "player" and not units then units = unitMap() end
            local found, ends = healAura(heal, units)
            if found then
                heal.auraSeen = true
                if ends then heal.auraEnds = ends end
            elseif found == false and heal.auraSeen and not inCombat() and inSight(heal.who, units) then
                heals[name] = nil
                trace("GONE " .. heal.name .. ": its aura is not on " .. whom(heal.who))
            end
        end
    end
end

---------------------------------------------------------------------------
-- Casts
---------------------------------------------------------------------------

local function isRestSpell(spellID)
    local _, desc = spellNameAndDescription(spellID)
    local health, mana = readRest(desc)
    return (health or mana) ~= nil
end

-- Sitting to eat or drink ends: what was left will not come. Returns true if anything ended.
local function endRest(reason)
    local ended = false
    for key, heal in pairs(heals) do
        if heal.rest then
            heals[key] = nil
            ended = true
            trace(string.format("REST %s ended (%s)", heal.name, reason))
        end
    end
    return ended
end

-- Food or drink: always on the player. Returns the resources it restores ("health", "mana"), or nil.
local function onRest(spellID)
    local name, desc = spellNameAndDescription(spellID)
    if not name then return nil end
    local health, mana, duration, fedAfter = readRest(desc)
    if not health and not mana then return nil end
    local now = GetTime()
    local started = {}
    if not fedAfter and not unread[name] then
        unread[name] = true
        trace(string.format("REST %s has no buff that we can read: %q", name, desc))
    end
    for _, part in ipairs({ { "health", health, FOOD_SCHOOL }, { "mana", mana, DRINK_SCHOOL } }) do
        local resource, amount, school = part[1], part[2], part[3]
        if amount then
            local heal = newHeal(spellID, amount, duration, REST_INTERVAL, now, false, school)
            heal.name, heal.resource, heal.rest = name, resource, true
            -- The build-up to the buff shows on one bar: the health, for food and drink in one.
            if fedAfter and #started == 0 then heal.fedAt = now + fedAfter end
            heals[keyFor("player", name .. (resource == "mana" and "|mana" or ""))] = heal
            started[#started + 1] = resource
            trace(string.format("REST %s (id %d): %d %s over %ss", name, spellID, amount, resource, duration))
        end
    end
    return started
end

-- A heal cast on the player or a party member landed: its part over time starts now. Returns whether the heals
-- changed, who a heal over time started on (nil if none), the school of a cast heal that just landed, and who it
-- landed on.
local function onSucceeded(castGUID, spellID)
    local landed = casting and sameCast(casting, castGUID, spellID) and casting.school or nil
    local landedOn = landed and casting.who or nil
    local wasCasting = landed ~= nil
    if wasCasting then
        trace("LANDED " .. casting.name .. " on " .. whom(casting.who))
        casting = nil
    end
    local name, desc = spellNameAndDescription(spellID)
    if not name then return wasCasting, nil, landed, landedOn end
    local over, duration, direct = readHeal(desc)
    if not over then
        if not direct then noteUnread(name, desc) end
        return wasCasting, nil, landed, landedOn
    end
    local who = wentTo(castGUID)
    if not who then return wasCasting, nil, landed, landedOn end
    local now = GetTime()
    local key = keyFor(who, name)
    -- A bandage's channel comes with a success event of its own, which must not restart it as a heal over time.
    local current = heals[key]
    if current and current.channel and current.spellID == spellID and now - current.appliedAt <= CHANNEL_AFTER then
        return wasCasting, nil, landed, landedOn
    end
    heals[key] = newHeal(spellID, over, duration, TICK_INTERVAL, now, false, playerSchool(), who)
    heals[key].name = name
    trace(string.format("HOT %s (id %d) on %s: %d over %ss", name, spellID, whom(who), over, duration))
    return true, who, landed, landedOn
end

-- A bandage being applied: who to, or nil.
local function onChannelStart(castGUID, spellID)
    local name, desc = spellNameAndDescription(spellID)
    if not name then return end
    local over, duration = readHeal(desc)
    if not over then
        noteUnread(name, desc)
        return
    end
    local who = wentTo(castGUID)
    if not who then return end
    local key = keyFor(who, name)
    heals[key] = newHeal(spellID, over, duration, CHANNEL_INTERVAL, GetTime(), true, BANDAGE_SCHOOL, who)
    heals[key].name = name
    heals[key].castGUID = not isSecret(castGUID) and castGUID or nil
    trace(string.format("CHANNEL %s (id %d) on %s: %d over %ss", name, spellID, whom(who), over, duration))
    return who
end

-- A channel ends when it is done or broken (damage stops a bandage): what was left will not come.
local function onChannelStop(castGUID, spellID)
    for key, heal in pairs(heals) do
        if heal.channel and sameCast(heal, castGUID, spellID) then
            heals[key] = nil
            trace("CHANNEL " .. heal.name .. " ended")
            return true
        end
    end
end

-- A heal with a cast time shows while it is cast, with everything it will restore.
local function onCastStart(castGUID, spellID)
    casting = nil
    local name, desc = spellNameAndDescription(spellID)
    if not name then return end
    local over, _, direct = readHeal(desc)
    if not over and not direct then
        noteUnread(name, desc)
        return
    end
    local who, how = wentTo(castGUID)
    if not who then
        trace(string.format("CASTING %s on someone else (%s)", name, how))
        return
    end
    casting = { who = who, spellID = spellID, castGUID = not isSecret(castGUID) and castGUID or nil, name = name,
                amount = (over or 0) + direct, school = playerSchool(), startedAt = GetTime() }
    trace(string.format("CASTING %s on %s: %d (%s)", name, whom(who), casting.amount, how))
    return true
end

local function onCastEnded(event, castGUID, spellID)
    if not casting or not sameCast(casting, castGUID, spellID) then return end
    if event == "UNIT_SPELLCAST_STOP" then
        casting.stoppedAt = casting.stoppedAt or GetTime()
        return
    end
    trace("CASTING " .. casting.name .. (event == "UNIT_SPELLCAST_INTERRUPTED" and " interrupted" or " failed"))
    casting = nil
    return true
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local listeners = {}
local function notify(event, ...)
    for _, fn in ipairs(listeners) do fn(event, ...) end
end

local frame = CreateFrame("Frame")

local PLAYER_EVENTS = {
    "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_AURA",
}
local EVENTS = { "PLAYER_DEAD", "PLAYER_STARTED_MOVING" }

local function onEvent(_, event, ...)
    if event == "UNIT_SPELLCAST_SENT" then
        local _, targetName, castGUID, spellID = ...
        onSent(targetName, castGUID)
        -- Casting anything but more food or drink stands the player up.
        if not isRestSpell(spellID) and endRest("cast") then notify("changed") end
    elseif event == "UNIT_SPELLCAST_START" then
        local _, castGUID, spellID = ...
        if onCastStart(castGUID, spellID) then notify("changed") end
    elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_FAILED"
        or event == "UNIT_SPELLCAST_INTERRUPTED" then
        local _, castGUID, spellID = ...
        if onCastEnded(event, castGUID, spellID) then notify("changed") end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local _, castGUID, spellID = ...
        local rest = onRest(spellID)
        if rest then
            notify("changed")
            for _, resource in ipairs(rest) do notify("applied", resource) end
            return
        end
        local changed, appliedOn, landed, landedOn = onSucceeded(castGUID, spellID)
        if changed then notify("changed") end
        if appliedOn then notify("applied", "health", appliedOn) end
        if landed then notify("landed", landed, landedOn) end
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        local _, castGUID, spellID = ...
        local stood = endRest("channel")
        local who = onChannelStart(castGUID, spellID)
        if who then
            notify("changed")
            notify("applied", "health", who)
        elseif stood then
            notify("changed")
        end
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        local _, castGUID, spellID = ...
        if onChannelStop(castGUID, spellID) then notify("changed") end
    elseif event == "UNIT_AURA" then
        checkAuras(GetTime())
        notify("changed")
    elseif event == "PLAYER_STARTED_MOVING" then
        if endRest("moved") then notify("changed") end
    elseif event == "PLAYER_DEAD" then
        -- What was on the player goes; heals over time already on party members keep ticking.
        for key, heal in pairs(heals) do
            if heal.who == "player" or heal.channel then heals[key] = nil end
        end
        casting = nil
        notify("changed")
    end
end

local reported = {}
frame:SetScript("OnEvent", ns.Timed("heal tracking: events", function(...)
    local ok, err = pcall(onEvent, ...)
    if not ok and not reported[err] then
        reported[err] = true
        trace("ERROR " .. tostring(err))
        ns.Core.Print("Error in the heal tracking (it carries on): " .. tostring(err))
    end
end))

---------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------

function Heals.Enable(on)
    on = on and true or false
    if on == enabled then return end
    enabled = on
    if on then
        for _, event in ipairs(EVENTS) do frame:RegisterEvent(event) end
        for _, event in ipairs(PLAYER_EVENTS) do frame:RegisterUnitEvent(event, "player") end
        trace("tracking on")
    else
        frame:UnregisterAllEvents()
        wipe(heals)
        wipe(sentTo)
        casting = nil
        trace("tracking off")
    end
end

function Heals.IsEnabled()
    return enabled
end

-- fn(event, ...) for "changed" (the heals may have changed), "applied" (a heal started; with "health" or "mana", and
-- who it went to, as Heals.KeyOf) and "landed" (a cast heal landed; with its school and who it went to).
function Heals.Listen(fn)
    listeners[#listeners + 1] = fn
end

-- What is still on the way to the health ("health") or mana ("mana") of who (Heals.KeyOf): the total and the list,
-- oldest first, each { name, spellID, school, heal }. Finished heals are dropped first.
local function onTheWay(resource, who)
    local now = GetTime()
    if next(heals) and now - auraCheckedAt >= AURA_EVERY then checkAuras(now) end
    if casting and casting.stoppedAt and now - casting.stoppedAt > CAST_STOP_GRACE then
        trace("CASTING " .. casting.name .. " stopped without landing")
        casting = nil
    end
    local list, total = {}, 0
    local standIn = casting and casting.who == who and casting
    for key, heal in pairs(heals) do
        local amount = remaining(heal, now)
        if amount <= 0 then
            heals[key] = nil
            trace("EXPIRE " .. heal.name .. (heal.resource == "mana" and " (mana)" or "")
                .. (heal.who ~= "player" and (" on " .. whom(heal.who)) or ""))
        elseif heal.resource == resource and heal.who == who and not (standIn and standIn.name == heal.name) then
            list[#list + 1] = { name = heal.name, spellID = heal.spellID, school = heal.school,
                                appliedAt = heal.appliedAt, heal = amount }
        end
    end
    -- A heal being cast stands in for the one of the same name it would refresh.
    if standIn and resource == "health" then
        list[#list + 1] = { name = casting.name, spellID = casting.spellID, school = casting.school,
                            appliedAt = casting.startedAt, heal = casting.amount, provisional = true }
    end
    table.sort(list, function(a, b) return a.appliedAt < b.appliedAt end)
    for _, entry in ipairs(list) do total = total + entry.heal end
    return math.floor(total + 0.5), list
end

-- How far along eating or drinking is to its buff on "health" or "mana": 0 to 1 (1 once it is reached), and when
-- it started, which tells one meal from the next. nil when nothing there leads to a buff.
function Heals.Charge(resource)
    for _, heal in pairs(heals) do
        if heal.fedAt and heal.resource == resource then
            local progress = (GetTime() - heal.appliedAt) / (heal.fedAt - heal.appliedAt)
            return math.min(1, progress), heal.appliedAt
        end
    end
end

function Heals.Player()
    return onTheWay("health", "player")
end

function Heals.Mana()
    return onTheWay("mana", "player")
end

-- Whether any heal is on the way to anyone, or being cast: with none, a group's markers have nothing to look up.
function Heals.Busy()
    return next(heals) ~= nil or casting ~= nil
end

-- Who a unit's heals are kept under ("player", a party member's GUID or name), or nil for none.
Heals.KeyOf = keyOf

-- What is on the way to a unit's health (party1..4, raid1..40 or the player, as the group stands now), as Heals.Player.
function Heals.For(unit)
    local who = type(unit) == "string" and not isSecret(unit) and keyOf(unit)
    if not who then return 0, {} end
    return onTheWay("health", who)
end

-- For /sab heals: what is on the way, then the last n trace lines.
function Heals.Debug(n)
    local function describe(total, list)
        local parts = {}
        for _, entry in ipairs(list) do
            parts[#parts + 1] = string.format("%s %d", entry.name, math.floor(entry.heal + 0.5))
        end
        return string.format("%d (%s)", total, #parts > 0 and table.concat(parts, ", ") or "none")
    end
    local out = { string.format("Heals: tracking %s, health on the way %s, mana %s, auras %s",
        enabled and "on" or "off", describe(Heals.Player()), describe(Heals.Mana()),
        string.format("yours %s, the group's %s", auraState.player or "not checked yet",
            auraState.group or "not checked yet")) }
    local seen = { player = true }
    for _, unit in ipairs(GROUP) do
        local who = keyOf(unit)
        if who and not seen[who] then
            seen[who] = true
            local total, list = Heals.For(unit)
            if #list > 0 then
                out[#out + 1] = string.format("  %s: health on the way %s", unit, describe(total, list))
            end
        end
    end
    for i = math.max(1, #log - (n or 10) + 1), #log do out[#out + 1] = log[i] end
    return out
end

-- A spell another group member casts: the school of the heal liquid it would show in (by the caster's class, as the
-- player's own heals), or nil when it is no heal, its text cannot be read, or the class is not a healer's or is secret.
-- For others' heals on the heal marker (HealMarker.lua), whose amount says nothing of who heals.
-- Second value, why (for /sab heals): "heal", "helpful" (no text to read, the game calls it helpful), "no heal",
-- "no text", "unreadable", "not a healer". The class is asked first, so a mage's casts read no spell text, and what a
-- spell's text says is kept by its ID (every language's readers may run over it).
local castKinds = {} -- spell ID -> "heal" or "no heal", once its text has been read
function Heals.CastSchool(unit, spellID)
    if spellID == nil or isSecret(spellID) then return nil, "unreadable" end
    local okClass, _, class = pcall(UnitClass, unit)
    if not readable(okClass, class) or not CLASS_SCHOOLS[class] then return nil, "not a healer" end
    local why = castKinds[spellID]
    if not why then
        local ok, name, desc = pcall(spellNameAndDescription, spellID)
        if not ok or not name then return nil, "unreadable" end
        -- Over time, or direct only (Flash Heal reads as nil, nil and its direct amount).
        local over, _, direct = readHeal(desc)
        if over or (direct and direct > 0) then
            why = "heal"
            castKinds[spellID] = why
        elseif type(desc) == "string" and desc ~= "" then
            castKinds[spellID] = "no heal"
            return nil, "no heal"
        else
            -- A spell the player does not know may have no text until the client loads it (a paladin's Holy Light on
            -- a priest's client, seen in game as the shared look): the game's own word that it is helpful stands in,
            -- and the text is asked for, for the next cast.
            if C_Spell and C_Spell.RequestLoadSpellData then pcall(C_Spell.RequestLoadSpellData, spellID) end
            local okHelp, helpful = pcall(C_Spell and C_Spell.IsSpellHelpful or IsHelpfulSpell, spellID)
            if not (okHelp and helpful == true) then return nil, "no text" end
            why = "helpful"
        end
    end
    if why == "no heal" then return nil, why end
    return CLASS_SCHOOLS[class], why
end

-- For the tests: the English readers, and the ones that try every language.
Heals.parseHeal = parseHeal
Heals.parseRest = parseRest
Heals.readHeal = readHeal
Heals.readRest = readRest
