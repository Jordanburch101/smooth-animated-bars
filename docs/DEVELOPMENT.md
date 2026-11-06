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
| `SmoothAnimatedBars/` | The addon. `Bars.lua` puts the liquid on the unit frames, `Liquid.lua` draws it, `Themes.lua` holds the themes, `Options.lua` the settings page, `Wizard.lua` the setup and `Preview.lua` its preview frames, `Capture.lua` the gallery's art capture |
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

## Gallery

The gallery draws the liquid on Forever's own frame art, which lives in the game's data files. To capture
it, run `/sab capture` in game (out of combat): it screenshots the art on black and on white as TGA. Then:

```powershell
tools/venv/Scripts/python tools/capture_art.py                                  # branding/art/*.png
cd tools/harness; ../venv/Scripts/python gallery.py ../../SmoothAnimatedBars    # branding/gallery
```

Capture again only if the game's frame art changes. The mage and rogue animations use those characters'
portraits: capture on each, then `capture_art.py --portrait mage --pair 2` and `--portrait rogue --pair 1`
(the newest pair is the last capture). `gallery.py` takes scenario names to render only some:
`hero`, `mage`, `rogue`, `themes`. Animations are animated WebP, in full colour. A full run takes about a
quarter of an hour; the gallery is rebuilt and committed for every release.

## Adding a theme

Register it in `Themes.lua`. Only the fields that differ from the default theme are needed; the comment at
the top of `Themes.lua` lists everything a theme can set. Its movement is scaled down for the unit frames'
small bars.

## CI

`.github/workflows/ci.yml` runs the tests and a release build on every push to `main` and on pull requests;
the build is attached to the run as a download.
