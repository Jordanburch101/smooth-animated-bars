# Nameplates and the Personal Resource Display

Enemy and friendly nameplates, and the display.

## Enemy nameplates

*Where:* `Bars.lua`, `plateHealth`, off by default

Forever's plates are `Blizzard_NamePlates` (`forever` branch). The game pools the plates' unit frames:
`NamePlateBaseMixin:AcquireUnitFrame` sets `plate.UnitFrame` and `plate.unitToken` on `NAME_PLATE_UNIT_ADDED` (perhaps
after our handler), and the release sets `UnitFrame` to nil, so one health bar
(`UnitFrame.HealthBarsContainer.healthBar`) shows mob after mob. The liquid is built once per bar and follows its unit,
waits for the unit frame, and gives the game's fill back on removal before the bar is reused. The bar has no mask, so
the clip frame is the bar itself, and the liquid takes a mask of the addon's own, `PlateMask.tga` (`make_media.py`), the
shape of the game's fill with its cut corners: square, it covered the bronze rim's corners. The plate's DoT liquids take
it too (`Bars.PlateMask`). Forever's plates are its own (`Blizzard_NamePlates/Camelot/*`, loaded instead of the shared
files): a bronze bar background (`UI-HUD-CoolDownManager-Bar-BG`), a separate level box
(`ui-hud-nameplates-levelindicator`), and a yellow glow on the target (`UI-HUD-CoolDownManager-Selected-yellow`). `/sab
capture plates` and `capture_art.py --plates` capture those pieces (and the Classic style's `Nameplate-Border`);
measuring a live plate's layout in game did not save, so the layout was measured on screenshots of the Normal and Large
styles. Forbidden plates (`FORBIDDEN_NAME_PLATE_*`, friendly plates in instances) are never handed to addons. At most
`MAX_PLATES` (15) have the liquid, idling at 20 fps. Friendly plates (`plateFriendly`) are a side of their own (`Side`:
by `UnitCanAttack`, never the player's own plate, nothing when the answer is secret) with their own cap (`MAX_FRIENDLY`,
10), so a city cannot take the enemies' slots; the DoT marker gets enemy plates only.

Not yet seen in game: friendly plates, and what colour Forever gives other players' plates. On a plate (10 px, half a
unit frame bar) the swirl texture (64 px a repeat) shows as a thin slice, so veins and lightning show less than on the
unit frames. Drawing them at half size and brighter, with more lightning, was tried in game and the plain look was
preferred, so plates draw the liquid exactly as the unit frames do. The game darkens every plate but the target's
(`deselectedOverlay`, the bar's OVERLAY layer, likely over the liquid as the text is; not checked); that is the game's
frame, so it stays. Plate liquids sit above the bar (`RaisePlate`, `RaisePlateMarker`), the one exception to the frame
level rule: at the bar's level the plate's background, dark inside with a shadow along its edges, drew over the liquid.
Both were tried in game and above was much better. The levels, up from the bar: DoT liquids +1, health liquid +2 (at the
same level the game kept no fixed order, and a DoT liquid on top showed its straight cut over the health's front now and
then), the fill's shading +3 (`PlateShade.tga`), text copies +4. `PlateMask.tga` is only the fill's shape; the fade
toward the top and bottom is `PlateShade`, black drawn over all the plate's liquids, because fading the liquids
themselves let a DoT liquid under the health show through the health's faded edges, a brighter block behind its front
(in game too, and in the gallery's render); seen in game and right. The plate's text inside the bar was then under the
liquid (seen in game: health numbers turned on in the game's nameplate settings were hidden), so `Bars.lua`
(`PlateTexts`) copies the bar's `Text`/`LeftText`/`RightText`, and the name while the game puts it inside the bar
(`NamePlateSetupOptions.unitNameAnchorStyle`, InsideHealthBar for the Modern and Block styles; going by the name's
position instead hid it for players on Block and Large plates, seen in game), into FontStrings of its own above the
liquids and shading, every 0.1 s: text (secret, through `SetText`), font, colour and place; the game's are left alone.
The game sizes these texts with `SetTextHeight(NamePlateSetupOptions.healthBarFontHeight)`, which `GetFont` does not
report: copying `GetFont` drew the copy bigger, so in game it showed doubled over the game's (seen through the liquid's
faded edge) and cut short ("10..."). The copies take the font object and that height, and the health texts are pinned at
their justified side rather than laid over their text-sized box; seen in game and right. The name's copy is laid out as
the game lays out its own (`UpdateAnchors`): between the name's left and right ends, its height left to the text, its
font height set to its line height, and always one line (the XML's `wordwrap="false"`).

Seen in game: the copy wrapped a long name ("Befouled Water / Elemental") once its height was free, and over the name's
one-line box the wrapped line had been cut short instead, so the copy was wrapping all along. The cause, from Forever's
API docs (`SimpleFontStringAPIDocumentation`): FontString has no `GetWordWrap` (its getter is `CanWordWrap`), so copying
the wrap always failed and left the default, wrapping on; the mock had a `GetWordWrap` and now has `CanWordWrap` only. A
player on Better Blizzard Plates (source: github.com/Bodify/BetterBlizzPlates, `forever/`) saw a second name behind the
game's: that addon colours the name with `SetVertexColor`, scales it with `SetIgnoreParentScale`, hides it with
`SetAlpha(0)`, and always reparents it (`RaiseNameAboveHealthBar`: two levels over the bar, level with our liquid and
under its shading, so still copied), or to a HIGH frame with its Raise Strata option. So the copies take the vertex
colour (the game's own name colour is one too, `CompactUnitFrame_UpdateName`), scale (not a secret one: `SetScale` takes
it only untainted; the ignore-parent flag turned the other way around `SetScale`, as that addon does) and alpha, and a
name on a frame in another strata or above the copies' level is not copied.

Seen in game on the game's own plates: fine.

Not yet seen with that addon; its custom font's size is still not copied (the copy takes the game's text height). The
docs also mark `GetCenter`/`GetRect` `SecretWhenAnchoringSecret`, which is why going by the name's position failed, and
`IsShown`/`IsVisible` `SecretReturnsForAspect` Shown: a secret answer is never compared, and the copy is faded by it
with `SetAlphaFromBoolean` (allowed when tainted; `SetShown` takes a secret only when untainted). In a battleground the
game set its plate fills' alpha from a secret, and `GetAlpha` (`SecretReturnsForAspect` Alpha) answered with one:
comparing it to hide the fill errored on every plate (seen in game). Alphas read back from the game's regions are never
compared when secret (`Bars.lua`, `AlphaTo`), and a secret `IsVisible` is taken as visible (`Visible`). The mock cannot
catch these: Lua 5.1 lets `==`, `~=` and truth tests on a table through. With that fixed the battleground plates kept
the liquid but lost the class colour the game's own bar had shown: there the game colours enemy players' plates by a
class it keeps secret (`UnitClass` is `SecretWhenUnitIdentityRestricted`), so `GetStatusBarColor` answers with secrets.
A colour can still be handed on: `SetVertexColor` takes secrets from addons. So the liquid is drawn white (grey, at
`PLATE_SHADE`) and a texture tinted with the secret colour, `MOD` blended, multiplies it (`Bars.lua`, `PlateColor`,
`plateTint`), from the bar's left edge to `TINT_PAST` past the health's edge, in the shading's frame under the shading.
Only when the theme comes from the plate's colour (`fromGame`); a fixed theme keeps its own look.

Seen in game in a battleground: class colours on the liquid, no errors. Putting the liquids back at the bar's level
under the game's texts was tried again in game (the darkening of plates that are not the target, `deselectedOverlay`,
OVERLAY, then lies over them): raised was still preferred.

Seen in game with two DoTs (Fire and Shadow) on a raised plate, each in its own colour inside the rim. The setup's
nameplate step shows four example plates instead of the unit frames (`Preview.CreatePlates`), built from those atlases
in the Normal style and following the plate settings; seen in game and right. The DoT marker on plates (`plateDots`,
needs `plateHealth`): `Dots.lua` keeps DoTs per mob, so `Dots.Unit(token)` reads a plate's; `Marker.lua` builds a marker
per plate bar the first time its mob carries the player's DoTs (from `Bars.Plates()`), with no model skulls, and its
kill icon (`plateKillIcon`, asked for on CurseForge, issue #5) 20 tall and 7 left of the bar, clear of the target's
glow, only 5 levels up so it does not draw over the plates beside it (seen in game and right), and a DoT landing there
shows as more damage to come (Dots says "applied" only for the target).

Seen in game: the marker works on plates, but a bleed (Blood theme) did not show against a hostile plate's red, and a
lighter or darker bleed was tried. The real cause was the health: the game tints its grey fill with the plate's colour,
so an enemy plate shows a deep red, (165, 6, 3) measured in game, while the liquid took the colour at full strength.
Plate colours are taken at a share of the fill's brightness (`Bars.lua`, `PLATE_SHADE`), and a bleed on a plate is the
target frame's Blood. At 65% with the unit frames' theme from a colour, a plate still looked darker than the game's in
game: measured, its red matched (145 against 144) but white in the fill and swirl had greyed it to (145, 45, 42) against
the game's pure (144, 0, 0). A plate's own colour now takes a deep theme (`Themes.FromColor(c, template, true)`): no
white anywhere, its clouds and dark pockets kept to its hue (`swirlC`, `deepColor`, which `Liquid.lua` otherwise shifts
round the wheel), lightning in its colour (`pureLight`; `EmitBolt` otherwise draws it toward white), no inherited
particles, and a nearly flat fill along the bar, as the game's is. Several rounds of tuning went wrong because the
plates being measured never had that theme: they followed a target on Class Color with Class Color on Mobs at Game
Colour, and that fallback (`ThemeFor`) built the unit frames' theme. It, and Reaction on a mob's plate
(`PlateReaction`), now take the deep theme. The bar's colour is readable in game (`1 0 0`, not secret). With 57% the
plate looked right in game. The mock draws the added light layers fainter than the game (10 green against 45 in game for
the same plate), so plate colours have to be judged on screenshots from the game, with the effects off and on. The fill
also fades to dark over its top and bottom quarter, so the game's red sits inside the rim; `PlateShade.tga` darkens the
liquids the same way (`make_media.py`, `PLATE_FADE`, measured on the captured fill).

Not yet seen in game: the plate's size being readable, the liquid under the plate's deselected overlay, and the cost in
a crowd.

A player reported that a mob someone else had tagged no longer showed grey: the game greys an enemy plate then
(`CompactUnitFrame_UpdateHealthColor`, 0.9 grey, by `CompactUnitFrame_IsTapDenied`: `greyOutWhenTapDenied`, set for
enemy plates only, `not UnitPlayerControlled(unit) and UnitIsTapDenied(unit)`). On Game Colour the liquid already
followed it (the plate's colour is read every `PLATE_COLOR_EVERY`), but a theme or Class Color hid it. `plateTapped`
(on by default) makes a tagged mob's enemy plate take Game Colour whatever is picked (`Bars.TapDenied`, from
`ChoiceFor`), so the game's grey shows through the plates' deep theme. A secret answer counts as not tagged. Forever's
target frame greys only its reputation strip and portrait for a tagged mob (`TargetFrame.lua`, `CheckFaction`, on
`UNIT_FACTION`), not its health bar. Greying the target's health was asked for too: `targetTapped` (on by default)
does it on the target's, focus's and targets of target's health, in the addon's own grey (`Bars.TAPPED`, 0.5, the
portrait's grey) through the unit frames' theme, looked at again on `UNIT_FACTION` as the game does (now registered
with the unit frames' events, not only the plates'). No unit events come for a target of target, so its grey follows
on the next `UNIT_TARGET`. Not yet seen in game: whether `UnitIsTapDenied` or `UnitPlayerControlled` come back secret on
Forever, and whether `UNIT_FACTION` fires at the tag.

## Personal Resource Display

*Where:* `Bars.lua`, the `prd` spots, `prdHealth`/`prdPower`

On Forever it is `Blizzard_PersonalResourceDisplay` (forever branch, with a small `Camelot/` override), not a nameplate:
one global frame, `PersonalResourceDisplayFrame`, parented to UIParent and placed with Edit Mode, shown when the game's
option is on (`C_GameRules.IsPersonalResourceDisplayEnabled`, CVar `nameplateShowSelf`) or only in combat by its Edit
Mode setting. Its bars are `HealthBarsContainer.healthBar`, `PowerBar` and `AlternatePowerBar` (a druid's mana in a
form, `DruidAlternatePowerBarMixin`), all `PersonalResourceStatusBar`: the plates' art (`UI-HUD-CoolDownManager-Bar` on
`-Bar-BG`), no mask, texts `TextString`/`LeftText`/`RightText`, and their sizes and the health's class colour are Edit
Mode settings. So the spots are `flat`: they take the plates' look (`PlateMask`, `PlateShade`, raised two levels with
copies of the texts), but keep the unit frames' motes, stirs and Rage Fury, and their theme: the bar's own colour at
full strength, not the plates' deep one at `PLATE_SHADE`, which looked dull next to the player frame in game.
`spot.plate` stays for what only nameplates do. A frame hidden and shown again snaps the liquid to its value
(`UpdateBar`, `unseen`; `away` is a party member offline). The power bar's `ManaCostPredictionBar`, `FeedbackFrame` and
`FullPowerFrame` are at or near the bar's level, so the raised liquid may cover their nearest pixels.

Seen in game: it shows and fits the rim. The heal marker (`HealMarker.lua`, `extra`) puts a marker on each PRD bar from
the same heals, shown only while that bar's liquid is live, one level above the bar (under the liquid two up, as the DoT
marker on a plate), so it needs no seam; it hides the PRD's own prediction, a texture (`healthBar.myHealPrediction`).
`ManaRule.lua` drives every mana bar (`Bars.FindAll`); the form mana's bar counts as mana whatever the power type
(`spot.token`).

Not yet seen in game. A hidden bar's liquid is not updated, so nothing is set off in one (`Bars.WaitOver`,
`Bars.Release`, the fury's burst check `Visible`), heal flags are dropped while a marker is hidden, and a bar shown
again settles (`Liquid:Settle`): a burst in flight when it hid would otherwise finish when it shows. Settled, it counts
as quiet, so it is drawn at once (`drawNow`): waiting for its next idle update left an empty bar for a few frames. Every
class has the `AlternatePowerBar`, but on Forever only a druid's is used, so only druids build one.
