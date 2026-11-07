# Changelog

Player-facing notes for each release. Write for players: what they can now
do or see, and what was broken and now works. Leave out internal changes.
Sections are `### New` and `### Fixed`; skip one that would be empty.

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
