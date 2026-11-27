# Performance

What the addon costs in game, how it is measured, and what was cut. The tools are in [DEVELOPMENT.md](../DEVELOPMENT.md#measuring).

## Measuring the cost

`/sab perf` times the updates with `debugprofilestop`, unit frames and plates apart, and of the unit frames the Personal
Resource Display's and the party's (`PerfGroup`); the mock's times are mostly the mock's own cost, so only the game's
say anything. What the mock can count is widget calls per frame (wrap the mock's Region methods), which is what costs in
the client. In a party in combat the unit frames took 4.3 ms a frame (15% at 36 fps) and 4.6 ms (25% at 55 fps) in game;
counted in the mock, the eight party liquids, stirred all fight and so never quiet, made more calls than the player's,
target's and display's together. So party liquids update at most 20 times a second and stir at most every 1.2 s
(`PARTY_FPS`, `PARTY_STIR_EVERY`), and their fronts have a slice per 1.25 px of height (8 and 6 instead of 15;
`Liquid.New`'s `rows`, looked the same zoomed in). `Liquid.lua` shows and hides its textures only when that changes
(`On`, `Off`): a third of a quiet liquid's calls were Show and Hide on textures already so. Together a party's eight
went from about 4500 calls a frame to 820 in a stream of events, and the player's and target's four from 2700 to 2100.
`/sab perf` also lists the six costliest unit frame bars with their Rage Fury's share (`PerfBars`). After the party
changes, in game in a party in combat at 24 fps: party 0.2 ms a frame per liquid, the full-size bars about 0.85 ms each,
the display's two 2.1 ms with its fury. Matched against `tools/harness/bench.py`'s call counts for the same bars, each
widget call cost about 1.7 to 2 microseconds in game. The bench then showed the fury at nearly 40% of all calls in
combat: it ran at 30 fps even where its curve has faded it out (below half rage), which the addon cannot know. So the
fury runs at 20 fps (`FURY_FPS`), and every liquid's front has a slice per 1.25 px of height (`Liquid.RowsFor`: 15 on 20
px health, 8 on 10 px bars), all liquids of a height alike, their fronts matched by position (`SliceAt`) where counts
differ. Together, by the bench, a warrior with a party of three in combat went from about 9.9 ms to 6.1.

Reported by a player (1.14.1): 5 to 10% CPU, 15% and more at peaks, with only the player and target on and every effect
up; the bench agreed (player and target in combat about 1350 calls, 2.6 ms, a frame at 60 fps, the same per frame at any
frame rate as a moving liquid is drawn every frame).

1.14.1 against 1.14.2, end to end (`bench.py --party 0 --only player --ref v1.14.1 --fps 100`, a warrior's player and
target with the Rage Fury, offline): quiet calls 402 to 150 (-63%), combat calls 1520 to 307 (-80%), combat Lua work
34.4k to 13.5k instructions a frame (-61%). Lua is most of the cost in game (see the calibration below), so combat costs
well under half as much. In game the fights' slow frames went too: no frame over 5 ms in six windows, against 26 and 6
before (the third round).

Asked for: cheaper, with the look unchanged. Half of those calls were the layers' caps (seven layers, a cap per slice,
each placed, sized, given coordinates and alpha every update). Now (`Liquid.lua`): each cap is anchored between its
layer's main texture's far end and its slice's (`AnchorCaps`; a shown cap always ends where its slice does) and each tip
on its slice (`LayoutTips`), so the client lays them out; sizes, coordinates and points are set only when they change;
colours and alpha once they move by half an 8-bit step (`COLOR_STEP`); a layer's colour goes to its textures as they are
drawn, with the alpha in the same `SetVertexColor` (`LayerLook`); the gradients go to the body and slices only when they
change (`gradStamp`). By the bench: player and target in combat 1349 calls a frame to 673, quiet 416 to 162, the whole
set 46% fewer in combat, Lua work up about a tenth. `tools/harness/samelook.py` found every texture's place and
coordinates the same as before to float rounding in every scenario, colours within half a step.

Seen in game after that (the player's CPU addon, 124 fps, Bar Height on): 8 to 10% idle, about 20% in a fight alone; the
bench, run on the player's own saved variables (`bench.py --saved`, every frame but the player's and target's hidden),
agreed (about 880 calls, 1.7 ms, a frame in that fight). A third of the idle cost was asking every frame what no update
needed: whether each of the ~40 bars the addon knows shows (hidden party bars, the game's bars faded under Bar Height)
and whether each of the game's segments shows. So a hidden bar sleeps until our hidden bar on it gets an `OnShow` (the
client runs a frame's shown descendants' OnShow and OnHide with it; the mock now does too), the game's bars Bar Height
fades rest until it gives the frame back (`Bars.Sleep`, `Bars.Wake`, `Bars.Rest`; either is looked at again after
`SLEEP_CHECK` in case no wake came), and Bar Height mirrors the segments every frame only for `SEGMENT_FOLLOW` after an
event that changes them (`SEGMENT_EVENTS`, from Mainline `UnitFrame.lua`, listened to only while a frame is taller),
else at each poll. By the bench on those settings at 124 fps: idle with no target 466 calls a frame to 239. In a fight
the liquid's drawing is most of it, so Animation Frame Rate (`animationFps`, asked for as a setting; `Liquid:Due`) caps
how often a moving liquid updates, the bars', DoT marker's and heal marker's: 850 calls a frame Unlimited, 574 at 60,
418 at 30. Its place on the bar is the client's every frame either way.

Seen in game: the look unchanged (caps, tips, waking bars); `/sab perf` idle 0.30 ms a frame at 150 fps (0.41 before the
sleeping bars), a 1v1 fight at 100 fps 1.4 ms Unlimited and 1.15 at 60, with no difference to the eye at 60, so 60 is
the default (asked for). At 100 fps a cap of 60 is every other frame, and what runs every frame anyway stays, hence a
fifth, not half. `samelook.py` runs at Unlimited, so it compares the drawing, not the cap. The game's own profiler
(Numy's Addon Profiler reads `C_AddOnProfiler`) then counted about twice what `/sab perf` timed: `/sab perf` timed the
liquid alone, and the addon's memory swung 43 to 110 MB, garbage the game collects on the addon's time (spikes over 10
ms). Functions made each frame or poll (`pcall(function() ... end)` in Bar Height's copies, the markers' `Each`) and
tables (`{ GetRegions() }`, atlas lookups) were most of it; named functions and kept tables now, the mock's garbage
count 4.9 KB a frame idle to 0.6, and in game memory steady at 20 MB, no frame over 10 ms in a fight. `/sab perf` now
also times every part for the next 10 s (`ns.Timed` round every update, event handler and ticker, `Bars.TimeStep` inside
a bar's update, steps of a liquid's) with the game's profiler's figure. Bar Height's poll took about 2 ms ten times a
second (looks of hidden segments and icons, each segment reading the bars' places, every region scanned for other
addons' texts): 1.2 ms after (hidden ones skipped, a bar's place read once, the scan once a second).
`tools/harness/rig.py` (asked for: in game testing was slow) plays `/sab perf` in the mock with the player's saved
settings on a modelled clock. Its first costs were fitted to two reports (idle with a target at 121 fps, a 1v1 at 95)
and said the addon's own Lua, not its calls to the game, was most of the cost; that was wrong twice over. The Lua counts
(rig and `bench.py`) came from a count hook armed once, and in Lua 5.1 a hook's own instructions use up its count, so
they were about three times too high (most for loop-heavy code: `Simulate` four times); the hook now re-arms itself as
its last act, checked against a hook on every instruction. And with every part's Lua and calls growing together, two
reports cannot tell the two apart: refitted on true counts it still chose Lua, at an implausible 46 us a thousand
instructions. So `/sab perf calib` measures them in the client (each kind of widget call on a texture of its own, and
`Core.CalibLua`, whose instructions the rig counts exactly), and the rig uses those, the reports only checking them. Not
yet run in game. Lua cut meanwhile, the look exactly the same (`samelook.py`: colours within 0.00/255): `Simulate` in
one pass, `FrontOffset` worked out in `Draw`, the caps' helpers written out in `DrawLayer`, and each bar timed only
while `/sab perf` times every part; a fight on the player's settings (player and target only) 32.7 to 27.6 thousand
instructions a frame, 601 widget calls either way. Addons cannot write files, so each `/sab perf` is kept in
`SmoothAnimatedBarsDB.perfLog` (last 50), which the client writes on `/reload`; `tools/perf_report.py` turns the newest
saved file under Forever's WTF folder into `perf/perf_report.txt` (git-ignored).

## Measured in the client (/sab perf calib)

Run once in game (2026-11-26, 146 fps, a warrior), each call timed 4000 times on a texture of its own, the loop round it
(0.075 us a call, with `rawequal` in it) taken off: setters 0.14 to 0.22 us (`SetTexCoord` 0.14, `SetWidth` 0.15,
`SetAlpha` 0.16, `SetSize` 0.17, `SetVertexColor` 0.22), `SetPoint` 0.35, getters 0.12 to 0.15 (`IsVisible`, `GetWidth`,
`IsShown`), a StatusBar's `SetValue` 0.18. So widget calls cost about a tenth of the 1.7 to 2 us the bench had assumed,
which came from putting all of an in-game time on the calls. `Core.CalibLua` (the springs' arithmetic, 182422
instructions counted in the mock) took 1.40 ms: 7.7 ns an instruction.

With those costs the rig predicted a third to a quarter of two fights measured the same evening (all parts 0.48 ms
against 1.77, the bars' liquid 1.25 against 1.25 at 92 fps after the fit below): the gap was alike across parts that make
many widget calls and parts that make few (the heal marker), so it is in the Lua. Fitted freely to those two fights the
costs came out at 0.55 us a setter, 0.82 us an other game function (`UnitPowerPercent` with a curve, `GetTime`...) and 34
us a thousand Lua instructions, four and a half times the arithmetic's: the addon's own code is table lookups by name,
method and function calls, which cost far more than a tight loop's arithmetic. The rig now takes the widget calls'
costs as measured and fits only the Lua's and the other game functions' to the reports: 39 us a thousand instructions
and 0.59 us a game function, the bars' liquid predicted at 1.16 and 1.80 ms against 1.25 and 1.77 measured
(`rig_calibration.json`; the Rage Fury's step is under-predicted by about half). So the addon's Lua, above all its calls between
functions and its lookups, is most of what it costs, and widget calls a tenth or so.

By the rig at those costs, a fight at 92 fps (the player's and target's bars, Bar Height on): all parts 1.64 ms a frame
before the Lua cut in `Simulate`, `Draw` and `DrawLayer` and 1.51 after. Where it goes: drawing 0.60, the bars' inflow,
build-up and Rage Fury 0.25 (0.38 to 0.56 measured in game, more at high rage), lightning, bubbles and motes 0.24, Bar
Height every frame 0.12 and its poll 0.07, the waves 0.10.

## The third round (four agents, look exact)

The rig's fight now has a warrior's rage spends (`rig.py --casts`, 36 a minute by default): a spend makes the Rage Fury
burst for 1.1 s, when it updated every frame and threw 62 sparks, and a warrior spends often enough to be bursting most
of a fight. Without them the rig had under-predicted the fury step by half. Refitted with them on the two fights
(widget calls as measured, Lua 28 us a thousand instructions, game functions 0.96 us): the bars' liquid 1.27 and 1.79
ms against 1.25 and 1.77 measured, the steps within about a fifth.

Cut, every texture the same each frame (`samelook.py`, colours within 0.00/255), 1136 tests passing:

- Drawing (`Draw`, `DrawLayer`): each cap compares one key with its layer's (`sabKey`, `layer.key`, moved on by a new
  colour, alpha, hiding or file) instead of three tests; each slice's offsets down the texture kept per layer; a layer
  hidden whole is not hidden cap by cap again (`allOff`); `Place`, `Width`, `Alpha`, `On`, `Off`, `min`, `max`, `abs`,
  `FrontOffset` and a non-leader's `Wobble` written out; `Mix` into locals (an inflow made a table a frame).
- Particles: only particles in flight are walked (two lists beside the pools, a new one still taking the same pool
  slot), a style's constants worked out when it changes, `Look`/`Alpha`/`Lerp` and the bolts' `RollBolt` written out, a
  sheet flash's arc never placed while hidden, the emitters' counters in locals.
- Bars.lua: `Secret` with one `select("#")`, `issecretvalue` direct on the hot paths, bars off, failed or asleep
  skipped without calling `RunBar`, `Inflow`/`BuildUp` only when there is something to do, the fury's `GetTime` only when
  sampling and its rage samples' tables reused, its glow's colour set only when the theme's changes.
- Bar Height: a taller frame whose game frame is hidden (no focus, pet or party) is no longer copied each poll but in
  full when it shows (`OnShow`): one poll 12.6k instructions to 5.9k (about 0.49 ms of Lua to 0.23, the spike risk),
  half the poll's cost; segment overlays mirrored only while their segment shows.
- The heal and DoT markers: with nothing showing and nothing on the way, the step between reads keeps time and sight
  without the call; a hidden DoT marker does not feed its hidden bar.

By the bench (no `/sab perf` timing on, the player's settings, a fight at pace 10): Lua 27.7k instructions a frame to
21.7k (-22%), widget calls 601 to 555 (-8%), quiet 283 to 243 (-14%). By the rig (which runs `/sab perf`, so its
timing's own overhead is in both columns; some of the idle gain is that overhead, cut too): a fight at 92 fps with rage
spends 1.53 ms a frame to 1.17 (14.1% of the frame to 10.7%), idle at 120 fps 0.77 to 0.54 (9.2% to 6.5%). Not yet seen
in game.

Held back, each a change of timing or look, for the user to decide (measured by a research agent on branch
`perf-lookchange-research`, its `framecost.py` per-frame predicted cost and `lookdiff.py` pixel differences of the
preview, against today's cap of 60 against Unlimited at 92 fps, 0.68 mean and p99 10.3, which was seen in game as no
difference):

| Option | Fight | Idle | Look (mean / p99 of 255) |
|---|---|---|---|
| Stagger the capped liquids' updates across frames | 0 (peaks: p99 2.80 to 2.35 ms, max 3.08 to 2.54) | +4% (a rate fix needed) | 0.36 / 4.3 |
| No caps on the four added-light layers | -16% | -9% | 0.11 / 0.6 (the mock draws added light fainter: judge in game) |
| No caps on all seven layers | -20% | -12% | 0.09; big bulges lighter and flatter without the dark clouds |
| Idle liquids at 20 fps | 0 | -11% | 0.10 |
| Default cap 45 | 0 at 92 fps, -16% at 120 to 144 | | at 120 fps about what 60 against Unlimited is at 92 |
| At most 12 slices | -9% | -8% | 0.44 / 8.0, the front's outline |
| The bursting fury held to the cap (`3c0291c`) | fury step 0.61 to 0.38 ms in the rig | | the burst at 60 updates a second instead of every frame |
| Bar Height's poll spread over frames, or every 0.2 s | poll peak 5.9k to 1.5k instructions; or half its cost | | copies up to a frame or 0.1 s later |
| Physics step 1/60 | -3% | -5% | 0.09; not worth it |
| Drop the swirlB layer | -4% | | 2.86 / 22: visible, no |

Five of those were put behind test switches (`/sab try`, a throwaway window) and tried in game (2026-11-27, a warrior,
Bar Height on): staggered updates, no caps on the four added-light layers (cloudLight, core, swirlA, swirlB), idle
liquids at 20 fps, the bursting fury held to the Animation Frame Rate, Bar Height's poll every 0.2 s. No difference was
seen with all five on (asked), so they are the defaults now and the switches are gone (`IDLE_FPS` 20, `POLL` 0.2 with its
once-a-second copies counted from it, `FULL_EVERY`; the glow layers made without caps, `Layer`'s `noCaps`). Measured in
game against all off, one fight each, alike in what moved: our parts 1.36 ms a frame to 0.98 (-28%; the rig said -25%),
drawing 0.096 ms an update to 0.061-0.065; another fight with them on, with half again as many liquid updates a frame,
1.51. The game's profiler counted no frame over 5 ms in any of six windows (idle and fights, on and off), against 26 and
6 in two fights before this round. Staggered, the liquids' share of a fight's slowest frame went from 3.3 ms to about 1;
what is left in the slowest frames is a burst of events in one frame (DoT tracking up to 1.1 ms, the bars' events 0.8,
heal tracking 0.5), and once the idle heal marker at 2.2 ms. Idle was 0.42 to 0.56 ms either way (it depends on what
moves). The rig with all five: a fight at 92 fps 1.17 to 0.88 ms, idle at 120 fps 0.55 to 0.48.

## Event handlers (offline, 2026-11-27)

What is left in a fight's slowest frames is a burst of events landing in one frame. `tools/harness/events.py` counts
every instruction each kind of event costs on the player's settings: a cast sent cost about 5000 instructions and one
succeeded 3600 to 4000, against 300 to 1400 for a hit, health or power; a burst of a fight's events in one frame 25.4k
(about 0.7 ms at 28 us a thousand, in line with the event bursts seen in game). Two causes, both cut exactly:

- `Heals.lua`'s `recipient` searched all 44 group units (party1..4, raid1..40) twice for a cast sent at a named target,
  each a `pcall`ed `UnitExists`, alone too. With neither party1 nor raid1 there (no group) it searches none (`members`).
- Every cast's text went through every language's readers again (`Locale.lua`). Readings are kept by text (`Kept`,
  `Keep`, `Again`, each with its number of values, so a kept reading gives back exactly what reading gave): the readers
  are pure, every language running in the same order whatever the client's. A secret text is read each time; the store
  starts over past 300 texts.

Also: `Dots.lua`'s and `Heals.lua`'s `isSecret` call `issecretvalue` without a `pcall` (Bars.lua already did). A cast sent
5009 instructions to 1925, one succeeded about 600 fewer at its first reading and most of the rest after; the burst 25.4k
to 13.2k. Every reading case passes (the DoT and heal cases in every language). Not yet seen in game.

Left alone: a raid member's health or power event costs the bars about 300 instructions with raid frames off (the
handler looks through every bar for its unit); an index of the units with a live bar would need keeping wherever a bar's
unit changes, for about 0.02 ms a frame in a busy raid. DoT tracking hears every unit's hits (about 190 instructions for a
group member's), but its handling of them is not provably nothing. `/sab perf calib` now also times `SetAlpha` through
the method kept in a local ("SetAlpha kept"), to tell whether keeping widget methods in locals in the liquid's loops is
worth it (the rig cannot: the same instructions).
