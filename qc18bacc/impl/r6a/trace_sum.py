#!/usr/bin/env python3
"""impl/r6a (H1): summarise net_trace.tcl output (one R line per root net) by bus class.
    python3 -I trace_sum.py trace_v.txt [--top N]
Class of a root net = its driver (chip IO name / driver hierarchy, digits collapsed) -> its leaf sink groups."""
import re
import sys
from collections import defaultdict

def norm(s):
    return re.sub(r"\d+", "N", s)

def cls(net, drv, dm, groups):
    g = set(groups.split(",")) if groups else set()
    if drv == "PORT":
        return "host:" + re.sub(r"\[.*", "", net)
    p = drv.split("/")
    d = "/".join(p[:-1]) if len(p) > 1 else "chip"
    d = norm(re.sub(r"_reg.*", "", d))
    if "BLK" in g and len(g) == 1:
        sk = "BLK"
    else:
        sk = ",".join(sorted(norm(x) for x in g))
    return f"{d} -> {sk}"

def main():
    rows = defaultdict(lambda: [0, 0, 0, 0.0, 0, 0])   # roots, bufs, rsz bufs, buf area, long>1mm, long>2mm
    tot = [0, 0, 0, 0.0, 0, 0]
    for ln in open(sys.argv[1]):
        if not ln.startswith("R "):
            continue
        f = ln.split()
        net, drv, dm, nl, nb, nr, ba, hp = f[1], f[2], f[3], int(f[4]), int(f[5]), int(f[6]), float(f[7]), float(f[8])
        groups = f[9] if len(f) > 9 else ""
        k = cls(net, drv, dm, groups)
        v = [1, nb, nr, ba, int(hp > 1000), int(hp > 2000)]
        for i in range(6):
            rows[k][i] += v[i]
            tot[i] += v[i]
    top = int(sys.argv[3]) if len(sys.argv) > 3 else 40
    print(f"TOTAL roots(listed) {tot[0]} buf/inv {tot[1]} rsz-inserted {tot[2]} area_mm2 {tot[3] / 1e6:.3f} "
          f"long>1mm {tot[4]} long>2mm {tot[5]}")
    print(f"{'class (driver -> leaf groups)':90s} {'roots':>7s} {'bufs':>7s} {'rsz':>7s} {'%rsz':>6s} {'mm2':>6s} {'>1mm':>6s} {'%>1mm':>6s} {'>2mm':>6s}")
    for k, v in sorted(rows.items(), key=lambda kv: -kv[1][2])[:top]:
        print(f"{k[:90]:90s} {v[0]:7d} {v[1]:7d} {v[2]:7d} {100 * v[2] / tot[2]:6.1f} {v[3] / 1e6:6.3f} {v[4]:6d} "
              f"{100 * v[4] / max(tot[4], 1):6.1f} {v[5]:6d}")
    if "--long" in sys.argv:
        print("by long nets:")
        for k, v in sorted(rows.items(), key=lambda kv: -kv[1][4])[:top]:
            print(f"{k[:90]:90s} {v[0]:7d} {v[4]:6d} {100 * v[4] / max(tot[4], 1):6.1f}")

if __name__ == "__main__":
    main()
