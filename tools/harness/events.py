"""What the addon's event handlers cost: each kind of event a fight brings, and a burst of them in one frame, counted
exactly (a hook on every Lua instruction run in the addon's files), on a player's saved settings.

    python events.py ../../SmoothAnimatedBars [--saved FILE] [--class WARRIOR] [--by 12] [--ref HEAD] [--detail]

The liquid's per-frame work is bench.py's and rig.py's; this is the other half of a slow frame: in game the slowest
frames of a fight were bursts of events landing in one frame (DoT tracking up to 1.1 ms, the bars' events 0.8, heal
tracking 0.5; docs/findings/performance.md). --by N lists the N costliest functions of the burst; --ref measures the
addon at a git ref on the same events beside it.
"""
import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, ".."))
import bench  # noqa: E402
import gitref  # noqa: E402
import perf_report  # noqa: E402

# Spells a warrior's fight casts (descriptions as the client words them), so the casts' readers have text to read.
SPELLS = r"""
__spells[78] = { 'Heroic Strike', 'A strong attack that increases melee damage by 11 and causes a high amount of threat.' }
__spells[772] = { 'Rend', 'Wounds the target causing them to bleed for 15 damage over 9 sec.' }
__spells[6343] = { 'Thunder Clap', 'Blasts nearby enemies increasing the time between their attacks by 10% for 10 sec and doing 10 damage to them.' }
"""

# One of each kind of event a 1v1 brings, by name (fired in order; the burst fires them all in one frame).
KINDS = [
    ("swing on the target (UNIT_COMBAT)", "__fire('UNIT_COMBAT', 'target', 'WOUND', '', 23, 1)"),
    ("its nameplate's copy", "__fire('UNIT_COMBAT', 'nameplate1', 'WOUND', '', 23, 1)"),
    ("swing on the player", "__fire('UNIT_COMBAT', 'player', 'WOUND', '', 9, 1)"),
    ("target health", "__fire('UNIT_HEALTH', 'target')"),
    ("its nameplate's health", "__fire('UNIT_HEALTH', 'nameplate1')"),
    ("player health", "__fire('UNIT_HEALTH', 'player')"),
    ("player rage", "__fire('UNIT_POWER_UPDATE', 'player', 'RAGE')"),
    ("target power", "__fire('UNIT_POWER_UPDATE', 'target', 'MANA')"),
    ("target auras", "__fire('UNIT_AURA', 'target', { isFullUpdate = true })"),
    ("player auras", "__fire('UNIT_AURA', 'player', { isFullUpdate = true })"),
    ("cast sent (Rend)", "__castN = __castN + 1; __fire('UNIT_SPELLCAST_SENT', 'player', 'Mob', 'Cast-' .. __castN, 772)"),
    ("cast succeeded (Rend)", "__fire('UNIT_SPELLCAST_SUCCEEDED', 'player', 'Cast-' .. __castN, 772)"),
    ("cast sent (Heroic Strike)", "__castN = __castN + 1; __fire('UNIT_SPELLCAST_SENT', 'player', 'Mob', 'Cast-' .. __castN, 78)"),
    ("cast succeeded (Heroic Strike)", "__fire('UNIT_SPELLCAST_SUCCEEDED', 'player', 'Cast-' .. __castN, 78)"),
]

COUNTER = r"""
__evIns, __evFn = 0, {}
local getinfo, find, match = debug.getinfo, string.find, string.match
function __evOn(byFn)
    __evIns, __evFn = 0, {}
    debug.sethook(function()
        local i = getinfo(2, 'S')
        if i and find(i.source, 'SmoothAnimatedBars/', 1, true) and not find(i.source, 'harness', 1, true) then
            __evIns = __evIns + 1
            if byFn then
                local key = (match(i.short_src, '[^/\\]+$') or '?') .. ':' .. (i.linedefined or 0)
                __evFn[key] = (__evFn[key] or 0) + 1
            end
        end
    end, '', 1)
end
function __evOff() debug.sethook() return __evIns end
"""


def session(addon, saved, cls):
    lua = bench.session(addon, set(), {}, cls, 0, saved)
    lua.execute("debug.sethook()")
    lua.execute(SPELLS + COUNTER + "__castN = 0; __combat = true")
    step = lua.globals().__step
    for _ in range(120):  # settle in, a fight going
        step(1 / 60)
    return lua, step


def measure(addon, saved, cls, by):
    lua, step = session(addon, saved, cls)
    out = []
    for name, code in KINDS:
        lua.execute("__evOn(true)")
        lua.execute(code)
        n = lua.eval("__evOff()")
        fns = lua.eval("__evFn")
        out.append((name, n, sorted(((k, fns[k]) for k in fns.keys()), key=lambda kv: -kv[1])[:4]))
        for _ in range(6):  # a few frames between, as in game
            step(1 / 60)
    for _ in range(60):
        step(1 / 60)
    lua.execute("__evOn(true)")
    for _, code in KINDS:
        lua.execute(code)
    burst = lua.eval("__evOff()")
    fns = lua.eval("__evFn")
    top = sorted(((k, fns[k]) for k in fns.keys()), key=lambda kv: -kv[1])[:by]
    return out, burst, top


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("addon")
    ap.add_argument("--saved", default=None, help="saved variables (default: the newest under Forever's WTF folder)")
    ap.add_argument("--class", dest="cls", default="WARRIOR")
    ap.add_argument("--by", type=int, default=12)
    ap.add_argument("--ref")
    ap.add_argument("--detail", action="store_true", help="each costly event's four costliest functions")
    ap.add_argument("--lua-us", type=float, default=28.0, help="us a thousand instructions in game (rig_calibration)")
    a = ap.parse_args()
    saved = a.saved or perf_report.find_saved()
    now, burst, top = measure(a.addon, saved, a.cls, a.by)
    before = measure(gitref.export(a.ref), saved, a.cls, a.by) if a.ref else None
    us = a.lua_us / 1000
    print(f"{'event':36s} {'instructions':>12s} {'us in game':>10s}" + (f" {'at ' + a.ref:>14s}" if before else ""))
    for i, (name, n, fns) in enumerate(now):
        extra = f" {before[0][i][1]:14d}" if before else ""
        print(f"{name:36s} {n:12d} {n * us:10.1f}{extra}")
        if a.detail and n >= 1000:
            print("      " + ", ".join(f"{k} {c}" for k, c in fns))
    print(f"{'all of them in one frame':36s} {burst:12d} {burst * us:10.1f}" + (f" {before[1]:14d}" if before else ""))
    print(f"\nthe burst's costliest functions (file:line the function starts on):")
    for k, n in top:
        print(f"   {n:8d}  {k}")


if __name__ == "__main__":
    main()
