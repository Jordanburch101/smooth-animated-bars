# Shields and Weakened Soul

Power Word: Shield's absorb on the player's health, and Weakened Soul.

## Shields

*Where:* `Shield.lua`, `shield`

Forever's player frame has the game's absorb display (`healthBar.TotalAbsorbBar`, a segment with `Fill` and
`TiledFillOverlay`, and `OverAbsorbGlow` at the bar's end; Camelot `PlayerFrame.lua` wires them up).
`UnitGetTotalAbsorbs` is `SecretReturns`, but the game's heal prediction calculator
(`CreateUnitHealPredictionCalculator`, filled by `UnitGetDetailedHealPrediction`) gives the absorb clamped as asked
(`SetDamageAbsorbClampMode`), secret.

Seen in game (`/sab shield`, a level 6 priest): the calculator answers, and the game's absorb bar and glow are readable
(at full health the bar hidden, the glow shown), so they say when a shield goes up and breaks. The shield is laid out as
the DoT marker is, part of the health liquid: a hidden reverse bar from the health's front, fed the absorb clamped to
the whole bar, gives where it starts, and the health liquid's front moves back there (`Bars.Front`); the shield (opaque
dark-gold glass, a sheen brightening to a crescent rim on the front, `Strands.tga` drifting, rays, crackle, motes) fills
the rest, in the marker's frames (a clip with SPILL, a pool in it). Four looks came before, each judged in game: a wall
of light past the health's front where the game draws absorbs (read as an incoming heal); see-through glass over the
health's end (the green showed through); added light at the harness's strength (washed to white in game, which draws
added light several times stronger); and a golden liquid of its own on the marker's way, with the health liquid lifted a
level over it (`Bars.SetOver`), which hid the player bar's text in game (the text copies the target frame gets did not
show), so the shield never raises it. Judge the shield at the game's size (about 1.3 px a unit here), not the gallery's
3. A clip frame inside a bar-sized clipping frame once hid every texture the bar's mask cut (`/sab shield test` showed
it); the marker's layout works. A texture has one alpha: `SetVertexColor`'s fourth value and `SetAlpha` set the same
thing. The shield gave its layers their strength as a vertex alpha, then faded them in with `SetAlpha(1)`, so in game
the faint sheen (0.16) drew opaque, a flat cream block over the glass (seen in game, both with added and with blended
light; the harness had multiplied the two, so its renders looked right). The washed-out added light above was likely
this too. Strengths now go through `SetAlpha` alone and the shield fades by its frame's alpha; the mock keeps one alpha
per texture.

Seen in game after that: the look right, but the body ran a few pixels past the rim's crescent in a straight cut, and
nothing tied the shield to the health liquid. So the body is cut on the crescent by a mask of its own (`ShieldEdge.tga`,
`EDGE_SPAN` rims wide, `CLAMPTOBLACKADDITIVE`), and where the two meet the shield's light spills back over the health
(`contact`), lit a moment after a soaked hit. Nothing left the shield either (asked for: light sparking out, god rays),
so it sheds god rays from the rim's middle past the bar (`Beam.tga`, square so `SetRotation` can aim it, `shed`) and
embers drift off the rim while it holds. The rays' frame is on the bar, not in the clip: cut to SPILL around the bar
they ended in a hard box. In game the health then ended stick straight and still at the shield: its front's waves lay
under the opaque glass. A band of glass clouding over before the body came next, in colours of its own (the glass's,
then the body's average with its strands, measured on a render): in game each showed as a strip with a step where the
body began, the body's colour there never quite the band's. So the whole body, every layer, fades in from `LEAD` back
over the health's end over `FADE_W` by a mask of its own (`fadeIn`, `ShieldFade.tga`, `FADE_SPAN` fades wide, a third
mask on each body texture after the bar's and the edge's), with nothing of its own colour to match, the spill swelling
to it and fading out across it (`spillOut`), in a frame of its own (`glow`) that breathes. The health liquid's front is
on the shield's start itself: set `LEAD` past it, it ran past the real health as a shield drained, and at full health
the whole liquid slid right, a gap at the bar's left end (seen in game). The shield laps at it now and then (`Bars.Lap`,
`Liquid:Nudge`: a ripple with no splash), a soaked hit harder; at 45 every 0.8 s the health kept sloshing when idle
(seen in game), now 10 every 1.8 s, felt better in game. A mirrored crescent once stood where the glass turns opaque,
the barrier's back face: in game a stray C beside the health, so it is gone. How a shield ends (asked for: something
really cool): however it goes, broken, run out or taken off, it shatters (`SHATTER`: the glass strains with glowing
cracks, whitening and a tremble, then flashes white in its own shape and bursts into shards, `Shard.tga`, and streaks,
with a shockwave off the rim, `blast`, and a splash in the health). A shield that ran out or was taken off once
dissolved instead (the glass brightening, then fading out among rising lights; a slow fade before that was a muddy
smear): not liked, so every ending shatters. Either way the glass holds its last place: a second hidden bar (`ghost`,
`hold`) is fed as the run is and stops being fed when it ends, while the run drains and the health flows up beneath
(faded while the health was still flowing up, the empty bar showed between them in game), the run measured from the rim
while the glass shows (`RunInset`, `m.inset`): let through to the health's front, the last `RIM_INSET` units of green
showed past the rim the moment the shield broke. Render the endings as the game runs them (the run easing to nothing,
the glass its last size back from the health's front, which the breaking hit moves) and look at them frame by frame: a
render that dropped the shield in one frame hid all this. What bursts or rises is spawned along a whole bar back from
the rim and cut to the shield by a mask of the fade-in's shape SPILL taller (`burstFade`), so a bigger shield throws
more; cut by the pool instead, the shards ended in a hard line. `Crystal.tga` (an ice shard clear in its middle) drew as
faint outlines, hence `Shard.tga`; a flash of its own over the shield was a hard-edged box, hence the glass whitening
itself. A heal cast on yourself with a shield up painted green over the shield: the heal marker's seam
(`HealMarker.lua`) lays the health's colour on the health's edge, where the health liquid's front no longer is. While
the front is moved (`Bars.Moved`) the heal marker lies side by side from the health's edge, past the shield, with no
seam.

Not yet seen in game: the endings, and `ABSORB` on the player (the rim's flare on a soaked hit).

## Weakened Soul

*Where:* `Soul.lua`, `weakenedSoul`; Forever's tooltip: 15 s, Power Word: Shield 30 s

Auras are secret in combat, so the wait is timed from a shield going up (`Shield.Exists`, the game's absorb display),
unless the player's own cast of another spell whose description says "absorb" went off within `ATTRIBUTE` (English
only); out of combat the debuff itself is read, which starts, corrects or ends the wait. Where the absorb display is
secret, the player's own shield sent at themselves (`UNIT_SPELLCAST_SENT`'s target) starts it. Drawn on the health
liquid's own front (`Bars.Mover`) and the health's edge (`Bars.Edge`), so it follows the client's layout; while a shield
holds, in its glass (`Shield.State().mover`). Chosen from four mockups (ash, a healing crack, a ghost of the glass, a
sigil) and refined in mockups: ash over the breaking glass was a grey block, so it waits for the burst; a ring at the
release read as generic, hence the crescent. Its textures are all below OVERLAY sublevel 0, as the shield's: the bar's
texts are OVERLAY 1 at the same level. In combat any absorb going up that is not the player's own cast (a Voidwalker's
Sacrifice, an item) is taken for Power Word: Shield until the debuff can be read; a shield landing on one already up is
missed. Out of combat a debuff read as gone ends only a wait it was once read in (as `Heals.lua`). Where the absorb
display is secret, both files take the player's own shield on themselves from `UNIT_SPELLCAST_SENT`'s target against
`UnitName("player")`; what Forever sends there for a character with a surname is not yet seen. Neither the shield nor
Weakened Soul is drawn on other addons' player bars (Frames Forever and ClassicUI Forever fade the game's frame out, so
both stay hidden there): not built yet. `/sab soul test` plays it with no shield.

Seen in game and liked: the look.
