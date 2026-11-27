"""What the liquid costs, without the game: widget calls per frame, by group of bars, quiet and in combat.

Usage: python bench.py <addon dir> [--fps 60] [--party 3] [--class WARRIOR] [--seconds 4] [--max]
                       [--ref HEAD] [--by line|file|method|lua|luafile] [--only player] [--saved FILE] [--cap 60]

The mock's own times say nothing about the client's, but the number of calls the liquid makes to the game's widgets
(SetPoint, SetAlpha, Show...) does: that is where the client spends its time. Matched against /sab perf in game (a
warrior in a party of four in combat, at 24 fps), the whole cost came to about 1.7 to 2 microseconds a call there, so
the estimate column uses 1.9; it scales with the machine. That is all the work per call, the Lua around it too: a widget
call alone costs 0.15 to 0.35 microseconds (/sab perf calib), and rig.py splits the two. The "% frame" column is that estimate as a share of each frame at --fps:
a liquid that is moving is drawn every frame, so its cost per frame does not drop as the frame rate rises, and its share
of the frame grows with it. "Lua k" is the addon's own Lua work, thousands of Lua 5.1 instructions a frame (the client
runs Lua 5.1, not LuaJIT), counted in the addon's files only: work saved in widget calls must not come back here.

Each group is measured on its own, with only its settings on, in two states: quiet (nothing changing, so liquids idle)
and in combat (every unit's health and power changing ten times a second, as a fight's do, so liquids never settle).
Runs are repeatable (a fixed random seed and order, as samelook.py's), so --ref compares the working copy with the
addon at a git ref on exactly the same frames. --by breaks the combat calls of each group down by the line making them
or by widget method, or its Lua work by line (lua). --max sets Animation Speed and Wave Intensity to 200%.
"""
import argparse
import os
import sys

from lupa.lua51 import LuaRuntime

import gitref
import samelook

HERE = os.path.dirname(os.path.abspath(__file__))
US_PER_CALL = 1.9
SAMPLE = 100  # Lua instructions between samples of where the work is
BARS = ("playerHealth", "playerPower", "targetHealth", "targetPower", "petHealth", "petPower", "focusHealth",
        "focusPower", "totHealth", "totPower", "prdHealth", "prdPower", "partyHealth", "partyPower")
POWER = {"WARRIOR": (1, "RAGE"), "ROGUE": (3, "ENERGY"), "MAGE": (0, "MANA"), "PRIEST": (0, "MANA"),
         "DRUID": (0, "MANA"), "PALADIN": (0, "MANA"), "HUNTER": (0, "MANA"), "WARLOCK": (0, "MANA")}
# Each group: its label, the bars switched on, and other settings.
GROUPS = [
    ("player + target", {"playerHealth", "playerPower", "targetHealth", "targetPower"}, {"rageFury": False}),
    ("  their rage fury", {"playerHealth", "playerPower", "targetHealth", "targetPower"}, {"rageFury": True}),
    ("personal resource display", {"prdHealth", "prdPower"}, {"rageFury": False}),
    ("  its rage fury", {"prdHealth", "prdPower"}, {"rageFury": True}),
    ("party", {"partyHealth", "partyPower"}, {}),
]


def session(addon, on, extra, cls, party, saved_file=None, pre=None):
    """pre: Lua run after the mock and before the addon loads (rig.py's modelled clock)."""
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(open(os.path.join(HERE, "wowmock.lua"), encoding="utf-8").read())
    lua.execute(samelook.STABLE_PAIRS)
    lua.execute("math.randomseed(20261126)")
    if pre:
        lua.execute(pre)
    if saved_file:
        # A player's own saved variables (the account's settings, every feature as they have it), as the game loads them.
        lua.execute(open(saved_file, encoding="utf-8").read())
        saved = "SmoothAnimatedBarsDB"
        # Only the player and a target fighting them, as in a fight alone: the mock shows every frame otherwise.
        lua.execute("""for _, f in ipairs({ PetFrame, FocusFrame, TargetFrameToT, FocusFrameToT }) do
            if f then f:Hide() end
        end""")
    else:
        settings = {k: k in on for k in BARS}
        settings.update(extra)
        settings.update({"setupDone": True, "heals": False, "manaBuild": False})
        saved = "{ " + ", ".join(f"{k} = {samelook.lua_value(v)}" for k, v in settings.items()) + " }"
    index = POWER.get(cls, (0, "MANA"))[0]
    lua.execute(f"""
        __player.class, __player.power = {cls!r}, {index}
        __target = {{ guid = 'Creature-0-1-2-3-299-0001', name = 'Defias Pillager' }}
        if {'false' if saved_file else 'true'} then PersonalResourceDisplayFrame:Show() else PersonalResourceDisplayFrame:Hide() end
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
        -- Every widget call counted, by method and by the line making it (__byOn turns the breakdown on).
        __calls, __byM, __byL, __byOn = 0, {}, {}, false
        local R = getmetatable(UIParent)
        local getinfo, match = debug.getinfo, string.match
        for k, fn in pairs(R) do
            if type(fn) == 'function' and k ~= '__index' then
                R[k] = function(...)
                    __calls = __calls + 1
                    if __byOn then
                        __byM[k] = (__byM[k] or 0) + 1
                        local i = getinfo(2, 'Sl')
                        -- Called through pcall: the line that called pcall.
                        if i and i.what == 'C' then i = getinfo(3, 'Sl') end
                        local key = i and ((match(i.short_src, '[^/\\\\]+$') or '?') .. ':' .. (i.currentline or 0)) or '?'
                        __byL[key] = (__byL[key] or 0) + 1
                    end
                    return fn(...)
                end
            end
        end
        -- The addon's own Lua work: a sample every SAMPLE instructions, kept when it lands in one of the addon's files.
        -- In Lua 5.1 the hook's own instructions use up the count too, so the hook re-arms it as its last act: armed
        -- once, about two thirds of each SAMPLE went on the hook, which counted the addon's work three times over
        -- (and more where a sample took the hook's longer way), against a hook on every instruction.
        __luaSamples, __byLua, __byLuaFn = 0, {}, {}
        local find, sethook = string.find, debug.sethook
        local hook
        hook = function()
            local i = getinfo(2, 'Sl')
            if i and find(i.source, 'SmoothAnimatedBars/', 1, true) and not find(i.source, 'harness', 1, true) then
                __luaSamples = __luaSamples + 1
                if __byOn then
                    local file = match(i.short_src, '[^/\\\\]+$') or '?'
                    local key = file .. ':' .. (i.currentline or 0)
                    __byLua[key] = (__byLua[key] or 0) + 1
                    key = file .. ':' .. (i.linedefined or 0) -- the function, by the line it starts on
                    __byLuaFn[key] = (__byLuaFn[key] or 0) + 1
                end
            end
            sethook(hook, '', SAMPLE)
        end
        sethook(hook, '', SAMPLE)
    """.replace("SAMPLE", str(SAMPLE)))
    return lua


def measure(lua, combat, seconds, fps, party, token):
    step = lua.globals().__step
    lua.execute("__calls, __luaSamples = 0, 0")
    t, next_event = 0.0, 0.0
    while t < seconds:
        if combat and t >= next_event:
            next_event += 0.1
            lua.execute(f"""
                __fire('UNIT_HEALTH', 'player'); __fire('UNIT_POWER_UPDATE', 'player', {token!r})
                __fire('UNIT_HEALTH', 'target'); __fire('UNIT_POWER_UPDATE', 'target', 'MANA')
                for i = 1, {party} do
                    __fire('UNIT_HEALTH', 'party' .. i); __fire('UNIT_POWER_UPDATE', 'party' .. i, 'MANA')
                end""")
        step(1 / fps)
        t += 1 / fps
    frames = seconds * fps
    return lua.eval("__calls") / frames, lua.eval("__luaSamples") * SAMPLE / frames / 1000


def run(addon, a, token, by=None):
    """{label: (quiet calls, combat calls, combat Lua k)} for each group, a fury's being what it adds, and the
    breakdown of each group's combat calls if asked."""
    out, breakdown, base, keep = {}, {}, {}, True
    groups = [("your saved settings", set(), {})] if a.saved else GROUPS
    for label, on, extra in groups:
        if not label.startswith("  "):
            keep = not a.only or a.only in label
        if not keep or (label.strip().endswith("fury") and a.cls != "WARRIOR"):
            continue
        extra = dict(extra)
        if a.max:
            extra.update(samelook.MAX)
        lua = session(addon, on, extra, a.cls, a.party if "party" in label or a.saved else 0, a.saved)
        if getattr(a, "cap", None):
            lua.execute(f"if __ns.Liquid.SetFrameRate then __ns.Liquid.SetFrameRate({a.cap}) end")
        measure(lua, False, 1.0, a.fps, 0, token)  # settle in
        quiet, _ = measure(lua, False, a.seconds, a.fps, 0, token)
        if by:
            lua.execute("__byOn, __byM, __byL = true, {}, {}")
        combat, luak = measure(lua, True, a.seconds, a.fps, a.party, token)
        if by:
            frames = a.seconds * a.fps
            table = lua.eval({"line": "__byL", "file": "__byL", "method": "__byM", "lua": "__byLua",
                              "luafile": "__byLua", "luafn": "__byLuaFn"}[by])
            scale = SAMPLE / 1000 if by.startswith("lua") else 1  # Lua: thousands of instructions a frame
            rows = {}
            for k, v in table.items():
                if by in ("file", "luafile"):
                    k = k.rsplit(":", 1)[0]
                rows[k] = rows.get(k, 0) + v * scale / frames
            breakdown[label] = sorted(rows.items(), key=lambda kv: -kv[1])
        if label.startswith("  "):  # the fury: what turning it on adds to the group above
            quiet, combat, luak = quiet - base["quiet"], combat - base["combat"], luak - base["luak"]
        else:
            base = {"quiet": quiet, "combat": combat, "luak": luak}
        out[label] = (quiet, combat, luak)
    return out, breakdown


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("addon")
    ap.add_argument("--fps", type=float, default=60)
    ap.add_argument("--party", type=int, default=3, help="party members besides you (0 to 4)")
    ap.add_argument("--class", dest="cls", default="WARRIOR")
    ap.add_argument("--seconds", type=float, default=4)
    ap.add_argument("--max", action="store_true", help="Animation Speed and Wave Intensity at 200%%")
    ap.add_argument("--ref", help="also measure the addon at this git ref and show the change")
    ap.add_argument("--by", choices=("line", "file", "method", "lua", "luafile", "luafn"),
                    help="break each group's combat calls down by line, file or method, or its Lua work by line, file "
                         "or function (luafn, by the line the function starts on)")
    ap.add_argument("--saved", help="a SmoothAnimatedBars.lua saved variables file: one group, with those settings")
    ap.add_argument("--cap", type=int, help="Animation Frame Rate: moving liquids updated at most this often")
    ap.add_argument("--only", help="only the groups whose label contains this (with their fury)")
    a = ap.parse_args()
    token = POWER.get(a.cls, (0, "MANA"))[1]
    print(f"{a.cls.lower()}, {a.party} party members, {a.fps:g} fps{', effects at 200%' if a.max else ''}; "
          f"estimate at {US_PER_CALL} us a call")
    now, breakdown = run(a.addon, a, token, a.by)
    # The same --by at the ref: breaking the work down by line changes where the Lua samples land (about a tenth fewer in
    # the addon's files), so a ref measured without it made a change look that much better than it was.
    before = run(gitref.export(a.ref), a, token, a.by)[0] if a.ref else None
    frame_ms = 1000 / a.fps

    def row(label, q, c, k):
        ms = c * US_PER_CALL / 1000
        return f"{label:28s} {q:8.0f} {c:9.0f} {ms:7.2f} {100 * ms / frame_ms:7.1f}% {k:7.1f}"

    head = f"{'':28s} {'quiet':>8s} {'combat':>9s} {'ms':>7s} {'frame':>8s} {'Lua k':>7s}"
    print(head)
    totals = [0.0, 0.0, 0.0]
    for label, (q, c, k) in now.items():
        print(row(label, q, c, k))
        totals = [totals[0] + q, totals[1] + c, totals[2] + k]
    print(row("total", *totals))
    if before:
        print(f"\nat {a.ref}:")
        print(head)
        old = [0.0, 0.0, 0.0]
        for label, (q, c, k) in before.items():
            print(row(label, q, c, k))
            old = [old[0] + q, old[1] + c, old[2] + k]
        print(row("total", *old))
        pct = [(n - o) / o * 100 if o else 0 for n, o in zip(totals, old)]
        print(f"\nchange: quiet calls {pct[0]:+.0f}%, combat calls {pct[1]:+.0f}%, combat Lua work {pct[2]:+.0f}%")
    what = "Lua k" if a.by and a.by.startswith("lua") else "calls"
    by = {"lua": "line", "luafile": "file", "luafn": "function"}.get(a.by, a.by)
    for label, rows in breakdown.items():
        print(f"\n{label.strip()}, combat {what} a frame by {by}:")
        for k, v in rows[:15]:
            print(f"    {k:36s} {v:8.1f}")


if __name__ == "__main__":
    sys.exit(main())
