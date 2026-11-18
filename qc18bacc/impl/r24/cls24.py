#!/usr/bin/env python3
"""R24: aggregate qb24_cls class files (start>end n worst w mean m) into in / reg / macro x reg / macro / out / icg."""
import sys
for fn in sys.argv[1:]:
    agg = {}
    for l in open(fn):
        t = l.split(); s, e = t[0].split(">", 1); n, w, m = int(t[1]), float(t[3]), float(t[5])
        sc = "in_g_hpn" if s.startswith("p:g_hpn") else "in" if s.startswith("p:") else "reg" if s.startswith("reg") else "icg" if s.startswith("icg") else "mac"
        ec = "reg" if e.startswith("reg") else "out" if e.startswith("p:") else "icg" if e.startswith("icg") else "mac"
        a = agg.setdefault(f"{sc}>{ec}", [0, 0.0, 0.0]); a[0] += n; a[1] = min(a[1], w); a[2] += n * m
    tot = sum(a[0] for a in agg.values())
    print(f"{fn.split('/')[-1]}: total {tot} " + "; ".join(f"{k} {a[0]} w {a[1]:.3f} m {a[2]/a[0]:.3f}" for k, a in sorted(agg.items(), key=lambda x: -x[1][0])[:7]))
