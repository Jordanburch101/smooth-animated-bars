# Taller bars: everything from the game's frames

While a bar height is not the game's, `TallFrames.lua` draws a frame of ours in place of the game's and fades the
game's pieces it redraws. The goal: nothing the game's frame shows is lost or left out of place. This list is every
piece of Forever's player, target, focus, pet, target of target and party member frames (from the `forever` branch
of Gethe/wow-ui-source, `Blizzard_UnitFrame/Mainline` with the `Camelot` overrides), and what happens to it.

Rules for every item: only read the game's frames and fade (alpha 0) what ours redraws, never move, hook or write
onto them (`CLAUDE.md`, Game frames). Secrets are only handed on. Each item gets a check in `tools/harness/test.py`
and is not ticked until it is seen in game.

Legend: `[x]` done and seen in game, `[~]` done, not yet seen in game, `[ ]` to do.

## Already done

- [x] Frame art, sliced and stretched (player, target)
- [~] Frame art for the focus, pet, targets of target and party members
- [x] Portrait, ring cut and grown once it would clip
- [~] Portrait redrawn on every change of unit (target of target, focus target, party roster, name change)
- [x] Health and power bars with the liquid (`Bars.AddBar`), and with the game's fill and colour when the liquid is off
- [x] Bar texts (centre, left, right), name, level, the level circle, the target's banner colour
- [~] Dead and unconscious texts (target, focus, targets of target)
- [x] Icons round the portrait carried to the moved ring (elite dragon, high level skull, raid target, boss, quest,
      leader, guide, role, PvP, prestige, attack icon, corner embellishment)
- [~] Party overlay icons (leader, guide, PvP, role, disconnect)
- [~] Player aggro flash and status glow, target and focus flash, pet and party flash (`Preview.TallGlow`)
- [x] Target with Buffs on Top grows down, clear of its auras
- [x] Vehicle and a druid's extra mana bar: the game's frame given back

## 1. Shields, absorbs and predictions (lost on every taller frame)

The game's health bar segments are children of the faded bar, so they go with it.

How it was done: ours copy each segment onto our bar under the game's own key, its fill seen through a mask on a box
anchored to the game's `FillMask` (which the game lays out from the secret amounts), so the heal marker and the shield
find and hide them on our bars exactly as on the game's (`TallFrames.lua`, `BuildSegments`).

- [~] **Our Shield and Weakened Soul on the taller player bar.** Both follow the frame drawn in the game's place
      (`Follow`), reading the shield's going up on the game's bar.
- [~] **The game's absorb segment and over-absorb glow** (`TotalAbsorbBar`, `OverAbsorbGlow`) on the player, target,
      focus, pet and party health. Hidden on the player while our Shield shows, as on the game's bar.
- [~] **Heal absorbs** (`HealAbsorbBar` with its shadows, `OverHealAbsorbGlow`).
- [~] **The game's heal prediction** (`MyHealPredictionBar`, `OtherHealPredictionBar`), hidden while our heal marker
      shows.
- [x] **The heal marker on taller bars as on the game frame's**: the player's health (with others' heals) and mana,
      and a party member's health (taller party members had none before). Seen in game: heals working on taller
      frames (which frames and whether others' heals were among them not reported).
- [~] **Mana cost prediction** (`ManaCostPredictionBar`, from section 7): copied the same way.
- [ ] **Check in game** that the client lets ours anchor to the game's masks (anchoring to a region laid out from
      secrets), and how the copies look over the liquid.
- [ ] **Temporary max health loss** (`TempMaxHealthLoss`, the player's divider and shadow): check first whether
      Forever ever shows it.
- [ ] **The health loss animation** (`AnimatedLossBar`) on our bar while the liquid is off. Low priority.

## 2. Target combo points (left at the game's portrait)

- [x] **The ring of combo points** (`ComboFrame`, Camelot: parented to `TargetFrame`, centred on its portrait,
      radius 66, five `RogueComboPointTemplate` points, start angle moved while the PvP icon shows). While the target
      is taller: fade it and draw our own points round our ring (radius times the ring's scale), with the points'
      atlases, from `GetComboPoints("player", "target")` (readable), lit and dimmed with their own animation.
      `ComboFrame` fades itself in with `UIFrameFadeIn`, which sets its alpha each frame: check our fade holds.

## 3. Hit text (lost or left behind)

- [x] **Player hit text** (`PlayerFrameContentMain.HitIndicator.HitText`, faded with the main content): copied onto
      ours over the moved portrait, text, colour, size and its alpha each frame (`CombatFeedback` fades it).
- [~] **Pet hit text** (`PetHitIndicator`, not faded): fade it and copy it the same way, as the pet's ring moves.

## 4. Party portraits

- [ ] **Portrait tint and greying**, copied each poll: grey when dead, blue as a ghost, red at low health
      (`Portrait:SetVertexColor`), desaturated when offline (`SetDesaturated`), and the portrait's alpha pulse
      (`UpdateMemberHealth`). Each may be secret: hand it on, never compare.
- [ ] **The offline grey health bar** (`SetStatusBarDesaturated`) on our bar while the liquid is off.

## 5. Glows shaped for the art (left at the game's size)

- [ ] **Pet attack mode** (`PetAttackModeTexture`, `UI-HUD-UnitFrame-TargetofTarget-PortraitOn-Status`, ADD,
      red): through `Preview.TallGlow` as the flashes are.
- [ ] **Party status glow** (`PartyMemberOverlay.Status`, `ui-hud-unitframe-party-portraiton-status`): the same.

## 6. Pieces left at the game's place

Anything the game anchors to its frame's top or portrait is off once ours grows up and the ring moves. Each is
faded and drawn by ours where `Place` puts it, as the carried icons are.

- [ ] **Ready checks** on the player and party members (`ReadyCheck`, centred on the portrait).
- [x] **Player rest** (checked in game: fine left as it is) (`PlayerRestLoop`, the "zzz" flipbook `UI-HUD-UnitFrame-Player-Rest-Flipbook`): our own
      flipbook of the same atlas.
- [ ] **Player group number** (`GroupIndicator`, its three atlases and `PlayerFrameGroupIndicatorText`).
- [~] **Player PvP timer** (`PlayerPVPTimerText`, beside the PvP badge we carry): faded and drawn beside our copy.
      The badge itself was carried to the wrong place (its template's own 0.8 scale), fixed with it (seen in game).
- [ ] **Player play time icon** (`PlayerPlayTime`): check first whether Forever shows it.
- [ ] **Target and focus threat %** (`NumericalThreat`: its text, background and border, over the banner).
- [ ] **Target and focus ping icon** (`PingIconFrame`).
- [ ] **Party resurrectable text** (`ResurrectableIndicator`, by the bottom edge, which moves as members grow down).
- [ ] **Beside the frame, centred on its height** (moved by half the growth): the pet's happiness
      (`PetFrameHappiness`), a party member's not-present icon (`NotPresentIcon`), the encounter power bar
      (`powerBarAlt`). Check in game whether the shift shows before carrying them.

## 7. The player's power bar

- [~] **Mana cost prediction** (`ManaCostPredictionBar`: the share of mana a cast will spend): done with section 1.
- [ ] **Gain and spend flash** (`FeedbackFrame`, `BuilderSpenderFrame`) and the **full power pulse**
      (`FullPowerFrame`): check first whether they show on Forever, as power is secret.
- [ ] **The bar's spark** (`Spark`, on the player, target, focus and targets of target), while the liquid is off.

## 8. Decisions

- [x] **The target's cast bar with Buffs on Top.** (Checked in game: fine left as it is.) It hangs 5 above the frame's bottom, one level below ours, so
      growing down covers its top (and the target of target's). Growing up covers the auras instead. Options: leave
      it, grow by the cast bar's own height only, or draw a copy of the cast bar below ours.
- **Not possible under the rules: the mouse.** The strip ours adds above the game's frame does not click or target,
      and the bars' tooltips stay where the game's bars are. Fixing it means changing the game's secure frame.
