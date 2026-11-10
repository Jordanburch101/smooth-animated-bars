-- Russian (ruRU) spell descriptions and names. Registers itself with Locale.lua;
-- ported from DoesItDie 0.9.3 by Joe Greive (MIT licence, notice in Locale.lua).
-- The Russian patterns only see descriptions the other languages didn't read, and can't match their text (they
-- need "урона"/"здоровья" with "за N сек." or "в течение N сек.", "Завершающий прием", "Длина серии").
--
-- The wording is WoW: Forever's own Russian tooltips (Wowhead's tooltip API, data env Forever, locale 7), for every
-- spell the addon tracks or ignores. Not verified on a Russian client yet. How it differs:
--   * "нанося 40 ед. урона от темной магии за 12 сек." (40 Shadow damage over 12 sec), or "в течение 12 сек.";
--     Moonfire leaves out "ед.": "12 дополнительного урона от тайной магии в течение 9 сек."
--   * the school follows "урона": "от огня", "от темной магии", "от сил природы", "от магии льда", "от светлой
--     магии", "от тайной магии"; bleeds name none, or are worded as lost health: "теряет 15 ед. здоровья за 9 сек."
--   * a duration after "урона" is not always the DoT's: "нанося 6 ед. урона, прерывая применение заклинания ... в
--     течение 6 сек." (Shield Bash's lockout), "... и заставляет его атаковать вас в течение 3 сек." (Seal of Fury's
--     taunt). So only the school may stand between "урона" and the duration.
--   * finishers: "Завершающий прием" (Eviscerate: "Завершающий удар"), then "5 приемов: 189 ед. урона за 12 сек."
--     per combo point count
--   * builders: "Длина серии приемов увеличивается на 1."
-- Wowhead spells "е" where the client may print "ё" (приём, тёмной): the patterns accept both.
-- Digits are spelled [0-9] next to Cyrillic text (multibyte), as in the Korean and Chinese files.

local _, ns = ...

local PHYSICAL = 1

-- The school phrase between "урона" and the duration: nothing (a bleed: Rip, Rend), or "от" and one or two words
-- ("от огня", "от темной магии", "от ледяного огня"). Anything longer is a clause of its own, whose duration is
-- not the damage's: "урона от светлой магии и заставляет его атаковать вас в течение 3 сек." (Seal of Fury),
-- "урона от сил природы. Волна также прерывает ..." (Earth Shock). nil for words that name no school.
-- Words are told apart by explicit ASCII bytes, not %s or %p: in plain Lua 5.1 those follow the C library's locale,
-- which may class the bytes of Cyrillic letters (128 and up) as spaces or punctuation.
local NOT_IN_WORD = "[ \t\r\n%.,;:!%?\"'%(%)%[%]%-]"

local function schoolFromWords(words)
    if words == "" then return PHYSICAL end
    local first, second = words:match("^ от ([^ ]+) ?([^ ]*)$")
    if not first or first:find(NOT_IN_WORD) or second:find(NOT_IN_WORD) then return nil end
    -- Combined first: Frostfire Bolt's "от ледяного огня" is fire and frost together.
    local fire = words:find("огн", 1, true)
    local frost = words:find("льд", 1, true) or words:find("ледян", 1, true)
    if fire and frost then return 4 + 16 end
    if words:find("темн", 1, true) or words:find("тёмн", 1, true) then return 32 end
    if fire then return 4 end
    if words:find("природ", 1, true) then return 8 end
    if frost then return 16 end
    if words:find("светл", 1, true) then return 2 end
    if words:find("тайн", 1, true) then return 64 end
    if words:find("кровотеч", 1, true) then return PHYSICAL end -- Lacerate: "60 ед. урона от кровотечения за 15 сек."
end

-- What may stand between the amount and "урона"/"здоровья": "ед." (units), "дополнительного" (Moonfire: "12
-- дополнительного урона"), both, or nothing (Rake: "теряет 27 и дополнительно 60 здоровья"). Not the tail of a
-- formula: "[47 + (Сила атаки дальнего боя * (0.05))] ед. физического урона" (Summon Hawk) would read 5, and
-- "(24.5 * 8 * 1) ед. урона" (Blizzard) 1.
local UNIT_WORDS = { [" "] = true, [" ед. "] = true, [" дополнительного "] = true, [" ед. дополнительного "] = true }

-- Russian names of the spells in Dots.lua's name-keyed tables (Forever's, from Wowhead). Names the client
-- reports by spell ID are added at load anyway (Locale.lua), so these mostly matter for the tests.
local NAMES = {
    ["Insect Swarm"] = { "Рой насекомых" },
    ["Bane of Agony"] = { "Бич агонии" },
    ["Curse of Agony"] = { "Проклятие агонии" }, -- Classic's name; unverified on Forever
    ["Corruption"] = { "Порча" },
    ["Fireball"] = { "Огненный шар" },
    ["Holy Fire"] = { "Священный огонь" },
    ["Rip"] = { "Разорвать" },
    ["Rupture"] = { "Рваная рана" },
    ["Siphon Life"] = { "Вытягивание жизни" },
    ["Serpent Sting"] = { "Укус змеи" },
    ["Pyroblast"] = { "Огненная глыба" },
    ["Rain of Fire"] = { "Огненный ливень" },
    ["Hellfire"] = { "Адское Пламя", "Адское пламя" },
    ["Blizzard"] = { "Снежная буря" },
    ["Flamestrike"] = { "Огненный столб" },
    ["Consecration"] = { "Освящение" },
    ["Hurricane"] = { "Гроза" },
    ["Volley"] = { "Град стрел" },
    ["Drain Life"] = { "Похищение жизни" },
    ["Drain Soul"] = { "Похищение души" },
    ["Drain Mana"] = { "Похищение маны" },
    ["Health Funnel"] = { "Канал здоровья" },
    ["Mind Flay"] = { "Пытка разума" },
    ["Arcane Missiles"] = { "Чародейские снаряды" },
    ["Starshards"] = { "Звездные осколки", "Звёздные осколки" },
    ["Immolation Trap"] = { "Обжигающая ловушка" },
    ["Explosive Trap"] = { "Взрывная ловушка" },
}

-- Non-breaking spaces (U+00A0, U+202F) as plain ones, so "40 ед." reads the same either way; then decimal commas
-- ("1,5 сек." -> "1.5 сек.") and thousands separators ("1 132").
local function normalize(desc)
    desc = desc:gsub("\194\160", " "):gsub("\226\128\175", " ")
    desc = desc:gsub("([0-9]),([0-9])", "%1.%2")
    return (desc:gsub("([0-9]) ([0-9][0-9][0-9])%f[^0-9]", "%1%2"))
end

-- "Завершающий прием" (Rip, Rupture, Kidney Shot) or "Завершающий удар" (Eviscerate).
local function isFinisher(desc)
    return desc:find("Завершающий при", 1, true) ~= nil or desc:find("Завершающий удар", 1, true) ~= nil
end

-- "Длина серии приемов увеличивается на 1." (Rake, Sinister Strike, Garrote; Cheap Shot 2). Claw's Russian text
-- has its numbers swapped ("нанося 39% базового и 1 ед. дополнительного урона. Длина серии приемов увеличивается
-- на 140."), and no builder awards more than 5, so a higher number counts as the one point every other builder gives.
-- Mutilate words it "Продлевает серию приемов на 2." ("приёмов" accepted too).
local function comboPointsAwarded(desc)
    local points = tonumber(desc:match("Длина серии [^0-9]-увеличивается на ([0-9]+)")
        or desc:match("Продлевает серию при[^ ]-мов на ([0-9]+)"))
    if points and points > 5 then return 1 end
    return points
end

-- "5 приемов: 189 ед. урона за 12 сек." per combo point count (Rip, Rupture).
local function parseFinisher(desc, comboPoints)
    local byPoints, highest = {}, 0
    for pts, amount, secs in desc:gmatch("([0-9]+) при[^:\n]-: *([0-9]+) ед%. урона за ([0-9]+%.?[0-9]*) сек") do
        local points = tonumber(pts)
        byPoints[points] = { total = tonumber(amount), duration = tonumber(secs) }
        highest = math.max(highest, points)
    end
    if highest == 0 then return nil end
    local entry = byPoints[math.max(1, math.min(comboPoints, highest))] or byPoints[highest]
    return entry.total, PHYSICAL, entry.duration
end

-- The last "<amount> ед. <noun> <school> за/в течение <secs> сек." clause in the description, so a direct hit
-- first (Immolate, Moonfire, Fireball) yields the periodic part: total, school, duration. Only units before the
-- noun (UNIT_WORDS) and only a school after it (schoolFromWords).
local function lastClause(desc, noun)
    local bestAt, total, school, duration
    for _, lead in ipairs({ " за ", " в течение " }) do
        local pattern = "()([0-9]+)([^0-9]-)" .. noun .. "([^0-9]-)" .. lead .. "([0-9]+%.?[0-9]*) сек"
        for at, amount, units, between, secs in desc:gmatch(pattern) do
            local clauseSchool = UNIT_WORDS[units] and schoolFromWords(between)
            if clauseSchool and (not bestAt or at > bestAt) then
                bestAt, total, school, duration = at, amount, clauseSchool, secs
            end
        end
    end
    if bestAt then return tonumber(total), school, tonumber(duration) end
end

local function parseDot(desc, comboPoints)
    desc = normalize(desc)
    if isFinisher(desc) then return parseFinisher(desc, comboPoints or 5) end
    -- Weapon poisons ("Смазать оружие ядом") are proc DoTs, not cast on the target.
    if desc:find("Смазать оружие", 1, true) then return nil end

    local total, school, duration = lastClause(desc, "урона")
    if total and duration > 0 then return total, school, duration end

    -- Bleeds worded as lost health: "теряет 15 ед. здоровья за 9 сек." (Rend), "Противник теряет 27 и
    -- дополнительно 60 здоровья за 9 сек." (Rake). Only with "теряет", so a heal over time ("Восстанавливает
    -- союзнику 575 ед. здоровья за 15 сек.", Riptide) is never read.
    if desc:find("теряет", 1, true) then
        total, school, duration = lastClause(desc, "здоровья")
        if total and school == PHYSICAL and duration > 0 then return total, PHYSICAL, duration end
    end

    -- A drain stated as a rate: "Вы похищаете у цели 11 ед. здоровья раз в 3 сек. ... Время действия – 30 сек."
    -- (Siphon Life; its school comes from SCHOOL_BY_NAME). Drain Life reads the same way but is ignored by name.
    local amount, every = desc:match("похищаете у цели ([0-9]+) ед%. здоровья раз в ([0-9]+%.?[0-9]*) сек")
    local lasts = desc:match("Время действия [^0-9]-([0-9]+%.?[0-9]*) сек")
    if amount and every and lasts then
        every, lasts = tonumber(every), tonumber(lasts)
        if every > 0 and lasts > 0 then
            return tonumber(amount) * math.floor(lasts / every + 0.5), PHYSICAL, lasts, every
        end
    end
end

ns.locale.register({
    tag = "ruRU",
    parseDot = parseDot,
    isFinisher = function(desc) return isFinisher(normalize(desc)) end,
    comboPointsAwarded = comboPointsAwarded,
    names = NAMES,
})
