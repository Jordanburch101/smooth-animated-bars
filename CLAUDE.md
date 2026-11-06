# Smooth Animated Bars

World of Warcraft addon for **WoW Forever only** (`## Interface: 16001`): the liquid from Smooth Experience
Bar (`../smooth-experience-bar`) in the game's player and target frame health and power bars. The README
covers the layout and tools; this file holds the rules.

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
- **Visual changes:** render a preview (`tools/harness/preview.py`) and look at it.
- **Commits:** stage the files you changed by name, never `git add -A`. Commit messages are plain and
  professional.
- **Changelog:** add player-facing notes to `CHANGELOG.md` under the next version as features land
  (`### New`, `### Fixed`, no internal changes).
