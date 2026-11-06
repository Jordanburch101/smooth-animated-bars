"""Cut Forever's unit frame art out of the two screenshots /sab capture takes (see Capture.lua).

Usage: python capture_art.py [--portrait NAME] [--pair N] [screenshots dir] [out dir]
Defaults: the Forever client's Screenshots folder, and branding/art.

  --portrait NAME  keep only the player's portrait, as portrait-NAME.png: for gallery scenarios with
                   another character (capture on that character)
  --pair N         use the Nth newest pair of screenshots (default 1), so several characters can be
                   captured one after another and cut out afterwards

A pair is the grid on black and then on white. A pixel drawn with colour c and opacity a over black
shows a*c, over white a*c + (1 - a), so a = 1 - (white - black) and c = black / a. Two red squares
mark the grid; their centres are 1000 grid units apart, which gives the scale. Writes one RGBA PNG per
cell (232 x 100 grid units, at the screenshots' pixels per unit) and art.json with that scale.
"""
import argparse
import glob
import json
import os

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Must match Capture.lua.
CELLS = ["player-art", "player-portrait", "player-circle", "player-health-mask",
         "player-power-mask", "target-art", "target-portrait", "target-circle",
         "target-banner", "target-health-mask", "target-power-mask", "target-killicon"]
CELL_W, CELL_H, STEP_X, STEP_Y = 232, 100, 252, 120
# Cells that only need part of their area, as (left, top, right, bottom) grid units within the cell; the rest
# is cleared. The kill icon sits on the target's portrait (centre 177, 48) in the grid's bottom-right cell,
# where the game's tooltip shows if the mouse rests on something during the capture.
KEEP = {"target-killicon": (177 - 30, 48 - 30, 177 + 30, 48 + 30)}
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
        raise SystemExit("No red markers in the black screenshot: is it the /sab capture one?")
    mid = (xs.min() + xs.max()) / 2
    left, right = xs < mid, xs >= mid
    if not left.any() or not right.any():
        raise SystemExit("Found only one red marker.")
    return (xs[left].mean(), ys[left].mean()), (xs[right].mean(), ys[right].mean())


def main():
    parser = argparse.ArgumentParser(description="Cut the /sab capture screenshots into frame art.")
    parser.add_argument("shots", nargs="?", default=r"C:\Program Files (x86)\World of Warcraft\_forever_\Screenshots")
    parser.add_argument("out", nargs="?", default=os.path.join(ROOT, "branding", "art"))
    parser.add_argument("--portrait", help="keep only the player's portrait, as portrait-NAME.png")
    parser.add_argument("--pair", type=int, default=1, help="the Nth newest pair of screenshots")
    args = parser.parse_args()

    shots = sorted(glob.glob(os.path.join(args.shots, "*.tga")), key=os.path.getmtime)
    if len(shots) < 2 * args.pair:
        raise SystemExit(f"Need {2 * args.pair} TGA screenshots in {args.shots}; run /sab capture in game first.")
    end = len(shots) - 2 * (args.pair - 1)
    black_path, white_path = shots[end - 2], shots[end - 1]
    black, white = load(black_path), load(white_path)
    if black.shape != white.shape:
        raise SystemExit("The two screenshots differ in size.")
    if black[2:6, 2:6].mean() > 0.1 or white[2:6, 2:6].mean() < 0.9:
        raise SystemExit(f"Expected the black shot then the white one:\n  {black_path}\n  {white_path}")

    (x1, y1), (x2, _) = markers(black)
    ppu = (x2 - x1) / MARK_APART
    print(f"black {os.path.basename(black_path)}, white {os.path.basename(white_path)}: {ppu:.3f} px per unit")

    alpha = np.clip(1 - (white - black).mean(axis=2), 0, 1)
    color = np.clip(black / np.maximum(alpha, 1e-3)[..., None], 0, 1)
    rgba = np.dstack([color, alpha])

    os.makedirs(args.out, exist_ok=True)
    w, h = round(CELL_W * ppu), round(CELL_H * ppu)
    wanted = ["player-portrait"] if args.portrait else CELLS
    for i, name in enumerate(CELLS):
        if name not in wanted:
            continue
        gx, gy = 20 + i % 4 * STEP_X, 40 + i // 4 * STEP_Y
        left = round(x1 + (gx - MARK_CENTRE[0]) * ppu)
        top = round(y1 + (gy - MARK_CENTRE[1]) * ppu)
        piece = rgba[top:top + h, left:left + w].copy()
        if name in KEEP:
            x0, y0, x1, y1 = (round(v * ppu) for v in KEEP[name])
            keep = np.zeros(piece.shape[:2], bool)
            keep[y0:y1, x0:x1] = True
            piece[~keep] = 0
        cell = Image.fromarray((piece * 255 + 0.5).astype(np.uint8), "RGBA")
        file = f"portrait-{args.portrait}.png" if args.portrait else name + ".png"
        cell.save(os.path.join(args.out, file))
        print("wrote", file)
    if not args.portrait:
        with open(os.path.join(args.out, "art.json"), "w", encoding="utf-8") as f:
            json.dump({"ppu": ppu, "cell": [CELL_W, CELL_H], "cells": CELLS}, f, indent=2)
        print(f"wrote art.json ({w}x{h} px per piece) to {args.out}")


if __name__ == "__main__":
    main()
