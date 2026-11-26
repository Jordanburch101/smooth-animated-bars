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
