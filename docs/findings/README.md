# What we learned about Forever

Facts found while building the addon, which the code relies on and which are not obvious from it, one file a topic.
Each says what was **seen in game** and what is **not yet seen in game** (built from Forever's code or docs, or tried
only in the mock); keep that line up to date when something is tried. The rules these lead to are in
[CLAUDE.md](../../CLAUDE.md); the tools are in [DEVELOPMENT.md](../DEVELOPMENT.md).

| File | What it covers |
|---|---|
| [client.md](client.md) | Forever's UI source, secret values, layering and masks, auras in combat, regeneration, toc changes, the empty realm |
| [unit-frames.md](unit-frames.md) | The health-loss animation, Class Color by unit, the pet, focus and targets of target, the unit frame menus (taint, the controller interface) |
| [group-frames.md](group-frames.md) | Party member frames and raid-style frames: how the game pools them, what is secret, layering on raid frames, the black frame |
| [nameplates.md](nameplates.md) | Enemy and friendly nameplates (pooling, masks, raised levels, text copies, secret colours, deep themes) and the Personal Resource Display |
| [dots.md](dots.md) | DoT tracking without the combat log, rogue poisons, the poison skulls, DoTs on the player |
| [languages.md](languages.md) | Reading spell text in every client language, and how it was checked |
| [heals.md](heals.md) | The game's heal prediction, other players' heals, heals on party and raid members, the heal liquid's seam |
| [shield.md](shield.md) | Power Word: Shield's absorb and how its look was found, Weakened Soul |
| [power.md](power.md) | The five-second rule's build-up and the Rage Fury (curves on secret power) |
| [other-addons.md](other-addons.md) | Bars other addons hand over (`AddBar`), faded frames, aura timers, the adaptors |
| [taller-bars.md](taller-bars.md) | Bar Height: slicing the frame art, masks, segments, icons, texts and glows carried over |
| [editor.md](editor.md) | The editor window, how settings are registered, the effect levels, profiles |
| [performance.md](performance.md) | What the addon costs in game, how it is measured (`/sab perf`, the bench, the rig) and what was cut |
| [capture.md](capture.md) | `/sab capture` and its pitfalls |

The gallery's scenarios are in [GALLERY.md](../GALLERY.md), the release steps in [RELEASE.md](../RELEASE.md), and the
list of what taller frames still miss in [TALLER_BARS_GOALS.md](../TALLER_BARS_GOALS.md).
