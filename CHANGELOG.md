# Changelog

Player-facing notes for each release. Write for players: what they can now
do or see, and what was broken and now works. Leave out internal changes.
Sections are `### New` and `### Fixed`; skip one that would be empty.

## 1.14.1

### Fixed
- With the DoT Marker on, text another addon puts on the target's health bar
  (such as Health Bar Text Forever's) was hidden under the liquid.
- With Bar Height, text another addon puts on your frames' bars (such as
  Health Bar Text Forever's) disappeared, and the game's own text could show
  in its place.
- With Bar Height and Game Colour (the default), the bars could show grey
  instead of the game's colours.

## 1.14.0

### New
- **Bar Height**: the health and power bars of your player, target, focus,
  pet, target of target and party frames can be made taller, with a slider for
  each on that frame's page in the editor. A taller frame is drawn from the
  game's own frame art. The player, target and focus frames grow upward, so the
  debuffs and cast bar below them stay clear (with Buffs on Top, the target and
  focus grow downward instead); the pet, target of target and party members
  grow downward, the party members only as far as the gap between them.
  Taller frames keep what the game shows on its bars: incoming heals,
  shields and heal absorbs, the mana a cast will cost, the heal marker
  (on party members too), the Shield, Weakened Soul and your combo points.
- **Other healers' heals in their own colours**: a heal another priest or
  paladin is casting on you or your group now shows in the Holy look, and a
  druid's or shaman's in Nature's spring green, instead of always the silvery
  teal. When healers of both kinds heal the same player, it stays teal.
- **Animation Speed and Wave Intensity**: two sliders on the editor's
  Effects tab. Speed makes everything in the liquid move slower or faster,
  from 25% to 200%; the bar still follows your health at the game's pace.
  Wave Intensity sets how far the liquid's front bulges and ripples, from a
  flat front at 0% to twice as dramatic at 200%. A bar with its own effects
  has its own sliders too.

### Fixed
- Heals of 1,000 or more (Holy Light rank 8 and up, the top ranks of
  Greater Heal, Healing Touch and Healing Wave, the biggest bandages, food and
  drink) now show on the heal marker, in every client language. Amounts with
  a thousands separator went unread or read short.
- Your own raid-style frame could turn black until a reload.

## 1.13.0

### New
- **Heal marker on party and raid frames**: your heals over time,
  bandages and the heals you are casting on a party or raid member now show
  ahead of their health, as they do on yours, on the party frames and on
  raid-style frames alike. It follows the Heal Marker setting and shows
  while their health has the liquid.
- **Heal marker in every language**: your heals, bandages, food and drink
  now show on French, German, Spanish, Portuguese, Russian, Korean and
  Chinese clients too.
- **Other players' heals on the heal marker**: a heal another player is
  casting on you, a party member or a raid member now shows as a silvery
  teal liquid after your own heals, sized by the game's own prediction.
  While the heal marker shows, it takes the place of the game's flat heal
  prediction bars.

### Fixed
- Greater Heal and Prayer of Healing now show on the heal marker while you
  cast them.
- Food whose buff says "If you eat for 10 seconds" now builds up to its buff
  like other food.
- An addon's debuff timer bars, drawn in the game's own aura buttons, no
  longer give an error in chat. The game keeps those bars to itself, so they
  stay as the game draws them.
- With Better Blizzard Plates, a nameplate's name no longer shows twice. The
  name drawn over the liquid now takes that addon's colour, size and hiding,
  and is left to it when it raises the name above everything.
- A character without a surname that has its own settings no longer
  switches to the account-wide settings after the game's November 2026
  patch, which stopped telling addons the realm.

## 1.12.0

### New
- **Settings for each character**: give a character its own look by
  unticking Use Account-Wide Settings on the editor's new Profiles tab.
- **Copy settings** from another character, or from the account-wide ones,
  on the Profiles tab.
- **Shields on your health**: while a shield is on you, the end of your
  health bar turns into a barrier of golden glass. It flares when it soaks a
  hit and shatters when it ends. Turn it off under Shield in the editor's
  Combat tab.
- **Weakened Soul on your health**: after Power Word: Shield, your health's
  edge turns to ash and slowly warms back to gold, then flashes when you can
  be shielded again. Turn it off under Weakened Soul in the editor's Combat
  tab.
- **DoT marker learns your real damage**: after each fight it reads what your
  DoTs actually did from the game's damage meter, so the marker and kill icon
  keep up with your gear. Thanks to DoesItDie, whose tracking this follows.

### Fixed
- A DoT that is resisted and never ticks no longer stays on the marker for
  its whole duration.
- Rend and other bleeds no longer run out on the marker a tick early when
  your swings land just before their ticks.
- With action targeting, a DoT cast while the last kill is still your target
  goes on the next mob, not the corpse.
- DoTs cast with a `/cast [@mouseover]` macro, or with the game's own
  Mouseover Cast option, go on the mob under your mouse.
- Rip and Rupture no longer vanish from the marker when an auto-attack misses
  at the same moment.
- The editor's panels have borders in the game's own style.

## 1.11.0

### New
- **The editor**: every setting in one window, beside live examples of all
  your frames laid out as on your screen. Click a frame to change it, and
  hover over a colour to try it on your bars first. Open it with `/sab`, by
  right-clicking your frame, or from the addon's page in the game's AddOns
  settings.
- **Effects for one bar**: any bar can now have its own effects. Open it in
  the editor and untick Use the global effects on its Effects tab, to turn
  off Bubbles on just your power bar, say.
- **Raid frames**: the liquid in raid frames, and in raid-style party
  frames. Names, icons, heals and shields stay on top. Off to start with:
  turn on Health and Power under Raid in the editor.
- **Proven with other unit frame addons**: tried in game with FlareUI (from
  6.10) and Frames Forever (from 1.4.3), which build the liquid into their
  own bars, and now ClassicUI Forever, whose player, target, focus, target
  of target, party and pet bars follow your settings for each frame. The
  addon's page lists what each supports.
- **Your colours on other addons' bars**: tick Your Colours on Their Bars
  under Other Addons to give bars from addons like FlareUI the colours you
  pick for each frame, instead of their own.

### Fixed
- **Faded-out frames**: bars on a frame another addon has faded out no
  longer keep animating unseen. The liquid pauses until the frame is back.
- **`/sab off`**: now turns off nameplates and raid frames too.

## 1.10.0

### New
- **Kill icon on nameplates**: with Your DoTs on Nameplates on, the game's
  skull now shows beside a mob's nameplate when your DoTs will finish it off,
  as it does on your target's portrait. Turn it off with Kill Icon on
  Nameplates under Nameplates in the settings.

### Fixed
- **DoT marker on the target**: your target's health no longer sometimes
  ends in a straight cut against your DoTs. Its wavy front now always flows
  over them, as it was meant to.

## 1.9.0

### New
- **Other unit frame addons**: addons that replace the game's unit frames
  can now hand their own health and power bars to Smooth Animated Bars, so
  the liquid fills their bars instead of the hidden game ones. Those bars
  keep the colours you set in that addon, and bars that fill from the right
  get the liquid flowing the other way. Your heals, bandages, food and drink
  pour into your own bars there, and the mana bar builds up through the wait
  before mana regenerates. With the DoT Marker on, your damage over time shows
  on their target's health bar too. Turn it off under Other Addons in
  the settings.

### Fixed
- **Controllers**: with the game's controller interface on, right-clicking
  your target or another unit frame no longer blocks an action and breaks the
  controller interface until a /reload. That happened when inviting someone
  to your group or asking to join theirs. The Open Settings entry is left out
  of those menus while the controller interface is on.

## 1.8.0

### New
- **Lighter**: the liquid takes much less of each frame, most of all in
  combat, with a party, and on a warrior's furious rage bar.
- **Party frames**: the liquid now fills your party members' health and
  power bars too. Each bar follows its own member: Class Color shows each
  one's class, and Game Colour each one's power type. While a member is
  offline their bar goes back to the game's grey one. Switch them on or
  off, and pick their colours, under Party in the settings, or right-click
  a party member's frame and choose Open Settings. Raid-style party frames
  keep the game's own bars.
- **Personal Resource Display**: the liquid fills the game's Personal
  Resource Display too, the extra health and power bars you can turn on in
  the game's options and place with Edit Mode. It follows your own bars' colours,
  or takes its own under Personal Resource Display in the settings. Your
  heals, bandages, food and drink show there as on your player frame, the
  mana bar builds up through the wait before mana regenerates, and a
  warrior's rage grows furious. A druid's mana under the power bar in Cat or
  Bear Form gets the liquid as well.

### Fixed
- A bar no longer shows empty for a moment after you log in or switch its
  liquid on.

## 1.7.3

### Fixed
- Right-clicking your target in a dungeon, raid or battleground shows the
  game's menu properly again. Before, its lines were drawn on top of each
  other with an error, so you couldn't set a target marker. In those places
  the menu no longer has Open Settings.

## 1.7.2

### Fixed
- Nameplates in battlegrounds no longer stop with an error ("attempt to
  compare a secret number value") and go back to the game's bar, and
  enemy players' nameplates there keep their class colours.

## 1.7.1

### Fixed
- Names on enemy nameplates in the Block and Large styles, which the game
  draws inside the health bar, no longer disappear under the liquid, and
  long names are no longer cut shorter than the game cuts them.

## 1.7.0

### New
- **Rage Fury**: your rage bar grows more furious as it fills. From about
  half full it heats up, flames licking inside, lightning and sparks
  flying, and at full rage it throbs, ready to burst. Spending rage lets
  it go in a spray of sparks. Turn it off under Rage in the settings.

## 1.6.1

### Fixed
- Health numbers on nameplates (turned on in the game's nameplate
  settings) are no longer hidden under the liquid, and neither is the
  name in the Large nameplate style.
- Nameplates in their own colour now match the game's: an enemy's red is
  as deep as the game's, no longer greyed out and darker looking.
- Your DoTs on nameplates no longer show a brighter block just behind the
  health's edge.

## 1.6.0

### New
- **Enemy nameplates**: the liquid in the health bars of enemy nameplates,
  in the nameplate's own colour or your target's. Turn it on under
  Nameplates in the settings, or in the setup. In a big crowd the first 15
  get it.
- **Friendly nameplates**: the same for other players and friendly NPCs,
  with a colour of their own: the nameplate's, any theme, or Class Color
  for other players' classes. Up to 10 get it, apart from the enemies, so a
  busy city cannot crowd out a fight. Friendly nameplates in dungeons keep
  the game's bar, as the game keeps them from addons.
- **Your DoTs on nameplates**: every mob carrying your damage over time
  shows it on its nameplate, as your target's frame does, and keeps it
  when you change target. Bleeds look the same as on the frame. No kill
  icon or poison skulls there.
- **Bleeds bleed**: on the DoT marker a bleed beats like a heart and spurts
  blood with every beat, drips between beats, and gushes on a critical hit.
- **Other client languages**: the DoT marker reads your spells in French,
  German, Spanish, Portuguese, Russian, Korean and Chinese too (not yet
  tried in game; rogue poisons and Immolation Trap still need an English
  client). `/sab dots` lists any spell text it could not read.
- **Nameplates in the setup**: a last step to turn enemy and friendly
  nameplates on, with example nameplates showing each choice.
- **What's new**: this window, once after each update. `/sab changes` or
  What's New on the settings page opens it again.
- **`/sab perf`**: what the liquid costs each frame, the unit frames and the
  nameplates apart, kept for later (`/sab perf 12 mobs` labels it).

### Fixed
- Rip and Rupture cast with 1 combo point no longer show the damage of a
  5-point one on the DoT marker.
- Grounding Totem no longer shows on the DoT marker.
- Mutilate's 2 combo points are counted, so a Rip or Rupture after it shows
  the right damage.

## 1.5.0

### New
- Right-click your frame, your target's, your pet's or your focus's: the
  menu now ends with Open Settings for Smooth Animated Bars, which opens
  the settings at that frame's section.
- Rogue poisons on your target: a poison that does damage over time, like
  Deadly Poison, now shows on the DoT marker as a Plague liquid. The poison
  is noted when you put it on your weapon, and seen landing by its Nature
  ticks. It counts one stack, so with more stacks it deals more than it shows.
- Nature DoTs on your target (poisons, Serpent Sting) give off the game's
  own poison skulls: a few drift up while they run, swinging their heads as
  they fade, and a burst comes with each tick. Their liquid is a darker
  green than the Plague theme, so it stands apart from the health.

## 1.4.0

### New
- Liquid in the pet, focus and target-of-target frames too.
- The settings have a section for each frame: Player, Target, Pet, Focus
  and Target of Target. Each bar is on or off, and while it is on, its
  colour shows under it. The target and pet start on Same as Yours, the
  focus and targets of target on Same as Target. The setup has a new step
  for your target's colours.
- Class Color now follows each unit: a targeted player shows their class
  instead of yours. Class Color on Mobs says what it shows on a mob:
  Reaction (red, yellow or green, the default), Game Colour so only
  players show a class, the class the game gives the mob, or your own class.
- Mana regen build-up: after a spell that costs mana, your mana stops
  regenerating from Spirit for five seconds. Your mana bar now shows that
  wait: motes gather into the front of the liquid, which turns pale and
  pulses faster while lightning starts up, then it lets go in a burst of
  stars as regeneration returns. Another spell that costs mana starts the
  wait again, and spells that cost none, like Shoot, do not. On by default,
  under Mana in the settings; `/sab mana` shows what it saw.
- Fire looks like fire now rather than lava: flame tongues lick up through
  the bar from a hot base into a smoky top, the whole fire flickers, and
  real sparks fly off it, swaying as they rise and cooling from white-gold to
  red. Fire DoTs on your target (Immolate and the like) burn the same way.
- New theme, Shadow: a near-black liquid, thick as tar, with smoke trailing
  low off it, slow bubbles rising and bursting, and a violet light deep
  inside that waxes and wanes. Shadow DoTs on your target (Corruption,
  Shadow Word: Pain and the like) now show as Shadow rather than Void.
  Void is still there to pick.

### Fixed
- An error that turned the target's health liquid and the DoT marker off
  ("attempt to compare local 'w' (a secret number value)"): when the game
  keeps a bar's size from addons, the liquid now keeps the size it last knew.

## 1.3.0

### New
- Heal marker: the health your own heals will still bring back shows ahead
  of your health as a liquid of its own, so you can see how far Renew, a
  bandage or the heal you are casting on yourself will take you. Holy gold
  for priest and paladin heals, spring green for druid and shaman heals
  and for bandages; both at once show side by side. Each ripples with
  every tick, a heal you cast bursts into your health as it lands (leaves
  for Nature, holy sparks for Holy), bandages throw up green pluses as
  they tick, as the game does over a healed character, a broken bandage
  drops out at once, and healing past full health is cut off at the bar's
  end. While it shows, it takes the place of the game's flat teal bar for
  your own heals. Your own heals on yourself only. On by default, under
  Healing in the settings; `/sab heals` shows what it is tracking.
- Eating and drinking show too: what your food will still bring back is a
  Honey liquid ahead of your health, and what your drink will is a Nagrand
  liquid ahead of your mana. They end when you stand up: moving or casting
  anything else ends them.
- Food with a buff builds up in your health liquid while you eat, even at
  full health, then lets go in a burst of stars when you have eaten long
  enough to become well fed. Slow stars keep rising after that, so you
  know you can get up.
- Whatever is on the way pours into your bar: its particles drift back
  into your health or mana liquid, whose front ripples and takes on some
  of the incoming colour.

## 1.2.0

### New
- DoT marker: each school of damage over time is now a liquid of its own,
  so a warlock's Corruption and Immolate show as Void and Fire side by side.
  The school you put up first sits at the front of the health, the next
  behind it. Two schools show at once; a third joins the second.

## 1.1.0

### New
- DoT marker: the health your damage-over-time spells will still burn away
  turns into a second liquid on your target's health bar, in your DoTs'
  colour (Void for Shadow, Fire, Plague for Nature, Blood for bleeds...),
  eating into the health liquid. If no health liquid is left, your DoTs will
  kill the target, and the game's skull shows on its portrait. It goes by
  your spells' tooltips and runs each DoT for its whole duration. Off
  unless you turn it on: the setup has a new last step for it, and it is
  under Damage Over Time in the settings. `/sab dots` shows what it is
  tracking.
- A new icon in the AddOns list: the Greater Nether Essence.

## 1.0.0

### New
- Liquid health and power bars on the player and target frames, with the
  liquid from Smooth Experience Bar: waves, a magic swirl, bubbles,
  sparkles and lightning. It eases to wherever the game's bar is and
  stirs whenever the bar changes.
- Health and power each take the game's colour (green health; blue mana,
  red rage, yellow energy) or any of 24 themes, Class Color and Faction
  among them, with their own particles.
- Turn each bar and each effect on or off in Options > AddOns > Smooth
  Animated Bars, or with `/sab`. `/sab on` and `/sab off` switch all four
  bars at once.
- A short setup on your first login: which bars, their colours and how
  lively they are, each shown as you pick it on preview player and target
  frames (and your own frame). Skip puts everything back. Open it again
  with `/sab setup` or from the settings.
