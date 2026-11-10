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

-- The first registered language that reads `desc` as a DoT: total damage, school mask, duration, stated tick
-- interval (the returns of parseDot in Dots.lua).
function L.parseDot(desc, comboPoints)
    for _, language in ipairs(L.languages) do
        local total, school, duration, interval = ask(language.parseDot, desc, comboPoints)
        if type(total) == "number" and type(duration) == "number" then return total, school, duration, interval end
    end
end

function L.isFinisher(desc)
    for _, language in ipairs(L.languages) do
        if ask(language.isFinisher, desc) then return true end
    end
    return false
end

function L.comboPointsAwarded(desc)
    for _, language in ipairs(L.languages) do
        local points = ask(language.comboPointsAwarded, desc)
        if type(points) == "number" then return points end
    end
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
