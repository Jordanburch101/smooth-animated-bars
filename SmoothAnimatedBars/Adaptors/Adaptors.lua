-- Adaptors: for unit frame addons that replace the game's bars with their own and do not hand them to us with
-- SmoothAnimatedBars.AddBar, a file here finds those bars and hands them over itself. agent.md in this folder says
-- when to write one and how; each adaptor is a file of its own, listed in the toc after this one.

local _, ns = ...

local Adaptors = { list = {} }
ns.Adaptors = Adaptors

Adaptors.LOOK_EVERY = 1 -- seconds: the other addon builds and rebuilds its bars on passes of its own

-- adaptor: { addons = its folder names (C_AddOns; any one loaded will do: an addon can come as a suite and as standalone
-- pieces), name = shown to players, Look = function(adaptor) }. Look finds the addon's bars and hands each over with
-- Adaptors.Hand; it runs at login and every LOOK_EVERY after, in combat too.
function Adaptors.Register(adaptor)
    Adaptors.list[#Adaptors.list + 1] = adaptor
end

-- A StatusBar under a key of a table (one of the other addon's fields), or nil. By its methods, as Bars.lua's IsBar:
-- the fields are the other addon's own and can be anything after its next release.
function Adaptors.Bar(t, key)
    local bar = type(t) == "table" and t[key]
    if type(bar) == "table" and bar.GetStatusBarTexture and bar.GetValue then return bar end
end

-- A table under a key, or nil.
function Adaptors.Table(t, key)
    local v = type(t) == "table" and t[key]
    return type(v) == "table" and v or nil
end

-- A unit token that can be used: a plain string, not secret, not empty.
function Adaptors.Unit(v)
    return type(v) == "string" and not (issecretvalue and issecretvalue(v)) and v ~= "" and v or nil
end

-- Hands one bar over, with the on/off setting, colour and effects of our frame it stands for (frame: "player",
-- "target", "focus", "pet", "tot" or "party"; Bars.AddBar's key) rather than the Other Addons' Bars setting: to the
-- player these are still their unit frames. options as AddBar's; theme "settings" gives it our colour settings.
-- An error is reported once per adaptor and the look carries on.
-- A bar the other addon handed over itself (it has taken up AddBar) is its own to look after, removed or not: taking
-- it back each look would undo its RemoveBar and swap its options for ours every second. A bar whose liquid failed is
-- left on its own fill: handing it over again each look would flicker it.
function Adaptors.Hand(adaptor, bar, unit, kind, frame, options)
    local by = ns.Bars.HandedBy(bar)
    if by == "addon" or by == "failed" then return end
    local key = frame .. (kind == "health" and "Health" or "Power")
    local ok, err = pcall(ns.Bars.AddBar, bar, unit, kind, options, key)
    if not ok and not adaptor.reported then
        adaptor.reported = true
        ns.Core.Print(adaptor.name .. "'s bars: " .. tostring(err))
    end
end

local function LookAll()
    if not ns.Core.ready then return end
    for _, adaptor in ipairs(Adaptors.list) do
        if adaptor.on then
            local ok, err = pcall(adaptor.Look, adaptor)
            if not ok and not adaptor.reported then
                adaptor.reported = true
                ns.Core.Print(adaptor.name .. "'s bars: " .. tostring(err))
            end
        end
    end
end
Adaptors.LookAll = LookAll

-- At PLAYER_ENTERING_WORLD (SmoothAnimatedBars.lua), after our bars are set up: the adaptors whose addon is loaded
-- look now and on a ticker; with none, nothing runs.
function Adaptors.Start()
    local any = false
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded
    for _, adaptor in ipairs(Adaptors.list) do
        adaptor.on = false
        for _, folder in ipairs(adaptor.addons) do
            if loaded and loaded(folder) then adaptor.on = true end
        end
        if adaptor.on then any = true end
    end
    if not any then return end
    LookAll()
    if not Adaptors.ticker then Adaptors.ticker = C_Timer.NewTicker(Adaptors.LOOK_EVERY, LookAll) end
end
