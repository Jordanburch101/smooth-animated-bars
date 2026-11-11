# Developing Smooth Animated Bars

The rules for working on the addon, and what we learned about WoW Forever along the way, are in
[CLAUDE.md](../CLAUDE.md). This page is the map and the commands.

## How it works

WoW Forever keeps health and power secret from addons, so the addon never reads how full a bar is. A hidden
bar of its own takes the game's (secret) value with the game's smoothing, and the liquid hangs on the edge of
that hidden fill, so the game places it. The game's own bar masks cut it to shape. `SmoothAnimatedBars/Bars.lua`
explains the details.

## Layout

| Folder | What it is |
|---|---|
| `SmoothAnimatedBars/` | The addon. `Bars.lua` puts the liquid on the unit frames, `Liquid.lua` draws it, `Themes.lua` holds the themes, `Dots.lua` tracks the player's DoTs (ported from DoesItDie) and `Marker.lua` marks them on the target, `Heals.lua` tracks the player's heals on themselves and `HealMarker.lua` marks them on the player's health, `ManaRule.lua` times the wait before mana regenerates, which `Bars.lua` draws, `Options.lua` the settings page, `Wizard.lua` the setup and `Preview.lua` its preview frames, `Capture.lua` the gallery's art capture |
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

## The in-game changelog

`WhatsNew.lua` shows each release's `CHANGELOG.md` section in a window once after an update. Its notes are
`WhatsNewData.lua`, which `scripts/package.ps1` writes for every build and git ignores. To try the window in the
dev install, write it by hand, then restart the game once (it is a toc file) and use `/sab changes`:

```powershell
tools/venv/Scripts/python tools/whatsnew_data.py    # SmoothAnimatedBars/WhatsNewData.lua from CHANGELOG.md
```

## Measuring

`/sab perf [note]` in game prints what the liquid's updates cost each frame over the last 10 seconds, the unit
frames and the enemy nameplates apart, and saves it in the saved variables. After `/reload`:

```powershell
tools/venv/Scripts/python tools/perf_report.py    # perf/perf_report.txt: a line per report, then each second
```

It reads the newest `SmoothAnimatedBars.lua` under Forever's WTF folder (`--file` for another). Only the Lua
updates are timed, not the client drawing the textures, so compare fps with a setting on and off too.

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
