#!/usr/bin/env python3
"""R22: placed std-cell area per floorplan y band (mplace.tcl ::QB15_BANDS + the gaps between them), all cells and the
prm cells (instance name contains u_prm; macros qb_* excluded), west strip (x < 860) / columns (x >= 860) split
(cell origin decides the band).  Input: impl/r12/q1dump.tcl dump (M <master> <area> /
I <name> <master> <x> <y>), e.g. <run>/bud_pl/dump_db.txt.
    python3 -I yband22.py <dump_db.txt> <mplace.tcl>"""
import re
import sys
import collections as C

dump, mp = sys.argv[1], sys.argv[2]
t = open(mp).read()
W, H = map(float, re.search(r'DIE_AREA\) \{0 0 ([\d.]+) ([\d.]+)\}', t).groups())
b = re.search(r'set ::QB15_BANDS \{(.*)\}', t).group(1).split()
bands = sorted([(float(b[i + 1]), float(b[i + 2]), b[i]) for i in range(0, len(b), 3)])
regs, y = [], 0.0
for y0, y1, n in bands:
    if y0 - y > 1: regs.append((y, y0, 'gap'))
    regs.append((y0, y1, n)); y = y1
if H - y > 1: regs.append((y, H, 'gap'))
area, A, P = {}, C.Counter(), C.Counter()
for ln in open(dump):
    f = ln.split()
    if f[0] == 'M': area[f[1]] = float(f[2]); continue
    if f[0] != 'I' or f[2] not in area or f[2].startswith('qb_'): continue      # std cells only
    x, yy = float(f[3]), float(f[4])
    k = next((i for i, r in enumerate(regs) if r[0] <= yy < r[1]), len(regs) - 1)
    s = 'W' if x < 860 else 'C'
    A[(k, s)] += area[f[2]]
    if 'u_prm' in f[1]: P[(k, s)] += area[f[2]]
print('# yband22 %s: std area per y band (mm2): all / prm, west strip | columns' % dump)
for k, (y0, y1, n) in enumerate(regs):
    a = A[(k, 'W')] + A[(k, 'C')]; p = P[(k, 'W')] + P[(k, 'C')]
    print('YB %-9s y %7.1f-%7.1f (%5.1f um) all %.3f (W %.3f C %.3f) prm %.3f (W %.3f C %.3f)' % (
        n, y0, y1, y1 - y0, a / 1e6, A[(k, 'W')] / 1e6, A[(k, 'C')] / 1e6, p / 1e6, P[(k, 'W')] / 1e6, P[(k, 'C')] / 1e6))
print('YB total all %.3f prm %.3f mm2' % (sum(A.values()) / 1e6, sum(P.values()) / 1e6))
