-- Other client languages for the DoT tracking. Dots.lua reads English spell descriptions and looks spells up by
-- their English names; each language file (Locale_deDE.lua, ...) loads after this one and before Dots.lua and calls
--
--     ns.locale.register({
--         tag = "deDE",
--         parseDot = function(desc, comboPoints) ... end,   -- same returns as parseDot in Dots.lua
--         isFinisher = function(desc) ... end,              -- a combo point finisher ("Finishing move")
--         comboPointsAwarded = function(desc) ... end,      -- N from "Awards N combo point", or nil
--         names = { ["Rip"] = { "Zerfetzen" }, ... },       -- English name -> names in this language
--     })
--
-- The English patterns always run first. Descriptions they don't read go to every registered language in
-- registration order, whatever GetLocale() says: one language's patterns can't match another's text, and DoesItDie
-- found that on WoW: Forever GetLocale() can answer enUS while the spell text is German.
--
-- Ported from DoesItDie 0.9.3 by Joe Greive (its Locale.lua and Locale_*.lua, without the options window's
-- translations). None of the languages has been tried on a client of that language here.
--
-- MIT License
--
-- Copyright (c) 2026 Joe Greive
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
-- documentation files (the "Software"), to deal in the Software without restriction, including without
-- limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the
-- Software, and to permit persons to whom the Software is furnished to do so, subject to the following
-- conditions:
--
-- The above copyright notice and this permission notice shall be included in all copies or substantial portions
-- of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED
-- TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
-- THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
-- CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
-- DEALINGS IN THE SOFTWARE.

local _, ns = ...

local L = { languages = {} }
ns.locale = L

-- Every field but tag is optional.
function L.register(language)
    assert(type(language) == "table" and type(language.tag) == "string", "Smooth Animated Bars: a language needs a tag")
    table.insert(L.languages, language)
end

-- Gives every registered language's names the entry their English name has, in each table that has one.
function L.addNames(tables)
    for _, language in ipairs(L.languages) do
        for englishName, aliases in pairs(language.names or {}) do
            for _, alias in ipairs(aliases) do
                if type(alias) == "string" and alias ~= "" and alias ~= englishName then
                    for _, tbl in ipairs(tables) do
                        if tbl[englishName] ~= nil and tbl[alias] == nil then tbl[alias] = tbl[englishName] end
                    end
                end
            end
        end
    end
end

-- A language's reader may trip over text it was not written for; that only means it did not read it.
local function ask(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, a, b, c, d = pcall(fn, ...)
    if ok then return a, b, c, d end
end

-- Each reading kept by its text: every language's readers run in the same order whatever the client's language, so the
-- same text always reads the same, and a cast's text was read again at every cast (about 3500 instructions a cast through
-- the languages' patterns, by tools/harness/events.py). A secret text is never a key: read each time. The store starts
-- over past READINGS_MAX texts (a spell's text changes with its rank and the player's power, not much more).
local READINGS_MAX = 300
local readings, readingsCount = {}, 0

local function Kept(kind, desc)
    if type(desc) ~= "string" or (issecretvalue and issecretvalue(desc)) then return nil end
    local byText = readings[kind]
    return byText and byText[desc]
end

-- A reading kept with how many values it had, so a kept one gives back exactly what reading gave (none, where nothing
-- read the text): Again.
local function Keep(kind, desc, ...)
    if type(desc) ~= "string" or (issecretvalue and issecretvalue(desc)) then return ... end
    if readingsCount >= READINGS_MAX then readings, readingsCount = {}, 0 end
    local byText = readings[kind]
    if not byText then
        byText = {}
        readings[kind] = byText
    end
    byText[desc] = { n = select("#", ...), ... }
    readingsCount = readingsCount + 1
    return ...
end

local function Again(r)
    return unpack(r, 1, r.n)
end

-- The first registered language that reads `desc` as a DoT: total damage, school mask, duration, stated tick
-- interval (the returns of parseDot in Dots.lua).
local function ParseDot(desc, comboPoints)
    for _, language in ipairs(L.languages) do
        local total, school, duration, interval = ask(language.parseDot, desc, comboPoints)
        if type(total) == "number" and type(duration) == "number" then return total, school, duration, interval end
    end
end

function L.parseDot(desc, comboPoints)
    local kind = "dot" .. tostring(comboPoints)
    local r = Kept(kind, desc)
    if r then return Again(r) end
    return Keep(kind, desc, ParseDot(desc, comboPoints))
end

function L.isFinisher(desc)
    local r = Kept("finisher", desc)
    if r then return Again(r) end
    for _, language in ipairs(L.languages) do
        if ask(language.isFinisher, desc) then return (Keep("finisher", desc, true)) end
    end
    return (Keep("finisher", desc, false))
end

function L.comboPointsAwarded(desc)
    local r = Kept("combo", desc)
    if r then return Again(r) end
    for _, language in ipairs(L.languages) do
        local points = ask(language.comboPointsAwarded, desc)
        if type(points) == "number" then return (Keep("combo", desc, points)) end
    end
    return Keep("combo", desc)
end

--------------------------------------------------------------------------------
-- Heals, food and drink (Heals.lua). This part is the addon's own, not DoesItDie's: each language file hands
-- L.healReader its wording and registers the readers it builds as parseHeal and parseRest (the returns of Heals.lua's
-- own). Checked against Forever's tooltips for its heals, bandages, food and drink in every language (Wowhead,
-- dataEnv=16); the cases are in tools/harness/heal_language_cases.json.
--------------------------------------------------------------------------------

local function first(desc, patterns)
    for _, p in ipairs(patterns or {}) do
        local a, b = desc:match(p)
        if a then return a, b end
    end
end

local function number(s)
    return s and tonumber((s:gsub(",", "."))) or nil
end

-- Thousands separators joined: "1.177" (de, es, pt), "1 177" (fr, ru; their non-breaking spaces are plain by now).
-- The comma ("1,177": en, ko, zh) is Heals.lua's `plain`, run before any language's reader. A decimal never has three
-- digits after its point in Forever's text ("1,5 Sek."), so a group of exactly three is taken for thousands. A review
-- found these readers took "Heilt ... um 1.177 bis 1.309." for 177 (the separator text Wowhead's cases leave out).
-- Repeated until none is left, as one pass joins only every other group of "1.234.567".
local function joinThousands(desc)
    local n
    repeat
        desc, n = desc:gsub("([0-9])[%. ]([0-9][0-9][0-9])%f[^0-9]", "%1%2")
    until n == 0
    return desc
end
L.joinThousands = joinThousands

-- spec: the language's wording, every pattern matched against the description as it is (digits as [0-9] next to
-- multibyte text, as the DoT patterns spell them):
--   heal   = patterns, any of which marks a heal, anchored at the text's start as the English reader's are ("^Cura",
--            "^Rend [0-9]"): spells that cost, drain or convert health name it further in ("Vous rend 30% de vos points
--            de vie", Last Stand; "perd 147 points de vie en 21 sec", Rend), and read anywhere they were taken for
--            heals over time on the caster (a review found Bloodrage, Rend, Devouring Plague and Lightwell so);
--   range  = a pattern capturing a direct heal's lowest and highest roll ("(%d+) al (%d+)");
--   over   = patterns capturing, for a heal over time, the position where its duration stands, the seconds, and the
--            position after them ("()durante (%d+%.?%d*) s()");
--   after  = true where the amount comes after the duration ("Heilt das Ziel 15 Sek. lang um 830"), else it is the
--            last number before it ("Rend 830 points de vie à la cible en 15 sec.");
--   skip   = patterns marking text that is no heal for one target, though it reads like one: a channel healing the
--            party "every 2 sec" (Tranquility, whose tick length a reader would take for the amount);
--   rest   = patterns marking food or drink (the line about staying seated); such text is never a heal;
--   health, mana = patterns capturing what food and drink restore, read only before the buff's text begins (extra:
--            patterns marking it, "Also restores 8 Mana every 5 seconds"); restOver = patterns capturing their
--            seconds; fed = patterns capturing how many seconds of eating bring a buff.
function L.healReader(spec)
    local function parseHeal(desc)
        desc = joinThousands((desc:gsub("^ +", "")))
        if first(desc, spec.rest) or first(desc, spec.skip) or not first(desc, spec.heal) then return nil end
        local direct = number((desc:match(spec.range))) or 0
        local over, duration
        for _, p in ipairs(spec.over) do
            local at, secs, after = desc:match(p)
            if at then
                duration = number(secs)
                if spec.after then
                    over = number(desc:sub(after):match("([0-9]+)"))
                else
                    local last
                    for n in desc:sub(1, at - 1):gmatch("([0-9]+)") do last = n end
                    over = number(last)
                end
                break
            end
        end
        if not (over and duration and duration > 0) then over, duration = nil, nil end
        if not over and direct <= 0 then return nil end
        return over, duration, direct
    end
    local function parseRest(desc)
        desc = joinThousands(desc)
        if not first(desc, spec.rest) then return nil end
        local duration = number((first(desc, spec.restOver)))
        if not duration or duration <= 0 then return nil end
        local restores = desc
        for _, p in ipairs(spec.extra or {}) do
            local at = restores:find(p)
            if at then restores = restores:sub(1, at - 1) end
        end
        local health, mana = number((first(restores, spec.health))), number((first(restores, spec.mana)))
        if not health and not mana then return nil end
        return health, mana, duration, number((first(desc, spec.fed)))
    end
    return parseHeal, parseRest
end

-- The first registered language that reads `desc` as a heal: amount over time, its duration, the direct amount.
local function ParseHeal(desc)
    for _, language in ipairs(L.languages) do
        local over, duration, direct = ask(language.parseHeal, desc)
        if over or (type(direct) == "number" and direct > 0) then return over, duration, direct end
    end
end

function L.parseHeal(desc)
    local r = Kept("heal", desc)
    if r then return Again(r) end
    return Keep("heal", desc, ParseHeal(desc))
end

-- The first registered language that reads `desc` as food or drink: health, mana, seconds, seconds to a buff.
local function ParseRest(desc)
    for _, language in ipairs(L.languages) do
        local health, mana, duration, fed = ask(language.parseRest, desc)
        if type(duration) == "number" and (health or mana) then return health, mana, duration, fed end
    end
end

function L.parseRest(desc)
    local r = Kept("rest", desc)
    if r then return Again(r) end
    return Keep("rest", desc, ParseRest(desc))
end

-- Words nearly every English description has and other languages' descriptions don't ("sec" is left out: French
-- writes it too).
local ENGLISH_WORDS = { the = true, damage = true, ["and"] = true, ["for"] = true, over = true, of = true,
    to = true, by = true, with = true, your = true, you = true }

local function looksEnglish(desc)
    for word in desc:gmatch("%a+") do
        if ENGLISH_WORDS[word:lower()] then return true end
    end
    return false
end
L.looksEnglish = looksEnglish

-- Whether to log a description nothing read as a DoT (once per spell per session), so /sab dots shows the wording
-- of a language that is not read yet, or not fully. Decided by the text itself, not GetLocale(): English
-- descriptions that are not DoTs are not logged.
local loggedUnread = {}
function L.shouldLogUnread(spellID, desc)
    if type(desc) ~= "string" or desc == "" or looksEnglish(desc) then return false end
    if loggedUnread[spellID] then return false end
    loggedUnread[spellID] = true
    return true
end
