"""Gallery images: the liquid in Forever's player and target frames, drawn on the game's own frame art.

Usage: python gallery.py <addon dir> [out dir] [scenario ...]
Default out dir: branding/gallery. Writes each scenario as an animated WebP (hero is the warrior, then
mage and rogue), frames.png (a still of the warrior) and themes.png (the player frame in a few themes).
A full run takes about a quarter of an hour.

The frame art comes from branding/art, which tools/capture_art.py cuts out of the screenshots /sab
capture takes in game (Capture.lua); a scenario's portrait is portrait-<scenario>.png there, captured on
that character with --portrait, else the capturing character's. The liquid is the addon itself running
against the mock: as in the client, its frame ends at the bar's fill edge (simulated here, easing as
the client's smoothing does), the captured bar masks cut it to shape, and motes fly free within the
clip frame's reach.
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
ONLY = sys.argv[3:]
ART = os.path.join(ROOT, "branding", "art")
K = 3.0       # px per frame unit; the captured art has about 3.27
FPS = 20
SPILL = 16    # Bars.lua: how far motes fly past a bar
FRAME_W, FRAME_H = 232, 100

# Forever's layout, as SmoothAnimatedBars/Preview.lua has it (LAYOUT), with y measured down.
BARS = {
    ("player", "health"): (87, 43, 124, 20), ("player", "power"): (87, 61, 124, 10),
    ("target", "health"): (21, 41, 126, 20), ("target", "power"): (17, 60, 134, 10),
}
NAME_AT = {"player": (149, 37), "target": (82.5, 36)}
BANNER = (0.8, 0.1, 0.1)  # the target's name banner, hostile
ORDER = [("player", "health"), ("player", "power"), ("target", "health"), ("target", "power")]
POWER = {"MANA": 0, "RAGE": 1, "FOCUS": 2, "ENERGY": 3}

# Each scenario: the player (name, level, power type), the target, bar maxima (player health and
# power, target health and power), and a loop of { seconds, the four bars as fractions }. A new
# target comes in at full health.
SCENARIOS = {
    # Rage builds as blows land and is spent on strikes.
    "hero": dict(
        player="Hollywood Hootsman", level="12", power="RAGE", target="Defias Pillager", target_level="12",
        maxes=(349, 100, 210, 350), loop=8.4,
        script=[(0.0, 1.00, 0.10, 1.00, 0.90), (1.2, 0.72, 0.30, 0.80, 0.90), (2.2, 0.72, 0.30, 0.55, 0.75),
                (3.0, 0.48, 0.55, 0.55, 0.75), (4.0, 0.48, 0.25, 0.25, 0.60), (5.0, 0.85, 0.25, 0.25, 0.60),
                (6.0, 0.85, 0.50, 0.00, 0.60), (7.2, 1.00, 0.10, 1.00, 0.90)]),
    # Each Fireball takes a big bite of mana and of the target; the kobold gets one swing in.
    "mage": dict(
        player="Mailbox Hootsman", level="12", power="MANA", target="Kobold Geomancer", target_level="11",
        maxes=(232, 420, 198, 320), loop=8.0,
        script=[(0.0, 1.00, 1.00, 1.00, 1.00), (1.5, 1.00, 0.86, 0.68, 1.00), (2.4, 1.00, 0.86, 0.68, 0.88),
                (3.0, 1.00, 0.72, 0.36, 0.88), (3.6, 0.84, 0.72, 0.36, 0.88), (4.5, 0.84, 0.58, 0.06, 0.88),
                (5.2, 0.84, 0.52, 0.00, 0.88), (6.4, 0.84, 0.52, 1.00, 1.00), (7.0, 0.90, 0.60, 1.00, 1.00)]),
    # Energy ticks back 20 every two seconds; Sinister Strike spends 40, Eviscerate 35.
    "rogue": dict(
        player="Hotdog Rouge", level="12", power="ENERGY", target="Defias Footpad", target_level="12",
        maxes=(258, 100, 214, 280), loop=8.4,
        script=[(0.0, 1.00, 1.00, 1.00, 0.70), (0.4, 1.00, 0.60, 0.86, 0.70), (1.2, 1.00, 0.20, 0.72, 0.70),
                (1.6, 0.91, 0.20, 0.72, 0.70), (2.0, 0.91, 0.40, 0.72, 0.70), (2.6, 0.83, 0.40, 0.72, 0.70),
                (4.0, 0.83, 0.60, 0.72, 0.70), (4.2, 0.83, 0.25, 0.42, 0.70), (5.0, 0.76, 0.25, 0.42, 0.70),
                (6.0, 0.76, 0.45, 0.42, 0.70), (6.4, 0.76, 0.05, 0.00, 0.70), (7.4, 0.76, 0.05, 1.00, 0.70),
                (8.0, 0.76, 0.25, 1.00, 0.70)]),
}


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
    names = json.load(open(os.path.join(ART, "art.json"), encoding="utf-8"))["cells"]
    names += [f[:-4] for f in os.listdir(ART) if f.startswith("portrait-") and f.endswith(".png")]
    art = {name: resize_rgba(Image.open(os.path.join(ART, name + ".png")).convert("RGBA"), size) for name in names}
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

def start(settings, power="RAGE"):
    """The addon in the mock with its four bars sized as Forever's, the player on the given power type
    and the target on mana; returns the session. Each bar's liquid frame becomes __mover_<unit>_<kind>."""
    before = f"""
        SmoothAnimatedBarsDB.setupDone = true
        TargetFrame.healthbar.w, TargetFrame.manabar.w = 126, 134
        UnitPowerType = function(unit)
            if unit == 'target' then return 0, 'MANA' end
            return {POWER[power]}, '{power}'
        end
        for _, b in ipairs({{ PlayerFrame.healthbar, PlayerFrame.manabar, TargetFrame.healthbar, TargetFrame.manabar }}) do
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
    return render.Session(ADDON, settings=settings, before_login=before, after_login=after)


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


def draw_frame(session, img, art, fx, fy, which, fills, values, sc, portrait):
    """A whole frame onto img (RGB): art, liquid, then the level circle and text above them."""
    canvas = img.convert("RGBA")
    pieces = [portrait if which == "player" else "target-portrait", f"{which}-art"]
    if which == "target":
        pieces.append("target-banner")
    for piece in pieces:
        canvas.alpha_composite(art[piece], (int(fx), int(fy)))
    img.paste(canvas.convert("RGB"))
    for kind in ("health", "power"):
        draw_bar(session, img, art, fx, fy, which, kind, fills[(which, kind)])
    canvas = img.convert("RGBA")
    canvas.alpha_composite(art[f"{which}-circle"], (int(fx), int(fy)))
    img.paste(canvas.convert("RGB"))
    draw = ImageDraw.Draw(img)
    nx, ny = NAME_AT[which]
    text(draw, fx + nx * K, fy + ny * K, sc["player"] if which == "player" else sc["target"], 10, (255, 209, 0), False)
    cx, cy = circle_centre(art, which)
    level = sc["level"] if which == "player" else sc["target_level"]
    text(draw, fx + cx * K, fy + (cy + 0.5) * K, level, 13, (255, 255, 255), True)
    maxes = dict(zip(ORDER, sc["maxes"]))
    for kind in ("health", "power"):
        x, y, w, h = BARS[(which, kind)]
        text(draw, fx + (x + w / 2) * K, fy + (y + h / 2) * K, f"{values[(which, kind)]} / {maxes[(which, kind)]}",
             10, (255, 255, 255), True)


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


def portrait_for(art, key):
    """The warrior is the character the frame art was captured on, so its portrait is player-portrait."""
    name = f"portrait-{key}"
    if name in art:
        return name
    if key == "hero":
        return "player-portrait"
    print(f"  no {name}.png yet: using the capturing character's portrait")
    return "player-portrait"


def scenario(art, key):
    """Both frames through a scenario's loop, as a GIF; the warrior's also gives frames.png."""
    sc = SCENARIOS[key]
    session = start({}, sc["power"])
    portrait = portrait_for(art, key)
    pad, gap = round(24 * K), round(30 * K)
    w, h = pad * 2 + gap + round(FRAME_W * K) * 2, pad * 2 + round(FRAME_H * K)
    back = backdrop(w, h)
    spots = {"player": (pad, pad), "target": (pad + gap + round(FRAME_W * K), pad)}
    maxes = dict(zip(ORDER, sc["maxes"]))

    def at(t):
        row = [r for r in sc["script"] if r[0] <= t][-1]
        return dict(zip(ORDER, row[1:]))

    fills, shown = dict(at(0)), at(0)
    frames, still = [], None
    t, dt = 0.0, 1 / FPS
    while t < sc["loop"] - 1e-9:
        goal = at(t)
        for k in ORDER:
            if goal[k] != shown[k]:
                which, kind = k
                event = "UNIT_HEALTH" if kind == "health" else "UNIT_POWER_UPDATE"
                session.lua.execute(f"__fire('{event}', '{which}')")
                if which == "target" and kind == "health" and goal[k] > shown[k] + 0.5:
                    fills[k] = goal[k]  # a new target: its bar does not ease up
        shown = goal
        session.run_until(t)
        for k in ORDER:
            fills[k] += (goal[k] - fills[k]) * (1 - math.exp(-8 * dt))
        values = {k: round(goal[k] * maxes[k]) for k in ORDER}
        img = back.copy()
        for which, (fx, fy) in spots.items():
            draw_frame(session, img, art, fx, fy, which, fills, values, sc, portrait)
        frames.append(img)
        if key == "hero" and still is None and t >= 3.3:
            still = img
        t += dt
    os.makedirs(OUT, exist_ok=True)
    # An animated WebP: full colour, so no banding in the liquid as in a GIF's 256.
    webp = os.path.join(OUT, key + ".webp")
    frames[0].save(webp, save_all=True, append_images=frames[1:], duration=round(1000 / FPS), loop=0,
                   quality=92, method=6)
    print(f"wrote {key}.webp ({os.path.getsize(webp) // 1024} KB)")
    if still is not None:
        still.save(os.path.join(OUT, "frames.png"))
        print("wrote frames.png")


THEMES = ["game", "class", "fire", "frost", "arcane", "fel", "cosmic", "void"]
THEME_NAMES = {"game": "Game Colour", "class": "Class Color"}


def themes(art):
    """The warrior's frame in a few health colours, mid-fight: themes.png."""
    sc = SCENARIOS["hero"]
    cols, cell_w, cell_h = 2, round((FRAME_W + 20) * K), round((FRAME_H + 22) * K)
    rows = math.ceil(len(THEMES) / cols)
    pad = round(12 * K)
    sheet = backdrop(pad * 2 + cols * cell_w, pad * 2 + rows * cell_h)
    draw = ImageDraw.Draw(sheet)
    maxes = dict(zip(ORDER, sc["maxes"]))
    for i, key in enumerate(THEMES):
        session = start({"healthColor": key}, sc["power"])
        fills = {("player", "health"): 0.68, ("player", "power"): 0.45,
                 ("target", "health"): 1, ("target", "power"): 1}
        session.run_until(2.5)
        session.lua.execute("__fire('UNIT_HEALTH', 'player'); __fire('UNIT_POWER_UPDATE', 'player')")
        session.run_until(2.8)
        values = {k: round(v * maxes[k]) for k, v in fills.items()}
        fx = pad + (i % cols) * cell_w
        fy = pad + (i // cols) * cell_h
        draw_frame(session, sheet, art, fx, fy + 12 * K, "player", fills, values, sc, portrait_for(art, "hero"))
        text(draw, fx + 116 * K, fy + 8 * K, THEME_NAMES.get(key, key.title()), 10, (230, 230, 240), False)
    sheet.save(os.path.join(OUT, "themes.png"))
    print("wrote themes.png")


if __name__ == "__main__":
    art = load_art()
    for key in SCENARIOS:
        if not ONLY or key in ONLY:
            scenario(art, key)
    if not ONLY or "themes" in ONLY:
        themes(art)
