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
    -- Colours: "game" for the bar's own colour, or a theme key (Themes.lua)
    healthColor  = "game",
    powerColor   = "game",
    -- The other frames' bars: "same" (the pet's as the player's, the focus's and targets of target's as the
    -- target's), "game" or a theme key
    targetHealthColor = "same",
    targetPowerColor  = "same",
    petHealthColor    = "same",
    petPowerColor     = "same",
    focusHealthColor  = "same",
    focusPowerColor   = "same",
    totHealthColor    = "same",
    totPowerColor     = "same",
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
}
local FOLLOWS = { target = "player", pet = "player", focus = "target", tot = "target" }

-- The colour a frame's bar of this kind ("health" or "power") shows: "game" or a theme key, "same" followed through.
function Core.ColorChoice(frame, kind)
    local choice = Core.Get(COLOR_KEYS[frame][kind])
    if choice == "same" and FOLLOWS[frame] then return Core.ColorChoice(FOLLOWS[frame], kind) end
    return choice
end

-- Whether a bar of the target, the focus or a target of target shows Class Color: only then does what Class Color
-- shows on mobs matter.
function Core.TargetUsesClass()
    for _, frame in ipairs({ "target", "focus", "tot" }) do
        for _, kind in ipairs({ "health", "power" }) do
            if Core.Get(frame .. (kind == "health" and "Health" or "Power")) and Core.ColorChoice(frame, kind) == "class" then
                return true
            end
        end
    end
    return false
end

local BAR_KEYS = { "playerHealth", "playerPower", "targetHealth", "targetPower", "petHealth", "petPower", "focusHealth",
                   "focusPower", "totHealth", "totPower" }

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
}
for _, key in ipairs(BAR_KEYS) do SETTING_APPLY[key] = function() ApplyBars(true) end end
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
        ns.Options.Register(db, DEFAULTS)
        self:UnregisterEvent("ADDON_LOADED")

    elseif event == "PLAYER_ENTERING_WORLD" then
        local isLogin, isReload = arg1, arg2
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
    "/sab debug - what each bar is doing",
    "/sab dots - your DoTs on the target, and what the tracking saw lately",
    "/sab heals - your heals on the way to you, and what the tracking saw lately",
    "/sab mana - the wait before your mana regenerates, and what it saw lately",
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
        Core.Print(cmd == "on" and "Liquid in the unit frames' bars." or "The game's own bars again.")
    elseif cmd == "capture" then -- photographs the frame art for the gallery; see Capture.lua
        ns.Capture.Start()
    elseif cmd == "setup" then
        ns.Wizard.Open()
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
    else
        for _, line in ipairs(HELP) do Core.Print(line) end
    end
end
