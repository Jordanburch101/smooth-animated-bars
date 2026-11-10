"""Tests: the liquid on the unit frame bars, the settings page, slash commands and every theme,
against the WoW mock of the Forever client, where health and power are secret.

Usage: python test.py <addon dir>
Prints each check and exits 1 if any fails (a Lua error also fails with a traceback).
"""
import json
import os
import sys

try:
    from lupa.luajit21 import LuaRuntime
except ImportError:  # some builds of lupa ship without LuaJIT; WoW's Lua is 5.1 either way
    from lupa.lua51 import LuaRuntime

ADDON = sys.argv[1].replace("\\", "/")
HERE = os.path.dirname(os.path.abspath(__file__))
failures = []


def check(ok, what):
    print(f"  {'ok  ' if ok else 'FAIL'} {what}")
    if not ok:
        failures.append(what)


# Helpers in Lua: our frames on a game bar, and what the liquid on it is showing.
HELPERS = """
    -- The liquid's frames on a bar: the first StatusBar and clipping frame of ours on it (the game's own heal
    -- prediction segments there do not clip). It builds them before the markers build their own there.
    function __ours(bar)
        local proxy, clip, mover
        for _, f in ipairs(__frames) do
            if f.parent == bar then
                if f.SetValue then proxy = proxy or f elseif f.clipsChildren then clip = clip or f end
            end
        end
        for _, f in ipairs(__frames) do
            if clip and f.parent == clip then mover = f end
        end
        return proxy, clip, mover
    end
    function __liquid(bar)
        local _, clip, mover = __ours(bar)
        local n, shown, masked, free = 0, 0, 0, 0
        for _, r in ipairs(__regions) do
            if mover and r.parent == mover and r.kind == "Texture" then
                n = n + 1
                if r.shown and clip.shown then shown = shown + 1 end
                if r.masks and #r.masks > 0 then masked = masked + 1 else free = free + 1 end
            end
        end
        return n, shown, bar.fill.alpha, masked, free
    end
    -- The colour at the liquid's front, from the first slice of the front that shows.
    function __tint(bar)
        local _, _, mover = __ours(bar)
        for _, r in ipairs(__regions) do
            if r.parent == mover and r.shown and r.grad then return r.grad[2][1], r.grad[2][2], r.grad[2][3] end
        end
    end
    function __motes(bar)
        local _, _, mover = __ours(bar)
        local n = 0
        for _, r in ipairs(__regions) do
            if r.parent == mover and r.shown and r.layer == "OVERLAY" and r.sub == 4 then n = n + 1 end
        end
        return n
    end
    function __bars() return { PlayerFrame.healthbar, PlayerFrame.manabar, TargetFrame.healthbar, TargetFrame.manabar } end
"""


def session(saved="{ setupDone = true }", setup=""):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(open(os.path.join(HERE, "wowmock.lua"), encoding="utf-8").read())
    lua.execute(HELPERS)
    # As on Forever: every bar's value and range is secret.
    lua.execute("""
        for _, b in ipairs(__bars()) do b:SetMinMaxValues(0, __secret()); b:SetValue(__secret()) end
        __player.power = 1
        SmoothAnimatedBarsDB = """ + saved)
    lua.execute(setup)
    lua.globals().__ns = lua.globals().__loadAddon(ADDON, "SmoothAnimatedBars")
    lua.execute("__fire('ADDON_LOADED', 'SmoothAnimatedBars'); __fire('PLAYER_ENTERING_WORLD', true, false)")
    return lua


def run(lua, seconds):
    step = lua.globals().__step
    for _ in range(int(seconds * 60)):
        step(1 / 60)


def chat(lua):
    return list(lua.globals().__chat.values())


print("== liquid on the bars")
lua = session()
run(lua, 1)
n, shown, alpha, masked, free = lua.eval("__liquid(PlayerFrame.healthbar)")
check(n > 0 and shown > 0 and alpha == 0,
      f"on by default: liquid on the player's health bar with its values secret, game fill hidden ({shown}/{n}, alpha {alpha})")
check(masked > 0 and free == 64, f"liquid cut to the bar's mask, motes left free ({masked} masked, {free} free)")
check(lua.eval("""(function()
    local _, _, mover = __ours(PlayerFrame.healthbar)
    local mask = PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.HealthBarMask
    for _, r in ipairs(__regions) do
        if r.parent == mover and r.masks and r.masks[1] == mask then return true end
    end
end)()"""), "player health takes the mask on the bar's container")
check(lua.eval("""(function()
    local _, _, mover = __ours(PlayerFrame.manabar)
    for _, r in ipairs(__regions) do
        if r.parent == mover and r.masks and r.masks[1] == PlayerFrame.manabar.ManaBarMask then return true end
    end
end)()"""), "power takes the mana bar's own mask")
check(lua.eval("""(function()
    local proxy, clip, mover = __ours(PlayerFrame.healthbar)
    local a = mover.points.TOPRIGHT
    return a and a.rel == proxy.fill and a.relPoint == "TOPRIGHT" and mover.w == 124
        and mover.useParentLevel and clip.useParentLevel
end)()"""), "liquid frame ends on the hidden bar's fill edge, a bar wide, at the bar's level")
check(lua.eval("""(function()
    local _, clip = __ours(PlayerFrame.healthbar)
    local tl, br = clip.points.TOPLEFT, clip.points.BOTTOMRIGHT
    return clip.clipsChildren and tl.rel == PlayerFrame.healthbar and tl.x == 0 and tl.y > 0 and br.x > 0 and br.y < 0
end)()"""), "clip frame starts at the bar's left edge, with room above, below and past the end")
loss = "PlayerFrame.healthbar.AnimatedLossBar"
check(lua.eval(f"{loss}.fill.alpha") == 0, "the game's red health-loss bar is hidden with the fill")
lua.execute(f"{loss}:Show(); {loss}:SetValue(__secret()); {loss}.fill:SetAlpha(1)")
run(lua, 0.05)
check(lua.eval(f"{loss}.fill.alpha") == 0, "and stays hidden when the game shows it after damage (it would cover the liquid)")
lua.execute(f"{loss}:Hide()")
lua.execute("PlayerFrame.healthbar:SetValue(__secret())")
run(lua, 0.2)
check(lua.eval("""(function()
    local proxy = __ours(PlayerFrame.healthbar)
    return proxy.value == PlayerFrame.healthbar.value and proxy.max == PlayerFrame.healthbar.max
        and proxy.interpolation == Enum.StatusBarInterpolation.ExponentialEaseOut
end)()"""), "the hidden bar takes the game bar's secret value, smoothed")
check(all(lua.eval(f"(select(2, __liquid(__bars()[{i}])))") > 0 for i in range(1, 5)),
      "all four bars: player health and power, target health and power")
run(lua, 3)
before = lua.eval("__motes(PlayerFrame.healthbar)")
lua.execute("__fire('UNIT_HEALTH', 'player')")
run(lua, 0.1)
after = lua.eval("__motes(PlayerFrame.healthbar)")
check(after > before, f"a health change stirs the liquid ({before} then {after} motes)")
r, g, b = lua.eval("__tint(PlayerFrame.manabar)")
check(r > 0.5 and b < 0.3, f"game colour: rage liquid is red ({r:.2f}, {g:.2f}, {b:.2f})")
r, g, b = lua.eval("__tint(PlayerFrame.healthbar)")
check(g > 0.5 and r < 0.4, f"game colour: health liquid is green ({r:.2f}, {g:.2f}, {b:.2f})")
lua.execute("__player.power = 0; __fire('UNIT_DISPLAYPOWER', 'player')")
run(lua, 0.2)
r, g, b = lua.eval("__tint(PlayerFrame.manabar)")
check(r < 0.3 and b > 0.5, f"shifting to mana turns the liquid blue ({r:.2f}, {g:.2f}, {b:.2f})")
bad = lua.eval("""(function()
    local bad = {}
    for _, r in ipairs(__regions) do
        local f = r.file
        if r.kind == "Texture" and f and f ~= "SOLID" and not f:find("^Interface\\\\AddOns\\\\SmoothAnimatedBars\\\\Media\\\\") then
            bad[#bad + 1] = f
        end
    end
    return table.concat(bad, ", ")
end)()""")
check(not bad, f"no textures loaded from game paths (Forever often fails to load them) {bad or ''}")
media = os.path.join(ADDON, "Media")
missing = lua.eval("""(function()
    local seen = {}
    for _, r in ipairs(__regions) do
        if r.file and r.file ~= "SOLID" then seen[r.file:match("([^\\\\]+)$")] = true end
    end
    local out = {}
    for name in pairs(seen) do out[#out + 1] = name end
    return table.concat(out, ",")
end)()""")
gone = [m for m in missing.split(",") if m and not os.path.exists(os.path.join(media, m + ".tga"))]
check(not gone, f"every texture the liquid uses is in Media/ {gone}")
lua.execute("SlashCmdList.SMOOTHANIMATEDBARS('debug')")
dbg = [m for m in chat(lua) if "value secret" in m and ("|r player " in m or "|r target " in m)]
check(len(dbg) == 4 and all("live yes" in m and "mask yes" in m and "error" not in m for m in dbg),
      f"/sab debug reports each bar ({len(dbg)} lines)")
check(not any("Error in" in m for m in chat(lua)), "no errors")

print("== settings")
rows = lua.eval("__settingsRows()")
rows = [rows[i] for i in range(1, len(rows) + 1)]
keys = [r.key for r in rows if r.key]
check(keys == ["playerHealth", "healthColor", "playerPower", "powerColor", "targetHealth", "targetHealthColor",
               "targetPower", "targetPowerColor", "mobClassColor", "petHealth", "petHealthColor", "petPower",
               "petPowerColor", "focusHealth", "focusHealthColor", "focusPower", "focusPowerColor", "totHealth",
               "totHealthColor", "totPower", "totPowerColor", "plateHealth", "plateHealthColor", "plateDots", "plateFriendly", "plateFriendlyColor", "mobClassColor",
               "waves", "swirl", "bubbles", "sparkles", "ambient", "lightning", "dots", "dotKillIcon", "heals", "manaBuild"],
      f"settings page rows: {keys}")
check(not lua.eval("__sharedListTainted"), "nothing added to the game's shared settings list (Forever: Social blocked)")
options = [o for o in rows if o.key == "healthColor"][0].options
labels = [options[i].label for i in range(1, len(options) + 1)]
check(labels[0] == "Game Colour" and "Class Color" in labels and "Item Quality" not in labels and len(labels) == 26,
      f"colour choices: game colour then the themes, without Item Quality ({len(labels)})")
lua.execute("__settings.playerHealth:SetValue(false)")
run(lua, 0.2)
check(lua.eval("(select(2, __liquid(PlayerFrame.healthbar)))") == 0 and lua.eval("PlayerFrame.healthbar.fill.alpha") == 1
      and lua.eval("PlayerFrame.healthbar.AnimatedLossBar.fill.alpha") == 1
      and lua.eval("(select(2, __liquid(PlayerFrame.manabar)))") > 0,
      "turning one bar off gives it back its own fill and loss animation, and leaves the others")
lua.execute("__settings.playerHealth:SetValue(true)")
run(lua, 0.2)
check(lua.eval("(select(2, __liquid(PlayerFrame.healthbar)))") > 0, "and on again")
lua.execute("__settings.healthColor:SetValue('class')")
run(lua, 0.2)
r, g, b = lua.eval("__tint(PlayerFrame.healthbar)")
check(r > 0.8 and b > 0.5, f"class colour: a paladin's health is pink ({r:.2f}, {g:.2f}, {b:.2f})")
r, g, b = lua.eval("__tint(PlayerFrame.manabar)")
check(r < 0.3 and b > 0.5, "power keeps its own choice")
lua.execute("__settings.waves:SetValue(false); __settings.bubbles:SetValue(false); __settings.lightning:SetValue(false)")
run(lua, 1)
check(lua.eval("""(function()
    local _, _, mover = __ours(PlayerFrame.healthbar)
    for _, r in ipairs(__regions) do
        if r.parent == mover and r.shown and r.layer == "OVERLAY" and r.sub == 3 then return false end
    end
    return true
end)()"""), "effects switched off: no bubbles")
lua.execute("SlashCmdList.SMOOTHANIMATEDBARS('off')")
run(lua, 0.2)
check(all(lua.eval(f"__bars()[{i}].fill.alpha") == 1 for i in range(1, 5))
      and lua.eval("SmoothAnimatedBarsDB.targetPower") is False, "/sab off: all four bars back to the game's, saved")
lua.execute("SlashCmdList.SMOOTHANIMATEDBARS('on')")
run(lua, 0.2)
check(all(lua.eval(f"(select(2, __liquid(__bars()[{i}])))") > 0 for i in range(1, 5)), "/sab on: liquid again")
lua.execute("SlashCmdList.SMOOTHANIMATEDBARS('')")
check(lua.eval("__openedCategory") == "Smooth Animated Bars", "/sab opens the settings page")
lua.execute("__closeSettings(); __combat = true; __openedCategory = nil; SlashCmdList.SMOOTHANIMATEDBARS('')")
check(lua.eval("__openedCategory") is None, "not opened in combat")
lua.execute("__combat = false; __fire('PLAYER_REGEN_ENABLED')")
check(lua.eval("__openedCategory") == "Smooth Animated Bars", "opened once combat ends")

print("== target colours")
tc = session()
tc.execute("""
    __player.class = 'PALADIN'
    __settings.healthColor:SetValue('class')
    function __aim(t) __target = t; __fire('PLAYER_TARGET_CHANGED') end
""")
run(tc, 0.2)
check(tc.eval("SmoothAnimatedBarsDB.targetHealthColor") == "same" and tc.eval("SmoothAnimatedBarsDB.mobClassColor") == "reaction",
      "the target follows the player's choice by default, and mobs show their reaction")


def mob_row(lua):
    rows = lua.eval("__settingsRows()")
    return [rows[i] for i in range(1, len(rows) + 1) if rows[i].key == "mobClassColor"][0]


check(mob_row(tc).frame.shown and mob_row(tc).indent, "Class Color on Mobs shows, indented, while the target follows Class Color")
tc.execute("__aim({ guid = 'Player-1', name = 'Friend', isOtherPlayer = true, class = 'MAGE' })")
run(tc, 0.2)
r, g, b = tc.eval("__tint(TargetFrame.healthbar)")
check(b > 0.8 and r < 0.5, f"Class Color: a targeted mage's health is a mage's blue ({r:.2f}, {g:.2f}, {b:.2f})")
r, g, b = tc.eval("__tint(PlayerFrame.healthbar)")
check(r > 0.8 and b > 0.5, f"and the player's own stays the player's ({r:.2f}, {g:.2f}, {b:.2f})")
tc.execute("__aim({ guid = 'Player-2', name = 'Other', isOtherPlayer = true, class = 'DRUID' })")
run(tc, 0.2)
r, g, b = tc.eval("__tint(TargetFrame.healthbar)")
check(r > 0.8 and b < 0.3, f"a new target recolours the bar ({r:.2f}, {g:.2f}, {b:.2f})")
tc.execute("__aim({ guid = 'Creature-1', name = 'Boar', class = 'MAGE', reaction = 2 })")
run(tc, 0.2)
r, g, b = tc.eval("__tint(TargetFrame.healthbar)")
check(r > 0.7 and g < 0.4, f"a hostile mob by reaction: red ({r:.2f}, {g:.2f}, {b:.2f})")
tc.execute("__aim({ guid = 'Creature-2', name = 'Guard', reaction = 5 })")
run(tc, 0.2)
r, g, b = tc.eval("__tint(TargetFrame.healthbar)")
check(g > 0.7 and r < 0.5, f"a friendly one: green ({r:.2f}, {g:.2f}, {b:.2f})")
tc.execute("__aim({ guid = 'Creature-1', name = 'Boar', class = 'MAGE', reaction = 2 }); __settings.mobClassColor:SetValue('class')")
run(tc, 0.2)
r, g, b = tc.eval("__tint(TargetFrame.healthbar)")
check(b > 0.8 and r < 0.5, f"Mob's Class: the class the game gives it ({r:.2f}, {g:.2f}, {b:.2f})")
tc.execute("__settings.mobClassColor:SetValue('game')")
run(tc, 0.2)
r, g, b = tc.eval("__tint(TargetFrame.healthbar)")
check(g > 0.7 and r < 0.4, f"Game Colour: a mob keeps the game's green ({r:.2f}, {g:.2f}, {b:.2f})")
tc.execute("__aim({ guid = 'Player-1', name = 'Friend', isOtherPlayer = true, class = 'MAGE' })")
run(tc, 0.2)
r, g, b = tc.eval("__tint(TargetFrame.healthbar)")
check(b > 0.8 and r < 0.5, f"while a player still shows their class ({r:.2f}, {g:.2f}, {b:.2f})")
tc.execute("__aim({ guid = 'Creature-1', name = 'Boar', class = 'MAGE', reaction = 2 })")
tc.execute("__settings.mobClassColor:SetValue('own')")
run(tc, 0.2)
r, g, b = tc.eval("__tint(TargetFrame.healthbar)")
check(r > 0.8 and b > 0.5, f"Your Class: the player's own ({r:.2f}, {g:.2f}, {b:.2f})")
tc.execute("__settings.targetHealthColor:SetValue('fire')")
run(tc, 0.2)
r, g, b = tc.eval("__tint(TargetFrame.healthbar)")
pr, pg, pb = tc.eval("__tint(PlayerFrame.healthbar)")
check(r > 0.8 and b < 0.3 and pb > 0.5, f"the target's health has its own choice, without touching the player's ({r:.2f}, {g:.2f}, {b:.2f})")
check(not mob_row(tc).frame.shown, "with no Class Color on the target, Class Color on Mobs is hidden")
tc.execute("__player.power = 0; __fire('UNIT_DISPLAYPOWER', 'target')")
run(tc, 0.2)
mr_, mg_, mb_ = tc.eval("__tint(TargetFrame.manabar)")
check(mb_ > 0.5, "and its power keeps its own")
tc.execute("__settings.targetHealthColor:SetValue('class'); __settings.mobClassColor:SetValue('reaction')")
check(mob_row(tc).frame.shown, "and back with it")
tc.execute("__aim({ guid = 'Player-3', name = 'Hidden', isOtherPlayer = true, class = __secret() })")
run(tc, 0.2)
r, g, b = tc.eval("__tint(TargetFrame.healthbar)")
check(g > 0.7 and r < 0.4 and not any("Error" in m for m in chat(tc)),
      f"a class kept secret: the game's colour, no error ({r:.2f}, {g:.2f}, {b:.2f})")
lua5 = session("{ setupDone = true, targetHealthColor = 'gone', mobClassColor = 'gone' }")
check(lua5.eval("SmoothAnimatedBarsDB.targetHealthColor") == "same" and lua5.eval("SmoothAnimatedBarsDB.mobClassColor") == "reaction",
      "unknown saved choices fall back")

print("== pet, focus and target of target")
sf = session()
run(sf, 0.3)
small = {"PetFrameHealthBar": "pet health", "PetFrameManaBar": "pet power", "TargetFrameToT.HealthBar": "target of target health",
         "TargetFrameToT.ManaBar": "target of target power", "FocusFrame.healthbar": "focus health",
         "FocusFrame.manabar": "focus power", "FocusFrameToT.HealthBar": "focus's target health",
         "FocusFrameToT.ManaBar": "focus's target power"}
for path in small:
    sf.execute(f"local b = {path}; b:SetMinMaxValues(0, __secret()); b:SetValue(__secret())")
run(sf, 0.3)
live = [name for path, name in small.items() if sf.eval(f"(select(2, __liquid({path})))") > 0]
check(len(live) == 8, f"liquid in all eight small bars, on their secret values ({live})")
check(all(sf.eval(f"(select(4, __liquid({path})))") > 0 for path in small),
      "each cut by its own mask: the pet's named after its bar, the others on the bar")
check(sf.eval("PetFrameHealthBar.fill.alpha") == 0 and sf.eval("TargetFrameToT.HealthBar.fill.alpha") == 0,
      "the game's fill hidden under it")
check(sf.eval("__ns.Bars.Find('playerHealth') == PlayerFrame.healthbar")
      and sf.eval("__ns.Bars.Find('targetPower') == TargetFrame.manabar"), "the player's and target's bars are still the ones found")


def row(lua, key):
    rows = lua.eval("__settingsRows()")
    return [rows[i] for i in range(1, len(rows) + 1) if rows[i].key == key][0]


check(row(sf, "petHealthColor").frame.shown and row(sf, "petHealthColor").indent,
      "settings: each bar's colour shows indented under it while the bar is on")
sf.execute("__settings.petHealth:SetValue(false)")
run(sf, 0.2)
check(sf.eval("(select(2, __liquid(PetFrameHealthBar)))") == 0 and sf.eval("PetFrameHealthBar.fill.alpha") == 1
      and sf.eval("(select(2, __liquid(PetFrameManaBar)))") > 0 and sf.eval("(select(2, __liquid(PlayerFrame.healthbar)))") > 0,
      "Pet Health off: the pet's health bar is the game's again, its power and yours stay")
check(not row(sf, "petHealthColor").frame.shown and row(sf, "petPowerColor").frame.shown, "and its colour option goes")
sf.execute("__settings.petHealth:SetValue(true); __settings.totPower:SetValue(false)")
run(sf, 0.2)
check(sf.eval("(select(2, __liquid(TargetFrameToT.ManaBar)))") == 0 and sf.eval("(select(2, __liquid(FocusFrameToT.ManaBar)))") == 0
      and sf.eval("(select(2, __liquid(TargetFrameToT.HealthBar)))") > 0 and sf.eval("(select(2, __liquid(FocusFrame.manabar)))") > 0,
      "Target of Target Power off: both targets of target's power, not their health or the focus's")
sf.execute("__settings.totPower:SetValue(true)")
sf.execute("""
    __player.class = 'PALADIN'
    __settings.healthColor:SetValue('class')
    __units.targettarget = { isOtherPlayer = true, class = 'MAGE' }
    __units.focus = { class = 'MAGE', reaction = 2 }
    __fire('UNIT_TARGET', 'target'); __fire('PLAYER_FOCUS_CHANGED')
""")
run(sf, 0.3)
r, g, b = sf.eval("__tint(TargetFrameToT.HealthBar)")
check(b > 0.8 and r < 0.5, f"Same as Target, the target following yours, Class Color: the target's target shows its class ({r:.2f}, {g:.2f}, {b:.2f})")
r, g, b = sf.eval("__tint(FocusFrame.healthbar)")
check(r > 0.7 and g < 0.4, f"a hostile mob as focus, by reaction ({r:.2f}, {g:.2f}, {b:.2f})")
r, g, b = sf.eval("__tint(PetFrameHealthBar)")
check(r > 0.8 and b > 0.5, f"the pet, Same as Yours, takes your class colour ({r:.2f}, {g:.2f}, {b:.2f})")
sf.execute("__units.targettarget = { reaction = 5 }; __fire('UNIT_TARGET', 'target')")
run(sf, 0.3)
r, g, b = sf.eval("__tint(TargetFrameToT.HealthBar)")
check(g > 0.7 and r < 0.5, f"the target changing its target recolours it: a friendly mob ({r:.2f}, {g:.2f}, {b:.2f})")
sf.execute("__settings.targetHealthColor:SetValue('fire')")
run(sf, 0.2)
r, g, b = sf.eval("__tint(FocusFrame.healthbar)")
pr, pg, pb = sf.eval("__tint(PetFrameHealthBar)")
check(r > 0.8 and b < 0.3 and pb > 0.5, "the focus follows the target's Fire; the pet keeps yours")
sf.execute("__settings.focusHealthColor:SetValue('frost'); __settings.petHealthColor:SetValue('fire')")
run(sf, 0.2)
r, g, b = sf.eval("__tint(FocusFrame.healthbar)")
tr, tg, tb = sf.eval("__tint(TargetFrameToT.HealthBar)")
pr, pg, pb = sf.eval("__tint(PetFrameHealthBar)")
hr, hg, hb = sf.eval("__tint(PlayerFrame.healthbar)")
check(b > 0.8 and tr > 0.8 and tb < 0.3 and pr > 0.8 and pb < 0.3 and hb > 0.5,
      "each frame's own colour: the focus Frost, the target of target still the target's Fire, the pet Fire, you yours")
before = sf.eval("__motes(PetFrameHealthBar)")
sf.execute("__fire('UNIT_HEALTH', 'pet')")
run(sf, 0.05)
check(sf.eval("__motes(PetFrameHealthBar)") > before, "a change to the pet's health stirs its liquid")
check(not any("Error" in m for m in chat(sf)), "no errors")

print("== a bar whose size is kept secret")
ss = session("{ setupDone = true, dots = true }")
ss.execute("__target = { guid = 'Creature-0-1-2-3-299-0001', name = 'Mottled Boar' }; __fire('PLAYER_TARGET_CHANGED')")
run(ss, 0.5)
ss.execute("""
    for _, b in ipairs({ TargetFrame.healthbar, PlayerFrame.healthbar }) do b.w, b.h = __secret(), __secret() end
""")
run(ss, 1)
check(not any("Error" in m for m in chat(ss)), "the client keeping the bars' size secret (seen in game): no error")
check(ss.eval("(select(2, __liquid(TargetFrame.healthbar)))") > 0 and ss.eval("(select(2, __liquid(PlayerFrame.healthbar)))") > 0,
      "the liquid carries on at the size it last knew")
ss.execute("TargetFrame.healthbar.w, TargetFrame.healthbar.h = 140, 20")
run(ss, 0.5)
check(ss.eval("__ns.Bars.Liquid(TargetFrame.healthbar).width") == 150, "and follows the size again once it can read it")

print("== unit frame menus")
um = session()
check(um.eval("__menuCallbacks['MENU_UNIT_SELF'] ~= nil and __menuCallbacks['MENU_UNIT_TARGET'] ~= nil "
              "and __menuCallbacks['MENU_UNIT_PET'] ~= nil and __menuCallbacks['MENU_UNIT_FOCUS'] ~= nil"),
      "added to the player, target, pet and focus frames' menus through Menu.ModifyMenu")
items = um.eval("__openUnitMenu('SELF', { ownerFrame = PlayerFrame, unit = 'player', fromPlayerFrame = true })")
kinds = [(items[i].kind, items[i].text) for i in range(1, len(items) + 1)]
check(kinds == [("divider", None), ("title", "Smooth Animated Bars"), ("button", "Open Settings")],
      f"right-clicking your frame: a divider, the addon's name and Open Settings ({kinds})")
um.execute("__closeSettings(); __openedCategory = nil")
items[3].onClick()
check(um.eval("__openedCategory") == "Smooth Animated Bars", "which opens the settings")
um.execute("__closeSettings(); __openedCategory = nil; __combat = true")
items[3].onClick()
check(um.eval("__openedCategory") is None, "in combat it waits")
um.execute("__combat = false; __fire('PLAYER_REGEN_ENABLED')")
check(um.eval("__openedCategory") == "Smooth Animated Bars", "and opens once combat ends")
for which, frame in (("TARGET", "TargetFrame"), ("ENEMY_PLAYER", "TargetFrame"), ("PET", "PetFrame"), ("FOCUS", "FocusFrame")):
    got = um.eval(f"#__openUnitMenu('{which}', {{ ownerFrame = {frame}, unit = 'target' }})")
    check(got == 3, f"{which} menu from {frame}: added")
check(um.eval("#__openUnitMenu('PLAYER', { name = 'Somebody' })") == 0
      and um.eval("#__openUnitMenu('PARTY', { ownerFrame = UIParent, unit = 'party1' })") == 0,
      "a player's menu from a chat name or a party frame: left alone")
um.execute("""
    __closeSettings()
    for _, f in ipairs(__frames) do
        if f.scrollChild and f.parent == __settingsCategory.frame then __page = f end
    end
    __page.h = 300
    function __headerY(title)
        for _, r in ipairs(__regions) do
            local init = r.initializer
            if r.rowTemplate and init and init.kind == 'header' and init.data.name == title then
                for _, p in pairs(r.points) do return -p.y end
            end
        end
    end
""")
for which, frame, section in (("PET", "PetFrame", "Pet"), ("FOCUS", "FocusFrame", "Focus"), ("SELF", "PlayerFrame", "Player")):
    um.execute(f"__closeSettings(); local items = __openUnitMenu('{which}', {{ ownerFrame = {frame} }}); items[3].onClick(items[3])")
    run(um, 0.1)
    got, want = um.eval("__page:GetVerticalScroll()"), um.eval(f"__headerY('{section}')") - 10
    check(abs(got - max(0, want)) < 0.5, f"from the {frame} menu the settings open at {section} (scrolled to {got}, header at {want})")
um.execute("__closeSettings(); __combat = true; local items = __openUnitMenu('TARGET', { ownerFrame = TargetFrame }); items[3].onClick(items[3])")
um.execute("__combat = false; __fire('PLAYER_REGEN_ENABLED')")
run(um, 0.1)
got, want = um.eval("__page:GetVerticalScroll()"), um.eval("__headerY('Target')") - 10
check(abs(got - want) < 0.5, f"and from the target's in combat, at Target once combat ends ({got}, {want})")
check(not any("Error" in m for m in chat(um)), "no errors")

print("== every theme")
lua2 = session()
rows2 = lua2.eval("__settingsRows()")
options = [rows2[i] for i in range(1, len(rows2) + 1) if rows2[i].key == "powerColor"][0].options
keys = [options[i].value for i in range(1, len(options) + 1)]
broken = []
for key in keys:
    lua2.execute(f"__settings.healthColor:SetValue('{key}'); __settings.powerColor:SetValue('{key}')")
    lua2.execute("__fire('UNIT_HEALTH', 'player'); __fire('UNIT_POWER_UPDATE', 'player')")
    run(lua2, 0.5)
    if lua2.eval("(select(2, __liquid(PlayerFrame.healthbar)))") == 0:
        broken.append(key)
check(not broken and not any("Error in" in m for m in chat(lua2)), f"all {len(keys)} colour choices draw ({broken})")

print("== saved settings")
lua3 = session("{ setupDone = true, playerPower = false, healthColor = 'gone', waves = false }")
run(lua3, 0.5)
check(lua3.eval("(select(2, __liquid(PlayerFrame.manabar)))") == 0 and lua3.eval("PlayerFrame.manabar.fill.alpha") == 1,
      "a bar switched off stays off after a reload")
check(lua3.eval("SmoothAnimatedBarsDB.healthColor") == "game" and lua3.eval("SmoothAnimatedBarsDB.waves") is False
      and lua3.eval("SmoothAnimatedBarsDB.sparkles") is True, "an unknown theme falls back to the game colour; defaults fill gaps")
lua4 = session(setup="PlayerFrame = nil; TargetFrame = nil")
check(any("Could not find 4" in m for m in chat(lua4)), "missing unit frames are reported, not an error")

print("== setup wizard")
wz = session("nil", "__combat = true")
run(wz, 3)
check(not wz.eval("SmoothAnimatedBarsSetup and SmoothAnimatedBarsSetup.shown"), "first login: not opened in combat")
wz.execute("__combat = false")
run(wz, 6)
check(wz.eval("SmoothAnimatedBarsSetup.shown") and wz.eval("__ns.Wizard.State().page") == "bars",
      "first login: opens once out of combat, on the bars step")
wz.execute("""
    function __card(field, key) return __ns.Wizard.State().ui.cards[field][key] end
    function __pick(field, key) local c = __card(field, key); c.scripts.OnClick(c) end
    function __press(name) local b = __ns.Wizard.State().ui[name]; b.scripts.OnClick(b) end
""")
check(wz.eval("__card('bars', 'all').radio.checked") and not wz.eval("__card('bars', 'mine').radio.checked")
      and wz.eval("__ns.Wizard.State().ui.step.text") == "Step 1 of 6"
      and not wz.eval("__ns.Wizard.State().ui.back:IsEnabled()"),
      "starts from the current settings: all four bars picked, step 1 of 6, no Back")
wz.execute("__pick('bars', 'mine')")
run(wz, 0.2)
check(wz.eval("SmoothAnimatedBarsDB.targetHealth") is False
      and wz.eval("(select(2, __liquid(TargetFrame.healthbar)))") == 0
      and wz.eval("(select(2, __liquid(PlayerFrame.healthbar)))") > 0 and wz.eval("__card('bars', 'mine').radio.checked"),
      "Just mine: applied at once, target bars back to the game's")
check(wz.eval("__settings.targetHealth:GetValue()") is False, "picks go through the settings controls")
wz.execute("__press('next'); __pick('healthColor', 'fire')")
run(wz, 0.2)
r, g, b = wz.eval("__tint(PlayerFrame.healthbar)")
check(wz.eval("__ns.Wizard.State().page") == "colors" and wz.eval("SmoothAnimatedBarsDB.healthColor") == "fire"
      and r > 0.8 and b < 0.3, f"colours: Fire on health shows at once ({r:.2f}, {g:.2f}, {b:.2f})")
check(wz.eval("__card('powerColor', 'game').radio.checked") and not wz.eval("__card('healthColor', 'game').radio.checked"),
      "each row shows its own pick")
wz.execute("__press('next')")
check(wz.eval("__ns.Wizard.State().page") == "targetColors" and not wz.eval("__card('mobClassColor', 'reaction').shown"),
      "the target's colours: its own step, the Mobs row hidden with no Class Color on the target")
wz.execute("__pick('targetHealthColor', 'class')")
check(not wz.eval("__card('mobClassColor', 'own').shown"),
      "Class Color on the target's health, but its bars off (Just mine): still no Mobs row")
wz.execute("__ns.Core.SetSetting('targetHealth', true); __pick('mobClassColor', 'own')")
run(wz, 0.2)
check(wz.eval("SmoothAnimatedBarsDB.targetHealthColor") == "class" and wz.eval("__card('mobClassColor', 'own').shown")
      and wz.eval("SmoothAnimatedBarsDB.mobClassColor") == "own" and wz.eval("__card('targetPowerColor', 'same').radio.checked")
      and wz.eval("__card('mobClassColor', 'own').radio.checked") and wz.eval("SmoothAnimatedBarsDB.healthColor") == "fire",
      "Class Color brings the Mobs row; each row its own pick, the player's untouched")
wz.execute("__press('next'); __pick('effects', 'still')")
check(wz.eval("SmoothAnimatedBarsDB.waves") is False and wz.eval("SmoothAnimatedBarsDB.sparkles") is False
      and wz.eval("__ns.Wizard.State().ui.next.text") == "Next", "effects: Still turns them off")
wz.execute("__press('next')")
check(wz.eval("__ns.Wizard.State().page") == "dots" and wz.eval("__card('dots', 'off').radio.checked")
      and wz.eval("__ns.Wizard.State().ui.next.text") == "Next",
      "DoTs: Off picked as the setting starts")
wz.execute("__pick('dots', 'marker')")
check(wz.eval("SmoothAnimatedBarsDB.dots") is True and wz.eval("SmoothAnimatedBarsDB.dotKillIcon") is False
      and wz.eval("__ns.Dots.IsEnabled()") and wz.eval("__card('dots', 'marker').radio.checked"),
      "Just the marker: tracking on at once, no skull")
wz.execute("__press('next')")
check(wz.eval("__ns.Wizard.State().page") == "plates" and wz.eval("__card('plates', 'off').radio.checked")
      and wz.eval("__card('friends', 'off').radio.checked") and wz.eval("__ns.Wizard.State().ui.next.text") == "Finish"
      and wz.eval("__ns.Wizard.State().ui.step.text") == "Step 6 of 6",
      "Nameplates: the last step, both rows Off as the settings start, says Finish")
PP = "__ns.Wizard.State().ui.platePreview"
check(wz.eval(PP + ".shown") and not wz.eval("__ns.Wizard.State().ui.preview.shown") and wz.eval("#" + PP + ".plates") == 4,
      "the preview strip shows four example nameplates instead of the unit frames")
check(wz.eval("(select(2, __liquid(" + PP + ".plates[1])))") == 0 and wz.eval(PP + ".plates[1].fill.alpha") == 1,
      "with nameplates off they show the game's own bar")
wz.execute("__showPlate('nameplate1', { reaction = 2 }); __pick('plates', 'dots'); __pick('friends', 'on')")
run(wz, 0.3)
check(wz.eval("SmoothAnimatedBarsDB.plateHealth") is True and wz.eval("SmoothAnimatedBarsDB.plateDots") is True
      and wz.eval("SmoothAnimatedBarsDB.plateFriendly") is True
      and wz.eval("(select(2, __liquid(__plates.nameplate1.UnitFrame.HealthBarsContainer.healthBar)))") > 0
      and wz.eval("__card('plates', 'dots').radio.checked") and wz.eval("__card('friends', 'on').radio.checked"),
      "With your DoTs and friends on: applied at once, the mob's nameplate takes the liquid")
check(all(wz.eval("(select(2, __liquid(" + PP + ".plates[%d])))" % i) > 0 for i in (1, 2, 3, 4))
      and wz.eval(PP + ".marker.live") and wz.eval(PP + ".plates[1].state.mask ~= nil")
      and wz.eval("(select(2, __ours(" + PP + ".plates[1]))).useParentLevel") is False,
      "and the example plates follow: the liquid in all four, the plate mask, a level above the bar, the DoTs live")
run(wz, 2.5)
check(wz.eval(PP + ".marker.clip.shown"), "the target's DoTs show on its example plate as the loop plays")
wz.execute("__press('back')")
check(wz.eval("__ns.Wizard.State().ui.preview.shown") and not wz.eval(PP + ".shown"),
      "Back to the DoT step: the unit frames again")
wz.execute("__press('next')")
wz.execute("__pick('plates', 'liquid')")
check(wz.eval("SmoothAnimatedBarsDB.plateDots") is False and wz.eval("__card('plates', 'liquid').radio.checked"),
      "Liquid alone: the DoTs on nameplates off")
wz.execute("__pick('plates', 'off')")
check(wz.eval("SmoothAnimatedBarsDB.plateHealth") is False and wz.eval("__card('plates', 'off').radio.checked")
      and wz.eval("(select(2, __liquid(__plates.nameplate1.UnitFrame.HealthBarsContainer.healthBar)))") == 0,
      "Off: the nameplate back to the game's bar")
wz.execute("__press('skip')")
check(not wz.eval("SmoothAnimatedBarsSetup.shown") and wz.eval("SmoothAnimatedBarsDB.targetHealth") is True
      and wz.eval("SmoothAnimatedBarsDB.healthColor") == "game" and wz.eval("SmoothAnimatedBarsDB.waves") is True
      and wz.eval("SmoothAnimatedBarsDB.targetHealthColor") == "same" and wz.eval("SmoothAnimatedBarsDB.mobClassColor") == "reaction"
      and wz.eval("SmoothAnimatedBarsDB.dots") is False and not wz.eval("__ns.Dots.IsEnabled()")
      and wz.eval("SmoothAnimatedBarsDB.plateFriendly") is False and wz.eval("SmoothAnimatedBarsDB.plateDots") is False
      and wz.eval("SmoothAnimatedBarsDB.setupDone") is True, "Skip puts every setting back and does not ask again")
run(wz, 0.2)
check(wz.eval("(select(2, __liquid(TargetFrame.healthbar)))") > 0, "and the bars follow")
wz.execute("__fire('PLAYER_ENTERING_WORLD', false, true)")
run(wz, 3)
check(not wz.eval("SmoothAnimatedBarsSetup.shown"), "not opened again on the next login")
wz.execute("SlashCmdList.SMOOTHANIMATEDBARS('setup')")
wz.execute("__pick('bars', 'health'); __press('next'); __pick('powerColor', 'class'); __press('next'); __press('next');"
           " __pick('effects', 'gentle'); __press('next'); __pick('dots', 'both'); __press('next');"
           " __pick('plates', 'liquid'); __press('next')")
check(not wz.eval("SmoothAnimatedBarsSetup.shown") and wz.eval("SmoothAnimatedBarsDB.playerPower") is False
      and wz.eval("SmoothAnimatedBarsDB.powerColor") == "class" and wz.eval("SmoothAnimatedBarsDB.swirl") is True
      and wz.eval("SmoothAnimatedBarsDB.bubbles") is False and wz.eval("SmoothAnimatedBarsDB.dots") is True
      and wz.eval("SmoothAnimatedBarsDB.dotKillIcon") is True and wz.eval("SmoothAnimatedBarsDB.plateHealth") is True
      and any("All set" in m for m in chat(wz)),
      "/sab setup, then Finish keeps the choices")
wz.execute("SlashCmdList.SMOOTHANIMATEDBARS('setup'); __pick('effects', 'full'); SmoothAnimatedBarsSetup:Hide()")
check(wz.eval("SmoothAnimatedBarsDB.bubbles") is False, "closing the window (Escape) is Skip")
rows_wz = wz.eval("__settingsRows()")
button = [rows_wz[i] for i in range(1, len(rows_wz) + 1) if rows_wz[i].name == "Setup Wizard"]
check(bool(button), "Setup Wizard button on the settings page")
if button:
    button[0].onClick()
check(wz.eval("SmoothAnimatedBarsSetup.shown"), "which opens it")
check(not any("Error in" in m for m in chat(wz)), "no errors")

print("== wizard previews")
pv = session("nil")
run(pv, 3)
pv.execute("""
    function __pv(which, kind) return __ns.Wizard.State().ui.preview[which][kind] end
    function __pick(field, key) local c = __ns.Wizard.State().ui.cards[field][key]; c.scripts.OnClick(c) end
""")
check(pv.eval("SmoothAnimatedBarsSetup.shown"), "wizard open with its previews")
check(all(pv.eval(f"(select(2, __liquid(__pv('{w}', '{k}'))))") > 0
          for w in ("player", "target") for k in ("health", "power")),
      "liquid on all four preview bars")
check(pv.eval("__pv('player', 'health').HealthBarMask.atlas") == "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health-Mask"
      and pv.eval("__pv('target', 'power').ManaBarMask.atlas") == "UI-HUD-UnitFrame-Target-PortraitOn-Bar-Mana-Mask",
      "preview bars take Forever's bar masks by atlas name")
check(pv.eval("(select(4, __liquid(__pv('player', 'health'))))") > 0, "the preview liquid is cut by them")
check(pv.eval("__pv('player', 'health').text.text") == "271 / 271", "bar text as on the game's frame")
check(pv.eval("""(function()
    for _, r in ipairs(__regions) do
        if r.kind == "FontString" and r.text == "Hotdog Hootsman" and r ~= PlayerName then return true end
    end
end)()"""), "the player preview shows the name as the game's frame does, surname included")
r, g, b = pv.eval("__tint(__pv('player', 'power'))")
check(r > 0.5 and b < 0.3, f"player preview power takes your power type (rage: {r:.2f}, {g:.2f}, {b:.2f})")
before = pv.eval("__pv('player', 'health').shownValue")
run(pv, 0.35)  # the loop's first hit lands 1.2 s after the wizard opens
after = pv.eval("__pv('player', 'health').shownValue")
check(after < before and pv.eval("__motes(__pv('player', 'health'))") > 0,
      f"the loop plays a hit: {before} then {after}, and the liquid stirs")
pv.execute("__pick('bars', 'mine')")
run(pv, 0.2)
check(pv.eval("(select(2, __liquid(__pv('target', 'health'))))") == 0 and pv.eval("__pv('target', 'health').fill.alpha") == 1
      and pv.eval("(select(2, __liquid(__pv('player', 'health'))))") > 0,
      "Just mine: the target preview shows the game's plain bars")
pv.execute("__pick('bars', 'all'); __ns.Wizard.State().ui.next.scripts.OnClick(__ns.Wizard.State().ui.next); __pick('healthColor', 'frost')")
run(pv, 0.2)
r, g, b = pv.eval("__tint(__pv('target', 'health'))")
check(b > 0.8 and r < 0.8, f"Frost on health shows on the target preview too ({r:.2f}, {g:.2f}, {b:.2f})")
pv.execute("__settings.dots:SetValue(true); function __pm() return __ns.Wizard.State().ui.preview.marker end")
for _ in range(600):
    run(pv, 1 / 60)
    if pv.eval("__pm().value") == 58:
        break
run(pv, 0.2)
check(pv.eval("__pm().clip.shown") and pv.eval("__pm().value") == 58 and pv.eval("__pm().killBar.max") == 53
      and pv.eval("__pm().killBar.value") == 58 and pv.eval("__pm().window.shown"),
      "DoTs on: the target preview plays two DoTs that will kill it, marker and skull showing")
check(pv.eval("__pm().liquids[1].themeKey") == "shadow" and pv.eval("__pm().liquids[2].themeKey") == "fire"
      and pv.eval("__pm().liquids[2].pool.shown"), "the preview shows Corruption as Shadow and Immolate as Fire")
check(pv.eval("__pm().window.points.CENTER.rel == __ns.Wizard.State().ui.preview.target.portrait"),
      "the skull sits on the preview's portrait")
for _ in range(300):
    run(pv, 1 / 60)
    if not pv.eval("__pm().clip.shown"):
        break
check(not pv.eval("__pm().clip.shown") and not pv.eval("__pm().window.shown"), "and both go when the target dies")
pv.execute("SmoothAnimatedBarsSetup:Hide()")
run(pv, 0.5)
check(not pv.eval("SmoothAnimatedBarsSetup.shown") and pv.eval("SmoothAnimatedBarsDB.healthColor") == "game"
      and pv.eval("SmoothAnimatedBarsDB.dots") is False,
      "closing the wizard: previews hidden with it, settings back")
check(not any("Error in" in m for m in chat(pv)), "no errors")

# A client without one of the atlases: that piece is left out, the liquid still shows.
pm = session("nil", "__missingAtlases['UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health-Mask'] = true;"
                    " __missingAtlases['UI-HUD-UnitFrame-Player-PortraitOn'] = true")
run(pm, 3)
pm.execute("function __pv(which, kind) return __ns.Wizard.State().ui.preview[which][kind] end")
check(pm.eval("SmoothAnimatedBarsSetup.shown") and pm.eval("(select(2, __liquid(__pv('player', 'health'))))") > 0
      and pm.eval("__pv('player', 'health').HealthBarMask") is None and not any("Error in" in m for m in chat(pm)),
      "a missing atlas leaves that piece out: no mask, liquid uncut, no error")

print("== DoT marker")
dm = session("{ setupDone = true, heals = false, manaBuild = false }")
run(dm, 0.5)
check(dm.eval("SmoothAnimatedBarsDB.dots") is False and not dm.eval("__ns.Dots.IsEnabled()")
      and dm.eval("(__ns.Marker.State())") is None, "off by default: no tracking, no marker built")
LISTENING = """(function()
    for _, f in ipairs(__frames) do
        for e in pairs(f.events) do
            if e:find('^UNIT_SPELLCAST') or e == 'UNIT_COMBAT' then return true end
        end
    end
    return false
end)()"""
check(not dm.eval(LISTENING), "and no combat or cast events listened to")
dm.execute("__settings.dots:SetValue(true)")
check(dm.eval("__ns.Dots.IsEnabled()") and dm.eval("__ns.Marker.State() ~= nil") and dm.eval(LISTENING),
      "on: tracking, and a marker on the target's health bar")
dm.execute("""
    __spells[172] = { 'Corruption', 'Corrupts the target, causing 90 Shadow damage over 18 sec.' }
    __spells[348] = { 'Immolate', 'Burns the enemy for 11 Fire damage and then an additional 20 Fire damage over 15 sec.' }
    __spells[1752] = { 'Sinister Strike', 'An instant strike that causes 3 damage in addition to your normal weapon damage. Awards 1 combo point.' }
    function __m() return (__ns.Marker.State()) end
    function __total() return (__ns.Dots.Target()) end
    function __cast(id, guid)
        __fire('UNIT_SPELLCAST_SENT', 'player', __target and __target.name or '', guid, id)
        __fire('UNIT_SPELLCAST_SUCCEEDED', 'player', guid, id)
    end
    __target = { guid = 'Creature-0-1-2-3-299-0001', name = 'Mottled Boar' }
    __fire('PLAYER_TARGET_CHANGED')
""")
run(dm, 0.3)
check(not dm.eval("__m().clip.shown") and not dm.eval("__m().window.shown"), "a target without DoTs: nothing shown")
dm.execute("__cast(1752, 'Cast-0')")
run(dm, 0.3)
check(dm.eval("__total()") == 0 and not dm.eval("__m().clip.shown"), "a strike that is not a DoT: nothing shown")
dm.execute("function __d(i) return __m().liquids[i] end")
dm.execute("__cast(172, 'Cast-1')")
run(dm, 0.15)
check(dm.eval("__d(1).liquid.energy") > 0.3, "a DoT landing splashes the DoT liquid")
run(dm, 1)
check(dm.eval("__total()") == 90 and dm.eval("__m().clip.shown") and dm.eval("__d(1).themeKey") == "shadow"
      and dm.eval("__d(1).pool.shown") and not dm.eval("__d(2).pool.shown"),
      "Corruption: 90 damage to come, shown as one Shadow liquid")
check(dm.eval("__d(1).run.max == TargetFrame.healthbar.max") and dm.eval("__d(1).run.value") == 90
      and dm.eval("__d(2).run.value") == 90 and dm.eval("__d(1).run.reverse"),
      "its running total takes the health bar's secret range, its value the DoT's damage, filling back from the front")
check(dm.eval("__d(1).run.points.TOPRIGHT.rel == __m().proxy.fill")
      and dm.eval("__m().proxy.value == TargetFrame.healthbar.value")
      and dm.eval("__m().clip.clipsChildren") and dm.eval("__m().clip.parent == TargetFrame.healthbar"),
      "on the front of a hidden bar fed the health bar's secret value, clipped from the bar's left edge")
check(dm.eval("__d(1).mover.points.TOPRIGHT.rel == __m().proxy.fill") and dm.eval("__d(1).mover.w") == 124
      and dm.eval("__d(1).pool.clipsChildren") and dm.eval("__d(1).pool.points.TOPLEFT.rel == __d(1).fill")
      and dm.eval("__d(1).pool.points.TOPLEFT.x") == -6,
      "the DoT liquid hangs on the health's edge, cut a little under where it ends")
check(dm.eval("""(function()
    local _, _, green = __ours(TargetFrame.healthbar)
    local a = green.points.TOPRIGHT
    return a.rel == __m().endFill and a.relPoint == 'TOPLEFT'
end)()"""), "the health liquid's front moves back to where the health will end")
LAYERS = """(function(i)
    local m, mask = __m(), TargetFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBarMask
    local masked, free, top = 0, 0, -99
    for _, t in ipairs(m.liquids[i].liquid.textures) do
        if t.masks and t.masks[1] == mask then masked = masked + 1 else free = free + 1 end
        if t.layer == 'ARTWORK' and t.sub > top then top = t.sub end
    end
    local d = m.liquids[i]
    return masked > 0 and free == 64 and m.clip.useParentLevel and d.pool.useParentLevel and d.mover.useParentLevel
        and top
end)"""
check(dm.eval(LAYERS + "(1)") == -3 and dm.eval(LAYERS + "(2)") == 2,
      "cut by the bar's mask, motes free, at the bar's level; under the health liquid (sublevels 3 to 7), "
      "the second DoT liquid over the first")
check(dm.eval("issecretvalue(__m().killBar.max)") and dm.eval("__m().killBar.value") == 90 and dm.eval("__m().window.shown")
      and dm.eval("__m().window.points.CENTER.rel == TargetFrame.TargetFrameContainer.Portrait")
      and dm.eval("__m().window.clipsChildren"),
      "the kill icon's bar takes the target's secret health against the damage, clipped on the portrait")
check(dm.eval("__m().icon.atlas") == "UI-HUD-UnitFrame-Target-HighLevelTarget_Icon" and dm.eval("__m().icon.h") == 30,
      "the kill icon is the game's own skull, by atlas")
check(dm.eval("__m().window.level") == dm.eval("TargetFrame:GetFrameLevel()") + 20, "the kill icon just above the target frame")
run(dm, 1.85)  # Corruption's first tick, 3 s after the cast
before = dm.eval("__d(1).liquid.energy")
dm.execute("__fire('UNIT_COMBAT', 'target', 'WOUND', '', 16, 32)")
run(dm, 0.3)
check(dm.eval("__total()") == 80 and dm.eval("SmoothAnimatedBarsDB.dotTicks[172]") == 16,
      f"a tick of 16 is learned: 5 ticks left, 80 to come ({dm.eval('__total()')})")
check(dm.eval("__d(1).liquid.energy") > before, "and the tick ripples the DoT liquid")
dm.execute("__fire('UNIT_COMBAT', 'target', 'WOUND', '', 120, 1)")
run(dm, 0.3)
check(dm.eval("__total()") == 80, "a melee hit is not taken for a tick")
dm.execute("__cast(348, 'Cast-2')")
run(dm, 1)
check(dm.eval("__total()") == 100 and dm.eval("__d(1).run.value") == 80 and dm.eval("__d(2).run.value") == 100
      and dm.eval("__d(1).themeKey") == "shadow" and dm.eval("__d(2).themeKey") == "fire" and dm.eval("__d(2).pool.shown"),
      "Immolate's 20 more: Corruption stays Shadow at the front, Immolate a Fire liquid of its own behind it")
check(dm.eval("__d(2).mover.points.TOPRIGHT.rel == __d(1).fill") and dm.eval("__d(2).mover.points.TOPRIGHT.relPoint") == "TOPLEFT"
      and dm.eval("__d(2).pool.points.TOPLEFT.rel == __d(2).fill") and dm.eval("__d(2).pool.points.TOPLEFT.x") == -6
      and dm.eval("__d(2).pool.points.BOTTOMRIGHT.rel == __d(1).fill") and dm.eval("__d(2).pool.points.BOTTOMRIGHT.x") == 10,
      "the Fire liquid hangs on the end of the Shadow one, its waves reaching over it")
dm.execute("__settings.targetHealth:SetValue(false)")
run(dm, 0.3)
check(dm.eval("__d(1).liquid.body.sub") == 3 and dm.eval("__d(2).liquid.body.sub") == 3
      and dm.eval("__d(1).pool.points.TOPLEFT.x") == 0 and dm.eval("__d(2).pool.points.BOTTOMRIGHT.x") == 0
      and dm.eval("__m().clip.shown"),
      "health liquid off: the DoT liquids lie over the game's fill instead, side by side, cut at their ends")
dm.execute("__settings.targetHealth:SetValue(true)")
run(dm, 0.3)
check(dm.eval("__d(1).liquid.body.sub") == -7 and dm.eval("__d(2).liquid.body.sub") == -2,
      "and go back under the liquid when it is on again")
dm.execute("__settings.dotKillIcon:SetValue(false)")
run(dm, 0.3)
check(not dm.eval("__m().window.shown") and dm.eval("__m().clip.shown"), "Kill Icon off: the marker without the skull")
dm.execute("__target = nil; __fire('PLAYER_TARGET_CHANGED')")
run(dm, 0.3)
check(not dm.eval("__m().clip.shown"), "no target: marker hidden")
dm.execute("__target = { guid = 'Creature-0-1-2-3-299-0001', name = 'Mottled Boar' }; __fire('PLAYER_TARGET_CHANGED')")
run(dm, 0.15)
grow = dm.eval("__d(2).run.value")
run(dm, 1)
check(dm.eval("__m().clip.shown") and grow < dm.eval("__d(2).run.value") and abs(dm.eval("__d(2).run.value") - dm.eval("__total()")) < 1,
      f"back on the boar: its DoTs again, the DoT liquid growing in ({grow:.0f} then {dm.eval('__total()')})")
dm.execute("__target.dead = true")
run(dm, 0.3)
check(not dm.eval("__m().clip.shown"), "a dead target: marker hidden")
# Rend, as seen in game: Forever keeps hit amounts secret, so no tick is ever seen. White swings land and are
# parried around it.
dm.execute("""
    __spells[6546] = { 'Rend', 'Wounds the target causing them to bleed for 28 damage over 12 sec.' }
    __target = { guid = 'Creature-0-1-2-3-524-0002', name = 'Rockhide Boar' }
    __fire('PLAYER_TARGET_CHANGED')
    __cast(6546, 'Cast-3')
""")
run(dm, 0.3)
dm.execute("__fire('UNIT_COMBAT', 'target', 'PARRY', '', 0, 1)")
for _ in range(3):
    run(dm, 2.2)
    dm.execute("__fire('UNIT_COMBAT', 'target', 'WOUND', '', __secret(), 1)")
run(dm, 0.5)  # 7.4 s after the cast: two ticks left
check(dm.eval("__total()") == 14 and dm.eval("__m().clip.shown"),
      f"Rend with hit amounts secret: no tick is seen, but it is not dropped, and runs down on time ({dm.eval('__total()')})")
check(any("Hit amounts are secret" in m for m in dm.eval("__ns.Dots.Debug(40)").values()),
      "and the tracking says why")
# The hit flags (crits): readable on Forever, unlike the amounts. /sab dots counts what the target's hits show,
# readable or secret, and only under the target's token (the same hit comes again under its nameplate's).
dm.execute("""
    __fire('UNIT_COMBAT', 'target', 'WOUND', 'CRITICAL', __secret(), 1)
    __fire('UNIT_COMBAT', 'nameplate1', 'WOUND', 'CRITICAL', __secret(), 1)
    __fire('UNIT_COMBAT', 'target', 'WOUND', __secret(), __secret(), 1)
""")
run(dm, 0.05)
jet = dm.eval("__m().liquids[1].liquid.jet")
check(dm.eval("__m().liquids[1].themeKey") == "blood" and jet is not None and jet.density > 1,
      "a crit on the bleeding target makes its bleed gush")
flags = [m for m in dm.eval("__ns.Dots.Debug(0)").values() if m.startswith("Hit flags")]
check(len(flags) == 1 and flags[0].startswith("Hit flags on the target: readable (CRITICAL 1, none ")
      and flags[0].endswith("), secret 1"),
      f"/sab dots counts the target's hit flags, readable and secret ({flags})")
run(dm, 5.5)  # its last tick, due 12 s after the cast, has a moment to land
check(dm.eval("__total()") == 0 and not dm.eval("__m().clip.shown"), "gone once its 12 seconds are up")
dm.execute("__cast(6546, 'Cast-4'); __fire('UNIT_COMBAT', 'target', 'DODGE', '', 0, 1)")
run(dm, 0.3)
check(dm.eval("__total()") == 0, "a Rend dodged as it is cast is dropped")
dm.execute("""
    __target = { guid = 'Creature-0-1-2-3-524-0003', name = 'Rockhide Boar' }
    __fire('PLAYER_TARGET_CHANGED')
    __cast(172, 'Cast-5')
""")
for _ in range(4):
    run(dm, 1.6)
    dm.execute("__fire('UNIT_COMBAT', 'target', 'WOUND', '', 40, 1)")
run(dm, 0.5)
check(dm.eval("__total()") == 0,
      "with hit amounts readable, a DoT whose ticks never come is still dropped (resisted or immune)")
# A rogue's poisons: a weapon coating, never cast on the mob. Its ticks are known by their school alone, the
# amounts secret as on Forever.
dm.execute("""
    __spells[2823] = { 'Deadly Poison', 'Coats a weapon with poison that lasts for 30 min. Each strike has a 30% '
        .. 'chance of poisoning the enemy for 36 Nature damage over 12 sec. Stacks up to 5 times on a single target.' }
    __spells[8679] = { 'Instant Poison', 'Coats a weapon with poison that lasts for 30 min. Each strike has a 20% '
        .. 'chance of poisoning the enemy which instantly inflicts 19 to 25 Nature damage.' }
    function __nature() __fire('UNIT_COMBAT', 'target', 'WOUND', '', __secret(), 8) end
    __target = { guid = 'Creature-0-1-2-3-524-0004', name = 'Rockhide Boar' }
    __fire('PLAYER_TARGET_CHANGED')
    __fire('UNIT_COMBAT', 'target', 'WOUND', '', __secret(), 1)
""")
run(dm, 0.3)
dm.execute("__nature()")
run(dm, 0.3)
check(dm.eval("__total()") == 0, "a Nature hit with no poison on the weapons is not a poison")
dm.execute("__cast(2823, 'Cast-6'); __weapons.mainHand = true")
run(dm, 0.3)
check(dm.eval("__total()") == 0 and dm.eval("SmoothAnimatedBarsDB.dotPoisons.dots['Deadly Poison'].total") == 36,
      "coating a weapon with Deadly Poison puts nothing on the target, and is remembered across reloads")
dm.execute("__nature()")
run(dm, 0.3)
check(dm.eval("__total()") == 27 and dm.eval("__m().clip.shown") and dm.eval("__d(1).themeKey") == "plague",
      f"its first Nature tick on the boar: three ticks of 9 to come, one Plague liquid ({dm.eval('__total()')})")
SKULLS = """(function()
    local out = {}
    for _, f in ipairs(__frames) do
        if f.kind == 'PlayerModel' and f.shown then out[#out + 1] = f end
    end
    return out
end)()"""
check(dm.eval("""(function()
    local skulls = """ + SKULLS + """
    if #skulls < 6 then return false end
    for _, f in ipairs(skulls) do
        local at = f.points.CENTER
        if f.model ~= 166881 or not at or at.rel ~= __d(1).clampFill or f.modelAlpha < 0 or f.modelAlpha > 1
            or f.level <= TargetFrame:GetFrameLevel() then return false end
    end
    return true
end)()"""), "the poison landing sends up a burst of the game's own skull (Skull.m2), on the end of its liquid, over the frame")
check(dm.eval("__d(1).clamp.points.TOPLEFT.rel == TargetFrame.healthbar and __d(1).clamp.points.BOTTOMRIGHT.rel == __m().proxy.fill")
      and dm.eval("issecretvalue(__d(1).clamp.max)") and dm.eval("__d(1).clamp.reverse"),
      "the skulls' place is held inside the bar: from its left edge to the health's, over the target's secret health")
check(dm.eval("""(function()
    local l, motes, fumes = __d(1).liquid, false, false
    for _, em in ipairs(l.ambient or {}) do
        if em.texture == 'Mote' then motes = true end
        if em.texture == 'Wisp' then fumes = true end
    end
    return l.burst.texture == 'Glow' and motes and fumes
end)()"""), "and the liquid glows with green motes among Plague's fumes")
check(dm.eval("__d(1).liquid.theme.fillB[1] < __ns.Themes.Get('plague').fillB[1]")
      and dm.eval("__ns.Themes.Get('plague').fillB[1]") == 0.75,
      "in a darker green than Plague's, which the bars' own Plague theme keeps")
run(dm, 1.2)
dm.execute("__nature()")
run(dm, 1.5)
dm.execute("__nature()")
run(dm, 0.3)
check(dm.eval("__total()") == 18, f"a Nature hit off its rhythm is not taken; the next tick is ({dm.eval('__total()')})")
dm.execute("__cast(6546, 'Cast-7')")
run(dm, 0.3)
check(dm.eval("__total()") == 46 and dm.eval("__d(1).themeKey") == "plague" and dm.eval("__d(2).themeKey") == "blood",
      "Rend joins it as Blood behind the poison")
run(dm, 2.4)
dm.execute("__nature()")
run(dm, 3)
dm.execute("__nature()")  # the last of its four ticks
run(dm, 3)
dm.execute("__nature()")  # and one more: it was put on again meanwhile
run(dm, 0.3)
check(dm.eval("__total()") == 27 + 14,
      f"ticking on past its end, the poison starts again from that tick, next to Rend's last two ({dm.eval('__total()')})")
dm.execute("""
    __cast(8679, 'Cast-8')
    __target = { guid = 'Creature-0-1-2-3-524-0005', name = 'Rockhide Boar' }
    __fire('PLAYER_TARGET_CHANGED')
""")
run(dm, 0.3)
dm.execute("__nature()")
run(dm, 0.3)
check(dm.eval("__total()") == 0, "with Instant Poison on as well, one Nature hit could be either: nothing yet")
run(dm, 2.7)
dm.execute("__nature()")
run(dm, 0.3)
check(dm.eval("__total()") == 18, f"a second a tick later is Deadly Poison's: two ticks seen, 18 to come ({dm.eval('__total()')})")
run(dm, 12)
dm.execute("""
    __weapons.mainHand = false
    __target = { guid = 'Creature-0-1-2-3-524-0006', name = 'Rockhide Boar' }
    __fire('PLAYER_TARGET_CHANGED')
""")
run(dm, 0.3)
dm.execute("__nature()")
run(dm, 3)
dm.execute("__nature()")
run(dm, 0.3)
check(dm.eval("__total()") == 0 and dm.eval("SmoothAnimatedBarsDB.dotPoisons.dots['Deadly Poison']") is None,
      "weapons the game says are bare: the poisons are forgotten")
check(dm.eval("(__ns.Dots.parseCoating(__spells[8679][2]))") == "direct"
      and dm.eval("(__ns.Dots.parseCoating('Coats a weapon with poison that lasts for 30 min. Each strike has a 30% "
                  "chance of poisoning the enemy, slowing their movement speed by 50% for 12 sec.'))") is None
      and dm.eval("(__ns.Dots.parseDot(__spells[2823][2]))") is None,
      "coating text: a poison that strikes at once, one that only slows, and a coating is never a cast DoT")
dm.execute("__target.dead = true")
run(dm, 0.2)
dm.execute("SlashCmdList.SMOOTHANIMATEDBARS('dots')")
check(any(m.startswith("|cff40d060Smooth Animated Bars|r DoT marker: on") for m in chat(dm))
      and any("POISON Deadly Poison worn off" in m for m in chat(dm))
      and any("Poison on the weapons: none" in m for m in chat(dm)), "/sab dots reports the marker and the tracking")
check(not any("Error in" in m or "Error " in m for m in chat(dm)), "no errors (the target's health stayed secret)")
dm.execute("__settings.dots:SetValue(false)")
run(dm, 0.2)
check(not dm.eval("__ns.Dots.IsEnabled()") and not dm.eval(LISTENING) and not dm.eval("__m().clip.shown"),
      "off again: tracking stops and listens to nothing")
check(dm.eval("(__ns.Dots.parseDot('Transfers 15 health from the target to the caster every 3 sec. Lasts 30 sec.'))") == 150
      and dm.eval("(__ns.Dots.parseDot('Heals the target of 830 damage over 15 sec.'))") is None
      and dm.eval("(__ns.Dots.parseDot('Finishing move. 1 point : 24 damage over 12 sec. 5 points: 120 damage over 12 sec.', 5))") == 120,
      "spell text: drains, heals over time and finishers")

dd = session("{ setupDone = true, dots = true }", "__addons.DoesItDie = true")
run(dd, 0.3)
check(not dd.eval("__ns.Dots.IsEnabled()") and any("DoesItDie is loaded" in m for m in chat(dd)),
      "with DoesItDie loaded the marker stays off and says why")

# The poison tracking is untried in game, so nothing in it may raise an error: bad saved data is dropped, and an
# error inside it turns only it off.
dp = session("{ setupDone = true, dots = true, dotPoisons = { dots = { Bad = { name = 'Bad', total = 'lots' }, "
             "['Deadly Poison'] = 'x' }, directUntil = 'soon' } }")
dp.execute("""
    __spells[172] = { 'Corruption', 'Corrupts the target, causing 90 Shadow damage over 18 sec.' }
    __spells[2823] = { 'Deadly Poison', 'Coats a weapon with poison that lasts for 30 min. Each strike has a 30% '
        .. 'chance of poisoning the enemy for 36 Nature damage over 12 sec.' }
    __weapons.mainHand = true
    function __cast(id, guid)
        __fire('UNIT_SPELLCAST_SENT', 'player', __target.name, guid, id)
        __fire('UNIT_SPELLCAST_SUCCEEDED', 'player', guid, id)
    end
    function __nature() __fire('UNIT_COMBAT', 'target', 'WOUND', '', __secret(), 8) end
    __target = { guid = 'Creature-0-1-2-3-524-0001', name = 'Rockhide Boar' }
    __fire('PLAYER_TARGET_CHANGED')
""")
run(dp, 0.3)
dp.execute("__nature(); __fire('UNIT_COMBAT', 'target', 'WOUND', '', __secret(), __secret())")
run(dp, 0.3)
check(dp.eval("(__ns.Dots.Target())") == 0 and dp.eval("next(SmoothAnimatedBarsDB.dotPoisons.dots)") is None
      and not any("Error in" in m for m in chat(dp)),
      "saved poisons that make no sense are dropped, and a secret school is left alone, without an error")
dp.execute("__cast(2823, 'Cast-1'); SmoothAnimatedBarsDB.dotPoisons.dots = 5")
run(dp, 0.3)
dp.execute("__nature(); __cast(172, 'Cast-2')")
run(dp, 0.3)
dp.execute("SlashCmdList.SMOOTHANIMATEDBARS('dots')")
check(not any("Error in" in m for m in chat(dp)) and dp.eval("(__ns.Dots.Target())") == 90
      and any("tracking off after an error" in m for m in chat(dp))
      and any("ERROR in the poison tracking" in m for m in chat(dp)),
      "an error in the poison tracking prints nothing in chat, turns only it off (Corruption still shows), "
      "and /sab dots says so")
dp.execute("__nature()")
run(dp, 0.3)
check(dp.eval("(__ns.Dots.Target())") == 90 and not any("Error in" in m for m in chat(dp)),
      "and it stays off quietly")

# Other client languages (Locale*.lua, from DoesItDie): their spell text reads as the English does.
dl = session("{ setupDone = true, dots = true }")
dl.execute("""
    function __read(desc, points)
        local total, school, duration = __ns.Dots.parseDot(desc, points)
        return tostring(total) .. '/' .. tostring(school) .. '/' .. tostring(duration)
    end
""")
LANGUAGE_DOTS = [
    ("French", "Corrompt la cible et lui inflige 40 points de dégâts d'Ombre en 12 sec.", None, "40/32/12"),
    ("French, a non-breaking space", "Immole la cible et lui inflige 11 points de dégâts de Feu, puis 20 points "
     "de dégâts de Feu supplémentaires en 15 sec.", None, "20/4/15"),
    ("French finisher", "Coup de grâce qui fait saigner la cible. 1 point : 44 points de dégâts en 12 sec. "
     "5 points : 120 points de dégâts en 12 sec.", 5, "120/1/12"),
    ("German", "Verdirbt das Ziel und verursacht 12 Sek. lang 40 Punkt(e) Schattenschaden.", None, "40/32/12"),
    ("Spanish", "Corrompe al objetivo y le inflige 40 p. de daño de las Sombras durante 12 s.", None, "40/32/12"),
    ("Portuguese", "Corrompe o alvo, causando 40 de dano de Sombra ao longo de 12 s.", None, "40/32/12"),
    ("Russian", "Поражает цель порчей, нанося 40 ед. урона от темной магии за 12 сек.", None, "40/32/12"),
    ("Korean", "대상을 타락시켜 12초에 걸쳐 총 40의 암흑 피해를 입힙니다.", None, "40/32/12"),
    ("Chinese", "腐蚀目标，在12秒内造成总计40点暗影伤害。", None, "40/32/12"),
]
for label, desc, points, want in LANGUAGE_DOTS:
    dl.globals()["__desc"] = desc
    got = dl.eval(f"__read(__desc, {points or 'nil'})")
    check(got == want, f"{label} spell text reads as a DoT ({got}, wanted {want})")
# Forever's own tooltip text in every language (Wowhead's Forever data), each case a fix or a spell that matters:
# "dot" is total/school/duration (null: must read as no DoT), "combo" the points a builder awards, "finisher"
# whether it is a combo point finisher.
with open(os.path.join(HERE, "language_cases.json"), encoding="utf-8") as f:
    LANGUAGE_CASES = json.load(f)
wrong = []
for case in LANGUAGE_CASES:
    dl.globals()["__desc"] = case["desc"]
    if "dot" in case:
        got = dl.eval(f"__read(__desc, {case['points'] or 'nil'})")
        want = case["dot"] or "nil/nil/nil"
    elif "combo" in case:
        got, want = dl.eval("__ns.Dots.comboPointsAwarded(__desc)"), case["combo"]
    else:
        got, want = bool(dl.eval("__ns.Dots.isFinisher(__desc)")), case["finisher"]
    if got != want:
        wrong.append(f"{case['label']}: {got}, wanted {want}")
check(not wrong, f"Forever's spell text in every language: {len(LANGUAGE_CASES)} cases"
      + "".join("\n         " + w for w in wrong))
dl.execute("""
    __spells[172] = { 'Corruption', "Corrompt la cible et lui inflige 90 points de dégâts d'Ombre en 18 sec." }
    __spells[1079] = { 'Déchirure', 'Coup de grâce qui fait saigner la cible. 1 point : 44 points de dégâts en 12 sec.' }
    __spells[6603] = { 'Attaque', 'Attaque la cible.' }
    function __cast(id, guid)
        __fire('UNIT_SPELLCAST_SENT', 'player', __target.name, guid, id)
        __fire('UNIT_SPELLCAST_SUCCEEDED', 'player', guid, id)
    end
    __target = { guid = 'Creature-0-1-2-3-524-0001', name = 'Sanglier rochecuir' }
    __fire('PLAYER_TARGET_CHANGED')
""")
run(dl, 0.3)
dl.execute("__cast(172, 'Cast-1'); __cast(6603, 'Cast-2')")
run(dl, 0.3)
dl.execute("SlashCmdList.SMOOTHANIMATEDBARS('dots')")
check(dl.eval("(__ns.Dots.Target())") == 90 and dl.eval("__ns.Dots.parseDot('Attaque la cible.')") is None
      and not any("Error in" in m for m in chat(dl)),
      "a French Corruption cast shows on the marker; text that is not a DoT in any language reads as none")
check(any("NOT READ Attaque (id 6603)" in m for m in chat(dl))
      and not any("NOT READ Corruption" in m for m in chat(dl)),
      "/sab dots lists a description no language read, so a player can send its wording")

POISON_SETUP = """
    __spells[2823] = { 'Deadly Poison', 'Coats a weapon with poison that lasts for 30 min. Each strike has a 30% '
        .. 'chance of poisoning the enemy for 36 Nature damage over 12 sec.' }
    __weapons.mainHand = true
    function __cast(id, guid)
        __fire('UNIT_SPELLCAST_SENT', 'player', __target.name, guid, id)
        __fire('UNIT_SPELLCAST_SUCCEEDED', 'player', guid, id)
    end
    function __nature() __fire('UNIT_COMBAT', 'target', 'WOUND', '', __secret(), 8) end
    function __d(i) return (__ns.Marker.State()).liquids[i] end
    __target = { guid = 'Creature-0-1-2-3-524-0001', name = 'Rockhide Boar' }
    __fire('PLAYER_TARGET_CHANGED')
"""
sk = session("{ setupDone = true, dots = true }")
sk.execute(POISON_SETUP)
run(sk, 0.3)
sk.execute("__cast(2823, 'Cast-1')")
run(sk, 0.3)
sk.execute("__nature()")
run(sk, 1.2)
moved = sk.eval("(function() local n = 0 for _, f in ipairs(" + SKULLS + ") do if f.points.CENTER.y > 4 then n = n + 1 end end return n end)()")
check(moved > 0 and sk.eval("#" + SKULLS) <= 16, f"the skulls rise off the liquid ({moved} risen), at most 16 at once")
sk.execute("__settings.sparkles:SetValue(false); __settings.ambient:SetValue(false)")
run(sk, 3)
check(sk.eval("#" + SKULLS) == 0, "with Sparkles and Ambient off, no more skulls")
sk.execute("__settings.sparkles:SetValue(true); __settings.ambient:SetValue(true)")
run(sk, 1.5)
check(sk.eval("#" + SKULLS) > 0, "on again: they drift up while the poison runs")
sk.execute("__target = nil; __fire('PLAYER_TARGET_CHANGED')")
run(sk, 0.3)
check(sk.eval("#" + SKULLS) == 0 and not any("Error in" in m for m in chat(sk)), "no target: the skulls go with the marker")

# Where no model frame can be made, the liquid throws up the addon's drawn skull instead.
sf = session("{ setupDone = true, dots = true }", """
    local create = CreateFrame
    CreateFrame = function(kind, ...)
        if kind == 'PlayerModel' then error('no model frames here') end
        return create(kind, ...)
    end
""")
sf.execute(POISON_SETUP)
run(sf, 0.3)
sf.execute("__cast(2823, 'Cast-1')")
run(sf, 0.3)
sf.execute("__nature()")
run(sf, 0.3)
check(sf.eval("""(function()
    local l, flying = __d(1).liquid, false
    for _, mote in ipairs(l.motes) do
        if mote.active and mote.file == 'Skull' then flying = true end
    end
    return l.burst.texture == 'Skull' and flying
end)()""") and not any("Error in" in m for m in chat(sf)),
      "with no model frames, the liquid throws up the drawn skull instead, without an error")

print("== heal marker")
hm = session("{ setupDone = true }", "__player.class = 'PRIEST'")
run(hm, 0.5)
HEAL_EVENTS = """(function()
    for _, f in ipairs(__frames) do
        if f.events.UNIT_SPELLCAST_CHANNEL_START then return true end
    end
    return false
end)()"""
check(hm.eval("SmoothAnimatedBarsDB.heals") is True and hm.eval("__ns.Heals.IsEnabled()") and hm.eval(HEAL_EVENTS)
      and hm.eval("__ns.HealMarker.State() ~= nil") and not hm.eval("__ns.HealMarker.State().clip.shown"),
      "on by default: tracking, a marker on the player's health bar, nothing shown without heals")
hm.execute("""
    __spells[139] = { 'Renew', 'Heals the target of 830 damage over 15 sec.' }
    __spells[746] = { 'First Aid', 'Heals 66 damage over 6 sec.' }
    __spells[2061] = { 'Flash Heal', 'Heals a friendly target for 193 to 237.' }
    __spells[585] = { 'Smite', 'Smite an enemy for 15 to 20 Holy damage.' }
    function __h() return __ns.HealMarker.State() end
    function __hd(i) return __h().liquids[i] end
    function __heal() return (__ns.Heals.Player()) end
    function __send(id, guid, name) __fire('UNIT_SPELLCAST_SENT', 'player', name or 'Testchar', guid, id) end
    function __instant(id, guid, name)
        __send(id, guid, name)
        __fire('UNIT_SPELLCAST_SUCCEEDED', 'player', guid, id)
    end
""")
hm.execute("__instant(585, 'Cast-0', 'Mottled Boar'); __send(585, 'Cast-00', 'Mottled Boar')"
           "; __fire('UNIT_SPELLCAST_START', 'player', 'Cast-00', 585); __fire('UNIT_SPELLCAST_STOP', 'player', 'Cast-00', 585)")
run(hm, 0.3)
check(hm.eval("__heal()") == 0 and not hm.eval("__h().clip.shown") and not any("Error in" in m for m in chat(hm)),
      "a spell that is not a heal, instant or cast: nothing shown, no error")
hm.execute("__spells[9999] = { 'Odd Heal', 'Restores a little health to a friendly target.' }; __instant(9999, 'Cast-01')")
check(any("UNREAD Odd Heal" in m for m in hm.eval("__ns.Heals.Debug(20)").values()),
      "a heal whose text cannot be read: its text goes to /sab heals")
hm.execute("__instant(139, 'Cast-1'); __renewAt = __now")


def renew():
    """What Renew (830 over 15 s, a tick every 3) still has to heal."""
    done = int((hm.eval("__now - __renewAt")) / 3 + 0.05)
    return max(0, 166 * (5 - done))


run(hm, 0.15)
check(hm.eval("__hd(1).liquid.energy") > 0.3, "a heal starting splashes the heal liquid")
run(hm, 1)
check(hm.eval("__heal()") == 830 and hm.eval("__h().clip.shown") and hm.eval("__hd(1).themeKey") == "holy"
      and hm.eval("__hd(1).pool.shown") and not hm.eval("__hd(2).pool.shown"),
      "Renew on yourself: 830 to come, one Holy liquid (a priest's heal)")
check(hm.eval("__hd(1).run.max == PlayerFrame.healthbar.max") and hm.eval("issecretvalue(__hd(1).run.max)")
      and hm.eval("__hd(1).run.value") == 830 and not hm.eval("__hd(1).run.reverse")
      and hm.eval("__hd(1).run.points.TOPLEFT.rel == __h().proxy.fill")
      and hm.eval("__hd(1).run.points.TOPLEFT.relPoint") == "TOPRIGHT"
      and hm.eval("__h().proxy.value == PlayerFrame.healthbar.value"),
      "its running total takes the health bar's secret range, filling on from the health's edge")
check(hm.eval("__hd(1).mover.points.TOPRIGHT.rel == __hd(1).fill") and hm.eval("__hd(1).mover.w") == 124
      and hm.eval("__hd(1).pool.points.TOPLEFT.rel == __h().proxy.fill") and hm.eval("__hd(1).pool.points.TOPLEFT.x") == -6
      and hm.eval("__hd(1).pool.points.BOTTOMRIGHT.rel == __h().clip")
      and hm.eval("__h().clip.points.BOTTOMRIGHT.rel == PlayerFrame.healthbar")
      and hm.eval("__h().clip.points.BOTTOMRIGHT.x") == 0 and hm.eval("__h().clip.clipsChildren"),
      "the heal liquid ends where the health will be, starts a little under the health's edge, cut at the bar's end")
HEAL_LAYERS = """(function(i)
    local m = __h()
    local mask = PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.HealthBarMask
    local masked, free, top = 0, 0, -99
    for _, t in ipairs(m.liquids[i].liquid.textures) do
        if t.masks and t.masks[1] == mask then masked = masked + 1 else free = free + 1 end
        if t.layer == 'ARTWORK' and t.sub > top then top = t.sub end
    end
    local d = m.liquids[i]
    return masked > 0 and free == 64 and m.clip.useParentLevel and d.pool.useParentLevel and d.mover.useParentLevel
        and top
end)"""
check(hm.eval(HEAL_LAYERS + "(1)") == 2 and hm.eval(HEAL_LAYERS + "(2)") == -3,
      "cut by the bar's mask, motes free, at the bar's level, under the health liquid; the second under the first")
run(hm, 2)  # Renew's first tick, 3 s after the cast
check(hm.eval("__heal()") == 664, f"a tick lands every 3 seconds: 4 of 5 left, 664 to come ({hm.eval('__heal()')})")
hm.execute("__target = { guid = 'Player-1-00000002', name = 'Friend', friendly = true }; __fire('PLAYER_TARGET_CHANGED')")
hm.execute("__instant(139, 'Cast-2', 'Friend')")
run(hm, 0.3)
check(hm.eval("__heal()") == 664, "Renew on a friend: not yours to show")
hm.execute("__send(746, 'Cast-3'); __fire('UNIT_SPELLCAST_CHANNEL_START', 'player', 'Cast-3', 746)"
           "; __fire('UNIT_SPELLCAST_SUCCEEDED', 'player', 'Cast-3', 746)")
run(hm, 0.3)
check(hm.eval("__heal()") == renew() + 66 and hm.eval("__hd(1).themeKey") == "holy" and hm.eval("__hd(2).themeKey") == "bandage"
      and hm.eval("__hd(2).pool.shown") and hm.eval("__hd(2).value") == renew() + 66,
      "a bandage on yourself: 66 more, a liquid of its own past the Holy one, its own success event not counted twice")
check(hm.eval("__hd(2).pool.points.TOPLEFT.rel == __hd(1).fill") and hm.eval("__hd(2).pool.points.TOPLEFT.x") == -6
      and hm.eval("__hd(2).mover.points.TOPRIGHT.rel == __hd(2).fill"),
      "the bandage's liquid starts on the Holy one's end")
check(hm.eval("__hd(2).liquid.burst.texture") == "Plus" and hm.eval("__hd(2).liquid.ambient[1].texture") == "Plus"
      and hm.eval("__hd(2).liquid.theme.fillB[1]") > 0.8 and hm.eval("__hd(1).liquid.burst.texture") != "Plus",
      "a bandage throws green pluses, as the game shows over a healed character, in the heals' spring green")
run(hm, 0.8)
check(hm.eval("__heal()") == renew() + 55, f"bandages tick every second ({hm.eval('__heal()')})")
hm.execute("__fire('UNIT_SPELLCAST_CHANNEL_STOP', 'player', 'Cast-3', 746)")
run(hm, 0.3)
check(hm.eval("__heal()") == renew(), "the bandage broken (or done): what it had left is gone")
for _ in range(120):
    run(hm, 1 / 60)
    if not hm.eval("__hd(2).pool.shown"):
        break
check(not hm.eval("__hd(2).pool.shown") and hm.eval("__hd(1).pool.shown"), "its liquid glides away, Renew's stays")
hm.execute("__target = nil; __fire('PLAYER_TARGET_CHANGED')")
hm.execute("__player.surname = 'Hootsman'; __send(2061, 'Cast-s1', 'Testchar Hootsman')"
           "; __fire('UNIT_SPELLCAST_START', 'player', 'Cast-s1', 2061)")
run(hm, 0.3)
full = hm.eval("__heal()") == renew() + 193
hm.execute("__fire('UNIT_SPELLCAST_STOP', 'player', 'Cast-s1', 2061)"
           "; __send(2061, 'Cast-s2', 'Testchar-Mockrealm'); __fire('UNIT_SPELLCAST_START', 'player', 'Cast-s2', 2061)")
run(hm, 0.3)
check(full and hm.eval("__heal()") == renew() + 193,
      "a cast sent at your name with Forever's surname, or with the realm, is on you")
hm.execute("__fire('UNIT_SPELLCAST_STOP', 'player', 'Cast-s2', 2061); __player.surname = nil")
run(hm, 0.3)
hm.execute("__send(2061, 'Cast-4', ''); __fire('UNIT_SPELLCAST_START', 'player', 'Cast-4', 2061)")
run(hm, 0.3)
check(hm.eval("__heal()") == renew() + 193, f"Flash Heal being cast on yourself: its lowest roll shows ({hm.eval('__heal()')})")
OWN, OTHERS = "PlayerFrame.healthbar.MyHealPredictionBar.Fill.alpha", "PlayerFrame.healthbar.OtherHealPredictionBar.Fill.alpha"
check(hm.eval(OWN) == 0 and hm.eval(OTHERS) == 1,
      "the game's own prediction of your heals is hidden under the marker; others' heals keep theirs")
hm.execute("__fire('UNIT_SPELLCAST_INTERRUPTED', 'player', 'Cast-4', 2061)")
run(hm, 0.3)
check(hm.eval("__heal()") == renew(), "interrupted: gone")
hm.execute("__settings.playerHealth:SetValue(false)")
run(hm, 0.3)
check(hm.eval("__hd(1).liquid.body.sub") == 3 and hm.eval("__hd(1).pool.points.TOPLEFT.x") == 0
      and hm.eval("__h().clip.shown"), "health liquid off: the heal liquid lies over the game's fill, from its edge")
hm.execute("__settings.playerHealth:SetValue(true)")
run(hm, 0.3)
check(hm.eval("__hd(1).liquid.body.sub") == -2, "and goes back under the liquid when it is on again")
# Seen in game: in combat the aura lookup said "none" for a Rejuvenation that was on the player.
hm.execute("__aurasReadable = true; __combat = true; __instant(139, 'Cast-A'); __renewAt = __now")
run(hm, 1)
check(hm.eval("__heal()") == renew() == 830, "in combat, a lookup that never found Renew's aura does not drop it")
hm.execute("__playerAuras[139] = { expirationTime = __now + 30 }")
run(hm, 0.6)
hm.execute("__playerAuras[139] = nil; __fire('UNIT_AURA', 'player')")
run(hm, 0.6)
check(hm.eval("__heal()") == renew(), "nor does its aura going missing in combat")
hm.execute("__combat = false; __fire('UNIT_AURA', 'player')")
run(hm, 0.3)
check(hm.eval("__heal()") == 0 and any("GONE Renew" in m for m in hm.eval("__ns.Heals.Debug(20)").values()),
      "out of combat, an aura seen and then gone (dispelled, cancelled): dropped")
hm.execute("__playerAuras[139] = { expirationTime = __now + 4.5 }; __instant(139, 'Cast-5')")
run(hm, 1)
check(hm.eval("__heal()") == 332, f"with its aura there, Renew follows the aura's time left ({hm.eval('__heal()')})")
hm.execute("__player.dead = true")
run(hm, 0.3)
check(not hm.eval("__h().clip.shown") and hm.eval(OWN) == 1, "dead: marker hidden, the game's prediction back")
hm.execute("__player.dead = false; __fire('PLAYER_DEAD')")
run(hm, 0.3)
check(hm.eval("__heal()") == 0, "and dying drops every heal")
hm.execute("SlashCmdList.SMOOTHANIMATEDBARS('heals')")
check(any("Heal marker (health): on" in m for m in chat(hm)) and any("HOT Renew" in m for m in chat(hm)),
      "/sab heals reports the marker and the tracking")
check(not any("Error in" in m for m in chat(hm)), "no errors (the player's health stayed secret)")
hm.execute("__settings.heals:SetValue(false)")
run(hm, 0.2)
check(not hm.eval("__ns.Heals.IsEnabled()") and not hm.eval(HEAL_EVENTS) and not hm.eval("__h().clip.shown"),
      "off: tracking stops and listens to nothing")
over, dur, direct = hm.eval("__ns.Heals.parseHeal('Heals a friendly target for 93 to 107 and another 98 over 21 sec.')")
check((over, dur, direct) == (98, 21, 93)
      and hm.eval("(__ns.Heals.parseHeal('Heals the target for 32 over 12 sec.'))") == 32
      and hm.eval("(__ns.Heals.parseHeal('Corrupts the target, causing 90 Shadow damage over 18 sec.'))") is None,
      "spell text: direct and over time, over time only, and a DoT is no heal")
dr = session("{ setupDone = true }", "__player.class = 'DRUID'")
dr.execute("""
    __spells[774] = { 'Rejuvenation', 'Heals the target for 32 over 12 sec.' }
    __fire('UNIT_SPELLCAST_SENT', 'player', 'Testchar', 'Cast-1', 774)
    __fire('UNIT_SPELLCAST_SUCCEEDED', 'player', 'Cast-1', 774)
""")
run(dr, 0.5)
check(dr.eval("(__ns.Heals.Player())") == 32 and dr.eval("__ns.HealMarker.State().liquids[1].themeKey") == "nature",
      "a druid's Rejuvenation is Nature")
print("== food and drink")
fd = session("{ setupDone = true }", "__player.class = 'MAGE'; __player.power = 0")
fd.execute("""
    __spells[433] = { 'Food', 'Restores 61 health over 18 sec. Must remain seated while eating.' }
    __spells[430] = { 'Drink', 'Restores 151 mana over 18 sec. Must remain seated while drinking.' }
    __spells[18234] = { 'Refreshment', 'Restores 294 health and 294 mana over 18 sec. Must remain seated.' }
    __spells[133] = { 'Fireball', 'Hurls a fiery ball that causes 14 to 22 Fire damage.' }
    function __hp() return (__ns.HealMarker.State()) end
    function __mp() return select(2, __ns.HealMarker.State()) end
    function __use(id, guid)
        __fire('UNIT_SPELLCAST_SENT', 'player', '', guid, id)
        __fire('UNIT_SPELLCAST_SUCCEEDED', 'player', guid, id)
    end
""")
fd.execute("__use(433, 'Cast-1'); __use(430, 'Cast-2')")
run(fd, 1)
check(fd.eval("(__ns.Heals.Player())") == 61 and fd.eval("(__ns.Heals.Mana())") == 151,
      "eating and drinking: 61 health and 151 mana on the way, the drink not standing you up from the food")
check(fd.eval("__hp().liquids[1].themeKey") == "honey" and fd.eval("__hp().clip.shown")
      and fd.eval("__mp().liquids[1].themeKey") == "nagrand" and fd.eval("__mp().clip.shown")
      and fd.eval("__mp().bar == PlayerFrame.manabar") and fd.eval("__mp().liquids[1].run.max == PlayerFrame.manabar.max")
      and fd.eval("__mp().spec.mask == PlayerFrame.manabar.ManaBarMask"),
      "food as Honey ahead of the health, drink as Nagrand ahead of the mana, on the mana bar's secret range and mask")
SEAM = """(function()
    local s = __mp().liquids[1].seam
    local before = __ns.Bars.Liquid(PlayerFrame.manabar)
    local r = before.gradC:GetRGBA()
    local width, differ = nil, false
    for _, t in ipairs(s.rows) do
        if width and t.w ~= width then differ = true end
        width = t.w
    end
    local a = s.mover.points.TOPRIGHT
    return s.mover.shown and a.rel == __mp().proxy.fill and a.relPoint == 'TOPRIGHT' and differ
        and s.rows[1].vc[1] == r and s.rows[1].layer == 'ARTWORK' and s.rows[1].sub == 7
        and s.rows[1].masks[1] == PlayerFrame.manabar.ManaBarMask
end)()"""
check(fd.eval(SEAM), "a seam of the mana's colour lies above the drink on the mana's edge, following its waves slice by slice")
fd.execute("__settings.playerPower:SetValue(false)")
run(fd, 0.3)
check(not fd.eval("__mp().liquids[1].seam.mover.shown") and fd.eval("__mp().clip.shown"),
      "with the mana liquid off there is no front to follow: no seam")
fd.execute("__settings.playerPower:SetValue(true)")
run(fd, 0.5)
INFLOW = """(function(bar, source)
    -- Motes in the bar's own liquid moving back from its front, in the incoming liquid's colours.
    local n = 0
    for _, m in ipairs(__ns.Bars.Liquid(bar).motes) do
        if m.active and m.vx < 0 and m.r1 == source.theme.splashFrom[1] and m.g1 == source.theme.splashFrom[2] then
            n = n + 1
        end
    end
    return n
end)"""
check(fd.eval(INFLOW + "(PlayerFrame.manabar, __mp().liquids[1].liquid)") > 0
      and fd.eval(INFLOW + "(PlayerFrame.healthbar, __hp().liquids[1].liquid)") > 0,
      "they pour in: the drink's motes drift back into the mana liquid, the food's into the health")
run(fd, 2.2)
check(fd.eval("(__ns.Heals.Player())") < 61 and fd.eval("(__ns.Heals.Mana())") < 151, "both tick down")
fd.execute("__fire('PLAYER_STARTED_MOVING')")
run(fd, 1.8)
check(fd.eval("(__ns.Heals.Player())") == 0 and fd.eval("(__ns.Heals.Mana())") == 0
      and fd.eval(INFLOW + "(PlayerFrame.manabar, __mp().liquids[1].liquid)") == 0,
      "moving stands you up: food and drink end, and stop pouring in")
fd.execute("__use(18234, 'Cast-3')")
run(fd, 0.5)
both = fd.eval("(__ns.Heals.Player())") == 294 and fd.eval("(__ns.Heals.Mana())") == 294
fd.execute("__use(133, 'Cast-4')")
run(fd, 0.3)
check(both and fd.eval("(__ns.Heals.Player())") == 0 and fd.eval("(__ns.Heals.Mana())") == 0,
      "food and drink in one feeds both bars; casting anything else stands you up")
fd.execute("__player.power = 1; __use(430, 'Cast-5')")
run(fd, 0.5)
check(not fd.eval("__mp().clip.shown"), "with rage on the power bar (a druid's bear form), no drink marker")
fd.execute("SlashCmdList.SMOOTHANIMATEDBARS('heals')")
check(any("Heal marker (mana)" in m for m in chat(fd)) and any("REST Drink" in m for m in chat(fd))
      and not any("Error in" in m for m in chat(fd)), "/sab heals reports both markers; no errors")
check(fd.eval("(__ns.Heals.parseRest('Restores 2148 health and 4410 mana over 30 sec.'))") == 2148
      and fd.eval("(__ns.Heals.parseRest('Heals the target for 32 over 12 sec.'))") is None,
      "food text read; a heal is not food")
print("== a meal's buff")
FED_FOOD = "Restores 61 health over 18 sec. Must remain seated while eating. If you spend at least 10 seconds eating you will become well fed and gain 4 Stamina for 15 min."
mb = session("{ setupDone = true }", "__player.class = 'DRUID'; __player.power = 0")
mb.execute(f"""
    __spells[433] = {{ 'Food', '{FED_FOOD}' }}
    __spells[434] = {{ 'Bread', 'Restores 61 health over 18 sec. Must remain seated while eating.' }}
    function __eat(id, guid)
        __fire('UNIT_SPELLCAST_SENT', 'player', '', guid, id)
        __fire('UNIT_SPELLCAST_SUCCEEDED', 'player', guid, id)
    end
    function __stars()
        local n = 0
        for _, m in ipairs(__ns.Bars.Liquid(PlayerFrame.healthbar).motes) do
            if m.active and m.style and m.style.texture == 'Star' then n = n + 1 end
        end
        return n
    end
    function __tint() return __ns.Bars.Liquid(PlayerFrame.healthbar).inflowMix end
""")
mb.execute("__eat(434, 'Cast-0')")
run(mb, 11)
check(mb.eval("(__ns.Heals.Charge('health'))") is None and mb.eval("__stars()") == 0,
      "food without a buff: no build-up, no burst")
check(any("Bread has no buff" in m for m in mb.eval("__ns.Heals.Debug(30)").values()),
      "and /sab heals shows its text, in case Forever words the buff differently")
mb.execute("__fire('PLAYER_STARTED_MOVING')")
run(mb, 2)
mb.execute("__eat(433, 'Cast-1')")
run(mb, 1)
early = mb.eval("__tint()")
run(mb, 8)
late = mb.eval("__tint()")
progress = mb.eval("(__ns.Heals.Charge('health'))")
check(0.85 < progress < 1 and late > early and mb.eval("__stars()") == 0,
      f"food with a buff: it builds up in the health liquid, the tint growing ({early:.2f} then {late:.2f}), no stars yet")
run(mb, 1.2)
check(mb.eval("__stars()") > 25 and mb.eval("__tint()") > 0.9,
      f"at 10 seconds it lets go: {mb.eval('__stars()')} stars along the bar and a flash of the honey's colour")
run(mb, 3)
check(0 < mb.eval("__stars()") < 25 and mb.eval("__tint()") < 0.9,
      "then slow stars keep rising while you stay sitting: you can get up")
mb.execute("__fire('PLAYER_STARTED_MOVING')")
run(mb, 3)
check(mb.eval("__stars()") == 0 and mb.eval("__ns.Bars.Liquid(PlayerFrame.healthbar).inflowTheme == nil") and not mb.eval("(__ns.HealMarker.State()).clip.shown"),
      "standing up ends it")
mb.execute("__eat(433, 'Cast-2')")
run(mb, 5)
mb.execute("__fire('PLAYER_STARTED_MOVING')")
run(mb, 8)
check(mb.eval("__stars()") == 0, "standing up before 10 seconds: no burst")
mb.execute("__eat(433, 'Cast-3')")
run(mb, 10.5)
check(mb.eval("__stars()") > 25, "and the next meal builds up and lets go again")
check(not any("Error in" in m for m in chat(mb)), "no errors")
fl = session("{ setupDone = true }", "__player.class = 'PRIEST'")
fl.execute("""
    __spells[2061] = { 'Flash Heal', 'Heals a friendly target for 193 to 237.' }
    function __d1() return __ns.HealMarker.State().liquids[1] end
    __fire('UNIT_SPELLCAST_SENT', 'player', '', 'Cast-L', 2061)
    __fire('UNIT_SPELLCAST_START', 'player', 'Cast-L', 2061)
""")
run(fl, 1.5)
before = fl.eval("__d1().liquid.energy")
fl.execute("__fire('UNIT_SPELLCAST_STOP', 'player', 'Cast-L', 2061); __fire('UNIT_SPELLCAST_SUCCEEDED', 'player', 'Cast-L', 2061)")
run(fl, 0.15)
check(fl.eval("(__ns.Heals.Player())") == 0 and fl.eval("__ns.HealMarker.State().clip.shown") and fl.eval("__d1().pool.shown")
      and fl.eval("__d1().liquid.energy") > max(before, 1.0),
      "a lone cast heal landing: its liquid bursts, and glides into the health instead of vanishing")
for _ in range(180):
    run(fl, 1 / 60)
    if not fl.eval("__ns.HealMarker.State().clip.shown"):
        break
check(not fl.eval("__ns.HealMarker.State().clip.shown") and not any("Error in" in m for m in chat(fl)),
      "then the marker hides")
fl.execute("""
    __fire('UNIT_SPELLCAST_SENT', 'player', '', 'Cast-M', 2061)
    __fire('UNIT_SPELLCAST_START', 'player', 'Cast-M', 2061)
""")
run(fl, 0.5)
fl.execute("__fire('UNIT_SPELLCAST_STOP', 'player', 'Cast-M', 2061)")
run(fl, 0.2)
held = fl.eval("(__ns.Heals.Player())")
run(fl, 0.5)
check(held == 193 and fl.eval("(__ns.Heals.Player())") == 0,
      "a cast that stops without landing (moved, cancelled) holds a moment for its success, then goes")

print("== the wait before mana regenerates")
check(lua.eval("SmoothAnimatedBarsDB.manaBuild") is True, "on by default")
mr = session()
mr.execute("""
    __player.power = 0
    __fire('UNIT_DISPLAYPOWER', 'player')
    __spells[133] = { 'Fireball', 'Hurls a fiery ball.' }
    __spellCosts[133] = { { type = 0, name = 'MANA', cost = 42 } }
    __spells[5019] = { 'Shoot', 'Shoots a wand.' }
    function __cast(id, guid)
        __fire('UNIT_SPELLCAST_SENT', 'player', 'Kobold', guid, id)
        __fire('UNIT_SPELLCAST_SUCCEEDED', 'player', guid, id)
    end
    function __mana() return __ns.Bars.Liquid(PlayerFrame.manabar) end
""")
check(mr.eval("__ns.ManaRule.Left()") is None, "no wait to begin with")
mr.execute("__cast(5019, 'Cast-1')")
check(mr.eval("__ns.ManaRule.Left()") is None, "a spell with no cost starts no wait")
run(mr, 0.2)
mr.execute("__cast(133, 'Cast-2')")
check(abs(mr.eval("__ns.ManaRule.Left()") - 5) < 0.01, "a spell that costs mana starts the five seconds")
run(mr, 1)
mr.execute("__cast(133, 'Cast-3')")
check(abs(mr.eval("__ns.ManaRule.Left()") - 5) < 0.01, "another spend starts the wait again")
energy = mr.eval("__mana().energy")
run(mr, 0.1)
mr.execute("""
    __spellCosts[133] = nil
    __fire('UNIT_SPELLCAST_SENT', 'player', 'Kobold', 'Cast-4', 133)
    __spellCosts[133] = { { type = 0, name = 'MANA', cost = 42 } }
    __fire('UNIT_SPELLCAST_SUCCEEDED', 'player', 'Cast-4', 133)
""")
check(any("FREE Fireball" in m for m in mr.eval("__ns.ManaRule.Debug(40)").values()),
      "a cast free when sent (Clearcasting) is free, whatever the spell costs when it succeeds")
run(mr, 2)
# Mana can still trickle in during the wait (Meditation, mp5), and each change stirs the bar.
for _ in range(6):
    mr.execute("__fire('UNIT_POWER_UPDATE', 'player')")
    run(mr, 0.4)
moved = mr.eval("""(function()
    local most, m = 0, __mana()
    for i = 1, #m.pos do most = math.max(most, math.abs(m:FrontOffset(i))) end
    return most
end)()""")
check(moved < 0.6, f"the front holds still through the build-up, even stirred ({moved:.2f} px)")
energy = mr.eval("__mana().energy")
check(energy > 0.8, f"the liquid builds up ({energy:.2f})")
check(mr.eval("__mana().charge") > 1, "lightning starting up")
run(mr, 0.6)
check(mr.eval("__ns.ManaRule.Left()") is None and mr.eval("__motes(PlayerFrame.manabar)") >= 30, "and lets go in stars")
check(mr.eval("__mana().inflowTheme ~= nil"), "with a flash of its front")
run(mr, 2)
check(mr.eval("__mana().inflowTheme") is None, "which fades, leaving the front its own colours")
run(mr, 1)
check(mr.eval("__mana().steady") == 0, "and the front moves freely again")
check(not any("Error in" in m for m in chat(mr)), "no errors")

mr.execute("""
    __spellCosts[133] = { { type = __secret(), name = __secret(), cost = __secret() } }
    __cast(133, 'Cast-5')
""")
check(mr.eval("__ns.ManaRule.Left()") is not None, "a secret cost counts as a spend")
mr.execute("__spellCosts[133] = { { type = 0, name = 'MANA', cost = __secret() } }; __cast(133, 'Cast-5b')")
check(mr.eval("__ns.ManaRule.Left()") is not None and not any("Error" in m for m in chat(mr)),
      "a secret amount of mana too, without an error")

mr.execute("__player.power = 1; __spellCosts[133] = { { type = 0, name = 'MANA', cost = 42 } }; __cast(133, 'Cast-6')")
run(mr, 3)
check(mr.eval("__mana().steady") == 0 and mr.eval("__mana().inflowTheme") is None,
      "nothing shows while the bar is on another power (a druid's forms)")
mr.execute("__player.power = 0")
run(mr, 0.5)
check(mr.eval("__mana().steady") == 1, "it shows again back on mana")
mr.execute("SlashCmdList.SMOOTHANIMATEDBARS('mana')")
check(any("mana build-up: on" in m for m in chat(mr)) and any("SPEND Fireball" in m for m in chat(mr)),
      "/sab mana reports the wait and what it saw")

mr.execute("__settings.manaBuild:SetValue(false)")
check(mr.eval("__ns.ManaRule.Left()") is None, "off: the wait is called off")
mr.execute("__cast(133, 'Cast-7')")
check(mr.eval("__ns.ManaRule.Left()") is None, "and casts start none")
run(mr, 3)
check(mr.eval("__mana().steady") == 0, "the front moves freely again")
mr.execute("__settings.manaBuild:SetValue(true); __cast(133, 'Cast-8')")
check(mr.eval("__ns.ManaRule.Left()") is not None, "on again")
mr.execute("__fire('PLAYER_DEAD')")
check(mr.eval("__ns.ManaRule.Left()") is None, "dying ends the wait")
check(not any("Error" in m for m in chat(mr)), "no errors")

print("== /sab capture (gallery art)")
cap = session()
run(cap, 0.5)
cap.execute("__combat = true; SlashCmdList.SMOOTHANIMATEDBARS('capture')")
check(not cap.eval("SmoothAnimatedBarsCapture") and any("out of combat" in m for m in chat(cap)), "not in combat")
cap.execute("__combat = false; SlashCmdList.SMOOTHANIMATEDBARS('capture')")
grid = "SmoothAnimatedBarsCapture"
cap.execute(f"""
    function __gridBg()
        for _, r in ipairs(__regions) do
            if r.parent == {grid} and r.layer == "BACKGROUND" then return r.color[1] end
        end
    end
    function __cells()
        local n = 0
        for _, f in ipairs(__frames) do if f.parent == {grid} then n = n + 1 end end
        return n
    end
    function __marks()
        local n = 0
        for _, r in ipairs(__regions) do
            if r.parent == {grid} and r.color and r.color[1] == 1 and r.color[2] == 0 and r.w == 6 then n = n + 1 end
        end
        return n
    end
""")
check(cap.eval(f"{grid}.shown") and cap.eval("__gridBg()") == 0 and cap.eval("__cvars.screenshotFormat") == "tga",
      "the grid shows on black, screenshots switched to TGA")
check(cap.eval("__cells()") == 12 and cap.eval("__marks()") == 2, "twelve pieces in cells, two red markers")
check(cap.eval(f"""(function()
    local scale = {grid}.scale
    return scale > 0 and 1030 * scale <= UIParent.w and 420 * scale <= UIParent.h
end)()"""), "the grid is scaled to fit the screen")
check(cap.eval(f"""(function()
    local masked = 0
    for _, f in ipairs(__frames) do
        if f.parent == {grid} then
            for _, r in ipairs(__regions) do
                if r.parent == f and r.color and r.masks and #r.masks > 0 then masked = masked + 1 end
            end
        end
    end
    return masked
end)()""") == 4, "four bar masks, each a white fill cut by its mask")
run(cap, 0.6)
check(cap.eval("__screenshots") == 1, "first screenshot, on black")
cap.execute("__fire('SCREENSHOT_SUCCEEDED')")
check(cap.eval("__gridBg()") == 1, "then the background turns white")
run(cap, 4.1)
check(cap.eval("__screenshots") == 2, "second screenshot once the game's notice has faded")
cap.execute("__fire('SCREENSHOT_SUCCEEDED')")
check(not cap.eval(f"{grid}.shown") and cap.eval("__cvars.screenshotFormat") == "jpg"
      and any("capture_art.py" in m for m in chat(cap)), "then it hides, puts the screenshot format back and says what next")
cap.execute("__fire('SCREENSHOT_SUCCEEDED')")
check(cap.eval("__screenshots") == 2, "a later screenshot of the player's own is left alone")

print("== /sab capture plates (nameplate art)")
cp = session()
cp.execute("SlashCmdList.SMOOTHANIMATEDBARS('capture plates')")
grid = "SmoothAnimatedBarsCapturePlates"
check(cp.eval(f"{grid}.shown") and cp.eval("__cvars.screenshotFormat") == "tga"
      and any("No nameplate on your target to measure" in m for m in chat(cp)),
      "with no target nameplate: says so, and captures the art anyway, as TGA")
pieces = cp.eval(f"""(function()
    local out = {{}}
    for _, r in ipairs(__regions) do
        if r.parent == {grid} and r.kind == "Texture" and (r.atlas or (r.file and r.file ~= "SOLID")) then
            out[#out + 1] = (r.atlas or r.file) .. " " .. r.tc[3] .. " " .. r.w .. "x" .. r.h
        end
    end
    table.sort(out)
    return table.concat(out, "; ")
end)()""")
check(pieces == r"Interface\TargetingFrame\UI-TargetingFrame-BarFill 0 128x10; Interface\Tooltips\Nameplate-Border 0.5 128x16; "
      r"UI-HUD-CoolDownManager-Bar 0 128x10; UI-HUD-CoolDownManager-Bar-BG 0 136x19; "
      r"UI-HUD-CoolDownManager-Selected-yellow 0 139x19; ui-hud-nameplates-deselected-overlay 0 128x10; "
      r"ui-hud-nameplates-levelindicator 0 28x25; ui-hud-nameplates-levelindicator-rectangle-selected 0 34x32; "
      r"ui-hud-nameplates-levelindicator-skull 0 18x18",
      f"draws the Classic plate's border (the texture's bottom half) and bar fill, and the other styles' pieces: {pieces}")
run(cp, 0.6)
check(cp.eval("__screenshots") == 1, "first screenshot, on black")
cp.execute("__fire('SCREENSHOT_SUCCEEDED')")
run(cp, 4.1)
check(cp.eval("__screenshots") == 2, "then on white")
cp.execute("__fire('SCREENSHOT_SUCCEEDED')")
check(not cp.eval(f"{grid}.shown") and cp.eval("__cvars.screenshotFormat") == "jpg"
      and any("capture_art.py --plates" in m for m in chat(cp)), "then it hides, puts the format back and says what next")
cp.execute("SlashCmdList.SMOOTHANIMATEDBARS('capture')")
check(cp.eval("SmoothAnimatedBarsCapture.shown") and not cp.eval(f"{grid}.shown"),
      "the frames' capture still works after it, on its own grid")
check(not any("Error in" in m for m in chat(cp)), "no errors")

print("== enemy nameplates")


def plate_bar(token):
    return f"__plates['{token}'].UnitFrame.HealthBarsContainer.healthBar"


np = session()
np.execute("__showPlate('nameplate1', { reaction = 2 })")
run(np, 0.3)
check(np.eval("(select(2, __liquid(" + plate_bar("nameplate1") + ")))") == 0
      and np.eval(plate_bar("nameplate1") + ".fill.alpha") == 1, "off by default: a plate keeps the game's own fill")
np.execute(plate_bar("nameplate1") + ".level = 7; __settings.plateHealth:SetValue(true)")
run(np, 0.3)
check(np.eval("(select(2, __ours(" + plate_bar("nameplate1") + "))).useParentLevel") is False
      and np.eval("(select(2, __ours(" + plate_bar("nameplate1") + "))).level") == 8,
      "a plate's liquid sits a level above its bar, over the plate's dark background")
n, shown, alpha, masked, free = np.eval("__liquid(" + plate_bar("nameplate1") + ")")
check(shown > 0 and alpha == 0, f"turned on: a plate already showing gets the liquid, game fill hidden ({shown}/{n})")
check(masked > 0 and free == 64 and np.eval("""(function()
    local bar = """ + plate_bar("nameplate1") + """
    local mask = __ns.Bars.PlateMask(bar)
    local a, b = mask.points.TOPLEFT, mask.points.BOTTOMRIGHT
    return mask.kind == "MaskTexture" and mask.file:sub(-15) =="Media\\\\PlateMask" and a.rel == bar and b.rel == bar
end)()"""), f"a plate's bar has no mask, so the liquid takes the addon's own in the fill's shape, laid over the bar; "
      f"motes free ({masked} masked, {free} free)")
check(np.eval("""(function()
    local bar = """ + plate_bar("nameplate1") + """
    local _, clip = __ours(bar)
    local tl, br = clip.points.TOPLEFT, clip.points.BOTTOMRIGHT
    return clip.clipsChildren and tl.rel == bar and tl.x == 0 and tl.y == 0 and br.x == 0 and br.y == 0
end)()"""), "its clip frame is the bar itself, so the waves stop at the bar's end")
r, g, b = np.eval("__tint(" + plate_bar("nameplate1") + ")")
check(r > 0.5 and g < 0.4, f"follows the target's colour, which follows the player's game colour: the plate's own red "
      f"({r:.2f}, {g:.2f}, {b:.2f})")
np.execute(plate_bar("nameplate1") + ":SetStatusBarColor(0.5, 0.5, 0.5)")
run(np, 0.7)
r, g, b = np.eval("__tint(" + plate_bar("nameplate1") + ")")
check(abs(r - g) < 0.1 and abs(g - b) < 0.1, f"a tapped mob's grey plate turns the liquid grey ({r:.2f}, {g:.2f}, {b:.2f})")
run(np, 3)
np.execute("__fire('UNIT_HEALTH', 'nameplate1')")
run(np, 0.1)
check(np.eval("(select(2, __liquid(" + plate_bar("nameplate1") + ")))") > 0, "a health change on the plate keeps it going")
np.execute("__showPlate('nameplate2', { friendly = true, reaction = 5 })")
run(np, 0.2)
check(np.eval("(select(2, __liquid(" + plate_bar("nameplate2") + ")))") == 0
      and np.eval(plate_bar("nameplate2") + ".fill.alpha") == 1, "a friendly plate is left alone")
np.execute("__showPlate('nameplate3', { reaction = 2 }, { forbidden = true })")
run(np, 1.5)
check(not any("Error in" in m for m in chat(np)), "a forbidden plate (friendly, in an instance) is passed over without an error")
np.execute("__showPlate('nameplate4', { reaction = 2 }, { late = true })")
run(np, 0.1)
check(np.eval("(select(2, __liquid(" + plate_bar("nameplate4") + ")))") > 0,
      "a plate that gets its unit frame after the event still gets the liquid")
np.execute("__bar1 = " + plate_bar("nameplate1") + "; __hidePlate('nameplate1')")
bar1 = np.eval("__bar1")
run(np, 0.1)
check(bar1.fill.alpha == 1 and not np.eval("(function(b) local _, clip = __ours(b); return clip.shown end)")(bar1),
      "a plate that goes gives its bar back the game's fill before the game reuses it")
np.execute("__showPlate('nameplate5', { friendly = true, reaction = 5 })")
run(np, 0.2)
check(np.eval(plate_bar("nameplate5") + " == __bar1") and bar1.fill.alpha == 1,
      "the game hands that bar to a friendly unit: it keeps the game's fill")
np.execute("__hidePlate('nameplate5'); __showPlate('nameplate6', { reaction = 2 })")
run(np, 0.2)
check(np.eval(plate_bar("nameplate6") + " == __bar1") and np.eval("(select(2, __liquid(" + plate_bar("nameplate6") + ")))") > 0,
      "and to an enemy again: the same liquid comes back on it")
np.execute("for i = 7, 30 do __showPlate('nameplate' .. i, { reaction = 2 }) end")
run(np, 0.3)
live = np.eval("""(function()
    local n = 0
    for token, base in pairs(__plates) do
        local bar = base.UnitFrame and base.UnitFrame.HealthBarsContainer.healthBar
        if bar and select(2, __liquid(bar)) > 0 then n = n + 1 end
    end
    return n
end)()""")
check(live == 15, f"a crowd of 26 enemies: the liquid on 15 of them, the rest keep the game's fill ({live})")
np.execute("__hidePlate('nameplate6')")
run(np, 0.1)
live2 = np.eval("""(function()
    local n = 0
    for token, base in pairs(__plates) do
        local bar = base.UnitFrame and base.UnitFrame.HealthBarsContainer.healthBar
        if bar and select(2, __liquid(bar)) > 0 then n = n + 1 end
    end
    return n
end)()""")
check(live2 == 15, f"one of them goes: a waiting plate takes its place ({live2})")
np.execute("__units.nameplate7.friendly = true; __fire('UNIT_FACTION', 'nameplate7')")
run(np, 0.1)
check(np.eval(plate_bar("nameplate7") + ".fill.alpha") == 1, "a mob turning friendly gets the game's fill back")
np.execute("SlashCmdList.SMOOTHANIMATEDBARS('debug')")
check(any("enemy nameplates: on, 15 with the liquid" in m for m in chat(np)), "/sab debug counts the plates")
run(np, 11)
np.execute("__chat = {}; SlashCmdList.SMOOTHANIMATEDBARS('perf')")
perf = chat(np)
check(any("unit frames: 12 liquids" in m for m in perf) and any("nameplates: 15 liquids" in m for m in perf)
      and any("per nameplate" in m for m in perf) and any("addon memory" in m for m in perf),
      "/sab perf times the unit frames and the plates apart: " + " | ".join(perf))
np.execute("__combat = true; SlashCmdList.SMOOTHANIMATEDBARS('perf 26 Mobs Pulled'); __combat = false")
check(np.eval("#SmoothAnimatedBarsDB.perfLog") == 2 and np.eval("SmoothAnimatedBarsDB.perfLog[2].note") == "26 Mobs Pulled"
      and np.eval("#SmoothAnimatedBarsDB.perfLog[2].seconds") == 10 and np.eval("SmoothAnimatedBarsDB.perfLog[2].combat")
      and np.eval("SmoothAnimatedBarsDB.perfLog[2].zone") == "Elwynn Forest"
      and any("/reload writes it" in m for m in chat(np)),
      "/sab perf saves each report in the saved variables, with a note as typed, the zone and combat")
# The client writes the saved variables as plain Lua; perf_report.py reads that back into a text report.
saved = np.eval("""(function()
    local function ser(v, ind)
        if type(v) == "table" then
            local parts = {}
            for k, x in pairs(v) do
                local key = type(k) == "number" and ("[" .. k .. "]") or ("[" .. string.format("%q", k) .. "]")
                parts[#parts + 1] = ind .. "  " .. key .. " = " .. ser(x, ind .. "  ") .. ","
            end
            return "{\\n" .. table.concat(parts, "\\n") .. "\\n" .. ind .. "}"
        elseif type(v) == "string" then return string.format("%q", v)
        else return tostring(v) end
    end
    return "SmoothAnimatedBarsDB = " .. ser({ perfLog = SmoothAnimatedBarsDB.perfLog }, "") .. "\\n"
end)()""")
sys.path.insert(0, os.path.join(HERE, ".."))
import tempfile  # noqa: E402
import perf_report  # noqa: E402
with tempfile.TemporaryDirectory() as tmp:
    sv = os.path.join(tmp, "SmoothAnimatedBars.lua")
    with open(sv, "w", encoding="utf-8") as f:
        f.write(saved)
    text = "\n".join(perf_report.report(perf_report.load_log(sv), sv))
check("26 Mobs Pulled" in text and "Elwynn Forest *" in text and text.count("--- ") == 2,
      "perf_report.py turns the saved reports into a text file: a line each, then each second")
np.execute("SlashCmdList.SMOOTHANIMATEDBARS('perf clear')")
check(np.eval("SmoothAnimatedBarsDB.perfLog") is None, "/sab perf clear forgets them")
np.execute("__chat = {}; SlashCmdList.SMOOTHANIMATEDBARS('perf reset'); SlashCmdList.SMOOTHANIMATEDBARS('perf')")
check(any("Nothing measured yet" in m for m in chat(np)) and np.eval("SmoothAnimatedBarsDB.perfLog") is None,
      "/sab perf reset starts over, and nothing is saved until something is measured")
np.execute("__settings.plateHealth:SetValue(false)")
run(np, 0.2)
check(np.eval("""(function()
    for token, base in pairs(__plates) do
        local bar = base.UnitFrame and base.UnitFrame.HealthBarsContainer.healthBar
        if bar and (select(2, __liquid(bar)) > 0 or bar.fill.alpha ~= 1) then return false end
    end
    return true
end)()"""), "turned off: every plate has the game's fill again")
check(np.eval("(select(2, __liquid(PlayerFrame.healthbar)))") > 0, "and the unit frames keep theirs")
np.execute("SlashCmdList.SMOOTHANIMATEDBARS('off')")
run(np, 0.2)
check(np.eval("SmoothAnimatedBarsDB.plateHealth") is False, "/sab off leaves the plate setting as it was")
check(not any("Error in" in m for m in chat(np)), "no errors")

print("== DoT marker on enemy nameplates")
pd = session("{ setupDone = true, heals = false, manaBuild = false, plateHealth = true }")
pd.execute("""
    __spells[172] = { 'Corruption', 'Corrupts the target, causing 90 Shadow damage over 18 sec.' }
    __spells[348] = { 'Immolate', 'Burns the enemy for 11 Fire damage and then an additional 20 Fire damage over 15 sec.' }
    function __cast(id, guid)
        __fire('UNIT_SPELLCAST_SENT', 'player', __target and __target.name or '', guid, id)
        __fire('UNIT_SPELLCAST_SUCCEEDED', 'player', guid, id)
    end
    BOAR = { guid = 'Creature-0-1-2-3-299-0001', name = 'Mottled Boar', reaction = 2 }
    WOLF = { guid = 'Creature-0-1-2-3-525-0002', name = 'Prowler', reaction = 2 }
    __showPlate('nameplate1', BOAR)
    __showPlate('nameplate2', WOLF)
    function __pbar(token) return __plates[token].UnitFrame.HealthBarsContainer.healthBar end
    function __pm(token)
        local _, _, markers = __ns.Marker.State()
        return markers[__pbar(token)]
    end
    function __aim(t) __target = t; __fire('PLAYER_TARGET_CHANGED') end
""")
run(pd, 0.3)
check(not pd.eval("__ns.Dots.IsEnabled()"), "off by default: no tracking for the plates either")
pd.execute("__settings.plateDots:SetValue(true)")
run(pd, 0.3)
check(pd.eval("__ns.Dots.IsEnabled()") and pd.eval("SmoothAnimatedBarsDB.dots") is False,
      "on: tracking runs for the plates, with the target frame's marker still off")
check(pd.eval("__pm('nameplate1')") is None, "a plate is given no marker before the mob carries your DoTs")
pd.execute("__aim(BOAR); __cast(172, 'Cast-1')")
run(pd, 1)
check(pd.eval("__pm('nameplate1') ~= nil and __pm('nameplate1').clip.shown")
      and pd.eval("__pm('nameplate1').liquids[1].themeKey") == "shadow"
      and pd.eval("__pm('nameplate1').liquids[1].value") == 90 and pd.eval("__pm('nameplate1').liquids[1].run.value") > 85,
      "Corruption on the boar: a Shadow liquid of 90 on its plate")
check(pd.eval("__pm('nameplate1').clip.parent == __pbar('nameplate1')")
      and pd.eval("__pm('nameplate1').clip.points.TOPLEFT.y") == 0
      and pd.eval("__pm('nameplate1').clip.points.BOTTOMRIGHT.x") == 0,
      "on the plate's bar, clipped to it")
check(pd.eval("""(function()
    local _, _, mover = __ours(__pbar('nameplate1'))
    local a = mover.points.TOPRIGHT
    return a.rel == __pm('nameplate1').endFill and a.relPoint == 'TOPLEFT'
end)()"""), "the plate's health liquid draws back to where its health will end")
check(pd.eval("""(function()
    local mask = __ns.Bars.PlateMask(__pbar('nameplate1'))
    for _, t in ipairs(__pm('nameplate1').liquids[1].liquid.textures) do
        if t.masks and t.masks[1] == mask then return true end
    end
end)()"""), "the plate's DoT liquids take its mask too, so they keep to the bar's cut corners")
check(not pd.eval("__pm('nameplate1').window.shown") and not pd.eval("__pm('nameplate1').hasIcon"),
      "no kill icon on a plate")
check(pd.eval("__pm('nameplate1').liquids[1].liquid.body.sub") == -7, "under the plate's health liquid")
check(pd.eval("__pm('nameplate1').clip.useParentLevel") is False
      and pd.eval("__pm('nameplate1').clip.level") == pd.eval("__pbar('nameplate1'):GetFrameLevel()") + 1,
      "the plate's DoT liquids a level above the bar too")
check(not pd.eval("(__ns.Marker.State())"), "the target frame's marker is not built while DoT Marker is off")
pd.execute("__aim(WOLF); __cast(348, 'Cast-2')")
run(pd, 1)
check(pd.eval("__pm('nameplate1').clip.shown") and pd.eval("__pm('nameplate2').clip.shown")
      and pd.eval("__pm('nameplate2').liquids[1].themeKey") == "fire"
      and pd.eval("__pm('nameplate1').liquids[1].themeKey") == "shadow",
      "Immolate on the wolf: Fire on its plate, and the boar left behind keeps its Corruption")
pd.execute("""
    __spells[6546] = { 'Rend', 'Wounds the target causing them to bleed for 28 damage over 12 sec.' }
    RAT = { guid = 'Creature-0-1-2-3-77-0005', name = 'Tunnel Rat', reaction = 2 }
    __showPlate('nameplate5', RAT)
    __aim(RAT); __cast(6546, 'Cast-3')
""")
run(pd, 1)
fill = pd.eval("__pm('nameplate5').liquids[1].liquid.theme.fillB")
health = pd.eval("__ns.Bars.Liquid(__pbar('nameplate5')).theme.fillB")
target_blood = pd.eval("__ns.Bars.Theme('blood').fillB")
check(health[1] < 0.7 and health[1] > 0.5,
      f"a red plate's health takes the game's deep red, the plate's colour at the fill's 65% ({health[1]:.2f}, "
      f"{health[2]:.2f}, {health[3]:.2f})")
check(pd.eval("__pm('nameplate5').liquids[1].themeKey") == "blood"
      and all(abs(fill[i] - target_blood[i]) < 1e-9 for i in (1, 2, 3)),
      f"a bleed on a plate is the target frame's Blood, the same colour ({fill[1]}, {fill[2]}, {fill[3]})")
pd.execute("__hidePlate('nameplate5')")
run(pd, 0.3)
pd.execute("__showPlate('nameplate3', { guid = 'Creature-0-1-2-3-99-0003', name = 'Kobold', reaction = 2 })")
run(pd, 0.3)
check(pd.eval("__pm('nameplate3') == nil or not __pm('nameplate3').clip.shown"), "a mob without your DoTs shows no marker")
pd.execute("__units.nameplate2.dead = true")
run(pd, 0.3)
check(not pd.eval("__pm('nameplate2').clip.shown"), "a dead mob's plate: marker hidden")
pd.execute("__bar1 = __pbar('nameplate1'); __hidePlate('nameplate1')")
run(pd, 0.3)
check(pd.eval("(function() local _, _, m = __ns.Marker.State(); "
              "return not m[__bar1].clip.shown and not m[__bar1].live end)()"),
      "the boar's plate goes: its marker hides")
pd.execute("__showPlate('nameplate4', { guid = 'Creature-0-1-2-3-99-0004', name = 'Kobold', reaction = 2 })")
run(pd, 0.3)
check(pd.eval("__pbar('nameplate4') == __bar1") and not pd.eval("__pm('nameplate4').clip.shown")
      and pd.eval("""(function()
    local _, _, mover = __ours(__bar1)
    return mover.points.TOPRIGHT.relPoint == 'TOPRIGHT'
end)()"""), "the game gives that bar to an undotted mob: no marker, its health liquid on its own health's edge")
pd.execute("__hidePlate('nameplate4'); __showPlate('nameplate1', BOAR)")
run(pd, 0.3)
check(pd.eval("__pm('nameplate1').clip.shown") and pd.eval("__pm('nameplate1').liquids[1].themeKey") == "shadow",
      "the boar's plate shows again: its Corruption is still there")
pd.execute("__settings.plateHealth:SetValue(false)")
run(pd, 0.3)
check(pd.eval("(function() local _, _, m = __ns.Marker.State(); "
              "for _, x in pairs(m) do if x.clip.shown then return false end end return true end)()")
      and not pd.eval("__ns.Dots.IsEnabled()"),
      "Enemy Nameplates off: the plates' markers go too, and tracking stops")
pd.execute("SlashCmdList.SMOOTHANIMATEDBARS('dots')")
check(any("DoT marker on nameplates: off" in m for m in chat(pd)), "/sab dots reports the plates' marker")
check(not any("Error in" in m for m in chat(pd)), "no errors")

print("== probe for DoTs on the player")
sp = session()
check(not sp.eval("__ns.SelfProbe.IsListening()"), "off by default: listens to nothing")
sp.execute("SlashCmdList.SMOOTHANIMATEDBARS('self on')")
sp.execute("""
    __playerDebuffs = { { name = 'Poison', spellId = 744, auraInstanceID = 7, duration = 30, expirationTime = 130,
                          dispelName = 'Poison', isHarmful = true } }
    __spells[744] = { 'Poison', 'Inflicts 10 Nature damage every 3 sec for 30 sec.' }
    __combat = true
    __fire('UNIT_AURA', 'player', __secret())
    __fire('UNIT_COMBAT', 'player', 'WOUND', '', __secret(), 8)
    __fire('UNIT_COMBAT', 'target', 'WOUND', '', 5, 1)
""")
sp.execute("SlashCmdList.SMOOTHANIMATEDBARS('self')")
lines = chat(sp)
check(any("UNIT_AURA (combat)" in m and "payload 0/1" in m for m in lines), "a secret UNIT_AURA payload counts as secret")
check(any("GetUnitAuras (combat)" in m and "whole aura 0/1" in m for m in lines), "and so does a secret debuff")
check(any("UNIT_COMBAT (combat)" in m and "amount 0/1" in m and "school 1/0" in m for m in lines),
      "a hit on the player: secret amount, readable school")
check(sp.eval("#SmoothAnimatedBarsDB.selfProbe.events") > 0, "the events are kept for /reload")
sp.execute("""
    __aurasReadable = true; __combat = false
    __fire('UNIT_AURA', 'player', { addedAuras = { __playerDebuffs[1] } })
""")
events = list(sp.eval("SmoothAnimatedBarsDB.selfProbe.events").values())
check(any("spellId=744" in e and "Nature damage every 3 sec" in e and "GetRemainingDuration=30" in e for e in events),
      "readable debuffs are logged with their spell, description and duration")
sp.execute("SlashCmdList.SMOOTHANIMATEDBARS('self clear')")
check(sp.eval("#SmoothAnimatedBarsDB.selfProbe.events") == 0, "/sab self clear starts afresh")
sp2 = session("{ setupDone = true, selfProbe = { on = true } }")
check(sp2.eval("__ns.SelfProbe.IsListening()"), "stays on across a reload")
sp2.execute("SlashCmdList.SMOOTHANIMATEDBARS('self off')")
check(not sp2.eval("__ns.SelfProbe.IsListening()") and not sp2.eval("SmoothAnimatedBarsDB.selfProbe.on"), "/sab self off stops it")
check(not any("ERROR" in e for e in events) and not any("Error in" in m for m in chat(sp)), "no errors")

print("== friendly nameplates")
fp = session("{ setupDone = true, heals = false, manaBuild = false, plateHealth = true }")
fp.execute("""
    function __pbar(token) return __plates[token].UnitFrame.HealthBarsContainer.healthBar end
    function __shown(token) return (select(2, __liquid(__pbar(token)))) > 0 end
    __showPlate('nameplate1', { reaction = 2 })
    __showPlate('nameplate2', { friendly = true, reaction = 5, color = { 0.1, 0.9, 0.1 } })
""")
run(fp, 0.3)
check(fp.eval("__shown('nameplate1')") and not fp.eval("__shown('nameplate2')")
      and fp.eval("__pbar('nameplate2').fill.alpha") == 1, "off by default: enemies only, friends keep the game's bar")
fp.execute("__settings.plateFriendly:SetValue(true)")
run(fp, 0.3)
check(fp.eval("__shown('nameplate2')") and fp.eval("__pbar('nameplate2').fill.alpha") == 0,
      "turned on: a friendly plate already showing gets the liquid")
r, g, b = fp.eval("__tint(__pbar('nameplate2'))")
check(g > 0.5 and r < 0.4, f"in the plate's own colour, green for a friendly NPC ({r:.2f}, {g:.2f}, {b:.2f})")
check(fp.eval("__ns.Bars.PlateMask(__pbar('nameplate2')) ~= nil")
      and fp.eval("(select(2, __ours(__pbar('nameplate2')))).useParentLevel") is False
      and fp.eval("__ns.Bars.Liquid(__pbar('nameplate2')).theme.fillB[2]") < 0.8,
      "a friendly plate as an enemy one: the plate mask, a level above the bar, the game's shade of its colour")
fp.execute("__showPlate('nameplate3', { isOtherPlayer = true, friendly = true, reaction = 5, class = 'MAGE', color = { 0.1, 0.9, 0.1 } })")
run(fp, 0.3)
check(fp.eval("__shown('nameplate3')"), "another player's plate gets it too")
fp.execute("__settings.plateHealthColor:SetValue('fire')")
run(fp, 0.7)
r, g, b = fp.eval("__tint(__pbar('nameplate2'))")
r1, g1, b1 = fp.eval("__tint(__pbar('nameplate1'))")
check(g > 0.5 and r < 0.4 and r1 > 0.6, f"friends keep their own colour while the enemies take Fire ({r:.2f}, {g:.2f}, {b:.2f})")
fp.execute("__settings.plateFriendlyColor:SetValue('same')")
run(fp, 0.7)
r, g, b = fp.eval("__tint(__pbar('nameplate2'))")
check(abs(r - r1) < 0.05 and abs(g - g1) < 0.05, f"Same as Enemy Nameplates: Fire too ({r:.2f}, {g:.2f}, {b:.2f})")
def mob_rows(lua):
    rows = lua.eval("__settingsRows()")
    return [rows[i] for i in range(1, len(rows) + 1) if rows[i].key == "mobClassColor"]


check(not any(r.frame.shown for r in mob_rows(fp)), "no nameplate or target on Class Color: Class Color on Mobs hidden")
fp.execute("__settings.plateFriendlyColor:SetValue('class')")
run(fp, 0.7)
under_target, under_plates = mob_rows(fp)
check(under_plates.frame.shown and under_plates.indent and not under_target.frame.shown,
      "friendly nameplates on Class Color: Class Color on Mobs shows under Nameplates, not under Target")
check(fp.eval("""(function()
    local found = {}
    for _, r in ipairs(__settingsRows()) do
        if r.key == "mobClassColor" then found[#found + 1] = r.frame.initializer.data.setting end
    end
    return #found == 2 and found[1] == found[2]
end)()"""), "both rows are the same setting")
r, g, b = fp.eval("__tint(__pbar('nameplate3'))")
check(b > 0.6 and r < 0.5, f"Class Color: another player in their class colour, a mage blue ({r:.2f}, {g:.2f}, {b:.2f})")
r, g, b = fp.eval("__tint(__pbar('nameplate2'))")
check(g > 0.5 and r < 0.4, f"and a friendly NPC by its reaction, green ({r:.2f}, {g:.2f}, {b:.2f})")
fp.execute("__settings.plateFriendlyColor:SetValue('game'); __settings.plateHealthColor:SetValue('class')")
run(fp, 0.3)
check(mob_rows(fp)[1].frame.shown, "enemy nameplates on Class Color show it under Nameplates too")
fp.execute("__settings.plateHealthColor:SetValue('same')")
run(fp, 0.7)
fp.execute("__showPlate('nameplate4', { friendly = true, reaction = 5 }, { forbidden = true })")
run(fp, 1.5)
check(not any("Error in" in m for m in chat(fp)), "a forbidden friendly plate (in an instance) is passed over without an error")
fp.execute("__settings.plateDots:SetValue(true); __settings.plateHealth:SetValue(false)")
run(fp, 0.3)
check(not fp.eval("__shown('nameplate1')") and fp.eval("__pbar('nameplate1').fill.alpha") == 1
      and fp.eval("__shown('nameplate2')") and fp.eval("__shown('nameplate3')"),
      "enemies off, friends on: each side on its own")
check(fp.eval("next(__ns.Bars.Plates()) == nil"), "the DoT marker is offered enemy plates only")
fp.execute("__settings.plateHealth:SetValue(true)")
fp.execute("for i = 10, 30 do __showPlate('nameplate' .. i, { friendly = true, isOtherPlayer = true, reaction = 5 }) end")
fp.execute("for i = 40, 44 do __showPlate('nameplate' .. i, { reaction = 2 }) end")
run(fp, 0.3)
counts = fp.eval("""(function()
    local friends, enemies = 0, 0
    for token, base in pairs(__plates) do
        local bar = base.UnitFrame and base.UnitFrame.HealthBarsContainer.healthBar
        if bar and select(2, __liquid(bar)) > 0 then
            if __units[token].friendly then friends = friends + 1 else enemies = enemies + 1 end
        end
    end
    return friends .. "/" .. enemies
end)()""")
check(counts == "10/6", f"a city's crowd of friends: 10 of them get it, and the enemies keep their own slots ({counts})")
fp.execute("SlashCmdList.SMOOTHANIMATEDBARS('debug')")
check(any("friendly: on, 10 (at most 10)" in m for m in chat(fp)), "/sab debug counts each side")
fp.execute("__settings.plateFriendly:SetValue(false)")
run(fp, 0.3)
check(not fp.eval("__shown('nameplate2')") and fp.eval("__pbar('nameplate2').fill.alpha") == 1
      and fp.eval("__shown('nameplate40')"), "friends off again: their bars go back to the game's, the enemies keep theirs")
check(not any("Error in" in m for m in chat(fp)), "no errors")

if failures:
    print(f"\n{len(failures)} check(s) failed:")
    for f in failures:
        print("  -", f)
    sys.exit(1)
print("\nok")
