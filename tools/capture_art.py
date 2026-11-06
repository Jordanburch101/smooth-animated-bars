"""Cut Forever's unit frame art out of the two screenshots /sab capture takes (see Capture.lua).

Usage: python capture_art.py [screenshots dir] [out dir]
Defaults: the Forever client's Screenshots folder, and branding/art.

The newest two TGA screenshots are the grid on black and then on white. A pixel drawn with colour c
and opacity a over black shows a*c, over white a*c + (1 - a), so a = 1 - (white - black) and
c = black / a. Two red squares mark the grid; their centres are 1000 grid units apart, which gives the
scale. Writes one RGBA PNG per cell (232 x 100 grid units, at the screenshots' pixels per unit) and
art.json with that scale.
"""
import glob
import json
import os
import sys

import numpy as np
from PIL import Image

SHOTS = sys.argv[1] if len(sys.argv) > 1 else r"C:\Program Files (x86)\World of Warcraft\_forever_\Screenshots"
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                                                         "branding", "art")

# Must match Capture.lua.
CELLS = ["player-art", "player-portrait", "player-circle", "player-health-mask",
         "player-power-mask", "target-art", "target-portrait", "target-circle",
         "target-banner", "target-health-mask", "target-power-mask"]
CELL_W, CELL_H, STEP_X, STEP_Y = 232, 100, 252, 120
MARK_CENTRE = (11, 11)  # the first square's centre, grid units right and down from the corner
MARK_APART = 1000


def load(path):
    return np.asarray(Image.open(path).convert("RGB")).astype(np.float64) / 255


def markers(black):
    """Centres of the two red squares, left then right, in pixels. They end 14 grid units down and
    the grid is scaled to fit 420 units in the screen's height, so only the top 1/25 of the screen is
    searched: the target's red question mark portrait lies further down."""
    top = black[:max(1, black.shape[0] // 25)]
    red = (top[..., 0] > 0.8) & (top[..., 1] < 0.25) & (top[..., 2] < 0.25)
    ys, xs = np.nonzero(red)
    if len(xs) == 0:
        sys.exit("No red markers in the black screenshot: is it the /sab capture one?")
    mid = (xs.min() + xs.max()) / 2
    left, right = xs < mid, xs >= mid
    if not left.any() or not right.any():
        sys.exit("Found only one red marker.")
    return (xs[left].mean(), ys[left].mean()), (xs[right].mean(), ys[right].mean())


def main():
    shots = sorted(glob.glob(os.path.join(SHOTS, "*.tga")), key=os.path.getmtime)
    if len(shots) < 2:
        sys.exit(f"Need two TGA screenshots in {SHOTS}; run /sab capture in game first.")
    black_path, white_path = shots[-2], shots[-1]
    black, white = load(black_path), load(white_path)
    if black.shape != white.shape:
        sys.exit("The two screenshots differ in size.")
    if black[2:6, 2:6].mean() > 0.1 or white[2:6, 2:6].mean() < 0.9:
        sys.exit(f"Expected the black shot then the white one:\n  {black_path}\n  {white_path}")

    (x1, y1), (x2, _) = markers(black)
    ppu = (x2 - x1) / MARK_APART
    print(f"black {os.path.basename(black_path)}, white {os.path.basename(white_path)}: {ppu:.3f} px per unit")

    alpha = np.clip(1 - (white - black).mean(axis=2), 0, 1)
    color = np.clip(black / np.maximum(alpha, 1e-3)[..., None], 0, 1)
    rgba = np.dstack([color, alpha])

    os.makedirs(OUT, exist_ok=True)
    w, h = round(CELL_W * ppu), round(CELL_H * ppu)
    for i, name in enumerate(CELLS):
        gx, gy = 20 + i % 4 * STEP_X, 40 + i // 4 * STEP_Y
        left = round(x1 + (gx - MARK_CENTRE[0]) * ppu)
        top = round(y1 + (gy - MARK_CENTRE[1]) * ppu)
        cell = rgba[top:top + h, left:left + w]
        Image.fromarray((cell * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(OUT, name + ".png"))
    with open(os.path.join(OUT, "art.json"), "w", encoding="utf-8") as f:
        json.dump({"ppu": ppu, "cell": [CELL_W, CELL_H], "cells": CELLS}, f, indent=2)
    print(f"wrote {len(CELLS)} pieces ({w}x{h} px each) and art.json to {OUT}")


if __name__ == "__main__":
    main()
