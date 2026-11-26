# Unit frames

The player, target and small frames, their colours and menus.

## Health-loss animation

After damage the player frame shows `healthBar.AnimatedLossBar`, a red bar behind the game's fill. Once shown, it draws
over anything else at that frame level, so its texture is kept transparent while the liquid shows (`Bars.lua`,
`HideGameFill`).

## Class Color by unit

*Where:* `Themes.UnitColor`

Forever's docs mark `UnitClass` `SecretWhenUnitIdentityRestricted`, so a target's class is read under `pcall` with a
secret check, and a bar that gets no answer takes the game's colour. Not yet tried in game on other players or in
instances.

## Small frames

*Where:* `Bars.lua`, `SPOTS` with `frame`

The pet's bars are globals (`PetFrameHealthBar`) with masks named after them; the focus is the target's template; each
target of target is `TargetFrameToT`/`FocusFrameToT` (`.HealthBar`, `.ManaBar`, masks on the bar). No unit events fire
for `targettarget`/`focustarget`, so their liquid is refreshed on `UNIT_TARGET` and never stirred. Not yet seen in game.

## Unit frame menus

*Where:* `Options.lua`, `AddToUnitMenus`

`Menu.ModifyMenu("MENU_UNIT_" .. which, ...)` adds Open Editor (Open Settings before the editor), opening it at that
frame's section; the frames pass themselves as `contextData.ownerFrame` (Mainline `PlayerFrame.lua`, `TargetFrame.lua`,
`PetFrame.lua`), which tells them from chat names. The party's member frames are pooled and nameless, so they are told
by their parent, `PartyFrame` (not yet seen in game).

Seen in game, and the menus' protected actions (Set Focus, Target Marker Icon) still work with it, in and out of combat.
But not in an instance: there a mob's name is secret, so the menu's title has a secret width, which the game can lay out
only untainted. Anything added taints the layout, which errors (`FrameUtil.lua` `GetUnscaledFrameRect`, "a secret number
value, while execution tainted by 'SmoothAnimatedBars'") and draws the menu on one line without its background (reported
by players, error seen in game). So a menu whose unit has a secret identity (`C_Secrets.ShouldUnitIdentityBeSecret`, or
a secret `UnitName`) is left alone; seen in game in a dungeon, the menu right again. Forever has the game's own
controller interface (`Blizzard_Gamepad*`, `C_InputInterfaceStyle.GetCurrentStyle() ==
Enum.InputDeviceInterfaceType.Gamepad`). There a menu taking the gamepad's focus pushes its bindings, and the gamepad
action bar then calls the protected `SetPreferredGamepadInteractTarget` (`MainActionBarFrame.lua`,
`UpdateInteractIcons`). With our entries in the menu that ran tainted: `ADDON_ACTION_FORBIDDEN` on right-clicking the
target (seen in game), and players reported the controller interface broken until `/reload` after inviting from it. So
the menus are left alone while it is on; seen in game, no more errors.
