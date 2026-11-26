# Smooth Animated Bars

World of Warcraft addon for **WoW Forever only** (`## Interface: 16001`): the liquid from Smooth Experience
Bar (`../smooth-experience-bar`) in the game's player and target frame health and power bars. The README is
for players; `docs/DEVELOPMENT.md` covers the layout and tools; this file holds the rules.

## Rules

- **Secret values:** Forever keeps health and power secret from addons, in and out of combat (`UnitHealth`,
  `UnitPower`, the bars' `GetValue`). Never compare them or do arithmetic on them. Hand them to widgets
  (`StatusBar:SetValue`) and anchor to what the client lays out; `Bars.lua` explains the design.
- **Game frames:** only read and draw on them. No hooks, no fields written onto them, no changes besides the
  fill texture's alpha. Our frames sit at the bar's own frame level so the game's text stays on top, except on
  nameplates (see Enemy nameplates below) and a health liquid with the DoT marker on it (see DoT tracking). One
  exception, asked for: while a player or target bar height is not the game's (see Taller bars), a frame of ours is
  drawn in place of the game's, and the game's pieces it redraws are faded (alpha 0) meanwhile and given their alpha
  back after. Nothing is ever drawn over or faded at the game's heights.
- **Forever assets:** game files by path often fail to load there. Use `SetColorTexture` for solid fills and
  the addon's own TGAs in `SmoothAnimatedBars/Media/` (made by `tools/make_media.py`), never `Interface\...`
  game paths. Icons by file ID.
- **Settings:** every setting is in the editor (`Editor.lua`, `FRAMES` and `TABS`), a window of ours with live examples,
  opened by `/sab`, the unit frame menus and Open Editor on the settings page. A new setting needs a control there;
  the tests check every setting has one. The settings page is a landing page, a canvas category built at login
  (`Options.lua`); every setting is still registered with the game (`Settings.RegisterAddOnSetting`, no rows) and
  changed through it (`Core.SetSetting`). Never register initializers into the game's vertical layout lists: on
  Forever that taints the Social page. `tools/harness/editor_shot.py` draws the editor's layout. One exception to
  registering: a bar's own effects (the profile's `effects[barKey][effect]`, `Core.SetEffect`), a nested table
  the Settings API cannot hold, read by each bar's liquids and markers (`b.opts`, filled by `Bars.FillEffects` whenever an effect changes).
  Two effects are amounts, not switches (`Core.EFFECT_LEVELS`, asked for): Animation Speed (`animationSpeed`, 25 to
  200%, `opts.speed`) scales the liquid's own clock in `Liquid:Update`, while the fill speed and lean stay in real time
  as the edge follows the game's bar; Wave Intensity (`waveIntensity`, 0 to 200%, `opts.intensity`) scales what
  `FrontOffset` returns and the body's cut behind it, so ripples, slosh, lean and wobble grow together (the simulation
  itself is unchanged). Both are percentages, held to their range when read (`Core.EffectLevel`). From two reviews: the
  settings' clean-up (`Clean`) kept only true or false in a bar's own effects, so its levels were lost at every login
  and profile change (now kept as numbers in range); a follower's (the fury's) own tremble is scaled too, or at 0% it
  shook over a flat bar past its body's cut; the tips' glow from a slice's speed is scaled. Accepted: below 100% speed
  a stirred liquid takes longer to go quiet, so stays at full rate longer (cost); at 200% a dent reached 6.2, past the
  markers' `OVERLAP` of 6, opening a gap behind a DoT or heal liquid for a frame now and then (13 of 9000 slice-frames
  measured; `OVERLAP` left as seen in game).
- **Lua's 200 locals:** `Bars.lua`'s main chunk is at the limit; one more file-level `local` fails to load in game
  ("main function has more than 200 local variables", seen). Put new functions on a table (`Bars.X`) instead.
- **Tests:** run `tools/venv/Scripts/python tools/harness/test.py SmoothAnimatedBars` before every commit; it
  exits 1 on any failed check. The mock (`tools/harness/wowmock.lua`) should be as strict as the client:
  when the client rejects something the mock accepted, make the mock reject it too.
- **Speed changes:** a change made to cost less must not change the look (asked for). Measure it with
  `tools/harness/bench.py --ref HEAD` (widget calls and the addon's Lua work, the same frames before and after) and check
  it with `tools/harness/samelook.py --ref HEAD`, which must pass (every texture the same each frame, colours within half
  an 8-bit step). Both are repeatable: a fixed random seed, and `pairs` in a fixed order (`samelook.STABLE_PAIRS`), as
  table addresses, and so the order the liquids took their random numbers in, differed from run to run.
- **Visual changes:** render a preview (`tools/harness/preview.py`) and look at it. Rebuild the gallery
  (`tools/harness/gallery.py`) when the liquid's look changes, and look at it before committing.
- **Gallery:** `branding/gallery/` holds the README's images: animated WebP for each scenario (`hero`,
  `mage`, `rogue`, `warlock` and `rend` with the DoT marker, `priest` with the heal marker, `druid` with both, `eating`, a meal up to its buff, `mana`, the build-up to mana regenerating, `fury`, a warrior's rage building to full and spent back to 40%, `plates`, four Normal-style nameplates drawn from the captured plate art (`gallery.py`, `PLATES`), two with DoTs, and `prd`, a warrior's Personal Resource Display through a fight to furious rage and a bandage, on the same plate art, its bar sizes Edit Mode's defaults as guessed, and `party`, four party members stacked as in game, on the party art with the setup's example party and its class icons for portraits; the power mask and bar are shifted
  1.5 right and 1.9 down there (`gallery.py`, `PARTY_POWER_SHIFT`): at Forever's own offsets they sat over the gold divider in the captured art, though in
  game the game's fill does not, so the gallery was tuned by eye to sit in the slot; the example party in the setup and the editor (`Preview.lua`, `PARTY_POWER_SHIFT`) showed the same in game and takes the same shift, the capture keeping the game's offsets), and `raid`, a ten-player raid through a pull in two groups of raid-style frames, on the raid frame art (`gallery.py`, `RAIDERS`), its tank targeted, and `shield`, a priest's Power Word: Shield soaking five hits and shattering, no Weakened Soul (asked for; not made by
  `gallery.py`: the mock cannot lay the shield out from the secret absorb, so it was composited from the gallery's own
  player frame with the real `Shield.lua` and `Soul.lua` rendered where the client would place them, as the shield's
  previews were; render it that way again if either changes), and `tall`, a mage's player frame with its bars grown to
  the sliders' tallest (40 and 20), shrunk to the game's 20 and 10 and settled in the middle, looping (`gallery.py`,
  `TALL_KEYS`): the art is the addon's own slicing (`Preview.SetFrameTall` on a `LiveFrame`) of the captured art, the
  captured masks stretched as `TallSpec` stretches them, the level circle moved with the ring (the mock's circle atlas
  has no real size), and the liquid the addon's in the game's bars resized to match, and PNG stills (`frames.png`, `themes.png`), at full
  quality (`K = 3.0`, 20 fps). No GIFs.
  A full run takes about a quarter of an hour, so run it in the background.
- **Frame art:** `branding/art/` is Forever's own unit frame art, captured in game with `/sab capture` and
  cut out by `tools/capture_art.py` (`/sab capture plates` and `--plates` for the nameplates' pieces, `/sab capture
  party` and `--party` for the party member frame's: its art, bar masks and four class portraits, `/sab capture raid` and `--raid` for the raid-style frame's atlases: its background, the power bar's, the target's highlight and a group's border). It is only for the gallery and is never packaged. The layout numbers
  live in `Preview.lua` (`LAYOUT`) and are repeated in `gallery.py`; change both together.
- **Commits:** stage the files you changed by name, never `git add -A`. Commit messages are plain and
  professional.
- **Changelog:** add player-facing notes to `CHANGELOG.md` under the next version as features land
  (`### New`, `### Fixed`, no internal changes).

## Release

Every release, before tagging:

1. Check that the `CHANGELOG.md` section for the version is complete and written for players:
   `## X.Y.Z` with `### New` and `### Fixed`. `bash scripts/changelog.sh X.Y.Z` prints what the release
   will use. The same section is the in-game changelog (`WhatsNew.lua`, as Road to Sixty's): every player sees
   it in a window after updating, so every release needs one and each note must read well on its own. Nothing
   else is updated by hand: `scripts/package.ps1` writes `WhatsNewData.lua` from `CHANGELOG.md`
   (`tools/whatsnew_data.py`), prints "WhatsNewData.lua: N versions, newest X.Y.Z" (the newest must be this
   version), and fails if the version has no section. That file is not committed.
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
  The school stays readable, so (as DoesItDie 0.9.1 to 0.9.4 does; ported here) a hit is matched to a DoT's tick by
  school and timing alone (`onHiddenAmountHit`), bleeds kept on their cast's schedule so white swings can't pull them
  early; a DoT that never ticks is dropped, but only on a mob whose hits have shown their school (`schoolHitAt`;
  DoesItDie drops on any mob in view). The tooltip's numbers leave out spell and attack power, so after combat the
  damage meter's per-spell totals (`C_DamageMeter`, readable then; seen in game by DoesItDie on a warlock) teach each
  DoT's real tick (`learnFromMeter`), blended by tick count. The meter counts every tick and the tally only those seen,
  so a fight is not learned from where a DoT ticked out of sight (`Dots.LoseSight`: tabbed away, its plate gone while
  the mob lived), a finisher's points were unknown, or the addon loaded mid-fight (a review found the first saved 1.7
  times the real tick). Still inherited from DoesItDie: any hit of the school near a tick is taken for it, the
  player's own Mind Flay or Drain Life too. Not yet seen here in game: any of the ported part. The
  hit's flag is readable, though (seen in game: `BLOCK_REDUCED`, and a crit
  made a Rend gush), so a crit on the target makes a bleed gush; it does not say whose hit it was. `/sab dots` counts what the target's hits show (`Dots.lua`, `noteFlag`). The player's `UNIT_SPELLCAST_*` events and spell descriptions are readable. DoesItDie reports (not verified here) that
  creature GUIDs are secret in instances, so mobs there are keyed by their nameplate. The
  marker and kill icon (`Marker.lua`) leave every comparison with health to StatusBars, as the liquid does.
  The marker is up to two DoT liquids, one per school (oldest at the front), drawn 10 and 5 sublevels under
  the health liquid (`Liquid:SetSublevelOffset`; Liquid.lua uses sublevels 3 to 7 of -8..7, so there is no
  room for a third), and the health liquid's front is moved onto where the health will end (`Bars.Front`). Those
  sublevels order the DoT liquids, which share a clip frame, but not the health liquid, in frames of its own: at the
  bar's level with the marker, the health's front sometimes lay under a DoT liquid's straight cut (seen in game on the
  target frame, one DoT right and the next wrong, as on plates before). So while a marker is live on a bar
  (`Bars.SetOver`, from `Marker.Apply`) its health liquid is one level up, with copies of the bar's texts
  (`TextString`/`LeftText`/`RightText`, put on the bar by `SetBarText`) one more up (`Bars.lua`, `Over`); on another
  addon's target bar the liquid goes one past its `level`. The target's heal prediction and absorb bars are child
  frames one level up too, so they now tie with the liquid's front. Seen in game on the target frame: the front over
  the DoTs every time. Not yet seen: other addons' target bars. Reported by a player: Health Bar Text Forever
  (github.com/Pirson-s-Addons/HealthBarTextForever) puts its own texts on the target's health bar
  (`bar:CreateFontString`) and fades the game's to alpha 0, so under the raised liquid its text was hidden and the copies
  of the game's showed nothing. Every other FontString on a raised bar is copied too (`Bars.CopyOtherTexts`); seen in game
  with that addon: working. The kill icon is the
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
  `Locale_ruRU.lua` lists ASCII bytes. The poison coatings, traps and Weakened Soul's "absorb" still read English
  only. `/sab dots` logs `NOT READ` for non-English text nothing read.
  Heals, food and drink (`Heals.lua`, `readHeal`/`readRest`) go the same way: English first, then each language's
  readers, built from its wording by `Locale.lua`'s `L.healReader` (the addon's own, not DoesItDie's). Checked the same
  way, against Forever's text for the lowest and highest rank of every class heal, bandages, food and drink in every
  language, each read as the English of the same spell (`tools/harness/heal_language_cases.json`, 1160 cases). That
  check found English missing Greater Heal ("A slow casting spell that heals..."), Prayer of Healing and Desperate
  Prayer, and a food's buff worded "If you eat for 10 seconds"; all read now. Tranquility ("every 2 sec") and food
  restoring a share of health are read in no language. `/sab heals` logs `UNREAD` for non-English text with a number
  that nothing read. Not tried on any non-English client. A review found the first readers, which looked for a health
  word anywhere, taking spells that cost, drain or convert health for heals over time on the caster (Bloodrage, Last
  Stand, Rend's "perd 147 points de vie en 21 sec", Devouring Plague in every language, Lightwell): each language's
  heal patterns are now anchored at the text's start, as English's are, and the cases include 609 readings of 75
  spells that are no heal (damage over time, drains, costs, buffs, potions), each read as English reads it. Potions
  and Holy Strength's proc still read as a direct heal in some languages; instant, they show nothing.
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
  transparent while the heal marker shows. The other one (heals from others) is taken over too, see Other players'
  heals.
- **Other players' heals** (`HealMarker.lua`, `m.others`, asked for): Forever's heal prediction calculator, filled with
  `UnitGetDetailedHealPrediction(unit, "player", calc)`, gives `GetIncomingHeals()` as amount, amountFromHealer,
  amountFromOthers, clamped, all secret (the calculator's own docs). amountFromOthers lays out a hidden StatusBar after
  the player's own heals (`OTHERS_LINGER` after the game's bar goes, the run eased to nothing). Being secret it cannot
  say whether anything is coming, so the liquid shows while the game shows its own bar for others' heals
  (`OtherHealPredictionBar` on the player and party frames, the `otherHealPrediction` texture on raid-style frames and
  the Personal Resource Display, hidden by the game at nothing: `CompactUnitFrameUtil_UpdateFillBar`, Mainline
  `UnitFrameHealPredictionBars_Update`); a secret answer fades the liquid by it (`SetAlphaFromBoolean`). That bar's fill
  is transparent meanwhile, so the game's predictions are all ours while the marker shows. In Forever's code the
  prediction is `UnitGetIncomingHeals`, which in the modern client counts heals being cast, not heals over time; not
  yet seen in game what Forever counts. Drawn under the player's heal liquids: BORDER 3..7 on unit frames
  (`OTHERS_LAYERS`; their ARTWORK sublevels are spent), with a seam of the nearest front before it; BACKGROUND 1..5 on
  raid-style frames (`OTHERS_RAID_LAYERS`). A resting party or raid marker is woken by `UNIT_HEAL_PREDICTION` for its
  member. The amount is one sum, and each healer's own share (the calculator filled with that healer) is secret too,
  so neither says who heals. Their look comes from group members' heal casts (asked for: always the water look before;
  `HealMarker.lua`, `casting`, `OthersSchool`): a cast from its start to its end, kept when its text reads as a heal
  and its caster's class is a healer's (`Heals.CastSchool`, by class as the player's own), aimed at whoever
  `UnitIsUnit(caster .. "target", token)` names, or at anyone where that says nothing (click or mouseover casts, a
  secret answer). Holy or Nature where every healer casting at the unit is of that school, the shared look
  (`OTHERS_THEME`, Tidal in silvery teal) where they differ or nobody is casting (heals over time); kept while the
  liquid drains. Seen in game on raid-style frames: a paladin's heals still in the shared look. The likely cause, not
  confirmed: a spell the player does not know may have no description until the client loads it, so it never read as
  a heal; with no text, `C_Spell.IsSpellHelpful` stands in and `C_Spell.RequestLoadSpellData` asks for the text.
  `/sab heals` lists the last group casts and what was read of each (`castLog`: the spell ID or "a secret spell",
  heal / helpful / no heal / no text / not a healer, and whose target). From a review: a cast's end can be missed
  (a loading screen, the caster out of sight, a secret payload), so a cast is over `CAST_MAX` after its start, and its
  look kept `CAST_GRACE` after its end while the heal lands; with nobody casting the shared look comes back while the
  game still shows others' heals (no cast accounts for them), and stays only while the liquid drains; the player's own
  raid token is known by GUID or raid index where `UnitIsUnit` is secret; in a raid only raid tokens count (the events
  come for both); the class is asked before any spell text, and a spell's reading is kept by ID. Not yet seen in game:
  group heals (Prayer of Healing, Chain Heal) look right only on the caster's target, and bandages take the caster's
  class look. Not yet seen in game: whether other members'
  casts and their targets are readable there. Not yet
  seen in game: any of it, whether the game's bar's shown state is readable on each frame, and the cost. Seen in game in
  a dungeon: looks good. From a review: the amount is never truth-tested (`x and secret or y` tests it), the calculator
  is asked only while the game's bar shows, and when it gives nothing the game's bar is left showing
  (`m.othersBroken`); a woken marker that hides rests again (`Hide` clears `othersWake`), and only `player`, `partyN`
  and `raidN` events wake any. On raid-style frames the player's heal liquid's body, clouds and swirls tie with others'
  sublevels where others' pool reaches back under it (no sublevels are free there); accepted.
- **Heals on party members** (`Heals.lua`, `HealMarker.lua`, `BuildParty`; asked for on CurseForge): who a heal goes
  to comes from `UNIT_SPELLCAST_SENT`'s target name matched against `UnitName("partyN")` (alone, `Name-Realm`, or with
  UnitName's second value), or with no name from the target (`UnitIsUnit("target", "partyN")`). A member's heals are
  kept by GUID (name where it is secret), so they stay with them when the party's tokens move; a party bar whose
  member changes drops its marker at once (`Owner`). Out of combat a member's heal follows its aura
  (`C_UnitAuras.GetAuraDataBySpellName(unit, name, "HELPFUL|PLAYER")`, `RequiresNonSecretAura` in Forever's docs,
  as the player's). Markers update at the party liquids' 20 fps and show only while the bar's liquid is live; the
  game's `MyHealPredictionBar` there is hidden while they show, as on the player frame. Not yet seen in game: any of
  it, in particular the sent name for a member with a surname or from another realm, party names in an instance, and
  the aura lookup. Raid-style frames (`raidHealth`) get one too, recipients matched over raid1..40 as well, a raid unit
  that is the player counting as the player, and none in Edit Mode (its preview puts the player on every frame). Laid
  out for those frames (`HealMarker.lua`, `RAID_LAYERS`): no clip frames (drawn outside the layer sort there, see Raid
  frames), square masks to the bar and to past the health's edge, and one heal liquid in BACKGROUND 3..7, between the
  button's background (BACKGROUND 0) and the health liquid (BORDER -4..0), so no seam; there is no room for a second.
  The button's `myHealPrediction` (BORDER 5) is hidden while it shows. Not yet seen in game either. From a review: a
  member from another realm with the player's first name gets a heal sent at their Name-Realm (exact readings for
  the whole group before the loose "Name-...", and the player's only for their own realm, `GetRealmName`); the
  player's own raid unit is also known by GUID (`UnitIsUnit` is `SecretWhenUnitComparisonRestricted`); a hidden
  group marker looks nothing up while no heal goes anywhere (`Heals.Busy`), raid markers follow `Bars.raid.Rate`,
  and the aura check finds who's who once a pass (`unitMap`). Counted in the mock before those: 40 raid frames with
  ten Renews out went from about 4600 widget calls a frame to 6400. A second review: the loose "Name-..." match for a member
  had no realm guard, so in a raid a heal on an outsider with the player's first name landed on the player's own raid
  unit (a member UnitName gives no realm for is now from the player's realm, and loose matches only where
  `GetRealmName` cannot be read); a secret sent name is kept for nobody; a member out of sight (`UnitIsVisible`) keeps
  a heal whose aura reads as gone; an idle group marker stops before any widget call, and an owner change on a hidden
  marker no longer hides it again (that cleared a heal's splash just landed); `TryBuildGroup` guards both callers.
  Forever's Chinese battleground bandages say 回复, not 恢复 (now in the cases, 1160).
  Reported by a player: Holy Light rank 8 (1177 to 1309, the first rank over 999) showed nothing while the lower ranks
  worked. Likely the client writes English amounts with thousands separators ("1,177"), which Wowhead's text (and so
  the cases) leaves out; English readers now drop them (`Heals.lua` `plain`, `Dots.lua` `plainSpaces`; Korean and
  Chinese write the comma too). A review found the other languages' heal readers had the same gap (only their DoT
  readers joined separators): German "um 1.177 bis 1.309" read as 177, a heal over time after its duration as 1, and
  food as its last three digits. `L.healReader` now joins "1.177" and "1 177" first (`Locale.lua`, `joinThousands`,
  a group of exactly three digits, as Forever's decimals have one). Not yet confirmed in game.
- **Shields** (`Shield.lua`, `shield`): Forever's player frame has the game's absorb display (`healthBar.TotalAbsorbBar`,
  a segment with `Fill` and `TiledFillOverlay`, and `OverAbsorbGlow` at the bar's end; Camelot `PlayerFrame.lua` wires
  them up). `UnitGetTotalAbsorbs` is `SecretReturns`, but the game's heal prediction calculator
  (`CreateUnitHealPredictionCalculator`, filled by `UnitGetDetailedHealPrediction`) gives the absorb clamped as asked
  (`SetDamageAbsorbClampMode`), secret. Seen in game (`/sab shield`, a level 6 priest): the calculator answers, and the
  game's absorb bar and glow are readable (at full health the bar hidden, the glow shown), so they say when a shield goes
  up and breaks. The shield is laid out as the DoT marker is, part of the health liquid: a hidden reverse bar from the
  health's front, fed the absorb clamped to the whole bar, gives where it starts, and the health liquid's front moves
  back there (`Bars.Front`); the shield (opaque dark-gold glass, a sheen brightening to a crescent rim on the front,
  `Strands.tga` drifting, rays, crackle, motes) fills the rest, in the marker's frames (a clip with SPILL, a pool in it).
  Four looks came before, each judged in game: a wall of light past the health's front where the game draws absorbs
  (read as an incoming heal); see-through glass over the health's end (the green showed through); added light at the
  harness's strength (washed to white in game, which draws added light several times stronger); and a golden liquid of
  its own on the marker's way, with the health liquid lifted a level over it (`Bars.SetOver`), which hid the player
  bar's text in game (the text copies the target frame gets did not show), so the shield never raises it. Judge the
  shield at the game's size (about 1.3 px a unit here), not the gallery's 3. A clip frame inside a bar-sized clipping
  frame once hid every texture the bar's mask cut (`/sab shield test` showed it); the marker's layout works. A texture has
  one alpha: `SetVertexColor`'s fourth value and `SetAlpha` set the same thing. The shield gave its layers their strength
  as a vertex alpha, then faded them in with `SetAlpha(1)`, so in game the faint sheen (0.16) drew opaque, a flat cream
  block over the glass (seen in game, both with added and with blended light; the harness had multiplied the two, so its
  renders looked right). The washed-out added light above was likely this too. Strengths now go through `SetAlpha` alone
  and the shield fades by its frame's alpha; the mock keeps one alpha per texture. Seen in game after that: the look
  right, but the body ran a few pixels past the rim's crescent in a straight cut, and nothing tied the shield to the
  health liquid. So the body is cut on the crescent by a mask of its own (`ShieldEdge.tga`, `EDGE_SPAN` rims wide,
  `CLAMPTOBLACKADDITIVE`), and where the two meet the shield's light spills back over the health (`contact`), lit a
  moment after a soaked hit. Nothing left the shield either (asked
  for: light sparking out, god rays), so it sheds god rays from the rim's middle past the bar (`Beam.tga`, square so
  `SetRotation` can aim it, `shed`) and embers drift off the rim while it holds. The rays' frame is on the bar, not in
  the clip: cut to SPILL around the bar they ended in a hard box. In game the health then ended stick straight and still
  at the shield: its front's waves lay under the opaque glass. A band of glass clouding over before the body came
  next, in colours of its own (the glass's, then the body's average with its strands, measured on a render): in game
  each showed as a strip with a step where the body began, the body's colour there never quite the band's. So the
  whole body, every layer, fades in from `LEAD` back over the health's end over `FADE_W` by a mask of its own
  (`fadeIn`, `ShieldFade.tga`, `FADE_SPAN` fades wide, a third mask on each body texture after the bar's and the
  edge's), with nothing of its own colour to match, the spill swelling to it and fading out across it
  (`spillOut`), in a frame of its own (`glow`) that breathes. The health liquid's front
  is on the shield's start itself: set `LEAD` past it, it ran past the real health as a shield drained, and at full
  health the whole liquid slid right, a gap at the bar's left end (seen in game). The shield laps at it now and then
  (`Bars.Lap`, `Liquid:Nudge`: a ripple with no splash), a soaked hit harder; at 45 every 0.8 s the health kept
  sloshing when idle (seen in game), now 10 every 1.8 s, felt better in game. A mirrored crescent once stood where the
  glass turns opaque, the barrier's back face: in game a stray C beside the health, so it is gone. How a shield ends (asked for: something really cool): however it goes, broken, run out or taken off, it
  shatters (`SHATTER`: the glass strains with glowing cracks, whitening and a tremble, then flashes white in its
  own shape and bursts into shards, `Shard.tga`, and streaks, with a shockwave off the rim, `blast`, and a splash
  in the health). A shield that ran out or was taken off once dissolved instead (the glass brightening, then
  fading out among rising lights; a slow fade before that was a muddy smear): not liked, so every ending
  shatters. Either way the glass holds its last place: a
  second hidden bar (`ghost`, `hold`) is fed as the run is and stops being fed when it ends, while the run drains
  and the health flows up beneath (faded while the health was still flowing up, the empty bar showed between them
  in game), the run measured from the rim while the glass shows (`RunInset`, `m.inset`): let through to the health's
  front, the last `RIM_INSET` units of green showed past the rim the moment the shield broke. Render the endings
  as the game runs them (the run easing to nothing, the glass its last size back from the health's front, which the
  breaking hit moves) and look at them frame by frame: a render that dropped the shield in one frame hid all this. What bursts or rises is spawned along a whole bar back from the rim and cut to the shield by a mask of
  the fade-in's shape SPILL taller (`burstFade`), so a bigger shield throws more; cut by the pool instead, the shards
  ended in a hard line. `Crystal.tga` (an ice shard clear in its middle) drew as faint outlines, hence `Shard.tga`; a
  flash of its own over the shield was a hard-edged box, hence the glass whitening itself. A heal cast on yourself with a shield up painted green over the
  shield: the heal marker's seam (`HealMarker.lua`) lays the health's colour on the health's edge, where the health
  liquid's front no longer is. While the front is moved (`Bars.Moved`) the heal marker lies side by side from the
  health's edge, past the shield, with no seam. Not yet seen in game: the endings, and
  `ABSORB` on the player (the rim's flare on a soaked hit).
- **Weakened Soul** (`Soul.lua`, `weakenedSoul`; Forever's tooltip: 15 s, Power Word: Shield 30 s): auras are secret in
  combat, so the wait is timed from a shield going up (`Shield.Exists`, the game's absorb display), unless the player's
  own cast of another spell whose description says "absorb" went off within `ATTRIBUTE` (English only); out of combat
  the debuff itself is read, which starts, corrects or ends the wait. Where the absorb display is secret, the player's
  own shield sent at themselves (`UNIT_SPELLCAST_SENT`'s target) starts it. Drawn on the health liquid's own front
  (`Bars.Mover`) and the health's edge (`Bars.Edge`), so it follows the client's layout; while a shield holds, in its
  glass (`Shield.State().mover`). Chosen from four mockups (ash, a healing crack, a ghost of the glass, a sigil) and
  refined in mockups: ash over the breaking glass was a grey block, so it waits for the burst; a ring at the release
  read as generic, hence the crescent. Its textures are all below OVERLAY sublevel 0, as the shield's: the bar's texts are
  OVERLAY 1 at the same level. In combat any absorb going up that is not the player's own cast (a Voidwalker's
  Sacrifice, an item) is taken for Power Word: Shield until the debuff can be read; a shield landing on one already up
  is missed. Out of combat a debuff read as gone ends only a wait it was once read in (as `Heals.lua`). Where the absorb
  display is secret, both files take the player's own shield on themselves from `UNIT_SPELLCAST_SENT`'s target against
  `UnitName("player")`; what Forever sends there for a character with a surname is not yet seen. Neither the shield nor
  Weakened Soul is drawn on other addons' player bars (Frames Forever and ClassicUI Forever fade the game's frame out,
  so both stay hidden there): not built yet. `/sab soul test` plays it with no shield. Seen in game and liked: the look.
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
- **Rage fury** (`Bars.lua`, `Fury`): a liquid can react to how full a bar is without the addon learning it.
  `UnitPowerPercent(unit, nil, false, curve)` evaluates a `C_CurveUtil.CreateCurve()` on the unit's share of its power
  (0 to 1) and returns a secret, which `SetAlpha` takes (Forever's docs: `SecretArguments = "AllowedWhenTainted"`).
  GlowingBars fades its glows this way. The fury is a second liquid over the rage bar's, its front the bar liquid's
  (`Liquid:Follow`), in a child frame of the mover whose alpha is the curve's. A burst on a rage spend shows the
  alpha from 0.3 s before (secrets can be kept, only not compared). Seen in game and liked: the fury fading in with the
  rage, drawn over the bar's liquid. The fury's burst showed nothing below half rage (its frame is faded out there), so
  every spend also throws sparks off the bar's own liquid. Not yet measured: the cost (`/sab perf`).
- **Class Color by unit** (`Themes.UnitColor`): Forever's docs mark `UnitClass` `SecretWhenUnitIdentityRestricted`, so
  a target's class is read under `pcall` with a secret check, and a bar that gets no answer takes the game's colour.
  Not yet tried in game on other players or in instances.
- **Small frames** (`Bars.lua`, `SPOTS` with `frame`): the pet's bars are globals (`PetFrameHealthBar`) with masks
  named after them; the focus is the target's template; each target of target is `TargetFrameToT`/`FocusFrameToT`
  (`.HealthBar`, `.ManaBar`, masks on the bar). No unit events fire for `targettarget`/`focustarget`, so their
  liquid is refreshed on `UNIT_TARGET` and never stirred. Not yet seen in game.
- **Party frames** (`Bars.lua`, `AddPartySpots`; `/sab party` reports what the game shows, saved in
  `SmoothAnimatedBarsDB.partyProbe` for `/reload`): `PartyFrame` (`Blizzard_UnitFrame/Shared/PartyFrame.lua`) pools four
  `PartyMemberFrameTemplate` buttons and on each show releases and re-acquires them as `MemberFrame1..4`, so a bar can
  land in another place: each bar gets a spot of its own when first found. Health is
  `HealthBarContainer.HealthBar` (mask on the container), power `ManaBar` (mask on the bar), 70x10 and 74x7. The game
  puts the unit on each bar (`bar.unit`, party1..4), which the liquid follows. Seen in game with `/sab party`, in
  Stormwind and in the Stockade in combat: health, power and `UnitHealthMax` secret, sizes, masks and the fill's alpha
  readable, class and power type readable (in a dungeon in combat too), `UNIT_HEALTH`/`UNIT_POWER_UPDATE` fire for
  the party units (power many times a second). Each health bar has the game's `MyHealPredictionBar`,
  `OtherHealPredictionBar`, `HealAbsorbBar` and `TotalAbsorbBar` (child frames, a level above the liquid) and
  `TempMaxHealthLoss`. They are left showing: they lie on the fill's front and tell of heals and shields the addon does
  not track for party members (on the player frame the heal marker shows the same heals, so the game's is hidden
  there); how they draw against the liquid is not yet seen. The game makes the member frames when `PartyFrame` first
  shows (`PartyFrameMixin:OnShow`), which can come after `GROUP_ROSTER_UPDATE` or with no group change (Edit Mode), so
  while a wanted party bar is missing they are looked for every second out of combat (`LookForParty`). A member's
  colour is read again with the half-second online check, and a hidden party bar (perhaps left on `player` by Edit
  Mode's preview) is never stirred. Whether a member is online is asked of the member frame's unit, as the game's
  `UpdateOnlineStatus` does: in a vehicle the bar shows `partypetN`. An empty slot's
  unit answers `UnitIsConnected` false, and while a member is offline the game's grey bar is given back. Raid-style
  party frames (`CompactPartyFrameMember1..5`, CompactUnitFrames) are another matter: no masks, and their colour and
  fill alpha secret even out of combat. The party pets' bars (`PetFrame.HealthBar`, no mask) and the fury on a party
  member's rage are left out for now. Liquid on the party bars not yet seen in game.
- **Raid frames** (`Bars.lua`, `Bars.raid`, `raidHealth`, off by default; `/sab raid` reports them, saved in
  `SmoothAnimatedBarsDB.raidProbe`, and `/sab raid test [low|up|off]` lays magenta blocks on their health bars): raid
  frames, raid-style party frames, pets and main tanks are all `CompactUnitFrameTemplate` (`Blizzard_UnitFrame/Shared`),
  named `CompactPartyFrameMember1..5`, `CompactRaidGroup1..8Member1..5` (groups kept apart) and `CompactRaidFrame1..N`
  (combined, made on demand, handed between units). Their settings are CVars (`raidFramesDisplayClassColor`,
  `raidFramesHealthBarColor` as AARRGGBB hex, `raidFramesHealthText`, power bars, dispel overlay...) and Edit Mode
  (size 72..144 x 36..72, groups, sort, opacity). Seen in Edit Mode's preview (every frame on `player`): health bar
  96x42 at 1,1 in a 98x44 button, no mask, at the button's level; colour, fill alpha, frame alpha (range fade) and
  `UnitInRange` secret, `GetEffectiveAlpha` refused (RequiresScriptObjectAlphaAccess); the name, health text, role icon
  and aggro border are ARTWORK 0 on the button, heal prediction and shields BORDER 5-6, absorbs ARTWORK 1-2, target
  highlight OVERLAY 0. With the test blocks: at the same level the client sorts both frames' textures by layer
  together (an ARTWORK 3 block hid the role icons, one level up hid the names too, a BORDER 1 block hid nothing of the
  game's); text drew over the ARTWORK block. So the raid liquid is in BORDER (`Liquid:SetLayerMap`, `Bars.raid.LAYERS`),
  at the bar's level. The first build cut it to the bar with a clip frame (`SetClipsChildren`), and in game in a party
  with raid-style frames every bar showed black at 100%: the fill hidden, the button's dark background over the liquid.
  A clipping frame seems to be drawn outside the layer sorting (likely also why a plate's background drew over its
  liquid at the bar's level). So it is cut by a square mask of our own (`Square.tga`, `Bars.raid.MASK`), motes too (the
  frames touch), and its clip frame does not clip. Seen in game in a party with raid-style frames: the liquid in class
  colours, names, health text and the target's highlight over it. Its colour is worked out from those CVars and
  the class (`Bars.raid.Color`), and only a secret class falls back to the bar's secret colour on a `MOD` tint. Power
  (`raidPower`, `Bars.raid.KINDS`) is the same on `powerBar`: 8 px under the health (which shrinks by that), a frame of
  its own at level 5 with its background on it, shown by the game for everyone or healers only; its colour is the power
  type's. At the party's 20 fps the raid-style party looked steppier than the player frame (seen in game), so the rate
  follows how many raid liquids show (`Bars.raid.RATES`): up to 10 at 30 fps stirring every 0.4 s, up to 20 at the
  party's 20, more at 15. Reported twice (a player, and seen here once): the player's own raid frame black until a
  `/reload`, the game's fill hidden and no liquid drawn. Seen again after joining a party in combat (the bar's
  own line was not in the screenshots; `0x16` there is only the template size of power bars the game never shows). Likely
  cause, not proven: a health bar's size comes from its anchors alone, 0 x 0 while alone (when it is built on), and the game
  anchors it by the temporary max health loss (`UnitFrame.lua`, `TempMaxHealthLossMixin`), whose event
  `UNIT_MAX_HEALTH_MODIFIERS_CHANGED` is `SecretPayloads`; `GetWidth` is `SecretWhenAnchoringSecret`. The player's own hidden
  frame gets that event while alone, before any size was known, so the liquid was never drawn though the fill was hidden.
  Whether the game's next plain anchor (`CompactUnitFrame_UpdateAll`) clears the secret is not known. Such a bar now takes
  its button's size (`Bars.raid.SizeOf`; with that secret too, the size last known, from a review), and any bar with no size
  shows the game's fill. Seen in game after the fix: invited to a group
  in combat, no black frame (once; the bug never came every time, so not proven). Bars built while alone had 6 slices (built at height 1) and now have
  the intended 15, 252 textures instead of 171: the cost is not measured in game. `/sab raid` lists, under every frame's bars, our liquid's
  state (`Bars.raid.Ours`: live, unit, sight, clip, fill alpha, our value, front, clock, textures shown, colour and
  tint) and the heal marker's on it (`HealMarker.DebugBar`), and the player's own frames in chat as well; two reports
  a few seconds apart show whether its clock still moves. Not yet seen in game: the dispel overlay (not among the button's textures), heal prediction and aggro over the liquid, a
  secret class's tint, a full raid's frames and its cost.
- **Enemy nameplates** (`Bars.lua`, `plateHealth`, off by default): Forever's plates are `Blizzard_NamePlates`
  (`forever` branch). The game pools the plates' unit frames: `NamePlateBaseMixin:AcquireUnitFrame` sets
  `plate.UnitFrame` and `plate.unitToken` on `NAME_PLATE_UNIT_ADDED` (perhaps after our handler), and the release
  sets `UnitFrame` to nil, so one health bar (`UnitFrame.HealthBarsContainer.healthBar`) shows mob after mob. The
  liquid is built once per bar and follows its unit, waits for the unit frame, and gives the game's fill back on
  removal before the bar is reused. The bar has no mask, so the clip frame is the bar itself, and the liquid takes a mask of the addon's own, `PlateMask.tga` (`make_media.py`), the shape of the game's fill with its cut corners: square, it covered the bronze rim's corners. The plate's DoT liquids take it too (`Bars.PlateMask`).
  Forever's plates are its own (`Blizzard_NamePlates/Camelot/*`, loaded instead of the shared files): a bronze bar background (`UI-HUD-CoolDownManager-Bar-BG`), a separate level box (`ui-hud-nameplates-levelindicator`), and a yellow glow on the target (`UI-HUD-CoolDownManager-Selected-yellow`). `/sab capture plates` and `capture_art.py --plates` capture those pieces (and the Classic style's `Nameplate-Border`); measuring a live plate's layout in game did not save, so the layout was measured on screenshots of the Normal and Large styles. Forbidden plates
  (`FORBIDDEN_NAME_PLATE_*`, friendly plates in instances) are never handed to addons. At most `MAX_PLATES` (15)
  have the liquid, idling at 20 fps. Friendly plates (`plateFriendly`) are a side of their own (`Side`: by
  `UnitCanAttack`, never the player's own plate, nothing when the answer is secret) with their own cap
  (`MAX_FRIENDLY`, 10), so a city cannot take the enemies' slots; the DoT marker gets enemy plates only. Not yet
  seen in game: friendly plates, and what colour Forever gives other players' plates. On a plate (10 px, half a
  unit frame bar) the swirl texture (64 px a repeat) shows as a thin slice, so veins and lightning show less than on
  the unit frames. Drawing them at half size and brighter, with more lightning, was tried in game and the plain look
  was preferred, so plates draw the liquid exactly as the unit frames do. The game darkens every plate but the target's
  (`deselectedOverlay`, the bar's OVERLAY layer, likely over the liquid as the text is; not checked); that is
  the game's frame, so it stays. Plate liquids sit above the bar (`RaisePlate`, `RaisePlateMarker`), the one
  exception to the frame level rule: at the bar's level the plate's background, dark inside with a shadow along its
  edges, drew over the liquid. Both were tried in game and above was much better. The levels, up from the bar: DoT
  liquids +1, health liquid +2 (at the same level the game kept no fixed order, and a DoT liquid on top showed its
  straight cut over the health's front now and then), the fill's shading +3 (`PlateShade.tga`), text copies +4.
  `PlateMask.tga` is only the fill's shape; the fade toward the top and bottom is `PlateShade`, black drawn over all
  the plate's liquids, because fading the liquids themselves let a DoT liquid under the health show through the
  health's faded edges, a brighter block behind its front (in game too, and in the gallery's render); seen in game
  and right. The plate's text inside the bar was then under the liquid (seen in game: health numbers turned on in the
  game's nameplate settings were hidden), so `Bars.lua` (`PlateTexts`) copies the bar's `Text`/`LeftText`/`RightText`,
  and the name while the game puts it inside the bar (`NamePlateSetupOptions.unitNameAnchorStyle`, InsideHealthBar for the
  Modern and Block styles; going by the name's position instead hid it for players on Block and Large plates, seen in
  game), into FontStrings of its own above the liquids and shading, every 0.1 s: text
  (secret, through `SetText`), font, colour and place; the game's are left alone. The game sizes these texts with
  `SetTextHeight(NamePlateSetupOptions.healthBarFontHeight)`, which `GetFont` does not report: copying `GetFont` drew
  the copy bigger, so in game it showed doubled over the game's (seen through the liquid's faded edge) and cut short
  ("10..."). The copies take the font object and that height, and the health texts are pinned at their justified side
  rather than laid over their text-sized box; seen in game and right. The name's copy is laid out as the game lays out
  its own (`UpdateAnchors`): between the name's left and right ends, its height left to the text, its font height set
  to its line height, and always one line (the XML's `wordwrap="false"`). Seen in game: the copy wrapped a long name
  ("Befouled Water / Elemental") once its height was free, and over the name's one-line box the wrapped line had been
  cut short instead, so the copy was wrapping all along. The cause, from Forever's API docs
  (`SimpleFontStringAPIDocumentation`): FontString has no `GetWordWrap` (its getter is `CanWordWrap`), so copying the
  wrap always failed and left the default, wrapping on; the mock had a `GetWordWrap` and now has `CanWordWrap` only.
  A player on Better Blizzard Plates (source: github.com/Bodify/BetterBlizzPlates, `forever/`) saw a second name
  behind the game's: that addon colours the name with `SetVertexColor`, scales it with `SetIgnoreParentScale`, hides it
  with `SetAlpha(0)`, and always reparents it (`RaiseNameAboveHealthBar`: two levels over the bar, level with our
  liquid and under its shading, so still copied), or to a HIGH frame with its Raise Strata option. So the copies take
  the vertex colour (the game's own name colour is one too, `CompactUnitFrame_UpdateName`), scale (not a secret one:
  `SetScale` takes it only untainted; the ignore-parent flag turned the other way around `SetScale`, as that addon
  does) and alpha, and a name on a frame in another strata or above the copies' level is not copied. Seen in game on
  the game's own plates: fine. Not yet seen with that addon; its custom font's size is still not copied (the copy takes
  the game's text height).
  The docs also mark `GetCenter`/`GetRect` `SecretWhenAnchoringSecret`, which is why going by the name's position
  failed, and `IsShown`/`IsVisible` `SecretReturnsForAspect` Shown: a secret answer is never compared, and the copy is
  faded by it with `SetAlphaFromBoolean` (allowed when tainted; `SetShown` takes a secret only when untainted).
  In a battleground the game set its plate fills' alpha from a secret, and `GetAlpha` (`SecretReturnsForAspect`
  Alpha) answered with one: comparing it to hide the fill errored on every plate (seen in game). Alphas read back
  from the game's regions are never compared when secret (`Bars.lua`, `AlphaTo`), and a secret `IsVisible` is taken
  as visible (`Visible`). The mock cannot catch these: Lua 5.1 lets `==`, `~=` and truth tests on a table through.
  With that fixed the battleground plates kept the liquid but lost the class colour the game's own bar had shown: there
  the game colours enemy players' plates by a class it keeps secret (`UnitClass` is `SecretWhenUnitIdentityRestricted`),
  so `GetStatusBarColor` answers with secrets. A colour can still be handed on: `SetVertexColor` takes secrets from
  addons. So the liquid is drawn white (grey, at `PLATE_SHADE`) and a texture tinted with the secret colour, `MOD`
  blended, multiplies it (`Bars.lua`, `PlateColor`, `plateTint`), from the bar's left edge to `TINT_PAST` past the
  health's edge, in the shading's frame under the shading. Only when the theme comes from the plate's colour
  (`fromGame`); a fixed theme keeps its own look. Seen in game in a battleground: class colours on the liquid, no errors. Putting the liquids back
  at the bar's level under the game's texts was tried again in game (the darkening of plates that are not the target,
  `deselectedOverlay`, OVERLAY, then lies over them): raised was still preferred. Seen in
  game with two DoTs (Fire and Shadow) on a raised plate, each in its own colour inside the rim. The setup's nameplate
  step shows four example plates instead of the unit frames (`Preview.CreatePlates`), built from those atlases in
  the Normal style and following the plate settings; seen in game and right.
  `/sab perf` times the updates with `debugprofilestop`, unit frames and plates
  apart, and of the unit frames the Personal Resource Display's and the party's (`PerfGroup`); the mock's times are
  mostly the mock's own cost, so only the game's say anything. What the mock can count is widget calls per frame
  (wrap the mock's Region methods), which is what costs in the client. In a party in combat the unit frames took
  4.3 ms a frame (15% at 36 fps) and 4.6 ms (25% at 55 fps) in game; counted in the mock, the eight party liquids,
  stirred all fight and so never quiet, made more calls than the player's, target's and display's together. So party
  liquids update at most 20 times a second and stir at most every 1.2 s (`PARTY_FPS`, `PARTY_STIR_EVERY`), and their
  fronts have a slice per 1.25 px of height (8 and 6 instead of 15; `Liquid.New`'s `rows`, looked the same zoomed in).
  `Liquid.lua` shows and hides its textures only when that changes (`On`, `Off`): a third of a quiet liquid's calls
  were Show and Hide on textures already so. Together a party's eight went from about 4500 calls a frame to 820 in a
  stream of events, and the player's and target's four from 2700 to 2100. `/sab perf` also lists the six costliest
  unit frame bars with their Rage Fury's share (`PerfBars`). After the party changes, in game in a party in combat at
  24 fps: party 0.2 ms a frame per liquid, the full-size bars about 0.85 ms each, the display's two 2.1 ms with its
  fury. Matched against `tools/harness/bench.py`'s call counts for the same bars, each widget call cost about 1.7 to
  2 microseconds in game. The bench then showed the fury at nearly 40% of all calls in combat: it ran at 30 fps even
  where its curve has faded it out (below half rage), which the addon cannot know. So the fury runs at 20 fps
  (`FURY_FPS`), and every liquid's front has a slice per 1.25 px of height (`Liquid.RowsFor`: 15 on 20 px health, 8 on
  10 px bars), all liquids of a height alike, their fronts matched by position (`SliceAt`) where counts differ.
  Together, by the bench, a warrior with a party of three in combat went from about 9.9 ms to 6.1. Reported by a player
  (1.14.1): 5 to 10% CPU, 15% and more at peaks, with only the player and target on and every effect up; the bench
  agreed (player and target in combat about 1350 calls, 2.6 ms, a frame at 60 fps, the same per frame at any frame
  rate as a moving liquid is drawn every frame). Asked for: cheaper, with the look unchanged. Half of those calls were
  the layers' caps (seven layers, a cap per slice, each placed, sized, given coordinates and alpha every update). Now
  (`Liquid.lua`): each cap is anchored between its layer's main texture's far end and its slice's (`AnchorCaps`; a shown
  cap always ends where its slice does) and each tip on its slice (`LayoutTips`), so the client lays them out; sizes,
  coordinates and points are set only when they change; colours and alpha once they move by half an 8-bit step
  (`COLOR_STEP`); a layer's colour goes to its textures as they are drawn, with the alpha in the same `SetVertexColor`
  (`LayerLook`); the gradients go to the body and slices only when they change (`gradStamp`). By the bench: player and
  target in combat 1349 calls a frame to 673, quiet 416 to 162, the whole set 46% fewer in combat, Lua work up about a
  tenth. `tools/harness/samelook.py` found every texture's place and coordinates the same as before to float rounding
  in every scenario, colours within half a step. Seen in game after that (the player's CPU addon, 124 fps, Bar Height
  on): 8 to 10% idle, about 20% in a fight alone; the bench, run on the player's own saved variables
  (`bench.py --saved`, every frame but the player's and target's hidden), agreed (about 880 calls, 1.7 ms, a frame in
  that fight). A third of the idle cost was asking every frame what no update needed: whether each of the ~40 bars the
  addon knows shows (hidden party bars, the game's bars faded under Bar Height) and whether each of the game's segments
  shows. So a hidden bar sleeps until our hidden bar on it gets an `OnShow` (the client runs a frame's shown
  descendants' OnShow and OnHide with it; the mock now does too), the game's bars Bar Height fades rest until it gives
  the frame back (`Bars.Sleep`, `Bars.Wake`, `Bars.Rest`; either is looked at again after `SLEEP_CHECK` in case no wake
  came), and Bar Height mirrors the segments every frame only for `SEGMENT_FOLLOW` after an event that changes them
  (`SEGMENT_EVENTS`, from Mainline `UnitFrame.lua`, listened to only while a frame is taller), else at each poll. By the
  bench on those settings at 124 fps: idle with no target 466 calls a frame to 239. In a fight the liquid's drawing is
  most of it, so Animation Frame Rate (`animationFps`, asked for as a setting; `Liquid:Due`) caps how often a moving
  liquid updates, the bars', DoT marker's and heal marker's: 850 calls a frame Unlimited, 574 at 60, 418 at 30. Its
  place on the bar is the client's every frame either way. Seen in game: the look unchanged (caps, tips, waking bars);
  `/sab perf` idle 0.30 ms a frame at 150 fps (0.41 before the sleeping bars), a 1v1 fight at 100 fps 1.4 ms Unlimited
  and 1.15 at 60, with no difference to the eye at 60, so 60 is the default (asked for). At 100 fps a cap of 60 is every
  other frame, and what runs every frame anyway stays, hence a fifth, not half. `samelook.py` runs at Unlimited, so it
  compares the drawing, not the cap. Addons cannot write
  files, so each `/sab perf` is kept in `SmoothAnimatedBarsDB.perfLog` (last 50), which the client writes on
  `/reload`; `tools/perf_report.py` turns the newest saved file under Forever's WTF folder into
  `perf/perf_report.txt` (git-ignored). The DoT marker on plates (`plateDots`, needs `plateHealth`): `Dots.lua`
  keeps DoTs per mob, so `Dots.Unit(token)` reads a plate's; `Marker.lua` builds a marker per plate bar the first
  time its mob carries the player's DoTs (from `Bars.Plates()`), with no model skulls, and its kill icon
  (`plateKillIcon`, asked for on CurseForge, issue #5) 20 tall and 7 left of the bar, clear of the target's glow,
  only 5 levels up so it does not draw over the plates beside it (seen in game and right), and a DoT
  landing there shows as more damage to come (Dots says "applied" only for the target). Seen in game: the marker
  works on plates, but a bleed (Blood theme) did not show against a hostile plate's red, and a lighter or darker bleed was
  tried. The real cause was the health: the game tints its grey fill with the plate's colour, so an enemy plate
  shows a deep red, (165, 6, 3) measured in game, while the liquid took the colour at full strength. Plate colours
  are taken at a share of the fill's brightness (`Bars.lua`, `PLATE_SHADE`), and a bleed on a plate is the target
  frame's Blood. At 65% with the unit frames' theme from a colour, a plate still looked darker than the game's in
  game: measured, its red matched (145 against 144) but white in the fill and swirl had greyed it to (145, 45, 42)
  against the game's pure (144, 0, 0). A plate's own colour now takes a deep theme (`Themes.FromColor(c, template,
  true)`): no white anywhere, its clouds and dark pockets kept to its hue (`swirlC`, `deepColor`, which `Liquid.lua`
  otherwise shifts round the wheel), lightning in its colour (`pureLight`; `EmitBolt` otherwise draws it toward
  white), no inherited particles, and a nearly flat fill along the bar, as the game's is. Several rounds of tuning
  went wrong because the plates being measured never had that theme: they followed a target on Class Color with
  Class Color on Mobs at Game Colour, and that fallback (`ThemeFor`) built the unit frames' theme. It, and Reaction
  on a mob's plate (`PlateReaction`), now take the deep theme. The bar's colour is readable in game (`1 0 0`, not
  secret). With 57% the plate looked right in game. The mock draws the added light layers fainter than the game
  (10 green against 45 in game for the same plate), so plate colours have to be judged on screenshots from the game,
  with the effects off and on.
  The fill also fades to dark over its top and bottom quarter, so the game's red sits inside the rim; `PlateShade.tga`
  darkens the liquids the same way (`make_media.py`, `PLATE_FADE`, measured on the captured fill). Not yet seen in
  game: the plate's size being readable, the liquid under the plate's
  deselected overlay, and the cost in a crowd.
- **Personal Resource Display** (`Bars.lua`, the `prd` spots, `prdHealth`/`prdPower`): on Forever it is
  `Blizzard_PersonalResourceDisplay` (forever branch, with a small `Camelot/` override), not a nameplate: one global frame,
  `PersonalResourceDisplayFrame`, parented to UIParent and placed with Edit Mode, shown when the game's option is on
  (`C_GameRules.IsPersonalResourceDisplayEnabled`, CVar `nameplateShowSelf`) or only in combat by its Edit Mode setting.
  Its bars are `HealthBarsContainer.healthBar`, `PowerBar` and `AlternatePowerBar` (a druid's mana in a form,
  `DruidAlternatePowerBarMixin`), all `PersonalResourceStatusBar`: the plates' art (`UI-HUD-CoolDownManager-Bar` on
  `-Bar-BG`), no mask, texts `TextString`/`LeftText`/`RightText`, and their sizes and the health's class colour are Edit
  Mode settings. So the spots are `flat`: they take the plates' look (`PlateMask`, `PlateShade`, raised two levels with
  copies of the texts), but keep the unit frames' motes, stirs and Rage Fury, and their theme: the bar's own colour at
  full strength, not the plates' deep one at `PLATE_SHADE`, which looked dull next to the player frame in game.
  `spot.plate` stays for what only nameplates do. A frame hidden and shown again snaps the liquid to its value
  (`UpdateBar`, `unseen`; `away` is a party member offline). The power bar's `ManaCostPredictionBar`, `FeedbackFrame`
  and `FullPowerFrame` are at or near the bar's level, so the raised liquid may cover their nearest pixels. Seen in game: it shows and fits the rim. The
  heal marker (`HealMarker.lua`, `extra`) puts a marker on each PRD bar from the same heals, shown only while that bar's
  liquid is live, one level above the bar (under the liquid two up, as the DoT marker on a plate), so it needs no seam;
  it hides the PRD's own prediction, a texture (`healthBar.myHealPrediction`). `ManaRule.lua` drives every mana bar
  (`Bars.FindAll`); the form mana's bar counts as mana whatever the power type (`spot.token`). Not yet seen in game.
  A hidden bar's liquid is not updated, so nothing is set off in one (`Bars.WaitOver`, `Bars.Release`, the fury's
  burst check `Visible`), heal flags are dropped while a marker is hidden, and a bar shown again settles
  (`Liquid:Settle`): a burst in flight when it hid would otherwise finish when it shows. Settled, it counts as quiet,
  so it is drawn at once (`drawNow`): waiting for its next idle update left an empty bar for a few frames. Every class has the
  `AlternatePowerBar`, but on Forever only a druid's is used, so only druids build one.
- **Unit frame menus** (`Options.lua`, `AddToUnitMenus`): `Menu.ModifyMenu("MENU_UNIT_" .. which, ...)` adds Open
  Editor (Open Settings before the editor), opening it at that frame's section; the frames pass themselves as `contextData.ownerFrame` (Mainline `PlayerFrame.lua`, `TargetFrame.lua`,
  `PetFrame.lua`), which tells them from chat names. The party's member frames are pooled and nameless, so they are
  told by their parent, `PartyFrame` (not yet seen in game). Seen in game, and the menus' protected actions
  (Set Focus, Target Marker Icon) still work with it, in and out of combat. But not in an instance: there a mob's
  name is secret, so the menu's title has a secret width, which the game can lay out only untainted. Anything added
  taints the layout, which errors (`FrameUtil.lua` `GetUnscaledFrameRect`, "a secret number value, while execution
  tainted by 'SmoothAnimatedBars'") and draws the menu on one line without its background (reported by players,
  error seen in game). So a menu whose unit has a secret identity (`C_Secrets.ShouldUnitIdentityBeSecret`, or a
  secret `UnitName`) is left alone; seen in game in a dungeon, the menu right again. Forever has the game's own
  controller interface (`Blizzard_Gamepad*`, `C_InputInterfaceStyle.GetCurrentStyle() == Enum.InputDeviceInterfaceType.Gamepad`).
  There a menu taking the gamepad's focus pushes its bindings, and the gamepad action bar then calls the protected
  `SetPreferredGamepadInteractTarget` (`MainActionBarFrame.lua`, `UpdateInteractIcons`). With our entries in the menu
  that ran tainted: `ADDON_ACTION_FORBIDDEN` on right-clicking the target (seen in game), and players reported the
  controller interface broken until `/reload` after inviting from it. So the menus are left alone while it is on; seen in game, no more errors.
- **Other addons' bars** (`SmoothAnimatedBars.AddBar`, the global table in `SmoothAnimatedBars.lua`; `Bars.lua`,
  `External`; README "For addon authors"): asked for by Frames Forever (Halfdays), which hides the game's frames.
  Their bars are spots with `external` (the options) in `bars`, built by `NewBar`, set live by `Bars.Apply` under one
  setting (`externalBars`) and not by our per-frame ones. The rule on game frames does not apply: the addon hands us the
  bar and agrees to its fill going transparent. Frames Forever's code (in `_forever_\Interface\AddOns\Frames_Forever`):
  its default health colour is a gradient from `UnitHealthPercent` curves, so secret, followed by the white liquid
  and a `MOD` tint as on battleground plates; its "lost health" mode is `SetReverseFill(true)` with the bar showing
  missing health, so the liquid is mirrored (`Liquid:SetMirror`); its text is three levels up. At the bar's own level the
  liquid showed dim in game: the bar's background, a texture on the bar (dark at 80%), drew over it, as a plate's did.
  So it is one level up by default (`level`); seen in game and right. Their heal prediction is a child frame one level
  up too, past the fill's edge, so only the front's waves can meet it (not yet seen). Seen in game: the liquid on
  their player bars, and their default health colour (secret) through the tint. `GetReverseFill` (the client's getter),
  the colour and the level are looked at every 0.1 s.
  The player's bars get the heal marker (`HealMarker.lua`, `BuildExternal`: at the liquid's level, under it by
  sublevels with seams, as on the player frame; hidden on a bar filling from the right) and the mana build-up
  (`ManaRule.lua`, `Bars.ExternalBars`); seen missing in game before that (eating, a bandage), and working after.
  Frames Forever's bars hold a percentage (`BarValue.lua`: range 0..100 when health is secret), so the marker takes
  `UnitHealthMax`/`UnitPowerMax` for its range, not the bar's. Four review agents went over the first version; from
  them: `AddBar` again with the same arguments does nothing (an addon may call it from its updates; it had snapped the
  liquid and cleared its motes), options are checked and an unknown theme falls back, our own bars and nameplate units
  are declined, at most `External.MAX_GROUP` (10) party and raid bars and no fury on them, a bar's errors are reported
  once (`Bars.Reported`), bars added before `PLAYER_ENTERING_WORLD` wait for it (`Core.ready`) so the login order of
  `Bars.Apply` and `HealMarker.Apply` holds, the heal seam takes a secret colour directly, and the table is read-only.
  A target's health bar gets the DoT marker (`Marker.lua`, `BuildExternal`, `RaiseExternal`): seen missing in game (a
  Rend on Frames Forever's target), and working after. Measured against `UnitHealthMax("target")`, at the liquid's level, no kill icon,
  hidden on a bar filling from the right; `Bars.Front` puts a mirrored bar's front back on its fill's left edge.
  Frames Forever hides the game's player and pet frames with `SetAlpha(0)` (target, focus and party it reparents to a
  hidden frame), and "immersion" addons fade idle frames out the same way. `IsVisible` does not see alpha, so in
  Halfdays' `/sab perf` the hidden player frame's liquids still ran (0.12 ms a frame each). So a bar is `shown`,
  `hidden` (`IsVisible` false) or `faded` (effective alpha under 0.01; `Bars.lua`, `Sight`: `GetEffectiveAlpha`, frames
  only, `SecretReturnsForAspect` Alpha and `RequiresScriptObjectAlphaAccess`, so under `pcall`, a secret taken as
  shown). It is found once a frame in `UpdateBar` (`b.sight`) and reused by events, `/sab perf` and the markers
  (`Bars.Sight`): each check is three widget calls. A faded liquid pauses like a hidden one. A faded marker pauses
  rather than hides: hidden, it forgot what it had shown, so each fade-in replayed a meal's release and grew the DoTs
  in from nothing (a review caught it). While faded it drops landings and ticks (`calm`), and a buff reached meanwhile
  sates the bar quietly (`Bars.Sate`). Not yet seen in game.
  Aura timers (issue #13, found in game by a DoT timer addon's author): addons show a target's debuffs only through
  the game's `CustomAuraContainerTemplate`, whose buttons drive the bar handed to `SetDurationBar`, and once an aura is
  assigned the button and everything in it are forbidden (our liquid's frames too: "calling 'SetVertexColor' on bad
  self"), its bar's getters included, and `C_UnitAuras` throws in combat. So `AddBar` declines a bar under a frame
  with `SetDurationBar` or a forbidden one (`Bars.AuraBound`), and `RunBar` drops one that turns forbidden without a
  word in chat. The mock's `__forbid` makes a region and its children reject every method but `IsForbidden`. Not yet
  seen in game: whether the button's `SetDurationBar` and `IsForbidden` answer as expected.
- **The editor** (`Editor.lua`): the game's `ButtonFrameTemplate` window (as the setup's), tabs on the character
  sheet's title plaque (`UI-Character-Info-Title`, as Road to Sixty's mode switch: the picked one in colour, the others
  desaturated at 70%; the scene buttons under the screen too), `UICheckButtonTemplate` boxes, `UIPanelButtonTemplate` buttons, and chips of our own. Its colour tiles are stills of each theme's liquid (`PaintTile`):
  the fill's gradient, the theme's cloud and vein textures in its colours, the front's glow and line, and two of its
  particles (its ambient ones, else its burst's), all static, so a drawer of 26 costs nothing while open. Nothing in it is protected, so it opens in combat, unlike the game's settings panel.
  Its first build (a sidebar of sections over one preview) was replaced, on the user's choice of mockups (canvas
  "SAB Options Redesign", board E), by a screen of every example at once where the game puts them, clicked to edit,
  and an inspector of bar cards with Colour and Effects drawers. The examples are `Preview.lua`'s: `Create` (the
  player and target), `CreateSingle` (the target's art standing for the focus, pet or target of target, smaller, each in
  a place of its own: the first layout swapped them into the target's place, and a bigger window was asked
  for to show them all; the screen's layout was then measured on a screenshot from the game and agreed on a mockup,
  canvas board F, which made the window 1180 x 630), `CreateParty` stacked, `CreatePlates`, `CreatePRD` (flat bars raised as the real ones, `Bars.Preview` with `flat`) and `CreateRaid`
  (ten raid-style frames in solid colours, as the game's raid art is by path; `spot.raidLook` gives them the raid
  frames' colours from the CVars and each member's class, and no spill: the frames touch, and in game the first build's
  motes flew over them). All play the scenes (`SetScene`: fight, damage, heal, power; groups take the frames' rows a
  little apart); the one being edited at full speed and the rest at a third, idling at 10 fps (`Preview.SetActive`,
  `spot.calm`), as about 40 liquids show at once. A frame whose health and power are both off rests full and still
  instead of playing the scene (`Preview.Resting`, in `SetFraction` and `SetPlate`), asked for once raid frames, off by
  default, kept animating their plain fill. The heal scene feeds a heal marker on the example's health
  (`HealMarker.Preview`, named "preview" so real heals and meals never reach it): a Renew, then a bandage; in game the
  first build's Healing only moved the bar (seen). Its panels (the screen, the inspector, the cards and rows) are Road to
  Sixty's panes (its `Screens.Pane`, `Editor.lua` `Pane`): `BackdropTemplate` with the tooltip border and ground by
  file ID (137057, 137056, as AceGUI uses them on Forever; the backdrop hands them to `SetTexture`), grey 0.6, gold on
  the open card; the screen's is an edge-only frame over its examples. Not yet seen in game. A colour tile under the mouse is tried on every bar its setting
  reaches, real and example, without being saved (`Core.Try`, read by `Core.ColorChoice`), until the mouse leaves or
  the window closes. In game the first drawers were empty: a pane anchored TOPLEFT and RIGHT has its vertical middle
  pinned to its parent's too, which gave it a negative height (the mock does not model that); panes take both top
  corners now. The stage's backdrop is a vertical gradient (`SetGradient`), dusky blue as in the mockup. The settings page's preview is built at `PLAYER_ENTERING_WORLD` (`Options.BuildPreview`), never
  while the settings panel is open. Not yet seen in game: this layout.
- **Adaptors** (`SmoothAnimatedBars/Adaptors/`, `agent.md` there says when to write one and how): for a unit frame
  addon that does not call `AddBar`, a file of ours finds its bars and hands them over (`Bars.AddBar`'s internal `key`:
  our frame's settings, not `externalBars`). The first is ClassicUI Forever's. Read the other addon's code, never copy
  it, and ask its author to call `AddBar` too. An adaptor steps aside for a bar that addon hands over itself, removed
  or not, and for one whose liquid failed (`Bars.HandedBy`, `Adaptors.Hand`): a review found the two would otherwise
  swap the bar's options every second and undo its `RemoveBar`. A game bar it unmasks (`Bars.Unmask`) is cut by its
  clip frame at the bar's edges instead (no spill), or the front's glow showed past a smaller bar onto its art. Seen in game: ClassicUI Forever's player health, inside its art.
  FlareUI (6.10 on, `Modules/UnitFrames.lua` `ns.SAB`) calls `AddBar` itself, with no theme, so its bars kept its
  colours (a warrior's player bar in class tan whatever the editor said). Your Colours on Their Bars (`externalColors`,
  off by default; `Bars.lua`, `ChoiceFor`, `GameColor`) gives every handed-over bar the colour picked for the frame it
  stands for, Game Colour being the game's (green health), not the bar's. A bar's `spot.frame` is set before `NewBar`
  colours it: set after, a bar handed over with the setting on (after a `/reload`) failed to set up and kept its own
  fill (seen in game). Seen in game and right on FlareUI's bars after that.
- **Taller bars** (players are told "Bar Height": they did not like "taller bars"; `TallFrames.lua`, `Preview.TallArt`, `playerHealthHeight`... sliders in the editor; asked for):
  Forever's player and target art (`UI-HUD-UnitFrame-<Player|Target>-PortraitOn`) is one atlas, so a taller frame is
  that atlas cut into slices: each bar's slot stretched by repeating a band from its middle, the portrait ring cut out
  with `CircleMask` and put back, and the panel's end the ring hides (never seen in the capture) drawn again from the
  dark block beside it. The ring keeps its size until it no longer covers that end, then grows (asked for). The layout
  numbers (`TALL`) were measured on the capture. Seen in game: `SetAtlas` and then `SetTexCoord` drew nothing at all, so
  a slice is the atlas's file by ID (`C_Texture.GetAtlasInfo`) with coordinates, as FlareUI cuts the same art
  (`Modules/UnitFramesRing.lua`); the mock now rejects texture coordinates on an atlas texture. The bars' masks are
  mostly transparent margin round their slot: stretched evenly, the liquid stopped short of the slot (seen in game), so
  each is stretched until the part it lets through (`opaque`, measured on the captured masks) is exactly the bar's
  growth taller. Seen in game and right in the editor's examples. On the real frames (`TallFrames.lua`) the frame is
  `Preview.LiveFrame` as a child of the game's frame, grown upward from its bottom edge (asked for: the target's auras
  start 9 above its art's bottom, and its cast bar, the target of target and the pet frame hang below). It fades the
  game's art, portrait, bars (with their texts and predictions), name and level, carries the icons round the portrait
  (elite dragon, skull, raid target, leader, PvP...) to where the moved ring puts them, copies the texts each 0.1 s, and
  hands its own bars, filled from the game's each frame, to the liquid with `Bars.AddBar` and the frame's own key, as an
  adaptor does: so the DoT marker and the mana build-up follow. The game's segments on its bars (heal predictions, heal
  absorb, absorb, the player's mana cost prediction; StatusBarOverlaySegmentTemplate) are children of the faded bar,
  so ours copy them onto our bars under the game's keys (`MyHealPredictionBar`...`OverAbsorbGlow`): each a bar-wide
  fill seen through a mask on a box anchored to the game's own `FillMask` (laid by the game from the fill's edge,
  from secrets it alone may do arithmetic on), moved by how far our bar is from the game's, our bar's height; shown as
  the game's are, each frame. Under those keys the heal marker and the shield find and hide them as on the game's bars:
  the heal marker builds on our bars as on the game frame's (`HealMarker.lua`, `BuildTall`: the player's health with
  others' heals, mana, a party member's health), not as another addon's, and the shield and Weakened Soul are drawn on
  our player health bar while it shows (`Follow` in both, the game's absorb display still read on the game's bar). From
  a review: a copy can only fade by a secret shown state (its own `IsShown` then answers true), so the heal marker asks
  the game's segment (`MirrorOf` on the copy, read by `GameOthers`), or others' heals never faded or hid there; the
  glows are cut by the bar's slot as the game's are (`PlayerFrame.xml` masks them; 9 of their 16 lie past the bar's
  end); a copy's alpha is never copied (the game's may be the paused game-bar marker's 0); Weakened Soul keeps its glass
  parts per shield and uses the shield only on its own bar (the two switch bars in separate OnUpdates). Seen in game:
  the player's PvP badge carried far up and right of the frame, its timer ("5 m") left where the game had it. The
  badge's template has a scale of its own (`PlayerPvpBackgroundIconTemplate`, `scale="0.8"`), and a scaled region
  answers `GetLeft`/`GetWidth` in its own units, so carried icons and glows are now taken into the frame's units by
  their effective scales (`ScaleTo`); the mock answers a placed region's position (`sx`, `sy`) in its own units too.
  Seen in game after that: the badge in its place.
  Texts the game anchors to a carried icon are faded and drawn beside our copy of it (`follow`: the PvP timer).
  Seen in game with Health Bar Text Forever: it fades the game's bar texts to alpha 0 and draws its own on the bars
  (`bar:CreateFontString`), so on taller frames our copies brought the game's text back and its own vanished with the
  faded bars (the target of target's, where the game has none, entirely). The bar texts' copies take their own alpha
  (never faded by us; their frames are), and every other FontString on the game's bars is copied onto ours, placed
  against our copy of the game text it hangs on, in its own font and size (`TallFrames.OtherTexts`); seen in game
  with that addon: working. Reported by players: grey bars after setting a Bar Height; not seen here, as this account has Your Colours on Their
  Bars on (`externalColors`), which already took the game's colours there. Our bars are
  handed over as another addon's are, whose Game Colour is the bar's own colour (`PlateColor`), and ours is the
  StatusBar's untinted white over the game's art, so the default drew a white liquid (in the mock too, power even under
  Class Color). Our bars are listed in `Bars.tall`, and there Game Colour is the game's (`GameColor`), as with Your
  Colours on Their Bars; seen in game with that setting off: right. Seen
  in game: heals on taller frames working (the heal marker). Not yet seen in game: the rest of that, and whether the
  client lets ours anchor to the game's masks. The full list of what
  the game's frames show and what is still missing is `docs/TALLER_BARS_GOALS.md`. Left as the game's: the rest loop,
  the group indicator.
  Built out of combat only; in a vehicle the game's frame is given back. Seen in game on a target: the frame, bars,
  portrait and text copies right, but the name and level copies invisible: a FontString's `GetTextColor` alpha is its
  `SetAlpha`, 0 on the faded game text, so copies take the colour's red, green and blue only (the mock keeps one alpha
  for text too). And with Edit Mode's Buffs on Top the game anchors the target's auras above its art
  (`TargetFrameMixin:AnchorAuraContainer`), which growing up covered (seen), so a target with `buffsOnTop` grows down.
  The focus (`focusHealthHeight`...), the pet and both targets of target (`pet`/`tot`, from the game's 11 and 7) take it
  too, each frame a spec in `TallFrames.lua` (`SPEC`: the target's template shared by the target and the focus, one
  for both targets of target) naming its art, so frames of one art share its layout and measurements (`Preview.lua`,
  `LAYOUT` and `TALL` by art; the editor's pet and target of target examples are now in their own art). The small
  frames' art (`UI-HUD-UnitFrame-TargetofTarget-PortraitOn`, the pet's too) was never captured: it was measured on
  the game's own sheet, `uiunitframec60.blp` (BLP2, uncompressed BGRA: Pillow cannot read it, the pixels follow a
  1172-byte header), from github.com/Adrestie/mod-forever-ui (its `data/art/interface/foreverui/hud`, and the
  atlases' places on it in `data/addon/ForeverUI/UIAtlas_04_unit_frames.lua`, generated from the Forever client
  1.60.1). Measured there, the player's and target's art agreed with their capture's numbers within a few tenths. That
  repo also has Forever's other sheets (action bars, party, raid, minimap), worth a look before capturing art again;
  it has no masks. The small frames use the party frame's masks, so their opaque bands are the party capture's. Seen
  in the editor: the small frames' masks, placed by the game's anchors, let the liquid through 1.4 above their slots
  and the power's 2 left, under the gold divider (as on the party frame, where `PARTY_POWER_SHIFT` was set by eye); the
  game keeps its fill in the slot, so each mask is centred on its slot as measured on the sheet. A ring grown past its
  frame widens the editor's outline (`TallArt`'s `over`). The party members (`partyHealthHeight`/`partyPowerHeight`,
  from the game's 10 and 7): the party art is the small frames' pixel for pixel, 1 right and 2 down (`TALL.party`,
  measured on `uipartyframec60.blp` from the same repo); measured there, centring the power mask on its slot needs
  0.9 right and 1.9 down, against `PARTY_POWER_SHIFT`'s 1.5 and 1.9 by eye, so that shift stays. The game pools the
  four member buttons and hands them between `MemberFrame1..4`, so a member's state is kept by its button
  (`TallFrames.State().party`) and its unit read from the button each look. The game stacks them 10 apart (26 with
  party pets) and each has 2 under its art, so they grow down and their sliders stop at +8 and +4; the editor's
  stacked party is drawn smaller as it grows, to stay on the screen. Not yet seen in game: the focus, pet, targets
  of target and party taller. Seen in game: the player's aggro flash (`FrameFlash`, the threat indicator) left at the
  game's place, misaligned with the taller frame. The flashes (`...-PortraitOn-InCombat`) and the player's status
  glow (`...-Status`) have the art's outline round the ring and the name row, so they are laid out by the art's own
  slicing (`Preview.TallGlow`, `Lay` with no panel's end, the ring cut `GLOW_PAD` wider), placed where the game's sits,
  in its colour and blend mode. The game pulses the status glow's alpha every frame (`PlayerFrame_OnUpdate`), so the
  player's and target's pieces are hidden by fading their containers (`PlayerFrameContainer`,
  `PlayerFrameContentMain` and the target's), never the glows themselves, whose own alpha ours copies each frame; the
  pet's and a party member's flash sit on the frame itself and are faded alone. The game's hit numbers over the portrait
  go with the player's main content, so ours copies them over its portrait each frame (`CopyHit`: text, colour, alpha; seen in game
  working, before its sizes: asked to match the default exactly), its size worked out from `UNIT_COMBAT`'s action and flag
  (`HitSize`; a FontString has no getter for `SetTextHeight`), not grown with the ring
  (asked for; only its place moves with the portrait). A hit flagged ABSORB, BLOCK or
  RESIST is a word at 0.75 or, with some damage through, a number at full size: the amount is secret, so told by the text
  being secret. The pet's (`PetHitIndicator`) share a frame with its name alone, so that frame is faded (the game sets the
  text's own alpha each frame). Not yet seen in game: the sizes, the pet's. The combo points round the target's portrait (Camelot `ComboFrame.lua`) were seen in game
  left round the game's smaller ring; ours are dots of the game's own template round our ring (`BuildCombo`,
  `MirrorCombo`), the game's dots faded rather than `ComboFrame`, whose alpha `UIFrameFadeIn` sets. Seen in
  game: in sync with the game's. The editor's target example has them for a rogue (`Preview.lua`, `AddCombo`, asked for;
  seen in game, working). Seen in game: the resting "zzz" and the target's cast bar fine. A druid's extra mana bar has its own player art
  (`AlternatePowerFrameTexture`): while it shows, the game's frame is given back. Seen in game: a target of target showing the face of the
  one before, as no portrait event comes when the target picks a new target; portraits are now redrawn on
  `UNIT_TARGET` (the target's or focus's new target), a new target or focus, the party's roster, and whenever the
  name the game shows changes (`TallFrames.lua`, `Changes`).
- **Toc changes** (a new file) need a full game restart; `/reload` does not pick them up.
- **No realm since build 71037** (reported by another addon's author; Forever's patch of 2026-11-21): `GetRealmName()`
  returns `""`. An empty realm is no answer, never a realm: a character without a surname keeps its one saved
  "Name - X" profile (`SmoothAnimatedBars.lua`, `KnownKey`; names are unique across the region), else takes the
  ruleset as a surnamed one does, and keeps that one if the realm reads again. Before the fix such a character had
  switched to the account-wide settings (its key "Name - ", not in `ownSettings`); settings made under "Name - " then
  move to its new key. Heal recipients fall back to the loose "Name-..." match (`Heals.lua`, `realmPart`), after the
  exact ones. The mock keeps a realm by default, as the profile tests key by it; the no-realm tests set it to `""`.
  Seen in game after the fix: fine on characters with surnames.
- **Capture:** `/sab capture` uses `Screenshot()` and the `screenshotFormat` CVar (TGA, put back after).
  The screenshot is the full render resolution (an ultrawide 3440x1440 here), and the red "?" target
  portrait once fooled the marker search, which now looks only at the top of the screen. The game's tooltip
  (bottom right, if the mouse rests on a mob) once landed in the grid's last cell, the kill icon, so
  `capture_art.py` keeps only the portrait's area of that cell (`KEEP`).

## Dev setup

`_forever_\Interface\AddOns\SmoothAnimatedBars` is a junction to this repo's `SmoothAnimatedBars/`, so
`/reload` loads the working copy. Settings are account-wide in `SmoothAnimatedBarsDB.global` by default (as the user
asked), or a character's own in `.profiles["Name - Realm"]` ("First Last - Ruleset" on Forever) for a character in
`.ownSettings`; `Core.db` is the profile in use, and the game's registered settings reach it through a proxy table
(`settingsView`), so a switch needs no re-registering. Everything else at the root (`Core.account`) is the account's:
the setup (shown once per account), the changelog, the DoT data, `/sab` logs, the plate art. Earlier versions' flat
settings become `.global` on load. A character's own settings start as a copy of `.global` and are kept if it goes back
to sharing. Editor's Profiles tab: Use Account-Wide Settings, a picker with arrows and Copy (`Core.SetUseGlobal`,
`Core.CopySources`, `Core.CopyProfile`); clicking the picker opens the game's menu (`MenuUtil.CreateContextMenu`), but
not under the controller interface, for the reason the unit menus are left alone there (`Options.GamepadUI`). A profile change while the setup is open: its Skip puts back every profile it saw in use, as first seen (a
character's own made then from the shared ones as the shared ones were), but leaves a copy over one as copied
(`Wizard.ProfileChanged`; a review found switching away and back had lost the Skip). `setupDone` marks
that the setup wizard has run. The tools need `tools/venv` (`pip install lupa numpy pillow`).
