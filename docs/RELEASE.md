# Releasing

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

1.0.0 was tagged before there was a release workflow or a CurseForge project.

## The icon

The addon's icon is the game's INV_Enchant_EssenceNetherLarge (Greater Nether Essence, file ID 132870, found in
ItemTree_Data's item records), and it is the icon for the CurseForge project too, borderless (`branding/README.md`).
`public/favicon.ico` is the borderless icon at 16 to 64 px, as in Smooth Experience Bar.
