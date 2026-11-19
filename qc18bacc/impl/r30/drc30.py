#!/usr/bin/env python3
"""R30: classify a DRT marker report (-output_drc / -drc_report_iter_step) by type, layer and source kinds.
    python3 -I drc30.py <drc.rpt> [<n examples>]"""
import collections
import re
import sys

src = sys.argv[1]; nex = int(sys.argv[2]) if len(sys.argv) > 2 else 0
tl = collections.Counter(); kinds = collections.Counter(); ex = collections.defaultdict(list)
raw = collections.Counter()
typ = srcs = None
def kind(tok):
    return tok
for ln in open(src):
    s = ln.strip()
    if s.startswith('violation type:'):
        typ = s.split(':', 1)[1].strip(); srcs = ''
    elif s.startswith('srcs:'):
        srcs = s[5:].strip()
    elif s.startswith('bbox') and typ is not None:
        lay = s.rsplit(' ', 1)[-1]
        tl[(typ, lay)] += 1
        toks = srcs.split()
        cls = []
        i = 0
        while i < len(toks):
            t = toks[i]
            if ':' in t:
                k, v = t.split(':', 1)
            elif i + 1 < len(toks):
                k, v = t, toks[i + 1]; i += 1
            else:
                k, v = t, ''
            i += 1
            if k == 'net' and v in ('VDD', 'VSS'):
                cls.append('PG')
            elif k == 'net':
                cls.append('net')
            else:
                cls.append(k)
        c = (typ, lay, ' + '.join(sorted(cls)))
        kinds[c] += 1
        if len(ex[c]) < nex:
            ex[c].append(srcs + ' | ' + s)
        if len(raw) < 5:
            raw[srcs] += 1
        typ = None
tot = sum(tl.values())
print('R30D total', tot)
for k, v in tl.most_common(15):
    print('R30D %-16s %-5s %7d %5.1f %%' % (k[0], k[1], v, 100.0 * v / tot))
print('R30D -- by sources')
for k, v in kinds.most_common(25):
    print('R30D %-16s %-5s %-30s %7d %5.1f %%' % (k[0], k[1], k[2], v, 100.0 * v / tot))
    for e in ex[k]:
        print('R30D    ex', e[:220])
