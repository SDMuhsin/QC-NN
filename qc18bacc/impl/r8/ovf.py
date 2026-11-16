#!/usr/bin/env python3
"""impl/r8 (results/r8.md): GRT overflow per floorplan region as a fraction of the region's gcells, from a
global_route -congestion_report_file (one record per overflowed gcell and direction; bbox in um).
    python3 -I ovf.py <gr_congestion.rpt> <label> [gcell_um 3.0] [die_w 3990] [die_h 5825.4]
Regions (um, R6c / R8 floorplan, array x 860-3980, y 1700.6-4810.6) as impl/r7b/ovf.py: SWc, Sband, Wstrip, array,
north.  Per region: overflowed gcells (H or V, unique) and % of the region's gcells, entries H / V, sum overflow
(tracks) H / V, and the share of entries whose source nets include each unit (net-name prefix)."""
import os
import re
import sys
from collections import defaultdict

# array west edge / bottom / top (um); env QB8_XA / QB8_YA / QB8_YT for other floorplans (e.g. QB_WEST variants)
XA, YA, YT = (float(os.environ.get(k, d)) for k, d in (("QB8_XA", 860.0), ("QB8_YA", 1700.6), ("QB8_YT", 4810.6)))
UNITS = [("u_top/u_act/", "act"), ("g_rt_u_seq/", "seq"), ("u_prm/", "prm"), ("g_pcol_", "pcol"), ("u_head/", "head"),
         ("u_top/g_dist_", "dist"), ("clknet", "clock")]


def part(x, y):
    if y >= YT:
        return "north"
    if y < YA:
        return "SWc" if x < XA else "Sband"
    return "Wstrip" if x < XA else "array"


def main():
    rpt, lab = sys.argv[1], sys.argv[2]
    g = float(sys.argv[3]) if len(sys.argv) > 3 else 3.0
    W = float(sys.argv[4]) if len(sys.argv) > 4 else 3990.0
    H = float(sys.argv[5]) if len(sys.argv) > 5 else 5825.4
    area = {"SWc": XA * YA, "Sband": (W - XA) * YA, "Wstrip": XA * (YT - YA), "array": (W - XA) * (YT - YA),
            "north": W * (H - YT)}
    area["total"] = W * H
    cells = defaultdict(set)
    E = defaultdict(lambda: [0, 0])
    U = defaultdict(int)
    d, srcs, cu = None, [], (0, 0, 0)
    for ln in open(rpt):
        s = ln.strip()
        if s.startswith("violation type"):
            d = "H" if "Horizontal" in s else "V"
        elif s.startswith("srcs:"):
            srcs = s[5:].split()
        elif s.startswith("congestion information"):
            cu = tuple(int(v) for v in re.search(r"capacity:(\d+) usage:(\d+) overflow:(\d+)", s).groups())
        elif s.startswith("bbox"):
            m = re.search(r"\(\s*([\d.]+),\s*([\d.]+)\s*\)\s*-\s*\(\s*([\d.]+),\s*([\d.]+)\)", s)
            x, y = (float(m.group(1)) + float(m.group(3))) / 2, (float(m.group(2)) + float(m.group(4))) / 2
            us = {u for p, u in UNITS for n in srcs if p in n}
            for r in (part(x, y), "total"):
                cells[r].add((int(x // g), int(y // g)))
                E[(r, d)][0] += 1
                E[(r, d)][1] += cu[2]
                for u in us:
                    U[(r, u)] += 1
    print(f"# GRT overflow [S] {lab}: gcells {g:g} um; ovf gcells = unique overflowed gcells (H or V) and % of the region;"
          f" entries / tracks per direction; unit = % of entries with a source net of that unit")
    for r in ["total", "Sband", "SWc", "Wstrip", "array", "north"]:
        n = len(cells[r]); tot = area[r] / g / g
        eh, ev = E[(r, "H")], E[(r, "V")]
        ne = eh[0] + ev[0]
        us = " ".join(f"{u} {100.0 * U[(r, u)] / ne:.0f}" for p, u in UNITS if ne and U[(r, u)])
        print(f"{lab} {r:7s} ovf_gcells {n:8d} ({100.0 * n / tot:5.2f} % of {tot:9.0f}) H {eh[0]:8d} / {eh[1]:9d}"
              f"  V {ev[0]:8d} / {ev[1]:9d} | {us}")


if __name__ == "__main__":
    main()
