# Branding

The addon icon is the game icon `inv_enchant_essencenetherlarge`, Greater Nether Essence (file ID 132870,
https://www.wowhead.com/icon=132870/inv-enchant-essencenetherlarge). The toc shows it by file ID.

- `icon-original-64.png` - the game's 64x64 BLP converted losslessly, border included
  (https://wago.tools/api/casc/132870). 64x64 is the largest size the game has.
- `smooth-animated-bars-54.png` - the original with the game border cropped off (5 px: at 4 px the
  border's grey still shows in the corners), lossless. Use this (or the upscales) for CurseForge and other
  listings.
- `smooth-animated-bars-64.png`, `-128.png`, `-256.png` - upscaled from the 54px crop (Lanczos).
- `../public/favicon.ico` - the borderless 64 at 16, 32, 48 and 64 px.

## Art and gallery

`art/` is Forever's unit frame art, captured in game, and `gallery/` the README's images rendered from it
by `tools/harness/gallery.py`. Both are only for the README and listings, never packaged; see
[docs/DEVELOPMENT.md](../docs/DEVELOPMENT.md).
