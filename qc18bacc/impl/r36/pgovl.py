#!/usr/bin/env python3
"""R36 (results/r36.md): overlap of the top's PDN shapes (impl/r36/pgdump.tcl -> rpt/r36_pg.txt) with block LEF
geometry on the same layer.  For each hard-block master given as <master>=<lef>, every top special shape on a layer in
LAYERS (default M7,M8,M9,VIA7,VIA8) that overlaps the block's bbox is tested against that LEF's OBS rects and PIN rects
(transformed by the instance orientation).  Reports per master / layer: top shapes over the block, shapes that overlap
OBS (= block-internal metal that a top PG shape would short), shapes that overlap a PIN of another net (signal pins,
or VDD on VSS), and shapes that touch a same-net PG pin (the intended connections).
usage: pgovl.py <r36_pg.txt> <master>=<lef> [...] [--layers M7,M8,M9,VIA7,VIA8] [--examples N]"""
import sys, collections
args = [a for a in sys.argv[1:]]
layers = 'M7,M8,M9,VIA7,VIA8'.split(','); nex = 5
if '--layers' in args: i = args.index('--layers'); layers = args[i + 1].split(','); del args[i:i + 2]
if '--examples' in args: i = args.index('--examples'); nex = int(args[i + 1]); del args[i:i + 2]
pg, specs = args[0], dict(a.split('=', 1) for a in args[1:])
LS = set(layers); G = 20.0

def read_lef(path, macro):
    """OBS / PIN rects on LS of MACRO macro: returns (size, obs[layer] list, pins[layer] list of (rect, pin, use))."""
    obs = collections.defaultdict(list); pins = collections.defaultdict(list); size = None
    inm = False; mode = None; layer = None; pin = None; use = 'SIGNAL'
    with open(path) as f:
        for line in f:
            s = line.split()
            if not s: continue
            if s[0] == 'MACRO': inm = (s[1] == macro); continue
            if not inm: continue
            k = s[0]
            if k == 'SIZE': size = (float(s[1]), float(s[3]))
            elif k == 'PIN': mode = 'PIN'; pin = s[1]; use = 'SIGNAL'
            elif k == 'USE' and mode == 'PIN': use = s[1].rstrip(';')
            elif k == 'OBS': mode = 'OBS'
            elif k == 'LAYER': layer = s[1]
            elif k == 'RECT' and layer in LS:
                r = tuple(map(float, s[1:5]))
                if mode == 'OBS': obs[layer].append(r)
                elif mode == 'PIN': pins[layer].append((r, pin, use))
            elif k == 'END' and len(s) > 1 and s[1] == macro: break
            elif k == 'END' and mode == 'PIN' and len(s) > 1 and s[1] == pin: mode = None
    return size, obs, pins

def xf(r, orient, w, h):
    x0, y0, x1, y1 = r
    if orient in ('R0', 'N'): return r
    if orient in ('MY', 'FN'): return (w - x1, y0, w - x0, y1)
    if orient in ('MX', 'FS'): return (x0, h - y1, x1, h - y0)
    if orient in ('R180', 'S'): return (w - x1, h - y1, w - x0, h - y0)
    raise SystemExit('orientation %s not handled' % orient)

def index(rects):
    g = collections.defaultdict(list)
    for j, it in enumerate(rects):
        r = it[0] if isinstance(it[0], tuple) else it
        for gx in range(int(r[0] // G), int(r[2] // G) + 1):
            for gy in range(int(r[1] // G), int(r[3] // G) + 1): g[(gx, gy)].append(j)
    return g

def ov(a, b): return a[0] < b[2] and b[0] < a[2] and a[1] < b[3] and b[1] < a[3]

inst, shapes = [], collections.defaultdict(list)
with open(pg) as f:
    for line in f:
        s = line.split()
        if s[0] == 'S' and s[2] in LS: shapes[s[2]].append((s[1], tuple(map(float, s[3:7]))))
        elif s[0] == 'I': inst.append((s[1], s[2], s[3], float(s[4]), float(s[5]), tuple(map(float, s[6:10]))))
for m, lef in specs.items():
    size, obs, pins = read_lef(lef, m)
    if size is None: print('PGOVL %s: macro not found in %s' % (m, lef)); continue
    w, h = size
    idx_o = {l: index(obs[l]) for l in obs}; idx_p = {l: index(pins[l]) for l in pins}
    tot = collections.Counter(); bad_o = collections.Counter(); bad_p = collections.Counter(); bad_x = collections.Counter(); good = collections.Counter(); ex = []
    for (iname, master, orient, lx, ly, bb) in inst:
        if master != m: continue
        for l in layers:
            for net, r in shapes.get(l, ()):
                if not ov(r, bb): continue
                tot[l] += 1
                # top shape in block coordinates (inverse of the orientation transform = same for these 4 orientations)
                rb = (r[0] - bb[0], r[1] - bb[1], r[2] - bb[0], r[3] - bb[1])
                rb = xf(rb, orient, w, h)
                cand = set()
                for gx in range(int(rb[0] // G), int(rb[2] // G) + 1):
                    for gy in range(int(rb[1] // G), int(rb[3] // G) + 1): cand.update(idx_o.get(l, {}).get((gx, gy), ()))
                cp = set()
                for gx in range(int(rb[0] // G), int(rb[2] // G) + 1):
                    for gy in range(int(rb[1] // G), int(rb[3] // G) + 1): cp.update(idx_p.get(l, {}).get((gx, gy), ()))
                hit = [pins[l][j] for j in cp if ov(rb, pins[l][j][0])]
                inside = any(p[1] == net and p[0][0] <= rb[0] + 1e-4 and p[0][1] <= rb[1] + 1e-4 and p[0][2] >= rb[2] - 1e-4 and p[0][3] >= rb[3] - 1e-4 for p in hit)
                if any(ov(rb, obs[l][j]) for j in cand):
                    bad_o[l] += 1
                    if not inside:
                        bad_x[l] += 1
                        if len(ex) < nex: ex.append('%s %s %s %s top %s' % (iname, l, net, 'OBS-not-on-own-pin', ' '.join('%.2f' % v for v in r)))
                if any(p[1] != net for p in hit):
                    bad_p[l] += 1
                    if len(ex) < 2 * nex: ex.append('%s %s %s PIN %s top %s' % (iname, l, net, sorted({p[1] for p in hit if p[1] != net})[:3], ' '.join('%.2f' % v for v in r)))
                if any(p[1] == net for p in hit): good[l] += 1
    print('PGOVL master %s lef %s size %.1f x %.1f instances %d' % (m, lef, w, h, sum(1 for i in inst if i[1] == m)))
    for l in layers:
        print('  %-5s block OBS rects %7d pin rects %6d | top shapes over block %6d  overlap OBS %6d (not inside own-net pin: %6d)  overlap other-net pin %5d  touch same-net PG pin %6d'
              % (l, len(obs.get(l, ())), len(pins.get(l, ())), tot[l], bad_o[l], bad_x[l], bad_p[l], good[l]))
    for e in ex: print('  ex', e)
