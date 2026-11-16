-- Smooth Animated Bars: the liquid from Smooth Experience Bar in the game's own player and target
-- frame health and power bars. Settings are account-wide, in SmoothAnimatedBarsDB.

local ADDON_NAME, ns = ...

local Core = {}
ns.Core = Core

local DEFAULTS = {
    -- Bars
    playerHealth = true,
    playerPower  = true,
    targetHealth = true,
    targetPower  = true,
    -- The small frames' bars; "tot" is both targets of target, the target's and the focus's
    petHealth    = true,
    petPower     = true,
    focusHealth  = true,
    focusPower   = true,
    totHealth    = true,
    totPower     = true,
    -- The party frames' bars, all four members'
    partyHealth  = true,
    partyPower   = true,
    -- The Personal Resource Display's bars (the game shows them with its Personal Resource Display option on)
    prdHealth    = true,
    prdPower     = true,
    -- The raid frames' health, and the raid-style party frames' (Bars.lua, Bars.raid), off until it has been tried in a
    -- raid
    raidHealth   = false,
    raidPower    = false,
    -- Enemy nameplates' health (Bars.lua), off until it has been tried in a crowd
    plateHealth  = false,
    -- Friendly nameplates' health, the same way (outside instances: the game keeps those there to itself)
    plateFriendly = false,
    -- Bars other addons hand us with SmoothAnimatedBars.AddBar (unit frame addons that hide the game's frames)
    externalBars = true,
    -- The DoT marker on enemy nameplates (Marker.lua), with plateHealth
    plateDots    = false,
    -- The kill icon beside a nameplate whose mob the player's DoTs will finish, with plateDots
    plateKillIcon = true,
    -- Colours: "game" for the bar's own colour, or a theme key (Themes.lua)
    healthColor  = "game",
    powerColor   = "game",
    -- The other frames' bars: "same" (the pet's and the party's as the player's, the focus's and targets of target's as
    -- the target's), "game" or a theme key
    targetHealthColor = "same",
    targetPowerColor  = "same",
    petHealthColor    = "same",
    petPowerColor     = "same",
    focusHealthColor  = "same",
    focusPowerColor   = "same",
    totHealthColor    = "same",
    totPowerColor     = "same",
    partyHealthColor  = "same",
    partyPowerColor   = "same",
    prdHealthColor    = "same",
    prdPowerColor     = "same",
    -- The raid frames: the game's raid colour (class colours or the colour set in its Raid Frames options) by default
    raidHealthColor   = "game",
    raidPowerColor    = "same",
    plateHealthColor  = "same",
    -- Friendly nameplates: their own colour by default, or "same" for the enemy plates'
    plateFriendlyColor = "game",
    -- What Class Color gives a mob: "reaction", "game" (the bar's own colour), "class" (its own) or "own" (the player's)
    mobClassColor = "reaction",
    -- Effects, read live by the liquid
    waves     = true,
    swirl     = true,
    bubbles   = true,
    sparkles  = true,
    ambient   = true,
    lightning = true,
    -- The DoT marker on the target's health bar (Marker.lua), offered by the setup wizard
    dots        = false,
    dotKillIcon = true,
    -- The heal marker on the player's health bar (HealMarker.lua)
    heals       = true,
    -- The build-up on the mana bar through the wait before mana regenerates (ManaRule.lua)
    manaBuild   = true,
    -- The rage bar growing furious as it fills, and bursting when rage is spent (Bars.lua, Fury)
    rageFury    = true,
}

local db

function Core.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff40d060Smooth Animated Bars|r " .. msg)
end

function Core.Defaults()
    return DEFAULTS
end

function Core.Get(key)
    return db and db[key]
end

-- Each frame's colour settings, and whose its "same" follows.
local COLOR_KEYS = {
    player = { health = "healthColor", power = "powerColor" },
    target = { health = "targetHealthColor", power = "targetPowerColor" },
    pet    = { health = "petHealthColor", power = "petPowerColor" },
    focus  = { health = "focusHealthColor", power = "focusPowerColor" },
    tot    = { health = "totHealthColor", power = "totPowerColor" },
    party  = { health = "partyHealthColor", power = "partyPowerColor" },
    prd    = { health = "prdHealthColor", power = "prdPowerColor" },
    raid   = { health = "raidHealthColor", power = "raidPowerColor" },
    plate  = { health = "plateHealthColor" },
    friend = { health = "plateFriendlyColor" },
}
local FOLLOWS = { target = "player", pet = "player", focus = "target", tot = "target", party = "player", prd = "player",
                  raid = "party", plate = "target", friend = "plate" }

-- The colour a frame's bar of this kind ("health" or "power") shows: "game" or a theme key, "same" followed through.
function Core.ColorChoice(frame, kind)
    local choice = Core.Get(COLOR_KEYS[frame][kind])
    if choice == "same" and FOLLOWS[frame] then return Core.ColorChoice(FOLLOWS[frame], kind) end
    return choice
end

-- Whether a bar of the target, the focus or a target of target shows Class Color: only then does what Class Color
-- shows on mobs matter.
-- The on/off setting of a frame's bar of this kind: friendly nameplates have one setting of their own.
local function FrameOn(frame, kind)
    if frame == "friend" then return kind == "health" and Core.Get("plateFriendly") end
    return Core.Get(frame .. (kind == "health" and "Health" or "Power"))
end

local function UsesClass(frames)
    for _, frame in ipairs(frames) do
        for kind in pairs(COLOR_KEYS[frame]) do
            if FrameOn(frame, kind) and Core.ColorChoice(frame, kind) == "class" then return true end
        end
    end
    return false
end

function Core.TargetUsesClass()
    return UsesClass({ "target", "focus", "tot" })
end

-- The same for the enemy and friendly nameplates, whose mobs follow Class Color on Mobs too.
function Core.PlatesUseClass()
    return UsesClass({ "plate", "friend" })
end

local BAR_KEYS = { "playerHealth", "playerPower", "targetHealth", "targetPower", "petHealth", "petPower", "focusHealth",
                   "focusPower", "totHealth", "totPower", "partyHealth", "partyPower", "prdHealth", "prdPower" }

local function ApplyBars(verbose)
    local live, missing = ns.Bars.Apply()
    if missing > 0 and verbose then
        Core.Print("Could not find " .. missing .. " of the unit frame bars. /sab debug lists them.")
    end
    return live
end

local SETTING_APPLY = {
    healthColor = function() ns.Bars.ApplyColors() end,
    powerColor  = function() ns.Bars.ApplyColors() end,
    mobClassColor     = function() ns.Bars.ApplyColors() end,
    dots        = function() ns.Marker.Apply() end,
    dotKillIcon = function() ns.Marker.Apply() end,
    heals       = function() ns.HealMarker.Apply() end,
    manaBuild   = function() ns.ManaRule.Apply() end,
    plateHealth = function() ApplyBars(false); ns.Marker.Apply() end,
    plateDots   = function() ns.Marker.Apply() end,
    plateKillIcon = function() ns.Marker.Apply() end,
    plateFriendly = function() ApplyBars(false) end,
    raidHealth  = function() ApplyBars(false) end,
    raidPower   = function() ApplyBars(false) end,
    externalBars = function()
        ApplyBars(false)
        ns.HealMarker.Apply()
        Core.FireExternal("enabled", db.externalBars and true or false)
    end,
}
for _, key in ipairs(BAR_KEYS) do SETTING_APPLY[key] = function() ApplyBars(true) end end
-- The Personal Resource Display's heal markers are built once its bars have the liquid.
for _, key in ipairs({ "prdHealth", "prdPower" }) do
    SETTING_APPLY[key] = function() ApplyBars(true); ns.HealMarker.Apply() end
end
for frame, keys in pairs(COLOR_KEYS) do
    if frame ~= "player" then
        for _, key in pairs(keys) do SETTING_APPLY[key] = function() ns.Bars.ApplyColors() end end
    end
end
for _, key in ipairs({ "waves", "swirl", "bubbles", "sparkles", "ambient", "lightning" }) do
    SETTING_APPLY[key] = function()
        ns.Bars.ApplyOptions()
        ns.Marker.ApplyOptions()
        ns.HealMarker.ApplyOptions()
    end
end

function Core.OnSettingChanged(key)
    local apply = SETTING_APPLY[key]
    if apply then apply() end
end

-- Through the settings control where there is one, so the settings page follows.
function Core.SetSetting(key, value)
    if not (ns.Options.Set and ns.Options.Set(key, value)) then
        db[key] = value
        Core.OnSettingChanged(key)
    end
end

--------------------------------------------------------------------------------
-- For other addons
--------------------------------------------------------------------------------

-- The public entry point, a global table: a unit frame addon that hides the game's frames can hand us its own bars.
-- README.md, "For addon authors", is the contract; this is a summary.
--   SmoothAnimatedBars.AddBar(bar, unit, kind [, options]) -> true if taken, false if declined
--     bar: a horizontal StatusBar (its value may be secret); unit: "player", "target", "party1"...; kind: "health" or
--     "power". Calling it again with the same arguments does nothing; with a new unit the liquid follows it.
--     options: theme (nil keeps the bar's own colour; "settings" takes this addon's colour settings for that unit; or a
--     theme key, an unknown one meaning the bar's own colour), mask (a MaskTexture, taken the first time), level (whole
--     frame levels above the bar, 0 to 20, 1 by default), spill (true lets motes fly past the bar's edges), name (the
--     addon's name, for /sab perf and /sab debug). Bad arguments raise an error in the caller.
--     Declined: a vertical bar, one of this addon's own bars, a nameplate unit, or more than ten party and raid members'
--     bars at once.
--   SmoothAnimatedBars.RemoveBar(bar) -> true if it was added: the bar's own fill comes back.
--   SmoothAnimatedBars.HasBar(bar): added and not removed. IsLive(bar): its liquid is showing now.
--   SmoothAnimatedBars.IsEnabled(): whether the player allows other addons' bars (externalBars).
--   SmoothAnimatedBars.RegisterCallback(fn) / UnregisterCallback(fn): fn("enabled", on) when that setting changes.
--   SmoothAnimatedBars.GetThemes(): the theme keys options.theme takes.
-- A bar that fills from the right (SetReverseFill) is followed from its fill's left edge, and its colour, fill
-- direction, orientation and level are looked at again ten times a second. Calls made before this addon has loaded its
-- settings are kept and done once it has; a bar goes live once the player is in the world.
local API_VERSION = 1
local early = {}     -- bar -> its AddBar arguments, from calls made before the settings loaded
local failed = {}    -- bar -> true once an error adding it has been reported, until it is added again
local callbacks = {} -- functions to tell when the externalBars setting changes

local api = { apiVersion = API_VERSION }

function api.AddBar(bar, unit, kind, options)
    local bad = ns.Bars.CheckAddBar(bar, unit, kind, options)
    if bad then error(bad, 2) end
    if not db then
        if ns.Bars.Declined(bar, unit) then return false end
        early[bar] = { unit, kind, options }
        return true
    end
    local ok, taken = pcall(ns.Bars.AddBar, bar, unit, kind, options)
    if not ok then
        -- Whatever was set up is let go, so HasBar answers as AddBar did.
        pcall(ns.Bars.RemoveBar, bar)
        if not failed[bar] and not ns.Bars.Reported(bar) then
            failed[bar] = true
            ns.Bars.Reported(bar, true)
            Core.Print("Could not put the liquid on another addon's bar: " .. tostring(taken))
        end
        return false
    end
    if taken then failed[bar] = nil end
    return taken
end

function api.RemoveBar(bar)
    if early[bar] then
        early[bar] = nil
        return true
    end
    local ok, removed = pcall(ns.Bars.RemoveBar, bar)
    return ok and removed or false
end

function api.HasBar(bar)
    if early[bar] then return true end
    return ns.Bars.HasBar(bar)
end

function api.IsLive(bar)
    return ns.Bars.HasBar(bar) and ns.Bars.IsLive(bar) or false
end

function api.IsEnabled()
    return db ~= nil and db.externalBars and true or false
end

function api.GetThemes()
    local out = {}
    for i, key in ipairs(ns.Themes.order) do out[i] = key end
    return out
end

function api.RegisterCallback(fn)
    if type(fn) ~= "function" then error("SmoothAnimatedBars.RegisterCallback: fn must be a function", 2) end
    for _, f in ipairs(callbacks) do if f == fn then return end end
    callbacks[#callbacks + 1] = fn
end

function api.UnregisterCallback(fn)
    for i, f in ipairs(callbacks) do
        if f == fn then
            table.remove(callbacks, i)
            return
        end
    end
end

-- Each callback in turn; one that errors is reported and does not stop the others.
function Core.FireExternal(event, ...)
    for _, fn in ipairs(callbacks) do
        local ok, err = pcall(fn, event, ...)
        if not ok then Core.Print("An other addon's callback failed: " .. tostring(err)) end
    end
end

-- Read-only, so no addon can replace a function another relies on.
SmoothAnimatedBars = setmetatable({}, {
    __index = api,
    __newindex = function() error("SmoothAnimatedBars is read-only", 2) end,
    __metatable = false,
})

local function AddEarlyBars()
    for bar, args in pairs(early) do
        api.AddBar(bar, args[1], args[2], args[3])
    end
    wipe(early)
end

local events = CreateFrame("Frame")
local openAfterCombat = false
local openSection

-- The settings panel cannot be opened safely in combat, so wait for it to end. section: where to open it ("Pet"...).
function Core.OpenSettings(section)
    if InCombatLockdown() then
        openSection = section
        if not openAfterCombat then
            openAfterCombat = true
            events:RegisterEvent("PLAYER_REGEN_ENABLED")
            Core.Print("Settings will open after combat.")
        end
        return true
    end
    return ns.Options.Open(section)
end

events:SetScript("OnEvent", function(self, event, arg1, arg2)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        SmoothAnimatedBarsDB = SmoothAnimatedBarsDB or {}
        db = SmoothAnimatedBarsDB
        for k, v in pairs(DEFAULTS) do
            if db[k] == nil then db[k] = v end
        end
        if db.healthColor ~= "game" and not ns.Themes.list[db.healthColor] then db.healthColor = "game" end
        if db.powerColor ~= "game" and not ns.Themes.list[db.powerColor] then db.powerColor = "game" end
        for frame, keys in pairs(COLOR_KEYS) do
            if frame ~= "player" then
                for _, key in pairs(keys) do
                    if db[key] ~= "same" and db[key] ~= "game" and not ns.Themes.list[db[key]] then db[key] = "same" end
                end
            end
        end
        if db.mobClassColor ~= "game" and db.mobClassColor ~= "class" and db.mobClassColor ~= "own" then
            db.mobClassColor = "reaction"
        end
        Core.db = db
        ns.Dots.Load(db)
        ns.SelfProbe.Load(db)
        ns.Options.Register(db, DEFAULTS)
        self:UnregisterEvent("ADDON_LOADED")
        AddEarlyBars()

    elseif event == "PLAYER_ENTERING_WORLD" then
        local isLogin, isReload = arg1, arg2
        Core.ready = true -- other addons' bars go live from here on (Bars.AddBar)
        ApplyBars(true)
        ns.Bars.ApplyColors() -- class and faction themes know the player now
        ns.Marker.Apply()
        ns.HealMarker.Apply()
        ns.ManaRule.Apply()
        -- The setup wizard, once per account, a moment after the first login with the addon.
        if (isLogin or isReload) and not db.setupDone then C_Timer.After(2, ns.Wizard.OpenWhenReady) end

    elseif event == "PLAYER_REGEN_ENABLED" then
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        if openAfterCombat then
            openAfterCombat = false
            ns.Options.Open(openSection)
            openSection = nil
        end
    end
end)
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")

--------------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------------

local HELP = {
    "/sab - open settings",
    "/sab on | off - liquid in all the bars, or none",
    "/sab setup - open the setup wizard",
    "/sab changes - what's new in the latest versions",
    "/sab debug - what each bar is doing",
    "/sab dots - your DoTs on the target, and what the tracking saw lately",
    "/sab heals - your heals on the way to you, and what the tracking saw lately",
    "/sab mana - the wait before your mana regenerates, and what it saw lately",
    "/sab self on | off - note what the game lets the addon read about DoTs and hits on you, saved for /reload; "
        .. "/sab self shows it (self clear: start afresh)",
    "/sab perf [note] - what the liquid costs each frame, the unit frames (the display and party apart) and the "
        .. "nameplates, and the costliest bars, saved for "
        .. "tools/perf_report.py after /reload (perf reset: time afresh, perf clear: forget the saved ones)",
    "/sab party [note] - what the game lets the addon read about the party frames, saved for /reload "
        .. "(party clear: forget the saved ones)",
    "/sab raid [note] - the same for the raid-style frames (raid clear: forget the saved ones); /sab raid test "
        .. "[low | up | off] - a magenta block where their liquid would go, to see what the game draws over it",
}

-- /sab perf keeps each report in the saved variables, which the client writes to disk on /reload or logout (addons
-- cannot write files). tools/perf_report.py turns them into a text file.
local PERF_LOG_MAX = 50
local PERF_WORDS = { ["perf reset"] = true, ["perf clear"] = true }

local function Where()
    local ok, zone = pcall(GetRealZoneText)
    if not ok or type(zone) ~= "string" or (issecretvalue and issecretvalue(zone)) then zone = nil end
    local ok2, _, kind = pcall(GetInstanceInfo)
    if not ok2 or type(kind) ~= "string" or (issecretvalue and issecretvalue(kind)) then kind = nil end
    return zone, kind
end

local function SavePerf(note)
    local snap = ns.Bars.PerfSnapshot()
    if not snap then return false end
    snap.when = date and date("%Y-%m-%d %H:%M:%S") or nil
    snap.zone, snap.instance = Where()
    snap.combat = InCombatLockdown() and true or false
    snap.note = note
    snap.version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or nil
    db.perfLog = db.perfLog or {}
    table.insert(db.perfLog, snap)
    while #db.perfLog > PERF_LOG_MAX do table.remove(db.perfLog, 1) end
    return true
end

-- /sab party: the same, its lines kept for reading after /reload, while the party frames have no liquid yet.
local PARTY_LOG_MAX = 20

local function SaveParty(lines, note, key)
    key = key or "partyProbe"
    local snap = { lines = lines, note = note, combat = InCombatLockdown() and true or false }
    snap.when = date and date("%Y-%m-%d %H:%M:%S") or nil
    snap.zone, snap.instance = Where()
    snap.version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or nil
    db[key] = db[key] or {}
    table.insert(db[key], snap)
    while #db[key] > PARTY_LOG_MAX do table.remove(db[key], 1) end
end

local RAID_TEST = { ["raid test"] = "liquid", ["raid test low"] = "low", ["raid test up"] = "up", ["raid test off"] = "off" }
local RAID_TEST_SAYS = {
    liquid = "in the liquid's layer at the bar's level",
    low = "in the game fill's layer at the bar's level",
    up = "in the liquid's layer one level above the bar",
}

SLASH_SMOOTHANIMATEDBARS1 = "/sab"
SlashCmdList.SMOOTHANIMATEDBARS = function(input)
    local cmd = strlower(strtrim(input or ""))
    if cmd == "" or cmd == "config" or cmd == "options" then
        if not Core.OpenSettings() then
            for _, line in ipairs(HELP) do Core.Print(line) end
        end
    elseif cmd == "on" or cmd == "off" then
        for _, key in ipairs(BAR_KEYS) do Core.SetSetting(key, cmd == "on") end
        Core.SetSetting("externalBars", cmd == "on") -- other addons' bars too
        Core.Print(cmd == "on" and "Liquid in the unit frames' bars." or "The game's own bars again.")
    elseif cmd == "capture" then -- photographs the frame art for the gallery; see Capture.lua
        ns.Capture.Start()
    elseif cmd == "capture plates" then -- the same for a nameplate's art
        ns.Capture.Start("plates")
    elseif cmd == "capture party" then -- and a party member frame's
        ns.Capture.Start("party")
    elseif cmd == "setup" then
        ns.Wizard.Open()
    elseif cmd == "changes" then
        ns.WhatsNew.Open()
    elseif cmd == "debug" then
        for _, line in ipairs(ns.Bars.Debug()) do Core.Print(line) end
    elseif cmd == "dots" then
        for _, line in ipairs(ns.Marker.Debug()) do Core.Print(line) end
        for _, line in ipairs(ns.Dots.Debug(15)) do Core.Print(line) end
    elseif cmd == "heals" then
        for _, line in ipairs(ns.HealMarker.Debug()) do Core.Print(line) end
        for _, line in ipairs(ns.Heals.Debug(15)) do Core.Print(line) end
    elseif cmd == "mana" then
        for _, line in ipairs(ns.ManaRule.Debug(15)) do Core.Print(line) end
    elseif cmd == "self" then
        for _, line in ipairs(ns.SelfProbe.Debug(8)) do Core.Print(line) end
    elseif cmd == "self on" or cmd == "self off" then
        ns.SelfProbe.SetOn(cmd == "self on")
        Core.Print(cmd == "self on" and "Self probe on: take a DoT and some hits, then /sab self and /reload."
            or "Self probe off.")
    elseif cmd == "self clear" then
        ns.SelfProbe.Clear()
        Core.Print("Self probe cleared.")
    elseif cmd == "perf" or cmd:match("^perf ") and not PERF_WORDS[cmd] then
        for _, line in ipairs(ns.Bars.Perf()) do Core.Print(line) end
        local note = strtrim(input or ""):match("^%S+%s+(.+)$") -- /sab perf <note>: what was going on
        if SavePerf(note) then
            Core.Print("Saved (" .. #db.perfLog .. " in the log). /reload writes it to disk; then run "
                .. "tools/perf_report.py for a text file.")
        end
    elseif cmd == "party clear" then
        db.partyProbe = nil
        Core.Print("Saved party reports cleared.")
    elseif cmd == "party" or cmd:match("^party ") then
        local lines = ns.Bars.PartyDebug()
        for _, line in ipairs(lines) do Core.Print(line) end
        SaveParty(lines, strtrim(input or ""):match("^%S+%s+(.+)$"))
        Core.Print("Saved (" .. #db.partyProbe .. " in the log). /reload writes it to disk.")
    elseif RAID_TEST[cmd] then
        local mode = RAID_TEST[cmd]
        local n = ns.Bars.RaidTest(mode)
        if mode == "off" then
            Core.Print("Raid test blocks hidden.")
        else
            Core.Print(string.format("Magenta blocks on %d raid-style health bars, %s. Whatever shows over the magenta "
                .. "draws over the liquid there. /sab raid test off to hide them.", n, RAID_TEST_SAYS[mode]))
        end
    elseif cmd == "raid clear" then
        db.raidProbe = nil
        Core.Print("Saved raid reports cleared.")
    elseif cmd == "raid" or cmd:match("^raid ") then
        local full, brief = ns.Bars.RaidDebug()
        for _, line in ipairs(brief) do Core.Print(line) end
        SaveParty(full, strtrim(input or ""):match("^%S+%s+(.+)$"), "raidProbe")
        Core.Print("Saved the full report (" .. #db.raidProbe .. " in the log). /reload writes it to disk.")
    elseif cmd == "perf reset" then
        ns.Bars.PerfReset()
        Core.Print("Timing from now on. /sab perf in a few seconds.")
    elseif cmd == "perf clear" then
        db.perfLog = nil
        Core.Print("Saved timings cleared.")
    else
        for _, line in ipairs(HELP) do Core.Print(line) end
    end
end
