#!/usr/bin/env python3
"""R35: add ANTENNAGATEAREA (inputs on the port net) / ANTENNADIFFAREA (drivers) to the PIN sections of a block LEF, from
blkant.tcl's "port master pin in|out" dump and the std-cell LEF antenna data (first value of each statement).
usage: blkant.py <cells.lef> <dump.txt> <in.lef> <out.lef>"""
import sys
from collections import defaultdict
cl, dump, src, dst = sys.argv[1:5]
G, D = {}, {}
m = p = None
for line in open(cl):
    s = line.split()
    if not s: continue
    if s[0] == 'MACRO': m = s[1]
    elif s[0] == 'PIN': p = s[1]
    elif s[0] == 'ANTENNAGATEAREA' and m and p: G.setdefault((m, p), float(s[1]))
    elif s[0] == 'ANTENNADIFFAREA' and m and p: D.setdefault((m, p), float(s[1]))
A = defaultdict(lambda: [0.0, 0.0])
for l in open(dump):
    port, mst, pin, d = l.split()
    if d == 'in': A[port][0] += G.get((mst, pin), 0.0)
    elif d == 'out': A[port][1] += D.get((mst, pin), 0.0)
n = 0
with open(dst, 'w') as o:
    cur = None
    for line in open(src):
        s = line.split(); o.write(line)
        if s[:1] == ['PIN'] and len(s) > 1: cur = s[1]
        elif cur and s[:1] == ['DIRECTION']:
            g, d = A.get(cur, (0.0, 0.0))
            if g > 0: o.write('    ANTENNAGATEAREA %.4f ;\n' % g)
            if d > 0: o.write('    ANTENNADIFFAREA %.4f ;\n' % d)
            n += (g > 0) or (d > 0); cur = None
print('BLKANT pins annotated', n, 'of', len(A), 'ports; cell pins with gate area', len(G))
