# Smooth Animated Bars

World of Warcraft addon for **WoW Forever only** (`## Interface: 16001`): the liquid from Smooth Experience
Bar (`../smooth-experience-bar`) in the game's player and target frame health and power bars. The README is
for players; `docs/DEVELOPMENT.md` covers the layout and tools; this file holds the rules.

## Rules

- **Secret values:** Forever keeps health and power secret from addons, in and out of combat (`UnitHealth`,
  `UnitPower`, the bars' `GetValue`). Never compare them or do arithmetic on them. Hand them to widgets
  (`StatusBar:SetValue`) and anchor to what the client lays out; `Bars.lua` explains the design.
- **Game frames:** only read and draw on them. No hooks, no fields written onto them, no changes besides the
  fill texture's alpha. Our frames sit at the bar's own frame level so the game's text stays on top.
- **Forever assets:** game files by path often fail to load there. Use `SetColorTexture` for solid fills and
  the addon's own TGAs in `SmoothAnimatedBars/Media/` (made by `tools/make_media.py`), never `Interface\...`
  game paths. Icons by file ID.
- **Settings page:** a canvas category built at login (`Options.lua`). Never register initializers into the
  game's vertical layout lists: on Forever that taints the Social page.
- **Tests:** run `tools/venv/Scripts/python tools/harness/test.py SmoothAnimatedBars` before every commit; it
  exits 1 on any failed check. The mock (`tools/harness/wowmock.lua`) should be as strict as the client:
  when the client rejects something the mock accepted, make the mock reject it too.
- **Visual changes:** render a preview (`tools/harness/preview.py`) and look at it. Rebuild the gallery
  (`tools/harness/gallery.py`) when the liquid's look changes, and look at it before committing.
- **Gallery:** `branding/gallery/` holds the README's images: animated WebP for each scenario (`hero`,
  `mage`, `rogue`, `warlock` and `rend` with the DoT marker, `priest` with the heal marker, `druid` with both, `eating`, a meal up to its buff, and `mana`, the build-up to mana regenerating) and PNG stills (`frames.png`, `themes.png`), at full quality (`K = 3.0`, 20 fps). No GIFs.
  A full run takes about a quarter of an hour, so run it in the background.
- **Frame art:** `branding/art/` is Forever's own unit frame art, captured in game with `/sab capture` and
  cut out by `tools/capture_art.py`. It is only for the gallery and is never packaged. The layout numbers
  live in `Preview.lua` (`LAYOUT`) and are repeated in `gallery.py`; change both together.
- **Commits:** stage the files you changed by name, never `git add -A`. Commit messages are plain and
  professional.
- **Changelog:** add player-facing notes to `CHANGELOG.md` under the next version as features land
  (`### New`, `### Fixed`, no internal changes).

## Release

Every release, before tagging:

1. Check that the `CHANGELOG.md` section for the version is complete and written for players:
   `## X.Y.Z` with `### New` and `### Fixed`. `bash scripts/changelog.sh X.Y.Z` prints what the release
   will use.
2. Only if something visible changed since the gallery was last rebuilt (the liquid, a theme, the DoT marker,
   the frame art): rebuild the images it shows, all of them with
   `cd tools/harness; ../venv/Scripts/python gallery.py ../../SmoothAnimatedBars`, or just the scenarios that
   changed by name. Look at every image it wrote (a still from each WebP as well), then commit them by name
   with the release, so the README and the store pages show the version being released. The liquid moves at
   random, so a rebuild rewrites every file even when nothing changed: don't commit those. Recapture the
   frame art first (`/sab capture`, then `tools/capture_art.py`) if the game's frame art has changed.
3. Run the tests, commit and push `main`, and check that CI passes.
4. Tag and push the tag: `git tag -a vX.Y.Z -m "Smooth Animated Bars X.Y.Z"`, then `git push origin vX.Y.Z`.
   The version comes from the tag (the toc says `@project-version@`; `scripts/package.ps1` fills it in);
   tags containing `beta` or `alpha` become pre-releases.
5. The Release workflow (`.github/workflows/release.yml`, ported from Smooth Experience Bar) fails at once if
   the changelog section is missing, then tests, builds, makes the GitHub release with the zip and notes,
   and uploads to CurseForge (project 1786695, the `CF_PROJECT_ID` repo variable; the `CF_API_TOKEN`
   secret holds the token, and without it the upload is skipped). Watch it to the end
   (`gh run watch <id> --exit-status`): the GitHub release can succeed while the upload fails.
6. If only the CurseForge upload failed, fix the cause on `main`, then run
   `gh workflow run curseforge-check.yml -f tag=vX.Y.Z` to upload that release again. Run it without a tag
   to test the token and game versions without uploading.

1.0.0 was tagged before there was a release workflow or a CurseForge project. The addon's icon is the game's INV_Enchant_EssenceNetherLarge
(Greater Nether Essence, file ID 132870, found in ItemTree_Data's item records), and it is the icon for the
CurseForge project too, borderless (`branding/README.md`). `public/favicon.ico` is the borderless icon at 16
to 64 px, as in Smooth Experience Bar.

## What we learned about Forever

Facts found while building this, which the code relies on and which are not obvious from it:

- **Forever's UI source** is the `forever` branch of github.com/Gethe/wow-ui-source:
  `gh api "repos/Gethe/wow-ui-source/contents/Interface/AddOns/<path>?ref=forever"`. The unit frames are
  `Blizzard_UnitFrame/Camelot/*` (Forever's overrides) on top of `Blizzard_UnitFrame/Mainline/*.xml`.
  Forever uses the modern atlas names (`UI-HUD-UnitFrame-...`) and draws them with its classic gold art.
  Other installed addons in `_forever_\Interface\AddOns` (Details, GlowingBars, ItemTree, Leatrix Plus) are
  worth grepping for working Forever API use.
- **Secret values:** confirmed in game with `/sab debug`. The player's health and power are secret even out
  of combat. A StatusBar takes a secret through `SetValue` / `SetMinMaxValues`, with
  `Enum.StatusBarInterpolation.ExponentialEaseOut` for the client's smoothing, and frames can anchor to its
  fill texture. So the liquid never learns which way a bar moved; any change only stirs it.
- **Layering:** the bars use `useParentLevel`, and the bar text is in the container's `OVERLAY` layer at the
  same frame level. Our frames take the bar's level (`SetUsingParentLevel`) so the text stays above the
  liquid. The game's bar masks (`HealthBarMask` on the player's container, `ManaBarMask` and the target's
  `HealthBarMask` on the bar) also cut textures in child frames, so the liquid uses them.
- **Health-loss animation:** after damage the player frame shows `healthBar.AnimatedLossBar`, a red bar
  behind the game's fill. Once shown, it draws over anything else at that frame level, so its texture is
  kept transparent while the liquid shows (`Bars.lua`, `HideGameFill`).
- **DoT tracking** (`Dots.lua`, ported from DoesItDie, MIT; keep its licence notice in the file): the combat
  log is closed to addons (registering `COMBAT_LOG_EVENT_UNFILTERED` shows a "blocked" popup). `UNIT_COMBAT`
  still fires on the target, focus and nameplates with plain actions (WOUND, PARRY, DODGE...), but its damage
  amounts are secret: a whole session of a warrior's Rends in DoesItDie's saved log had not one readable hit.
  So no tick is ever seen, DoTs run on their tooltip numbers, and a missing tick only counts on a mob whose
  hits have shown readable amounts. The hit's flag is readable, though (seen in game: `BLOCK_REDUCED`, and a crit
  made a Rend gush), so a crit on the target makes a bleed gush; it does not say whose hit it was. `/sab dots` counts what the target's hits show (`Dots.lua`, `noteFlag`). The player's `UNIT_SPELLCAST_*` events and spell descriptions are readable. DoesItDie reports (not verified here) that
  creature GUIDs are secret in instances, so mobs there are keyed by their nameplate. The
  marker and kill icon (`Marker.lua`) leave every comparison with health to StatusBars, as the liquid does.
  The marker is up to two DoT liquids, one per school (oldest at the front), drawn 10 and 5 sublevels under
  the health liquid (`Liquid:SetSublevelOffset`; Liquid.lua uses sublevels 3 to 7 of -8..7, so there is no
  room for a third), and the health liquid's front is moved onto where the health will end (`Bars.Front`). The kill icon is the
  atlas `UI-HUD-UnitFrame-Target-HighLevelTarget_Icon` (Forever's `TargetFrame.xml`).
- **Other client languages** (`Locale.lua`, `Locale_<tag>.lua`, ported from DoesItDie 0.9.3 without its options
  translations): English patterns run first, then every language in toc order, whatever `GetLocale()` says
  (DoesItDie saw it answer enUS on a German client). Not tried here on any non-English client, but checked against
  Forever's own tooltips for all 1407 class spells (from WhatsTraining's `Classes/Camelot` data) in every language,
  from Wowhead's tooltip API (`https://nether.wowhead.com/tooltip/spell/<id>?dataEnv=16&locale=<n>`, 16 is Forever;
  locale 0 en, 1 ko, 2 fr, 3 de, 4 cn, 6 es, 7 ru, 8 pt; zhTW (5) comes back in English). Every reading matched
  English; the fixed cases are in `tools/harness/language_cases.json`. Wowhead shows some numbers as formulas
  (Rupture), and its text has non-breaking spaces (U+00A0) that `%s` does not match, so every reader turns them into
  plain spaces first. In plain Lua 5.1, `%s`/`%p` follow the C locale and can match bytes inside Cyrillic letters, so
  `Locale_ruRU.lua` lists ASCII bytes. The poison coatings, traps and `Heals.lua` still read English only.
  `/sab dots` logs `NOT READ` for non-English text nothing read.
- **Rogue poisons** (`Dots.lua`, `onPoisonCombat`): a coating procs on weapon strikes, so no cast event says when it
  lands. DoesItDie's saved log on Forever has `HIT (amount hidden) school 8`: the amount is secret but the school is
  not, so a Nature hit on a mob while the weapon carries a poison with damage over time is taken as its tick. The
  coating is read from the poison's own `UNIT_SPELLCAST_SUCCEEDED` ("Coats a weapon ...") and saved with a `time()`
  expiry; `GetWeaponEnchantInfo` (if it answers) forgets it once the weapons are bare. One stack is counted, and with
  a poison that strikes at once (Instant Poison) also on, it takes two Nature hits a tick apart. Not yet tried in
  game: the coating's text on Forever, whether `GetWeaponEnchantInfo` answers, and how other players' Nature damage
  on the same mob gets in the way.
- **Poison skulls** (`Marker.lua`, Skulls): the game's own `SPELLS/Skull.m2` (file ID 166881) loads in a
  `PlayerModel` frame by file ID, and `SetFacing` and `SetModelAlpha` work on it (seen in game, on a target's Nature
  DoT). The skulls hang on a hidden bar from the health bar's left edge to the health's edge, over the target's
  secret health, so they stay over the bar when the DoTs would take more than the health. The mock draws no model,
  so the gallery cannot show them, and no gallery scenario has a Nature DoT. `Skull.tga` (`make_media.py`) stands in
  where no model frame can be made. `SPELLS/Poison_ImpactDot_Med_Base.m2` (166644), the game's poison effect,
  also loads, but drew as tangled green lines in a frame.
- **Heal prediction:** Forever's player frame has the game's own heal prediction (`healthBar.MyHealPredictionBar`
  and `OtherHealPredictionBar`, Mainline `PlayerFrame.xml`), a flat teal bar seen in game on a priest's Lesser
  Heal. At the bar's level it draws over the liquid, so `HealMarker.lua` keeps `MyHealPredictionBar.Fill`
  transparent while the heal marker shows; the other one (heals from others) is left alone.
- **Auras in combat:** `C_UnitAuras.GetPlayerAuraBySpellID` is `RequiresNonSecretAura`, and in game it answered
  "none" in combat for a Rejuvenation that was on the player. So a missing aura only ends a heal that was seen
  before, out of combat (`Heals.lua`, `checkAuras`). Sitting to eat or drink has no API; `PLAYER_STARTED_MOVING`
  (in Forever's `UnitDocumentation.lua`) and any other cast end it.
- **Heal liquid over the bar's:** in game the heal marker's liquid hid the bar liquid's front and showed its own
  straight cut, though its sublevels are lower, so sublevels do not seem to order liquids in separate clip frames
  (the mock does not model draw order). `HealMarker.lua` lays a seam of the bar's colour over the edge, which
  looked right in game. `Marker.lua` uses the same sublevels and has no seam.
- **DoTs on the player** (`SelfProbe.lua`, `/sab self on`; seen in game on a mob's Poison, 744): out of combat the
  player's harmful auras are fully readable through `GetUnitAuras`, `GetAuraDataByIndex` and `GetDebuffDataByIndex`
  (name, spellId, duration, expirationTime, dispelName), and `GetAuraDuration` returns a userdata whose
  `GetRemainingDuration`/`GetTotalDuration`/`GetElapsedDuration` answer. In combat all three lookups throw "Auras
  cannot be accessed when secret while tainted", and `UNIT_AURA`'s `addedAuras` is secret (the payload itself is
  not). `UNIT_COMBAT` on the player always has a secret amount but a readable action, flag and school, in combat and
  out: the poison's ticks were school 8 every 3 seconds, the mob's swings school 1. A mob's DoT description has no
  number ("Inflicts Nature damage to an enemy every 3 sec. for 30 sec."; Infected Wound's was nil).
- **Regeneration:** on Forever energy and mana refill continuously rather than in 2-second ticks, so the gallery's
  scenarios draw them that way (`gallery.py`, `regen`).
- **The five-second rule** (`ManaRule.lua`): mana is secret, so the wait is timed from `UNIT_SPELLCAST_SUCCEEDED`
  and `C_Spell.GetSpellPowerCost`, read at `UNIT_SPELLCAST_SENT`. In game the build-up ran on spells that cost mana,
  but what Forever answers for a free cast (Clearcasting) and when a channel's wait should start are not confirmed;
  `/sab mana` lists what it saw. A ripple's kick reaches the small bars' wave limit even at a quarter of its strength,
  so the build-up turns kicks off entirely (`Liquid:SetSteady`) rather than scaling them down.
- **Class Color by unit** (`Themes.UnitColor`): Forever's docs mark `UnitClass` `SecretWhenUnitIdentityRestricted`, so
  a target's class is read under `pcall` with a secret check, and a bar that gets no answer takes the game's colour.
  Not yet tried in game on other players or in instances.
- **Small frames** (`Bars.lua`, `SPOTS` with `frame`): the pet's bars are globals (`PetFrameHealthBar`) with masks
  named after them; the focus is the target's template; each target of target is `TargetFrameToT`/`FocusFrameToT`
  (`.HealthBar`, `.ManaBar`, masks on the bar). No unit events fire for `targettarget`/`focustarget`, so their
  liquid is refreshed on `UNIT_TARGET` and never stirred. Not yet seen in game.
- **Enemy nameplates** (`Bars.lua`, `plateHealth`, off by default): Forever's plates are `Blizzard_NamePlates`
  (`forever` branch). The game pools the plates' unit frames: `NamePlateBaseMixin:AcquireUnitFrame` sets
  `plate.UnitFrame` and `plate.unitToken` on `NAME_PLATE_UNIT_ADDED` (perhaps after our handler), and the release
  sets `UnitFrame` to nil, so one health bar (`UnitFrame.HealthBarsContainer.healthBar`) shows mob after mob. The
  liquid is built once per bar and follows its unit, waits for the unit frame, and gives the game's fill back on
  removal before the bar is reused. The bar has no mask, so the clip frame is the bar itself. Forbidden plates
  (`FORBIDDEN_NAME_PLATE_*`, friendly plates in instances) are never handed to addons. At most `MAX_PLATES` (15)
  have the liquid, idling at 20 fps. Friendly plates (`plateFriendly`) are a side of their own (`Side`: by
  `UnitCanAttack`, never the player's own plate, nothing when the answer is secret) with their own cap
  (`MAX_FRIENDLY`, 10), so a city cannot take the enemies' slots; the DoT marker gets enemy plates only. Not yet
  seen in game: friendly plates, and what colour Forever gives other players' plates. On a plate (10 px, half a
  unit frame bar) the swirl texture (64 px a repeat) shows as a thin slice, so veins and lightning show less than on
  the unit frames. Drawing them at half size and brighter, with more lightning, was tried in game and the plain look
  was preferred, so plates draw the liquid exactly as the unit frames do. The game darkens every plate but the target's
  (`deselectedOverlay`, the bar's OVERLAY layer, likely over the liquid as the text is; not checked); that is
  the game's frame, so it stays. `/sab perf` times the updates with `debugprofilestop`, unit frames and plates
  apart; the mock's numbers are mostly the mock's own cost, so only the game's say anything. Addons cannot write
  files, so each `/sab perf` is kept in `SmoothAnimatedBarsDB.perfLog` (last 50), which the client writes on
  `/reload`; `tools/perf_report.py` turns the newest saved file under Forever's WTF folder into
  `perf/perf_report.txt` (git-ignored). The DoT marker on plates (`plateDots`, needs `plateHealth`): `Dots.lua`
  keeps DoTs per mob, so `Dots.Unit(token)` reads a plate's; `Marker.lua` builds a marker per plate bar the first
  time its mob carries the player's DoTs (from `Bars.Plates()`), with no kill icon and no model skulls, and a DoT
  landing there shows as more damage to come (Dots says "applied" only for the target). Seen in game: the marker
  works on plates, but a bleed (Blood theme) did not show against a hostile plate's red, so plates take a dark
  crimson (`PLATE_LOOKS`; lighter blood looked pink in game). Not yet seen in game:
  the plate's size and colour (`GetStatusBarColor`) being readable, the liquid under the plate's text and
  deselected overlay, and the cost in a crowd.
- **Unit frame menus** (`Options.lua`, `AddToUnitMenus`): `Menu.ModifyMenu("MENU_UNIT_" .. which, ...)` adds Open
  Settings; the frames pass themselves as `contextData.ownerFrame` (Mainline `PlayerFrame.lua`, `TargetFrame.lua`,
  `PetFrame.lua`), which tells them from chat names and party frames. Seen in game, and the menus' protected actions
  (Set Focus, Target Marker Icon) still work with it, in and out of combat.
- **Toc changes** (a new file) need a full game restart; `/reload` does not pick them up.
- **Capture:** `/sab capture` uses `Screenshot()` and the `screenshotFormat` CVar (TGA, put back after).
  The screenshot is the full render resolution (an ultrawide 3440x1440 here), and the red "?" target
  portrait once fooled the marker search, which now looks only at the top of the screen. The game's tooltip
  (bottom right, if the mouse rests on a mob) once landed in the grid's last cell, the kill icon, so
  `capture_art.py` keeps only the portrait's area of that cell (`KEEP`).

## Dev setup

`_forever_\Interface\AddOns\SmoothAnimatedBars` is a junction to this repo's `SmoothAnimatedBars/`, so
`/reload` loads the working copy. Settings are account-wide in `SmoothAnimatedBarsDB`; `setupDone` marks
that the setup wizard has run. The tools need `tools/venv` (`pip install lupa numpy pillow`).
