# DoT tracking

The player's DoTs on the target and plates (Dots.lua, Marker.lua), and DoTs on the player.

## DoT tracking

*Where:* `Dots.lua`, ported from DoesItDie, MIT; keep its licence notice in the file

The combat log is closed to addons (registering `COMBAT_LOG_EVENT_UNFILTERED` shows a "blocked" popup). `UNIT_COMBAT`
still fires on the target, focus and nameplates with plain actions (WOUND, PARRY, DODGE...), but its damage amounts are
secret: a whole session of a warrior's Rends in DoesItDie's saved log had not one readable hit. The school stays
readable, so (as DoesItDie 0.9.1 to 0.9.4 does; ported here) a hit is matched to a DoT's tick by school and timing alone
(`onHiddenAmountHit`), bleeds kept on their cast's schedule so white swings can't pull them early; a DoT that never
ticks is dropped, but only on a mob whose hits have shown their school (`schoolHitAt`; DoesItDie drops on any mob in
view). The tooltip's numbers leave out spell and attack power, so after combat the damage meter's per-spell totals
(`C_DamageMeter`, readable then; seen in game by DoesItDie on a warlock) teach each DoT's real tick (`learnFromMeter`),
blended by tick count. The meter counts every tick and the tally only those seen, so a fight is not learned from where a
DoT ticked out of sight (`Dots.LoseSight`: tabbed away, its plate gone while the mob lived), a finisher's points were
unknown, or the addon loaded mid-fight (a review found the first saved 1.7 times the real tick). Still inherited from
DoesItDie: any hit of the school near a tick is taken for it, the player's own Mind Flay or Drain Life too.

Not yet seen here in game: any of the ported part. The hit's flag is readable, though (seen in game: `BLOCK_REDUCED`,
and a crit made a Rend gush), so a crit on the target makes a bleed gush; it does not say whose hit it was. `/sab dots`
counts what the target's hits show (`Dots.lua`, `noteFlag`). The player's `UNIT_SPELLCAST_*` events and spell
descriptions are readable. DoesItDie reports (not verified here) that creature GUIDs are secret in instances, so mobs
there are keyed by their nameplate. The marker and kill icon (`Marker.lua`) leave every comparison with health to
StatusBars, as the liquid does. The marker is up to two DoT liquids, one per school (oldest at the front), drawn 10 and
5 sublevels under the health liquid (`Liquid:SetSublevelOffset`; Liquid.lua uses sublevels 3 to 7 of -8..7, so there is
no room for a third), and the health liquid's front is moved onto where the health will end (`Bars.Front`). Those
sublevels order the DoT liquids, which share a clip frame, but not the health liquid, in frames of its own: at the bar's
level with the marker, the health's front sometimes lay under a DoT liquid's straight cut (seen in game on the target
frame, one DoT right and the next wrong, as on plates before). So while a marker is live on a bar (`Bars.SetOver`, from
`Marker.Apply`) its health liquid is one level up, with copies of the bar's texts (`TextString`/`LeftText`/`RightText`,
put on the bar by `SetBarText`) one more up (`Bars.lua`, `Over`); on another addon's target bar the liquid goes one past
its `level`. The target's heal prediction and absorb bars are child frames one level up too, so they now tie with the
liquid's front.

Seen in game on the target frame: the front over the DoTs every time.

Not yet seen: other addons' target bars.

Reported by a player: Health Bar Text Forever (github.com/Pirson-s-Addons/HealthBarTextForever) puts its own texts on
the target's health bar (`bar:CreateFontString`) and fades the game's to alpha 0, so under the raised liquid its text
was hidden and the copies of the game's showed nothing. Every other FontString on a raised bar is copied too
(`Bars.CopyOtherTexts`); seen in game with that addon: working. The kill icon is the atlas
`UI-HUD-UnitFrame-Target-HighLevelTarget_Icon` (Forever's `TargetFrame.xml`).

## Rogue poisons

*Where:* `Dots.lua`, `onPoisonCombat`

A coating procs on weapon strikes, so no cast event says when it lands. DoesItDie's saved log on Forever has `HIT
(amount hidden) school 8`: the amount is secret but the school is not, so a Nature hit on a mob while the weapon carries
a poison with damage over time is taken as its tick. The coating is read from the poison's own
`UNIT_SPELLCAST_SUCCEEDED` ("Coats a weapon ...") and saved with a `time()` expiry; `GetWeaponEnchantInfo` (if it
answers) forgets it once the weapons are bare. One stack is counted, and with a poison that strikes at once (Instant
Poison) also on, it takes two Nature hits a tick apart. Not yet tried in game: the coating's text on Forever, whether
`GetWeaponEnchantInfo` answers, and how other players' Nature damage on the same mob gets in the way.

## Poison skulls

*Where:* `Marker.lua`, Skulls

The game's own `SPELLS/Skull.m2` (file ID 166881) loads in a `PlayerModel` frame by file ID, and `SetFacing` and
`SetModelAlpha` work on it (seen in game, on a target's Nature DoT). The skulls hang on a hidden bar from the health
bar's left edge to the health's edge, over the target's secret health, so they stay over the bar when the DoTs would
take more than the health. The mock draws no model, so the gallery cannot show them, and no gallery scenario has a
Nature DoT. `Skull.tga` (`make_media.py`) stands in where no model frame can be made.
`SPELLS/Poison_ImpactDot_Med_Base.m2` (166644), the game's poison effect, also loads, but drew as tangled green lines in
a frame.

## DoTs on the player

*Where:* `SelfProbe.lua`, `/sab self on`; seen in game on a mob's Poison, 744

Out of combat the player's harmful auras are fully readable through `GetUnitAuras`, `GetAuraDataByIndex` and
`GetDebuffDataByIndex` (name, spellId, duration, expirationTime, dispelName), and `GetAuraDuration` returns a userdata
whose `GetRemainingDuration`/`GetTotalDuration`/`GetElapsedDuration` answer. In combat all three lookups throw "Auras
cannot be accessed when secret while tainted", and `UNIT_AURA`'s `addedAuras` is secret (the payload itself is not).
`UNIT_COMBAT` on the player always has a secret amount but a readable action, flag and school, in combat and out: the
poison's ticks were school 8 every 3 seconds, the mob's swings school 1. A mob's DoT description has no number
("Inflicts Nature damage to an enemy every 3 sec. for 30 sec."; Infected Wound's was nil).
