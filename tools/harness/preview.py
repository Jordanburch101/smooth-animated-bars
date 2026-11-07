"""Preview the liquid in the player frame's health and power bars, through damage, power gains and a heal.

Usage: python preview.py <addon dir> <out dir> [setting=value ...]
e.g.   python preview.py SmoothAnimatedBars preview healthColor=fire powerColor=game
Writes preview.gif and sheet.png (stills at key moments).

The client places the liquid from the bars' secret values and cuts it with the bars' masks; the mock
does neither. So the liquid frames are drawn here at a simulated fill edge, easing like the client's
smoothing, and cropped to the bar.
"""
import math
import os
import sys

from PIL import Image

import render

ADDON, OUT = sys.argv[1], sys.argv[2]
SETTINGS = dict(arg.split("=", 1) for arg in sys.argv[3:])
K = 4             # px per bar unit
W = 124           # Forever's player bars: 124x20 health, 124x10 power
HEALTH_H, POWER_H = 20, 10
POWER = SETTINGS.pop("power", "1")  # UnitPowerType index: 0 mana, 1 rage, 3 energy

# (time, health fraction, power fraction); the bars ease toward the latest.
KEYS = [(0, 1.0, 0.1), (1.0, 0.55, 0.1), (1.6, 0.55, 0.35), (2.4, 0.35, 0.35), (3.0, 0.35, 0.52),
        (4.0, 1.0, 0.52), (5.0, 1.0, 0.22)]
STILLS = (0.9, 1.15, 1.75, 4.15, 5.9)
CHANGED = "__fire('UNIT_HEALTH', 'player'); __fire('UNIT_POWER_UPDATE', 'player')"

session = render.Session(ADDON, settings=SETTINGS, scenario=[(t, CHANGED) for t, _, _ in KEYS[1:]],
                         before_login=f"__player.power = {POWER}", after_login="""
    for _, b in ipairs({ PlayerFrame.healthbar, PlayerFrame.manabar }) do
        b:SetMinMaxValues(0, __secret()); b:SetValue(__secret())
    end
    local function mover(bar)
        for _, clip in ipairs(__frames) do
            if clip.parent == bar and not clip.SetValue and clip.clipsChildren then
                for _, f in ipairs(__frames) do
                    if f.parent == clip then return f end
                end
            end
        end
    end
    __healthMover, __powerMover = mover(PlayerFrame.healthbar), mover(PlayerFrame.manabar)
    -- The client sizes these from their anchors, and the bar masks have no art in the mock.
    __healthMover.h, __powerMover.h = 20, 10
    for _, r in ipairs(__regions) do r.masks = nil end
""")

W_IMG, H_IMG = W * K + 80, 34 * K + 60
BACKGROUND = Image.new("RGB", (W_IMG, H_IMG), (40, 34, 22))


def draw(img, frame, frac, top, h):
    """The liquid frame with its right edge at the fill's edge, cropped to the bar."""
    session.frame = frame
    full = session.render(img, 40 + (frac * W - W) * K, top, K)
    box = (40, top, 40 + W * K, top + h * K)
    out = img.copy()
    out.paste(full.crop(box), box[:2])
    return out


os.makedirs(OUT, exist_ok=True)
fills = [KEYS[0][1], KEYS[0][2]]
frames, stills = [], {}
t, dt = 0.0, 1 / 20
while t < 6.0:
    session.run_until(t)
    goal = [k for k in KEYS if k[0] <= t][-1]
    for i in (0, 1):
        fills[i] += (goal[i + 1] - fills[i]) * (1 - math.exp(-8 * dt))
    img = draw(BACKGROUND, "__healthMover", fills[0], 30, HEALTH_H)
    img = draw(img, "__powerMover", fills[1], 30 + 22 * K, POWER_H)
    frames.append(img)
    for st in STILLS:
        if abs(t - st) < dt / 2:
            stills[st] = img
    t += dt
frames[0].save(os.path.join(OUT, "preview.gif"), save_all=True, append_images=frames[1:], duration=50, loop=0)
sheet = Image.new("RGB", (W_IMG, H_IMG * len(stills)))
for i, st in enumerate(sorted(stills)):
    sheet.paste(stills[st], (0, i * H_IMG))
sheet.save(os.path.join(OUT, "sheet.png"))
print("wrote", os.path.join(OUT, "preview.gif"), "and sheet.png")
