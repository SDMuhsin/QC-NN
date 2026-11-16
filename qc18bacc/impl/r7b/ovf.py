#!/usr/bin/env python3
"""impl/r7b (results/r7b.md): GRT overflow per floorplan region from a global_route -congestion_report_file.
    python3 -I ovf.py <gr_congestion.rpt> [label]
Per region and direction (H / V violation type): overflowed gcell entries, sum overflow (tracks), and the share of
the entries whose source nets include each top-level unit (net-name prefix, as impl/r7a classify's hierarchy).
Regions (um, the R6c / R7b array at x 860-3980, y 1700.6-4810.6): r7a windows south / west (impl/r7a/classify.py WIN),
and a partition: SWc (x < 860, y < 1700.6), Sband (x >= 860, y < 1700.6), Wstrip (x < 860, 1700.6 <= y < 4810.6),
array (x >= 860, 1700.6 <= y < 4810.6), north (y >= 4810.6)."""
import re
import sys
from collections import defaultdict

WIN = {"r7a_south": (1000.0, 1000.0, 3500.0, 2000.0), "r7a_west": (0.0, 2000.0, 1000.0, 4500.0)}
XA, YA, YT = 860.0, 1700.6, 4810.6
UNITS = [("u_top/u_act/", "act"), ("g_rt_u_seq/", "seq"), ("u_prm/", "prm"), ("u_head/", "head"),
         ("u_top/g_dist_", "dist"), ("clknet", "clock")]


def part(x, y):
    if y >= YT:
        return "north"
    if y < YA:
        return "SWc" if x < XA else "Sband"
    return "Wstrip" if x < XA else "array"


def main():
    rpt = sys.argv[1]
    lab = sys.argv[2] if len(sys.argv) > 2 else rpt
    T = defaultdict(lambda: [0, 0])
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
            regs = [part(x, y), "total"] + [w for w, (a, b, c, e) in WIN.items() if a <= x < c and b <= y < e]
            us = {u for p, u in UNITS for n in srcs if p in n}
            for r in regs:
                T[(r, d)][0] += 1
                T[(r, d)][1] += cu[2]
                for u in us:
                    U[(r, d, u)] += 1
    print(f"# GRT overflow by region [S] {lab}: entries (overflowed gcell x layer-direction), sum overflow (tracks);"
          f" unit = % of entries with a source net of that unit")
    for r in ["total", "Sband", "SWc", "Wstrip", "array", "north", "r7a_south", "r7a_west"]:
        for dd in "HV":
            n, o = T[(r, dd)]
            us = " ".join(f"{u} {100.0 * U[(r, dd, u)] / n:.0f}" for p, u in UNITS if n and U[(r, dd, u)])
            print(f"{lab} {r:9s} {dd} entries {n:8d} overflow {o:9d} | {us}")


if __name__ == "__main__":
    main()
