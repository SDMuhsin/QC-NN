#!/usr/bin/env python3
"""R30: DR markers per 50-um bin vs std density / pins (dens30.tcl R30_DUMP file).
    python3 -I bins30.py <bins.txt> <drc.rpt>"""
import collections
import re
import sys

B = 50.0
bins = {}
for ln in open(sys.argv[1]):
    k, cap, use, pins = ln.split()
    i, j = map(int, k.split(','))
    bins[(i, j)] = (float(cap), float(use), int(pins))
mk = collections.Counter(); mt = collections.defaultdict(collections.Counter)
typ = None
for ln in open(sys.argv[2]):
    s = ln.strip()
    if s.startswith('violation type:'):
        typ = s.split(':', 1)[1].strip()
    elif s.startswith('bbox'):
        v = list(map(float, re.findall(r'-?\d+\.?\d*', s)[:4])); lay = s.split()[-1]
        k = (int(v[0] // B), int(v[1] // B))
        mk[k] += 1; mt[k][typ + ' ' + lay] += 1
cls = [(0, .3), (.3, .4), (.4, .5), (.5, .6), (.6, .7), (.7, .8), (.8, 2)]
print('R30BIN class bins pins markers per1kpins top_types')
tot = sum(mk.values()); inb = 0
for lo, hi in cls:
    nb = np_ = nm = 0; tt = collections.Counter()
    for k, (cap, use, pins) in bins.items():
        if cap < 0.5 * B * B: continue
        d = use / cap
        if lo <= d < hi:
            nb += 1; np_ += pins; nm += mk.get(k, 0); tt.update(mt.get(k, {}))
    inb += nm
    print('R30BIN %.1f-%.1f %5d %8d %7d %7.1f %s' % (lo, hi, nb, np_, nm, 1000.0 * nm / max(np_, 1),
          ' '.join('%s:%d' % x for x in tt.most_common(4))))
print('R30BIN markers in bins >=50%% free: %d of %d' % (inb, tot))
