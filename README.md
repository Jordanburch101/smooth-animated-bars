<p align="center"><img src="https://raw.githubusercontent.com/Jordanburch101/smooth-animated-bars/refs/heads/main/branding/gallery/hero.webp" alt="Smooth Animated Bars: liquid health and power bars on the player and target frames, draining and refilling through a fight"></p>

# Smooth Animated Bars

Liquid health and power bars for the player and target frames in **WoW Forever**, with the liquid from
[Smooth Experience Bar](https://www.curseforge.com/wow/addons/smooth-experience-bar): waves, a magic swirl,
bubbles, sparkles, lightning and themes.

## What it does

- Draws the liquid in the game's own player and target frame bars: health, and mana, rage, energy or focus.
  The frames stay the game's; only the fill changes.
- The liquid eases to wherever the game's bar is, and stirs whenever the bar changes.
- Health and power each take the game's colour, or one of 24 themes (Class Color, Faction, Fire, Frost,
  Arcane, Void and more), with their own particles.
- Each bar and each effect can be switched off on its own.
- A three-step setup on the first login shows each choice on your own frame as you pick it.

![A mage's mana going in big bites with each Fireball, the kobold's health with it](branding/gallery/mage.webp)

![A rogue's energy ticking back and spent on Sinister Strike and Eviscerate](branding/gallery/rogue.webp)

![The player frame's health in eight colours: Game Colour, Class Color, Fire, Frost, Arcane, Fel, Cosmic and Void](branding/gallery/themes.png)

## Commands

| Command | |
|---|---|
| `/sab` | Open settings (also Options > AddOns > Smooth Animated Bars) |
| `/sab on` / `/sab off` | Liquid in all four bars, or none |
| `/sab setup` | Open the setup wizard |
| `/sab debug` | What each bar is doing |

## How it works

WoW Forever keeps health and power secret from addons, so the addon never reads how full a bar is. A hidden
bar of its own takes the game's (secret) value with the game's smoothing, and the liquid hangs on the edge of
that hidden fill, so the game places it. The game's own bar masks cut it to shape. `SmoothAnimatedBars/Bars.lua`
explains the details.

---

## Development

| Folder | What it is |
|---|---|
| `SmoothAnimatedBars/` | The addon. `Bars.lua` puts the liquid on the unit frames, `Liquid.lua` draws it, `Themes.lua` holds the themes, `Options.lua` the settings page, `Wizard.lua` the setup |
| `tools/make_media.py` | Generates the textures in `SmoothAnimatedBars/Media/` |
| `tools/harness/` | A mock of the Forever client's API that runs the addon outside the game: tests, previews and the gallery |
| `tools/capture_art.py` | Cuts Forever's frame art out of the screenshots `/sab capture` takes |
| `branding/` | `art/`: the captured frame art. `gallery/`: the images in this README |
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

### Gallery

The gallery draws the liquid on Forever's own frame art, which lives in the game's data files. To capture
it, run `/sab capture` in game (out of combat): it screenshots the art on black and on white as TGA. Then:

```powershell
tools/venv/Scripts/python tools/capture_art.py                                  # branding/art/*.png
cd tools/harness; ../venv/Scripts/python gallery.py ../../SmoothAnimatedBars    # branding/gallery
```

Capture again only if the game's frame art changes. The mage and rogue GIFs use those characters'
portraits: capture on each, then `capture_art.py --portrait mage --pair 2` and `--portrait rogue --pair 1`
(the newest pair is the last capture). `gallery.py` takes scenario names to render only some:
`hero`, `mage`, `rogue`, `themes`. Animations are animated WebP, in full colour. A full run takes about a
quarter of an hour; the gallery is rebuilt and committed for every release.

### Adding a theme

Register it in `Themes.lua`. Only the fields that differ from the default theme are needed; the comment at
the top of `Themes.lua` lists everything a theme can set. Its movement is scaled down for the unit frames'
small bars.

CI (`.github/workflows/ci.yml`) runs the tests and a release build on every push to `main` and on pull
requests; the build is attached to the run as a download.

## Credits

The liquid comes from Smooth Experience Bar, whose look is based on the
[Luxthos Experience Bar](https://wago.io/LuxthosExperienceBar) WeakAura by Luxthos & Daemoos. Smooth Animated
Bars is not affiliated with or endorsed by Blizzard Entertainment.
