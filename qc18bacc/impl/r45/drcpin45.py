#!/usr/bin/env python3
"""R45 probe: which cell pin (and M1 pin-rect width) is under each Calibre marker of a rule.
usage: drcpin45.py DRC_RES.db rule_regex design.def cell.lef [extra.lef ...]
Prints counts per (master, pin) and per pin-rect min-width bucket, and the share of markers on no cell pin."""
import sys, re, collections
db, rx, deff, lefs = sys.argv[1], re.compile(sys.argv[2]), sys.argv[3], sys.argv[4:]
# --- markers (centres, um)
L = open(db).read().split('\n'); prec = float(L[0].split()[1]); i = 1; mk = []
while i < len(L):
    name = L[i].strip(); i += 1
    if not name: continue
    hdr = L[i].split(); i += 1; ncur = int(hdr[0]); i += int(hdr[2])
    for _ in range(ncur):
        t = L[i].split(); i += 1; pts = []
        n = int(t[2])
        for _ in range(n):
            xy = list(map(int, L[i].split())); i += 1
            pts += [(xy[0], xy[1])] + ([(xy[2], xy[3])] if len(xy) == 4 else [])
        while i < len(L) and L[i][:2] in ('CN', 'P '): i += 1
        if rx.search(name):
            xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
            mk.append((name, (min(xs) + max(xs)) / 2 / prec, (min(ys) + max(ys)) / 2 / prec))
# --- LEF macros: size + M1 pin rects
mac = {}
for lf in lefs:
    cur = pin = lay = None
    for line in open(lf):
        t = line.split()
        if not t: continue
        if t[0] == 'MACRO': cur = t[1]; mac[cur] = {'size': (0, 0), 'pins': []}; pin = None
        elif cur and t[0] == 'SIZE': mac[cur]['size'] = (float(t[1]), float(t[3]))
        elif cur and t[0] == 'PIN': pin = t[1]
        elif cur and t[0] == 'OBS': pin = '_OBS'
        elif cur and t[0] == 'LAYER': lay = t[1]
        elif cur and t[0] == 'RECT' and pin and lay == 'M1':
            x0, y0, x1, y1 = map(float, t[1:5]); mac[cur]['pins'].append((pin, x0, y0, x1, y1))
        elif cur and t[0] == 'END' and len(t) > 1 and t[1] == cur: cur = None
# --- DEF components
units = 1000; comps = []
inc = False
txt = open(deff).read()
units = int(re.search(r'UNITS DISTANCE MICRONS (\d+)', txt).group(1))
sec = txt[txt.index('\nCOMPONENTS'):txt.index('END COMPONENTS')]
for m in re.finditer(r'-\s+(\S+)\s+(\S+)\s+.*?\+\s+(?:PLACED|FIXED)\s+\(\s*(-?\d+)\s+(-?\d+)\s*\)\s+(\S+)', sec):
    inst, master, x, y, o = m.group(1), m.group(2), int(m.group(3)) / units, int(m.group(4)) / units, m.group(5)
    if master in mac: comps.append((x, y, o, master, inst))
# grid index
G = 5.0; grid = collections.defaultdict(list)
for c in comps:
    w, h = mac[c[3]]['size']
    if c[2] in ('E', 'W', 'FE', 'FW'): w, h = h, w
    for gx in range(int(c[0] // G), int((c[0] + w) // G) + 1):
        for gy in range(int(c[1] // G), int((c[1] + h) // G) + 1):
            grid[(gx, gy)].append(c)
def xf(c, r):
    x, y, o, master = c[0], c[1], c[2], c[3]; w, h = mac[master]['size']; _, a, b, cc, d = r
    if o == 'N':  return (x + a, y + b, x + cc, y + d)
    if o == 'FS': return (x + a, y + h - d, x + cc, y + h - b)
    if o == 'S':  return (x + w - cc, y + h - d, x + w - a, y + h - b)
    if o == 'FN': return (x + w - cc, y + b, x + w - a, y + d)
    return None
perinst = collections.Counter(); cnt = collections.Counter(); wid = collections.Counter(); nopin = 0; ex = {}
for name, mx, my in mk:
    hit = None
    for c in grid[(int(mx // G), int(my // G))]:
        for r in mac[c[3]]['pins']:
            q = xf(c, r)
            if q and q[0] - 1e-3 <= mx <= q[2] + 1e-3 and q[1] - 1e-3 <= my <= q[3] + 1e-3:
                hit = (c, r, q); break
        if hit: break
    if not hit: nopin += 1; continue
    c, r, q = hit
    cnt[(c[3], r[0])] += 1
    perinst[(c[3], c[4])] += 1
    wid[round(min(q[2] - q[0], q[3] - q[1]), 3)] += 1
    ex.setdefault((c[3], r[0]), (c[4], mx, my, q))
print('markers', len(mk), 'on no M1 cell shape', nopin)
print('pin-rect min width (um):', sorted(wid.items(), key=lambda z: -z[1])[:10])
for k, v in cnt.most_common(25): print(' ', v, k, ex[k])
nin = collections.Counter(c[3] for c in comps)
pi = collections.defaultdict(list)
for (m, inst), v in perinst.items(): pi[m].append(v)
for m in [k[0] for k, _ in cnt.most_common(8)]:
    v = sorted(pi[m]); print('  %s: instances %d, with markers %d, markers/inst median %d max %d' % (m, nin[m], len(v), v[len(v)//2], v[-1]))
