# Party and raid frames

The party member frames and the raid-style frames.

## Party frames

*Where:* `Bars.lua`, `AddPartySpots`; `/sab party` reports what the game shows, saved in `SmoothAnimatedBarsDB.partyProbe` for `/reload`

`PartyFrame` (`Blizzard_UnitFrame/Shared/PartyFrame.lua`) pools four `PartyMemberFrameTemplate` buttons and on each show
releases and re-acquires them as `MemberFrame1..4`, so a bar can land in another place: each bar gets a spot of its own
when first found. Health is `HealthBarContainer.HealthBar` (mask on the container), power `ManaBar` (mask on the bar),
70x10 and 74x7. The game puts the unit on each bar (`bar.unit`, party1..4), which the liquid follows.

Seen in game with `/sab party`, in Stormwind and in the Stockade in combat: health, power and `UnitHealthMax` secret,
sizes, masks and the fill's alpha readable, class and power type readable (in a dungeon in combat too),
`UNIT_HEALTH`/`UNIT_POWER_UPDATE` fire for the party units (power many times a second). Each health bar has the game's
`MyHealPredictionBar`, `OtherHealPredictionBar`, `HealAbsorbBar` and `TotalAbsorbBar` (child frames, a level above the
liquid) and `TempMaxHealthLoss`. They are left showing: they lie on the fill's front and tell of heals and shields the
addon does not track for party members (on the player frame the heal marker shows the same heals, so the game's is
hidden there); how they draw against the liquid is not yet seen. The game makes the member frames when `PartyFrame`
first shows (`PartyFrameMixin:OnShow`), which can come after `GROUP_ROSTER_UPDATE` or with no group change (Edit Mode),
so while a wanted party bar is missing they are looked for every second out of combat (`LookForParty`). A member's
colour is read again with the half-second online check, and a hidden party bar (perhaps left on `player` by Edit Mode's
preview) is never stirred. Whether a member is online is asked of the member frame's unit, as the game's
`UpdateOnlineStatus` does: in a vehicle the bar shows `partypetN`. An empty slot's unit answers `UnitIsConnected` false,
and while a member is offline the game's grey bar is given back. Raid-style party frames (`CompactPartyFrameMember1..5`,
CompactUnitFrames) are another matter: no masks, and their colour and fill alpha secret even out of combat. The party
pets' bars (`PetFrame.HealthBar`, no mask) and the fury on a party member's rage are left out for now. Liquid on the
party bars not yet seen in game.

## Raid frames

*Where:* `Bars.lua`, `Bars.raid`, `raidHealth`, off by default; `/sab raid` reports them, saved in `SmoothAnimatedBarsDB.raidProbe`, and `/sab raid test [low|up|off]` lays magenta blocks on their health bars

Raid frames, raid-style party frames, pets and main tanks are all `CompactUnitFrameTemplate`
(`Blizzard_UnitFrame/Shared`), named `CompactPartyFrameMember1..5`, `CompactRaidGroup1..8Member1..5` (groups kept apart)
and `CompactRaidFrame1..N` (combined, made on demand, handed between units). Their settings are CVars
(`raidFramesDisplayClassColor`, `raidFramesHealthBarColor` as AARRGGBB hex, `raidFramesHealthText`, power bars, dispel
overlay...) and Edit Mode (size 72..144 x 36..72, groups, sort, opacity). Seen in Edit Mode's preview (every frame on
`player`): health bar 96x42 at 1,1 in a 98x44 button, no mask, at the button's level; colour, fill alpha, frame alpha
(range fade) and `UnitInRange` secret, `GetEffectiveAlpha` refused (RequiresScriptObjectAlphaAccess); the name, health
text, role icon and aggro border are ARTWORK 0 on the button, heal prediction and shields BORDER 5-6, absorbs ARTWORK
1-2, target highlight OVERLAY 0. With the test blocks: at the same level the client sorts both frames' textures by layer
together (an ARTWORK 3 block hid the role icons, one level up hid the names too, a BORDER 1 block hid nothing of the
game's); text drew over the ARTWORK block. So the raid liquid is in BORDER (`Liquid:SetLayerMap`, `Bars.raid.LAYERS`),
at the bar's level. The first build cut it to the bar with a clip frame (`SetClipsChildren`), and in game in a party
with raid-style frames every bar showed black at 100%: the fill hidden, the button's dark background over the liquid. A
clipping frame seems to be drawn outside the layer sorting (likely also why a plate's background drew over its liquid at
the bar's level). So it is cut by a square mask of our own (`Square.tga`, `Bars.raid.MASK`), motes too (the frames
touch), and its clip frame does not clip.

Seen in game in a party with raid-style frames: the liquid in class colours, names, health text and the target's
highlight over it. Its colour is worked out from those CVars and the class (`Bars.raid.Color`), and only a secret class
falls back to the bar's secret colour on a `MOD` tint. Power (`raidPower`, `Bars.raid.KINDS`) is the same on `powerBar`:
8 px under the health (which shrinks by that), a frame of its own at level 5 with its background on it, shown by the
game for everyone or healers only; its colour is the power type's. At the party's 20 fps the raid-style party looked
steppier than the player frame (seen in game), so the rate follows how many raid liquids show (`Bars.raid.RATES`): up to
10 at 30 fps stirring every 0.4 s, up to 20 at the party's 20, more at 15.

Reported twice (a player, and seen here once): the player's own raid frame black until a `/reload`, the game's fill
hidden and no liquid drawn. Seen again after joining a party in combat (the bar's own line was not in the screenshots;
`0x16` there is only the template size of power bars the game never shows). Likely cause, not proven: a health bar's
size comes from its anchors alone, 0 x 0 while alone (when it is built on), and the game anchors it by the temporary max
health loss (`UnitFrame.lua`, `TempMaxHealthLossMixin`), whose event `UNIT_MAX_HEALTH_MODIFIERS_CHANGED` is
`SecretPayloads`; `GetWidth` is `SecretWhenAnchoringSecret`. The player's own hidden frame gets that event while alone,
before any size was known, so the liquid was never drawn though the fill was hidden. Whether the game's next plain
anchor (`CompactUnitFrame_UpdateAll`) clears the secret is not known. Such a bar now takes its button's size
(`Bars.raid.SizeOf`; with that secret too, the size last known, from a review), and any bar with no size shows the
game's fill.

Seen in game after the fix: invited to a group in combat, no black frame (once; the bug never came every time, so not
proven). Bars built while alone had 6 slices (built at height 1) and now have the intended 15, 252 textures instead of
171: the cost is not measured in game. `/sab raid` lists, under every frame's bars, our liquid's state
(`Bars.raid.Ours`: live, unit, sight, clip, fill alpha, our value, front, clock, textures shown, colour and tint) and
the heal marker's on it (`HealMarker.DebugBar`), and the player's own frames in chat as well; two reports a few seconds
apart show whether its clock still moves.

Not yet seen in game: the dispel overlay (not among the button's textures), heal prediction and aggro over the liquid, a
secret class's tint, a full raid's frames and its cost.
