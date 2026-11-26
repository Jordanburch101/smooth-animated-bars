"""The CPU rig: what /sab perf would say in game, worked out offline from the addon running in the mock.

    python rig.py calibrate [--saved FILE] [--since "2026-11-26 14:40"] [--ref REF] [--fit]
    python rig.py predict [--saved FILE] [--scenario idle|notarget|fight] [--fps 120] [--ref HEAD]

The mock cannot time the client, so the rig gives the addon a clock of its own (debugprofilestop): every call to the
game's widgets and every thousand Lua instructions run in the addon's files moves it on by a cost per kind of call
(setters, getters, status bars, the rest) and per Lua work. The addon's own /sab perf then runs in the mock exactly as
in game (its part-by-part timing, ns.Timed and Bars.Lap), with the player's own saved settings (Bar Height and all),
only the player's and target's frames shown, at the frame rate measured in game, idle or in a fight (every unit's
health and power changing ten times a second), and its report is read back.

calibrate: the costs come from /sab perf calib in game, which times each kind of widget call and a piece of the addon's
Lua there (its instructions counted exactly here), and are checked against the reports with every part timed in game
(/sab perf, saved in the saved variables; --since picks those made with the code now in the working copy, or at --ref).
Each report is played back in the mock in its own conditions (in combat or not, a target or not, its frame rate), once
for each kind of cost, so each part's count of each kind is known, and each part's predicted time is printed beside
the measured one and written to rig_calibration.json. Without a /sab perf calib (or with --fit) the costs are instead
the non-negative fit of those counts to the measured times; from two reports that fit could not tell the Lua from the
widget calls (both grow with the liquid's work), so measure.

predict: one run with the fitted costs, its parts in predicted in-game ms a frame, beside the same at --ref. A
measurement in game now and then (/sab perf, then calibrate again) keeps the costs honest.
"""
import argparse
import json
import os
import sys
from concurrent.futures import ProcessPoolExecutor

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, ".."))
import bench  # noqa: E402
import gitref  # noqa: E402
import perf_report as loader  # noqa: E402  (tools/perf_report.py: the saved variables' reports)

ADDON = os.path.abspath(os.path.join(HERE, "..", "..", "SmoothAnimatedBars"))
CALIBRATION = os.path.join(HERE, "rig_calibration.json")
KINDS = ("set", "get", "bar", "other", "api", "lua")
# Units: microseconds a call, and microseconds a thousand Lua instructions.
SAMPLE = 50
SETTLE = 2.0
# A fight's changes a second for each of the player's and target's health and power (rig.py --pace).
PACE = 10.0
# The player's class (rig.py --class): a warrior's rage bar has the Rage Fury, others not.
CLASS = "WARRIOR"
PARTS_SECONDS = 10.6

# The modelled clock and the calls that move it, put in before the addon loads: Liquid.lua keeps debugprofilestop,
# and files keep game functions in locals, as they load. Each widget call moves the clock by its kind's cost (only the
# outermost: the mock's methods call each other, the client's do not), each other game function by 'api'.
CLOCK = r"""
__synth, __w = 0, { set = 0, get = 0, bar = 0, other = 0, api = 0, lua = 0 }
function debugprofilestop() return __synth end
local BAR = { SetValue = true, SetMinMaxValues = true, GetValue = true, GetMinMaxValues = true,
              SetStatusBarTexture = true, SetStatusBarColor = true, GetStatusBarTexture = true }
local function kind(name)
    if BAR[name] then return 'bar' end
    if name:find('^Set') or name == 'Show' or name == 'Hide' or name == 'ClearAllPoints' then return 'set' end
    if name:find('^Get') or name:find('^Is') or name:find('^Can') or name:find('^Has') then return 'get' end
    return 'other'
end
local R = getmetatable(UIParent)
__rigDepth = { n = 0 }
local D = __rigDepth
-- Under pcall, so a call that errors (the addon asks some under pcall on purpose) still steps back out.
local function finish(ok, ...)
    D.n = D.n - 1
    if not ok then error((...), 0) end
    return ...
end
for name, fn in pairs(R) do
    if type(fn) == 'function' and name ~= '__index' then
        local k = kind(name)
        R[name] = function(...)
            if D.n == 0 then __synth = __synth + __w[k] / 1000 end
            D.n = D.n + 1
            return finish(pcall(fn, ...))
        end
    end
end
local getinfo, find = debug.getinfo, string.find
-- The game's other functions (UnitHealth, GetTime, C_Spell..., CreateFrame): C in the client, Lua in the mock, so
-- each is a call of kind 'api'. The mock's own helpers (__fire...) and Lua's libraries are left alone.
local function wrapApi(t, name, fn)
    local i = getinfo(fn, 'S')
    if i.what ~= 'Lua' or find(i.source, 'SmoothAnimatedBars/', 1, true) then return end
    t[name] = function(...)
        if D.n == 0 then __synth = __synth + __w.api / 1000 end
        D.n = D.n + 1
        return finish(pcall(fn, ...))
    end
end
local skip = { pairs = true, ipairs = true, next = true, _G = true, string = true, math = true, table = true, coroutine = true, debug = true, io = true, os = true,
               package = true, bit = true }
for name, v in pairs(_G) do
    if type(name) == 'string' and name:sub(1, 2) ~= '__' and not skip[name] then
        if type(v) == 'function' then
            wrapApi(_G, name, v)
        elseif type(v) == 'table' and name:find('^C_') then
            for k, fn in pairs(v) do if type(fn) == 'function' then wrapApi(v, k, fn) end end
        end
    end
end
"""

# After loading: a count hook moves the clock by the Lua work run in the addon's own files.
METER = r"""
local getinfo, find, sethook = debug.getinfo, string.find, debug.sethook
-- Re-armed as the hook's last act: in Lua 5.1 the hook's own instructions use up the count, and armed once the meter
-- charged the addon's Lua about three times over (bench.py).
local hook
hook = function()
    if __rigDepth.n == 0 then
        local i = getinfo(2, 'S')
        if i and find(i.source, 'SmoothAnimatedBars/', 1, true) and not find(i.source, 'harness', 1, true) then
            __synth = __synth + __w.lua * SAMPLE / 1000000
        end
    end
    sethook(hook, '', SAMPLE)
end
sethook(hook, '', SAMPLE)
""".replace("SAMPLE", str(SAMPLE))

EVENTS = """
    __fire('UNIT_HEALTH', 'player'); __fire('UNIT_POWER_UPDATE', 'player', 'RAGE')
    __fire('UNIT_HEALTH', 'target'); __fire('UNIT_POWER_UPDATE', 'target', 'MANA')"""


def run(addon, saved, scenario, fps, weights, pace=None):
    """The addon's /sab perf parts, played in the mock: {part: ms a frame by the modelled clock}."""
    lua = bench.session(addon, set(), {}, CLASS, 0, saved, pre=CLOCK)
    lua.execute("debug.sethook()")  # bench's own sampling
    lua.execute(METER)
    lua.execute("for k, v in pairs({%s}) do __w[k] = v end" % ", ".join(f"{k} = {weights.get(k, 0)!r}" for k in KINDS))
    if scenario == "notarget":
        lua.execute("__target = nil; __fire('PLAYER_TARGET_CHANGED')")
    step = lua.globals().__step
    fight = scenario == "fight"
    gap = 1 / (pace or PACE)

    def play(seconds):
        t, next_event = 0.0, 0.0
        while t < seconds:
            if fight and t >= next_event:
                next_event += gap
                lua.execute(EVENTS)
            step(1 / fps)
            t += 1 / fps
    play(SETTLE)
    if fight:
        lua.execute("__combat = true")
    lua.execute("SlashCmdList.SMOOTHANIMATEDBARS('perf rig')")
    play(PARTS_SECONDS)
    parts = lua.eval("""(function()
        local log = SmoothAnimatedBarsDB.perfLog
        local e = log and log[#log]
        local out = {}
        for _, p in ipairs(e and e.parts or {}) do out[p.part] = p.ms end
        return out
    end)()""")
    return {k: v for k, v in parts.items()}


def _job(args):
    global CLASS
    CLASS = args[-1]
    return args[:-1], run(*args[:-1])


def counts(addon, saved, conditions):
    """For each (scenario, fps): {part: [count a frame of each kind]}: one run per kind with only its cost at 1."""
    jobs = [(addon, saved, sc, fps, {k: 1.0}, PACE, CLASS) for sc, fps in conditions for k in KINDS]
    out = {}
    with ProcessPoolExecutor() as pool:
        for (a, s, sc, fps, w, _), parts in pool.map(_job, jobs):
            k = next(iter(w))
            per = out.setdefault((sc, fps), {})
            for part, ms in parts.items():
                per.setdefault(part, dict.fromkeys(KINDS, 0.0))[k] = ms * 1000  # back to a count a frame
    return out


def nnls(A, b, iters=20000):
    """Non-negative least squares by projected gradient (small problems: a handful of costs)."""
    x = np.maximum(np.linalg.lstsq(A, b, rcond=None)[0], 0)
    L = np.linalg.norm(A, 2) ** 2 or 1.0
    for _ in range(iters):
        x = np.maximum(x - (A.T @ (A @ x - b)) / L, 0)
    return x


def scenario_of(snap):
    secs = snap.get("seconds") or []
    units = max((s.get("units", 0) for s in secs), default=0)
    if snap.get("combat"):
        return "fight"
    return "idle" if units >= 4 else "notarget"


# /sab perf calib's methods, and how often the liquid calls each in a fight (bench.py --by method on a player's settings):
# a kind's cost is its methods' weighted so.
CALIB_SET = {"SetTexCoord": 120, "SetAlpha": 104, "SetPoint": 67, "SetVertexColor": 63, "SetSize": 41, "SetWidth": 39}
CALIB_GET = {"IsShown": 64, "IsVisible": 20, "GetWidth": 10}


def calib_instructions(reps):
    """Core.CalibLua's Lua 5.1 instructions for reps passes, counted exactly (a hook on every instruction) in the mock."""
    lua = bench.session(ADDON, set(), {}, CLASS, 0)
    lua.execute("debug.sethook()")
    return lua.eval("""(function()
        local pos, vel, n = __ns.Core.CalibInput()
        local c = 0
        debug.sethook(function() c = c + 1 end, '', 1)
        __ns.Core.CalibLua(pos, vel, n, %d)
        debug.sethook()
        return c
    end)()""" % reps)


def measured(saved):
    """The costs from the newest /sab perf calib in the saved variables, or None. The Lua round each call (the loop with
    rawequal in it) is taken off: the rig counts that as the addon's Lua."""
    cal = loader.load_log(saved, "perfCalib")
    if not cal:
        return None, None
    c = cal[-1]
    us = c["us"]
    loop = us.get("loop", 0)

    def avg(weights):
        have = {m: n for m, n in weights.items() if m in us}
        return max(0.0, sum((us[m] - loop) * n for m, n in have.items()) / sum(have.values()))

    costs = {"set": avg(CALIB_SET), "get": avg(CALIB_GET), "bar": max(0.0, us.get("SetValue", loop) - loop)}
    costs["other"], costs["api"] = costs["set"], costs["get"]  # not measured: like the setters, like a getter
    costs["lua"] = c["luaMs"] * 1000 / calib_instructions(c["luaReps"]) * 1000
    return costs, c


def calibrate(a):
    log = loader.load_log(a.saved)
    chosen = [s for s in log if s.get("parts") and (s.get("when") or "") >= (a.since or "")]
    known, calib = (None, None) if a.fit else measured(a.saved)
    if known:
        print(f"costs measured in game by /sab perf calib ({calib.get('when')}): "
              + ", ".join(f"{k} {v:.3f} us" + (" a 1000 instructions" if k == "lua" else " a call")
                          for k, v in known.items()))
        if not chosen:
            with open(CALIBRATION, "w", encoding="utf-8") as f:
                json.dump({"costs": known, "kinds": KINDS, "fits": [], "measured": calib.get("when")}, f, indent=1)
            print(f"no reports with every part timed to check them against; wrote {CALIBRATION}")
            return
    if not chosen:
        sys.exit("No saved report has every part timed since " + repr(a.since) + ": /sab perf in game, then /reload.")
    addon = gitref.export(a.ref) if a.ref else ADDON
    conds = sorted({(scenario_of(s), round((s.get("partsFrames") or 1000) / 10)) for s in chosen})
    print(f"{len(chosen)} reports, played back as {conds}; {len(conds) * len(KINDS)} runs in the mock...")
    table = counts(addon, a.saved, conds)
    rows, b, labels = [], [], []
    for s in chosen:
        key = (scenario_of(s), round((s.get("partsFrames") or 1000) / 10))
        per = table[key]
        for p in s["parts"]:
            name, ms = p.get("part"), p.get("ms", 0)
            if name not in per or ms <= 0:
                continue
            weight = 1 / max(ms, 0.02)  # each part by its share, so the big ones cannot drown the small
            rows.append([per[name][k] * weight for k in KINDS])
            b.append(ms * 1000 * weight)
            labels.append((s.get("when"), key, name, ms, per[name]))
    if known:
        costs = known  # the reports below only check them
    else:
        x = nnls(np.array(rows), np.array(b))
        costs = dict(zip(KINDS, (float(v) for v in x)))
        print("costs fitted: " + ", ".join(f"{k} {v:.2f} us" + (" a 1000 instructions" if k == "lua" else " a call")
                                           for k, v in costs.items()))
    fits = []
    print(f"\n{'report':20s} {'as':16s} {'part':36s} {'game ms':>8s} {'rig ms':>8s}")
    for when, key, name, ms, c in labels:
        pred = sum(c[k] * costs[k] for k in KINDS) / 1000
        fits.append({"when": when, "scenario": key[0], "fps": key[1], "part": name, "game": ms, "rig": pred})
        print(f"{when or '?':20s} {key[0] + ' ' + str(key[1]):16s} {name:36s} {ms:8.3f} {pred:8.3f}")
    with open(CALIBRATION, "w", encoding="utf-8") as f:
        json.dump({"costs": costs, "kinds": KINDS, "fits": fits, "since": a.since, "ref": a.ref,
                   "measured": calib.get("when") if known else None}, f, indent=1)
    print(f"\nwrote {CALIBRATION}")


def predict(a):
    if not os.path.exists(CALIBRATION):
        sys.exit("No calibration yet: rig.py calibrate.")
    costs = json.load(open(CALIBRATION, encoding="utf-8"))["costs"]
    now = run(ADDON, a.saved, a.scenario, a.fps, costs)
    before = run(gitref.export(a.ref), a.saved, a.scenario, a.fps, costs) if a.ref else None

    def total(parts):
        return sum(v for k, v in parts.items() if " > " not in k)
    print(f"{a.scenario} at {a.fps} fps, predicted in-game ms a frame (rig_calibration.json)")
    head = f"{'part':40s} {'now':>8s}" + (f" {a.ref:>8s}" if before else "")
    print(head)
    names = sorted(set(now) | set(before or {}), key=lambda k: -(now.get(k, 0)))
    for k in names:
        line = f"{k:40s} {now.get(k, 0):8.3f}"
        if before is not None:
            line += f" {before.get(k, 0):8.3f}"
        print(line)
    line = f"{'all parts':40s} {total(now):8.3f}"
    if before is not None:
        line += f" {total(before):8.3f}"
    print(line)
    frame = 1000 / a.fps
    print(f"that is {100 * total(now) / frame:.1f}% of each frame at {a.fps} fps"
          + (f" ({100 * total(before) / frame:.1f}% at {a.ref})" if before else ""))


def main():
    global PACE, CLASS
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("action", choices=("calibrate", "predict"))
    ap.add_argument("--saved", default=None, help="saved variables (default: the newest under Forever's WTF folder)")
    ap.add_argument("--since", default="", help="calibrate: reports made at or after this time (YYYY-MM-DD HH:MM)")
    ap.add_argument("--ref", default=None, help="calibrate: the code those reports ran; predict: compare against it")
    ap.add_argument("--scenario", default="fight", choices=("idle", "notarget", "fight"))
    ap.add_argument("--fps", type=float, default=100)
    ap.add_argument("--class", dest="cls", default=CLASS, help="the player's class (WARRIOR, MAGE, ROGUE...)")
    ap.add_argument("--pace", type=float, default=PACE, help="a fight's changes a second (health and power)")
    ap.add_argument("--fit", action="store_true",
                    help="calibrate: fit the costs to the reports even where /sab perf calib measured them")
    a = ap.parse_args()
    a.saved = a.saved or loader.find_saved()
    PACE = a.pace
    CLASS = a.cls.upper()
    calibrate(a) if a.action == "calibrate" else predict(a)


if __name__ == "__main__":
    main()
