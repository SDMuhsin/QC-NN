#!/usr/bin/env python3
# R29: routed length per layer, pin positions and driver->sink distances of named nets from a run's out/<top>.def.
#   python3 -I net29.py <def> <net> [<net> ...]     (instance positions = placement origin, um)
import sys, re, collections
U = 2000.0; want = set(sys.argv[2:]); comp = {}; recs = {}; sec = None; buf = None
LAY = ['M%d' % i for i in range(1, 10)]
for ln in open(sys.argv[1]):
    if ln.startswith('COMPONENTS'): sec = 'C'; continue
    if ln.startswith('END COMPONENTS'): sec = None; continue
    if ln.startswith('NETS'): sec = 'N'; continue
    if ln.startswith('END NETS'): break
    if sec == 'C':
        m = re.match(r'\s*- (\S+) (\S+) .*\( (-?\d+) (-?\d+) \)', ln)
        if m: comp[m.group(1)] = (m.group(2), int(m.group(3)) / U, int(m.group(4)) / U)
    elif sec == 'N':
        m = re.match(r'\s*- (\S+)', ln)
        if m: buf = m.group(1) if m.group(1) in want else None
        if buf: recs[buf] = recs.get(buf, '') + ln
for n, rec in recs.items():
    L = collections.Counter()
    for part in re.split(r'\+ ROUTED|NEW', rec)[1:]:
        tk = part.replace('(', ' ( ').replace(')', ' ) ').split()
        if not tk or tk[0] not in LAY: continue
        pts = []; i = 1
        while i < len(tk):
            if tk[i] == 'RECT': break
            if tk[i] == '(':
                j = tk.index(')', i); v = tk[i+1:j]
                x = pts[-1][0] if v[0] == '*' else float(v[0]); y = pts[-1][1] if v[1] == '*' else float(v[1])
                pts.append((x, y)); i = j + 1
            else: i += 1
        for a, b in zip(pts, pts[1:]): L[tk[0]] += (abs(a[0]-b[0]) + abs(a[1]-b[1])) / U
    ps = re.findall(r'\( (\S+) (\S+) \)', rec.split('+')[0])
    print('NET', n, 'routed_um %.0f' % sum(L.values()), ' '.join('%s:%.0f' % (k, L[k]) for k in LAY if L[k]))
    for i, p in ps:
        c = comp.get(i, ('PIN', 0, 0)); print('   %-12s %-8s %8.1f %8.1f %s' % (c[0][:12], p, c[1], c[2], i[-40:]))
