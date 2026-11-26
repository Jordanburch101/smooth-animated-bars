# The gallery

`branding/gallery/` holds the README's images, made by `tools/harness/gallery.py` (how to run it:
[DEVELOPMENT.md](DEVELOPMENT.md#gallery)). Animated WebP and PNG stills (`frames.png`, `themes.png`), at full quality
(`K = 3.0`, 20 fps). No GIFs. A full run takes about a quarter of an hour, so run it in the background. Rebuild it when
the liquid's look changes and look at every image before committing; the liquid moves at random, so a rebuild rewrites
every file even when nothing changed, and those are not committed.

## Scenarios

- `hero`, `mage`, `rogue`; `warlock` and `rend` with the DoT marker; `priest` with the heal marker; `druid` with both.
- `eating`: a meal up to its buff. `mana`: the build-up to mana regenerating.
- `fury`: a warrior's rage building to full and spent back to 40%.
- `plates`: four Normal-style nameplates drawn from the captured plate art (`gallery.py`, `PLATES`), two with DoTs.
- `prd`: a warrior's Personal Resource Display through a fight to furious rage and a bandage, on the same plate art, its
  bar sizes Edit Mode's defaults as guessed.
- `party`: four party members stacked as in game, on the party art with the setup's example party and its class icons
  for portraits. The power mask and bar are shifted 1.5 right and 1.9 down there (`gallery.py`, `PARTY_POWER_SHIFT`): at
  Forever's own offsets they sat over the gold divider in the captured art, though in game the game's fill does not, so
  the gallery was tuned by eye to sit in the slot; the example party in the setup and the editor (`Preview.lua`,
  `PARTY_POWER_SHIFT`) showed the same in game and takes the same shift, the capture keeping the game's offsets.
- `raid`: a ten-player raid through a pull in two groups of raid-style frames, on the raid frame art (`gallery.py`,
  `RAIDERS`), its tank targeted.
- `shield`: a priest's Power Word: Shield soaking five hits and shattering, no Weakened Soul (asked for). Not made by
  `gallery.py`: the mock cannot lay the shield out from the secret absorb, so it was composited from the gallery's own
  player frame with the real `Shield.lua` and `Soul.lua` rendered where the client would place them, as the shield's
  previews were; render it that way again if either changes.
- `tall`: a mage's player frame with its bars grown to the sliders' tallest (40 and 20), shrunk to the game's 20 and 10
  and settled in the middle, looping (`gallery.py`, `TALL_KEYS`). The art is the addon's own slicing
  (`Preview.SetFrameTall` on a `LiveFrame`) of the captured art, the captured masks stretched as `TallSpec` stretches
  them, the level circle moved with the ring (the mock's circle atlas has no real size), and the liquid the addon's in
  the game's bars resized to match.

The mage, rogue, warlock, priest and druid scenarios use those characters' portraits where captured; see
[DEVELOPMENT.md](DEVELOPMENT.md#gallery).

## Frame art

`branding/art/` is Forever's own unit frame art, captured in game with `/sab capture` and cut out by
`tools/capture_art.py`: `/sab capture plates` and `--plates` for the nameplates' pieces, `/sab capture party` and
`--party` for the party member frame's (its art, bar masks and four class portraits), `/sab capture raid` and `--raid`
for the raid-style frame's atlases (its background, the power bar's, the target's highlight and a group's border). It is
only for the gallery and is never packaged. The layout numbers live in `Preview.lua` (`LAYOUT`) and are repeated in
`gallery.py`; change both together. What the capture runs into: [findings/capture.md](findings/capture.md).
