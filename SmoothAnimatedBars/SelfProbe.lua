-- A probe for DoTs on the player: what Forever lets an addon read about the player's own debuffs and the hits that
-- land on the player, in combat and out. Nothing is drawn yet; this decides what a DoT marker on the player's health
-- bar can be built on.
--
-- What it notes, readable or secret, with the value when readable:
--   UNIT_AURA on the player: the payload, and each added harmful aura's fields;
--   the player's harmful auras through C_UnitAuras.GetUnitAuras, GetAuraDataByIndex and GetDebuffDataByIndex;
--   GetAuraDuration on each (the duration object widgets take), and the spell's description if its ID is readable;
--   UNIT_COMBAT on the player: action, flag, amount and school.
-- It listens to nothing until /sab self on, and stays on across reloads until /sab self off. /sab self prints the
-- counts; SmoothAnimatedBarsDB.selfProbe keeps them and the last events for /reload.

local _, ns = ...

local SelfProbe = {}
ns.SelfProbe = SelfProbe

local MAX_EVENTS = 120
local AURA_FIELDS = { "name", "spellId", "auraInstanceID", "duration", "expirationTime", "dispelName", "sourceUnit",
                      "applications", "isHarmful", "points" }
local COMBAT_FIELDS = { "action", "flag", "amount", "school" }

local store -- SmoothAnimatedBarsDB.selfProbe: { counts = { [where] = { [field] = { readable, secret } } }, events = {} }

local function isSecret(v)
    if type(issecretvalue) ~= "function" then return false end
    local ok, r = pcall(issecretvalue, v)
    return ok and r or false
end

local function inCombat()
    return InCombatLockdown() and true or false
end

-- A short readable form of a value for the saved log; "?" for a secret.
local function show(v)
    if isSecret(v) then return "?" end
    if type(v) == "table" then
        local parts = {}
        for i, x in ipairs(v) do
            parts[#parts + 1] = show(x)
            if i >= 4 then break end
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    if type(v) == "number" then return string.format("%.4g", v) end
    return tostring(v)
end

local function count(where, field, v)
    local key = where .. (inCombat() and " (combat)" or " (out)")
    local byField = store.counts[key] or {}
    store.counts[key] = byField
    local c = byField[field] or { 0, 0 }
    byField[field] = c
    if isSecret(v) then c[2] = c[2] + 1 else c[1] = c[1] + 1 end
end

local function event(line)
    local events = store.events
    events[#events + 1] = string.format("%s %s%s", date and date("%H:%M:%S") or "", inCombat() and "[combat] " or "", line)
    while #events > MAX_EVENTS do table.remove(events, 1) end
end

-- Notes an aura's fields under `where`, and returns the readable ones as "field=value ..." for the log.
local function noteAura(where, aura)
    if isSecret(aura) then
        count(where, "whole aura", aura)
        return "aura secret"
    end
    if type(aura) ~= "table" then return "no aura" end
    local parts = {}
    for _, field in ipairs(AURA_FIELDS) do
        local ok, v = pcall(function() return aura[field] end)
        if not ok then v = nil end
        count(where, field, v)
        parts[#parts + 1] = field .. "=" .. show(v)
    end
    return table.concat(parts, " ")
end

-- Whatever the duration object is, and whether its methods answer.
local function noteDuration(instanceID)
    local get = C_UnitAuras and C_UnitAuras.GetAuraDuration
    if type(get) ~= "function" or instanceID == nil or isSecret(instanceID) then return nil end
    local ok, d = pcall(get, "player", instanceID)
    if not ok then return "GetAuraDuration failed: " .. tostring(d) end
    count("GetAuraDuration", "object", d)
    local line = "duration " .. type(d) .. (isSecret(d) and " (secret)" or "")
    if type(d) == "table" or type(d) == "userdata" then
        for _, method in ipairs({ "GetRemainingDuration", "GetTotalDuration", "GetElapsedDuration" }) do
            local okM, fn = pcall(function() return d[method] end)
            if okM and type(fn) == "function" then
                local okC, v = pcall(fn, d)
                if okC then
                    count("GetAuraDuration", method, v)
                    line = line .. " " .. method .. "=" .. show(v)
                end
            end
        end
    end
    return line
end

local function noteDescription(spellID)
    if spellID == nil or isSecret(spellID) or not (C_Spell and C_Spell.GetSpellDescription) then return nil end
    local ok, text = pcall(C_Spell.GetSpellDescription, spellID)
    if not ok then return nil end
    count("spell description", "text", text)
    if isSecret(text) or type(text) ~= "string" then return "description " .. show(text) end
    return "description: " .. text:sub(1, 120)
end

-- Every harmful aura on the player, by each lookup the client offers.
local function scan(why)
    local seen = {}
    local U = C_UnitAuras or {}
    if type(U.GetUnitAuras) == "function" then
        local ok, auras = pcall(U.GetUnitAuras, "player", "HARMFUL")
        if not ok then
            event("GetUnitAuras failed: " .. tostring(auras))
        elseif isSecret(auras) then
            count("GetUnitAuras", "list", auras)
            event(why .. ": GetUnitAuras list secret")
        elseif type(auras) == "table" then
            count("GetUnitAuras", "list", auras)
            for i = 1, #auras do
                local aura = auras[i]
                local line = noteAura("GetUnitAuras", aura)
                if type(aura) == "table" and not isSecret(aura) then
                    local id = aura.auraInstanceID
                    if id ~= nil and not isSecret(id) then seen[id] = true end
                    local d = noteDuration(id)
                    if d then line = line .. " | " .. d end
                    local desc = noteDescription(aura.spellId)
                    if desc then line = line .. " | " .. desc end
                end
                event(why .. ": GetUnitAuras #" .. i .. " " .. line)
            end
            if #auras == 0 then event(why .. ": GetUnitAuras none") end
        end
    end
    for _, lookup in ipairs({ { "GetAuraDataByIndex", "HARMFUL" }, { "GetDebuffDataByIndex" } }) do
        local fn = U[lookup[1]]
        if type(fn) == "function" then
            for i = 1, 40 do
                local ok, aura = pcall(fn, "player", i, lookup[2])
                if not ok then event(lookup[1] .. " failed: " .. tostring(aura)); break end
                if aura == nil then
                    if i == 1 then event(why .. ": " .. lookup[1] .. " none") end
                    break
                end
                event(why .. ": " .. lookup[1] .. " #" .. i .. " " .. noteAura(lookup[1], aura))
            end
        end
    end
end

local function onAura(unit, info)
    if isSecret(unit) or unit ~= "player" then return end
    count("UNIT_AURA", "payload", info)
    if isSecret(info) then
        event("UNIT_AURA payload secret")
    elseif type(info) == "table" then
        local added = info.addedAuras
        count("UNIT_AURA", "addedAuras", added)
        if type(added) == "table" and not isSecret(added) then
            for i = 1, #added do
                local aura = added[i]
                local harmful = type(aura) == "table" and not isSecret(aura) and aura.isHarmful
                if harmful ~= false then -- true, secret or unknown: worth noting
                    event("UNIT_AURA added " .. noteAura("UNIT_AURA added", aura))
                end
            end
        end
    end
    scan("aura")
end

local function onCombat(unit, action, flag, amount, school)
    if isSecret(unit) or unit ~= "player" then return end
    local values = { action = action, flag = flag, amount = amount, school = school }
    local parts = {}
    for _, field in ipairs(COMBAT_FIELDS) do
        count("UNIT_COMBAT", field, values[field])
        parts[#parts + 1] = field .. "=" .. show(values[field])
    end
    event("UNIT_COMBAT " .. table.concat(parts, " "))
end

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, ev, ...)
    if not store then return end
    local ok, err = pcall(ev == "UNIT_AURA" and onAura or onCombat, ...)
    if not ok then event("ERROR " .. tostring(err)) end
end)

local function listen(on)
    if on then
        frame:RegisterUnitEvent("UNIT_AURA", "player")
        frame:RegisterUnitEvent("UNIT_COMBAT", "player")
    else
        frame:UnregisterAllEvents()
    end
end

function SelfProbe.Load(db)
    db.selfProbe = db.selfProbe or {}
    store = db.selfProbe
    store.counts = store.counts or {}
    store.events = store.events or {}
    listen(store.on)
end

function SelfProbe.SetOn(on)
    if not store then return end
    store.on = on and true or nil
    listen(on)
    if on then scan("probe on") end
end

function SelfProbe.IsListening()
    return frame:IsEventRegistered("UNIT_AURA") and frame:IsEventRegistered("UNIT_COMBAT") and true or false
end

function SelfProbe.Clear()
    if not store then return end
    store.counts, store.events = {}, {}
end

-- For /sab self: per lookup and field, how often it was readable and secret; then the last few events.
function SelfProbe.Debug(n)
    local lines = {}
    if not store then return { "Self probe: not loaded" } end
    if not store.on then lines[1] = "Self probe: off (/sab self on to start it)" end
    local keys = {}
    for key in pairs(store.counts) do keys[#keys + 1] = key end
    table.sort(keys)
    if #keys == 0 and store.on then
        lines[#lines + 1] = "Self probe: nothing seen yet. Take a DoT (and a hit) in combat, then /sab self."
    end
    for _, key in ipairs(keys) do
        local parts = {}
        for field, c in pairs(store.counts[key]) do
            parts[#parts + 1] = string.format("%s %d/%d", field, c[1], c[2])
        end
        table.sort(parts)
        lines[#lines + 1] = key .. " (readable/secret): " .. table.concat(parts, ", ")
    end
    local events = store.events
    for i = math.max(1, #events - (n or 8) + 1), #events do lines[#lines + 1] = events[i] end
    return lines
end
