"""Gallery images: the liquid in Forever's player and target frames, drawn on the game's own frame art.

Usage: python gallery.py <addon dir> [out dir] [scenario ...]
Default out dir: branding/gallery. Writes each scenario as an animated WebP (hero is the warrior, then
mage, rogue, then warlock and rend, whose targets carry the DoT marker, priest, with the heal marker, druid, with both, eating, a meal up to its buff, mana, the build-up to mana regenerating, and fury, a warrior's rage building to full and spent), frames.png (a still of the warrior), themes.png (the player frame in a few themes) plates.webp (four nameplates, from the plate art capture_art.py --plates cut out) and prd.webp (a warrior's Personal Resource Display through a fight and a bandage, on the same plate art) and party.webp (four party members through a fight, from the party art capture_art.py --party cut out) and raid.webp (ten raid members through a pull, from the raid art capture_art.py --raid cut out) and tall.webp (a mage's player frame with its bars made taller and shorter, settling in the middle, the art cut as the addon cuts it for its taller frames).
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

# Spells that cost rage (Heroic Strike, Hamstring), and __rage(id, guid) casting one, for Rage Fury's bursts.
RAGE_SETUP = """
    __spellCosts[78] = { { type = 1, name = 'RAGE', cost = 15 } }
    __spellCosts[1715] = { { type = 1, name = 'RAGE', cost = 10 } }
    function __rage(id, guid) __fire('UNIT_SPELLCAST_SUCCEEDED', 'player', guid, id) end
"""

# Each scenario: the player (name, level, power type), the target, bar maxima (player health and
# power, target health and power), and a loop of { seconds, the four bars as fractions }. A new
# target comes in at full health. With regen (a fraction of the bar per second), the player's power refills
# continuously, as energy and mana do on Forever, rather than in steps: each drop in its column is a spend, and
# its rises are ignored. spends: (seconds, fraction) in place of the column, with power_start where it begins.
SCENARIOS = {
    # Rage builds as blows land, the bar heating up (Rage Fury), and two Heroic Strikes burst it back down.
    "hero": dict(
        player="Hollywood Hootsman", level="12", power="RAGE", target="Defias Pillager", target_level="12",
        maxes=(349, 100, 210, 350), loop=8.4, setup=RAGE_SETUP,
        script=[(0.0, 1.00, 0.10, 1.00, 0.90), (1.2, 0.72, 0.35, 0.80, 0.90), (2.2, 0.72, 0.60, 0.55, 0.75),
                (3.0, 0.48, 0.85, 0.55, 0.75), (4.0, 0.48, 0.70, 0.40, 0.60), (4.4, 0.48, 0.55, 0.25, 0.60),
                (5.0, 0.85, 0.55, 0.25, 0.60), (6.0, 0.85, 0.80, 0.00, 0.60), (7.2, 1.00, 0.10, 1.00, 0.90)],
        events=[(4.0, "__rage(78, 'Cast-1')"), (4.4, "__rage(78, 'Cast-2')")]),
    # Each Fireball takes a big bite of mana and of the target; the kobold gets one swing in.
    "mage": dict(
        player="Mailbox Hootsman", level="12", power="MANA", target="Kobold Geomancer", target_level="11",
        maxes=(232, 420, 198, 320), loop=8.0, regen=0.011,
        script=[(0.0, 1.00, 1.00, 1.00, 1.00), (1.5, 1.00, 0.86, 0.68, 1.00), (2.4, 1.00, 0.86, 0.68, 0.88),
                (3.0, 1.00, 0.72, 0.36, 0.88), (3.6, 0.84, 0.72, 0.36, 0.88), (4.5, 0.84, 0.58, 0.06, 0.88),
                (5.2, 0.84, 0.52, 0.00, 0.88), (6.4, 0.84, 0.52, 1.00, 1.00), (7.0, 0.90, 0.60, 1.00, 1.00)]),
    # Energy refills continuously at 10 a second; Sinister Strike spends 40, Eviscerate 35. Over the loop the regen
    # pays for exactly what is spent, so it joins up seamlessly.
    "rogue": dict(
        player="Hotdog Rouge", level="12", power="ENERGY", target="Defias Footpad", target_level="12",
        maxes=(258, 100, 214, 280), loop=11.5, regen=0.10, power_start=0.70,
        spends=[(0.4, 0.40), (4.4, 0.40), (8.0, 0.35)],
        script=[(0.0, 1.00, 0, 1.00, 0.70), (0.4, 1.00, 0, 0.84, 0.70), (1.6, 0.91, 0, 0.84, 0.70),
                (2.2, 0.91, 0, 0.76, 0.70), (2.8, 0.83, 0, 0.76, 0.70), (4.4, 0.83, 0, 0.60, 0.70),
                (5.0, 0.76, 0, 0.60, 0.70), (6.0, 0.76, 0, 0.50, 0.70), (7.0, 0.76, 0, 0.38, 0.70),
                (8.0, 0.76, 0, 0.00, 0.70), (9.4, 0.76, 0, 1.00, 0.70), (10.6, 0.88, 0, 1.00, 0.70)]),
    # The DoT marker, Shadow then Fire: Corruption goes up first as a Shadow liquid at the health's edge, and
    # Immolate follows as a Fire liquid behind it. Shadow Bolts land between the ticks until the
    # DoTs will finish the conjurer and the skull comes up. Casts and ticks go through the addon's own
    # tracking (events).
    "warlock": dict(
        player="Hexbag Hootsman", level="12", power="MANA", target="Defias Conjurer", target_level="11",
        maxes=(220, 380, 300, 300), loop=9.2, regen=0.006,
        spells={172: ("Corruption", "Corrupts the target, causing 72 Shadow damage over 18 sec."),
                348: ("Immolate", "Burns the enemy for 30 Fire damage and then an additional 90 Fire damage "
                                  "over 15 sec.")},
        script=[(0.0, 1.00, 1.00, 1.00, 1.0), (0.4, 1.00, 0.91, 1.00, 1.0), (2.0, 1.00, 0.79, 0.90, 1.0),
                (3.4, 1.00, 0.79, 0.86, 1.0), (4.2, 1.00, 0.68, 0.66, 1.0), (5.0, 1.00, 0.68, 0.60, 1.0),
                (5.6, 0.88, 0.68, 0.60, 1.0), (6.4, 0.88, 0.68, 0.56, 1.0), (6.9, 0.88, 0.58, 0.36, 1.0),
                (8.0, 0.88, 0.58, 0.30, 1.0), (8.6, 0.88, 0.62, 1.00, 1.0)],
        events=[(0.4, "__dotsCast(172, 'Cast-1')"),
                (2.0, "__dotsCast(348, 'Cast-2'); __hit(30, 4)"),
                (3.4, "__hit(12, 32)"), (4.2, "__hit(60, 32)"), (5.0, "__hit(18, 4)"), (6.4, "__hit(12, 32)"),
                (6.9, "__hit(60, 32)"), (8.0, "__hit(18, 4)"), (8.6, "__newTarget()")]),
    # A warrior's bleed: Rend goes up and the liquid is Blood, beating out of the wound; white swings and Heroic
    # Strikes bring the pillager down, one of them a crit that makes the bleed gush, until Rend will finish it and
    # the skull comes up, then a last swing kills it.
    "rend": dict(
        player="Hollywood Hootsman", level="12", power="RAGE", target="Defias Pillager", target_level="12",
        maxes=(349, 100, 210, 350), loop=9.0,
        spells={6546: ("Rend", "Wounds the target causing them to bleed for 28 damage over 12 sec.")},
        script=[(0.0, 1.00, 0.30, 1.000, 0.9), (0.4, 1.00, 0.20, 1.000, 0.9), (1.0, 1.00, 0.32, 0.857, 0.9),
                (2.2, 1.00, 0.20, 0.643, 0.9), (2.8, 0.90, 0.26, 0.643, 0.9), (3.4, 0.90, 0.26, 0.610, 0.9),
                (3.6, 0.90, 0.38, 0.467, 0.9), (5.0, 0.90, 0.20, 0.276, 0.9), (5.6, 0.82, 0.26, 0.276, 0.9),
                (6.0, 0.82, 0.38, 0.086, 0.9), (6.4, 0.82, 0.38, 0.052, 0.9), (7.6, 0.82, 0.48, 0.000, 0.9),
                (8.4, 0.82, 0.48, 1.000, 0.9)],
        events=[(0.4, "__dotsCast(6546, 'Cast-1')"), (1.0, "__hit(30, 1)"), (2.2, "__hit(45, 1)"),
                (3.4, "__hit(7, 1)"), (3.6, "__crit(30, 1)"), (5.0, "__hit(40, 1)"), (6.0, "__hit(40, 1)"),
                (6.4, "__hit(7, 1)"), (7.6, "__hit(11, 1); __target.dead = true"), (8.4, "__newTarget()")]),
    # The heal marker, Holy then Nature: Renew goes up as a Holy liquid ahead of the priest's health and Flash
    # Heal, while it is cast, joins it; then a bandage goes up as a Nature liquid past it. The health rises into
    # them tick by tick, and past full the bandage's last ticks are cut off at the bar's end.
    "priest": dict(
        player="Halo Hootsman", level="12", power="MANA", target="Kobold Tunneler", target_level="11",
        maxes=(300, 400, 200, 300), loop=10.4, cls="PRIEST", regen=0.006,
        heals={139: ("Renew", "Heals the target of 45 damage over 9 sec."),
               2061: ("Flash Heal", "Heals a friendly target for 40 to 48."),
               746: ("First Aid", "Heals 48 damage over 6 sec.")},
        script=[(0.0, 1.00, 1.00, 1.00, 1.0), (0.4, 0.75, 1.00, 1.00, 1.0), (1.0, 0.75, 0.93, 1.00, 1.0),
                (1.6, 0.55, 0.93, 0.88, 1.0), (3.7, 0.697, 0.81, 0.88, 1.0), (4.0, 0.747, 0.81, 0.88, 1.0),
                (5.2, 0.773, 0.81, 0.88, 1.0), (6.2, 0.80, 0.81, 0.88, 1.0), (7.0, 0.85, 0.81, 0.88, 1.0),
                (7.2, 0.877, 0.81, 0.88, 1.0), (8.2, 0.903, 0.81, 0.88, 1.0), (9.2, 0.93, 0.83, 0.94, 1.0),
                (10.0, 0.98, 0.83, 0.94, 1.0), (10.2, 1.00, 0.85, 1.00, 1.0)],
        events=[(1.0, "__healCast(139, 'Cast-1')"), (2.2, "__healStart(2061, 'Cast-2')"),
                (3.7, "__healDone(2061, 'Cast-2')"), (4.2, "__channel(746, 'Cast-3')"),
                (10.2, "__channelStop(746, 'Cast-3')")]),
    # Both markers: a druid at half health keeps Moonfire (Arcane) on the mystic, puts Rejuvenation up, takes a few
    # hits, then casts Healing Touch, which joins Rejuvenation's spring green while cast and bursts into the
    # health in leaves as it lands. Moonfire is cast again just before it runs out.
    "druid": dict(
        player="Hotdog Tree", level="6", power="MANA", target="Gnarlpine Mystic", target_level="6",
        maxes=(150, 210, 120, 160), loop=13.6, cls="DRUID", regen=0.004,
        spells={8921: ("Moonfire", "Burns the enemy for 9 to 12 Arcane damage and then an additional 12 Arcane "
                                   "damage over 9 sec.")},
        heals={774: ("Rejuvenation", "Heals the target for 44 over 12 sec."),
               5185: ("Healing Touch", "Heals a friendly target for 49 to 60.")},
        script=[(0.0, 0.500, 1.00, 1.000, 1.00), (0.4, 0.500, 0.92, 0.917, 1.00), (0.6, 0.440, 0.92, 0.917, 0.92),
                (1.2, 0.440, 0.83, 0.917, 0.92), (2.2, 0.370, 0.83, 0.917, 0.92), (3.4, 0.370, 0.83, 0.883, 0.92),
                (3.6, 0.320, 0.83, 0.883, 0.84), (4.2, 0.393, 0.83, 0.883, 0.84), (6.4, 0.393, 0.83, 0.850, 0.84),
                (7.2, 0.467, 0.83, 0.850, 0.84), (7.3, 0.827, 0.69, 0.850, 0.84), (8.4, 0.777, 0.69, 0.850, 0.76),
                (9.4, 0.777, 0.69, 0.817, 0.76), (9.6, 0.777, 0.61, 0.725, 0.76), (10.2, 0.850, 0.61, 0.725, 0.76),
                (12.6, 0.850, 0.64, 0.692, 0.76), (13.2, 0.923, 0.64, 0.692, 0.76)],
        events=[(0.4, "__dotsCast(8921, 'Cast-1'); __hit(10, 64)"), (1.2, "__healCast(774, 'Cast-2')"),
                (3.4, "__hit(4, 64)"), (4.8, "__healStart(5185, 'Cast-3')"), (6.4, "__hit(4, 64)"),
                (7.3, "__healDone(5185, 'Cast-3')"), (9.4, "__hit(4, 64)"),
                (9.6, "__dotsCast(8921, 'Cast-4'); __hit(11, 64)"), (12.6, "__hit(4, 64)")]),
    # Rage Fury: a warrior trading blows, rage climbing with every hit taken and landed until the bar is full and
    # furious, throbbing there a while; then Heroic Strikes and a Hamstring spend it back to 40%, each spend a burst,
    # the pillager falls and the next one comes in.
    "fury": dict(
        player="Hollywood Hootsman", level="12", power="RAGE", target="Defias Pillager", target_level="12",
        maxes=(349, 100, 210, 350), loop=12.0, portrait="hero", setup=RAGE_SETUP,
        script=[(0.0, 1.00, 0.40, 1.00, 0.90), (0.8, 0.93, 0.52, 1.00, 0.90), (1.6, 0.93, 0.61, 0.92, 0.90),
                (2.4, 0.86, 0.72, 0.92, 0.90), (3.2, 0.86, 0.83, 0.84, 0.90), (4.0, 0.79, 0.92, 0.84, 0.90),
                (4.8, 0.79, 1.00, 0.76, 0.90), (6.0, 0.72, 1.00, 0.76, 0.90), (7.2, 0.72, 0.85, 0.60, 0.90),
                (8.0, 0.72, 0.70, 0.44, 0.90), (8.8, 0.66, 0.60, 0.38, 0.90), (9.6, 0.66, 0.45, 0.20, 0.90),
                (10.4, 0.66, 0.40, 0.00, 0.90), (11.2, 1.00, 0.40, 1.00, 0.90)],
        events=[(7.2, "__rage(78, 'Cast-1')"), (8.0, "__rage(78, 'Cast-2')"), (8.8, "__rage(1715, 'Cast-3')"),
                (9.6, "__rage(78, 'Cast-4')")]),
    # Eating, on the player frame alone: from 20% health the food goes up as Honey, the health rising into it tick by
    # tick. The bar builds up for ten seconds and lets go in stars as the druid becomes well fed; slow stars
    # follow until it stands up.
    "eating": dict(
        player="Hotdog Tree", level="6", power="MANA", target="", target_level="", solo=True, portrait="druid",
        maxes=(150, 210, 120, 160), loop=14.6, cls="DRUID", regen=0.008,
        heals={433: ("Food", "Restores 108 health over 18 sec. Must remain seated while eating. If you spend at "
                             "least 10 seconds eating you will become well fed and gain 4 Stamina and Spirit.")},
        script=[(0.0, 0.20, 0.70, 1.0, 1.0), (3.5, 0.32, 0.70, 1.0, 1.0), (6.5, 0.44, 0.70, 1.0, 1.0),
                (9.5, 0.56, 0.70, 1.0, 1.0), (12.5, 0.68, 0.70, 1.0, 1.0)],
        events=[(0.5, "__healCast(433, 'Cast-1')"), (13.8, "__fire('PLAYER_STARTED_MOVING')")]),
    # The wait before mana regenerates, on the player frame alone: one spell and the whole wait, up to the burst as
    # regeneration returns, mana flowing back for a while, then two spells close together, the second starting the
    # wait again. The regen pays for what is spent over the loop, so it joins up.
    "mana": dict(
        player="Mailbox Hootsman", level="12", power="MANA", target="", target_level="", solo=True, portrait="mage",
        maxes=(232, 420, 198, 320), loop=17.5, regen=0.10 * 3 / 5.5, power_start=0.72, rule_wait=5.0,
        spends=[(1.0, 0.10), (9.0, 0.10), (11.0, 0.10)],
        script=[(0.0, 1.0, 0.72, 1.0, 1.0)]),
}


def power_at(sc, t):
    """The player's power at t for a scenario with regen: it refills continuously, up to full, between spends."""
    script = sc["script"]
    spends = sc.get("spends")
    if spends is None:
        spends = [(b[0], a[2] - b[2]) for a, b in zip(script, script[1:]) if b[2] < a[2]]
    power, last = sc.get("power_start", script[0][2]), 0.0
    wait, spent = sc.get("rule_wait", 0.0), False

    def gained(frm, to):
        # With rule_wait, nothing comes back for that long after a spend.
        return sc["regen"] * max(0.0, to - (frm + wait if spent else frm))

    for when, spend in spends:
        if when > t:
            break
        power = max(0.0, min(1.0, power + gained(last, when)) - spend)
        last, spent = when, True
    return min(1.0, power + gained(last, t))


def rule_setup():
    """Lua for a scenario showing the wait before mana regenerates: a spell that costs mana, each spend a cast of it."""
    return """
    __spells[133] = { 'Fireball', 'Hurls a fiery ball.' }
    __spellCosts[133] = { { type = 0, name = 'MANA', cost = 42 } }
    function __spend(guid)
        __fire('UNIT_SPELLCAST_SENT', 'player', 'Kobold', guid, 133)
        __fire('UNIT_SPELLCAST_SUCCEEDED', 'player', guid, 133)
    end
"""


def heals_setup(cls, spells):
    """Lua for a scenario with the heal marker: the player's class, the spells as the client describes them, and
    helpers for the events, all on the player: an instant heal, a cast's start and end, a bandage's channel."""
    lines = [f"__spells[{sid}] = {{ {name!r}, {desc!r} }}" for sid, (name, desc) in spells.items()]
    return "\n".join(lines) + f"""
    __player.class = {cls!r}
    __ns.Core.db.heals = true
    local function sent(id, guid) __fire('UNIT_SPELLCAST_SENT', 'player', __player.name, guid, id) end
    function __healCast(id, guid) sent(id, guid); __fire('UNIT_SPELLCAST_SUCCEEDED', 'player', guid, id) end
    function __healStart(id, guid) sent(id, guid); __fire('UNIT_SPELLCAST_START', 'player', guid, id) end
    function __healDone(id, guid)
        __fire('UNIT_SPELLCAST_STOP', 'player', guid, id); __fire('UNIT_SPELLCAST_SUCCEEDED', 'player', guid, id)
    end
    function __channel(id, guid)
        sent(id, guid); __fire('UNIT_SPELLCAST_CHANNEL_START', 'player', guid, id)
        __fire('UNIT_SPELLCAST_SUCCEEDED', 'player', guid, id)
    end
    function __channelStop(id, guid) __fire('UNIT_SPELLCAST_CHANNEL_STOP', 'player', guid, id) end
"""


def dots_setup(target, spells):
    """Lua for a scenario with the DoT marker: it on, a target to cast at, the spells as the client describes
    them, and helpers for the events: a cast, a hit on the target, and the next target."""
    lines = [f"__spells[{sid}] = {{ {name!r}, {desc!r} }}" for sid, (name, desc) in spells.items()]
    return "\n".join(lines) + f"""
    __ns.Core.db.dots = true
    __target = {{ guid = 'Creature-0-1-2-3-40-0001', name = {target!r} }}
    function __dotsCast(id, guid)
        __fire('UNIT_SPELLCAST_SENT', 'player', __target.name, guid, id)
        __fire('UNIT_SPELLCAST_SUCCEEDED', 'player', guid, id)
    end
    function __hit(amount, school) __fire('UNIT_COMBAT', 'target', 'WOUND', '', amount, school) end
    function __crit(amount, school) __fire('UNIT_COMBAT', 'target', 'WOUND', 'CRITICAL', amount, school) end
    function __newTarget()
        __target = {{ guid = 'Creature-0-1-2-3-40-0002', name = {target!r} }}
        __fire('PLAYER_TARGET_CHANGED')
    end
"""
MARKER_LONG = 10000       # Marker.lua: LONG
OVERLAP = 6               # Marker.lua: how far a DoT liquid reaches under the liquid behind it
ROOM = 10                 # Marker.lua: how far the second DoT liquid reaches over the first
PORTRAIT_CENTRE = (177, 48)  # the target's portrait: TOPRIGHT -26, -19, 58 across (Preview.lua LAYOUT)


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

def start(settings, power="RAGE", dots="", events=()):
    """The addon in the mock with its four bars sized as Forever's, the player on the given power type
    and the target on mana; returns the session. Each bar's liquid frame becomes __mover_<unit>_<kind>.
    dots: Lua from dots_setup, for a scenario with the DoT marker; events: (time, Lua)."""
    before = dots + f"""
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
        -- The liquid's clip frame is the bar's first clipping frame that is not a StatusBar (the markers' come
        -- after; the game's heal prediction segments do not clip).
        for key, bar in pairs(bars) do
            for _, clip in ipairs(__frames) do
                if clip.parent == bar and not clip.SetValue and clip.clipsChildren then
                    for _, f in ipairs(__frames) do
                        if f.parent == clip then
                            _G['__mover_' .. key] = f
                            f.w, f.h = bar.w, bar.h -- the client sizes it from its anchors
                        end
                    end
                    break
                end
            end
        end
        -- The DoT liquids' frames, sized as the client sizes them from their anchors.
        local marker = (__ns.Marker.State())
        if marker then
            for i, d in ipairs(marker.liquids) do
                _G['__dotMover' .. i] = d.mover
                d.mover.w, d.mover.h = TargetFrame.healthbar.w, TargetFrame.healthbar.h
            end
        end
        -- The heal liquids' frames likewise, on the health bar and (drink) the mana bar.
        local heal, mana = __ns.HealMarker.State()
        for prefix, m in pairs({ __healMover = heal or false, __manaMover = mana or false }) do
            if m then
                for i, d in ipairs(m.liquids) do
                    _G[prefix .. i] = d.mover
                    d.mover.w, d.mover.h = m.bar.w, m.bar.h
                    _G[prefix .. 'Seam' .. i] = d.seam.mover
                    d.seam.mover.w, d.seam.mover.h = m.bar.w, m.bar.h
                end
            end
        end
        -- The bar masks have no art in the mock; the captured ones are applied here instead. Regions made later (the
        -- rage fury, built on the bar's first update) lose theirs as they come.
        local unmasked = 0
        function __unmask()
            for i = unmasked + 1, #__regions do __regions[i].masks = nil end
            unmasked = #__regions
        end
        __unmask()
    """
    return render.Session(ADDON, settings=settings, before_login=before, after_login=after, scenario=events)


def is_mote(r):
    """Liquid.lua's motes: OVERLAY 4, or -1 and -6 on the DoT liquids, which lie 5 and 10 sublevels under the
    health liquid (Marker.lua, UNDER)."""
    return r.layer == "OVERLAY" and r.sub in (4, -1, -6)


def draw_bar(session, img, art, fx, fy, which, kind, frac, frame=None, cut=0.0, cut_right=None):
    """The liquid of one bar onto img (RGB), the frame's top-left at (fx, fy) px. frame: the global name of
    the liquid's frame, if not the bar's own liquid (a DoT liquid); cut and cut_right: where its clip frame
    starts and ends, in bar units from the bar's left edge (by default the bar's left edge, and SPILL past
    its end)."""
    x, y, w, h = BARS[(which, kind)]
    # Work on the bar's surroundings only: the bar, and the room motes have around it.
    sx, sy = int(fx + (x - 4) * K), int(fy + (y - SPILL) * K)
    sw, sh = int((w + SPILL + 8) * K), int((h + 2 * SPILL) * K)
    sub = img.crop((sx, sy, sx + sw, sy + sh))
    session.frame = frame or f"__mover_{which}_{kind}"
    ox, oy = fx + (x + frac * w - w) * K - sx, fy + y * K - sy
    clip = np.zeros((sh, sw), np.float32)
    clip[:, max(0, int((4 + max(0.0, cut)) * K)):] = 1
    if cut_right is not None:
        clip[:, max(0, int((4 + cut_right) * K)):] = 0
    liquid = session.render(sub, ox, oy, K, only=lambda r: not is_mote(r))
    # The captured mask covers the whole frame, from its top-left.
    mask = Image.new("L", (sw, sh), 0)
    mask.paste(art[f"{which}-{kind}-mask"].getchannel("A"), (int(fx) - sx, int(fy) - sy))
    m = np.asarray(mask).astype(np.float32) / 255 * clip
    a, b = np.asarray(sub).astype(np.float32), np.asarray(liquid).astype(np.float32)
    sub = Image.fromarray((a + (b - a) * m[..., None]).astype(np.uint8))
    # Motes, cut only by the clip frame: from the bar's left edge (or the cut) to SPILL past its end.
    motes = session.render(sub, ox, oy, K, only=is_mote)
    a, b = np.asarray(sub).astype(np.float32), np.asarray(motes).astype(np.float32)
    sub = Image.fromarray((a + (b - a) * clip[..., None]).astype(np.uint8))
    img.paste(sub, (sx, sy))


def heal_state(session):
    """What the player's heal markers are showing, by bar kind ("health", and "power" for drink): each heal
    liquid's running total as it glides (None for one not showing). A hidden marker is left out."""
    out = {}
    for kind, i in (("health", 1), ("power", 2)):
        m = session.lua.eval(f"(select({i}, __ns.HealMarker.State()))")
        if m is not None and m.clip.shown:
            out[kind] = [d.shown if d.pool.shown else None for d in (m.liquids[j] for j in range(1, len(m.liquids) + 1))]
    return out


def marker_state(session):
    """What the target's DoT marker is showing, from the addon: each DoT liquid's running total as it glides
    (None for one not showing), the damage, and the kill icon (shown, alpha). None when hidden."""
    m = session.lua.eval("(__ns.Marker.State())")
    if m is None or not m.clip.shown:
        return None
    runs = [d.shown if d.pool.shown else None for d in (m.liquids[i] for i in range(1, len(m.liquids) + 1))]
    return dict(runs=runs, value=m.value, icon=m.window.shown, icon_alpha=m.icon.alpha)


_warned = set()


def draw_kill_icon(img, art, fx, fy, health, state):
    """The game's skull (captured as target-killicon) on the portrait. It slides in over the last
    icon-width of a LONG bar as the damage reaches the health, cut by its icon-sized window."""
    if not state["icon"]:
        return
    if "target-killicon" not in art:
        if "icon" not in _warned:
            _warned.add("icon")
            print("  no target-killicon.png yet: the kill icon is left out (recapture with /sab capture)")
        return
    cell = art["target-killicon"]
    box = cell.getchannel("A").getbbox()
    if not box:
        return
    icon = cell.crop(box)
    iw = icon.width / K
    short = (1 - min(1.0, state["value"] / max(health, 1e-6))) * MARKER_LONG
    if short >= iw:
        return
    alpha = np.asarray(icon.getchannel("A")).astype(np.float32) * state["icon_alpha"]
    icon.putalpha(Image.fromarray(alpha.astype(np.uint8)))
    cut = round(short * K)
    canvas = img.convert("RGBA")
    canvas.alpha_composite(icon.crop((cut, 0, icon.width, icon.height)), (int(fx) + box[0], int(fy) + box[1]))
    img.paste(canvas.convert("RGB"))


def text(draw, x, y, s, size, color, outline):
    f = render.font(size * K)
    if outline:
        draw.text((x, y), s, font=f, fill=color, anchor="mm", stroke_width=max(1, round(K * 0.6)),
                  stroke_fill=(0, 0, 0))
    else:
        draw.text((x + K, y + K), s, font=f, fill=(0, 0, 0), anchor="mm")
        draw.text((x, y), s, font=f, fill=color, anchor="mm")


def draw_frame(session, img, art, fx, fy, which, fills, values, sc, portrait, marker=None, heals=None):
    """A whole frame onto img (RGB): art, liquid, the DoT marker (its state from marker_state) and the heal
    marker (heal_state), then the level circle and text above them."""
    canvas = img.convert("RGBA")
    pieces = [portrait if which == "player" else "target-portrait", f"{which}-art"]
    if which == "target":
        pieces.append("target-banner")
    for piece in pieces:
        canvas.alpha_composite(art[piece], (int(fx), int(fy)))
    img.paste(canvas.convert("RGB"))
    for kind in ("health", "power"):
        frac = fills[(which, kind)]
        if which == "target" and kind == "health" and marker:
            # Each DoT liquid on the edge in front of it, cut a little under where it ends, the second reaching
            # ROOM over the first; then the health liquid over them, its front moved back to where the health
            # will end. Back to front, as the client layers them.
            w = BARS[(which, kind)][2]
            maximum = dict(zip(ORDER, sc["maxes"]))[(which, kind)]
            front, ends = frac, []
            for run in marker["runs"]:
                ends.append(frac - run / maximum if run is not None else None)
            for i, end in enumerate(ends):
                if end is None:
                    continue
                draw_bar(session, img, art, fx, fy, which, kind, front, frame=f"__dotMover{i + 1}",
                         cut=end * w - OVERLAP, cut_right=None if i == 0 else front * w + ROOM)
                front = end
            frac = front
        if which == "player" and heals and heals.get(kind):
            # Each heal liquid from the edge before it (cut a little under it) to the bar's end, ending where its
            # running total does: the one past the other first, as the nearer one lies over it.
            w = BARS[(which, kind)][2]
            maximum = dict(zip(ORDER, sc["maxes"]))[(which, kind)]
            runs = heals[kind]
            prefix = "__healMover" if kind == "health" else "__manaMover"
            starts, before = [], frac
            for run in runs:
                starts.append(before)
                if run is not None:
                    before = frac + run / maximum
            for i in reversed(range(len(runs))):
                if runs[i] is None:
                    continue
                draw_bar(session, img, art, fx, fy, which, kind, frac + runs[i] / maximum,
                         frame=f"{prefix}{i + 1}", cut=starts[i] * w - OVERLAP, cut_right=w)
        draw_bar(session, img, art, fx, fy, which, kind, frac)
        if which == "player" and heals and heals.get(kind):
            # The seams, above everything: each on the edge its liquid starts from.
            for i in reversed(range(len(starts))):
                if heals[kind][i] is not None:
                    draw_bar(session, img, art, fx, fy, which, kind, starts[i], frame=f"{prefix}Seam{i + 1}",
                             cut_right=w)
    canvas = img.convert("RGBA")
    canvas.alpha_composite(art[f"{which}-circle"], (int(fx), int(fy)))
    img.paste(canvas.convert("RGB"))
    if which == "target" and marker:
        draw_kill_icon(img, art, fx, fy, values[("target", "health")], marker)
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
    if key in ("hero", "rend", "fury"):
        return "player-portrait"
    print(f"  no {name}.png yet: using the capturing character's portrait")
    return "player-portrait"


def scenario(art, key):
    """Both frames through a scenario's loop, as a GIF; the warrior's also gives frames.png."""
    sc = SCENARIOS[key]
    dots = dots_setup(sc["target"], sc["spells"]) if "spells" in sc else ""
    if "heals" in sc:
        dots += heals_setup(sc["cls"], sc["heals"])
    events = sc.get("events", ())
    dots += sc.get("setup", "")
    if "rule_wait" in sc:
        dots += rule_setup()
        events = [(when, f"__spend('Cast-{i}')") for i, (when, _) in enumerate(sc["spends"])]
    session = start({}, sc["power"], dots, events)
    portrait = portrait_for(art, sc.get("portrait", key))
    pad, gap = round(24 * K), round(30 * K)
    solo = sc.get("solo")  # the player frame alone
    w, h = pad * 2 + round(FRAME_W * K) * (1 if solo else 2) + (0 if solo else gap), pad * 2 + round(FRAME_H * K)
    back = backdrop(w, h)
    spots = {"player": (pad, pad)}
    if not solo:
        spots["target"] = (pad + gap + round(FRAME_W * K), pad)
    maxes = dict(zip(ORDER, sc["maxes"]))

    def at(t):
        row = [r for r in sc["script"] if r[0] <= t][-1]
        values = dict(zip(ORDER, row[1:]))
        if "regen" in sc:
            values[("player", "power")] = power_at(sc, t)
        return values

    fills, shown = dict(at(0)), at(0)
    frames, still = [], None
    t, dt = 0.0, 1 / FPS
    while t < sc["loop"] - 1e-9:
        goal = at(t)
        for k in ORDER:
            # A change the bar shows: the game's events come with the whole number changing.
            if round(goal[k] * maxes[k]) != round(shown[k] * maxes[k]):
                which, kind = k
                event = "UNIT_HEALTH" if kind == "health" else "UNIT_POWER_UPDATE"
                session.lua.execute(f"__fire('{event}', '{which}')")
                if which == "target" and kind == "health" and goal[k] > shown[k] + 0.5:
                    fills[k] = goal[k]  # a new target: its bar does not ease up
        shown = goal
        # The client's share of the player's power, for the rage fury's curve (it eases nothing, unlike the bar).
        session.lua.execute(f"__powerPercent.player = {goal[('player', 'power')]}")
        session.run_until(t)
        session.lua.execute("__unmask()")
        for k in ORDER:
            fills[k] += (goal[k] - fills[k]) * (1 - math.exp(-8 * dt))
        values = {k: round(goal[k] * maxes[k]) for k in ORDER}
        marker = marker_state(session) if "spells" in sc else None
        heals = heal_state(session) if "heals" in sc else None
        img = back.copy()
        for which, (fx, fy) in spots.items():
            draw_frame(session, img, art, fx, fy, which, fills, values, sc, portrait, marker, heals)
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


# ---------------------------------------------------------------------------- taller bars

# A mage's player frame with its bars made taller and shorter (the editor's Health and Power Bar Height): from the
# middle up to the tallest the sliders go (40 and 20), down to the game's own (20 and 10) and back to the middle, so it
# loops. Heights as how much taller than the game's, eased between these: (seconds, health, power).
TALL_LOOP = 8.8
TALL_KEYS = [(0.0, 10, 5), (1.2, 10, 5), (2.7, 20, 10), (3.3, 20, 10), (5.3, 0, 0), (5.8, 0, 0), (7.2, 10, 5),
             (TALL_LOOP, 10, 5)]
# A quiet fight meanwhile: two Fireballs out of the mana, which refills, and one hit taken that is healed back.
TALL_SC = dict(player="Mailbox Hootsman", level="12", power="MANA", maxes=(232, 420), regen=0.011,
               power_start=0.82, spends=[(1.6, 0.12), (4.8, 0.12)],
               script=[(0.0, 0.92, 0), (2.4, 0.78, 0), (6.6, 0.78, 0), (7.4, 0.92, 0)])
TALL_MAX = 30  # the most the frame grows (20 + 10)
# The frame of ours the addon lays out taller (Preview.LiveFrame, as TallFrames.lua puts on the game's frame): its art's
# slices of the atlas, the portrait's and level circle's places, and its bars' boxes, in frame units from its top-left.
TALL_LAYOUT = """
function __tallLayout(dh, dp, cx, cy)
    local P = __ns.Preview
    if not __tallF then
        __tallF = P.LiveFrame(UIParent, 'player', 'player')
        __tallF:Hide()
    end
    local f = __tallF
    P.SetFrameTall(f, math.max(dh, 0.0001), dp) -- laid out as sliced art even at the game's heights
    local slices = {}
    local tex = {}
    for _, t in ipairs(f.slices or {}) do tex[#tex + 1] = t end
    tex[#tex + 1] = f.ringTex
    for _, r in ipairs(tex) do
        if r and r.shown and r.tc then
            local p = r.points.TOPLEFT
            local m = r == f.ringTex and f.ringMask or nil
            slices[#slices + 1] = { r.tc[1], r.tc[2], r.tc[3], r.tc[4], p.x, -p.y, r.w, r.h, r == f.ringTex,
                                    m and m.points.TOPLEFT.x or false, m and -m.points.TOPLEFT.y or false,
                                    m and m.w or false }
        end
    end
    local pc = f.portrait.points.CENTER
    -- The level circle's centre (cx, cy: where the captured art has it) moved with the ring, as SetFrameTall moves it
    -- (the mock does not know the circle atlas's size, so its own place for it is off).
    local mx, my = f.tall.Moved(cx, cy)
    local function box(b) return { b.points.TOPLEFT.x, -b.points.TOPLEFT.y, b.w, b.h } end
    return slices, f.w, f.h, pc.x, -pc.y, f.portrait.w, mx, my, box(f.health), box(f.power)
end
"""


def tall_heights(t):
    """The bars' growth at t, eased (smoothstep) between TALL_KEYS."""
    for (t0, h0, p0), (t1, h1, p1) in zip(TALL_KEYS, TALL_KEYS[1:]):
        if t0 <= t <= t1:
            u = 0.0 if t1 == t0 else (t - t0) / (t1 - t0)
            u = u * u * (3 - 2 * u)
            return h0 + (h1 - h0) * u, p0 + (p1 - p0) * u
    return TALL_KEYS[-1][1:]


def tall_mask(base, bar0, bar1, band, d, height):
    """A bar's captured mask (alpha, the game's frame at K) laid out for a frame `height` units tall whose bar starts at
    bar1 instead of bar0 and is d taller: stretched about the top of the part it lets through (band, from the bar's
    top) until that part is d taller, as Preview.lua's TallSpec stretches the mask atlas."""
    o0, o1 = band
    s = (o1 - o0 + d) / (o1 - o0)
    ys = (np.arange(round(height * K)) + 0.5) / K
    orig = bar0 + o0 + (ys - bar1 - o0) / s
    rows = np.clip(np.floor(orig * K).astype(int), 0, base.shape[0] - 1)
    out = base[rows].copy()
    out[(orig < 0) | (orig * K >= base.shape[0])] = 0
    return out


def draw_tall_bar(session, img, fx, fy, box, mask, frac, frame):
    """A bar's liquid onto img (RGB) at its box in a taller frame (top-left at fx, fy px), cut by its mask (alpha for
    the whole frame at K) and its motes by the clip frame, as draw_bar does for the game's frame."""
    x, y, w, h = box
    sx, sy = int(fx + (x - 4) * K), int(fy + (y - SPILL) * K)
    sw, sh = int((w + SPILL + 8) * K), int((h + 2 * SPILL) * K)
    sub = img.crop((sx, sy, sx + sw, sy + sh))
    session.frame = frame
    ox, oy = fx + (x + frac * w - w) * K - sx, fy + y * K - sy
    clip = np.zeros((sh, sw), np.float32)
    clip[:, int(4 * K):] = 1
    liquid = session.render(sub, ox, oy, K, only=lambda r: not is_mote(r))
    cut = Image.new("L", (sw, sh), 0)
    cut.paste(Image.fromarray(mask), (int(fx) - sx, int(fy) - sy))
    m = np.asarray(cut).astype(np.float32) / 255 * clip
    a, b = np.asarray(sub).astype(np.float32), np.asarray(liquid).astype(np.float32)
    sub = Image.fromarray((a + (b - a) * m[..., None]).astype(np.uint8))
    motes = session.render(sub, ox, oy, K, only=is_mote)
    a, b = np.asarray(sub).astype(np.float32), np.asarray(motes).astype(np.float32)
    sub = Image.fromarray((a + (b - a) * clip[..., None]).astype(np.uint8))
    img.paste(sub, (sx, sy))


def tall(art):
    """tall.webp: the player frame's bars growing, shrinking and settling (TALL_KEYS), the frame drawn as the addon lays
    out its taller frames: the game's atlas cut into slices (Preview.TallArt), the portrait ring grown once it would
    clip, and the masks stretched; the liquid is the addon's in the game's bars made as tall."""
    sc = TALL_SC
    session = start({}, sc["power"])
    session.lua.execute(TALL_LAYOUT)
    ppu = json.load(open(os.path.join(ART, "art.json"), encoding="utf-8"))["ppu"]
    raw_art = Image.open(os.path.join(ART, "player-art.png")).convert("RGBA")
    raw_portrait = Image.open(os.path.join(ART, f"{portrait_for(art, 'mage')}.png")).convert("RGBA")
    # The atlas's place on the game's frame (Preview.lua, AtlasPlace: centred, its size as the client gives it).
    aw, ah = 194, 68
    ax0, ay0 = FRAME_W / 2 - aw / 2, FRAME_H / 2 - ah / 2
    bands = {kind: tuple(session.lua.eval(f"__ns.Preview.TALL.player.opaque.{kind}[{i}]") for i in (1, 2))
             for kind in ("health", "power")}
    masks = {kind: np.asarray(art[f"player-{kind}-mask"].getchannel("A")) for kind in ("health", "power")}
    circle = art["player-circle"]
    cbox = circle.getchannel("A").getbbox()
    circle_piece = circle.crop(cbox)
    ccx0, ccy0 = (cbox[0] + cbox[2]) / 2 / K, (cbox[1] + cbox[3]) / 2 / K  # the piece's own centre
    pad = round(24 * K)
    w, h = pad * 2 + round(FRAME_W * K), pad * 2 + round((FRAME_H + TALL_MAX) * K)
    back = backdrop(w, h)
    maxes = {"health": sc["maxes"][0], "power": sc["maxes"][1]}
    # The game's bars as tall as ours, and their liquid's frames (sized from their anchors in the client).
    grow = """local dh, dp = ...
        PlayerFrame.healthbar.h, PlayerFrame.manabar.h = 20 + dh, 10 + dp
        __mover_player_health.h, __mover_player_power.h = 20 + dh, 10 + dp"""
    resize = session.lua.eval("function(...) " + grow + " end")

    def at(t):
        health = [r for r in sc["script"] if r[0] <= t][-1][1]
        return {"health": health, "power": power_at(sc, t)}

    fills, shown = dict(at(0)), at(0)
    frames, t, dt = [], 0.0, 1 / FPS
    while t < TALL_LOOP - 1e-9:
        dh, dp = tall_heights(t)
        resize(dh, dp)
        goal = at(t)
        for kind in ("health", "power"):
            if round(goal[kind] * maxes[kind]) != round(shown[kind] * maxes[kind]):
                session.lua.execute(f"__fire('{'UNIT_HEALTH' if kind == 'health' else 'UNIT_POWER_UPDATE'}', 'player')")
        shown = goal
        session.lua.execute(f"__powerPercent.player = {goal['power']}")
        session.run_until(t)
        session.lua.execute("__unmask()")
        for kind in fills:
            fills[kind] += (goal[kind] - fills[kind]) * (1 - math.exp(-8 * dt))

        slices, fw, fh, pcx, pcy, psize, ccx, ccy, hbox, pbox = session.lua.eval("__tallLayout")(dh, dp, ccx0, ccy0)
        boxes = {"health": tuple(hbox[i] for i in range(1, 5)), "power": tuple(pbox[i] for i in range(1, 5))}
        # Bottom-aligned, as the game's frame grows upward from its bottom edge.
        fx, fy = pad, pad + round((FRAME_H + TALL_MAX - fh) * K)
        canvas = back.copy().convert("RGBA")
        layers = sorted(slices.values(), key=lambda s: s[9])  # the ring (true) last, over the portrait
        drawn = False
        for s in layers:
            l, r, top, bottom, dx, dy, sw_, sh_, ring, mx, my, msize = (s[i] for i in range(1, 13))
            if ring and not drawn:
                # The portrait, as captured, at its new place and size, between the panel and the ring.
                box = tuple(round(v * ppu) for v in (54 - 30, 49 - 30, 54 + 30, 49 + 30))
                piece = raw_portrait.crop(box).resize((round(psize * K), round(psize * K)), Image.LANCZOS)
                canvas.alpha_composite(piece, (fx + round((pcx - psize / 2) * K), fy + round((pcy - psize / 2) * K)))
                drawn = True
            src = ((ax0 + l * aw) * ppu, (ay0 + top * ah) * ppu, (ax0 + r * aw) * ppu, (ay0 + bottom * ah) * ppu)
            # Each edge rounded to the pixel, not the size: rounding the size left a column of the backdrop between the
            # panel's end and the strip carried under the ring once the ring grew (seen in the GIF; in game they meet).
            px0, py0 = round(dx * K), round(dy * K)
            pw, ph = max(1, round((dx + sw_) * K) - px0), max(1, round((dy + sh_) * K) - py0)
            piece = raw_art.crop(tuple(round(v) for v in src)).resize((pw, ph), Image.LANCZOS)
            if mx is not False:
                # CircleMask: a circle filling the mask's square.
                yy, xx = np.mgrid[0:piece.height, 0:piece.width]
                gx, gy = dx + (xx + 0.5) / K, dy + (yy + 0.5) / K
                inside = np.hypot(gx - (mx + msize / 2), gy - (my + msize / 2)) <= msize / 2
                a = np.asarray(piece).astype(np.float32)
                a[..., 3] *= inside
                piece = Image.fromarray(a.astype(np.uint8), "RGBA")
            canvas.alpha_composite(piece, (fx + px0, fy + py0))
        img = canvas.convert("RGB")
        for kind, bar0, d in (("health", 43, dh), ("power", 61, dp)):
            mask = tall_mask(masks[kind], bar0, boxes[kind][1], bands[kind], d, fh)
            draw_tall_bar(session, img, fx, fy, boxes[kind], mask, fills[kind], f"__mover_player_{kind}")
        canvas = img.convert("RGBA")
        canvas.alpha_composite(circle_piece, (fx + round(ccx * K - circle_piece.width / 2),
                                              fy + round(ccy * K - circle_piece.height / 2)))
        img = canvas.convert("RGB")
        draw = ImageDraw.Draw(img)
        nx, ny = NAME_AT["player"]
        text(draw, fx + nx * K, fy + ny * K, sc["player"], 10, (255, 209, 0), False)
        text(draw, fx + ccx * K, fy + (ccy + 0.5) * K, sc["level"], 13, (255, 255, 255), True)
        for kind in ("health", "power"):
            x, y, bw, bh = boxes[kind]
            text(draw, fx + (x + bw / 2) * K, fy + (y + bh / 2) * K,
                 f"{round(goal[kind] * maxes[kind])} / {maxes[kind]}", 10, (255, 255, 255), True)
        frames.append(img)
        t += dt
    os.makedirs(OUT, exist_ok=True)
    webp = os.path.join(OUT, "tall.webp")
    frames[0].save(webp, save_all=True, append_images=frames[1:], duration=round(1000 / FPS), loop=0,
                   quality=92, method=6)
    print(f"wrote tall.webp ({os.path.getsize(webp) // 1024} KB)")


# ---------------------------------------------------------------------------- nameplates

# Forever's plates in the Normal style, from the pieces /sab capture plates captured (capture_art.py --plates), laid
# out as measured on screenshots of the game's Normal plate: the bar 166 x 13; the bronze background's rim around it;
# the target's yellow glow around that; the level box 5 right of the bar, 28 wide, from 3 above it to 2 below, with
# its outline on the target; every plate but the target's darkened, and the name above the bar.
PLATE_W, PLATE_H = 166, 13
PLATE_BG = (2.8, 3.7, 3.2, 2.3)      # left, right, top, bottom
PLATE_GLOW = (2.8, 0.5, 1.9, 1.4)
PLATE_PIECES = ("plate-modern-bg", "plate-selected", "plate-deselected", "plate-level", "plate-level-selected")
# The colours the game gives plates' bars, read in game (GetStatusBarColor: 1 0 0 on an enemy).
PLATE_RED, PLATE_YELLOW, PLATE_GREEN = "{ 1, 0, 0 }", "{ 1, 1, 0 }", "{ 0, 1, 0 }"
LEVEL_GREEN, LEVEL_YELLOW, LEVEL_RED = (64, 191, 64), (255, 210, 0), (255, 64, 64)
PLATE_LOOP = 9.0

# Each plate: name, level and its colour, the unit, its health maximum, the target's (glow, not darkened), the spells
# cast on it, events, and a script of (seconds, health fraction). DoTs go up through the addon's own tracking, so the
# DoT liquids show what it reckons; at the loop's end a fresh mob of the same kind comes, as in the frames' scenarios.
PLATES = [
    # The target: Rend bleeds out of it while blows land, one a crit that makes the bleed gush. A last heavy blow
    # leaves it less health than the Rend still has to deal, and the kill icon comes up beside the plate.
    dict(name="Defias Pillager", level="12", level_color=LEVEL_YELLOW, unit="reaction = 2, color = " + PLATE_RED,
         max=210, target=True,
         spells={6546: ("Rend", "Wounds the target causing them to bleed for 28 damage over 12 sec.")},
         events=[(0.4, "__cast(6546, 'Cast-1')"), (1.0, "__hit(30, 1)"), (2.2, "__hit(45, 1)"),
                 (3.4, "__hit(7, 1)"), (3.6, "__crit(30, 1)"), (5.0, "__hit(85, 1)"), (6.4, "__hit(7, 1)"),
                 (8.4, "__newMob('Creature-0-1-2-3-40-0002')")],
         script=[(0.0, 1.000), (1.0, 0.857), (2.2, 0.643), (3.4, 0.610), (3.6, 0.467), (5.0, 0.062), (6.4, 0.029),
                 (8.4, 1.000)]),
    # Tabbed away from with Corruption and Immolate on it: both DoTs' liquids, Shadow and Fire, burn down with it.
    dict(name="Kobold Geomancer", level="11", level_color=LEVEL_GREEN, unit="reaction = 2, color = " + PLATE_RED,
         max=480, target=False,
         spells={172: ("Corruption", "Corrupts the target, causing 90 Shadow damage over 18 sec."),
                 348: ("Immolate", "Burns the enemy for 30 Fire damage and then an additional 90 Fire damage "
                                   "over 15 sec.")},
         events=[(0.3, "__cast(172, 'Cast-1')"), (1.6, "__cast(348, 'Cast-2'); __hit(30, 4)"),
                 (3.3, "__hit(15, 32)"), (4.6, "__hit(18, 4)"), (6.3, "__hit(15, 32)"), (7.6, "__hit(18, 4)"),
                 (8.6, "__newMob('Creature-0-1-2-3-40-0004')")],
         script=[(0.0, 1.000), (1.6, 0.938), (3.3, 0.906), (4.6, 0.869), (6.3, 0.838), (7.6, 0.800),
                 (8.6, 1.000)]),
    # Neutral, minding its own business.
    dict(name="Mottled Boar", level="10", level_color=LEVEL_GREEN, unit="reaction = 4, color = " + PLATE_YELLOW,
         max=180, target=False, script=[(0.0, 1.0)]),
    # Friendly plates have their own liquid, here the nameplate's green.
    dict(name="Stormwind Guard", level="25", level_color=LEVEL_RED,
         unit="friendly = true, reaction = 5, color = " + PLATE_GREEN, max=1500, target=False,
         settings={"plateFriendly": "true"}, script=[(0.0, 1.0)]),
]


def plate_pieces():
    """The captured pieces, trimmed to what shows: the atlas's transparent margin goes, so each piece is placed by
    the edges measured on the screenshots."""
    out = {}
    for name in PLATE_PIECES:
        path = os.path.join(ART, name + ".png")
        if not os.path.exists(path):
            sys.exit(f"No nameplate art in {ART}: run /sab capture plates in game, then capture_art.py --plates.")
        im = Image.open(path).convert("RGBA")
        box = im.getchannel("A").point(lambda a: 255 if a > 64 else 0).getbbox()
        out[name] = im.crop(box) if box else im
    return out


def plate_session(p):
    """The addon in the mock with one nameplate, p's mob, as the target if p has spells (DoTs are cast at the
    target); its liquid's frame becomes __hMover and its DoT marker __marker()."""
    spells = p.get("spells", {})
    lines = [f"__spells[{sid}] = {{ {name!r}, {desc!r} }}" for sid, (name, desc) in spells.items()]
    settings = dict({"plateHealth": "true", "plateDots": "true"}, **p.get("settings", {}))
    return render.Session(ADDON, settings=settings, before_login="SmoothAnimatedBarsDB.setupDone = true",
                          scenario=p.get("events", []), after_login="\n".join(lines) + """
        MOB = { %s, guid = 'Creature-0-1-2-3-40-0001', name = %r }
        __showPlate('nameplate1', MOB)
        if %s then __target = MOB; __fire('PLAYER_TARGET_CHANGED') end
        function __cast(id, guid)
            __fire('UNIT_SPELLCAST_SENT', 'player', MOB.name, guid, id)
            __fire('UNIT_SPELLCAST_SUCCEEDED', 'player', guid, id)
        end
        function __hit(amount, school) __fire('UNIT_COMBAT', 'target', 'WOUND', '', amount, school) end
        function __crit(amount, school) __fire('UNIT_COMBAT', 'target', 'WOUND', 'CRITICAL', amount, school) end
        -- A fresh mob of the same kind on the same plate, the old one's DoTs gone with it.
        function __newMob(guid) MOB.guid = guid; __fire('PLAYER_TARGET_CHANGED'); __fire('UNIT_HEALTH', 'nameplate1') end
        local bar = __plates.nameplate1.UnitFrame.HealthBarsContainer.healthBar
        bar.w, bar.h = %d, %d  -- Forever's bar; the liquid follows the bar's size
        for _, clip in ipairs(__frames) do
            if clip.parent == bar and not clip.SetValue and clip.clipsChildren then
                for _, f in ipairs(__frames) do if f.parent == clip and not f.SetValue then __hMover = __hMover or f end end
            end
        end
        function __marker() local _, _, m = __ns.Marker.State(); return m and m[bar] end
        -- The mock gives masks no size, so the renderer would blank what they cut; the plate's mask is drawn here.
        for _, r in ipairs(__regions) do r.masks = nil end
    """ % (p["unit"], p["name"], "true" if spells else "false", PLATE_W, PLATE_H))


PLATE_X = 30               # the bar's left edge in its cell: room for the kill icon left of it
PLATE_ICON_HEIGHT, PLATE_ICON_GAP = 20, 7  # Marker.lua: the kill icon on a plate, against ICON_HEIGHT's 30
_plate_skull = []


def plate_skull():
    """The game's skull from the target frame's capture (target-killicon), cut to what shows and scaled from the
    target frame's 30 units to a plate's 20. None if not captured."""
    if not _plate_skull:
        path = os.path.join(ART, "target-killicon.png")
        icon = None
        if os.path.exists(path):
            raw = Image.open(path).convert("RGBA")
            box = raw.getchannel("A").getbbox()
            if box:
                per_unit = raw.width / FRAME_W * 30 / PLATE_ICON_HEIGHT  # raw px per plate unit
                icon = raw.crop(box)
                icon = resize_rgba(icon, (max(1, round(icon.width / per_unit * K)),
                                          max(1, round(icon.height / per_unit * K))))
        _plate_skull.append(icon)
    return _plate_skull[0]


def draw_plate(session, pieces, plate_mask, cell, p, health, actual):
    """One plate onto a copy of cell (RGBA): background, the liquid and DoT liquids at health (a fraction), then
    the darkening or the target's glow, the level box, the name, and the kill icon once the DoTs will take more than
    the mob's actual health (a fraction: the client's kill bar does not ease)."""
    def place(img, piece, left, top, w, h):
        im = resize_rgba(pieces[piece], (max(1, round(w * K)), max(1, round(h * K))))
        img.alpha_composite(im, (round(left * K), round(top * K)))

    bx, by = PLATE_X, 24
    img = cell.copy()
    gx, gy = bx - PLATE_BG[0], by - PLATE_BG[2]
    gw, gh = PLATE_W + PLATE_BG[0] + PLATE_BG[1], PLATE_H + PLATE_BG[2] + PLATE_BG[3]
    place(img, "plate-modern-bg", gx, gy, gw, gh)

    base = img.convert("RGB")
    box = (round(bx * K), round(by * K), round((bx + PLATE_W) * K), round((by + PLATE_H) * K))
    mask = plate_mask.resize((box[2] - box[0], box[3] - box[1]), Image.LANCZOS)

    def layer(image, frame, right, lcut, rcut):
        # The liquid's frame ends at right (bar units); it shows from lcut to rcut, under the plate's mask.
        session.frame = frame
        session.lua.execute(f"{frame}.h = {PLATE_H}")
        full = session.render(image, bx * K + (right - PLATE_W) * K, by * K, K)
        left, r = max(box[0], round((bx + lcut) * K)), min(box[2], round((bx + rcut) * K))
        out = image.copy()
        if r > left:
            out.paste(full.crop((left, box[1], r, box[3])), (left, box[1]),
                      mask.crop((left - box[0], 0, r - box[0], mask.height)))
        return out

    # Back to front: each DoT liquid from where it will end to the edge in front of it, then the health over them,
    # its front moved back to where the health will end (Bars.Front).
    # The DoT marker's liquids come later, with masks of their own; the mock gives masks no size.
    session.lua.execute("for _, r in ipairs(__regions) do r.masks = nil end")
    edge = end = health * PLATE_W
    m = session.lua.eval("__marker()")
    if m is not None and m.clip.shown:
        session.lua.execute("__d1, __d2 = __marker().liquids[1].mover, __marker().liquids[2].mover")
        e1 = edge - (m.liquids[1].shown if m.liquids[1].pool.shown else 0) / p["max"] * PLATE_W
        end = e1
        if m.liquids[2].pool.shown:
            e2 = e1 - m.liquids[2].shown / p["max"] * PLATE_W
            base = layer(base, "__d2", e1, e2 - OVERLAP, e1 + ROOM)
            end = e2
        if m.liquids[1].pool.shown:
            base = layer(base, "__d1", edge, e1 - OVERLAP, edge + ROOM)
    base = layer(base, "__hMover", end, 0, end + ROOM)
    img = base.convert("RGBA")
    # The fill's shading over all the liquids (Bars.lua, PlateShade, a level above the health).
    shade = Image.open(os.path.join(ADDON, "Media", "PlateShade.tga")).convert("RGBA")
    img.alpha_composite(resize_rgba(shade, (box[2] - box[0], box[3] - box[1])), (box[0], box[1]))

    if p["target"]:
        place(img, "plate-selected", gx - PLATE_GLOW[0], gy - PLATE_GLOW[2], gw + PLATE_GLOW[0] + PLATE_GLOW[1],
              gh + PLATE_GLOW[2] + PLATE_GLOW[3])
    else:
        place(img, "plate-deselected", bx, by, PLATE_W, PLATE_H)
    lx, ly, lw, lh = bx + PLATE_W + 5, by - 3, 28, PLATE_H + 5
    place(img, "plate-level", lx, ly, lw, lh)
    if p["target"]:
        place(img, "plate-level-selected", lx - 3, ly - 3, lw + 6, lh + 7)
    draw = ImageDraw.Draw(img)
    for s, xy, size, color, anchor in ((p["level"], (lx + lw / 2, ly + lh / 2), 10, p["level_color"], "mm"),
                                       (p["name"], (bx + PLATE_W / 2, by - 2), 12, (255, 255, 255), "md")):
        draw.text((xy[0] * K, xy[1] * K), s, font=render.font(size * K), fill=color + (255,), anchor=anchor,
                  stroke_width=max(1, round(K)), stroke_fill=(0, 0, 0, 255))
    skull = plate_skull()
    if m is not None and m.clip.shown and m.window.shown and skull and m.value >= actual * p["max"]:
        # Its window's right edge PLATE_ICON_GAP left of the bar, centred on the bar's height, pulsing.
        alpha = np.asarray(skull.getchannel("A")).astype(np.float32) * m.icon.alpha
        icon = skull.copy()
        icon.putalpha(Image.fromarray(alpha.astype(np.uint8)))
        img.alpha_composite(icon, (round((bx - PLATE_ICON_GAP) * K) - icon.width,
                                   round((by + PLATE_H / 2) * K - icon.height / 2)))
    return img


def plates():
    """Four nameplates through a loop, in a 2 x 2 grid: plates.webp."""
    pieces = plate_pieces()
    plate_mask = Image.open(os.path.join(ADDON, "Media", "PlateMask.tga")).getchannel("A")
    cell_w, cell_h = round((PLATE_W + PLATE_X + 38) * K), round(46 * K)
    pad = round(10 * K)
    cols = 2
    rows = math.ceil(len(PLATES) / cols)
    back = backdrop(pad * 2 + cols * cell_w, pad * 2 + rows * cell_h).convert("RGBA")
    n = round(PLATE_LOOP * FPS)
    tracks = []
    for j, p in enumerate(PLATES):
        x, y = pad + (j % cols) * cell_w, pad + (j // cols) * cell_h
        cell = back.crop((x, y, x + cell_w, y + cell_h))
        session = plate_session(p)
        fill, shown = p["script"][0][1], p["script"][0][1]
        cells, t, dt = [], 0.0, 1 / FPS
        for _ in range(n):
            goal = [h for when, h in p["script"] if when <= t][-1]
            if round(goal * p["max"]) != round(shown * p["max"]):
                session.lua.execute("__fire('UNIT_HEALTH', 'nameplate1')")
                if goal > shown + 0.5:
                    fill = goal  # a fresh mob: its bar does not ease up
            shown = goal
            session.run_until(t)
            fill += (goal - fill) * (1 - math.exp(-8 * dt))
            cells.append(draw_plate(session, pieces, plate_mask, cell, p, fill, goal))
            t += dt
        tracks.append(cells)
        print(f"  rendered {p['name']}")
    frames = []
    for i in range(n):
        img = back.copy()
        for j, cells in enumerate(tracks):
            img.paste(cells[i], (pad + (j % cols) * cell_w, pad + (j // cols) * cell_h))
        frames.append(img.convert("RGB"))
    os.makedirs(OUT, exist_ok=True)
    webp = os.path.join(OUT, "plates.webp")
    frames[0].save(webp, save_all=True, append_images=frames[1:], duration=round(1000 / FPS), loop=0,
                   quality=92, method=6)
    print(f"wrote plates.webp ({os.path.getsize(webp) // 1024} KB)")


# ---------------------------------------------------------------------------- the personal resource display

# Forever's Personal Resource Display (Blizzard_PersonalResourceDisplay): health over power, each a
# PersonalResourceStatusBar on the plates' bronze background (plate-modern-bg, from /sab capture plates), with no mask
# of the game's, so the liquid takes the addon's own (PlateMask) and the plates' shading (PlateShade), as Bars.lua does.
# 200 wide at Edit Mode's default width; the bars' heights and the gap are Edit Mode settings, taken here as 12, 10 and
# the game's minimum 4. The background is anchored as PersonalResourceStatusBar anchors it (Blizzard_PersonalResourceDisplay
# .xml): from 2 left of and 3 above the bar to 6 right of and 7 below it. The capture drew it untrimmed in a cell from 2
# left and 3 above a 128 x 10 bar to 6 right and 6 below (Capture.lua, plate-modern-bg), so that whole cell is stretched
# over the display's anchors, as the game stretches the atlas. (Laid with the plates' measured rim, PLATE_BG, it did not
# sit around the bar.)
PRD_W, PRD_HEALTH_H, PRD_POWER_H, PRD_GAP = 200, 12, 10, 4
PRD_BG = (2, 3, 6, 7)  # left, top, right, bottom of the bar
PRD_LOOP = 14.0
PRD_MAXES = (349, 100)
# (seconds, health, rage): trading blows in combat, rage climbing to full and furious; two Heroic Strikes and a
# Hamstring spend it; the mob falls, and out of combat a bandage (8 ticks a second apart) heals while the rage ebbs.
PRD_SCRIPT = [(0.0, 1.00, 0.10), (0.8, 0.92, 0.26), (1.6, 0.92, 0.40), (2.4, 0.84, 0.55), (3.2, 0.84, 0.68),
              (4.0, 0.76, 0.82), (4.8, 0.76, 0.94), (5.4, 0.68, 1.00), (6.6, 0.68, 0.85), (7.2, 0.68, 0.70),
              (7.8, 0.68, 0.60), (9.6, 0.723, 0.57), (10.6, 0.766, 0.55), (11.6, 0.809, 0.52), (12.6, 0.852, 0.50),
              (13.6, 0.895, 0.47)]
PRD_EVENTS = [(6.6, "__rage(78, 'Cast-1')"), (7.2, "__rage(78, 'Cast-2')"), (7.8, "__rage(1715, 'Cast-3')"),
              (8.6, "__channel(746, 'Cast-4')")]
PRD_BANDAGE = {746: ("First Aid", "Heals 120 damage over 8 sec.")}


def prd_session():
    """The addon in the mock with the display shown, a warrior on rage with the heal marker; the bars' liquid frames
    become __prdHealth and __prdPower, the bandage's liquid __prdHeal (its marker __prdHealMarker)."""
    before = heals_setup("WARRIOR", PRD_BANDAGE) + RAGE_SETUP + f"""
        SmoothAnimatedBarsDB.setupDone = true
        UnitPowerType = function(unit) return 1, 'RAGE' end
        local prd = PersonalResourceDisplayFrame
        prd:Show()
        local hb, pb = prd.HealthBarsContainer.healthBar, prd.PowerBar
        hb.w, hb.h, pb.w, pb.h = {PRD_W}, {PRD_HEALTH_H}, {PRD_W}, {PRD_POWER_H}
        pb:SetStatusBarColor(1, 0, 0)
        for _, b in ipairs({{ hb, pb }}) do b:SetMinMaxValues(0, __secret()); b:SetValue(__secret()) end
    """
    after = """
        local prd = PersonalResourceDisplayFrame
        local hb, pb = prd.HealthBarsContainer.healthBar, prd.PowerBar
        local function mover(bar)
            for _, clip in ipairs(__frames) do
                if clip.parent == bar and not clip.SetValue and clip.clipsChildren then
                    for _, f in ipairs(__frames) do
                        if f.parent == clip and not f.SetValue then
                            f.w, f.h = bar.w, bar.h -- the client sizes it from its anchors
                            return f
                        end
                    end
                end
            end
        end
        __prdHealth, __prdPower = mover(hb), mover(pb)
        local m = select(3, __ns.HealMarker.State())[hb]
        __prdHealMarker, __prdHeal = m, m.liquids[1].mover
        __prdHeal.w, __prdHeal.h = hb.w, hb.h
        -- The mock gives masks no size, so the renderer would blank what they cut; the plate mask is drawn here.
        local unmasked = 0
        function __unmask()
            for i = unmasked + 1, #__regions do __regions[i].masks = nil end
            unmasked = #__regions
        end
        __unmask()
    """
    off = {k: "false" for k in ("playerHealth", "playerPower", "targetHealth", "targetPower")}
    return render.Session(ADDON, settings=off, before_login=before, after_login=after, scenario=PRD_EVENTS)


def draw_prd_bar(session, img, bg, plate_mask, shade, bx, by, h, layers):
    """One display bar onto img (RGB) with its top-left at (bx, by) in units: the bronze background, then each of
    layers ((frame, right edge, left cut, right cut) in bar units, back to front) cut to the plate mask, the shading
    over them, then their motes, which fly free in the clip frame's room (SPILL above, below and past the end)."""
    gx, gy = bx - PRD_BG[0], by - PRD_BG[1]
    gw, gh = PRD_W + PRD_BG[0] + PRD_BG[2], h + PRD_BG[1] + PRD_BG[3]
    canvas = img.convert("RGBA")
    canvas.alpha_composite(resize_rgba(bg, (round(gw * K), round(gh * K))), (round(gx * K), round(gy * K)))
    base = canvas.convert("RGB")
    box = (round(bx * K), round(by * K), round((bx + PRD_W) * K), round((by + h) * K))
    mask = plate_mask.resize((box[2] - box[0], box[3] - box[1]), Image.LANCZOS)
    for frame, right, lcut, rcut in layers:
        session.frame = frame
        full = session.render(base, bx * K + (right - PRD_W) * K, by * K, K, only=lambda r: not is_mote(r))
        left, r = max(box[0], round((bx + lcut) * K)), min(box[2], round((bx + rcut) * K))
        if r > left:
            base.paste(full.crop((left, box[1], r, box[3])), (left, box[1]),
                       mask.crop((left - box[0], 0, r - box[0], mask.height)))
    canvas = base.convert("RGBA")
    canvas.alpha_composite(resize_rgba(shade, (box[2] - box[0], box[3] - box[1])), box[:2])
    base = canvas.convert("RGB")
    room = (box[0], round((by - SPILL) * K), round((bx + PRD_W + SPILL) * K), round((by + h + SPILL) * K))
    for frame, right, lcut, _ in layers:
        session.frame = frame
        motes = session.render(base, bx * K + (right - PRD_W) * K, by * K, K, only=is_mote)
        left = max(room[0], round((bx + max(0.0, lcut)) * K))
        base.paste(motes.crop((left, room[1], room[2], room[3])), (left, room[1]))
    img.paste(base)


def prd():
    """A warrior's Personal Resource Display through a fight and a bandage: prd.webp."""
    bg = Image.open(os.path.join(ART, "plate-modern-bg.png")).convert("RGBA")  # untrimmed: its cell is its anchors
    plate_mask = Image.open(os.path.join(ADDON, "Media", "PlateMask.tga")).getchannel("A")
    shade = Image.open(os.path.join(ADDON, "Media", "PlateShade.tga")).convert("RGBA")
    session = prd_session()
    pad = 22
    w, h = round((PRD_W + 2 * pad) * K), round((PRD_HEALTH_H + PRD_GAP + PRD_POWER_H + 2 * pad) * K)
    back = backdrop(w, h)
    hy, py = pad, pad + PRD_HEALTH_H + PRD_GAP

    def at(t):
        return [r for r in PRD_SCRIPT if r[0] <= t][-1][1:]

    fills, shown = list(at(0)), at(0)
    frames, t, dt = [], 0.0, 1 / FPS
    while t < PRD_LOOP - 1e-9:
        goal = at(t)
        if round(goal[0] * PRD_MAXES[0]) != round(shown[0] * PRD_MAXES[0]):
            session.lua.execute("__fire('UNIT_HEALTH', 'player')")
        if round(goal[1] * PRD_MAXES[1]) != round(shown[1] * PRD_MAXES[1]):
            session.lua.execute("__fire('UNIT_POWER_UPDATE', 'player', 'RAGE')")
        shown = goal
        # The client's share of the rage, for the fury's curve.
        session.lua.execute(f"__powerPercent.player = {goal[1]}")
        session.run_until(t)
        session.lua.execute("__unmask()")
        for i in (0, 1):
            fills[i] += (goal[i] - fills[i]) * (1 - math.exp(-8 * dt))
        img = back.copy()
        health = fills[0] * PRD_W
        layers = []
        m = session.lua.eval("__prdHealMarker")
        if m.clip.shown and m.liquids[1].pool.shown:
            # The bandage's liquid ahead of the health, under it, reaching a little back under its front.
            layers.append(("__prdHeal", health + m.liquids[1].shown / PRD_MAXES[0] * PRD_W, health - OVERLAP, PRD_W))
        layers.append(("__prdHealth", health, 0, health + ROOM))
        draw_prd_bar(session, img, bg, plate_mask, shade, pad, hy, PRD_HEALTH_H, layers)
        rage = fills[1] * PRD_W
        draw_prd_bar(session, img, bg, plate_mask, shade, pad, py, PRD_POWER_H, [("__prdPower", rage, 0, rage + ROOM)])
        frames.append(img)
        t += dt
    os.makedirs(OUT, exist_ok=True)
    webp = os.path.join(OUT, "prd.webp")
    frames[0].save(webp, save_all=True, append_images=frames[1:], duration=round(1000 / FPS), loop=0,
                   quality=92, method=6)
    print(f"wrote prd.webp ({os.path.getsize(webp) // 1024} KB)")


# ---------------------------------------------------------------------------- the party

# Forever's party member frames (Mainline PartyFrameTemplates.xml), stacked as the game stacks them, from the pieces
# /sab capture party captured (capture_art.py --party): each frame 120 x 53, its art and its class portrait filling
# the frame's cell, the bars where Preview.lua's PARTY puts them (y measured down here), cut by the captured masks.
PARTY_W, PARTY_H, PARTY_GAP = 120, 53, 8
PARTY_NAME_AT = (48, 13)  # the name's left end and middle
# The setup's example party (Preview.lua, MEMBERS): name, class, power type, most power.
PARTY_MEMBERS = [("Brannoc", "WARRIOR", "RAGE", 100), ("Elisande", "PRIEST", "MANA", 300),
                 ("Corvin", "MAGE", "MANA", 320), ("Tessaly", "ROGUE", "ENERGY", 100)]
PARTY_HEALTH_MAX = 400
PARTY_LOOP = 8.4
# { seconds, each member's health and power as fractions }: the warrior takes the hits and builds rage, the priest
# spends mana healing, the mage casting, the rogue's energy comes and goes (Preview.lua, PARTY_SCRIPT).
PARTY_SCRIPT = [(0.0, 1.00, 0.10, 1.00, 0.90, 1.00, 1.00, 1.00, 1.00),
                (1.2, 0.70, 0.40, 1.00, 0.90, 0.90, 0.80, 1.00, 0.60),
                (2.2, 0.85, 0.55, 1.00, 0.75, 0.90, 0.65, 0.80, 0.40),
                (3.0, 0.55, 0.70, 1.00, 0.75, 0.90, 0.50, 0.80, 0.75),
                (4.0, 0.80, 0.30, 0.85, 0.60, 0.90, 0.50, 0.80, 0.35),
                (5.0, 0.80, 0.30, 0.85, 0.60, 0.65, 0.35, 0.60, 0.70),
                (6.0, 1.00, 0.20, 0.85, 0.45, 0.85, 0.35, 0.60, 1.00),
                (7.2, 1.00, 0.10, 1.00, 0.90, 1.00, 1.00, 1.00, 1.00)]
# The power mask, placed by Forever's source (Camelot ArtLayoutInfo.Player: 16, -26 from the frame), came out over the
# gold divider above the mana slot and its left border in the captured art, which the game's own fill does not reach in
# game. Measured on the captured art, the slot's dark interior runs from 31.7 to 39.1 down and from 46.1 across, the
# mask from 30.1 and 45.1: so in the gallery the mask and the bar sit PARTY_POWER_SHIFT further right and down.
PARTY_POWER_SHIFT = (1.5, 1.9)
BARS[("party", "health")] = (47, 20, 70, 10)
BARS[("party", "power")] = (44 + PARTY_POWER_SHIFT[0], 31 + PARTY_POWER_SHIFT[1], 74, 7)


def party_pieces():
    """The captured party pieces, at K px a unit, by name."""
    path = os.path.join(ART, "party.json")
    if not os.path.exists(path):
        sys.exit(f"No party art in {ART}: run /sab capture party in game, then capture_art.py --party.")
    names = json.load(open(path, encoding="utf-8"))["cells"]
    size = (round(PARTY_W * K), round(PARTY_H * K))
    pieces = {n: resize_rgba(Image.open(os.path.join(ART, n + ".png")).convert("RGBA"), size) for n in names}
    shifted = Image.new("RGBA", size, (0, 0, 0, 0))
    shifted.paste(pieces["party-power-mask"], (round(PARTY_POWER_SHIFT[0] * K), round(PARTY_POWER_SHIFT[1] * K)))
    pieces["party-power-mask"] = shifted
    return pieces


def party_session():
    """The addon in the mock with four party members shown; member i's liquid frames become __party<i>_health and
    __party<i>_power."""
    lines = []
    for i, (_, cls, token, _) in enumerate(PARTY_MEMBERS, 1):
        lines.append(f"__units.party{i} = {{ isOtherPlayer = true, class = {cls!r}, power = {POWER[token]} }}")
    before = "\n".join(lines) + """
        SmoothAnimatedBarsDB.setupDone = true
        for i = 1, 4 do
            local f = PartyFrame['MemberFrame' .. i]
            for _, b in ipairs({ f.HealthBarContainer.HealthBar, f.ManaBar }) do
                b:SetMinMaxValues(0, __secret()); b:SetValue(__secret())
            end
            f:Show()
        end
    """
    after = """
        __fire('GROUP_ROSTER_UPDATE')
        for i = 1, 4 do
            local f = PartyFrame['MemberFrame' .. i]
            for kind, bar in pairs({ health = f.HealthBarContainer.HealthBar, power = f.ManaBar }) do
                for _, clip in ipairs(__frames) do
                    if clip.parent == bar and not clip.SetValue and clip.clipsChildren then
                        for _, x in ipairs(__frames) do
                            if x.parent == clip and not x.SetValue then
                                x.w, x.h = bar.w, bar.h -- the client sizes it from its anchors
                                _G['__party' .. i .. '_' .. kind] = x
                            end
                        end
                        break
                    end
                end
            end
        end
        -- The captured masks are applied here instead; the mock gives masks no size.
        local unmasked = 0
        function __unmask()
            for i = unmasked + 1, #__regions do __regions[i].masks = nil end
            unmasked = #__regions
        end
        __unmask()
    """
    off = {k: "false" for k in ("playerHealth", "playerPower", "targetHealth", "targetPower")}
    return render.Session(ADDON, settings=off, before_login=before, after_login=after)


def party():
    """Four party members through a fight, stacked as the game shows them: party.webp."""
    art = party_pieces()
    session = party_session()
    pad = 18
    w = round((PARTY_W + 2 * pad) * K)
    h = round((4 * PARTY_H + 3 * PARTY_GAP + 2 * pad) * K)
    back = backdrop(w, h)
    keys = [(i, kind) for i in range(4) for kind in ("health", "power")]
    maxes = {(i, "health"): PARTY_HEALTH_MAX for i in range(4)}
    maxes.update({(i, "power"): m[3] for i, m in enumerate(PARTY_MEMBERS)})

    def at(t):
        row = [r for r in PARTY_SCRIPT if r[0] <= t][-1]
        return {(i, kind): row[1 + 2 * i + (kind == "power")] for i, kind in keys}

    fills, shown = dict(at(0)), at(0)
    frames, t, dt = [], 0.0, 1 / FPS
    while t < PARTY_LOOP - 1e-9:
        goal = at(t)
        for i, kind in keys:
            if round(goal[(i, kind)] * maxes[(i, kind)]) != round(shown[(i, kind)] * maxes[(i, kind)]):
                if kind == "health":
                    session.lua.execute(f"__fire('UNIT_HEALTH', 'party{i + 1}')")
                else:
                    session.lua.execute(f"__fire('UNIT_POWER_UPDATE', 'party{i + 1}', {PARTY_MEMBERS[i][2]!r})")
        shown = goal
        session.run_until(t)
        session.lua.execute("__unmask()")
        for k in keys:
            fills[k] += (goal[k] - fills[k]) * (1 - math.exp(-8 * dt))
        img = back.copy()
        for i, (name, cls, _, _) in enumerate(PARTY_MEMBERS):
            fx, fy = round(pad * K), round((pad + i * (PARTY_H + PARTY_GAP)) * K)
            canvas = img.convert("RGBA")
            canvas.alpha_composite(art[f"party-portrait-{cls.lower()}"], (fx, fy))
            canvas.alpha_composite(art["party-art"], (fx, fy))
            img.paste(canvas.convert("RGB"))
            for kind in ("health", "power"):
                draw_bar(session, img, art, fx, fy, "party", kind, fills[(i, kind)], frame=f"__party{i + 1}_{kind}")
            draw = ImageDraw.Draw(img)
            draw.text((fx + PARTY_NAME_AT[0] * K, fy + PARTY_NAME_AT[1] * K), name, font=render.font(9 * K),
                      fill=(255, 209, 0), anchor="lm", stroke_width=max(1, round(K * 0.4)), stroke_fill=(0, 0, 0))
        frames.append(img)
        t += dt
    os.makedirs(OUT, exist_ok=True)
    webp = os.path.join(OUT, "party.webp")
    frames[0].save(webp, save_all=True, append_images=frames[1:], duration=round(1000 / FPS), loop=0,
                   quality=92, method=6)
    print(f"wrote party.webp ({os.path.getsize(webp) // 1024} KB)")


# ---------------------------------------------------------------------------- the raid

# A ten-player raid in raid-style frames (CompactUnitFrameTemplate), two groups of five side by side as Edit Mode keeps
# groups together, each member 98 x 44 with its health bar 1 in from the edges and its power bar the bottom 8 of it
# (Blizzard's DefaultCompactUnitFrameSetup), from the pieces /sab capture raid captured (capture_art.py --raid): the
# frame's background, the power bar's, the target's highlight and the group's border. Without them, plain stand-ins.
RAID_W, RAID_H, RAID_POWER_H = 98, 44, 8
RAID_GROUP_GAP = 10
# The editor's example raid (Preview.lua, RAIDERS): name, class, power type, most power.
RAIDERS = [("Brannoc", "WARRIOR", "RAGE", 100), ("Elisande", "PRIEST", "MANA", 300), ("Corvin", "MAGE", "MANA", 320),
           ("Tessaly", "ROGUE", "ENERGY", 100), ("Garrik", "PALADIN", "MANA", 280), ("Mirelle", "DRUID", "MANA", 300),
           ("Vexa", "WARLOCK", "MANA", 310), ("Aldric", "PRIEST", "MANA", 290), ("Sorin", "MAGE", "MANA", 330),
           ("Hadrek", "WARRIOR", "RAGE", 100)]
RAID_STEP, RAID_STEPS = 1.0, 8
# A pull: the two warriors tank and build rage, everyone takes a burst of damage at 3 s that the healers bring back,
# the casters' mana drains and the rogue's energy comes and goes. Each member's health and power for each step (as
# fractions); the loop ends where it began.
RAID_HEALTH = [[1.00, 0.72, 0.86, 0.58, 0.80, 0.66, 0.90, 1.00],   # Brannoc, the main tank
               [1.00, 1.00, 0.95, 0.62, 0.78, 0.90, 1.00, 1.00],
               [1.00, 0.95, 1.00, 0.55, 0.70, 0.85, 0.95, 1.00],
               [1.00, 1.00, 0.88, 0.50, 0.64, 0.80, 0.92, 1.00],
               [1.00, 0.96, 1.00, 0.66, 0.82, 0.94, 1.00, 1.00],
               [1.00, 1.00, 0.97, 0.60, 0.76, 0.92, 1.00, 1.00],
               [0.92, 0.85, 0.80, 0.48, 0.66, 0.74, 0.86, 0.92],   # Vexa, paying life for mana
               [1.00, 1.00, 1.00, 0.64, 0.84, 0.95, 1.00, 1.00],
               [1.00, 0.94, 1.00, 0.52, 0.72, 0.86, 0.96, 1.00],
               [1.00, 0.84, 0.70, 0.46, 0.62, 0.78, 0.88, 1.00]]   # Hadrek, the off tank
RAID_POWER = [[0.10, 0.45, 0.70, 0.90, 0.55, 0.80, 0.40, 0.10],
              [1.00, 0.92, 0.84, 0.66, 0.52, 0.48, 0.70, 1.00],
              [1.00, 0.86, 0.74, 0.64, 0.52, 0.42, 0.70, 1.00],
              [1.00, 0.55, 0.85, 0.35, 0.75, 0.45, 0.90, 1.00],
              [1.00, 0.95, 0.90, 0.70, 0.60, 0.58, 0.80, 1.00],
              [1.00, 0.95, 0.88, 0.70, 0.56, 0.52, 0.76, 1.00],
              [1.00, 0.88, 0.96, 0.84, 0.72, 0.82, 0.90, 1.00],
              [1.00, 0.94, 0.86, 0.62, 0.50, 0.46, 0.72, 1.00],
              [1.00, 0.84, 0.70, 0.58, 0.46, 0.38, 0.68, 1.00],
              [0.10, 0.35, 0.60, 0.80, 0.50, 0.70, 0.30, 0.10]]
RAID_TARGET = 0  # the player's target: the main tank, with the game's highlight round the frame


def raid_pieces():
    """The captured raid pieces at K px a unit, by name; None without a capture (stand-ins are drawn instead)."""
    path = os.path.join(ART, "raid.json")
    if not os.path.exists(path):
        print("  no raid art yet (/sab capture raid, then capture_art.py --raid): drawing stand-ins")
        return None
    cells = json.load(open(path, encoding="utf-8"))["cells"]
    return {n: resize_rgba(Image.open(os.path.join(ART, n + ".png")).convert("RGBA"), (round(w * K), round(h * K)))
            for n, (w, h) in cells.items()}


def raid_session():
    """The addon in the mock with ten raid-style frames, raid1..10 in CompactRaidGroup1-2Member1-5, their health and
    power on; each bar's liquid frame becomes __raid<i>_health and __raid<i>_power."""
    lines = ["__cvars.raidFramesDisplayClassColor = '1'"]
    for i, (_, cls, token, _) in enumerate(RAIDERS, 1):
        lines.append(f"__units.raid{i} = {{ isOtherPlayer = true, class = {cls!r}, power = {POWER[token]} }}")
    before = "\n".join(lines) + f"""
        SmoothAnimatedBarsDB.setupDone = true
        for i = 1, {len(RAIDERS)} do
            local name = string.format('CompactRaidGroup%dMember%d', math.floor((i - 1) / 5) + 1, (i - 1) % 5 + 1)
            local f = CreateFrame('Button', name, UIParent)
            f.w, f.h, f.unit, f.displayedUnit = {RAID_W}, {RAID_H}, 'raid' .. i, 'raid' .. i
            f.healthBar = CreateFrame('StatusBar', name .. 'HealthBar', f)
            f.healthBar.w, f.healthBar.h = {RAID_W - 2}, {RAID_H - 2 - RAID_POWER_H}
            f.powerBar = CreateFrame('StatusBar', name .. 'PowerBar', f)
            f.powerBar.w, f.powerBar.h = {RAID_W - 2}, {RAID_POWER_H}
            f.powerBar:SetFrameLevel(5)
            for _, b in ipairs({{ f.healthBar, f.powerBar }}) do
                b:SetMinMaxValues(0, __secret()); b:SetValue(__secret())
            end
            f:Show()
        end
    """
    after = f"""
        -- Each bar's liquid: in the first frame of ours on the bar that holds a frame (a raid bar's does not clip; a
        -- mask cuts it), the frame inside.
        for i = 1, {len(RAIDERS)} do
            local name = string.format('CompactRaidGroup%dMember%d', math.floor((i - 1) / 5) + 1, (i - 1) % 5 + 1)
            local f = _G[name]
            for kind, bar in pairs({{ health = f.healthBar, power = f.powerBar }}) do
                local holder
                for _, c in ipairs(__frames) do
                    if c.parent == bar and not c.SetValue and not holder then
                        for _, x in ipairs(__frames) do
                            if x.parent == c then holder = c; break end
                        end
                    end
                end
                for _, x in ipairs(__frames) do
                    if holder and x.parent == holder and not x.SetValue then
                        x.w, x.h = bar.w, bar.h -- the client sizes it from its anchors
                        _G['__raid' .. i .. '_' .. kind] = x
                    end
                end
            end
        end
        -- The bar's own square mask cuts it in game; here the drawing is cut to the bar instead.
        local unmasked = 0
        function __unmask()
            for i = unmasked + 1, #__regions do __regions[i].masks = nil end
            unmasked = #__regions
        end
        __unmask()
    """
    on = {k: "false" for k in ("playerHealth", "playerPower", "targetHealth", "targetPower", "partyHealth",
                               "partyPower", "prdHealth", "prdPower")}
    on.update(raidHealth="true", raidPower="true")
    return render.Session(ADDON, settings=on, before_login=before, after_login=after)


def raid():
    """Ten raid members through a pull, in two groups as the game keeps them: raid.webp."""
    art = raid_pieces()
    session = raid_session()
    missing = [i for i in range(len(RAIDERS)) for kind in ("health", "power")
               if session.lua.eval(f"_G['__raid{i + 1}_{kind}'] == nil")]
    if missing:
        sys.exit(f"No raid liquid on members {sorted(set(m + 1 for m in missing))}: is raidHealth on?")
    pad = 14
    group_w = RAID_W + 4  # the group's border: 2 each side
    w = round((2 * pad + 2 * group_w + RAID_GROUP_GAP) * K)
    h = round((2 * pad + 5 * RAID_H + 5) * K)
    back = backdrop(w, h)
    keys = [(i, kind) for i in range(len(RAIDERS)) for kind in ("health", "power")]
    maxes = {(i, "health"): 400 for i in range(len(RAIDERS))}
    maxes.update({(i, "power"): m[3] for i, m in enumerate(RAIDERS)})
    loop = RAID_STEP * RAID_STEPS

    def at(t):
        n = min(RAID_STEPS - 1, int(t / RAID_STEP))
        return {(i, kind): (RAID_HEALTH if kind == "health" else RAID_POWER)[i][n] for i, kind in keys}

    def origin(i):
        """Member i's top-left, in px."""
        g, row = divmod(i, 5)
        return (round((pad + 2 + g * (group_w + RAID_GROUP_GAP)) * K), round((pad + 2 + row * RAID_H) * K))

    def paste(img, piece, x, y):
        canvas = img.convert("RGBA")
        canvas.alpha_composite(piece, (x, y))
        img.paste(canvas.convert("RGB"))

    # What stays still: the groups' borders, each frame's background and its power bar's.
    base = back.copy()
    draw = ImageDraw.Draw(base)
    for g in range(2):
        gx, gy = round((pad + g * (group_w + RAID_GROUP_GAP)) * K), round(pad * K)
        if art:
            paste(base, art["raid-group"], gx, gy)
    for i in range(len(RAIDERS)):
        fx, fy = origin(i)
        if art:
            paste(base, art["raid-bg"], fx, fy)
            paste(base, art["raid-power-bg"], fx + round(K), fy + round((RAID_H - 1 - RAID_POWER_H) * K))
        else:
            draw.rectangle((fx, fy, fx + round(RAID_W * K) - 1, fy + round(RAID_H * K) - 1), fill=(20, 20, 20),
                           outline=(0, 0, 0), width=max(1, round(K / 2)))

    fills, shown = dict(at(0)), at(0)
    frames, t, dt = [], 0.0, 1 / FPS
    while t < loop - 1e-9:
        goal = at(t)
        for i, kind in keys:
            if round(goal[(i, kind)] * maxes[(i, kind)]) != round(shown[(i, kind)] * maxes[(i, kind)]):
                if kind == "health":
                    session.lua.execute(f"__fire('UNIT_HEALTH', 'raid{i + 1}')")
                else:
                    session.lua.execute(f"__fire('UNIT_POWER_UPDATE', 'raid{i + 1}', {RAIDERS[i][2]!r})")
        shown = goal
        session.run_until(t)
        session.lua.execute("__unmask()")
        for k in keys:
            fills[k] += (goal[k] - fills[k]) * (1 - math.exp(-8 * dt))
        img = base.copy()
        for i, (name, _, _, _) in enumerate(RAIDERS):
            fx, fy = origin(i)
            for kind, top, bh in (("health", 1, RAID_H - 2 - RAID_POWER_H), ("power", RAID_H - 1 - RAID_POWER_H,
                                                                              RAID_POWER_H)):
                bx, by = fx + round(K), fy + round(top * K)
                bw = round((RAID_W - 2) * K)
                sub = img.crop((bx, by, bx + bw, by + round(bh * K)))
                session.frame = f"__raid{i + 1}_{kind}"
                # The liquid's frame ends at the fill's edge; cut to the bar, as the game's square mask cuts it.
                img.paste(session.render(sub, (fills[(i, kind)] - 1) * bw, 0, K), (bx, by))
            if art and i == RAID_TARGET:
                paste(img, art["raid-selected"], fx, fy)
            d = ImageDraw.Draw(img)
            d.text((fx + 4 * K, fy + 3 * K), name, font=render.font(8 * K), fill=(255, 255, 255), anchor="lt",
                   stroke_width=max(1, round(K * 0.35)), stroke_fill=(0, 0, 0))
        frames.append(img)
        t += dt
    os.makedirs(OUT, exist_ok=True)
    webp = os.path.join(OUT, "raid.webp")
    frames[0].save(webp, save_all=True, append_images=frames[1:], duration=round(1000 / FPS), loop=0,
                   quality=92, method=6)
    print(f"wrote raid.webp ({os.path.getsize(webp) // 1024} KB)")


if __name__ == "__main__":
    if not ONLY or any(k in ONLY for k in list(SCENARIOS) + ["themes", "tall"]):
        art = load_art()
        for key in SCENARIOS:
            if not ONLY or key in ONLY:
                scenario(art, key)
        if not ONLY or "themes" in ONLY:
            themes(art)
        if not ONLY or "tall" in ONLY:
            tall(art)
    if not ONLY or "plates" in ONLY:
        plates()
    if not ONLY or "prd" in ONLY:
        prd()
    if not ONLY or "party" in ONLY:
        party()
    if not ONLY or "raid" in ONLY:
        raid()
