"""Gallery images: the liquid in Forever's player and target frames, drawn on the game's own frame art.

Usage: python gallery.py <addon dir> [out dir]
Default out dir: branding/gallery. Writes hero.gif (both frames through hits, heals and power changes),
frames.png (a still of it) and themes.png (the player frame in a few themes).

The frame art comes from branding/art, which tools/capture_art.py cuts out of the screenshots /sab
capture takes in game (Capture.lua). The liquid is the addon itself running against the mock: as in
the client, its frame ends at the bar's fill edge (simulated here, easing as the client's smoothing
does), the captured bar masks cut it to shape, and motes fly free within the clip frame's reach.
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

import render

ADDON = sys.argv[1]
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, "branding", "gallery")
ART = os.path.join(ROOT, "branding", "art")
K = 2.0       # px per frame unit
FPS = 15
SPILL = 16    # Bars.lua: how far motes fly past a bar
FRAME_W, FRAME_H = 232, 100

# Forever's layout, as SmoothAnimatedBars/Preview.lua has it (LAYOUT), with y measured down.
BARS = {
    ("player", "health"): (87, 43, 124, 20), ("player", "power"): (87, 61, 124, 10),
    ("target", "health"): (21, 41, 126, 20), ("target", "power"): (17, 60, 134, 10),
}
NAMES = {"player": ((149, 37), "Hollywood Hootsman"), "target": ((82.5, 36), "Defias Pillager")}
BANNER = (0.8, 0.1, 0.1)  # the target's name banner, hostile
LEVEL = "12"
MAXES = {("player", "health"): 349, ("player", "power"): 100, ("target", "health"): 210, ("target", "power"): 350}

# The wizard preview's loop (Preview.lua SCRIPT): seconds, player health and power, target health and power.
SCRIPT = [
    (0.0, 1.00, 0.10, 1.00, 0.90), (1.2, 0.72, 0.30, 0.80, 0.90), (2.2, 0.72, 0.30, 0.55, 0.75),
    (3.0, 0.48, 0.55, 0.55, 0.75), (4.0, 0.48, 0.25, 0.25, 0.60), (5.0, 0.85, 0.25, 0.25, 0.60),
    (6.0, 0.85, 0.50, 0.00, 0.60), (7.2, 1.00, 0.10, 1.00, 0.90),
]
LOOP = 8.4
ORDER = [("player", "health"), ("player", "power"), ("target", "health"), ("target", "power")]


# ---------------------------------------------------------------------------- art

def resize_rgba(im, size):
    """Resize with premultiplied alpha, so transparent edges keep no dark fringe."""
    a = np.asarray(im).astype(np.float32) / 255
    pre = np.dstack([a[..., :3] * a[..., 3:], a[..., 3:]])
    out = [np.asarray(Image.fromarray(pre[..., i]).resize(size, Image.LANCZOS)) for i in range(4)]
    out = np.clip(np.dstack(out), 0, 1)
    rgb = np.where(out[..., 3:] > 1e-4, out[..., :3] / np.maximum(out[..., 3:], 1e-4), 0)
    return Image.fromarray((np.dstack([np.clip(rgb, 0, 1), out[..., 3:]]) * 255 + 0.5).astype(np.uint8), "RGBA")


def load_art():
    if not os.path.exists(os.path.join(ART, "art.json")):
        sys.exit(f"No frame art in {ART}: run /sab capture in game, then tools/capture_art.py.")
    size = (round(FRAME_W * K), round(FRAME_H * K))
    art = {}
    for name in json.load(open(os.path.join(ART, "art.json"), encoding="utf-8"))["cells"]:
        art[name] = resize_rgba(Image.open(os.path.join(ART, name + ".png")).convert("RGBA"), size)
    # Tint the banner as the game does for a hostile target.
    b = np.asarray(art["target-banner"]).astype(np.float32)
    b[..., :3] *= np.array(BANNER, np.float32)
    art["target-banner"] = Image.fromarray(b.astype(np.uint8), "RGBA")
    return art


def circle_centre(art, which):
    """The level circle's centre in frame units, from where its art is."""
    a = np.asarray(art[which + "-circle"])[..., 3]
    ys, xs = np.nonzero(a > 128)
    return (xs.min() + xs.max()) / 2 / K, (ys.min() + ys.max()) / 2 / K


# ---------------------------------------------------------------------------- the addon

def start(settings):
    """The addon in the mock with its four bars sized as Forever's, the player on rage and the target
    on mana; returns the session and each bar's liquid frame's global name."""
    before = """
        SmoothAnimatedBarsDB.setupDone = true
        TargetFrame.healthbar.w, TargetFrame.manabar.w = 126, 134
        UnitPowerType = function(unit) if unit == 'target' then return 0, 'MANA' end return 1, 'RAGE' end
        for _, b in ipairs({ PlayerFrame.healthbar, PlayerFrame.manabar, TargetFrame.healthbar, TargetFrame.manabar }) do
            b:SetMinMaxValues(0, __secret()); b:SetValue(__secret())
        end
    """
    after = """
        local bars = { player_health = PlayerFrame.healthbar, player_power = PlayerFrame.manabar,
                       target_health = TargetFrame.healthbar, target_power = TargetFrame.manabar }
        for key, bar in pairs(bars) do
            for _, clip in ipairs(__frames) do
                if clip.parent == bar and not clip.SetValue then
                    for _, f in ipairs(__frames) do
                        if f.parent == clip then
                            _G['__mover_' .. key] = f
                            f.w, f.h = bar.w, bar.h -- the client sizes it from its anchors
                        end
                    end
                end
            end
        end
        -- The bar masks have no art in the mock; the captured ones are applied here instead.
        for _, r in ipairs(__regions) do r.masks = nil end
    """
    session = render.Session(ADDON, settings=settings, before_login=before, after_login=after)
    return session


def is_mote(r):
    return r.layer == "OVERLAY" and r.sub == 4


def draw_bar(session, img, art, fx, fy, which, kind, frac):
    """The liquid of one bar onto img (RGB), the frame's top-left at (fx, fy) px."""
    x, y, w, h = BARS[(which, kind)]
    # Work on the bar's surroundings only: the bar, and the room motes have around it.
    sx, sy = int(fx + (x - 4) * K), int(fy + (y - SPILL) * K)
    sw, sh = int((w + SPILL + 8) * K), int((h + 2 * SPILL) * K)
    sub = img.crop((sx, sy, sx + sw, sy + sh))
    session.frame = f"__mover_{which}_{kind}"
    ox, oy = fx + (x + frac * w - w) * K - sx, fy + y * K - sy
    liquid = session.render(sub, ox, oy, K, only=lambda r: not is_mote(r))
    # The captured mask covers the whole frame, from its top-left.
    mask = Image.new("L", (sw, sh), 0)
    mask.paste(art[f"{which}-{kind}-mask"].getchannel("A"), (int(fx) - sx, int(fy) - sy))
    m = np.asarray(mask).astype(np.float32) / 255
    a, b = np.asarray(sub).astype(np.float32), np.asarray(liquid).astype(np.float32)
    sub = Image.fromarray((a + (b - a) * m[..., None]).astype(np.uint8))
    # Motes, cut only by the clip frame: from the bar's left edge to SPILL past its end.
    motes = session.render(sub, ox, oy, K, only=is_mote)
    clip = np.zeros((sh, sw), np.float32)
    clip[:, int(4 * K):] = 1
    a, b = np.asarray(sub).astype(np.float32), np.asarray(motes).astype(np.float32)
    sub = Image.fromarray((a + (b - a) * clip[..., None]).astype(np.uint8))
    img.paste(sub, (sx, sy))


def text(draw, x, y, s, size, color, outline):
    f = render.font(size * K)
    if outline:
        draw.text((x, y), s, font=f, fill=color, anchor="mm", stroke_width=max(1, round(K * 0.6)),
                  stroke_fill=(0, 0, 0))
    else:
        draw.text((x + K, y + K), s, font=f, fill=(0, 0, 0), anchor="mm")
        draw.text((x, y), s, font=f, fill=color, anchor="mm")


def draw_frame(session, img, art, fx, fy, which, fills, values):
    """A whole frame onto img (RGB): art, liquid, then the level circle and text above them."""
    canvas = img.convert("RGBA")
    for piece in ("portrait", "art") + (("banner",) if which == "target" else ()):
        canvas.alpha_composite(art[f"{which}-{piece}"], (int(fx), int(fy)))
    img.paste(canvas.convert("RGB"))
    for kind in ("health", "power"):
        draw_bar(session, img, art, fx, fy, which, kind, fills[(which, kind)])
    canvas = img.convert("RGBA")
    canvas.alpha_composite(art[f"{which}-circle"], (int(fx), int(fy)))
    img.paste(canvas.convert("RGB"))
    draw = ImageDraw.Draw(img)
    (nx, ny), name = NAMES[which]
    text(draw, fx + nx * K, fy + ny * K, name, 10, (255, 209, 0), False)
    cx, cy = circle_centre(art, which)
    text(draw, fx + cx * K, fy + (cy + 0.5) * K, LEVEL, 13, (255, 255, 255), True)
    for kind in ("health", "power"):
        x, y, w, h = BARS[(which, kind)]
        v = values[(which, kind)]
        text(draw, fx + (x + w / 2) * K, fy + (y + h / 2) * K, f"{v} / {MAXES[(which, kind)]}", 10,
             (255, 255, 255), True)


# ---------------------------------------------------------------------------- scenes

def backdrop(w, h):
    """A dusky stone-blue backdrop with a soft vignette."""
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    t = yy / max(1, h - 1)
    top, bottom = np.array([46, 52, 66], np.float32), np.array([24, 26, 34], np.float32)
    img = top + (bottom - top) * t[..., None]
    d = np.hypot((xx - w / 2) / (w / 2), (yy - h / 2) / (h / 2))
    img *= (1 - 0.35 * np.clip(d - 0.4, 0, 1))[..., None]
    return Image.fromarray(img.astype(np.uint8))


def loop_values(t):
    row = [r for r in SCRIPT if r[0] <= t][-1]
    return dict(zip(ORDER, row[1:]))


def hero(art):
    """Both frames through the loop: hero.gif and a still, frames.png."""
    session = start({})
    pad, gap = round(24 * K), round(30 * K)
    w, h = pad * 2 + gap + round(FRAME_W * K) * 2, pad * 2 + round(FRAME_H * K)
    back = backdrop(w, h)
    spots = {"player": (pad, pad), "target": (pad + gap + round(FRAME_W * K), pad)}
    fills = dict(loop_values(0))
    frames, still = [], None
    shown = loop_values(0)
    t, dt = 0.0, 1 / FPS
    while t < LOOP - 1e-9:
        goal = loop_values(t)
        for key in ORDER:
            if goal[key] != shown[key]:
                which, kind = key
                event = "UNIT_HEALTH" if kind == "health" else "UNIT_POWER_UPDATE"
                session.lua.execute(f"__fire('{event}', '{which}')")
                if which == "target" and goal[key] > shown[key] + 0.5:  # a new target: no easing
                    fills[key] = goal[key]
        shown = goal
        session.run_until(t)
        for key in ORDER:
            fills[key] += (goal[key] - fills[key]) * (1 - math.exp(-8 * dt))
        values = {key: round(goal[key] * MAXES[key]) for key in ORDER}
        img = back.copy()
        for which, (fx, fy) in spots.items():
            draw_frame(session, img, art, fx, fy, which, fills, values)
        frames.append(img)
        if still is None and t >= 3.3:
            still = img
        t += dt
    os.makedirs(OUT, exist_ok=True)
    pal = [f.quantize(colors=255, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE) for f in frames]
    pal[0].save(os.path.join(OUT, "hero.gif"), save_all=True, append_images=pal[1:], duration=round(1000 / FPS),
                loop=0, optimize=True)
    still.save(os.path.join(OUT, "frames.png"))
    print("wrote hero.gif and frames.png")


THEMES = ["game", "class", "fire", "frost", "arcane", "fel", "cosmic", "void"]


def themes(art):
    """The player frame in a few health colours, mid-fight: themes.png."""
    cols, cell_w, cell_h = 2, round((FRAME_W + 20) * K), round((FRAME_H + 22) * K)
    rows = math.ceil(len(THEMES) / cols)
    pad = round(12 * K)
    sheet = backdrop(pad * 2 + cols * cell_w, pad * 2 + rows * cell_h)
    draw = ImageDraw.Draw(sheet)
    for i, key in enumerate(THEMES):
        session = start({"healthColor": key})
        fills = {("player", "health"): 0.68, ("player", "power"): 0.45,
                 ("target", "health"): 1, ("target", "power"): 1}
        session.run_until(2.5)
        session.lua.execute("__fire('UNIT_HEALTH', 'player'); __fire('UNIT_POWER_UPDATE', 'player')")
        session.run_until(2.8)
        values = {k: round(v * MAXES[k]) for k, v in fills.items()}
        fx = pad + (i % cols) * cell_w
        fy = pad + (i // cols) * cell_h
        draw_frame(session, sheet, art, fx, fy + 12 * K, "player", fills, values)
        text(draw, fx + 116 * K, fy + 8 * K, THEME_NAMES.get(key, key.title()), 10, (230, 230, 240), False)
    sheet.save(os.path.join(OUT, "themes.png"))
    print("wrote themes.png")


THEME_NAMES = {"game": "Game Colour", "class": "Class Color"}


if __name__ == "__main__":
    art = load_art()
    hero(art)
    themes(art)
