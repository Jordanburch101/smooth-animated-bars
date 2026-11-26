-- Smooth Animated Bars: the liquid from Smooth Experience Bar in the game's own player and target
-- frame health and power bars. Settings are account-wide, or a character's own for a character that asks for that
-- (Profiles below); both are in SmoothAnimatedBarsDB.

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
    -- Those bars in the colours picked here for the frame each stands for (Bars.lua, ChoiceFor), not the other addon's
    externalColors = false,
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
    raidPowerColor    = "game",
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
    -- How fast everything in the liquid moves, and how far its front's waves bulge and dip, in percent
    animationSpeed = 100,
    waveIntensity  = 100,
    -- At most this many updates a second for a liquid that is moving (Liquid.SetFrameRate): 60 by default (seen in game
    -- at 60: no difference to the eye, a fifth less cost in a fight at 100 fps); 150 is Unlimited, every frame
    animationFps   = 60,
    -- The DoT marker on the target's health bar (Marker.lua), offered by the setup wizard
    dots        = false,
    dotKillIcon = true,
    -- The heal marker on the player's health bar (HealMarker.lua)
    heals       = true,
    -- The shield on the player's health bar while an absorb is on them (Shield.lua)
    shield      = true,
    -- Weakened Soul on the player's health bar after a Power Word: Shield (Soul.lua)
    weakenedSoul = true,
    -- The build-up on the mana bar through the wait before mana regenerates (ManaRule.lua)
    manaBuild   = true,
    -- The rage bar growing furious as it fills, and bursting when rage is spent (Bars.lua, Fury)
    rageFury    = true,
    -- The unit frames' bar heights, the game's by default. Taller, a frame of ours is drawn in place
    -- of the game's (TallFrames.lua), the art laid out again from slices of the game's atlas (Preview.SetFrameTall).
    playerHealthHeight = 20,
    playerPowerHeight  = 10,
    targetHealthHeight = 20,
    targetPowerHeight  = 10,
    focusHealthHeight  = 20,
    focusPowerHeight   = 10,
    -- The pet's and the targets of target's (both targets of target share theirs), the game's 11 and 7.
    petHealthHeight    = 11,
    petPowerHeight     = 7,
    totHealthHeight    = 11,
    totPowerHeight     = 7,
    -- The party members', the game's 10 and 7.
    partyHealthHeight  = 10,
    partyPowerHeight   = 7,
}

-- db is the settings in use: this character's own profile, or the account-wide one (Profiles below). root is
-- SmoothAnimatedBarsDB itself, which also keeps what belongs to the account whichever profile is in use: the setup's
-- and the changelog's progress, the DoT tracking's data, /sab's saved reports and the captured plate art.
local db, root

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

-- A colour being tried in the editor (a tile under the mouse): { key = a colour setting, choice }, shown by every bar
-- that setting reaches, real and example, without being saved. nil when nothing is being tried.
local trial

function Core.Try(colorKey, choice)
    local was = trial
    if colorKey then trial = { key = colorKey, choice = choice } else trial = nil end
    -- Every bar is coloured again only when what is tried changed: leaving a tile, or showing a page, often tries nothing.
    if not was and not trial then return end
    if was and trial and was.key == trial.key and was.choice == trial.choice then return end
    ns.Bars.ApplyColors()
end

-- The colour a frame's bar of this kind ("health" or "power") shows: "game" or a theme key, "same" followed through.
function Core.ColorChoice(frame, kind)
    local key = COLOR_KEYS[frame][kind]
    local choice = (trial and trial.key == key) and trial.choice or Core.Get(key)
    if choice == "same" and FOLLOWS[frame] then return Core.ColorChoice(FOLLOWS[frame], kind) end
    return choice
end

-- What a frame's bar would show on "same": the colour of the bar it follows (the editor's swatch for it).
function Core.SameChoice(frame, kind)
    local follows = FOLLOWS[frame]
    return follows and Core.ColorChoice(follows, kind) or nil
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
    externalColors = function() ns.Bars.ApplyColors() end,
    mobClassColor     = function() ns.Bars.ApplyColors() end,
    dots        = function() ns.Marker.Apply() end,
    dotKillIcon = function() ns.Marker.Apply() end,
    heals       = function() ns.HealMarker.Apply() end,
    shield      = function() ns.Shield.Apply() end,
    weakenedSoul = function() ns.Soul.Apply() end,
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
-- The player's and target's bar heights: a frame of ours in place of the game's while they are not the game's.
for _, key in ipairs({ "playerHealthHeight", "playerPowerHeight", "targetHealthHeight", "targetPowerHeight",
                       "focusHealthHeight", "focusPowerHeight", "petHealthHeight", "petPowerHeight",
                       "totHealthHeight", "totPowerHeight", "partyHealthHeight", "partyPowerHeight" }) do
    SETTING_APPLY[key] = function() ns.TallFrames.Apply() end
end
-- The Personal Resource Display's heal markers are built once its bars have the liquid.
for _, key in ipairs({ "prdHealth", "prdPower" }) do
    SETTING_APPLY[key] = function() ApplyBars(true); ns.HealMarker.Apply() end
end
for frame, keys in pairs(COLOR_KEYS) do
    if frame ~= "player" then
        for _, key in pairs(keys) do SETTING_APPLY[key] = function() ns.Bars.ApplyColors() end end
    end
end
local EFFECTS = { "waves", "swirl", "bubbles", "sparkles", "ambient", "lightning" }
Core.EFFECTS = EFFECTS
-- The effects that are amounts, not on or off: percentages, with their slider's range.
local EFFECT_LEVELS = {
    { key = "animationSpeed", min = 25, max = 200 },
    { key = "waveIntensity", min = 0, max = 200 },
}
Core.EFFECT_LEVELS = EFFECT_LEVELS
local IS_EFFECT, LEVEL = {}, {}
local function ApplyEffects()
    ns.Liquid.SetFrameRate(db and db.animationFps)
    ns.Bars.ApplyOptions()
    ns.Marker.ApplyOptions()
    ns.HealMarker.ApplyOptions()
    ns.Shield.ApplyOptions()
end
for _, key in ipairs(EFFECTS) do
    IS_EFFECT[key] = true
    SETTING_APPLY[key] = ApplyEffects
end
for _, level in ipairs(EFFECT_LEVELS) do
    IS_EFFECT[level.key], LEVEL[level.key] = true, level
    SETTING_APPLY[level.key] = ApplyEffects
end
SETTING_APPLY.animationFps = function() ns.Liquid.SetFrameRate(db.animationFps) end

-- An effect level as a factor (1 at 100%), kept in its range: a saved value from an older or edited file never drives
-- the liquid out of it.
function Core.EffectLevel(barKey, key)
    local level = LEVEL[key]
    local v = tonumber(Core.Effect(barKey, key)) or DEFAULTS[key]
    return math.max(level.min, math.min(level.max, v)) / 100
end

-- Effects for one bar: each of a bar's (by its on/off setting's key, "playerHealth"...) can be set apart from the global
-- one, kept in the profile in use, effects[barKey][effect] = true or false. A nested table cannot be a registered
-- setting, so these are kept in the saved table directly and applied here. Its liquids (Bars.lua, EffectOptions) and its
-- markers' read them live.
function Core.Effect(barKey, effect)
    local own = barKey and db and db.effects and db.effects[barKey]
    if own and own[effect] ~= nil then return own[effect] end
    return db and db[effect]
end

-- A bar takes effects of its own, starting from what it shows now.
function Core.OwnEffects(barKey)
    local own = {}
    for _, effect in ipairs(EFFECTS) do own[effect] = Core.Effect(barKey, effect) and true or false end
    for _, level in ipairs(EFFECT_LEVELS) do own[level.key] = tonumber(Core.Effect(barKey, level.key)) end
    db.effects = db.effects or {}
    db.effects[barKey] = own
    ApplyEffects()
    if ns.Editor and ns.Editor.Refresh then ns.Editor.Refresh() end
end

-- Sets a bar's own value for an effect; nil follows the global one again.
function Core.SetEffect(barKey, effect, value)
    if not IS_EFFECT[effect] then return end
    db.effects = db.effects or {}
    local own = db.effects[barKey] or {}
    own[effect] = value
    db.effects[barKey] = next(own) and own or nil
    ApplyEffects()
    if ns.Editor and ns.Editor.Refresh then ns.Editor.Refresh() end
end

-- Every effect of a bar back to the global ones.
function Core.ClearEffects(barKey)
    if not (db.effects and db.effects[barKey]) then return end
    db.effects[barKey] = nil
    ApplyEffects()
    if ns.Editor and ns.Editor.Refresh then ns.Editor.Refresh() end
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
-- Profiles
--------------------------------------------------------------------------------

-- Every character uses the account-wide settings (root.global) unless it asks for its own (root.ownSettings[key] = true,
-- kept in root.profiles[key]). So by default nothing changes from earlier versions, whose settings were account-wide and
-- kept flat in SmoothAnimatedBarsDB: those become root.global. The setup runs once per account (root.setupDone), and
-- its choices reach every character sharing the account-wide settings. A character's own settings start as a copy of
-- the account-wide ones the first time it asks for them, and are kept if it goes back to sharing. A profile holds every
-- setting in DEFAULTS and the bars' own effects (effects). Characters are keyed "Name - Realm", or "First Last -
-- Ruleset" on Forever, as in Smooth Experience Bar.
local GLOBAL = "*global*" -- the account-wide settings, as a source to copy from
Core.GLOBAL = GLOBAL
local profileKey

-- Forever has no realms: names are unique across the region, and a character plays under a ruleset. GetRealmName
-- there gives a server name, so the ruleset names the character instead.
local function RulesetName()
    local active, rules = C_GameRules and C_GameRules.IsGameRuleActive, Enum and Enum.GameRule
    if not (active and rules) then return end
    local function on(rule) return rule ~= nil and active(rule) end
    if on(rules.HardcoreRuleset) then return "Hardcore" end
    local rp, pvp = on(rules.RPRuleset), on(rules.PvPRuleset)
    if rp and pvp then return "RP-PVP" end
    if rp then return "RP" end
    if pvp then return "PVP" end
    return "Normal"
end

-- A key a character without a surname was saved under: its one "Name - Realm" (or "Name - Ruleset") profile. Names are
-- unique across Forever's region, so a single match is this character's; none or several, nil. Second, whether there
-- is a "Name - " one, made while the realm read "" by versions before this one knew it for no answer.
local function KnownKey(name)
    local found
    local function look(t)
        for key in pairs(t) do
            if type(key) == "string" and key ~= found and key:sub(1, #name + 3) == name .. " - "
                and key:sub(#name + 4):match("%S") then
                if found then return false end
                found = key
            end
        end
        return true
    end
    local stray = root.profiles[name .. " - "] ~= nil or root.ownSettings[name .. " - "] ~= nil
    if not (look(root.profiles) and look(root.ownSettings)) then return nil, stray end
    return found, stray
end

local function CharacterKey()
    local name, surname = UnitName("player")
    name = type(name) == "string" and name or "Unknown"
    -- Since client build 71037 GetRealmName gives "": no answer, never a realm.
    local realm = GetRealmName()
    if type(realm) ~= "string" or not realm:match("%S") then realm = nil end
    if type(surname) ~= "string" or surname == "" then
        -- "Name - Realm" while the realm reads and it has a profile there; else the one it has (made while the realm
        -- did not read, kept if it reads again); else the realm's, or with none the ruleset's, as a surname's.
        local key = realm and name .. " - " .. realm
        if key and (root.profiles[key] ~= nil or root.ownSettings[key] ~= nil) then return key end
        local known, stray = KnownKey(name)
        if known then return known end
        key = key or name .. " - " .. (RulesetName() or "Unknown")
        if stray and root.profiles[key] == nil and root.ownSettings[key] == nil then
            -- Settings made under "Name - " move to the key it will have from now on.
            local old = name .. " - "
            root.profiles[key], root.profiles[old] = root.profiles[old], nil
            root.ownSettings[key], root.ownSettings[old] = root.ownSettings[old], nil
        end
        return key
    end
    realm = realm or "Unknown"
    local consts = Constants and Constants.CharacterNameSeparatorConsts
    local sep = consts and consts.CHARACTERNAME_SURNAME_SEPARATOR or " "
    return name .. sep .. surname .. " - " .. (RulesetName() or realm)
end

local function CopyValue(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = CopyValue(x) end
    return out
end

-- A profile's settings: every one in DEFAULTS and the bars' own effects.
local function CopySettings(from, to)
    to = to or {}
    for k in pairs(DEFAULTS) do to[k] = CopyValue(from[k]) end
    to.effects = CopyValue(from.effects)
    return to
end

-- Fills a profile's gaps with the defaults and drops what this version does not know (a theme from a later version,
-- an effect that is gone), so any profile can be put in use.
local function Clean(p)
    for k, v in pairs(DEFAULTS) do
        if p[k] == nil or type(p[k]) ~= type(v) then p[k] = v end
    end
    if p.healthColor ~= "game" and not ns.Themes.list[p.healthColor] then p.healthColor = "game" end
    if p.powerColor ~= "game" and not ns.Themes.list[p.powerColor] then p.powerColor = "game" end
    for frame, keys in pairs(COLOR_KEYS) do
        if frame ~= "player" then
            for _, key in pairs(keys) do
                -- An unknown choice (a theme from a later version) goes back to the bar's own default.
                if p[key] ~= "same" and p[key] ~= "game" and not ns.Themes.list[p[key]] then
                    p[key] = DEFAULTS[key] or "same"
                end
            end
        end
    end
    if p.mobClassColor ~= "game" and p.mobClassColor ~= "class" and p.mobClassColor ~= "own" then
        p.mobClassColor = "reaction"
    end
    -- Bars' own effects: only known effects, true or false, the levels a number in their range, and only bars with
    -- any. (A review found the levels dropped here at every login and profile change, as they are not true or false.)
    if type(p.effects) ~= "table" then p.effects = {} end
    for bar, own in pairs(p.effects) do
        if type(bar) ~= "string" or type(own) ~= "table" then
            p.effects[bar] = nil
        else
            for k, v in pairs(own) do
                local level = LEVEL[k]
                if level then
                    own[k] = type(v) == "number" and v == v and math.max(level.min, math.min(level.max, v)) or nil
                elseif not IS_EFFECT[k] or type(v) ~= "boolean" then
                    own[k] = nil
                end
            end
            if not next(own) then p.effects[bar] = nil end
        end
    end
    return p
end

-- Settings come from the flat, account-wide table of earlier versions: they become the account-wide profile. Flat
-- settings found beside the profiles (an earlier version run again after this one) are dropped: which profile they
-- were meant for cannot be told.
local function Migrate()
    if type(root.global) == "table" then
        for k in pairs(DEFAULTS) do root[k] = nil end
        root.effects = nil
        return
    end
    local global = {}
    for k in pairs(DEFAULTS) do
        global[k] = root[k]
        root[k] = nil
    end
    global.effects = root.effects
    root.effects = nil
    root.global = global
end

-- After the settings in use changed all at once (how: "use", a profile put in use, made from the profile from if it is
-- new; or "copy", one copied over): everything they drive is applied again, as at login, and the editor and the setup
-- follow.
local function ApplyAll(wasExternal, how, from)
    if Core.ready then
        ApplyBars(true)
        ns.Bars.ApplyColors()
        ns.Marker.Apply()
        ns.HealMarker.Apply()
        ns.Shield.Apply()
        ns.Soul.Apply()
        ns.ManaRule.Apply()
        ApplyEffects()
    end
    local external = db.externalBars and true or false
    if wasExternal ~= nil and wasExternal ~= external then Core.FireExternal("enabled", external) end
    -- The setup's Skip knows what to put back (Wizard.ProfileChanged).
    if ns.Wizard and ns.Wizard.ProfileChanged then ns.Wizard.ProfileChanged(how, db, from) end
    if ns.Editor and ns.Editor.Refresh then ns.Editor.Refresh() end
end

-- Puts a profile in use; from: the profile it was just made from, if it is new.
local function Use(p, from)
    local wasExternal = db and (db.externalBars and true or false)
    db = Clean(p)
    Core.db = db
    if wasExternal ~= nil then
        Core.Try(nil)
        ApplyAll(wasExternal, "use", from)
    end
end

-- This character's key, as profiles are listed.
function Core.ProfileKey()
    return profileKey
end

-- Whether this character uses the account-wide settings: unless it asked for its own.
function Core.UsesGlobal()
    return root ~= nil and root.ownSettings[profileKey] ~= true
end

-- This character takes the account-wide settings, or its own again: the ones it had before, or a copy of the
-- account-wide ones if it never had its own.
function Core.SetUseGlobal(on)
    on = on and true or false
    if not root or Core.UsesGlobal() == on then return end
    root.ownSettings[profileKey] = (not on) or nil
    if on then
        Use(root.global)
    else
        local from
        if type(root.profiles[profileKey]) ~= "table" then
            root.profiles[profileKey], from = CopySettings(root.global), root.global
        end
        Use(root.profiles[profileKey], from)
    end
end

-- What can be copied onto the settings in use: the account-wide settings and other characters' own, sorted, each
-- { key, label }. A character sharing the account-wide settings has none of its own to offer. This character's own are
-- never offered: while it shares, unticking Use Account-Wide Settings brings them back, so copying them would only be
-- a second way to the same place.
function Core.CopySources()
    local out = {}
    if root.global ~= db then out[1] = { key = GLOBAL, label = "Account-Wide Settings" } end
    local keys = {}
    for key, p in pairs(root.profiles) do
        -- Only real profiles: a saved table edited by hand could hold anything.
        if type(key) == "string" and type(p) == "table" and p ~= db and key ~= profileKey
            and root.ownSettings[key] == true then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys)
    for _, key in ipairs(keys) do
        out[#out + 1] = { key = key, label = key }
    end
    return out
end

-- Replaces the settings in use with a copy of another profile's (a character's key, or GLOBAL). False if there is
-- no such profile.
function Core.CopyProfile(from)
    local src = from == GLOBAL and root.global or root.profiles[from]
    if type(src) ~= "table" or src == db then return false end
    local wasExternal = db.externalBars and true or false
    Core.Try(nil)
    CopySettings(src, db)
    Clean(db)
    ApplyAll(wasExternal, "copy")
    return true
end

-- At login: the saved table set up, and the settings this character uses put in use.
local function LoadProfiles()
    SmoothAnimatedBarsDB = type(SmoothAnimatedBarsDB) == "table" and SmoothAnimatedBarsDB or {}
    root = SmoothAnimatedBarsDB
    Migrate()
    if type(root.profiles) ~= "table" then root.profiles = {} end
    if type(root.ownSettings) ~= "table" then root.ownSettings = {} end
    profileKey = CharacterKey()
    Clean(root.global)
    Core.account = root
    if Core.UsesGlobal() then
        Use(root.global)
    else
        -- Its own, made again from the account-wide ones if the saved table lost them.
        if type(root.profiles[profileKey]) ~= "table" then root.profiles[profileKey] = CopySettings(root.global) end
        Use(root.profiles[profileKey])
    end
end

-- The settings in use, for the game's registered settings (Options.lua): they are bound to one table for good, so
-- they are given this one, which reads and writes whichever profile is in use.
local settingsView = setmetatable({}, {
    __index = function(_, k) return db[k] end,
    __newindex = function(_, k, v) db[k] = v end,
})

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
--     Declined: a vertical bar, one of this addon's own bars, a nameplate unit, a bar inside one of the game's aura
--     buttons (forbidden once an aura is assigned), or more than ten party and raid members' bars at once.
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

-- The editor (Editor.lua), at a section ("pet", "party"...) if one is given. It is a window of ours, so unlike the
-- game's settings panel it opens in combat too.
function Core.OpenEditor(section)
    return ns.Editor.Open(section)
end

events:SetScript("OnEvent", function(self, event, arg1, arg2)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        LoadProfiles()
        ns.Dots.Load(root)
        ns.SelfProbe.Load(root)
        ns.Options.Register(settingsView, DEFAULTS)
        self:UnregisterEvent("ADDON_LOADED")
        AddEarlyBars()

    elseif event == "PLAYER_ENTERING_WORLD" then
        local isLogin, isReload = arg1, arg2
        Core.ready = true -- other addons' bars go live from here on (Bars.AddBar)
        ns.Liquid.SetFrameRate(db.animationFps)
        ApplyBars(true)
        ns.Bars.ApplyColors() -- class and faction themes know the player now
        ns.Marker.Apply()
        ns.HealMarker.Apply()
        ns.Shield.Apply()
        ns.Soul.Apply()
        ns.ManaRule.Apply()
        ns.Adaptors.Start() -- other unit frame addons' own bars, for those that do not hand them over (Adaptors/)
        ns.TallFrames.Start() -- taller player and target bars, on a frame of ours (TallFrames.lua)
        -- The settings page's preview, once the bars are set up and before the settings panel can be open.
        ns.Options.BuildPreview()
        -- The setup wizard, once per account, a moment after the first login with the addon.
        if (isLogin or isReload) and not root.setupDone then C_Timer.After(2, ns.Wizard.OpenWhenReady) end
    end
end)
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")

--------------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------------

local HELP = {
    "/sab - open the editor: every setting beside a live preview",
    "/sab off - the game's own bars everywhere; /sab on - the liquid back in your frames (raid frames and nameplates stay as they are)",
    "/sab setup - open the setup wizard",
    "/sab changes - what's new in the latest versions",
    "/sab debug - what each bar is doing",
    "/sab dots - your DoTs on the target, and what the tracking saw lately",
    "/sab heals - your heals on the way to you, and what the tracking saw lately",
    "/sab shield - what the game lets the addon read about shields on you, and what the shield is doing; "
        .. "/sab shield test [off] - magenta blocks where the shield draws, to see what the game lays out",
    "/sab soul - what Weakened Soul saw and is doing; /sab soul test - 15 seconds of it on your health bar",
    "/sab mana - the wait before your mana regenerates, and what it saw lately",
    "/sab self on | off - note what the game lets the addon read about DoTs and hits on you, saved for /reload; "
        .. "/sab self shows it (self clear: start afresh)",
    "/sab perf [note] - what the liquid costs each frame, the unit frames (the display and party apart) and the "
        .. "nameplates, and the costliest bars, saved for "
        .. "tools/perf_report.py after /reload (perf reset: time afresh, perf clear: forget the saved ones)",
    "/sab party [note] - what the game lets the addon read about the party frames, saved for /reload "
        .. "(party clear: forget the saved ones)",
    "/sab tall [health] [power] - a test: the player and target frames at other bar heights (the game's are 20 and 10; "
        .. "34 and 14 by default), drawn from slices of the game's frame art; /sab tall off to close",
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
    root.perfLog = root.perfLog or {}
    table.insert(root.perfLog, snap)
    while #root.perfLog > PERF_LOG_MAX do table.remove(root.perfLog, 1) end
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
    root[key] = root[key] or {}
    table.insert(root[key], snap)
    while #root[key] > PARTY_LOG_MAX do table.remove(root[key], 1) end
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
    if cmd == "" or cmd == "config" or cmd == "options" or cmd == "editor" then
        Core.OpenEditor()
    elseif cmd == "on" or cmd == "off" then
        for _, key in ipairs(BAR_KEYS) do Core.SetSetting(key, cmd == "on") end
        Core.SetSetting("externalBars", cmd == "on") -- other addons' bars too
        -- Off is every bar; on leaves the ones that start off (raid frames, nameplates) as they were.
        if cmd == "off" then
            for _, key in ipairs({ "raidHealth", "raidPower", "plateHealth", "plateFriendly" }) do
                Core.SetSetting(key, false)
            end
        end
        Core.Print(cmd == "on" and "Liquid in the unit frames' bars." or "The game's own bars again.")
    elseif cmd == "capture" then -- photographs the frame art for the gallery; see Capture.lua
        ns.Capture.Start()
    elseif cmd == "capture plates" then -- the same for a nameplate's art
        ns.Capture.Start("plates")
    elseif cmd == "capture party" then -- and a party member frame's
        ns.Capture.Start("party")
    elseif cmd == "capture raid" then -- and a raid-style frame's
        ns.Capture.Start("raid")
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
    elseif cmd == "shield" then
        for _, line in ipairs(ns.Shield.Debug()) do Core.Print(line) end
    elseif cmd == "shield test" or cmd == "shield test off" then
        Core.Print(ns.Shield.Test(cmd == "shield test"))
    elseif cmd == "soul" then
        for _, line in ipairs(ns.Soul.Debug()) do Core.Print(line) end
    elseif cmd == "soul test" then
        Core.Print(ns.Soul.Test())
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
            Core.Print("Saved (" .. #root.perfLog .. " in the log). /reload writes it to disk; then run "
                .. "tools/perf_report.py for a text file.")
        end
    elseif cmd == "party clear" then
        root.partyProbe = nil
        Core.Print("Saved party reports cleared.")
    elseif cmd == "party" or cmd:match("^party ") then
        local lines = ns.Bars.PartyDebug()
        for _, line in ipairs(lines) do Core.Print(line) end
        SaveParty(lines, strtrim(input or ""):match("^%S+%s+(.+)$"))
        Core.Print("Saved (" .. #root.partyProbe .. " in the log). /reload writes it to disk.")
    elseif RAID_TEST[cmd] then
        local mode = RAID_TEST[cmd]
        local n = ns.Bars.RaidTest(mode)
        if mode == "off" then
            Core.Print("Raid test blocks hidden.")
        else
            Core.Print(string.format("Magenta blocks on %d raid-style health bars, %s. Whatever shows over the magenta "
                .. "draws over the liquid there. /sab raid test off to hide them.", n, RAID_TEST_SAYS[mode]))
        end
    elseif cmd == "tall" or cmd:match("^tall ") then
        local health, power = cmd:match("^tall%s+(%d+)%s*(%d*)$")
        if cmd == "tall off" then
            health = nil
        elseif cmd == "tall" then
            health, power = 34, 14
        elseif not health then
            Core.Print("/sab tall [health] [power]: bar heights, e.g. /sab tall 34 14; /sab tall off to close.")
            return
        end
        if health then
            health = math.min(60, math.max(20, tonumber(health)))
            power = math.min(40, math.max(10, tonumber(power) or 10))
        end
        for _, line in ipairs(ns.Preview.TallTest(health, power)) do Core.Print(line) end
    elseif cmd == "raid clear" then
        root.raidProbe = nil
        Core.Print("Saved raid reports cleared.")
    elseif cmd == "raid" or cmd:match("^raid ") then
        local full, brief = ns.Bars.RaidDebug()
        for _, line in ipairs(brief) do Core.Print(line) end
        SaveParty(full, strtrim(input or ""):match("^%S+%s+(.+)$"), "raidProbe")
        Core.Print("Saved the full report (" .. #root.raidProbe .. " in the log). /reload writes it to disk.")
    elseif cmd == "perf reset" then
        ns.Bars.PerfReset()
        Core.Print("Timing from now on. /sab perf in a few seconds.")
    elseif cmd == "perf clear" then
        root.perfLog = nil
        Core.Print("Saved timings cleared.")
    else
        for _, line in ipairs(HELP) do Core.Print(line) end
    end
end
