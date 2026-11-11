#!/usr/bin/env python3
"""Spatial / net-class breakdown of a TritonRoute DRC report (drt.drc.rpt).
drc_map.py <drt.drc.rpt> [tile um=100] [tilemap gr_diag out]"""
import sys, re, collections
f = sys.argv[1]; t = float(sys.argv[2]) if len(sys.argv) > 2 else 100.0
tiles = collections.Counter(); cls = collections.Counter(); typ = collections.Counter(); n = 0
ys = collections.Counter(); xs = collections.Counter()
src = ""; vt = ""
def nc(s):
    m = re.match(r"net:(u_array/g_col_\d+__g_row_\d+__u_pe)/", s)
    if m: return "PE"
    if s.startswith("net:u_array"): return "u_array"
    m = re.match(r"net:([^/ ]+)/", s)
    if m: return re.sub(r"\d+", "N", m[1])
    if s.startswith("net:"): return "top-level net"
    return s.split(":")[0]
for line in open(f):
    if "violation type" in line: vt = line.split(":", 1)[1].strip(); continue
    if "srcs:" in line: src = line.split("srcs:", 1)[1].split(); continue
    m = re.search(r"bbox = \( ([\d.]+), ([\d.]+) \) - \( ([\d.]+), ([\d.]+) \) on Layer (\S+)", line)
    if not m: continue
    x, y = float(m[1]), float(m[2]); n += 1
    tiles[int(x // t), int(y // t)] += 1; ys[int(y // t)] += 1; xs[int(x // t)] += 1
    typ[vt, m[5]] += 1
    for s in set(nc(s) for s in src): cls[s] += 1
print("markers", n)
print("types:", ", ".join(f"{k[0]}/{k[1]} {v}" for k, v in typ.most_common(8)))
print("net classes (marker count naming a net of):", ", ".join(f"{k} {v}" for k, v in cls.most_common(12)))
v = sorted(tiles.values(), reverse=True)
print(f"tiles {t:.0f} um with markers: {len(v)}; top 10 tiles hold {sum(v[:10])} ({100*sum(v[:10])/n:.1f} %), top 50 {sum(v[:50])} ({100*sum(v[:50])/n:.1f} %)")
print("by y band (um): " + " ".join(f"{k*t:.0f}:{ys[k]}" for k in sorted(ys)))
print("by x band (um): " + " ".join(f"{k*t:.0f}:{xs[k]}" for k in sorted(xs)))
print("top tiles:", " ".join(f"({x*t:.0f},{y*t:.0f}) {c}" for (x, y), c in tiles.most_common(12)))
