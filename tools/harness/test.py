"""Tests: the liquid on the unit frame bars, the settings page, slash commands and every theme,
against the WoW mock of the Forever client, where health and power are secret.

Usage: python test.py <addon dir>
Prints each check and exits 1 if any fails (a Lua error also fails with a traceback).
"""
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
    -- The liquid's frames on a bar. It builds them before the DoT marker builds its own there.
    function __ours(bar)
        local proxy, clip, mover
        for _, f in ipairs(__frames) do
            if f.parent == bar then
                if f.SetValue then proxy = proxy or f else clip = clip or f end
            end
        end
        for _, f in ipairs(__frames) do
            if clip and f.parent == clip then mover = f end
        end
        return proxy, clip, mover
    end
    function __liquid(bar)
        local _, _, mover = __ours(bar)
        local n, shown, masked, free = 0, 0, 0, 0
        for _, r in ipairs(__regions) do
            if mover and r.parent == mover and r.kind == "Texture" then
                n = n + 1
                if r.shown then shown = shown + 1 end
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
dbg = [m for m in chat(lua) if "value secret" in m]
check(len(dbg) == 4 and all("live yes" in m and "mask yes" in m and "error" not in m for m in dbg),
      f"/sab debug reports each bar ({len(dbg)} lines)")
check(not any("Error in" in m for m in chat(lua)), "no errors")

print("== settings")
rows = lua.eval("__settingsRows()")
rows = [rows[i] for i in range(1, len(rows) + 1)]
keys = [r.key for r in rows if r.key]
check(keys == ["playerHealth", "playerPower", "targetHealth", "targetPower", "healthColor", "powerColor",
               "waves", "swirl", "bubbles", "sparkles", "ambient", "lightning", "dots", "dotKillIcon"],
      f"settings page rows: {keys}")
check(not lua.eval("__sharedListTainted"), "nothing added to the game's shared settings list (Forever: Social blocked)")
options = [o for o in rows if o.key == "healthColor"][0].options
labels = [options[i].label for i in range(1, len(options) + 1)]
check(labels[0] == "Game Colour" and "Class Color" in labels and "Item Quality" not in labels and len(labels) == 25,
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
      and wz.eval("__ns.Wizard.State().ui.step.text") == "Step 1 of 4"
      and not wz.eval("__ns.Wizard.State().ui.back:IsEnabled()"),
      "starts from the current settings: all four bars picked, step 1 of 4, no Back")
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
wz.execute("__press('next'); __pick('effects', 'still')")
check(wz.eval("SmoothAnimatedBarsDB.waves") is False and wz.eval("SmoothAnimatedBarsDB.sparkles") is False
      and wz.eval("__ns.Wizard.State().ui.next.text") == "Next", "effects: Still turns them off")
wz.execute("__press('next')")
check(wz.eval("__ns.Wizard.State().page") == "dots" and wz.eval("__card('dots', 'off').radio.checked")
      and wz.eval("__ns.Wizard.State().ui.next.text") == "Finish",
      "DoTs: the last step, Off picked as the setting starts, says Finish")
wz.execute("__pick('dots', 'marker')")
check(wz.eval("SmoothAnimatedBarsDB.dots") is True and wz.eval("SmoothAnimatedBarsDB.dotKillIcon") is False
      and wz.eval("__ns.Dots.IsEnabled()") and wz.eval("__card('dots', 'marker').radio.checked"),
      "Just the marker: tracking on at once, no skull")
wz.execute("__press('skip')")
check(not wz.eval("SmoothAnimatedBarsSetup.shown") and wz.eval("SmoothAnimatedBarsDB.targetHealth") is True
      and wz.eval("SmoothAnimatedBarsDB.healthColor") == "game" and wz.eval("SmoothAnimatedBarsDB.waves") is True
      and wz.eval("SmoothAnimatedBarsDB.dots") is False and not wz.eval("__ns.Dots.IsEnabled()")
      and wz.eval("SmoothAnimatedBarsDB.setupDone") is True, "Skip puts every setting back and does not ask again")
run(wz, 0.2)
check(wz.eval("(select(2, __liquid(TargetFrame.healthbar)))") > 0, "and the bars follow")
wz.execute("__fire('PLAYER_ENTERING_WORLD', false, true)")
run(wz, 3)
check(not wz.eval("SmoothAnimatedBarsSetup.shown"), "not opened again on the next login")
wz.execute("SlashCmdList.SMOOTHANIMATEDBARS('setup')")
wz.execute("__pick('bars', 'health'); __press('next'); __pick('powerColor', 'class'); __press('next');"
           " __pick('effects', 'gentle'); __press('next'); __pick('dots', 'both'); __press('next')")
check(not wz.eval("SmoothAnimatedBarsSetup.shown") and wz.eval("SmoothAnimatedBarsDB.playerPower") is False
      and wz.eval("SmoothAnimatedBarsDB.powerColor") == "class" and wz.eval("SmoothAnimatedBarsDB.swirl") is True
      and wz.eval("SmoothAnimatedBarsDB.bubbles") is False and wz.eval("SmoothAnimatedBarsDB.dots") is True
      and wz.eval("SmoothAnimatedBarsDB.dotKillIcon") is True and any("All set" in m for m in chat(wz)),
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
check(pv.eval("__pm().liquids[1].themeKey") == "void" and pv.eval("__pm().liquids[2].themeKey") == "fire"
      and pv.eval("__pm().liquids[2].pool.shown"), "the preview shows Corruption as Void and Immolate as Fire")
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
dm = session()
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
check(dm.eval("__total()") == 90 and dm.eval("__m().clip.shown") and dm.eval("__d(1).themeKey") == "void"
      and dm.eval("__d(1).pool.shown") and not dm.eval("__d(2).pool.shown"),
      "Corruption: 90 damage to come, shown as one Void liquid (Shadow)")
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
      and dm.eval("__d(1).themeKey") == "void" and dm.eval("__d(2).themeKey") == "fire" and dm.eval("__d(2).pool.shown"),
      "Immolate's 20 more: Corruption stays Void at the front, Immolate a Fire liquid of its own behind it")
check(dm.eval("__d(2).mover.points.TOPRIGHT.rel == __d(1).fill") and dm.eval("__d(2).mover.points.TOPRIGHT.relPoint") == "TOPLEFT"
      and dm.eval("__d(2).pool.points.TOPLEFT.rel == __d(2).fill") and dm.eval("__d(2).pool.points.TOPLEFT.x") == -6
      and dm.eval("__d(2).pool.points.BOTTOMRIGHT.rel == __d(1).fill") and dm.eval("__d(2).pool.points.BOTTOMRIGHT.x") == 10,
      "the Fire liquid hangs on the end of the Void one, its waves reaching over it")
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
dm.execute("__target.dead = true")
run(dm, 0.2)
dm.execute("SlashCmdList.SMOOTHANIMATEDBARS('dots')")
check(any(m.startswith("|cff40d060Smooth Animated Bars|r DoT marker: on") for m in chat(dm))
      and any("CAST Corruption" in m for m in chat(dm)), "/sab dots reports the marker and the tracking")
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

if failures:
    print(f"\n{len(failures)} check(s) failed:")
    for f in failures:
        print("  -", f)
    sys.exit(1)
print("\nok")
