-- Chinese (zhCN and zhTW) spell descriptions and names. Registers itself with Locale.lua;
-- ported from DoesItDie 0.9.3 by Joe Greive (MIT licence, notice in Locale.lua).
-- The Chinese patterns only see descriptions the other languages didn't read, and can't match their text (they
-- need "秒内", "点", "伤害", "终结技", "连击点").
--
-- The wording is WoW: Forever's own Simplified Chinese tooltips (Wowhead's tooltip API, data env Forever, locale cn),
-- for every spell the addon tracks or ignores. Wowhead has no Traditional Chinese for Forever; the zhTW client's text
-- (issue #20: "並在隨後的12秒內造成總計38點火焰傷害") is the same wording in traditional characters, so traditional
-- characters are turned into simplified ones first (TRADITIONAL) and one set of patterns reads both. Not verified
-- on a Chinese client yet. How it differs from English:
--   * "在12秒内造成总计40点暗影伤害" (40 Shadow damage over 12 sec), with words like 总计/累计 (in total), 对其
--     (to it), 额外(的) (additional) around the amount
--   * the school is a word before "伤害" (damage): 暗影 Shadow, 火焰 Fire, ...; some tooltips leave it out
--     (Corruption, Fireball, Pyroblast), so those spells' schools are in SCHOOL_BY_NAME, and the reader takes the
--     direct hit's school or the wording's (WORDING_SCHOOLS) too
--   * finishers: "终结技", then "1点：12秒内44点伤害" (Rip) or "1点：25点伤害，持续8秒" (Rupture)
--   * builders: "奖励1个连击点数" (awards 1 combo point), also "奖励2点连击点数" (Cheap Shot)

local _, ns = ...

local PHYSICAL = 1

-- Patterns spell digits [0-9], not %d: %d and %s follow the C library's locale, and under some (e.g. Windows'
-- code page 1252) bytes inside Chinese characters count as digits or spaces.

-- Traditional characters in the words the patterns use -> simplified, and the full-width colon.
local TRADITIONAL = {
    ["點"] = "点", ["傷"] = "伤", ["內"] = "内", ["總"] = "总", ["計"] = "计", ["額"] = "额", ["對"] = "对",
    ["隨"] = "随", ["後"] = "后", ["個"] = "个", ["連"] = "连", ["擊"] = "击", ["獎"] = "奖", ["勵"] = "励",
    ["數"] = "数", ["終"] = "终", ["結"] = "结", ["續"] = "续", ["聖"] = "圣", ["術"] = "术", ["將"] = "将",
    ["標"] = "标", ["轉"] = "转", ["給"] = "给", ["獲"] = "获", ["蝕"] = "蚀", ["並"] = "并", ["幾"] = "几",
    ["機"] = "机", ["："] = ":",
}

-- School words, combined schools first: Frostfire Bolt's "造成额外39点霜火伤害". 秘法 is zhTW's Arcane.
local SCHOOLS = {
    { "霜火", 4 + 16 }, { "暗影", 32 }, { "火焰", 4 }, { "自然", 8 }, { "冰霜", 16 }, { "神圣", 2 }, { "奥术", 64 },
    { "奧术", 64 }, { "秘法", 64 },
}
local function schoolIn(words)
    for _, entry in ipairs(SCHOOLS) do
        if words:find(entry[1], 1, true) then return entry[2] end
    end
end

-- Tooltips that name no school anywhere: Corruption's "腐蚀目标，在12秒内造成累计40点伤害" (Shadow).
local WORDING_SCHOOLS = { { "腐蚀目标", 32 } }

-- Chinese names of the spells in Dots.lua's name-keyed tables: Forever's simplified ones (Wowhead), then the
-- same in traditional characters. Names the client reports by spell ID are added at load anyway (Locale.lua), so
-- these mostly matter for the tests.
local NAMES = {
    ["Insect Swarm"] = { "虫群", "蟲群" },
    ["Bane of Agony"] = { "痛苦灾祸", "痛苦災禍" },
    ["Curse of Agony"] = { "痛苦诅咒", "痛苦詛咒" },
    ["Corruption"] = { "腐蚀术", "腐蝕術" },
    ["Fireball"] = { "火球术", "火球術" },
    ["Holy Fire"] = { "神圣之火", "神聖之火" },
    ["Rip"] = { "撕扯" },
    ["Rupture"] = { "割裂" },
    ["Siphon Life"] = { "生命虹吸" },
    ["Serpent Sting"] = { "毒蛇钉刺", "毒蛇釘刺" },
    ["Pyroblast"] = { "炎爆术", "炎爆術" },
    ["Rain of Fire"] = { "火焰之雨" },
    ["Hellfire"] = { "地狱烈焰", "地獄烈焰" },
    ["Blizzard"] = { "暴风雪", "暴風雪" },
    ["Flamestrike"] = { "烈焰风暴", "烈焰風暴" },
    ["Consecration"] = { "奉献", "奉獻" },
    ["Hurricane"] = { "飓风", "颶風" },
    ["Volley"] = { "乱射", "亂射" },
    ["Drain Life"] = { "吸取生命" },
    ["Drain Soul"] = { "吸取灵魂", "吸取靈魂" },
    ["Drain Mana"] = { "吸取法力" },
    ["Health Funnel"] = { "生命通道" },
    ["Mind Flay"] = { "精神鞭笞" },
    ["Arcane Missiles"] = { "奥术飞弹", "奧術飛彈" },
    ["Starshards"] = { "星辰碎片" },
    ["Immolation Trap"] = { "献祭陷阱", "獻祭陷阱" },
    ["Explosive Trap"] = { "爆炸陷阱" },
}

local function normalize(desc)
    desc = desc:gsub("[\192-\255][\128-\191]*", TRADITIONAL)
    return (desc:gsub("([0-9]),([0-9][0-9][0-9])", "%1%2"))
end

local function isFinisher(desc)
    return desc:find("终结技", 1, true) ~= nil
end

-- "奖励1个连击点数" (Rake, Sinister Strike), "奖励1个连击点" (Claw), "奖励2点连击点数" (Cheap Shot), and Gouge's
-- "奖励1个$l连击点数" (a plural marker left in the text). The counter is checked as a whole string: a byte class
-- like [个点] would split those 3-byte characters. A chance ("有100%的几率奖励1个连击点数", Shank with Boot Knife,
-- where the English says 2) is no award.
local COMBO_COUNTERS = { ["个"] = true, ["点"] = true, ["个$l"] = true, ["点$l"] = true }
local function comboPointsAwarded(desc)
    desc = normalize(desc)
    for at, points, counter in desc:gmatch("()奖励([0-9]+)([^0-9]-)连击点") do
        local before = desc:sub(math.max(1, at - 6), at - 1)
        if COMBO_COUNTERS[counter] and before ~= "几率" and before ~= "机率" then return tonumber(points) end
    end
end

-- Per combo point count: "1点:12秒内44点伤害" (Rip) or "1点:25点伤害，持续8秒" (Rupture).
local function parseFinisher(desc, comboPoints)
    local byPoints, highest = {}, 0
    local function add(pts, amount, secs)
        local points = tonumber(pts)
        byPoints[points] = { total = tonumber(amount), duration = tonumber(secs) }
        highest = math.max(highest, points)
    end
    for pts, secs, amount in desc:gmatch("([0-9]+)点 *: *([0-9]+%.?[0-9]*)秒内([0-9]+)点") do add(pts, amount, secs) end
    for pts, amount, secs in desc:gmatch("([0-9]+)点 *: *([0-9]+)点伤害[^0-9]-持续([0-9]+%.?[0-9]*)秒") do
        add(pts, amount, secs)
    end
    if highest == 0 then return nil end
    local entry = byPoints[math.max(1, math.min(comboPoints, highest))] or byPoints[highest]
    return entry.total, PHYSICAL, entry.duration
end

-- Whether text between two numbers stays inside one clause.
local function oneClause(words)
    return not (words:find("，", 1, true) or words:find("。", 1, true) or words:find("；", 1, true))
end

-- The school of the direct hit earlier in the same sentence, for a DoT clause that names none: Fireball's
-- "对其造成15至23点火焰伤害，并在4秒内造成额外的2点伤害" (Fire).
local function directHitSchool(desc, at)
    local start, stop = 1, desc:find("。", 1, true)
    while stop and stop < at do
        start = stop + 3
        stop = desc:find("。", start, true)
    end
    local school
    for words in desc:sub(start, at - 1):gmatch("点([^0-9]-)伤害") do
        if oneClause(words) then school = schoolIn(words) or school end
    end
    return school
end

local function wordingSchool(desc)
    for _, entry in ipairs(WORDING_SCHOOLS) do
        if desc:find(entry[1], 1, true) then return entry[2] end
    end
end

local function parseDot(desc, comboPoints)
    desc = normalize(desc)
    if isFinisher(desc) then return parseFinisher(desc, comboPoints or 5) end
    -- Weapon poisons ("给一件武器浸毒") are proc DoTs, not cast on the target.
    if desc:find("武器", 1, true) and desc:find("毒", 1, true) then return nil end

    -- The last "N秒内 ... X点[school]伤害" clause, so a direct hit first (Immolate, Moonfire, Flame Shock) yields the
    -- periodic part. Heals ("恢复总计45点生命值") have no "伤害".
    local total, school, duration
    for at, secs, before, amount, words in desc:gmatch("()([0-9]+%.?[0-9]*)秒内([^0-9]-)([0-9]+)点([^0-9]-)伤害") do
        if oneClause(before) and oneClause(words) then
            total, duration = tonumber(amount), tonumber(secs)
            school = schoolIn(words) or directHitSchool(desc, at) or wordingSchool(desc) or PHYSICAL
        end
    end
    if total and duration and duration > 0 then return total, school, duration end

    -- A drain stated as a rate: "每3秒将目标的11点生命值转移给施法者，持续30秒" (Siphon Life; its school comes from
    -- SCHOOL_BY_NAME). Drain Life ("每1秒从目标身上吸取10点生命值并转移给施法者") reads the same way but is ignored
    -- by name. Health moving to the caster, not healing: Tranquility's "每2秒恢复91点生命值，持续10秒" is no DoT.
    local every, before, amount = desc:match("每([0-9]+%.?[0-9]*)秒([^0-9]-)([0-9]+)点生命值转移给")
    if not every then every, before, amount = desc:match("每([0-9]+%.?[0-9]*)秒([^0-9]-)([0-9]+)点生命值并转移给") end
    local lasts = desc:match("持续([0-9]+%.?[0-9]*)秒")
    if every and amount and lasts and oneClause(before) then
        every, lasts = tonumber(every), tonumber(lasts)
        if every > 0 and lasts > 0 then
            return tonumber(amount) * math.floor(lasts / every + 0.5), PHYSICAL, lasts, every
        end
    end
end

ns.locale.register({
    tag = "zhCN",
    parseDot = parseDot,
    isFinisher = function(desc) return isFinisher(normalize(desc)) end,
    comboPointsAwarded = comboPointsAwarded,
    names = NAMES,
})
