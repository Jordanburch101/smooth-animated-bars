# Heals

The heal marker: the player's heals, other players' heals, heals on party members.

## Heal prediction

Forever's player frame has the game's own heal prediction (`healthBar.MyHealPredictionBar` and `OtherHealPredictionBar`,
Mainline `PlayerFrame.xml`), a flat teal bar seen in game on a priest's Lesser Heal. At the bar's level it draws over
the liquid, so `HealMarker.lua` keeps `MyHealPredictionBar.Fill` transparent while the heal marker shows. The other one
(heals from others) is taken over too, see Other players' heals.

## Other players' heals

*Where:* `HealMarker.lua`, `m.others`, asked for

Forever's heal prediction calculator, filled with `UnitGetDetailedHealPrediction(unit, "player", calc)`, gives
`GetIncomingHeals()` as amount, amountFromHealer, amountFromOthers, clamped, all secret (the calculator's own docs).
amountFromOthers lays out a hidden StatusBar after the player's own heals (`OTHERS_LINGER` after the game's bar goes,
the run eased to nothing). Being secret it cannot say whether anything is coming, so the liquid shows while the game
shows its own bar for others' heals (`OtherHealPredictionBar` on the player and party frames, the `otherHealPrediction`
texture on raid-style frames and the Personal Resource Display, hidden by the game at nothing:
`CompactUnitFrameUtil_UpdateFillBar`, Mainline `UnitFrameHealPredictionBars_Update`); a secret answer fades the liquid
by it (`SetAlphaFromBoolean`). That bar's fill is transparent meanwhile, so the game's predictions are all ours while
the marker shows. In Forever's code the prediction is `UnitGetIncomingHeals`, which in the modern client counts heals
being cast, not heals over time; not yet seen in game what Forever counts. Drawn under the player's heal liquids: BORDER
3..7 on unit frames (`OTHERS_LAYERS`; their ARTWORK sublevels are spent), with a seam of the nearest front before it;
BACKGROUND 1..5 on raid-style frames (`OTHERS_RAID_LAYERS`). A resting party or raid marker is woken by
`UNIT_HEAL_PREDICTION` for its member. The amount is one sum, and each healer's own share (the calculator filled with
that healer) is secret too, so neither says who heals. Their look comes from group members' heal casts (asked for:
always the water look before; `HealMarker.lua`, `casting`, `OthersSchool`): a cast from its start to its end, kept when
its text reads as a heal and its caster's class is a healer's (`Heals.CastSchool`, by class as the player's own), aimed
at whoever `UnitIsUnit(caster .. "target", token)` names, or at anyone where that says nothing (click or mouseover
casts, a secret answer). Holy or Nature where every healer casting at the unit is of that school, the shared look
(`OTHERS_THEME`, Tidal in silvery teal) where they differ or nobody is casting (heals over time); kept while the liquid
drains.

Seen in game on raid-style frames: a paladin's heals still in the shared look. The likely cause, not confirmed: a spell
the player does not know may have no description until the client loads it, so it never read as a heal; with no text,
`C_Spell.IsSpellHelpful` stands in and `C_Spell.RequestLoadSpellData` asks for the text. `/sab heals` lists the last
group casts and what was read of each (`castLog`: the spell ID or "a secret spell", heal / helpful / no heal / no text /
not a healer, and whose target).

From a review: a cast's end can be missed (a loading screen, the caster out of sight, a secret payload), so a cast is
over `CAST_MAX` after its start, and its look kept `CAST_GRACE` after its end while the heal lands; with nobody casting
the shared look comes back while the game still shows others' heals (no cast accounts for them), and stays only while
the liquid drains; the player's own raid token is known by GUID or raid index where `UnitIsUnit` is secret; in a raid
only raid tokens count (the events come for both); the class is asked before any spell text, and a spell's reading is
kept by ID.

Not yet seen in game: group heals (Prayer of Healing, Chain Heal) look right only on the caster's target, and bandages
take the caster's class look.

Not yet seen in game: whether other members' casts and their targets are readable there.

Not yet seen in game: any of it, whether the game's bar's shown state is readable on each frame, and the cost.

Seen in game in a dungeon: looks good.

From a review: the amount is never truth-tested (`x and secret or y` tests it), the calculator is asked only while the
game's bar shows, and when it gives nothing the game's bar is left showing (`m.othersBroken`); a woken marker that hides
rests again (`Hide` clears `othersWake`), and only `player`, `partyN` and `raidN` events wake any. On raid-style frames
the player's heal liquid's body, clouds and swirls tie with others' sublevels where others' pool reaches back under it
(no sublevels are free there); accepted.

## Heals on party members

*Where:* `Heals.lua`, `HealMarker.lua`, `BuildParty`; asked for on CurseForge

Who a heal goes to comes from `UNIT_SPELLCAST_SENT`'s target name matched against `UnitName("partyN")` (alone,
`Name-Realm`, or with UnitName's second value), or with no name from the target (`UnitIsUnit("target", "partyN")`). A
member's heals are kept by GUID (name where it is secret), so they stay with them when the party's tokens move; a party
bar whose member changes drops its marker at once (`Owner`). Out of combat a member's heal follows its aura
(`C_UnitAuras.GetAuraDataBySpellName(unit, name, "HELPFUL|PLAYER")`, `RequiresNonSecretAura` in Forever's docs, as the
player's). Markers update at the party liquids' 20 fps and show only while the bar's liquid is live; the game's
`MyHealPredictionBar` there is hidden while they show, as on the player frame.

Not yet seen in game: any of it, in particular the sent name for a member with a surname or from another realm, party
names in an instance, and the aura lookup. Raid-style frames (`raidHealth`) get one too, recipients matched over
raid1..40 as well, a raid unit that is the player counting as the player, and none in Edit Mode (its preview puts the
player on every frame). Laid out for those frames (`HealMarker.lua`, `RAID_LAYERS`): no clip frames (drawn outside the
layer sort there, see Raid frames), square masks to the bar and to past the health's edge, and one heal liquid in
BACKGROUND 3..7, between the button's background (BACKGROUND 0) and the health liquid (BORDER -4..0), so no seam; there
is no room for a second. The button's `myHealPrediction` (BORDER 5) is hidden while it shows.

Not yet seen in game either.

From a review: a member from another realm with the player's first name gets a heal sent at their Name-Realm (exact
readings for the whole group before the loose "Name-...", and the player's only for their own realm, `GetRealmName`);
the player's own raid unit is also known by GUID (`UnitIsUnit` is `SecretWhenUnitComparisonRestricted`); a hidden group
marker looks nothing up while no heal goes anywhere (`Heals.Busy`), raid markers follow `Bars.raid.Rate`, and the aura
check finds who's who once a pass (`unitMap`). Counted in the mock before those: 40 raid frames with ten Renews out went
from about 4600 widget calls a frame to 6400.

A second review: the loose "Name-..." match for a member had no realm guard, so in a raid a heal on an outsider with the
player's first name landed on the player's own raid unit (a member UnitName gives no realm for is now from the player's
realm, and loose matches only where `GetRealmName` cannot be read); a secret sent name is kept for nobody; a member out
of sight (`UnitIsVisible`) keeps a heal whose aura reads as gone; an idle group marker stops before any widget call, and
an owner change on a hidden marker no longer hides it again (that cleared a heal's splash just landed); `TryBuildGroup`
guards both callers. Forever's Chinese battleground bandages say 回复, not 恢复 (now in the cases, 1160).

Reported by a player: Holy Light rank 8 (1177 to 1309, the first rank over 999) showed nothing while the lower ranks
worked. Likely the client writes English amounts with thousands separators ("1,177"), which Wowhead's text (and so the
cases) leaves out; English readers now drop them (`Heals.lua` `plain`, `Dots.lua` `plainSpaces`; Korean and Chinese
write the comma too).

A review found the other languages' heal readers had the same gap (only their DoT readers joined separators): German "um
1.177 bis 1.309" read as 177, a heal over time after its duration as 1, and food as its last three digits.
`L.healReader` now joins "1.177" and "1 177" first (`Locale.lua`, `joinThousands`, a group of exactly three digits, as
Forever's decimals have one). Not yet confirmed in game.

## Heal liquid over the bar's

In game the heal marker's liquid hid the bar liquid's front and showed its own straight cut, though its sublevels are
lower, so sublevels do not seem to order liquids in separate clip frames (the mock does not model draw order).
`HealMarker.lua` lays a seam of the bar's colour over the edge, which looked right in game. `Marker.lua` uses the same
sublevels and has no seam.
