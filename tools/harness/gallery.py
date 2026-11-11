"""Gallery images: the liquid in Forever's player and target frames, drawn on the game's own frame art.

Usage: python gallery.py <addon dir> [out dir] [scenario ...]
Default out dir: branding/gallery. Writes each scenario as an animated WebP (hero is the warrior, then
mage, rogue, then warlock and rend, whose targets carry the DoT marker, priest, with the heal marker, druid, with both, eating, a meal up to its buff, and mana, the build-up to mana regenerating), frames.png (a still of the warrior), themes.png (the player frame in a few themes) and plates.webp (four nameplates, from the plate art capture_art.py --plates cut out).
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
# target comes in at full health. With regen (a fraction of the bar per second), the player's power refills
# continuously, as energy and mana do on Forever, rather than in steps: each drop in its column is a spend, and
# its rises are ignored. spends: (seconds, fraction) in place of the column, with power_start where it begins.
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
    SmoothAnimatedBarsDB.heals = true
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
    SmoothAnimatedBarsDB.dots = true
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
        -- The bar masks have no art in the mock; the captured ones are applied here instead.
        for _, r in ipairs(__regions) do r.masks = nil end
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
    if key in ("hero", "rend"):
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
        session.run_until(t)
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
    # The target: Rend bleeds out of it while blows land, one a crit that makes the bleed gush.
    dict(name="Defias Pillager", level="12", level_color=LEVEL_YELLOW, unit="reaction = 2, color = " + PLATE_RED,
         max=210, target=True,
         spells={6546: ("Rend", "Wounds the target causing them to bleed for 28 damage over 12 sec.")},
         events=[(0.4, "__cast(6546, 'Cast-1')"), (1.0, "__hit(30, 1)"), (2.2, "__hit(45, 1)"),
                 (3.4, "__hit(7, 1)"), (3.6, "__crit(30, 1)"), (5.0, "__hit(40, 1)"), (6.4, "__hit(7, 1)"),
                 (8.4, "__newMob('Creature-0-1-2-3-40-0002')")],
         script=[(0.0, 1.000), (1.0, 0.857), (2.2, 0.643), (3.4, 0.610), (3.6, 0.467), (5.0, 0.276), (6.4, 0.243),
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


def draw_plate(session, pieces, plate_mask, cell, p, health):
    """One plate onto a copy of cell (RGBA): background, the liquid and DoT liquids at health (a fraction), then
    the darkening or the target's glow, the level box and the name."""
    def place(img, piece, left, top, w, h):
        im = resize_rgba(pieces[piece], (max(1, round(w * K)), max(1, round(h * K))))
        img.alpha_composite(im, (round(left * K), round(top * K)))

    bx, by = 10, 24
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
    return img


def plates():
    """Four nameplates through a loop, in a 2 x 2 grid: plates.webp."""
    pieces = plate_pieces()
    plate_mask = Image.open(os.path.join(ADDON, "Media", "PlateMask.tga")).getchannel("A")
    cell_w, cell_h = round((PLATE_W + 48) * K), round(46 * K)
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
            cells.append(draw_plate(session, pieces, plate_mask, cell, p, fill))
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


if __name__ == "__main__":
    if not ONLY or any(k in ONLY for k in list(SCENARIOS) + ["themes"]):
        art = load_art()
        for key in SCENARIOS:
            if not ONLY or key in ONLY:
                scenario(art, key)
        if not ONLY or "themes" in ONLY:
            themes(art)
    if not ONLY or "plates" in ONLY:
        plates()
