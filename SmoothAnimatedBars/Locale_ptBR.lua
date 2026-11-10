-- Brazilian Portuguese (ptBR) spell descriptions and names. Registers itself with Locale.lua;
-- ported from DoesItDie 0.9.3 by Joe Greive (MIT licence, notice in Locale.lua).
-- The Portuguese patterns only see descriptions the other languages didn't read, and can't match their text (they
-- need "de dano", "ao longo de N s", "Golpe final", "ponto de combo").
--
-- The wording is WoW: Forever's own Portuguese tooltips (Wowhead's tooltip API, data env Forever, locale pt), for
-- every spell the addon tracks or ignores (issue #19). Not verified on a Portuguese client yet. How it differs:
--   * "causando 40 de dano de Sombra ao longo de 12 s" (40 Shadow damage over 12 sec); bleeds name no school
--   * the school follows "dano": "de Sombra", "de Fogo", "de Natureza", "de Gelo", "Sagrado", "Arcano"
--   * finishers: "Golpe final", then "1 ponto: 44 de dano ao longo de 12 s." per combo point count
--   * builders: "Concede 1 ponto de combo."

local _, ns = ...

local PHYSICAL = 1

-- School words, combined schools first. Frostfire is one word, "causando mais 27 de dano de Fogofrio ao longo de
-- 9 s" (Frostfire Bolt), so it has no "Gelo" and would read as Fire without its own check.
local function schoolFromWords(words)
    if words:find("ogofrio", 1, true) then return 4 + 16 end
    local fire, frost = words:find("Fogo", 1, true), words:find("Gelo", 1, true)
    if fire and frost then return 4 + 16 end
    if words:find("Sombra", 1, true) then return 32 end
    if fire then return 4 end
    if words:find("Natureza", 1, true) then return 8 end
    if frost then return 16 end
    if words:find("Sagrado", 1, true) then return 2 end
    if words:find("Arcano", 1, true) then return 64 end
    return PHYSICAL
end

-- Portuguese names of the spells in Dots.lua's name-keyed tables (Forever's, from Wowhead). Names the client
-- reports by spell ID are added at load anyway (Locale.lua), so these mostly matter for the tests.
local NAMES = {
    ["Insect Swarm"] = { "Nuvem de Insetos" },
    ["Bane of Agony"] = { "Ruína da Agonia" },
    ["Curse of Agony"] = { "Maldição da Agonia" },
    ["Corruption"] = { "Corrupção" },
    ["Fireball"] = { "Bola de Fogo" },
    ["Holy Fire"] = { "Fogo Sagrado" },
    ["Rip"] = { "Rasgar" },
    ["Rupture"] = { "Ruptura" },
    ["Siphon Life"] = { "Sifão de Vida" },
    ["Serpent Sting"] = { "Picada de Serpente" },
    ["Pyroblast"] = { "Ignimpacto" },
    ["Rain of Fire"] = { "Chuva de Fogo" },
    ["Hellfire"] = { "Fogo do Inferno" },
    ["Blizzard"] = { "Nevasca" },
    ["Flamestrike"] = { "Golpe Flamejante" },
    ["Consecration"] = { "Consagração" },
    ["Hurricane"] = { "Furacão" },
    ["Volley"] = { "Salva" },
    ["Drain Life"] = { "Drenar Vida" },
    ["Drain Soul"] = { "Drenar Alma" },
    ["Drain Mana"] = { "Drenar Mana" },
    ["Health Funnel"] = { "Funil de Vida" },
    ["Mind Flay"] = { "Açoite Mental" },
    ["Arcane Missiles"] = { "Mísseis Arcanos" },
    ["Starshards"] = { "Fragmentos Estelares" },
    ["Immolation Trap"] = { "Armadilha Imolante" },
    ["Explosive Trap"] = { "Armadilha Explosiva" },
}

-- Non-breaking spaces (U+00A0, U+202F) made plain, as the text has them in places a plain space would do
-- ("\n \194\160 1 ponto: 57 de dano" in Rip, "1 ponto \194\160: 12% do acumulado" in Marca da Morte) and the
-- client may put them where Wowhead does not. Then thousands separators ("1.132" -> "1132") and decimal commas
-- ("1,5 s" -> "1.5 s").
local function normalize(desc)
    desc = desc:gsub("\194\160", " "):gsub("\226\128\175", " ")
    return (desc:gsub("(%d)%.(%d%d%d)", "%1%2"):gsub("(%d),(%d)", "%1.%2"))
end

local function isFinisher(desc)
    return desc:find("Golpe final", 1, true) ~= nil or desc:find("Golpe Final", 1, true) ~= nil
end

-- "Concede 1 ponto de combo." (Rake, Claw, Sinister Strike), with capitals in some: "Concede 2 pontos de Combo."
-- (Cheap Shot), "Concede 2 Pontos de Combo." (Mutilate).
local function comboPointsAwarded(desc)
    return tonumber(desc:match("Concede (%d+) [Pp]ontos? de [Cc]ombo"))
end

-- "1 ponto: 44 de dano ao longo de 12 s." per combo point count (Rip, Rupture). Points with no line of their own
-- take the nearest line below, else the lowest: never a higher one, which would show more than the cast deals.
local function parseFinisher(desc, comboPoints)
    local byPoints, highest, lowest = {}, 0, nil
    for pts, amount, secs in desc:gmatch("(%d+) pontos?%s*:%s*(%d+) de dano ao longo de (%d+%.?%d*) s") do
        local points = tonumber(pts)
        byPoints[points] = { total = tonumber(amount), duration = tonumber(secs) }
        highest = math.max(highest, points)
        lowest = math.min(lowest or points, points)
    end
    if highest == 0 then return nil end
    local entry
    for points = math.max(1, math.min(comboPoints, highest)), 1, -1 do
        entry = byPoints[points]
        if entry then break end
    end
    entry = entry or byPoints[lowest]
    return entry.total, PHYSICAL, entry.duration
end

local function parseDot(desc, comboPoints)
    desc = normalize(desc)
    if isFinisher(desc) then return parseFinisher(desc, comboPoints or 5) end
    -- Weapon poisons ("Cobre a arma com um veneno") are proc DoTs, not cast on the target.
    if desc:find("Cobre a arma", 1, true) then return nil end

    -- The last "X de dano [school] ao longo de N s" clause, so a direct hit first (Immolate, Moonfire, Rake) yields
    -- the periodic part. Between "dano" and "ao longo" there are no digits or sentence ends.
    local total, school, duration
    for amount, words, secs in desc:gmatch("(%d+) de dano([^%d%.]-) ao longo de (%d+%.?%d*) s") do
        total, school, duration = tonumber(amount), schoolFromWords(words), tonumber(secs)
    end
    if total and duration and duration > 0 then return total, school, duration end

    -- A drain stated as a rate: "Transfere 11 pontos de vida do alvo para o lançador a cada 3 s. Dura 30 s." (Siphon
    -- Life; its school comes from SCHOOL_BY_NAME). Drain Life reads the same way but is ignored by name.
    local amount, every = desc:match("Transfere (%d+) pontos de vida.-a cada (%d+%.?%d*) s")
    local lasts = desc:match("Dura (%d+%.?%d*) s")
    if amount and every and lasts then
        every, lasts = tonumber(every), tonumber(lasts)
        if every > 0 and lasts > 0 then
            return tonumber(amount) * math.floor(lasts / every + 0.5), PHYSICAL, lasts, every
        end
    end
end

ns.locale.register({
    tag = "ptBR",
    parseDot = parseDot,
    isFinisher = function(desc) return isFinisher(normalize(desc)) end,
    comboPointsAwarded = function(desc) return comboPointsAwarded(normalize(desc)) end,
    names = NAMES,
})
