"""What the liquid costs, without the game: widget calls per frame, by group of bars, quiet and in combat.

Usage: python bench.py <addon dir> [--fps 24] [--party 3] [--class WARRIOR] [--seconds 4]

The mock's own times say nothing about the client's, but the number of calls the liquid makes to the game's widgets
(SetPoint, SetAlpha, Show...) does: that is where the client spends its time. Matched against /sab perf in game (a
warrior in a party of four in combat, at 24 fps), each call cost about 1.7 to 2 microseconds there, so the estimate
column uses 1.9; it scales with the machine.

Each group is measured on its own, with only its settings on, in two states: quiet (nothing changing, so liquids idle)
and in combat (every unit's health and power changing ten times a second, as a fight's do, so liquids never settle).
"""
import argparse
import os
import sys

try:
    from lupa.luajit21 import LuaRuntime
except ImportError:  # some builds of lupa ship without LuaJIT
    from lupa.lua51 import LuaRuntime

HERE = os.path.dirname(os.path.abspath(__file__))
US_PER_CALL = 1.9
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


def session(addon, on, extra, cls, party):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(open(os.path.join(HERE, "wowmock.lua"), encoding="utf-8").read())
    settings = {k: k in on for k in BARS}
    settings.update(extra)
    settings.update({"setupDone": True, "heals": False, "manaBuild": False})
    saved = "{ " + ", ".join(f"{k} = {'true' if v else 'false'}" for k, v in settings.items()) + " }"
    index = POWER.get(cls, (0, "MANA"))[0]
    lua.execute(f"""
        __player.class, __player.power = {cls!r}, {index}
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
        __calls = 0
        local R = getmetatable(UIParent)
        for k, fn in pairs(R) do
            if type(fn) == 'function' and k ~= '__index' then
                R[k] = function(...) __calls = __calls + 1; return fn(...) end
            end
        end
    """)
    return lua


def measure(lua, combat, seconds, fps, party, token):
    step = lua.globals().__step
    lua.execute("__calls = 0")
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
    return lua.eval("__calls") / (seconds * fps)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("addon")
    ap.add_argument("--fps", type=float, default=24)
    ap.add_argument("--party", type=int, default=3, help="party members besides you (0 to 4)")
    ap.add_argument("--class", dest="cls", default="WARRIOR")
    ap.add_argument("--seconds", type=float, default=4)
    a = ap.parse_args()
    token = POWER.get(a.cls, (0, "MANA"))[1]
    print(f"{a.cls.lower()}, {a.party} party members, {a.fps:g} fps; estimate at {US_PER_CALL} us a call")
    print(f"{'':28s} {'quiet calls':>12s} {'combat calls':>13s} {'combat ms':>10s}")
    totals, base = [0, 0], {}
    for label, on, extra in GROUPS:
        if label.strip().endswith("fury") and a.cls != "WARRIOR":
            continue
        lua = session(a.addon, on, extra, a.cls, a.party if "party" in label else 0)
        measure(lua, False, 1.0, a.fps, 0, token)  # settle in
        quiet = measure(lua, False, a.seconds, a.fps, 0, token)
        combat = measure(lua, True, a.seconds, a.fps, a.party, token)
        if label.startswith("  "):  # the fury: what turning it on adds to the group above
            quiet, combat = quiet - base["quiet"], combat - base["combat"]
        else:
            base = {"quiet": quiet, "combat": combat}
        totals[0] += quiet
        totals[1] += combat
        print(f"{label:28s} {quiet:12.0f} {combat:13.0f} {combat * US_PER_CALL / 1000:10.2f}")
    print(f"{'total':28s} {totals[0]:12.0f} {totals[1]:13.0f} {totals[1] * US_PER_CALL / 1000:10.2f}")


if __name__ == "__main__":
    sys.exit(main())
