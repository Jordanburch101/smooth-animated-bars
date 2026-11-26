# The client

How Forever's client behaves for addons, in general: its UI source, secret values, layering, auras, the realm, toc files.

## Forever's UI source

It is the `forever` branch of github.com/Gethe/wow-ui-source: `gh api
"repos/Gethe/wow-ui-source/contents/Interface/AddOns/<path>?ref=forever"`. The unit frames are
`Blizzard_UnitFrame/Camelot/*` (Forever's overrides) on top of `Blizzard_UnitFrame/Mainline/*.xml`. Forever uses the
modern atlas names (`UI-HUD-UnitFrame-...`) and draws them with its classic gold art. Other installed addons in
`_forever_\Interface\AddOns` (Details, GlowingBars, ItemTree, Leatrix Plus) are worth grepping for working Forever API
use.

## Secret values

Confirmed in game with `/sab debug`. The player's health and power are secret even out of combat. A StatusBar takes a
secret through `SetValue` / `SetMinMaxValues`, with `Enum.StatusBarInterpolation.ExponentialEaseOut` for the client's
smoothing, and frames can anchor to its fill texture. So the liquid never learns which way a bar moved; any change only
stirs it.

## Layering

The bars use `useParentLevel`, and the bar text is in the container's `OVERLAY` layer at the same frame level. Our
frames take the bar's level (`SetUsingParentLevel`) so the text stays above the liquid. The game's bar masks
(`HealthBarMask` on the player's container, `ManaBarMask` and the target's `HealthBarMask` on the bar) also cut textures
in child frames, so the liquid uses them.

## Auras in combat

`C_UnitAuras.GetPlayerAuraBySpellID` is `RequiresNonSecretAura`, and in game it answered "none" in combat for a
Rejuvenation that was on the player. So a missing aura only ends a heal that was seen before, out of combat
(`Heals.lua`, `checkAuras`). Sitting to eat or drink has no API; `PLAYER_STARTED_MOVING` (in Forever's
`UnitDocumentation.lua`) and any other cast end it.

## Regeneration

On Forever energy and mana refill continuously rather than in 2-second ticks, so the gallery's scenarios draw them that
way (`gallery.py`, `regen`).

## Toc changes

A toc change (a new file) needs a full game restart; `/reload` does not pick it up.

## No realm since build 71037

Reported by another addon's author (Forever's patch of 2026-11-21): `GetRealmName()` returns `""`. An empty realm is no
answer, never a realm: a character without a surname keeps its one saved "Name - X" profile (`SmoothAnimatedBars.lua`,
`KnownKey`; names are unique across the region), else takes the ruleset as a surnamed one does, and keeps that one if
the realm reads again. Before the fix such a character had switched to the account-wide settings (its key "Name - ", not
in `ownSettings`); settings made under "Name - " then move to its new key. Heal recipients fall back to the loose
"Name-..." match (`Heals.lua`, `realmPart`), after the exact ones. The mock keeps a realm by default, as the profile
tests key by it; the no-realm tests set it to `""`. Seen in game after the fix: fine on characters with surnames.
