-- Healing on the way: the player's own heals over time and bandages on themselves, and heals they are casting
-- on themselves, with what each will still restore, for the heal marker on the player's health bar
-- (HealMarker.lua). Off unless the heals setting is on; while off no event is registered.
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

-- key (the spell's name, with "|mana" for drink) -> heal { spellID, name, total, duration, interval, appliedAt,
-- expiresAt, channel, school, resource ("health" or "mana"), rest (food or drink) }
local heals = {}
local casting           -- { spellID, castGUID, name, amount, school }: a heal being cast on the player
local sentOnSelf = {}   -- castGUID -> { self = bool, at }
local log = {}
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
-- Returns the amount over time and its duration (nil, nil if none) and the direct amount (0 if none). A
-- direct heal counts its lowest roll, so the marker errs short rather than promising too much.
local function parseHeal(desc)
    if type(desc) ~= "string" or isSecret(desc) or not desc:find("^Heal") then return nil end
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
-- Returns health, mana (each nil if not restored), the duration, and the seconds to the buff (nil if none).
local function parseRest(desc)
    if type(desc) ~= "string" or isSecret(desc) or not desc:find("^Restores") then return nil end
    local duration = tonumber(desc:match("over (%d+%.?%d*) sec") or "")
    if not duration or duration <= 0 then return nil end
    local health = tonumber(desc:match("(%d+) health") or "")
    local mana = tonumber(desc:match("(%d+) mana") or "")
    if not health and not mana then return nil end
    return health, mana, duration, tonumber(desc:match("at least (%d+) sec") or "")
end

-- A cast whose description talks of healing but reads as no heal: its text goes to the trace once, so
-- /sab heals shows the wording to teach parseHeal.
local unread = {}
local function noteUnread(name, desc)
    if unread[name] or type(desc) ~= "string" or not desc:lower():find("heal") then return end
    unread[name] = true
    trace(string.format("UNREAD %s: %q", name, desc))
end

local function playerSchool()
    local ok, _, class = pcall(UnitClass, "player")
    if not readable(ok, class) then return SCHOOLS.Holy end
    return CLASS_SCHOOLS[class] or SCHOOLS.Holy
end

-- Whether a sent target name is the player's: the first name alone, or with Forever's surname (UnitName's
-- second value, which the player frame shows), or with the realm ("Name-Realm").
local function isPlayerName(targetName)
    local ok, me, surname = pcall(UnitName, "player")
    if not readable(ok, me) or type(me) ~= "string" or me == "" then return false end
    if targetName == me then return true end
    if type(surname) == "string" and not isSecret(surname) and surname ~= ""
        and targetName == me .. " " .. surname then
        return true
    end
    local shown = PlayerName and PlayerName.GetText and select(2, pcall(PlayerName.GetText, PlayerName))
    if type(shown) == "string" and not isSecret(shown) and targetName == shown then return true end
    return targetName:sub(1, #me + 1) == me .. "-"
end

-- Whether a cast sent at targetName goes to the player. A named target is the player only by name; with no
-- name the cast is the player's own unless a friendly target other than the player takes it.
local function castsOnSelf(targetName)
    if type(targetName) == "string" and not isSecret(targetName) and targetName ~= "" then
        return isPlayerName(targetName)
    end
    if not UnitExists("target") then return true end
    local okMe, isMe = pcall(UnitIsUnit, "target", "player")
    if readable(okMe, isMe) and isMe then return true end
    local okHelp, help = pcall(UnitCanAssist, "player", "target")
    if readable(okHelp, help) and help then return false end
    return true
end

local function onSent(targetName, castGUID)
    local now = GetTime()
    for guid, sent in pairs(sentOnSelf) do
        if now - sent.at > SENT_SECONDS then sentOnSelf[guid] = nil end
    end
    if castGUID ~= nil and not isSecret(castGUID) then
        sentOnSelf[castGUID] = { self = castsOnSelf(targetName), at = now,
            name = isSecret(targetName) and "(secret)" or tostring(targetName) }
    end
end

-- Whether a cast went to the player: as it was sent, else (no send seen) by the target now.
-- The second value says how it was decided, for the trace.
local function wentToSelf(castGUID)
    local sent = castGUID ~= nil and not isSecret(castGUID) and sentOnSelf[castGUID]
    if sent then return sent.self, "sent at " .. sent.name end
    return castsOnSelf(nil), "no send seen"
end

local function sameCast(cast, castGUID, spellID)
    if cast.castGUID and castGUID ~= nil and not isSecret(castGUID) then return castGUID == cast.castGUID end
    return not isSecret(spellID) and spellID == cast.spellID
end

local function newHeal(spellID, total, duration, interval, now, channel, school)
    return { spellID = spellID, total = total, duration = duration, interval = interval,
             ticks = math.max(1, math.floor(duration / interval + 0.5)), appliedAt = now,
             expiresAt = now + duration, channel = channel, school = school, resource = "health" }
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

local auraState, auraCheckedAt = nil, -math.huge -- auraState: nil until checked, then "readable" or "secret" (for /sab heals)

-- The player's aura from spellID: true, expirationTime when found; false when readably gone; nil when the
-- client does not say.
local function playerAura(spellID)
    local get = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
    if type(get) ~= "function" then return nil end
    local ok, aura = pcall(get, spellID)
    if not ok or isSecret(aura) then
        if auraState ~= "secret" then auraState = "secret"; trace("Auras are secret here: heals run on their descriptions") end
        return nil
    end
    if auraState ~= "readable" then auraState = "readable"; trace("Auras are readable: heals follow them") end
    if aura == nil then return false end
    local ends = type(aura) == "table" and aura.expirationTime
    if type(ends) ~= "number" or isSecret(ends) or ends <= 0 then ends = nil end
    return true, ends
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
    for name, heal in pairs(heals) do
        if not heal.channel and now - heal.appliedAt >= AURA_GRACE then
            local found, ends = playerAura(heal.spellID)
            if found then
                heal.auraSeen = true
                if ends then heal.auraEnds = ends end
            elseif found == false and heal.auraSeen and not inCombat() then
                heals[name] = nil
                trace("GONE " .. name .. ": its aura is not on you")
            end
        end
    end
end

---------------------------------------------------------------------------
-- Casts
---------------------------------------------------------------------------

local function isRestSpell(spellID)
    local _, desc = spellNameAndDescription(spellID)
    local health, mana = parseRest(desc)
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
    local health, mana, duration, fedAfter = parseRest(desc)
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
            heals[name .. (resource == "mana" and "|mana" or "")] = heal
            started[#started + 1] = resource
            trace(string.format("REST %s (id %d): %d %s over %ss", name, spellID, amount, resource, duration))
        end
    end
    return started
end

-- A heal cast on the player landed: its part over time starts now. Returns whether the heals changed, whether
-- a heal over time started, and the school of a cast heal that just landed (it was being cast on the player).
local function onSucceeded(castGUID, spellID)
    local landed = casting and sameCast(casting, castGUID, spellID) and casting.school or nil
    local wasCasting = landed ~= nil
    if wasCasting then
        trace("LANDED " .. casting.name)
        casting = nil
    end
    local name, desc = spellNameAndDescription(spellID)
    if not name then return wasCasting, false, landed end
    local over, duration, direct = parseHeal(desc)
    if not over then
        if not direct then noteUnread(name, desc) end
        return wasCasting, false, landed
    end
    if not wentToSelf(castGUID) then return wasCasting, false, landed end
    local now = GetTime()
    -- A bandage's channel comes with a success event of its own, which must not restart it as a heal over time.
    local current = heals[name]
    if current and current.channel and current.spellID == spellID and now - current.appliedAt <= CHANNEL_AFTER then
        return wasCasting, false, landed
    end
    heals[name] = newHeal(spellID, over, duration, TICK_INTERVAL, now, false, playerSchool())
    heals[name].name = name
    trace(string.format("HOT %s (id %d): %d over %ss", name, spellID, over, duration))
    return true, true, landed
end

local function onChannelStart(castGUID, spellID)
    local name, desc = spellNameAndDescription(spellID)
    if not name then return end
    local over, duration = parseHeal(desc)
    if not over then
        noteUnread(name, desc)
        return
    end
    if not wentToSelf(castGUID) then return end
    heals[name] = newHeal(spellID, over, duration, CHANNEL_INTERVAL, GetTime(), true, BANDAGE_SCHOOL)
    heals[name].name = name
    heals[name].castGUID = not isSecret(castGUID) and castGUID or nil
    trace(string.format("CHANNEL %s (id %d): %d over %ss", name, spellID, over, duration))
    return true
end

-- A channel ends when it is done or broken (damage stops a bandage): what was left will not come.
local function onChannelStop(castGUID, spellID)
    for name, heal in pairs(heals) do
        if heal.channel and sameCast(heal, castGUID, spellID) then
            heals[name] = nil
            trace("CHANNEL " .. name .. " ended")
            return true
        end
    end
end

-- A heal with a cast time shows while it is cast, with everything it will restore.
local function onCastStart(castGUID, spellID)
    casting = nil
    local name, desc = spellNameAndDescription(spellID)
    if not name then return end
    local over, _, direct = parseHeal(desc)
    if not over and not direct then
        noteUnread(name, desc)
        return
    end
    local onSelf, how = wentToSelf(castGUID)
    if not onSelf then
        trace(string.format("CASTING %s on someone else (%s)", name, how))
        return
    end
    casting = { spellID = spellID, castGUID = not isSecret(castGUID) and castGUID or nil, name = name,
                amount = (over or 0) + direct, school = playerSchool(), startedAt = GetTime() }
    trace(string.format("CASTING %s on you: %d", name, casting.amount))
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
        local changed, applied, landed = onSucceeded(castGUID, spellID)
        if changed then notify("changed") end
        if applied then notify("applied", "health") end
        if landed then notify("landed", landed) end
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        local _, castGUID, spellID = ...
        local stood = endRest("channel")
        if onChannelStart(castGUID, spellID) then
            notify("changed")
            notify("applied", "health")
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
        wipe(heals)
        casting = nil
        notify("changed")
    end
end

local reported = {}
frame:SetScript("OnEvent", function(...)
    local ok, err = pcall(onEvent, ...)
    if not ok and not reported[err] then
        reported[err] = true
        trace("ERROR " .. tostring(err))
        ns.Core.Print("Error in the heal tracking (it carries on): " .. tostring(err))
    end
end)

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
        wipe(sentOnSelf)
        casting = nil
        trace("tracking off")
    end
end

function Heals.IsEnabled()
    return enabled
end

-- fn(event, ...) for "changed" (the heals may have changed), "applied" (a heal started; with "health" or
-- "mana") and "landed" (a heal cast on the player landed; with its school).
function Heals.Listen(fn)
    listeners[#listeners + 1] = fn
end

-- What is still on the way to the player's health ("health") or mana ("mana"): the total and the list, oldest
-- first, each { name, spellID, school, heal }. Finished heals are dropped first.
local function onTheWay(resource)
    local now = GetTime()
    if next(heals) and now - auraCheckedAt >= AURA_EVERY then checkAuras(now) end
    if casting and casting.stoppedAt and now - casting.stoppedAt > CAST_STOP_GRACE then
        trace("CASTING " .. casting.name .. " stopped without landing")
        casting = nil
    end
    local list, total = {}, 0
    for key, heal in pairs(heals) do
        local amount = remaining(heal, now)
        if amount <= 0 then
            heals[key] = nil
            trace("EXPIRE " .. heal.name .. (heal.resource == "mana" and " (mana)" or ""))
        elseif heal.resource == resource and not (casting and casting.name == heal.name) then
            list[#list + 1] = { name = heal.name, spellID = heal.spellID, school = heal.school,
                                appliedAt = heal.appliedAt, heal = amount }
        end
    end
    -- A heal being cast stands in for the one of the same name it would refresh.
    if casting and resource == "health" then
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
    return onTheWay("health")
end

function Heals.Mana()
    return onTheWay("mana")
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
        enabled and "on" or "off", describe(Heals.Player()), describe(Heals.Mana()), auraState or "not checked yet") }
    for i = math.max(1, #log - (n or 10) + 1), #log do out[#out + 1] = log[i] end
    return out
end

-- For the tests.
Heals.parseHeal = parseHeal
Heals.parseRest = parseRest
