"""Generate the TGA textures used by SmoothAnimatedBars.

Usage: python make_media.py <output dir>
"""
import math
import os
import random
import struct
import sys


def write_tga(path, w, h, pixel):
    """pixel(x, y) -> (r, g, b, a) floats 0..1, y = 0 at the top."""
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 0x08)
    out = bytearray(header)
    for y in range(h - 1, -1, -1):  # bottom-left origin
        for x in range(w):
            r, g, b, a = (max(0, min(255, int(c * 255 + 0.5))) for c in pixel(x, y))
            out += bytes((b, g, r, a))
    with open(path, "wb") as f:
        f.write(out)


class TileNoise:
    """Value noise that tiles over a px x py lattice."""

    def __init__(self, px, py, seed):
        rnd = random.Random(seed)
        self.px, self.py = px, py
        self.lat = [[rnd.random() for _ in range(px)] for _ in range(py)]

    def __call__(self, x, y):
        x0, y0 = math.floor(x), math.floor(y)
        fx, fy = x - x0, y - y0
        sx, sy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
        lat, px, py = self.lat, self.px, self.py
        a = lat[y0 % py][x0 % px]
        b = lat[y0 % py][(x0 + 1) % px]
        c = lat[(y0 + 1) % py][x0 % px]
        d = lat[(y0 + 1) % py][(x0 + 1) % px]
        top = a + (b - a) * sx
        bottom = c + (d - c) * sx
        return top + (bottom - top) * sy


def fbm(octaves, u, v):
    total, norm = 0.0, 0.0
    for noise, amp in octaves:
        total += noise(u * noise.px, v * noise.py) * amp
        norm += amp
    return total / norm


def make_swirl(path, w=256, h=64):
    """Thin, warped, tileable veins - the magic inside the liquid."""
    base = [(TileNoise(8 * 2**i, 2 * 2**i, 10 + i), 0.5**i) for i in range(4)]
    warp_x = [(TileNoise(4 * 2**i, 1 * 2**i, 30 + i), 0.5**i) for i in range(3)]
    warp_y = [(TileNoise(4 * 2**i, 1 * 2**i, 50 + i), 0.5**i) for i in range(3)]

    values = []
    for y in range(h):
        row = []
        for x in range(w):
            u, v = x / w, y / h
            wu = u + (fbm(warp_x, u, v) - 0.5) * 0.35
            wv = v + (fbm(warp_y, u, v) - 0.5) * 0.9
            n = fbm(base, wu % 1.0, wv % 1.0)
            ridge = 1 - abs(2 * n - 1)
            row.append(ridge ** 5)
        values.append(row)
    peak = max(max(r) for r in values) or 1
    write_tga(path, w, h, lambda x, y: (1, 1, 1, values[y][x] / peak))


def radial(size, fn):
    c = (size - 1) / 2

    def pixel(x, y):
        dx, dy = (x - c) / c, (y - c) / c
        return fn(dx, dy, math.hypot(dx, dy))

    return pixel


def make_bubble(path, size=64):
    """Glassy bubble: soft rim lit from below right, faint body, a bright highlight and a small glint."""

    def fn(dx, dy, d):
        lit = 0.55 + 0.45 * max(0.0, (dx + dy) / 1.414)  # light passing through, toward the bottom right
        ring = math.exp(-((d - 0.8) / 0.14) ** 2) * lit
        body = 0.2 * min(1.0, max(0.0, (0.8 - d) / 0.15))
        hl = math.exp(-(math.hypot((dx + 0.3) / 1.3, dy + 0.34) / 0.24) ** 2)
        glint = 0.7 * math.exp(-(math.hypot(dx - 0.4, dy - 0.38) / 0.12) ** 2)
        a = min(1.0, ring * 0.9 + body + hl + glint)
        if d > 0.95:
            a *= max(0.0, 1 - (d - 0.95) / 0.05)
        return 1, 1, 1, a

    write_tga(path, size, size, radial(size, fn))


def make_mote(path, size=32):
    def fn(dx, dy, d):
        core = math.exp(-(d / 0.18) ** 2)
        halo = 0.35 * math.exp(-(d / 0.55) ** 2)
        star = 0.55 * (math.exp(-(dx / 0.05) ** 2) * math.exp(-(dy / 0.75) ** 2)
                       + math.exp(-(dy / 0.05) ** 2) * math.exp(-(dx / 0.75) ** 2))
        a = min(1.0, core + halo + star)
        if d > 1:
            a *= max(0.0, 1 - (d - 1) * 4)
        return 1, 1, 1, a

    write_tga(path, size, size, radial(size, fn))


def make_glow(path, size=64):
    def fn(dx, dy, d):
        return 1, 1, 1, max(0.0, math.exp(-(d / 0.45) ** 2) - 0.02)

    write_tga(path, size, size, radial(size, fn))


class TileWorley:
    """Cellular noise that tiles over cx x cy cells. Returns distances to the nearest two points."""

    def __init__(self, cx, cy, seed):
        rnd = random.Random(seed)
        self.cx, self.cy = cx, cy
        self.pts = [[(rnd.random(), rnd.random()) for _ in range(cx)] for _ in range(cy)]

    def __call__(self, u, v):
        x, y = u * self.cx, v * self.cy
        ix, iy = math.floor(x), math.floor(y)
        f1 = f2 = 9.0
        for oy in (-1, 0, 1):
            for ox in (-1, 0, 1):
                gx, gy = ix + ox, iy + oy
                px, py = self.pts[gy % self.cy][gx % self.cx]
                d = math.hypot(gx + px - x, gy + py - y)
                if d < f1:
                    f1, f2 = d, f1
                elif d < f2:
                    f2 = d
        return f1, f2


def write_field(path, w, h, field, power=1.0):
    """field(u, v) -> value >= 0; normalised to its peak and written as white with alpha."""
    values = [[field(x / w, y / h) for x in range(w)] for y in range(h)]
    peak = max(max(r) for r in values) or 1
    write_tga(path, w, h, lambda x, y: (1, 1, 1, (values[y][x] / peak) ** power))


def make_heat(path, w=256, h=64):
    """Vertical flame tongues for fire."""
    base = [(TileNoise(16 * 2**i, 2 * 2**i, 70 + i), 0.5**i) for i in range(3)]
    warp = [(TileNoise(8, 2, 80), 1.0)]

    def field(u, v):
        wu = u + (fbm(warp, u, v) - 0.5) * 0.08
        n = fbm(base, wu % 1.0, v)
        return (1 - abs(2 * n - 1)) ** 4 * (0.35 + 0.65 * v)

    write_field(path, w, h, field)


def make_flames(path, w=256, h=64):
    """Licking flame tongues, taller than wide with dark gaps between, that waver as they rise. Tiles both ways
    so a theme can scroll it upward (swirl.rise)."""
    tongues = [(TileNoise(32 * 2**i, 4 * 2**i, 190 + i), 0.5**i) for i in range(3)]
    warp = [(TileNoise(8, 4, 195), 1.0), (TileNoise(16, 8, 196), 0.5)]

    def field(u, v):
        wu = u + (fbm(warp, u, v) - 0.5) * 0.07
        n = fbm(tongues, wu % 1.0, v)
        return max(0.0, n - 0.4) ** 1.4

    write_field(path, w, h, field)


def make_ramp(path, w=4, h=64):
    """Vertical ramp: opaque at the top, fading out two thirds of the way down. Liquid.lua's shade layers map it
    once over the bar's height (flipped for the hot base)."""

    def pixel(x, y):
        v = (y + 0.5) / h
        return 1, 1, 1, max(0.0, 1 - v / 0.7) ** 1.6

    write_tga(path, w, h, pixel)


def make_cracks(path, w=256, h=64):
    """Glowing cell edges, like cooling lava."""
    cells = TileWorley(16, 4, 90)
    warp = [(TileNoise(8, 2, 91), 1.0)]

    def field(u, v):
        f1, f2 = cells((u + (fbm(warp, u, v) - 0.5) * 0.02) % 1.0, v)
        e = f2 - f1
        return math.exp(-(e / 0.06) ** 2) + 0.35 * math.exp(-(e / 0.25) ** 2)

    write_field(path, w, h, field)


def make_caustics(path, w=256, h=64):
    """Soft rippling light, like sun through water."""
    cells = TileWorley(12, 3, 100)
    warp_x = [(TileNoise(8, 2, 101), 1.0), (TileNoise(16, 4, 102), 0.5)]
    warp_y = [(TileNoise(8, 2, 103), 1.0), (TileNoise(16, 4, 104), 0.5)]

    def field(u, v):
        wu = u + (fbm(warp_x, u, v) - 0.5) * 0.06
        wv = v + (fbm(warp_y, u, v) - 0.5) * 0.25
        f1, f2 = cells(wu % 1.0, wv % 1.0)
        return math.exp(-((f2 - f1) / 0.14) ** 2)

    write_field(path, w, h, field, 1.6)


def make_nebula(path, w=256, h=64):
    """Soft clouds."""
    base = [(TileNoise(8 * 2**i, 2 * 2**i, 110 + i), 0.55**i) for i in range(4)]
    warp_x = [(TileNoise(4, 1, 120), 1.0), (TileNoise(8, 2, 121), 0.5)]
    warp_y = [(TileNoise(4, 2, 122), 1.0), (TileNoise(8, 4, 123), 0.5)]

    def field(u, v):
        wu = u + (fbm(warp_x, u, v) - 0.5) * 0.25
        wv = v + (fbm(warp_y, u, v) - 0.5) * 0.8
        n = fbm(base, wu % 1.0, wv % 1.0)
        return max(0.0, n - 0.3)

    write_field(path, w, h, field, 1.2)


def make_tendrils(path, w=256, h=64):
    """Long thin streaks that writhe, for the void."""
    base = [(TileNoise(4 * 2**i, 4 * 2**i, 130 + i), 0.5**i) for i in range(3)]
    warp_x = [(TileNoise(4, 1, 140), 1.0)]
    warp_y = [(TileNoise(4, 2, 141), 1.0), (TileNoise(8, 4, 142), 0.5)]

    def field(u, v):
        wu = u + (fbm(warp_x, u, v) - 0.5) * 0.4
        wv = v + (fbm(warp_y, u, v) - 0.5) * 1.2
        n = fbm(base, wu % 1.0, wv % 1.0)
        return (1 - abs(2 * n - 1)) ** 8

    write_field(path, w, h, field)


def make_frost(path, w=256, h=64):
    """Crystalline lines at two scales."""
    big, small = TileWorley(16, 4, 150), TileWorley(32, 8, 151)

    def field(u, v):
        a1, a2 = big(u, v)
        b1, b2 = small(u, v)
        return math.exp(-((a2 - a1) / 0.06) ** 2) + 0.3 * math.exp(-((b2 - b1) / 0.1) ** 2)

    write_field(path, w, h, field)


EDGE_CORE = 0.7  # where the bright line sits across the edge texture; Liquid.lua matches it


def make_edge(path, w=32, h=48):
    """Soft bright line along the liquid front, one per slice.

    Across: a sharp core with a soft glow into the liquid and a quick fade out of it.
    Down: ramp, flat, ramp in thirds. Neighbouring slices overlap on the ramps, which sum to 1,
    so the line blends between slices instead of stepping.
    """

    def pixel(x, y):
        u, v = (x + 0.5) / w, (y + 0.5) / h
        d = u - EDGE_CORE
        a = math.exp(-(abs(d) / 0.18) ** 4) + 0.3 * math.exp(-(d / 0.35) ** 2)
        if d > 0:
            a *= max(0.0, 1 - d / (1 - EDGE_CORE))
        k = min(1.0, v * 3, (1 - v) * 3)
        return 1, 1, 1, min(1.0, a) * math.sin(k * math.pi / 2) ** 2

    write_tga(path, w, h, pixel)


def make_core(path, w=256, h=64):
    """Light from inside the liquid: a soft band through the middle, brighter in patches.

    Tiles across; the bar maps it once from top to bottom.
    """
    patches = [(TileNoise(4 * 2**i, 1, 170 + i), 0.5**i) for i in range(3)]

    def pixel(x, y):
        u, v = x / w, (y + 0.5) / h
        band = math.exp(-((v - 0.5) / 0.26) ** 2)
        return 1, 1, 1, band * (0.45 + 0.55 * fbm(patches, u, 0.0))

    write_tga(path, w, h, pixel)


def make_bolt(path, w=256, rows=8, rh=32):
    """Lightning crawling through cloud, for inside the liquid: `rows` variants stacked, each running
    left to right, so each stroke of a flash can take a new shape.

    A jagged main arc from midpoint displacement whose brightness wanders along its length, as if parts
    of it were behind cloud, with branches that thin out to nothing at their tips. Thin core, faint halo;
    the bloom around it is drawn separately.
    """
    rnd = random.Random(180)

    def arc(x0, y0, x1, y1, amp, depth, lo, hi):
        pts = [(x0, y0), (x1, y1)]
        for _ in range(depth):
            out = [pts[0]]
            for (ax, ay), (bx, by) in zip(pts, pts[1:]):
                my = (ay + by) / 2 + (rnd.random() - 0.5) * 2 * amp
                out += [((ax + bx) / 2, max(lo, min(hi, my))), (bx, by)]
            pts, amp = out, amp * 0.75
        return pts

    values = []
    for r in range(rows):
        top = r * rh
        lo, hi = top + 4, top + rh - 4
        mid = top + rh / 2
        main = arc(2, mid + rnd.uniform(-5, 5), w - 2, mid + rnd.uniform(-5, 5), rh * 0.3, 7, lo, hi)
        waves = [(rnd.uniform(1, 4), rnd.uniform(0, 6.28)) for _ in range(3)]

        def along(x):  # brightness along the arc: dips where it passes behind cloud
            s = sum(math.sin(x / w * f * 6.28 + p) for f, p in waves) / 3
            return 0.3 + 0.7 * (0.5 + 0.5 * s) ** 1.5

        segs = [(p, q, along((p[0] + q[0]) / 2)) for p, q in zip(main, main[1:])]

        def branch(sx, sy, k0, length, depth):
            ex = sx + rnd.choice((1, 1, -1)) * length
            ey = max(lo, min(hi, sy + rnd.choice((-1, 1)) * rnd.uniform(4, rh * 0.35)))
            pts = arc(sx, sy, ex, ey, rh * 0.15, 5, lo, hi)
            n = len(pts) - 1
            for j, (p, q) in enumerate(zip(pts, pts[1:])):
                segs.append((p, q, k0 * (1 - j / n) ** 1.3))  # thins out toward the tip
            if depth > 0:
                for _ in range(2):
                    j = rnd.randrange(n // 4, n * 3 // 4)
                    branch(*pts[j], k0 * 0.6 * (1 - j / n), length * 0.45, depth - 1)

        for _ in range(4):
            j = rnd.randrange(16, len(main) - 16)
            sx, sy = main[j]
            branch(sx, sy, 0.8 * along(sx), rnd.uniform(25, 60), 1)
        values.append(segs)

    def seg_dist(px, py, ax, ay, bx, by):
        vx, vy = bx - ax, by - ay
        t = max(0.0, min(1.0, ((px - ax) * vx + (py - ay) * vy) / (vx * vx + vy * vy or 1)))
        return math.hypot(px - ax - vx * t, py - ay - vy * t)

    h = rows * rh
    field = [[0.0] * w for _ in range(h)]
    for r, segs in enumerate(values):
        for y in range(r * rh, (r + 1) * rh):
            for x in range(w):
                a = 0.0
                for (ax, ay), (bx, by), k in segs:
                    if abs(ay - y) > 8 and abs(by - y) > 8:
                        continue
                    d = seg_dist(x + 0.5, y + 0.5, ax, ay, bx, by)
                    a = max(a, k * (math.exp(-(d / 1.0) ** 2) + 0.2 * math.exp(-(d / 2.5) ** 2)))
                fade = min(1.0, x / 20, (w - 1 - x) / 20)  # arcs thin out at their ends
                field[y][x] = min(1.0, a) * fade
    write_tga(path, w, h, lambda x, y: (1, 1, 1, field[y][x]))


def make_wisp(path, size=48):
    """A soft, uneven puff of vapour, taller than wide, for wisps rising off the liquid."""
    lumps = [(TileNoise(4 * 2**i, 4 * 2**i, 200 + i), 0.5**i) for i in range(3)]

    def fn(dx, dy, d):
        e = math.hypot(dx * 1.3, dy * 0.9)
        body = max(0.0, 1 - e) ** 1.6
        return 1, 1, 1, body * (0.35 + 0.65 * fbm(lumps, (dx + 1) / 2, (dy + 1) / 2))

    write_tga(path, size, size, radial(size, fn))


def make_smoke(path, size=64):
    """A ragged drift of smoke, wider than tall, curling and torn into holes, for smoke trailing over the liquid."""
    warp_x = [(TileNoise(3 * 2**i, 3 * 2**i, 210 + i), 0.5**i) for i in range(2)]
    warp_y = [(TileNoise(3 * 2**i, 3 * 2**i, 215 + i), 0.5**i) for i in range(2)]
    detail = [(TileNoise(5 * 2**i, 5 * 2**i, 220 + i), 0.55**i) for i in range(3)]

    def fn(dx, dy, d):
        u, v = (dx + 1) / 2, (dy + 1) / 2
        # Curl: the shape is bent by slow noise, so no two puffs read as the same round blob.
        wx = dx + (fbm(warp_x, u, v) - 0.5) * 0.5
        wy = dy + (fbm(warp_y, u, v) - 0.5) * 0.5
        e = math.hypot(wx * 0.95, wy * 1.5)
        body = max(0.0, 1 - e) ** 0.8
        # Torn: thin where the detail noise is low, so the edges fray and the middle has gaps.
        n = fbm(detail, u, v)
        tear = min(1.0, max(0.0, (n + body * 0.6 - 0.38) / 0.35))
        rim = max(0.0, 1 - d) ** 0.6  # nothing past the edge, where the warp would leave stray bits
        return 1, 1, 1, min(1.0, body * tear * rim * 1.3)

    write_tga(path, size, size, radial(size, fn))


def make_ember(path, size=32):
    """Teardrop flame: wide and bright at the bottom, thin at the top."""

    def fn(dx, dy, d):
        width = 0.12 + 0.22 * (dy + 1) / 2
        a = math.exp(-(dx / width) ** 2 - ((dy - 0.15) / 0.6) ** 2)
        a += 0.6 * math.exp(-(math.hypot(dx, dy - 0.35) / 0.18) ** 2)
        return 1, 1, 1, min(1.0, a)

    write_tga(path, size, size, radial(size, fn))


def make_spark(path, size=32):
    """A spark in flight: a small white-hot head near the top and a thin tail fading below it. Kept inside the
    middle circle so it can turn any way (burst.orient) without its corners clipping."""
    head_y, tail = -0.4, 0.95  # head position, tail length (texture halves, y down)

    def fn(dx, dy, d):
        head = math.exp(-(math.hypot(dx, dy - head_y) / 0.12) ** 2)
        along = (dy - head_y) / tail
        streak = 0.0
        if 0 <= along <= 1:
            width = 0.075 * (1 - 0.7 * along)
            streak = 0.85 * math.exp(-(dx / width) ** 2) * (1 - along) ** 1.6
        halo = 0.22 * math.exp(-(math.hypot(dx, dy - head_y + 0.05) / 0.3) ** 2)
        return 1, 1, 1, min(1.0, head + streak + halo)

    write_tga(path, size, size, radial(size, fn))


def make_snow(path, size=32):
    """Six-armed snowflake with side branches."""

    def seg_dist(px, py, ax, ay, bx, by):
        vx, vy = bx - ax, by - ay
        t = max(0.0, min(1.0, ((px - ax) * vx + (py - ay) * vy) / (vx * vx + vy * vy)))
        return math.hypot(px - ax - vx * t, py - ay - vy * t)

    segs = []
    for k in range(6):
        a = k * math.pi / 3
        ex, ey = math.cos(a) * 0.85, math.sin(a) * 0.85
        segs.append((0, 0, ex, ey))
        for side in (-1, 1):
            mx, my = math.cos(a) * 0.5, math.sin(a) * 0.5
            b = a + side * math.pi / 4
            segs.append((mx, my, mx + math.cos(b) * 0.25, my + math.sin(b) * 0.25))

    def fn(dx, dy, d):
        dist = min(seg_dist(dx, dy, *s) for s in segs)
        return 1, 1, 1, min(1.0, math.exp(-(dist / 0.06) ** 2) + 0.5 * math.exp(-(d / 0.15) ** 2))

    write_tga(path, size, size, radial(size, fn))


def make_leaf(path, size=32):
    """Pointed leaf on the diagonal with a faint centre vein."""

    def fn(dx, dy, d):
        c, s = math.cos(math.pi / 4), math.sin(math.pi / 4)
        u, v = (dx * c + dy * s) / 0.9, (-dx * s + dy * c) / 0.9
        if abs(u) >= 1:
            return 1, 1, 1, 0
        half = 0.38 * (1 - u * u) ** 0.8
        edge = half - abs(v)
        if edge <= 0:
            return 1, 1, 1, 0
        a = min(1.0, edge / 0.06)
        vein = 1 - 0.45 * math.exp(-(v / 0.03) ** 2)
        return 1, 1, 1, a * vein

    write_tga(path, size, size, radial(size, fn))


def make_star(path, size=32):
    """Sharp four-point star with shorter diagonals."""

    def fn(dx, dy, d):
        core = math.exp(-(d / 0.1) ** 2)
        main = math.exp(-abs(dx) / 0.025) * math.exp(-abs(dy) / 0.45) + math.exp(-abs(dy) / 0.025) * math.exp(-abs(dx) / 0.45)
        rx, ry = (dx + dy) * 0.7071, (dx - dy) * 0.7071
        diag = 0.5 * (math.exp(-abs(rx) / 0.02) * math.exp(-abs(ry) / 0.2) + math.exp(-abs(ry) / 0.02) * math.exp(-abs(rx) / 0.2))
        return 1, 1, 1, min(1.0, core + main + diag)

    write_tga(path, size, size, radial(size, fn))


def make_crystal(path, size=32):
    """Elongated ice shard with bright edges and a centre facet."""

    def fn(dx, dy, d):
        k = abs(dx) / 0.42 + abs(dy) / 0.95
        if k >= 1:
            return 1, 1, 1, 0
        edge = math.exp(-((1 - k) / 0.12) ** 2)
        facet = 0.5 * math.exp(-(dx / 0.04) ** 2)
        coverage = min(1.0, (1 - k) / 0.08)  # soft outline instead of a hard cut
        return 1, 1, 1, min(1.0, 0.35 + edge * 0.65 + facet) * coverage

    write_tga(path, size, size, radial(size, fn))


def make_plus(path, size=32):
    """A healing plus, like the game's over a healed character: a solid cross, bright inside and darker at its
    rim so it reads once tinted, with a soft glow around it."""

    def fn(dx, dy, d):
        arm, length = 0.24, 0.82
        # Distance inside the cross (positive inside), from the nearer of its two bars.
        inside = max(min(arm - abs(dx), length - abs(dy)), min(arm - abs(dy), length - abs(dx)))
        glow = 0.35 * math.exp(-(max(0.0, -inside) / 0.08) ** 2)
        if inside <= 0:
            return 1, 1, 1, glow
        a = min(1.0, inside / 0.05)
        shade = 0.55 + 0.45 * min(1.0, inside / 0.14)
        return shade, shade, shade, max(a, glow)

    write_tga(path, size, size, radial(size, fn))


def make_strands(path, w=256, h=64):
    """Long curving filaments of light that come and go along their length, for the shield (Shield.lua): the
    strands of light in a priest's barrier. A bar is about 20 px high in game and the texture is drawn one bar high,
    so the strands are 1.5 to 2.5 texels across: thinner ones blurred into a haze at the game's size. Tiles both ways:
    every curve has a whole number of waves across."""
    rnd = random.Random(260)
    strands = []
    for _ in range(7):
        strands.append(dict(c=rnd.random(), a=0.10 + 0.22 * rnd.random(), n=rnd.choice((1, 1, 2)), p=rnd.random(),
                            n2=rnd.choice((3, 4, 5)), a2=0.03 * rnd.random(), p2=rnd.random(),
                            width=0.022 + 0.014 * rnd.random(), bright=0.55 + 0.45 * rnd.random()))
    along = [(TileNoise(6 * 2**i, 1, 300 + i), 0.5**i) for i in range(3)]

    def field(u, v):
        total = 0.0
        for k, s in enumerate(strands):
            y = s["c"] + s["a"] * math.sin(2 * math.pi * (s["n"] * u + s["p"])) \
                + s["a2"] * math.sin(2 * math.pi * (s["n2"] * u + s["p2"]))
            d = (v - y + 0.5) % 1.0 - 0.5  # wraps top to bottom
            core = math.exp(-(d / s["width"]) ** 2)
            halo = 0.25 * math.exp(-(d / (s["width"] * 3)) ** 2)
            fade = max(0.0, fbm(along, (u + k * 0.37) % 1.0, 0.0) - 0.35) * 2.2
            total += (core + halo) * s["bright"] * min(1.0, fade)
        return total

    write_field(path, w, h, field, 1.1)


# The shield's rim: a crescent of light bowed toward the texture's right, its line at RIM_LINE across the texture at
# the middle and RIM_BOW further left at the top and bottom. Shield.lua matches both.
RIM_LINE, RIM_BOW = 0.70, 0.30


def make_rim(path, w=32, h=64):
    """The shield's rim (Shield.lua): a white-hot crescent with a soft glow either side of it, its core about a unit
    across at the rim's width (thinner was lost at the game's size, about a pixel and a half to a unit)."""

    def pixel(x, y):
        u, v = (x + 0.5) / w, (y + 0.5) / h
        d = u - (RIM_LINE - RIM_BOW * (2 * v - 1) ** 2)
        a = math.exp(-(d / 0.07) ** 2) + 0.4 * math.exp(-(d / 0.2) ** 2)
        return 1, 1, 1, min(1.0, a)

    write_tga(path, w, h, pixel)


def make_rim_crackle(path, w=32, h=64, frames=4):
    """Jagged filaments of light along the rim's crescent, frames stacked top to bottom: the shield flicks between
    them so its edge crackles (Shield.lua)."""
    rnd = random.Random(410)
    paths = []
    for _ in range(frames):
        offsets, o = [], 0.0
        for _ in range(h):
            o = max(-0.09, min(0.09, o + rnd.uniform(-0.03, 0.03)))
            offsets.append(o)
        paths.append((offsets, rnd.uniform(-0.05, 0.02)))

    def pixel(x, y):
        f, row = divmod(y, h)
        offsets, shift = paths[f]
        u, v = (x + 0.5) / w, (row + 0.5) / h
        d = u - (RIM_LINE + shift + offsets[row] - RIM_BOW * (2 * v - 1) ** 2)
        a = math.exp(-(d / 0.028) ** 2) + 0.25 * math.exp(-(d / 0.08) ** 2)
        return 1, 1, 1, min(1.0, a)

    write_tga(path, w, h * frames, pixel)


# The shield's edge mask is this many rim widths across, its crescent in the last of them (Shield.lua, EDGE_SPAN).
EDGE_SPAN = 16


def make_shield_edge(path, w=512, h=64):
    """A mask that ends the shield's body on its rim's crescent (Shield.lua): opaque left of the rim's line, clear
    right of it, over about a unit. The crescent fills the last 1/EDGE_SPAN of the width, as the rim fills its texture,
    so it lines up with Rim.tga when the mask is EDGE_SPAN rim widths across. Its straight cut ended the body past the
    rim's bowed top and bottom (seen in game)."""

    def pixel(x, y):
        u, v = (x + 0.5) / w, (y + 0.5) / h
        rim_u = (u - (1 - 1 / EDGE_SPAN)) * EDGE_SPAN
        d = rim_u - (RIM_LINE - RIM_BOW * (2 * v - 1) ** 2)
        return 1, 1, 1, max(0.0, min(1.0, 0.5 - d / 0.07))

    write_tga(path, w, h, pixel)


def make_shard(path, size=32):
    """A fragment of the shield's glass as it shatters (Shield.lua): a solid angular sliver, brighter along its edges,
    with a soft glow round it. Crystal.tga, an ice shard clear in its middle, drew as a faint outline at the shield's
    size."""
    pts = [(-0.36, -0.44), (0.42, -0.08), (-0.08, 0.46)]

    def edge_d(px, py):
        best, inside = 9.0, True
        for i in range(3):
            (ax, ay), (bx, by) = pts[i], pts[(i + 1) % 3]
            ex, ey = bx - ax, by - ay
            ln = math.hypot(ex, ey)
            side = (ex * (py - ay) - ey * (px - ax)) / ln  # signed distance to the edge's line
            if side < 0:
                inside = False
            t = max(0.0, min(1.0, ((px - ax) * ex + (py - ay) * ey) / (ln * ln)))
            best = min(best, math.hypot(px - ax - t * ex, py - ay - t * ey))
        return best, inside

    def pixel(x, y):
        px, py = (x + 0.5) / size - 0.5, (y + 0.5) / size - 0.5
        d, inside = edge_d(px, py)
        if inside:
            a = 0.8 + 0.2 * math.exp(-(d / 0.05) ** 2)
        else:
            a = 0.45 * math.exp(-(d / 0.07) ** 2)
        return 1, 1, 1, a

    write_tga(path, size, size, pixel)


# The shield's fade-in mask is this many fade widths across, its ramp in the first of them (Shield.lua, FADE_SPAN).
FADE_SPAN = 32


def make_shield_fade(path, w=512, h=4):
    """A mask that fades the shield's body in from its back (Shield.lua): clear at its left edge, opaque from the end
    of its first 1/FADE_SPAN on, smoothly between, so the body (glass, strands and all) comes in over the health's end
    with no colour of its own to match. A band of a set colour before the body showed as a lighter strip with a step
    where the body began, in game."""

    def pixel(x, y):
        k = min(1.0, (x + 0.5) / w * FADE_SPAN)
        return 1, 1, 1, k * k * (3 - 2 * k)

    write_tga(path, w, h, pixel)


def make_beam(path, size=64):
    """A shaft of light from the texture's middle out to its top edge, narrow at its root and fading as it spreads:
    the god rays the shield sheds past the bar (Shield.lua). Square and clear at its borders, so SetRotation (which
    turns the texture inside its square) can point it anywhere from the rim."""

    def pixel(x, y):
        dx, up = (x + 0.5) / size - 0.5, 0.5 - (y + 0.5) / size
        along = up / 0.5
        if along <= 0 or along >= 1:
            return 1, 1, 1, 0
        width = 0.022 + 0.06 * along
        a = math.exp(-(dx / width) ** 2) * (1 - along) ** 0.9 * min(1.0, along / 0.06)
        return 1, 1, 1, a

    write_tga(path, size, size, pixel)


def make_ray(path, w=32, h=64):
    """A soft shaft of light leaning a little to the right as it goes up, like light through a cathedral window: the
    god rays drifting through the shield (Shield.lua)."""

    def pixel(x, y):
        u, v = (x + 0.5) / w, (y + 0.5) / h
        d = u - 0.5 + 0.22 * (v - 0.5)
        return 1, 1, 1, math.exp(-(d / 0.16) ** 2) * (0.75 + 0.25 * math.sin(math.pi * v))

    write_tga(path, w, h, pixel)


# How bright the captured plate fill is down from its top edge, as a share of its middle, against the distance from
# the edge as a share of its height: it fades over its top and bottom quarter, so the game's red sits inside the rim.
PLATE_FADE = [(0.0, 0.0), (0.041, 0.13), (0.082, 0.37), (0.123, 0.59), (0.164, 0.75), (0.206, 0.87), (0.247, 0.94),
              (0.288, 1.0)]


def plate_shape(w, h, samples=4):
    """How much of each pixel of a w x h nameplate bar lies inside the game's fill (UI-HUD-CoolDownManager-Bar,
    captured with /sab capture plates): the bar with its four corners cut at 45 degrees, 1.5% of the width across and
    a quarter of the height down, as the captured fill is at 128 x 10."""
    cx, cy = 0.015 * w, 0.25 * h

    def inside(x, y):
        dx = min(x, w - x)
        dy = min(y, h - y)
        return dx / cx + dy / cy >= 1 if dx < cx and dy < cy else True

    def coverage(x, y):
        return sum(inside(x + (i + 0.5) / samples, y + (j + 0.5) / samples)
                   for i in range(samples) for j in range(samples)) / samples ** 2
    return coverage


def plate_fade(y, h):
    """The captured fill's brightness at row y of h, as a share of its middle (PLATE_FADE)."""
    d = min(y, h - y) / h
    for (d0, v0), (d1, v1) in zip(PLATE_FADE, PLATE_FADE[1:]):
        if d <= d1:
            return v0 + (v1 - v0) * (d - d0) / (d1 - d0)
    return 1.0


def make_plate_mask(path, w=256, h=32):
    """The shape of a nameplate's health bar (plate_shape), for the liquids there (the game's plate bar has no mask of
    its own). Opaque inside: the fill's fade toward its top and bottom is PlateShade's, drawn over all the plate's
    liquids. Fading the liquids themselves let a DoT liquid under the health show through the health's faded edges, a
    brighter block behind its front. It is stretched over the bar as the game stretches the fill, so it matches at
    any plate size."""
    coverage = plate_shape(w, h)
    write_tga(path, w, h, lambda x, y: (1, 1, 1, coverage(x, y)))


def make_square(path, size=8):
    """Opaque white, for a mask that cuts a liquid to a plain rectangle: a raid frame's bar, where a clip frame would
    leave the liquid under the frame's own background (Bars.lua, Bars.raid)."""
    write_tga(path, size, size, lambda x, y: (1, 1, 1, 1))


def make_plate_shade(path, w=256, h=32):
    """Black over a nameplate's bar, as opaque as the game's fill is dark there: nothing in the middle, darkening
    toward the top and bottom edges as the fill fades (PLATE_FADE), so the liquids under it take the game's shading
    and stay off the rim as the game's red does. In the bar's shape, as PlateMask."""
    coverage = plate_shape(w, h)
    write_tga(path, w, h, lambda x, y: (0, 0, 0, coverage(x, y) * (1 - plate_fade(y + 0.5, h))))


def make_skull(path, size=64):
    """A poison's skull, like the ones the game shows over a poisoned character: a rounded cranium over cheekbones
    and a narrower jaw, shaded as if lit from the upper left (gold where the light falls, sickly green in shadow),
    with deep eye sockets, a nose hole and a row of teeth, inside a soft green glow. Its colours are its own, so it
    is drawn with a near-white tint."""
    pix = 2 / (size - 1)

    def smin(a, b, k):
        h = max(0.0, min(1.0, 0.5 + 0.5 * (b - a) / k))
        return b + (a - b) * h - k * h * (1 - h)

    def ellipse(x, y, cx, cy, rx, ry):
        return (math.hypot((x - cx) / rx, (y - cy) / ry) - 1) * min(rx, ry)

    def box(x, y, cx, cy, bx, by, r):
        qx, qy = abs(x - cx) - bx + r, abs(y - cy) - by + r
        return math.hypot(max(qx, 0.0), max(qy, 0.0)) + min(max(qx, qy), 0.0) - r

    def outline(x, y):
        """Signed distance to the skull's outline (negative inside); y grows downwards."""
        cranium = ellipse(x, y, 0, -0.2, 0.64, 0.58)
        face = box(x, y, 0, 0.12, 0.47, 0.2, 0.14)
        jaw = box(x, y, 0, 0.47, 0.3, 0.19, 0.12)
        return smin(smin(cranium, face, 0.1), jaw, 0.08)

    def height(x, y):
        return math.sqrt(max(0.0, min(1.0, -outline(x, y) / 0.32)))

    def smooth(edge0, edge1, v):
        t = max(0.0, min(1.0, (v - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)

    light = (-0.45, -0.6, 0.66)
    norm = math.sqrt(sum(c * c for c in light))
    light = tuple(c / norm for c in light)
    lit, shadow, dark, halo = (1.0, 0.9, 0.34), (0.36, 0.54, 0.06), (0.07, 0.09, 0.01), (0.55, 0.95, 0.2)

    def fn(x, y, d):
        sd = outline(x, y)
        cover = max(0.0, min(1.0, 0.5 - sd / pix))
        glow = 0.45 * math.exp(-(max(sd, 0.0) / 0.14) ** 2)
        if cover <= 0:
            return halo[0], halo[1], halo[2], glow
        e = pix
        nx = -(height(x + e, y) - height(x - e, y)) / (2 * e) * 0.35
        ny = -(height(x, y + e) - height(x, y - e)) / (2 * e) * 0.35
        n = math.sqrt(nx * nx + ny * ny + 1)
        lambert = max(0.0, (nx * light[0] + ny * light[1] + light[2]) / n)
        bright = min(1.0, 0.25 + 0.85 * lambert - 0.25 * max(0.0, y - 0.1))
        # Hollows under the cheekbones.
        cheek = min(ellipse(x, y, -0.37, 0.24, 0.12, 0.1), ellipse(x, y, 0.37, 0.24, 0.12, 0.1))
        bright *= 1 - 0.45 * (1 - smooth(-0.06, 0.04, cheek))
        col = [shadow[i] + (lit[i] - shadow[i]) * bright for i in range(3)]
        # Deep sockets, dark at the middle and shading in at the rim; a nose hole; teeth under a dark mouth line.
        socket = min(ellipse(x, y, -0.25, -0.07, 0.18, 0.16), ellipse(x, y, 0.25, -0.07, 0.18, 0.16))
        nose = max(abs(x) * 1.6 + (y - 0.12) * 0.7 - 0.13, 0.04 - (y - 0.12), (y - 0.12) - 0.2)
        mouth = abs(y - 0.45) - 0.025
        gaps = 1.0
        if 0.33 < y < 0.6 and abs(x) < 0.27:
            k = (x + 0.27) / 0.108
            gaps = (abs(k - round(k)) * 0.108) - 0.014
        mouth = max(mouth, abs(x) - 0.27)
        hole = min(socket, nose, mouth, gaps if 0.33 < y < 0.6 and abs(x) < 0.27 else 1.0)
        inside = 1 - smooth(-pix, pix, hole)
        depth = 0.15 * smooth(-0.1, 0.0, socket)  # the sockets' rims catch a little light
        for i in range(3):
            col[i] = col[i] * (1 - inside) + (dark[i] + depth * shadow[i]) * inside
        a = cover + glow * (1 - cover)
        rgb = [(col[i] * cover + halo[i] * glow * (1 - cover)) / a for i in range(3)]
        return rgb[0], rgb[1], rgb[2], a

    write_tga(path, size, size, radial(size, fn))


def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    make_swirl(os.path.join(out, "Swirl.tga"))
    make_heat(os.path.join(out, "Heat.tga"))
    make_flames(os.path.join(out, "Flames.tga"))
    make_ramp(os.path.join(out, "Ramp.tga"))
    make_cracks(os.path.join(out, "Cracks.tga"))
    make_caustics(os.path.join(out, "Caustics.tga"))
    make_nebula(os.path.join(out, "Nebula.tga"))
    make_tendrils(os.path.join(out, "Tendrils.tga"))
    make_frost(os.path.join(out, "Frost.tga"))
    make_bubble(os.path.join(out, "Bubble.tga"))
    make_mote(os.path.join(out, "Mote.tga"))
    make_glow(os.path.join(out, "Glow.tga"))
    make_edge(os.path.join(out, "Edge.tga"))
    make_core(os.path.join(out, "Core.tga"))
    make_bolt(os.path.join(out, "Bolt.tga"))
    make_wisp(os.path.join(out, "Wisp.tga"))
    make_smoke(os.path.join(out, "Smoke.tga"))
    make_ember(os.path.join(out, "Ember.tga"))
    make_spark(os.path.join(out, "Spark.tga"))
    make_snow(os.path.join(out, "Snow.tga"))
    make_leaf(os.path.join(out, "Leaf.tga"))
    make_star(os.path.join(out, "Star.tga"))
    make_crystal(os.path.join(out, "Crystal.tga"))
    make_plus(os.path.join(out, "Plus.tga"))
    make_strands(os.path.join(out, "Strands.tga"))
    make_rim(os.path.join(out, "Rim.tga"))
    make_rim_crackle(os.path.join(out, "RimCrackle.tga"))
    make_ray(os.path.join(out, "Ray.tga"))
    make_shield_edge(os.path.join(out, "ShieldEdge.tga"))
    make_beam(os.path.join(out, "Beam.tga"))
    make_shield_fade(os.path.join(out, "ShieldFade.tga"))
    make_shard(os.path.join(out, "Shard.tga"))
    make_skull(os.path.join(out, "Skull.tga"))
    make_plate_mask(os.path.join(out, "PlateMask.tga"))
    make_plate_shade(os.path.join(out, "PlateShade.tga"))
    make_square(os.path.join(out, "Square.tga"))
    print("wrote", sorted(os.listdir(out)))


if __name__ == "__main__":
    main()
