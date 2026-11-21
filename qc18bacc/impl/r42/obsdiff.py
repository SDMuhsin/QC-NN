#!/usr/bin/env python3
"""R42: wire segments (defwires.py) overlapping OBS of a NEW block LEF .geo but not of the OLD one (new shorts from a view
swap).  python3 -I obsdiff.py <wires.txt> <old.geo> <new.geo>"""
import sys
from collections import defaultdict, Counter
G = 20.0
def load(g):
    d = defaultdict(list)
    for ln in open(g):
        t = ln.split()
        if t[0] != 'O': continue
        r = tuple(map(float, t[3:7]))
        for gx in range(int(r[0] // G), int(r[2] // G) + 1):
            for gy in range(int(r[1] // G), int(r[3] // G) + 1): d[(t[2], gx, gy)].append(r)
    return d
def hit(d, l, x1, y1, x2, y2):
    for gx in range(int(x1 // G), int(x2 // G) + 1):
        for gy in range(int(y1 // G), int(y2 // G) + 1):
            for r in d.get((l, gx, gy), ()):
                if r[0] < x2 and x1 < r[2] and r[1] < y2 and y1 < r[3]: return r
    return None
old, new = load(sys.argv[2]), load(sys.argv[3])
c = Counter(); ex = []
for ln in open(sys.argv[1]):
    t = ln.split(); l = t[0]; x1, y1, x2, y2 = map(float, t[1:5])
    r = hit(new, l, x1, y1, x2, y2)
    if r and not hit(old, l, x1, y1, x2, y2):
        c[(l, int(x1 // 200) * 200, int(y1 // 200) * 200)] += 1
        if len(ex) < 12: ex.append((ln.strip(), r))
print('OBSDIFF new-only overlaps', sum(c.values()), 'by layer/200um bin', c.most_common(12))
for e in ex: print('OBSDIFF_EX', e)
