#!/usr/bin/env python3
"""R14: summary of impl/r14/probe_drv.tcl's drv_nets.txt: DRV-violating nets by terminal class (block masters on the
net / top std / chip io), check kind, driver, HPWL; and whether the net's bbox overlaps a hard block footprint.
    python3 -I drv_sum.py <drv_nets.txt> [mplace.tcl]"""
import re
import sys
from collections import Counter, defaultdict

f = sys.argv[1]
boxes = []
if len(sys.argv) > 2:
    t = open(sys.argv[2]).read()
    m = re.search(r"P\(MACRO_PLACE\) \{(.*?)\n\}", t, re.S)
    # block footprints only (qb_hub / col / act) are recognisable by instance names
    for n, x, y, o in re.findall(r"\{(\S+) ([\d.]+) ([\d.]+) (\S+)\}", m.group(1)):
        boxes.append((n, float(x), float(y)))
cls = Counter(); hp = defaultdict(float); drv = Counter(); ex = {}
for ln in open(f):
    p = ln.split()
    if p[0] != "net":
        continue
    kind, pin, net, nt, nb, ms, h = p[1], p[2], p[3], int(p[4]), int(p[5]), p[6], float(p[7])
    dm, dp = p[12], p[13]
    ms_s = set(ms.split(","))
    blk = sorted(x for x in ms_s if x.startswith("qb_") and x not in ("qb_w_204x144m2", "qb_d_624x80m8"))
    hasstd = "std" in ms_s
    if nt == nb and not hasstd and "io" not in ms_s:
        c = "block-only (" + "+".join(blk) + ")"
    elif blk:
        c = "block+top (" + "+".join(blk) + ")"
    else:
        c = "top-only"
    hb = "hpwl<50" if h < 50 else ("50-500" if h < 500 else ("500-1500" if h < 1500 else ">1500"))
    k = (c, kind, hb)
    cls[k] += 1; hp[k] += h
    drv[(c, dm, re.sub(r"\[\d+\]$", "", dp))] += 1
    ex.setdefault(k, net)
print("%-58s %-7s %-9s %7s %10s  example" % ("class", "check", "hpwl", "nets", "sum_hpwl_mm"))
for k, v in sorted(cls.items(), key=lambda z: -z[1]):
    print("%-58s %-7s %-9s %7d %10.1f  %s" % (k[0], k[1], k[2], v, hp[k] / 1000, ex[k][:60]))
print("\ntop drivers (class, driver master, pin):")
for k, v in drv.most_common(25):
    print("  %6d  %s" % (v, " ".join(k)))
