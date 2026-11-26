# The editor and settings

The settings window (`Editor.lua`), how settings are kept and registered, and profiles.

## The editor

*Where:* `Editor.lua`

The game's `ButtonFrameTemplate` window (as the setup's), tabs on the character sheet's title plaque
(`UI-Character-Info-Title`, as Road to Sixty's mode switch: the picked one in colour, the others desaturated at 70%; the
scene buttons under the screen too), `UICheckButtonTemplate` boxes, `UIPanelButtonTemplate` buttons, and chips of our
own. Its colour tiles are stills of each theme's liquid (`PaintTile`): the fill's gradient, the theme's cloud and vein
textures in its colours, the front's glow and line, and two of its particles (its ambient ones, else its burst's), all
static, so a drawer of 26 costs nothing while open. Nothing in it is protected, so it opens in combat, unlike the game's
settings panel. Its first build (a sidebar of sections over one preview) was replaced, on the user's choice of mockups
(canvas "SAB Options Redesign", board E), by a screen of every example at once where the game puts them, clicked to
edit, and an inspector of bar cards with Colour and Effects drawers. The examples are `Preview.lua`'s: `Create` (the
player and target), `CreateSingle` (the target's art standing for the focus, pet or target of target, smaller, each in a
place of its own: the first layout swapped them into the target's place, and a bigger window was asked for to show them
all; the screen's layout was then measured on a screenshot from the game and agreed on a mockup, canvas board F, which
made the window 1180 x 630), `CreateParty` stacked, `CreatePlates`, `CreatePRD` (flat bars raised as the real ones,
`Bars.Preview` with `flat`) and `CreateRaid` (ten raid-style frames in solid colours, as the game's raid art is by path;
`spot.raidLook` gives them the raid frames' colours from the CVars and each member's class, and no spill: the frames
touch, and in game the first build's motes flew over them). All play the scenes (`SetScene`: fight, damage, heal, power;
groups take the frames' rows a little apart); the one being edited at full speed and the rest at a third, idling at 10
fps (`Preview.SetActive`, `spot.calm`), as about 40 liquids show at once. A frame whose health and power are both off
rests full and still instead of playing the scene (`Preview.Resting`, in `SetFraction` and `SetPlate`), asked for once
raid frames, off by default, kept animating their plain fill. The heal scene feeds a heal marker on the example's health
(`HealMarker.Preview`, named "preview" so real heals and meals never reach it): a Renew, then a bandage; in game the
first build's Healing only moved the bar (seen). Its panels (the screen, the inspector, the cards and rows) are Road to
Sixty's panes (its `Screens.Pane`, `Editor.lua` `Pane`): `BackdropTemplate` with the tooltip border and ground by file
ID (137057, 137056, as AceGUI uses them on Forever; the backdrop hands them to `SetTexture`), grey 0.6, gold on the open
card; the screen's is an edge-only frame over its examples.

Not yet seen in game. A colour tile under the mouse is tried on every bar its setting reaches, real and example, without
being saved (`Core.Try`, read by `Core.ColorChoice`), until the mouse leaves or the window closes. In game the first
drawers were empty: a pane anchored TOPLEFT and RIGHT has its vertical middle pinned to its parent's too, which gave it
a negative height (the mock does not model that); panes take both top corners now. The stage's backdrop is a vertical
gradient (`SetGradient`), dusky blue as in the mockup. The settings page's preview is built at `PLAYER_ENTERING_WORLD`
(`Options.BuildPreview`), never while the settings panel is open.

Not yet seen in game: this layout.
## Settings and effects

Every setting is in the editor (`Editor.lua`, `FRAMES` and `TABS`), a window of ours with live examples, opened by
`/sab`, the unit frame menus and Open Editor on the settings page. A new setting needs a control there; the tests check
every setting has one. The settings page is a landing page, a canvas category built at login (`Options.lua`); every
setting is still registered with the game (`Settings.RegisterAddOnSetting`, no rows) and changed through it
(`Core.SetSetting`). Never register initializers into the game's vertical layout lists: on Forever that taints the
Social page. `tools/harness/editor_shot.py` draws the editor's layout. One exception to registering: a bar's own effects
(the profile's `effects[barKey][effect]`, `Core.SetEffect`), a nested table the Settings API cannot hold, read by each
bar's liquids and markers (`b.opts`, filled by `Bars.FillEffects` whenever an effect changes).

Two effects are amounts, not switches (`Core.EFFECT_LEVELS`, asked for): Animation Speed (`animationSpeed`, 25 to 200%,
`opts.speed`) scales the liquid's own clock in `Liquid:Update`, while the fill speed and lean stay in real time as the
edge follows the game's bar; Wave Intensity (`waveIntensity`, 0 to 200%, `opts.intensity`) scales what `FrontOffset`
returns and the body's cut behind it, so ripples, slosh, lean and wobble grow together (the simulation itself is
unchanged). Both are percentages, held to their range when read (`Core.EffectLevel`).

From two reviews: the settings' clean-up (`Clean`) kept only true or false in a bar's own effects, so its levels were
lost at every login and profile change (now kept as numbers in range); a follower's (the fury's) own tremble is scaled
too, or at 0% it shook over a flat bar past its body's cut; the tips' glow from a slice's speed is scaled. Accepted: below
100% speed a stirred liquid takes longer to go quiet, so stays at full rate longer (cost); at 200% a dent reached 6.2,
past the markers' `OVERLAP` of 6, opening a gap behind a DoT or heal liquid for a frame now and then (13 of 9000
slice-frames measured; `OVERLAP` left as seen in game).

Animation Frame Rate (`animationFps`, 30 to 150, 150 is Unlimited, 60 by default) caps how often a moving liquid
updates; see [performance.md](performance.md).

## Profiles

Settings are account-wide in `SmoothAnimatedBarsDB.global` by default (as the user asked), or a character's own in
`.profiles["Name - Realm"]` ("First Last - Ruleset" on Forever) for a character in `.ownSettings`; `Core.db` is the
profile in use, and the game's registered settings reach it through a proxy table (`settingsView`), so a switch needs no
re-registering. Everything else at the root (`Core.account`) is the account's: the setup (shown once per account), the
changelog, the DoT data, `/sab` logs, the plate art. Earlier versions' flat settings become `.global` on load. A
character's own settings start as a copy of `.global` and are kept if it goes back to sharing. `setupDone` marks that
the setup wizard has run.

Editor's Profiles tab: Use Account-Wide Settings, a picker with arrows and Copy (`Core.SetUseGlobal`,
`Core.CopySources`, `Core.CopyProfile`); clicking the picker opens the game's menu (`MenuUtil.CreateContextMenu`), but
not under the controller interface, for the reason the unit menus are left alone there (`Options.GamepadUI`). A profile
change while the setup is open: its Skip puts back every profile it saw in use, as first seen (a character's own made
then from the shared ones as the shared ones were), but leaves a copy over one as copied (`Wizard.ProfileChanged`; a
review found switching away and back had lost the Skip). A character without a surname since the realm went empty: see
[client.md](client.md#no-realm-since-build-71037).
