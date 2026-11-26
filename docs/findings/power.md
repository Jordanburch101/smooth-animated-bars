# Mana and rage

The five-second rule's build-up and the Rage Fury.

## The five-second rule

*Where:* `ManaRule.lua`

Mana is secret, so the wait is timed from `UNIT_SPELLCAST_SUCCEEDED` and `C_Spell.GetSpellPowerCost`, read at
`UNIT_SPELLCAST_SENT`. In game the build-up ran on spells that cost mana, but what Forever answers for a free cast
(Clearcasting) and when a channel's wait should start are not confirmed; `/sab mana` lists what it saw. A ripple's kick
reaches the small bars' wave limit even at a quarter of its strength, so the build-up turns kicks off entirely
(`Liquid:SetSteady`) rather than scaling them down.

## Rage fury

*Where:* `Bars.lua`, `Fury`

A liquid can react to how full a bar is without the addon learning it. `UnitPowerPercent(unit, nil, false, curve)`
evaluates a `C_CurveUtil.CreateCurve()` on the unit's share of its power (0 to 1) and returns a secret, which `SetAlpha`
takes (Forever's docs: `SecretArguments = "AllowedWhenTainted"`). GlowingBars fades its glows this way. The fury is a
second liquid over the rage bar's, its front the bar liquid's (`Liquid:Follow`), in a child frame of the mover whose
alpha is the curve's. A burst on a rage spend shows the alpha from 0.3 s before (secrets can be kept, only not
compared). Seen in game and liked: the fury fading in with the rage, drawn over the bar's liquid. The fury's burst
showed nothing below half rage (its frame is faded out there), so every spend also throws sparks off the bar's own
liquid. Not yet measured: the cost (`/sab perf`).
