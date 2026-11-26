"""Checks that a change draws exactly what it drew before: for work on the liquid's cost, which must not change its look.

Usage: python samelook.py <addon dir> [--ref HEAD] [--seconds 6] [--fps 60] [--only NAME]

Plays the same scenarios (several classes and themes, every effect at its strongest, a reversed bar, quiet stretches
and fights) on the addon at a git ref and on the working copy, each in a fresh mock with the same random seed, and
compares every texture that shows, every frame: where it is on the screen (anchors resolved, whatever they are anchored
to), its size, texture and coordinates, colours and gradients, alpha (its parents' too), blend mode, draw layer and
rotation. Exits 1 on any difference past the tolerances below.

Geometry and texture coordinates must match to within float rounding. Colours and alpha may differ by up to
COLOR_TOL: a texture's colour is only set again once it has moved by about half of one 8-bit step (Liquid.lua,
COLOR_STEP), less than the screen can show.
"""
import argparse
import os
import sys

try:
    from lupa.luajit21 import LuaRuntime
except ImportError:
    from lupa.lua51 import LuaRuntime

import gitref

HERE = os.path.dirname(os.path.abspath(__file__))
GEOM_TOL = 1e-6
COLOR_TOL = 0.5 / 255 + 1e-6

BARS = ("playerHealth", "playerPower", "targetHealth", "targetPower", "prdHealth", "prdPower", "partyHealth",
        "partyPower", "petHealth", "petPower", "focusHealth", "focusPower", "totHealth", "totPower")
MAX = {"animationSpeed": 200, "waveIntensity": 200}
# name, class (UnitPowerType index), settings, party members, reversed external bar
SCENARIOS = [
    ("warrior, game colours, effects at their strongest", "WARRIOR", 1, {"rageFury": True, **MAX}, 2, False),
    ("warrior, default effects", "WARRIOR", 1, {"rageFury": True}, 0, False),
    ("mage, fire and prismatic", "MAGE", 0, {"healthColor": "fire", "powerColor": "prismatic",
                                              "targetHealthColor": "shadow", **MAX}, 1, False),
    ("rogue, shadow and tidal, slow", "ROGUE", 3, {"healthColor": "shadow", "powerColor": "tidal",
                                                   "animationSpeed": 25, "waveIntensity": 0}, 0, False),
    ("priest, frost, swirl and waves off", "PRIEST", 0, {"healthColor": "frost", "swirl": False, "waves": False}, 0, False),
    ("another addon's reversed bar", "WARRIOR", 1, {"healthColor": "fire", **MAX}, 0, True),
    ("Bar Height on the player and target", "MAGE", 0, {"playerHealthHeight": 30, "playerPowerHeight": 14,
                                                         "targetHealthHeight": 28, "targetPowerHeight": 12}, 2, False),
]

# Two runs of the same code must draw the same, so every random draw has to come in the same order. pairs over a table
# keyed by tables (the bars by their frames) goes in an order of their memory addresses, which differ between runs, and
# with it the order the liquids update in and take their random numbers. So pairs here goes in a fixed order: numbers,
# strings, then regions by when they were made, and other tables by when pairs first met them.
STABLE_PAIRS = r"""
local rawnext, rawget, type, sort, tostring = next, rawget, type, table.sort, tostring
-- Another table as a key (the bars by their spots) goes by its plain fields, as they were when first met here: the same
-- in every run, where its address is not.
local sigs = setmetatable({}, { __mode = "k" })
local function signature(k)
    local s = sigs[k]
    if s then return s end
    local parts = {}
    for f, v in rawnext, k do
        local tf, tv = type(f), type(v)
        if (tf == "string" or tf == "number") and (tv == "string" or tv == "number" or tv == "boolean") then
            parts[#parts + 1] = tostring(f) .. "=" .. tostring(v)
        end
    end
    sort(parts)
    s = table.concat(parts, ";")
    sigs[k] = s
    return s
end
local function rank(k)
    local t = type(k)
    if t == "number" then return 1, k end
    if t == "string" then return 2, k end
    if t == "boolean" then return 3, k and 1 or 0 end
    if t == "table" and type(rawget(k, "order")) == "number" and rawget(k, "kind") then return 4, rawget(k, "order") end
    if t == "table" then return 5, signature(k) end
    return 6, tostring(k)
end
local function before(a, b)
    local ra, va = rank(a)
    local rb, vb = rank(b)
    if ra ~= rb then return ra < rb end
    return va < vb
end
function pairs(t)
    local keys = {}
    for k in rawnext, t do keys[#keys + 1] = k end
    if #keys > 1 then sort(keys, before) end
    local i = 0
    return function()
        while true do
            i = i + 1
            local k = keys[i]
            if k == nil then return nil end
            local v = rawget(t, k)
            if v ~= nil then return k, v end
        end
    end, t, nil
end
"""

DUMP = r"""
local function absRect(r, memo)
    if memo[r] then return unpack(memo[r]) end
    local pl, pt, pw, ph = 0, 0, 1920, 1080
    if r.parent then pl, pt, pw, ph = absRect(r.parent, memo) end
    local w, h = r.w or 0, r.h or 0
    local left, right, cx, top, bottom, cy
    local any = false
    for p, a in pairs(r.points) do
        any = true
        local rl, rt, rw, rh = pl, pt, pw, ph
        if a.rel and a.rel ~= r.parent then rl, rt, rw, rh = absRect(a.rel, memo) end
        local ax = a.relPoint:find("LEFT") and 0 or (a.relPoint:find("RIGHT") and rw or rw / 2)
        local ay = a.relPoint:find("TOP") and 0 or (a.relPoint:find("BOTTOM") and rh or rh / 2)
        local x, y = rl + ax + a.x, rt + ay - a.y
        if p:find("LEFT") then left = x elseif p:find("RIGHT") then right = x else cx = x end
        if p:find("TOP") then top = y elseif p:find("BOTTOM") then bottom = y else cy = y end
    end
    if not any then left, top = pl, pt end
    if left and right then w = right - left elseif right then left = right - w elseif not left then left = (cx or 0) - w / 2 end
    if top and bottom then h = bottom - top elseif bottom then top = bottom - h elseif not top then top = (cy or 0) - h / 2 end
    memo[r] = { left, top, w, h }
    return left, top, w, h
end
function __lookDump()
    local memo, out = {}, {}
    local i = 0 -- textures are numbered among textures alone: a frame more or less (a change may add one) moves none
    for _, r in ipairs(__regions) do
        if r.kind == "Texture" then
            i = i + 1
            local a, p, on = __reveal(r.alpha) or 0, r.parent, r.shown
            while on and p do
                a, on, p = a * (__reveal(p.alpha) or 0), p.shown, p.parent
            end
            if on and a > 0 then
                local x, y, w, h = absRect(r, memo)
                local g1, g2 = r.grad and r.grad[1] or {}, r.grad and r.grad[2] or {}
                local c = r.color or {}
                out[#out + 1] = string.format("%d|%s|%s|%s|%s|%d|%d|%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g|"
                    .. "%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g",
                    i, tostring(r.file), tostring(r.blend), tostring(r.layer), tostring(r.wrap), r.sub or 0,
                    r.masks and #r.masks or 0, x, y, w, h, r.tc[1], r.tc[2], r.tc[3], r.tc[4], r.rotation or 0,
                    a, r.vc[1], r.vc[2], r.vc[3], g1[1] or -1, g1[2] or -1, g1[3] or -1, g1[4] or -1,
                    g2[1] or -1, g2[2] or -1, g2[3] or -1, g2[4] or -1, c[1] or -1, c[2] or -1, c[3] or -1, c[4] or -1,
                    r.grad and 1 or 0, 0, 0)
            end
        end
    end
    return table.concat(out, "\n")
end
"""


def lua_value(v):
    return "true" if v is True else "false" if v is False else repr(v)


def session(addon, cls, power, settings, party, reversed_bar):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(open(os.path.join(HERE, "wowmock.lua"), encoding="utf-8").read())
    lua.execute(STABLE_PAIRS)
    lua.execute("math.randomseed(20261126)")
    s = {k: True for k in BARS}
    # At Unlimited: the drawing is what is compared, not the Animation Frame Rate (a setting that changes it on purpose).
    s.update({"setupDone": True, "heals": False, "manaBuild": False, "animationFps": 150})
    s.update(settings)
    saved = "{ " + ", ".join(f"{k} = {lua_value(v)}" for k, v in s.items()) + " }"
    lua.execute(f"""
        __player.class, __player.power = {cls!r}, {power}
        __target = {{ guid = 'Creature-0-1-2-3-299-0001', name = 'Defias Pillager' }}
        PersonalResourceDisplayFrame:Show()
        for i = 1, {party} do
            __units['party' .. i] = {{ isOtherPlayer = true, class = 'MAGE', power = 0 }}
            PartyFrame['MemberFrame' .. i]:Show()
        end
        SmoothAnimatedBarsDB = {saved}""")
    lua.globals().__ns = lua.globals().__loadAddon(addon.replace("\\", "/"), "SmoothAnimatedBars")
    lua.execute("""
        local all = { PlayerFrame.healthbar, PlayerFrame.manabar, TargetFrame.healthbar, TargetFrame.manabar,
            PersonalResourceDisplayFrame.HealthBarsContainer.healthBar, PersonalResourceDisplayFrame.PowerBar }
        for i = 1, 4 do
            local f = PartyFrame['MemberFrame' .. i]
            all[#all + 1], all[#all + 2] = f.HealthBarContainer.HealthBar, f.ManaBar
        end
        for _, b in ipairs(all) do b:SetMinMaxValues(0, __secret()); b:SetValue(__secret()) end
        __fire('ADDON_LOADED', 'SmoothAnimatedBars'); __fire('PLAYER_ENTERING_WORLD', true, false)
        __fire('PLAYER_TARGET_CHANGED'); __fire('GROUP_ROSTER_UPDATE')
    """)
    if reversed_bar:
        lua.execute("""
            __uf = CreateFrame("Frame", nil, UIParent)
            __uf.level = 5
            local b = CreateFrame("StatusBar", nil, __uf)
            b.w, b.h, b.level = 180, 24, 6
            b:SetStatusBarTexture(b:CreateTexture(nil, "ARTWORK"))
            b:SetMinMaxValues(0, __secret()); b:SetValue(__secret())
            b:SetStatusBarColor(0.2, 0.8, 0.2)
            b:SetReverseFill(true)
            SmoothAnimatedBars.AddBar(b, 'player', 'health')
        """)
    lua.execute(DUMP)
    return lua


def play(lua, seconds, fps, party):
    """Yields each frame's dump: a quiet stretch, a fight (every unit's health and power changing ten times a second,
    with a stir now and then), then quiet again as it settles."""
    step = lua.globals().__step
    dump = lua.globals().__lookDump
    t, next_event, frame = 0.0, 0.0, 0
    fight = (seconds * 0.25, seconds * 0.7)
    # The target lost and found again late on: its frame hides and shows, and its bars stop and start.
    lose, find = seconds * 0.75, seconds * 0.85
    while t < seconds:
        if lose <= t < lose + 0.5 / fps:
            lua.execute("__saved_target = __target; __target = nil; TargetFrame:Hide(); __fire('PLAYER_TARGET_CHANGED')")
        if find <= t < find + 0.5 / fps:
            lua.execute("__target = __saved_target; TargetFrame:Show(); __fire('PLAYER_TARGET_CHANGED')")
        if fight[0] <= t < fight[1] and t >= next_event:
            next_event = t + 0.1
            lua.execute(f"""
                __fire('UNIT_HEALTH', 'player'); __fire('UNIT_POWER_UPDATE', 'player', 'RAGE')
                __fire('UNIT_HEALTH', 'target'); __fire('UNIT_POWER_UPDATE', 'target', 'MANA')
                for i = 1, {party} do
                    __fire('UNIT_HEALTH', 'party' .. i); __fire('UNIT_POWER_UPDATE', 'party' .. i, 'MANA')
                end""")
        step(1 / fps)
        t += 1 / fps
        frame += 1
        yield frame, dump()


def parse(text):
    out = {}
    for line in text.split("\n") if text else ():
        parts = line.split("|")
        out[int(parts[0])] = (parts[1:7], [float(v) for v in parts[7].split(",")], [float(v) for v in parts[8].split(",")])
    return out


def compare(a, b):
    """The first few differences between two frames' dumps, as text."""
    da, db = parse(a), parse(b)
    problems = []
    for i in sorted(set(da) | set(db)):
        if i not in da or i not in db:
            problems.append(f"texture {i} shows only {'after' if i in db else 'before'} the change")
            continue
        (ka, ga, ca), (kb, gb, cb) = da[i], db[i]
        if ka != kb:
            problems.append(f"texture {i}: {ka} became {kb}")
        worst = max((abs(x - y) for x, y in zip(ga, gb)), default=0)
        if worst > GEOM_TOL:
            problems.append(f"texture {i}: place/size/coords {ga} became {gb}")
        worst = max((abs(x - y) for x, y in zip(ca, cb)), default=0)
        if worst > COLOR_TOL:
            problems.append(f"texture {i}: colour/alpha off by {worst:.5f}: {ca} became {cb}")
        if len(problems) >= 5:
            break
    return problems


def colour_drift(a, b):
    da, db = parse(a), parse(b)
    return max((abs(x - y) for i in da if i in db for x, y in zip(da[i][2], db[i][2])), default=0.0)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("addon")
    ap.add_argument("--ref", default="HEAD", help="git ref to compare against (default HEAD)")
    ap.add_argument("--seconds", type=float, default=6)
    ap.add_argument("--fps", type=float, default=60)
    ap.add_argument("--only", help="run only scenarios whose name contains this")
    a = ap.parse_args()
    before_dir = gitref.export(a.ref)
    failed = False
    for name, cls, power, settings, party, rev in SCENARIOS:
        if a.only and a.only not in name:
            continue
        old = play(session(before_dir, cls, power, settings, party, rev), a.seconds, a.fps, party)
        new = play(session(a.addon, cls, power, settings, party, rev), a.seconds, a.fps, party)
        frames, drift, shown, bad = 0, 0.0, 0, None
        for (frame, x), (_, y) in zip(old, new):
            frames += 1
            shown = max(shown, x.count("\n") + 1 if x else 0)
            problems = compare(x, y)
            if problems:
                bad = (frame, problems)
                break
            drift = max(drift, colour_drift(x, y))
        if bad:
            failed = True
            print(f"DIFFERENT  {name}: frame {bad[0]}")
            for p in bad[1]:
                print("    " + p)
        else:
            print(f"same       {name}: {frames} frames, up to {shown} textures, colours within {drift * 255:.2f}/255")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
