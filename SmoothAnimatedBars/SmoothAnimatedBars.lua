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
    -- Colours: "game" for the bar's own colour, or a theme key (Themes.lua)
    healthColor  = "game",
    powerColor   = "game",
    -- Effects, read live by the liquid
    waves     = true,
    swirl     = true,
    bubbles   = true,
    sparkles  = true,
    ambient   = true,
    lightning = true,
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

local BAR_KEYS = { "playerHealth", "playerPower", "targetHealth", "targetPower" }

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
}
for _, key in ipairs(BAR_KEYS) do SETTING_APPLY[key] = function() ApplyBars(true) end end
for _, key in ipairs({ "waves", "swirl", "bubbles", "sparkles", "ambient", "lightning" }) do
    SETTING_APPLY[key] = function() ns.Bars.ApplyOptions() end
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

-- The settings panel cannot be opened safely in combat, so wait for it to end.
function Core.OpenSettings()
    if InCombatLockdown() then
        if not openAfterCombat then
            openAfterCombat = true
            events:RegisterEvent("PLAYER_REGEN_ENABLED")
            Core.Print("Settings will open after combat.")
        end
        return true
    end
    return ns.Options.Open()
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
        Core.db = db
        ns.Options.Register(db, DEFAULTS)
        self:UnregisterEvent("ADDON_LOADED")

    elseif event == "PLAYER_ENTERING_WORLD" then
        local isLogin, isReload = arg1, arg2
        ApplyBars(true)
        ns.Bars.ApplyColors() -- class and faction themes know the player now
        -- The setup wizard, once per account, a moment after the first login with the addon.
        if (isLogin or isReload) and not db.setupDone then C_Timer.After(2, ns.Wizard.OpenWhenReady) end

    elseif event == "PLAYER_REGEN_ENABLED" then
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        if openAfterCombat then
            openAfterCombat = false
            ns.Options.Open()
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
    "/sab on | off - liquid in all four bars, or none",
    "/sab setup - open the setup wizard",
    "/sab debug - what each bar is doing",
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
        Core.Print(cmd == "on" and "Liquid in the player and target frames' bars." or "The game's own bars again.")
    elseif cmd == "setup" then
        ns.Wizard.Open()
    elseif cmd == "debug" then
        for _, line in ipairs(ns.Bars.Debug()) do Core.Print(line) end
    else
        for _, line in ipairs(HELP) do Core.Print(line) end
    end
end
