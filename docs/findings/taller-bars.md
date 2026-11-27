# Bar Height

Taller player, target, focus, pet and party frames (TallFrames.lua). What the game's frames show and what is still missing: [TALLER_BARS_GOALS.md](../TALLER_BARS_GOALS.md).

## Bar Height (taller bars)

*Where:* players are told "Bar Height": they did not like "taller bars"; `TallFrames.lua`, `Preview.TallArt`, `playerHealthHeight`... sliders in the editor; asked for

Forever's player and target art (`UI-HUD-UnitFrame-<Player|Target>-PortraitOn`) is one atlas, so a taller frame is that
atlas cut into slices: each bar's slot stretched by repeating a band from its middle, the portrait ring cut out with
`CircleMask` and put back, and the panel's end the ring hides (never seen in the capture) drawn again from the dark
block beside it. The ring keeps its size until it no longer covers that end, then grows (asked for). The layout numbers
(`TALL`) were measured on the capture.

Seen in game: `SetAtlas` and then `SetTexCoord` drew nothing at all, so a slice is the atlas's file by ID
(`C_Texture.GetAtlasInfo`) with coordinates, as FlareUI cuts the same art (`Modules/UnitFramesRing.lua`); the mock now
rejects texture coordinates on an atlas texture. The bars' masks are mostly transparent margin round their slot:
stretched evenly, the liquid stopped short of the slot (seen in game), so each is stretched until the part it lets
through (`opaque`, measured on the captured masks) is exactly the bar's growth taller.

Seen in game and right in the editor's examples. On the real frames (`TallFrames.lua`) the frame is `Preview.LiveFrame`
as a child of the game's frame, grown upward from its bottom edge (asked for: the target's auras start 9 above its art's
bottom, and its cast bar, the target of target and the pet frame hang below). It fades the game's art, portrait, bars
(with their texts and predictions), name and level, carries the icons round the portrait (elite dragon, skull, raid
target, leader, PvP...) to where the moved ring puts them, copies the texts each poll (0.1 s, 0.2 since 1.14.2: no difference seen in game), and hands its own bars, filled
from the game's each frame, to the liquid with `Bars.AddBar` and the frame's own key, as an adaptor does: so the DoT
marker and the mana build-up follow. The game's segments on its bars (heal predictions, heal absorb, absorb, the
player's mana cost prediction; StatusBarOverlaySegmentTemplate) are children of the faded bar, so ours copy them onto
our bars under the game's keys (`MyHealPredictionBar`...`OverAbsorbGlow`): each a bar-wide fill seen through a mask on a
box anchored to the game's own `FillMask` (laid by the game from the fill's edge, from secrets it alone may do
arithmetic on), moved by how far our bar is from the game's, our bar's height; shown as the game's are, each frame.
Under those keys the heal marker and the shield find and hide them as on the game's bars: the heal marker builds on our
bars as on the game frame's (`HealMarker.lua`, `BuildTall`: the player's health with others' heals, mana, a party
member's health), not as another addon's, and the shield and Weakened Soul are drawn on our player health bar while it
shows (`Follow` in both, the game's absorb display still read on the game's bar).

From a review: a copy can only fade by a secret shown state (its own `IsShown` then answers true), so the heal marker
asks the game's segment (`MirrorOf` on the copy, read by `GameOthers`), or others' heals never faded or hid there; the
glows are cut by the bar's slot as the game's are (`PlayerFrame.xml` masks them; 9 of their 16 lie past the bar's end);
a copy's alpha is never copied (the game's may be the paused game-bar marker's 0); Weakened Soul keeps its glass parts
per shield and uses the shield only on its own bar (the two switch bars in separate OnUpdates).

Seen in game: the player's PvP badge carried far up and right of the frame, its timer ("5 m") left where the game had
it. The badge's template has a scale of its own (`PlayerPvpBackgroundIconTemplate`, `scale="0.8"`), and a scaled region
answers `GetLeft`/`GetWidth` in its own units, so carried icons and glows are now taken into the frame's units by their
effective scales (`ScaleTo`); the mock answers a placed region's position (`sx`, `sy`) in its own units too.

Seen in game after that: the badge in its place. Texts the game anchors to a carried icon are faded and drawn beside our
copy of it (`follow`: the PvP timer).

Seen in game with Health Bar Text Forever: it fades the game's bar texts to alpha 0 and draws its own on the bars
(`bar:CreateFontString`), so on taller frames our copies brought the game's text back and its own vanished with the
faded bars (the target of target's, where the game has none, entirely). The bar texts' copies take their own alpha
(never faded by us; their frames are), and every other FontString on the game's bars is copied onto ours, placed against
our copy of the game text it hangs on, in its own font and size (`TallFrames.OtherTexts`); seen in game with that addon:
working.

Seen in game (1.14.2) with Status Text "Both" on the taller player frame: the percentage and the value drawn over each
other in the middle of the bar, and the power's value centred. The copies are placed by the game texts' `GetPoint`,
which the mock answers; in game it must have come back unreadable (secret or failed; not yet seen which), as the
fallback was the centre. Each copy now falls back to its own side, at the XML's inset (`PlaceText`, `SIDE_PLACE`);
seen in game: fixed.

Reported by players: grey bars after setting a Bar Height; not seen here, as this account has Your Colours on Their Bars
on (`externalColors`), which already took the game's colours there. Our bars are handed over as another addon's are,
whose Game Colour is the bar's own colour (`PlateColor`), and ours is the StatusBar's untinted white over the game's
art, so the default drew a white liquid (in the mock too, power even under Class Color). Our bars are listed in
`Bars.tall`, and there Game Colour is the game's (`GameColor`), as with Your Colours on Their Bars; seen in game with
that setting off: right.

Seen in game: heals on taller frames working (the heal marker).

Not yet seen in game: the rest of that, and whether the client lets ours anchor to the game's masks. The full list of
what the game's frames show and what is still missing is `docs/TALLER_BARS_GOALS.md`. Left as the game's: the rest loop,
the group indicator. Built out of combat only; in a vehicle the game's frame is given back.

Seen in game on a target: the frame, bars, portrait and text copies right, but the name and level copies invisible: a
FontString's `GetTextColor` alpha is its `SetAlpha`, 0 on the faded game text, so copies take the colour's red, green
and blue only (the mock keeps one alpha for text too). And with Edit Mode's Buffs on Top the game anchors the target's
auras above its art (`TargetFrameMixin:AnchorAuraContainer`), which growing up covered (seen), so a target with
`buffsOnTop` grows down. The focus (`focusHealthHeight`...), the pet and both targets of target (`pet`/`tot`, from the
game's 11 and 7) take it too, each frame a spec in `TallFrames.lua` (`SPEC`: the target's template shared by the target
and the focus, one for both targets of target) naming its art, so frames of one art share its layout and measurements
(`Preview.lua`, `LAYOUT` and `TALL` by art; the editor's pet and target of target examples are now in their own art).
The small frames' art (`UI-HUD-UnitFrame-TargetofTarget-PortraitOn`, the pet's too) was never captured: it was measured
on the game's own sheet, `uiunitframec60.blp` (BLP2, uncompressed BGRA: Pillow cannot read it, the pixels follow a
1172-byte header), from github.com/Adrestie/mod-forever-ui (its `data/art/interface/foreverui/hud`, and the atlases'
places on it in `data/addon/ForeverUI/UIAtlas_04_unit_frames.lua`, generated from the Forever client 1.60.1). Measured
there, the player's and target's art agreed with their capture's numbers within a few tenths. That repo also has
Forever's other sheets (action bars, party, raid, minimap), worth a look before capturing art again; it has no masks.
The small frames use the party frame's masks, so their opaque bands are the party capture's. Seen in the editor: the
small frames' masks, placed by the game's anchors, let the liquid through 1.4 above their slots and the power's 2 left,
under the gold divider (as on the party frame, where `PARTY_POWER_SHIFT` was set by eye); the game keeps its fill in the
slot, so each mask is centred on its slot as measured on the sheet. A ring grown past its frame widens the editor's
outline (`TallArt`'s `over`). The party members (`partyHealthHeight`/`partyPowerHeight`, from the game's 10 and 7): the
party art is the small frames' pixel for pixel, 1 right and 2 down (`TALL.party`, measured on `uipartyframec60.blp` from
the same repo); measured there, centring the power mask on its slot needs 0.9 right and 1.9 down, against
`PARTY_POWER_SHIFT`'s 1.5 and 1.9 by eye, so that shift stays. The game pools the four member buttons and hands them
between `MemberFrame1..4`, so a member's state is kept by its button (`TallFrames.State().party`) and its unit read from
the button each look. The game stacks them 10 apart (26 with party pets) and each has 2 under its art, so they grow down
and their sliders stop at +8 and +4; the editor's stacked party is drawn smaller as it grows, to stay on the screen.

Not yet seen in game: the focus, pet, targets of target and party taller.

Seen in game: the player's aggro flash (`FrameFlash`, the threat indicator) left at the game's place, misaligned with
the taller frame. The flashes (`...-PortraitOn-InCombat`) and the player's status glow (`...-Status`) have the art's
outline round the ring and the name row, so they are laid out by the art's own slicing (`Preview.TallGlow`, `Lay` with
no panel's end, the ring cut `GLOW_PAD` wider), placed where the game's sits, in its colour and blend mode. The game
pulses the status glow's alpha every frame (`PlayerFrame_OnUpdate`), so the player's and target's pieces are hidden by
fading their containers (`PlayerFrameContainer`, `PlayerFrameContentMain` and the target's), never the glows themselves,
whose own alpha ours copies each frame; the pet's and a party member's flash sit on the frame itself and are faded
alone. The game's hit numbers over the portrait go with the player's main content, so ours copies them over its portrait
each frame (`CopyHit`: text, colour, alpha; seen in game working, before its sizes: asked to match the default exactly),
its size worked out from `UNIT_COMBAT`'s action and flag (`HitSize`; a FontString has no getter for `SetTextHeight`),
not grown with the ring (asked for; only its place moves with the portrait). A hit flagged ABSORB, BLOCK or RESIST is a
word at 0.75 or, with some damage through, a number at full size: the amount is secret, so told by the text being
secret. The pet's (`PetHitIndicator`) share a frame with its name alone, so that frame is faded (the game sets the
text's own alpha each frame).

Not yet seen in game: the sizes, the pet's. The combo points round the target's portrait (Camelot `ComboFrame.lua`) were
seen in game left round the game's smaller ring; ours are dots of the game's own template round our ring (`BuildCombo`,
`MirrorCombo`), the game's dots faded rather than `ComboFrame`, whose alpha `UIFrameFadeIn` sets.

Seen in game: in sync with the game's. The editor's target example has them for a rogue (`Preview.lua`, `AddCombo`,
asked for; seen in game, working).

Seen in game: the resting "zzz" and the target's cast bar fine. A druid's extra mana bar has its own player art
(`AlternatePowerFrameTexture`): while it shows, the game's frame is given back.

Seen in game: a target of target showing the face of the one before, as no portrait event comes when the target picks a
new target; portraits are now redrawn on `UNIT_TARGET` (the target's or focus's new target), a new target or focus, the
party's roster, and whenever the name the game shows changes (`TallFrames.lua`, `Changes`).
