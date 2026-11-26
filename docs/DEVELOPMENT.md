# Developing Smooth Animated Bars

The rules for working on the addon are in [CLAUDE.md](../CLAUDE.md), and what we learned about WoW Forever along the
way in [findings/](findings/README.md), a file a topic. This page is the map and the commands; the gallery's scenarios
are in [GALLERY.md](GALLERY.md) and the release steps in [RELEASE.md](RELEASE.md).

## How it works

WoW Forever keeps health and power secret from addons, so the addon never reads how full a bar is. A hidden
bar of its own takes the game's (secret) value with the game's smoothing, and the liquid hangs on the edge of
that hidden fill, so the game places it. The game's own bar masks cut it to shape. `SmoothAnimatedBars/Bars.lua`
explains the details.

## Layout

| Folder | What it is |
|---|---|
| `SmoothAnimatedBars/` | The addon. `Bars.lua` puts the liquid on the unit frames, `Liquid.lua` draws it, `Themes.lua` holds the themes, `Dots.lua` tracks the player's DoTs (ported from DoesItDie) and `Marker.lua` marks them on the target, `Heals.lua` tracks the player's heals on themselves and `HealMarker.lua` marks them on the player's health, `ManaRule.lua` times the wait before mana regenerates, which `Bars.lua` draws, `Editor.lua` the editor (every setting beside a live preview), `Options.lua` the settings page that opens it, `Wizard.lua` the setup and `Preview.lua` the preview frames both use, `Capture.lua` the gallery's art capture, `Adaptors/` other unit frame addons' bars for those that do not hand them over (`Adaptors/agent.md`) |
| `tools/make_media.py` | Generates the textures in `SmoothAnimatedBars/Media/` |
| `tools/harness/` | A mock of the Forever client's API that runs the addon outside the game: tests, previews and the gallery |
| `tools/capture_art.py` | Cuts Forever's frame art out of the screenshots `/sab capture` takes |
| `branding/` | `art/`: the captured frame art. `gallery/`: the README's images |
| `scripts/package.ps1` | Builds the release zip |

To try the source in game, link or copy `SmoothAnimatedBars/` into
`World of Warcraft/_forever_/Interface/AddOns/`.

```powershell
python -m venv tools/venv
tools/venv/Scripts/python -m pip install lupa numpy pillow

python tools/make_media.py SmoothAnimatedBars/Media                                                  # textures
tools/venv/Scripts/python tools/harness/test.py SmoothAnimatedBars                                   # tests
tools/venv/Scripts/python tools/harness/preview.py SmoothAnimatedBars preview healthColor=fire power=0  # preview.gif + sheet.png
./scripts/package.ps1                                                                                 # dist/SmoothAnimatedBars-<version>.zip
```

`preview.py` takes any setting as `key=value`, and `power=` for the power type (0 mana, 1 rage, 3 energy).

`editor_shot.py` draws the editor window at each frame and tab (or the ones named; `closed` closes the bar drawers)
to check its layout:

```powershell
cd tools/harness; ../venv/Scripts/python editor_shot.py ../../SmoothAnimatedBars shots player plates effects
```

The mock has no art for the game's templates and atlases, so the window, buttons and check buttons are plain
stand-ins and the examples' art is outlined. It applies `SetScale` and clipping but not texture coordinates, so the
colour tiles' textures are not drawn as in game. It shows where things sit; how the game's art looks is for the game.

## The in-game changelog

`WhatsNew.lua` shows each release's `CHANGELOG.md` section in a window once after an update. Its notes are
`WhatsNewData.lua`, which `scripts/package.ps1` writes for every build and git ignores. To try the window in the
dev install, write it by hand, then restart the game once (it is a toc file) and use `/sab changes`:

```powershell
tools/venv/Scripts/python tools/whatsnew_data.py    # SmoothAnimatedBars/WhatsNewData.lua from CHANGELOG.md
```

## Measuring

`/sab perf [note]` in game prints what the liquid's updates cost each frame over the last 10 seconds, the unit
frames and the enemy nameplates apart, then times every part of the addon over the next 10 seconds (and meanwhile each
bar: the Personal Resource Display's and the party's, and the costliest bars with their Rage Fury), and saves it all in
the saved variables. `/sab perf calib` times each kind of widget call and a piece of Lua in the client, for the rig.
After `/reload`:

```powershell
tools/venv/Scripts/python tools/perf_report.py    # perf/perf_report.txt: a line per report, then each second
```

It reads the newest `SmoothAnimatedBars.lua` under Forever's WTF folder (`--file` for another). Only the Lua
updates are timed, not the client drawing the textures, so compare fps with a setting on and off too.

Without the game, `tools/harness/bench.py` counts the liquid's calls to the game's widgets per frame, by group of
bars, quiet and in a combat-like stream of changes. Those calls are what costs in the client: matched against
`/sab perf` in game, each took about 1.9 microseconds, which gives its ms estimate and its share of the frame at
`--fps`. It also counts the addon's own Lua work (Lua 5.1 instructions in its files), so work saved in calls is not
spent again in Lua. Runs are repeatable, and `--ref` measures the addon at a git ref on the same frames to show what a
change saves; `--by line|method|lua` shows where the calls or the Lua work go:

```powershell
cd tools/harness
../venv/Scripts/python bench.py ../../SmoothAnimatedBars --party 3 --ref HEAD
../venv/Scripts/python bench.py ../../SmoothAnimatedBars --party 0 --max --only player --by line
```

`--saved <SmoothAnimatedBars.lua>` runs one group with a player's own saved variables (every feature as they have it,
Bar Height included), only the player's and target's frames shown, to match what they measure in game; `--fps` their
frame rate, and `--cap 60` the Animation Frame Rate. `--by file` and `--by luafile` sum the calls or the Lua work by
file.

### The CPU rig

`tools/harness/rig.py` says what `/sab perf` would say in game, without the game. It runs the addon in the mock with a
player's saved variables, gives it a clock of its own that moves by a cost for each call to the game (setters,
getters, status bars, other functions) and for its Lua work, and runs the addon's own `/sab perf` (its part-by-part
timing). The widget calls' costs are measured in game by `/sab perf calib`; the Lua's and the other game functions'
are fitted to the reports with every part timed (the calibration's own Lua, tight arithmetic, costs several times less
an instruction than the addon's code), and every part's prediction is printed beside its measured time:

```powershell
cd tools/harness
../venv/Scripts/python rig.py calibrate --since "2026-11-26 14:40" --pace 3   # after /sab perf calib, /sab perf, /reload
../venv/Scripts/python rig.py predict --scenario fight --fps 95 --pace 3      # idle, notarget or fight
../venv/Scripts/python rig.py predict --scenario idle --fps 120 --ref <commit> # beside an earlier version
```

`--since` picks the reports made with the code now in the working copy (`--ref` for the code they ran); `--pace` is a
fight's changes a second; `--class` the player's (a warrior's rage has the fury); `--casts` a warrior's rage spends a
minute in a fight (36 by default, 0 for none: each bursts the Rage Fury, most of its cost in game). The costs are written to
`rig_calibration.json` with each part's measured and predicted time. Without a `/sab perf calib` (or with `--fit`) the
costs are fitted to the reports instead, which cannot tell the Lua from the widget calls apart well. `--ref` in predict
needs a version with the part-by-part timing (`ns.Timed`) to compare against.

The Lua counts (here and in `bench.py`) sample every 50 instructions with a count hook that re-arms itself as its last
act: in Lua 5.1 the hook's own instructions use up the count, and armed once it counted the addon's Lua about three
times over, most where samples took its longer path. `bench.py --by luafn` sums the Lua by function.

A change made for speed must not change the look. `tools/harness/samelook.py` plays the same scenarios (classes,
themes, effects at their strongest and off, a reversed bar, quiet and fighting) on the addon at a git ref and on the
working copy, and compares every texture that shows, every frame: place, size, texture coordinates, colours, alpha,
blend and layer. It exits 1 on any difference past float rounding, or past half an 8-bit step in colour and alpha. It
and the bench are repeatable: a fixed random seed, and `pairs` in a fixed order (`samelook.STABLE_PAIRS`), as table
addresses, and so the order the liquids took their random numbers in, differed from run to run:

```powershell
cd tools/harness; ../venv/Scripts/python samelook.py ../../SmoothAnimatedBars --ref HEAD
```

## Gallery

The gallery draws the liquid on Forever's own frame art, which lives in the game's data files. To capture
it, run `/sab capture` in game (out of combat): it screenshots the art on black and on white as TGA. Then:

```powershell
tools/venv/Scripts/python tools/capture_art.py                                  # branding/art/*.png
cd tools/harness; ../venv/Scripts/python gallery.py ../../SmoothAnimatedBars    # branding/gallery
```

Capture again only if the game's frame art changes. The mage, rogue and warlock animations use those
characters' portraits: capture on each, then `capture_art.py --portrait mage --pair 2`, `--portrait rogue
--pair 1` and `--portrait warlock --pair N` (the newest pair is the last capture; until a warlock portrait is
captured, the warlock uses the capturing character's; `rend` is the warrior again). `gallery.py` takes scenario
names to render only some: `hero`, `mage`, `rogue`, `warlock`, `rend`, `priest`, `druid`, `eating`, `mana`, `fury`, `themes`. `eating` is the player frame alone, a meal up to its buff, with the druid's portrait. `mana` is the player frame alone, the build-up to mana regenerating, with the mage's portrait. `fury` is the warrior's rage building to full and spent on Heroic Strikes and a Hamstring, through the addon's own Rage Fury. The druid
carries both markers (Moonfire on the target, Rejuvenation and Healing Touch on itself) and has its own
portrait (`--portrait druid`). The priest's
health carries the heal marker (Holy, then a bandage's Nature), its casts going through the addon's own heal
tracking; until a priest portrait is captured (`--portrait priest`), it uses the capturing character's. The warlock's and the rend
scenario's targets carry the DoT marker (Shadow then Fire, and a bleed): their casts and ticks go through the
addon's own tracking, and the DoT liquid is the addon's own, drawn like the bars' liquid with
the health liquid's front moved back over it. The kill icon is the game's skull, captured as
`target-killicon.png`; captures from before 1.1.0 lack it, and the gallery then leaves the icon out. A full
capture also replaces `player-portrait.png`, which is the hero's, so take it on the warrior. Animations are animated WebP, in full colour. A full run takes about a
quarter of an hour; the gallery is rebuilt for a release when something visible has changed.

## Adding a theme

Register it in `Themes.lua`. Only the fields that differ from the default theme are needed; the comment at
the top of `Themes.lua` lists everything a theme can set. Its movement is scaled down for the unit frames'
small bars.

## CI

`.github/workflows/ci.yml` runs the tests and a release build on every push to `main` and on pull requests;
the build is attached to the run as a download.
