#!/usr/bin/env python3
"""R45 probe: Calibre ASCII DRC results db -> per rule, marker-centre histogram of (y mod row) and (x mod pitch).
usage: drcpos45.py DRC_RES.db [row_um=1.8] [xpitch_um=20] [rule_regex]"""
import sys, re, collections
db = sys.argv[1]; row = float(sys.argv[2]) if len(sys.argv) > 2 else 1.8
xp = float(sys.argv[3]) if len(sys.argv) > 3 else 20.0
rx = re.compile(sys.argv[4]) if len(sys.argv) > 4 else None
L = open(db).read().split('\n')
prec = float(L[0].split()[1]); i = 1
out = collections.defaultdict(list)
while i < len(L):
    name = L[i].strip(); i += 1
    if not name: continue
    hdr = L[i].split(); i += 1
    ncur = int(hdr[0]); i += int(L[i].split()[0]) + 1 if False else 0
    # skip header text lines: next line "<n_lines>" ... Calibre: "<cur> <orig> <nlines> <date>"
    nl = int(hdr[2]); i += nl
    for _ in range(ncur):
        t = L[i].split(); i += 1
        pts = []
        if t[0] == 'e':
            for _ in range(int(t[2])):
                xy = L[i].split(); i += 1; pts += [(int(xy[0]), int(xy[1])), (int(xy[2]), int(xy[3]))]
        elif t[0] == 'p':
            for _ in range(int(t[2])):
                xy = L[i].split(); i += 1; pts.append((int(xy[0]), int(xy[1])))
        while i < len(L) and L[i][:2] in ('CN', 'P '):
            i += 1
        xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
        out[name].append(((min(xs) + max(xs)) / 2 / prec, (min(ys) + max(ys)) / 2 / prec, (max(xs) - min(xs)) / prec, (max(ys) - min(ys)) / prec))
for name, m in out.items():
    if rx and not rx.search(name): continue
    hy = collections.Counter(round((c[1] % row), 2) for c in m)
    hx = collections.Counter(round((c[0] % xp), 1) for c in m)
    sz = collections.Counter((round(c[2], 3), round(c[3], 3)) for c in m)
    print(name, len(m))
    print('  y mod %.2f top:' % row, hy.most_common(8))
    print('  x mod %.1f top:' % xp, hx.most_common(8))
    print('  size top:', sz.most_common(6))
