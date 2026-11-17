# Adaptors

Notes for whoever works on this folder, person or agent. Not packaged (`scripts/package.ps1` drops every `.md`).

An adaptor is a file of ours that finds another unit frame addon's own bars and hands them to the liquid, for an addon
that does not call `SmoothAnimatedBars.AddBar` itself. The public API (README, "For addon authors") is the way this is
meant to work: the other addon knows when its bars are built and taken down, and we maintain nothing. An adaptor reads
another addon's private fields, which can change in any of its releases, and we cannot test it without that addon.
So each one is an exception, kept small.

## When to write one

All of these:

- Players ask for it, and enough of them run the addon for it to matter.
- Its author has been asked to call `AddBar` (an issue with a ready snippet for their code) and has not, or not yet.
- Its bars can be found from global frames by fields that look stable (set once when it skins a frame, not rebuilt
  each update).

Look first at whether it already does: FlareUI calls `AddBar` from its own code since 6.10 (`ns.SAB` in its
`Modules/UnitFrames.lua`), so it needs no adaptor. Ask the author first or at the same time. If they adopt `AddBar`, the adaptor can go. Until it does, it steps aside
for any bar their addon has handed over itself (`Bars.HandedBy`, in `Adaptors.Hand`), removed or not, so the two never
fight over a bar's options or undo their `RemoveBar`.

## How one works

- `Adaptors.lua` holds the list and the shared helpers. Each adaptor is a file listed in the toc after it, which calls
  `ns.Adaptors.Register({ addons = { <folder names> }, name = <shown to players>, Look = fn })`. Several folders when
  the addon also comes as standalone pieces.
- `Adaptors.Start()` runs at `PLAYER_ENTERING_WORLD` (`SmoothAnimatedBars.lua`), after our bars are set up. Only the
  adaptors with one of their folders loaded (`C_AddOns.IsAddOnLoaded`) run, once at once and then every `LOOK_EVERY` (1 s), in
  combat too. With none loaded, nothing runs.
- `Look` finds the bars and calls `Adaptors.Hand(self, bar, unit, kind, frame, options)` for each. `frame` is our frame
  the bar stands for (`player`, `target`, `focus`, `pet`, `tot`, `party`), and the bar takes that frame's on/off setting
  (`playerHealth`...), colour (with `theme = "settings"`) and effects, through `Bars.AddBar`'s internal `key`, not the
  Other Addons' Bars setting. To the player they are still their unit frames.
- Every lookup goes through `Adaptors.Table`, `Adaptors.Bar` and `Adaptors.Unit`, so a field that is gone or changed
  type finds nothing, and nothing happens: their bars stay plain, ours stay paused under their faded ones. Errors are
  reported once per adaptor.
- Calling `Hand` every second is fine: `AddBar` with the same arguments does nothing, and a new unit (a pooled party
  button moved) is followed.
- Hidden and faded bars pause by themselves (`Bars.lua`, `Sight`). An addon that fades the game's bars (alpha 0) and
  hides its own when a piece is turned off needs nothing more: the liquid follows whichever shows.
- A game bar the other addon keeps but moves and takes the game's mask off: `ns.Bars.Unmask(bar)`, for good (the other
  addon can only undo it on a reload). The mask, laid out for the game's art, would cut the liquid short.
- Read the other addon's code, never copy it, and note its licence and the version read in the file's header.

## Testing

- `tools/harness/test.py`: each adaptor gets a section that builds the other addon's frames in the mock as that
  version builds them, sets `__addons.<folder> = true` in the session's setup, and checks the bars get the liquid,
  follow our settings, and that nothing is looked for without the addon.
- In game: install the addon's release into `_forever_\Interface\AddOns` and restart the game fully (a new toc file is
  not picked up by `/reload`). `/sab debug` lists every handed-over bar as `<name> <unit> <kind>`.

## Adaptors

### ClassicUI Forever (`ClassicUIForever.lua`)

github.com/wowaddonmaker/classicuiforever, CurseForge 1700043, author justawower (owner fallenguard), all rights
reserved. Read from 0.58.0 (16 November 2026). It releases often. Folders: `ClassicUIForever`, and
`ClassicUIForeverStandaloneUnitFrames` for its standalone Cast Bars and Unit Frames piece (its `tools/standalone.py`
builds each piece from the same code, so the same fields).

What it does to the unit frames (its `Units/`):

- Player, target, focus (`PlayerFrame.lua`, `TargetFrame.lua`, `UnitFrameCore.lua` `UF.BuildBars`): fades the game's
  bars to alpha 0 (`ns.Fade`; the player's whole `HealthBarsContainer` and `ManaBarArea`, the target's bars), and
  builds a `host` frame (`frame.fcui.host`, one level over the frame) with its own StatusBars `host.fcui.health` and
  `.power` (`ns.CreateBar`, 119 wide). Its frame art and texts are on frames higher up. The faded game bar is moved
  over its bar to keep the mouse (`UF.Cover`).
- Targets of target: `TargetFrameToT.fcui.totHealth` / `.totPower` (46x7), filled by it from the unit on a 0.1 s beat.
- Party (`PartyPetFrames.lua` `SkinPartyMember`): the same `fcui.host` on each `PartyFrame.MemberFrameN`, the game's
  bars faded, the unit from `frame.unit`.
- Pet (`SkinPet`): keeps `PetFrameHealthBar`/`PetFrameManaBar`, resizes and moves them, and removes
  `PetFrameHealthBarMask`/`PetFrameManaBarMask` from their fills. `PetFrame.fcui.petArt` exists once it has.
- Turning a piece off (`Restore`): its host hidden, the game's bars unfaded; the pet stays until a reload.
- Its bars hold the unit's own values (secret), have nothing on them but the fill (its dark backdrop is on the host,
  below), and `ns.FillUnitBar` sets the fill texture again when its texture option changes (our fill alpha is set
  again every update).

So the adaptor hands over the health and power bars at level 0, with no mask and our colour settings. Seen in game
(0.58.0, a level 33 warrior, out of combat): the player frame's full health bar with the liquid inside its art, its
numbers over it. Not yet seen: power with something in it (the rage was empty) and the fury, the target, focus and
targets of target, the target's health with the DoT marker (the liquid goes a level up and may then tie with its art),
the pet's unmasked bars, the party as members join and leave, and a vehicle.
