# Smooth Animated Bars

World of Warcraft addon for **WoW Forever only** (`## Interface: 16001`): the liquid from Smooth Experience
Bar (`../smooth-experience-bar`) in the game's unit frame, nameplate and other addons' health and power bars. The README
is for players. This file holds the rules and the traps; the rest is in `docs/`:

| Document | What it holds |
|---|---|
| `docs/DEVELOPMENT.md` | The layout, the tools and their commands (tests, previews, bench, samelook, the CPU rig, the gallery) |
| `docs/findings/` | What we learned about Forever, one file a topic (index in its `README.md`): read the topic's file before working on it |
| `docs/GALLERY.md` | The gallery's scenarios and the frame art |
| `docs/RELEASE.md` | The release steps |
| `docs/TALLER_BARS_GOALS.md` | What the game's frames show and what Bar Height still misses |

## Rules

- **Secret values:** Forever keeps health and power secret from addons, in and out of combat (`UnitHealth`,
  `UnitPower`, the bars' `GetValue`), and many other answers when it chooses (see the traps below). Never compare them,
  do arithmetic on them or truth-test them. Hand them to widgets (`StatusBar:SetValue`, `SetAlpha`, `SetVertexColor`,
  `SetAlphaFromBoolean`) and anchor to what the client lays out; `Bars.lua` explains the design. The mock cannot catch a
  comparison (Lua 5.1 lets `==` and truth tests on a table through), so check by reading.
- **Game frames:** only read and draw on them. No hooks, no fields written onto them, no changes besides the
  fill texture's alpha. Our frames sit at the bar's own frame level so the game's text stays on top, except on
  nameplates and the Personal Resource Display (raised, `docs/findings/nameplates.md`) and a health liquid with the DoT
  marker on it (`docs/findings/dots.md`). One exception, asked for: while a bar height is not the game's (Bar Height,
  `docs/findings/taller-bars.md`), a frame of ours is drawn in place of the game's, and the game's pieces it redraws are
  faded (alpha 0) meanwhile and given their alpha back after. Nothing is ever drawn over or faded at the game's heights.
- **Forever assets:** game files by path often fail to load there. Use `SetColorTexture` for solid fills and
  the addon's own TGAs in `SmoothAnimatedBars/Media/` (made by `tools/make_media.py`), never `Interface\...`
  game paths. Icons and atlases' files by file ID.
- **Settings:** every setting has a control in the editor (`Editor.lua`, `FRAMES` and `TABS`); the tests check it. Every
  setting is registered with the game (`Settings.RegisterAddOnSetting`, no rows) and changed through it
  (`Core.SetSetting`), except a bar's own effects (`Core.SetEffect`). Never register initializers into the game's
  vertical layout lists: on Forever that taints the Social page. Details: `docs/findings/editor.md`.
- **Lua's 200 locals:** `Bars.lua`'s main chunk is at the limit; one more file-level `local` fails to load in game
  ("main function has more than 200 local variables", seen). Put new functions and constants on a table (`Bars.X`).
- **Tests:** run `tools/venv/Scripts/python tools/harness/test.py SmoothAnimatedBars` before every commit; it
  exits 1 on any failed check. The mock (`tools/harness/wowmock.lua`) should be as strict as the client:
  when the client rejects something the mock accepted, make the mock reject it too.
- **Speed changes:** a change made to cost less must not change the look (asked for). Measure it with
  `tools/harness/bench.py --ref HEAD` (widget calls and the addon's Lua work, the same frames before and after) and check
  it with `tools/harness/samelook.py --ref HEAD`, which must pass (every texture the same each frame, colours within half
  an 8-bit step). Both are repeatable (a fixed seed, `pairs` in a fixed order). What the addon costs and what was cut:
  `docs/findings/performance.md`.
- **Visual changes:** render a preview (`tools/harness/preview.py`) and look at it. Rebuild the gallery
  (`tools/harness/gallery.py`, `docs/GALLERY.md`) when the liquid's look changes, and look at it before committing; a
  full run takes about a quarter of an hour, so run it in the background. Judge colours on screenshots from the game: the
  mock draws added light fainter than the client.
- **Frame art:** `branding/art/` is captured in game (`/sab capture`, `tools/capture_art.py`), only for the gallery,
  never packaged. The layout numbers live in `Preview.lua` (`LAYOUT`) and are repeated in `gallery.py`; change both.
- **Findings:** what is learned about Forever goes into its topic's file in `docs/findings/` (a new file for a new
  topic, listed in its `README.md`), not here, saying what was seen in game and what is not yet seen. Only a trap that
  bites everyday code gets a line below.
- **Commits:** stage the files you changed by name, never `git add -A`. Commit messages are plain and
  professional.
- **Changelog:** add player-facing notes to `CHANGELOG.md` under the next version as features land
  (`### New`, `### Fixed`, no internal changes).
- **Releases:** follow `docs/RELEASE.md` step by step.

## Traps

- **Forever's UI source** is the `forever` branch of github.com/Gethe/wow-ui-source
  (`gh api "repos/Gethe/wow-ui-source/contents/Interface/AddOns/<path>?ref=forever"`); `Camelot/` folders are Forever's
  overrides. Other addons in `_forever_\Interface\AddOns` are worth grepping for working Forever API use.
- **Secret answers:** besides health and power, `GetAlpha` (`SecretReturnsForAspect` Alpha), `IsShown`/`IsVisible`
  (Shown), `GetWidth`/`GetRect`/`GetCenter` (`SecretWhenAnchoringSecret`), `UnitClass` and names
  (`SecretWhenUnitIdentityRestricted`), colours of secret-coloured bars, auras in combat (`RequiresNonSecretAura`) and
  `UNIT_COMBAT`'s amounts can all come back secret. `Bars.lua`'s `Secret`, `AlphaTo` and `Visible` handle them.
- **The combat log is closed** (`COMBAT_LOG_EVENT_UNFILTERED` shows a "blocked" popup); `UNIT_COMBAT` still fires with a
  readable action, flag and school (`docs/findings/dots.md`).
- **A texture has one alpha:** `SetVertexColor`'s fourth value and `SetAlpha` set the same thing.
- **Atlases:** `SetAtlas` then `SetTexCoord` draws nothing; use the atlas's file by ID (`C_Texture.GetAtlasInfo`) with
  coordinates.
- **Draw order:** a clipping frame (`SetClipsChildren`) seems to be drawn outside the layer sorting, and sublevels do not
  order textures in separate frames; what must stack goes by frame level or in one frame.
- **FontStrings:** no `GetWordWrap` (it is `CanWordWrap`); `GetFont` does not report `SetTextHeight`; `GetTextColor`'s
  alpha is the string's `SetAlpha`.
- **Scaled regions** answer `GetLeft`/`GetWidth` in their own units; take them into the frame's by effective scale.
- **Taint:** anything added to a unit menu whose unit has a secret identity, or while the controller interface is on,
  breaks the game's menu or gamepad actions; those menus are left alone (`docs/findings/unit-frames.md`).
- **Toc changes** (a new file) need a full game restart; `/reload` does not pick them up.
- **No realm:** since build 71037 `GetRealmName()` returns `""`; an empty realm is no answer (`docs/findings/client.md`).
- **Cost:** the addon's own Lua is most of what it costs (about 39 us a thousand instructions of its code in game), its
  function calls and lookups above all; a widget call is only 0.15 to 0.35 us (measured with `/sab perf calib`). Cut
  Lua, not only calls (`docs/findings/performance.md`).

## Dev setup

`_forever_\Interface\AddOns\SmoothAnimatedBars` is a junction to this repo's `SmoothAnimatedBars/`, so `/reload` loads
the working copy. Settings are account-wide (`SmoothAnimatedBarsDB.global`) by default, as the user asked; a
character's own and the Profiles tab are in `docs/findings/editor.md`. The tools need `tools/venv`
(`pip install lupa numpy pillow`).
