# Changelog

Player-facing notes for each release. Write for players: what they can now
do or see, and what was broken and now works. Leave out internal changes.
Sections are `### New` and `### Fixed`; skip one that would be empty.

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
