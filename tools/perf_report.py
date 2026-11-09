"""Turn the timings /sab perf saved in game into a text file.

The client writes the saved variables to disk on /reload or logout, so: /sab perf in game (as often as you like,
with a note: /sab perf 12 mobs pulled), /reload, then

    tools/venv/Scripts/python tools/perf_report.py [--file SmoothAnimatedBars.lua] [--out perf/perf_report.txt]

Without --file it takes the newest SmoothAnimatedBars.lua under Forever's WTF folder. The report is written to
perf/perf_report.txt (ignored by git) and printed.
"""
import argparse
import glob
import os
import sys

try:
    from lupa.luajit21 import LuaRuntime
except ImportError:
    from lupa.lua51 import LuaRuntime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WTF = r"C:\Program Files (x86)\World of Warcraft\_forever_\WTF\Account\*\SavedVariables\SmoothAnimatedBars.lua"


def find_saved():
    found = glob.glob(WTF)
    if not found:
        sys.exit(f"No saved variables found at {WTF}; pass --file.")
    return max(found, key=os.path.getmtime)


def to_py(v):
    """A Lua value as Python: tables with keys 1..n become lists, others dicts."""
    if hasattr(v, "items"):
        d = {k: to_py(x) for k, x in v.items()}
        if d and all(isinstance(k, int) for k in d) and sorted(d) == list(range(1, len(d) + 1)):
            return [d[i] for i in range(1, len(d) + 1)]
        return d
    return v


def load_log(path):
    lua = LuaRuntime(unpack_returned_tuples=True)
    with open(path, encoding="utf-8") as f:
        lua.execute(f.read())  # plain assignments written by the client
    db = lua.globals().SmoothAnimatedBarsDB
    return to_py(db["perfLog"]) if db is not None and db["perfLog"] is not None else []


def ms(x):
    return f"{x:7.3f}"


def report(log, source):
    out = [f"Smooth Animated Bars timings, {len(log)} saved from {source}", ""]
    if not log:
        out.append("Nothing saved yet: /sab perf in game, then /reload.")
        return out
    # One line per report, for comparing them at a glance.
    out.append("When                 Zone                       Plates  Unit ms  Plate ms  Per plate  Peak ms  "
               "fps  Frame %  Note")
    rows = []
    for snap in log:
        secs = snap.get("seconds") or []
        frames = sum(s["frames"] for s in secs) or 1
        unit = sum(s["unitMs"] for s in secs) / frames
        plate = sum(s["plateMs"] for s in secs) / frames
        plates = max((s["plates"] for s in secs), default=0)
        peak = max((s["peak"] for s in secs), default=0)
        fps = snap.get("fps") or 0
        share = (unit + plate) / (1000 / fps) * 100 if fps else 0
        per = f"{plate / plates:9.3f}" if plates else "        -"
        zone = (snap.get("zone") or "?") + (f" ({snap['instance']})" if snap.get("instance") not in (None, "none") else "")
        if snap.get("combat"):
            zone += " *"
        rows.append((snap, secs))
        out.append(f"{snap.get('when', '?'):<20} {zone[:26]:<26} {plates:6d} {ms(unit)}  {ms(plate)}  {per}  "
                   f"{peak:7.2f}  {fps:3.0f}  {share:6.1f}%  {snap.get('note') or ''}")
    out.append("")
    out.append("ms are the liquid's own updates per frame, averaged over the 10 seconds before each /sab perf.")
    out.append("Frame % is that share of the frame time at the fps then. * = in combat.")
    out.append("The client drawing the textures is not in these numbers: compare fps with plates on and off.")
    # Then each report second by second.
    for i, (snap, secs) in enumerate(rows, 1):
        out += ["", f"--- {i}. {snap.get('when', '?')}  {snap.get('note') or ''}".rstrip()]
        out.append(f"plates {'on' if snap.get('platesOn') else 'off'} (at most {snap.get('maxPlates', '?')}, idle "
                   f"{snap.get('plateIdleFps', '?')} fps), textures in live liquids {snap.get('textures', '?')}, "
                   f"addon memory {snap.get('memoryKB', 0):.0f} KB, version {snap.get('version') or '?'}")
        out.append("  s ago  frames  units  plates  unit ms/frame  plate ms/frame  peak ms")
        for ago, s in enumerate(secs, 1):
            f = s["frames"] or 1
            out.append(f"  {ago:5d}  {s['frames']:6d}  {s['units']:5d}  {s['plates']:6d}  {s['unitMs'] / f:13.3f}  "
                       f"{s['plateMs'] / f:14.3f}  {s['peak']:7.2f}")
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--file", help="the saved variables file (default: the newest under Forever's WTF folder)")
    ap.add_argument("--out", default=os.path.join(ROOT, "perf", "perf_report.txt"))
    args = ap.parse_args()
    path = args.file or find_saved()
    text = "\n".join(report(load_log(path), path)) + "\n"
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as f:
        f.write(text)
    print(text)
    print("wrote", args.out)


if __name__ == "__main__":
    main()
