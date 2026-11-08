-- The wait before mana regenerates: after a spell that spends mana, regeneration from Spirit stops for five seconds.
-- Mana itself is secret, so the wait is timed from the player's casts: a cast that succeeds and costs mana starts
-- it again. Its cost is read as the cast is sent, as a free cast (Clearcasting) uses its buff up by the time it
-- succeeds. Bars.lua draws the build-up on the mana bar.

local _, ns = ...

local ManaRule = {}
ns.ManaRule = ManaRule

local WAIT = 5        -- seconds
local TRACE_LINES = 40

local enabled = false
local startedAt       -- when the wait began, nil when there is none
local sentGUID, sentCost
local lines = {}

local function trace(msg)
    lines[#lines + 1] = string.format("%.1f %s", GetTime(), msg)
    if #lines > TRACE_LINES then table.remove(lines, 1) end
end

local function isSecret(v)
    return issecretvalue and issecretvalue(v)
end

local function spellName(spellID)
    return C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID) or tostring(spellID)
end

-- What a spell costs in mana right now: a number, 0 if nothing, or "secret" if the client will not say (which counts
-- as a spend: a wait shown wrongly is better than none at all).
local function manaCost(spellID)
    local read = C_Spell and C_Spell.GetSpellPowerCost
    local costs = read and read(spellID)
    if type(costs) ~= "table" then return 0 end
    for _, c in ipairs(costs) do
        if isSecret(c.name) or isSecret(c.type) then return "secret" end
        if c.name == "MANA" or c.type == 0 then
            if isSecret(c.cost) then return "secret" end
            return c.cost or 0
        end
    end
    return 0
end

local function bar()
    return ns.Bars.Find("playerPower")
end

local frame = CreateFrame("Frame")

local function stop()
    startedAt = nil
    frame:SetScript("OnUpdate", nil)
    local b = bar()
    if b then ns.Bars.Wait(b, nil) end
end

local function onUpdate()
    local progress = (GetTime() - startedAt) / WAIT
    local b = bar()
    if progress >= 1 then
        trace("REGEN starts")
        startedAt = nil
        frame:SetScript("OnUpdate", nil)
        if b then ns.Bars.WaitOver(b) end
    elseif b then
        ns.Bars.Wait(b, progress)
    end
end

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "UNIT_SPELLCAST_SENT" then
        local _, _, castGUID, spellID = ...
        sentGUID, sentCost = castGUID, manaCost(spellID)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local _, castGUID, spellID = ...
        local cost
        if castGUID == sentGUID then cost = sentCost else cost = manaCost(spellID) end
        if cost == "secret" or cost > 0 then
            trace("SPEND " .. spellName(spellID) .. " cost " .. tostring(cost))
            startedAt = GetTime()
            frame:SetScript("OnUpdate", onUpdate)
        else
            trace("FREE " .. spellName(spellID))
        end
    elseif event == "PLAYER_DEAD" then
        stop()
    end
end)

-- After the setting changes, and at login.
function ManaRule.Apply()
    enabled = ns.Core.Get("manaBuild") and true or false
    frame:UnregisterAllEvents()
    stop()
    if enabled then
        frame:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
        frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        frame:RegisterEvent("PLAYER_DEAD")
    end
end

-- For the tests: the seconds left of the wait, or nil.
function ManaRule.Left()
    return startedAt and WAIT - (GetTime() - startedAt) or nil
end

function ManaRule.Debug(n)
    local out = { "mana build-up: " .. (enabled and "on" or "off") .. (startedAt
        and string.format(", %.1f s left", WAIT - (GetTime() - startedAt)) or ", not waiting") }
    for i = math.max(1, #lines - (n or TRACE_LINES) + 1), #lines do out[#out + 1] = lines[i] end
    return out
end
