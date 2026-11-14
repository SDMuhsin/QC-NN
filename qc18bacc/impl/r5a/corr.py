#!/usr/bin/env python3
"""DRC markers vs local cell utilisation (results/r5a.md): corr.py <density.txt> <drt.drc.rpt> [bin_um]
Bins of the density dump (x y util pe_frac) joined with the marker count per bin; prints markers per utilisation
decile and the share of markers in bins above utilisation thresholds."""
import sys, re, collections as C
B = float(sys.argv[3]) if len(sys.argv) > 3 else 50.0
d = {}
for l in open(sys.argv[1]):
    x, y, u, p = map(float, l.split()); d[(x, y)] = (u, p)
mk = C.Counter()
for l in open(sys.argv[2]):
    m = re.search(r'bbox = \(\s*([-\d.]+),\s*([-\d.]+)', l)
    if m: mk[(int(float(m.group(1)) // B) * B, int(float(m.group(2)) // B) * B)] += 1
tot = sum(mk.values()); edge = sum(c for (x, y), c in mk.items() if y < B)
print('markers %d, south-edge bin row %d' % (tot, edge))
rows = sorted(((u, p, mk.get(k, 0)) for k, (u, p) in d.items() if k[1] >= B), key=lambda r: r[0])
n = len(rows)
for q in range(5):
    s = rows[q * n // 5:(q + 1) * n // 5]
    print('util quintile %d: util %.2f-%.2f pe_frac %.2f markers %d (%.1f per bin)' % (q, s[0][0], s[-1][0],
          sum(r[1] for r in s) / len(s), sum(r[2] for r in s), sum(r[2] for r in s) / len(s)))
