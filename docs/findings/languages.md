# Other client languages

Reading spell text in every language Forever ships.

## Other client languages

*Where:* `Locale.lua`, `Locale_<tag>.lua`, ported from DoesItDie 0.9.3 without its options translations

English patterns run first, then every language in toc order, whatever `GetLocale()` says (DoesItDie saw it answer enUS
on a German client). Not tried here on any non-English client, but checked against Forever's own tooltips for all 1407
class spells (from WhatsTraining's `Classes/Camelot` data) in every language, from Wowhead's tooltip API
(`https://nether.wowhead.com/tooltip/spell/<id>?dataEnv=16&locale=<n>`, 16 is Forever; locale 0 en, 1 ko, 2 fr, 3 de, 4
cn, 6 es, 7 ru, 8 pt; zhTW (5) comes back in English). Every reading matched English; the fixed cases are in
`tools/harness/language_cases.json`. Wowhead shows some numbers as formulas (Rupture), and its text has non-breaking
spaces (U+00A0) that `%s` does not match, so every reader turns them into plain spaces first. In plain Lua 5.1,
`%s`/`%p` follow the C locale and can match bytes inside Cyrillic letters, so `Locale_ruRU.lua` lists ASCII bytes. The
poison coatings, traps and Weakened Soul's "absorb" still read English only. `/sab dots` logs `NOT READ` for non-English
text nothing read. Heals, food and drink (`Heals.lua`, `readHeal`/`readRest`) go the same way: English first, then each
language's readers, built from its wording by `Locale.lua`'s `L.healReader` (the addon's own, not DoesItDie's). Checked
the same way, against Forever's text for the lowest and highest rank of every class heal, bandages, food and drink in
every language, each read as the English of the same spell (`tools/harness/heal_language_cases.json`, 1160 cases). That
check found English missing Greater Heal ("A slow casting spell that heals..."), Prayer of Healing and Desperate Prayer,
and a food's buff worded "If you eat for 10 seconds"; all read now. Tranquility ("every 2 sec") and food restoring a
share of health are read in no language. `/sab heals` logs `UNREAD` for non-English text with a number that nothing
read. Not tried on any non-English client.

A review found the first readers, which looked for a health word anywhere, taking spells that cost, drain or convert
health for heals over time on the caster (Bloodrage, Last Stand, Rend's "perd 147 points de vie en 21 sec", Devouring
Plague in every language, Lightwell): each language's heal patterns are now anchored at the text's start, as English's
are, and the cases include 609 readings of 75 spells that are no heal (damage over time, drains, costs, buffs, potions),
each read as English reads it. Potions and Holy Strength's proc still read as a direct heal in some languages; instant,
they show nothing.
