"""A rough picture of the editor window (Editor.lua) at each section, to check its layout.

Usage: python editor_shot.py <addon dir> <out dir> [section ...] [setting=value ...] [closed]
e.g.   python editor_shot.py SmoothAnimatedBars shots player plates effects
Writes <section>.png for each section (all of them if none are named).

The mock has no art for the game's templates or atlases, so they are stood in for: the window and buttons as plain
panels, check buttons as boxes, atlas textures (the preview frames' art) as faint outlines. Solid colours, gradients,
the addon's own media and text are drawn as the client would place them. It shows where things are, not how the game's
art looks; that is for the game itself.
"""
import os
import sys
import textwrap

import numpy as np
from PIL import Image, ImageDraw

import render

try:
    from lupa.luajit21 import LuaRuntime
except ImportError:
    from lupa.lua51 import LuaRuntime

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON, OUT = sys.argv[1].replace("\\", "/"), sys.argv[2]
ARGS = sys.argv[3:]
# closed: each section's colour choices closed, to see what lies under them.
CLOSED = "closed" in ARGS
ARGS = [a for a in ARGS if a != "closed"]
SETTINGS = dict(a.split("=", 1) for a in ARGS if "=" in a)
SECTIONS = [a for a in ARGS if "=" not in a]
K = 2
LAYERS = {"BACKGROUND": 0, "BORDER": 1, "ARTWORK": 2, "OVERLAY": 3}
# The game's font objects: size and colour.
FONTS = {
    "GameFontNormal": (12, (255, 209, 0)), "GameFontNormalSmall": (10, (255, 209, 0)),
    "GameFontNormalLarge": (16, (255, 209, 0)), "GameFontNormalHuge": (20, (255, 209, 0)),
    "GameFontHighlight": (12, (255, 255, 255)), "GameFontHighlightSmall": (10, (255, 255, 255)),
    "GameFontHighlightLarge": (16, (255, 255, 255)), "GameFontHighlightHuge": (20, (255, 255, 255)),
    "GameFontDisableSmall": (10, (128, 128, 128)), "TextStatusBarText": (10, (255, 255, 255)),
    "WhiteLargeNumberFont": (14, (255, 255, 255)),
}

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(open(os.path.join(HERE, "wowmock.lua"), encoding="utf-8").read())
lua.execute("SmoothAnimatedBarsDB = { setupDone = true }")
G = lua.globals()
G["__ns"] = G["__loadAddon"](ADDON, "SmoothAnimatedBars")
lua.execute("__fire('ADDON_LOADED', 'SmoothAnimatedBars'); __fire('PLAYER_ENTERING_WORLD', true, false)")
for k, v in SETTINGS.items():
    lua.execute(f"__settings[{k!r}]:SetValue({render.lua_value(v)})")

# Every region's place on the screen, its anchors followed through to other regions, and what draws it.
lua.execute("""
    -- A region's scale on the screen: its own (SetScale, frames only) times its parents'.
    function __scaleOf(r)
        local own = (r.kind == "Frame" and r.scale) or 1
        return own * (r.parent and __scaleOf(r.parent) or 1)
    end
    function __absRect(r, memo)
        memo = memo or {}
        if memo[r] then return unpack(memo[r]) end
        memo[r] = { 0, 0, 0, 0 } -- an anchor loop stays at the origin
        local pl, pt, pw, ph = 0, 0, 1920, 1080
        if r.parent then pl, pt, pw, ph = __absRect(r.parent, memo) end
        local k = __scaleOf(r)
        local w, h = r.w or 0, r.h or 0
        if r.kind == "FontString" then
            local size = r.fontSize or (__fontSizes[r.template or ""] or 12)
            local plain = tostring(r.text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            w, h = #plain * size * 0.55, size
            -- With a width it wraps (the client's default), and its height is its lines'.
            if r.w and r.w > 0 then
                if r.wordWrap ~= false then h = math.ceil(#plain * size * 0.5 / r.w) * size * 1.2 end
                w = r.w
            end
        end
        w, h = w * k, h * k
        local left, right, cx, top, bottom, cy
        local any = false
        for p, a in pairs(r.points) do
            any = true
            local rl, rt, rw, rh = pl, pt, pw, ph
            if a.rel and a.rel ~= r.parent then rl, rt, rw, rh = __absRect(a.rel, memo)
            elseif a.rel == nil and r.parent == nil then rl, rt, rw, rh = 0, 0, 1920, 1080 end
            local ax = a.relPoint:find("LEFT") and 0 or (a.relPoint:find("RIGHT") and rw or rw / 2)
            local ay = a.relPoint:find("TOP") and 0 or (a.relPoint:find("BOTTOM") and rh or rh / 2)
            local x, y = rl + ax + a.x * k, rt + ay - a.y * k
            if p:find("LEFT") then left = x elseif p:find("RIGHT") then right = x else cx = x end
            if p:find("TOP") then top = y elseif p:find("BOTTOM") then bottom = y else cy = y end
        end
        if not any then left, top = pl, pt end
        if left and right then w = right - left elseif right then left = right - w elseif not left then left = (cx or 0) - w / 2 end
        if top and bottom then h = bottom - top elseif bottom then top = bottom - h elseif not top then top = (cy or 0) - h / 2 end
        memo[r] = { left, top, w, h }
        return left, top, w, h
    end
    __fontSizes = { GameFontNormalSmall = 10, GameFontHighlightSmall = 10, GameFontDisableSmall = 10,
                    GameFontNormalLarge = 16, GameFontHighlightLarge = 16, GameFontNormalHuge = 20,
                    GameFontHighlightHuge = 20, TextStatusBarText = 10 }
    -- The window's regions and frames that show, each with its rect, its depth order and its clip.
    function __shot(root)
        local memo, out = {}, {}
        local children = {}
        for _, r in ipairs(__regions) do
            if r.parent then
                children[r.parent] = children[r.parent] or {}
                table.insert(children[r.parent], r)
            end
        end
        local n = 0
        local function walk(f, alpha, clip)
            if not f.shown then return end
            alpha = alpha * (__reveal(f.alpha) or 1)
            local l, t, w, h = __absRect(f, memo)
            if f.kind == "Frame" and (f.clipsChildren or f.scrollChild ~= nil) then
                local cl, ct, cr, cb = l, t, l + w, t + h
                if clip then cl, ct, cr, cb = math.max(cl, clip[1]), math.max(ct, clip[2]), math.min(cr, clip[3]), math.min(cb, clip[4]) end
                clip = { cl, ct, cr, cb }
            end
            n = n + 1
            out[#out + 1] = { r = f, l = l, t = t, w = w, h = h, alpha = alpha, clip = clip, order = n }
            local list = children[f] or {}
            -- Its own textures and text first, by layer, then the frames in it, as children draw over their parent.
            local regs, frames = {}, {}
            for _, c in ipairs(list) do
                if c.kind == "Frame" then frames[#frames + 1] = c elseif c.shown then regs[#regs + 1] = c end
            end
            local rank = { BACKGROUND = 0, BORDER = 1, ARTWORK = 2, OVERLAY = 3, HIGHLIGHT = 9 }
            table.sort(regs, function(a, b)
                local ra, rb = rank[a.layer] or 2, rank[b.layer] or 2
                if ra ~= rb then return ra < rb end
                if (a.sub or 0) ~= (b.sub or 0) then return (a.sub or 0) < (b.sub or 0) end
                return a.order < b.order
            end)
            for _, c in ipairs(regs) do
                if c.layer ~= "HIGHLIGHT" and c.kind ~= "MaskTexture" then
                    local cl, ct, cw, ch = __absRect(c, memo)
                    n = n + 1
                    out[#out + 1] = { r = c, l = cl, t = ct, w = cw, h = ch, alpha = alpha * (__reveal(c.alpha) or 1),
                                      scale = __scaleOf(c),
                                      clip = clip, order = n }
                end
            end
            table.sort(frames, function(a, b) return (a.level or 0) < (b.level or 0) or ((a.level or 0) == (b.level or 0) and a.order < b.order) end)
            for _, c in ipairs(frames) do walk(c, alpha, clip) end
        end
        walk(root, 1, nil)
        return out
    end
""")


def run(seconds):
    for _ in range(int(seconds * 60)):
        G.__step(1 / 60)


def media(cache, path):
    name = path.split("\\")[-1]
    if name not in cache:
        file = os.path.join(ADDON, "Media", name + ".tga")
        cache[name] = Image.open(file).convert("RGBA") if os.path.exists(file) else None
    return cache[name]


def shot(section, path):
    lua.execute(f"__ns.Editor.Open('{section}')")
    if CLOSED:
        lua.execute("local p = __ns.Editor.State().ui.pages[__ns.Editor.State().section]; "
                    "p.open = nil; __ns.Editor.Refresh()")
    run(1.5)
    items = lua.eval("__shot(SmoothAnimatedBarsEditor)")
    root = lua.eval("SmoothAnimatedBarsEditor")
    x0, y0 = lua.eval("__absRect(SmoothAnimatedBarsEditor)")[:2]
    W, H = int(root.w * K), int(root.h * K)
    img = Image.new("RGBA", (W, H), (22, 20, 18, 255))
    cache = {}
    for i in range(1, len(items) + 1):
        it = items[i]
        r = it.r
        box = [(it.l - x0) * K, (it.t - y0) * K, (it.l - x0 + it.w) * K, (it.t - y0 + it.h) * K]
        clip = it.clip
        cbox = None
        if clip:
            cbox = [(clip[1] - x0) * K, (clip[2] - y0) * K, (clip[3] - x0) * K, (clip[4] - y0) * K]
            if cbox[2] < cbox[0] or cbox[3] < cbox[1]:
                continue  # clipped away entirely
        layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        a = max(0.0, min(1.0, float(it.alpha)))
        if (box[2] - box[0] < 1 or box[3] < box[1]) and r.kind != "FontString":
            continue
        if r.kind == "Frame":
            tmpl = None
            if isinstance(r.text, str) and not r.SetValue:  # a UIPanelButtonTemplate button
                d.rectangle(box, fill=(110, 18, 10, int(230 * a)), outline=(176, 138, 69, int(255 * a)))
                f = render.font(10 * K)
                d.text(((box[0] + box[2]) / 2, (box[1] + box[3]) / 2), str(r.text), font=f, anchor="mm",
                       fill=(255, 209, 0, int(255 * a)))
            if r.checked is not None:  # a check button
                d.rectangle(box, fill=(20, 16, 10, int(255 * a)), outline=(199, 154, 74, int(255 * a)))
                if r.checked:
                    m = (box[2] - box[0]) * 0.25
                    d.line([(box[0] + m, (box[1] + box[3]) / 2), ((box[0] + box[2]) / 2, box[3] - m),
                            (box[2] - m, box[1] + m)], fill=(255, 209, 0, int(255 * a)), width=3)
        elif r.kind == "Texture":
            if r.file == "SOLID":
                c = [r.color[j] for j in range(1, 5)]
                if r.grad:
                    c1 = np.array([r.grad[1][j] for j in range(1, 5)])
                    c2 = np.array([r.grad[2][j] for j in range(1, 5)])
                    w = max(1, int(box[2] - box[0]))
                    for x in range(w):
                        cc = c1 + (c2 - c1) * (x + 0.5) / w
                        d.line([(box[0] + x, box[1]), (box[0] + x, box[3])],
                               fill=tuple(int(255 * v) for v in cc[:3]) + (int(255 * cc[3] * c[3] * a),))
                else:
                    vc = [r.vc[j] for j in range(1, 5)]
                    d.rectangle(box, fill=tuple(int(255 * c[j] * vc[j]) for j in range(3)) + (int(255 * c[3] * vc[3] * a),))
            elif isinstance(r.file, str):
                im = media(cache, r.file)
                if im and box[2] - box[0] >= 1 and box[3] - box[1] >= 1:
                    im = im.resize((int(box[2] - box[0]), int(box[3] - box[1])))
                    vc = [r.vc[j] for j in range(1, 5)]
                    arr = np.asarray(im).astype(np.float32)
                    arr[..., :3] *= np.array(vc[:3])
                    arr[..., 3] *= vc[3] * a * (0.6 if r.blend == "ADD" else 1)
                    layer.alpha_composite(Image.fromarray(arr.clip(0, 255).astype(np.uint8)), (int(box[0]), int(box[1])))
            elif r.atlas:
                d.rectangle(box, outline=(150, 120, 70, int(140 * a)))
        elif r.kind == "FontString" and r.text:
            size, color = FONTS.get(r.template or "", (12, (255, 255, 255)))
            size = size * float(it.scale or 1)
            if r.textColor:
                color = tuple(int(255 * r.textColor[j]) for j in range(1, 4))
            f = render.font(size * K)
            width = box[2] - box[0]
            text = str(r.text)
            lines = [text]
            if r.wordWrap is not False and r.w and r.w > 0:
                per = max(4, int(width / (size * K * 0.5)))
                lines = textwrap.wrap(text, per) or [text]
            justify = r.justifyH or "CENTER"
            y = (box[1] + box[3]) / 2 - (len(lines) - 1) * size * K * 0.6
            if len(lines) > 1:
                y = box[1] + size * K * 0.6
            for line in lines:
                if justify == "LEFT":
                    d.text((box[0], y), line, font=f, anchor="lm", fill=color + (int(255 * a),))
                elif justify == "RIGHT":
                    d.text((box[2], y), line, font=f, anchor="rm", fill=color + (int(255 * a),))
                else:
                    d.text(((box[0] + box[2]) / 2, y), line, font=f, anchor="mm", fill=color + (int(255 * a),))
                y += size * K * 1.2
        if cbox:
            m = Image.new("L", (W, H), 0)
            ImageDraw.Draw(m).rectangle(cbox, fill=255)
            layer.putalpha(Image.fromarray(np.minimum(np.asarray(layer)[..., 3], np.asarray(m))))
        img.alpha_composite(layer)
    img.convert("RGB").save(path)


os.makedirs(OUT, exist_ok=True)
ids = SECTIONS or list(lua.eval("__ns.Editor.Sections()").values())
for sid in ids:
    shot(sid, os.path.join(OUT, f"{sid}.png"))
    print("wrote", os.path.join(OUT, f"{sid}.png"))
