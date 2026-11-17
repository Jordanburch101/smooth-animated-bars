-- ClassicUI Forever (github.com/wowaddonmaker/classicuiforever, CurseForge 1700043): the 1.x art on the game's unit
-- frames. Read from 0.58.0, not copied (its licence is all rights reserved); agent.md has what was found there.
--
-- On the player, target, focus, both targets of target and the party members it fades the game's bars out (alpha 0, so
-- our liquid there pauses: Bars.lua, Sight) and fills StatusBars of its own, kept on the game's frames:
-- frame.fcui.host.fcui.health and .power (its UF.BuildBars, ns.CreateBar), and tot.fcui.totHealth and .totPower. They
-- hold the unit's own values (secret, through SetValue), plain rectangles under its art: no mask, the clip frame cuts
-- them, and at the bar's own level (level 0), with nothing on the bar but its fill, so its art and texts, on frames
-- above, stay over the liquid. The pet frame keeps the game's bars, moved, resized and with the game's mask taken off
-- their fill (its SkinPet; its art is then pet.fcui.petArt), so the liquid there drops that mask too (Bars.Unmask).
-- A piece turned off hides its bars and shows the game's again, and the liquid follows by itself.

local _, ns = ...
local A = ns.Adaptors

local OPTIONS = { theme = "settings", level = 0, name = "ClassicUI Forever" }
local FRAMES = { { "PlayerFrame", "player" }, { "TargetFrame", "target" }, { "FocusFrame", "focus" } }
local TOTS = { { "TargetFrameToT", "targettarget" }, { "FocusFrameToT", "focustarget" } }

-- Its bar of a kind on a frame it has skinned: frame.fcui.host.fcui[kind].
local function HostBar(frame, kind)
    return A.Bar(A.Table(A.Table(A.Table(frame, "fcui"), "host"), "fcui"), kind)
end

local function Look(self)
    for _, f in ipairs(FRAMES) do
        local frame = rawget(_G, f[1])
        for _, kind in ipairs({ "health", "power" }) do
            local bar = HostBar(frame, kind)
            if bar then A.Hand(self, bar, f[2], kind, f[2], OPTIONS) end
        end
    end
    for _, t in ipairs(TOTS) do
        local own = A.Table(rawget(_G, t[1]), "fcui")
        local health, power = A.Bar(own, "totHealth"), A.Bar(own, "totPower")
        if health then A.Hand(self, health, t[2], "health", "tot", OPTIONS) end
        if power then A.Hand(self, power, t[2], "power", "tot", OPTIONS) end
    end
    -- Party members: the game pools four buttons and moves them between places; each bar follows its button's unit.
    local party = rawget(_G, "PartyFrame")
    for i = 1, 4 do
        local frame = A.Table(party, "MemberFrame" .. i)
        local unit = frame and A.Unit(frame.unit)
        if unit then
            for _, kind in ipairs({ "health", "power" }) do
                local bar = HostBar(frame, kind)
                if bar then A.Hand(self, bar, unit, kind, "party", OPTIONS) end
            end
        end
    end
    if A.Table(A.Table(rawget(_G, "PetFrame"), "fcui"), "petArt") then
        for _, name in ipairs({ "PetFrameHealthBar", "PetFrameManaBar" }) do
            local bar = rawget(_G, name)
            if type(bar) == "table" then ns.Bars.Unmask(bar) end
        end
    end
end

-- The full addon, or its standalone piece with the unit frames (its tools/standalone.py: the same code, renamed).
A.Register({ addons = { "ClassicUIForever", "ClassicUIForeverStandaloneUnitFrames" }, name = "ClassicUI Forever",
             Look = Look })
