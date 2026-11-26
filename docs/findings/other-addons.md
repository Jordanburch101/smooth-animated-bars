# Other addons' bars

Bars handed over with AddBar, and the adaptors for addons that do not.

## Other addons' bars

*Where:* `SmoothAnimatedBars.AddBar`, the global table in `SmoothAnimatedBars.lua`; `Bars.lua`, `External`; README "For addon authors"

Asked for by Frames Forever (Halfdays), which hides the game's frames. Their bars are spots with `external` (the
options) in `bars`, built by `NewBar`, set live by `Bars.Apply` under one setting (`externalBars`) and not by our
per-frame ones. The rule on game frames does not apply: the addon hands us the bar and agrees to its fill going
transparent. Frames Forever's code (in `_forever_\Interface\AddOns\Frames_Forever`): its default health colour is a
gradient from `UnitHealthPercent` curves, so secret, followed by the white liquid and a `MOD` tint as on battleground
plates; its "lost health" mode is `SetReverseFill(true)` with the bar showing missing health, so the liquid is mirrored
(`Liquid:SetMirror`); its text is three levels up. At the bar's own level the liquid showed dim in game: the bar's
background, a texture on the bar (dark at 80%), drew over it, as a plate's did. So it is one level up by default
(`level`); seen in game and right. Their heal prediction is a child frame one level up too, past the fill's edge, so
only the front's waves can meet it (not yet seen).

Seen in game: the liquid on their player bars, and their default health colour (secret) through the tint.
`GetReverseFill` (the client's getter), the colour and the level are looked at every 0.1 s. The player's bars get the
heal marker (`HealMarker.lua`, `BuildExternal`: at the liquid's level, under it by sublevels with seams, as on the
player frame; hidden on a bar filling from the right) and the mana build-up (`ManaRule.lua`, `Bars.ExternalBars`); seen
missing in game before that (eating, a bandage), and working after. Frames Forever's bars hold a percentage
(`BarValue.lua`: range 0..100 when health is secret), so the marker takes `UnitHealthMax`/`UnitPowerMax` for its range,
not the bar's. Four review agents went over the first version; from them: `AddBar` again with the same arguments does
nothing (an addon may call it from its updates; it had snapped the liquid and cleared its motes), options are checked
and an unknown theme falls back, our own bars and nameplate units are declined, at most `External.MAX_GROUP` (10) party
and raid bars and no fury on them, a bar's errors are reported once (`Bars.Reported`), bars added before
`PLAYER_ENTERING_WORLD` wait for it (`Core.ready`) so the login order of `Bars.Apply` and `HealMarker.Apply` holds, the
heal seam takes a secret colour directly, and the table is read-only. A target's health bar gets the DoT marker
(`Marker.lua`, `BuildExternal`, `RaiseExternal`): seen missing in game (a Rend on Frames Forever's target), and working
after. Measured against `UnitHealthMax("target")`, at the liquid's level, no kill icon, hidden on a bar filling from the
right; `Bars.Front` puts a mirrored bar's front back on its fill's left edge. Frames Forever hides the game's player and
pet frames with `SetAlpha(0)` (target, focus and party it reparents to a hidden frame), and "immersion" addons fade idle
frames out the same way. `IsVisible` does not see alpha, so in Halfdays' `/sab perf` the hidden player frame's liquids
still ran (0.12 ms a frame each). So a bar is `shown`, `hidden` (`IsVisible` false) or `faded` (effective alpha under
0.01; `Bars.lua`, `Sight`: `GetEffectiveAlpha`, frames only, `SecretReturnsForAspect` Alpha and
`RequiresScriptObjectAlphaAccess`, so under `pcall`, a secret taken as shown). It is found once a frame in `UpdateBar`
(`b.sight`) and reused by events, `/sab perf` and the markers (`Bars.Sight`): each check is three widget calls. A faded
liquid pauses like a hidden one. A faded marker pauses rather than hides: hidden, it forgot what it had shown, so each
fade-in replayed a meal's release and grew the DoTs in from nothing (a review caught it). While faded it drops landings
and ticks (`calm`), and a buff reached meanwhile sates the bar quietly (`Bars.Sate`).

Not yet seen in game. Aura timers (issue #13, found in game by a DoT timer addon's author): addons show a target's
debuffs only through the game's `CustomAuraContainerTemplate`, whose buttons drive the bar handed to `SetDurationBar`,
and once an aura is assigned the button and everything in it are forbidden (our liquid's frames too: "calling
'SetVertexColor' on bad self"), its bar's getters included, and `C_UnitAuras` throws in combat. So `AddBar` declines a
bar under a frame with `SetDurationBar` or a forbidden one (`Bars.AuraBound`), and `RunBar` drops one that turns
forbidden without a word in chat. The mock's `__forbid` makes a region and its children reject every method but
`IsForbidden`.

Not yet seen in game: whether the button's `SetDurationBar` and `IsForbidden` answer as expected.

## Adaptors

*Where:* `SmoothAnimatedBars/Adaptors/`, `agent.md` there says when to write one and how

For a unit frame addon that does not call `AddBar`, a file of ours finds its bars and hands them over (`Bars.AddBar`'s
internal `key`: our frame's settings, not `externalBars`). The first is ClassicUI Forever's. Read the other addon's
code, never copy it, and ask its author to call `AddBar` too. An adaptor steps aside for a bar that addon hands over
itself, removed or not, and for one whose liquid failed (`Bars.HandedBy`, `Adaptors.Hand`): a review found the two would
otherwise swap the bar's options every second and undo its `RemoveBar`. A game bar it unmasks (`Bars.Unmask`) is cut by
its clip frame at the bar's edges instead (no spill), or the front's glow showed past a smaller bar onto its art.

Seen in game: ClassicUI Forever's player health, inside its art. FlareUI (6.10 on, `Modules/UnitFrames.lua` `ns.SAB`)
calls `AddBar` itself, with no theme, so its bars kept its colours (a warrior's player bar in class tan whatever the
editor said). Your Colours on Their Bars (`externalColors`, off by default; `Bars.lua`, `ChoiceFor`, `GameColor`) gives
every handed-over bar the colour picked for the frame it stands for, Game Colour being the game's (green health), not
the bar's. A bar's `spot.frame` is set before `NewBar` colours it: set after, a bar handed over with the setting on
(after a `/reload`) failed to set up and kept its own fill (seen in game).

Seen in game and right on FlareUI's bars after that.
